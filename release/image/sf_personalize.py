#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Make the two boot files of one machine from the release's generic boot files.

    sf_personalize.py BOOTDIR --partuuid P --part-lba N --part-blocks N -o OUTDIR

BOOTDIR is the release's boot directory (boot.json, boot.bin, kernel.kc, bootargs.template,
pdsf_pack.py). OUTDIR receives boot.bin and kernel.bin, the files sf/boot.bin and
sf/kernel.bin of the boot partition, and personal.json (their sizes and sha256; it names no
identifier). They are a pair: install both or neither.

  boot.bin   stage 2 as the release built it, for the release's root filesystem UUID
             (boot.json root_uuid, release/identity.nix): copied unchanged. The root image
             of the same release carries that UUID; the installer must not change it.
  kernel.bin the configuration record (the command line of bootargs.template with the
             release's root UUID and the target partition's identifier, first block and
             length filled in) and the kernel collection, packed by the release's own
             pdsf_pack.py with the options boot.json records.

Every input is checked against boot.json first; a mismatch stops before anything is written.
Standard library only, so it runs on the Linux of the target machine and on macOS.
"""
import argparse, hashlib, json, os, re, subprocess, sys

UUID = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')

def sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()

def die(msg):
    sys.exit('sf_personalize: ' + msg)

def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[1])
    ap.add_argument('bootdir')
    ap.add_argument('--partuuid', required=True, help='partition UUID of the SiliconForest root (lower case)')
    ap.add_argument('--part-lba', required=True, type=int, help='first 4096-byte block of the root partition')
    ap.add_argument('--part-blocks', required=True, type=int, help='length of the root partition in 4096-byte blocks')
    ap.add_argument('-o', '--out', required=True)
    a = ap.parse_args()
    if not UUID.match(a.partuuid):
        die('--partuuid: expected a lower-case UUID')
    if a.part_lba <= 0 or a.part_blocks <= 0:
        die('partition offset and length must be positive')
    meta = json.load(open(os.path.join(a.bootdir, 'boot.json')))
    for name, want in meta['files'].items():
        got = sha(os.path.join(a.bootdir, name))
        if got != want['sha256']:
            die('%s: sha256 %s, boot.json says %s' % (name, got, want['sha256']))
    fsuuid = meta['root_uuid']
    if not UUID.match(fsuuid):
        die('boot.json: root_uuid is not a lower-case UUID')
    stage2 = open(os.path.join(a.bootdir, 'boot.bin'), 'rb').read()
    if stage2.count(fsuuid.encode()) != 1:
        die('boot.bin carries the release root UUID %d times, not once' % stage2.count(fsuuid.encode()))
    lines = [l.strip() for l in open(os.path.join(a.bootdir, 'bootargs.template')) if l.strip() and not l.startswith('#')]
    args = ' '.join(lines)
    fields = {'@SF_FSUUID@': fsuuid, '@SF_PARTUUID@': a.partuuid,
              '@SF_PART_LBA@': str(a.part_lba), '@SF_PART_BLOCKS@': str(a.part_blocks)}
    for k, v in fields.items():
        if args.count(k) != 1:
            die('bootargs.template: %s occurs %d times' % (k, args.count(k)))
        args = args.replace(k, v)
    if '@' in args:
        die('bootargs.template: an unfilled field remains')
    if args.split().count('boot-uuid=' + fsuuid) != 1 or args.split().count('rd=uuid') != 1:
        die('the command line does not name exactly one disk root')
    os.makedirs(a.out, exist_ok=True)
    boot_bin, kernel_bin = os.path.join(a.out, 'boot.bin'), os.path.join(a.out, 'kernel.bin')
    with open(boot_bin + '.new', 'wb') as f:
        f.write(stage2)
    cmd = [sys.executable, '-I', '-B', os.path.join(a.bootdir, 'pdsf_pack.py'), 'pack',
           '--kernel', os.path.join(a.bootdir, 'kernel.kc'), '--bootargs', args]
    for kv in meta['pack_set']:
        cmd += ['--set', kv]
    cmd += ['-o', kernel_bin + '.new']
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)
    listing = subprocess.run([sys.executable, '-I', '-B', os.path.join(a.bootdir, 'pdsf_pack.py'), 'list', kernel_bin + '.new'],
                             check=True, capture_output=True, text=True).stdout
    if listing.count('crc ok') != 2 or 'WRONG' in listing:
        die('pdsf_pack.py list: the configuration and the collection must both check: ' + listing)
    packed = open(kernel_bin + '.new', 'rb').read()
    for token in ('boot-uuid=' + fsuuid, 'sfnvme_part=' + a.partuuid + ' '):
        if packed.count(token.encode()) != 1:
            die('the packed configuration does not carry %s exactly once' % token.split('=')[0])
    if os.path.getsize(kernel_bin + '.new') > meta['kernel_bin_max']:
        die('kernel.bin is larger than stage 2 reads')
    os.replace(boot_bin + '.new', boot_bin)
    os.replace(kernel_bin + '.new', kernel_bin)
    out = {'release': meta['release'], 'boot.bin': {'size': os.path.getsize(boot_bin), 'sha256': sha(boot_bin)},
           'kernel.bin': {'size': os.path.getsize(kernel_bin), 'sha256': sha(kernel_bin)},
           'note': 'a pair: install sf/boot.bin and sf/kernel.bin together (linux/sf-bootbin-install.sh)'}
    json.dump(out, open(os.path.join(a.out, 'personal.json'), 'w'), indent=1, sort_keys=True)
    print(json.dumps(out, sort_keys=True))

if __name__ == '__main__':
    main()
