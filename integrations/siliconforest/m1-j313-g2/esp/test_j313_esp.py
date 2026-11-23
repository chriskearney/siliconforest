#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Test j313_esp.py on a loopback FAT image holding a copy of the Air's backed-up ESP.

Needs sudo for losetup and mount. The backup is only read. Nothing here contacts a device.

  test_j313_esp.py --backup <boot-efi copy> --candidate <j313-window-boot.bin> --work <new dir>
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import j313_esp as esp  # noqa: E402

TOOL = str(HERE / 'j313_esp.py')
IMAGE_BYTES = 524288000  # the Air's ESP is about 500 MB
OWN = {esp.TARGET, esp.KEPT, esp.TEMP}


def sudo(*command, **options):
    return subprocess.run(['sudo', '-n', *command], check=True, text=True, capture_output=True, **options).stdout


def tree(root):
    out = {}
    listing = sudo('python3', '-c', (
        'import hashlib,os,sys,json\nr=sys.argv[1];o={}\n'
        'for d,_,fs in os.walk(r):\n for f in fs:\n  p=os.path.join(d,f)\n'
        '  h=hashlib.sha256()\n  s=open(p,"rb")\n'
        '  [h.update(b) for b in iter(lambda:s.read(1<<20),b"")]\n  s.close()\n'
        '  o[os.path.relpath(p,r)]=h.hexdigest()\nprint(json.dumps(o))'), str(root))
    out.update(json.loads(listing))
    return out


class Harness:
    def __init__(self, args):
        self.args = args
        self.work = args.work.resolve()
        self.mount = self.work / 'mnt'
        self.image = self.work / 'esp.img'
        self.device = None
        self.mounted = False
        self.dt = self.work / 'dt'
        self.results = []

    def tool(self, *words, dt=None):
        command = ['sudo', '-n', sys.executable, '-B', '-I', TOOL, words[0], '--esp', str(self.mount),
                   '--loop-test', '--dt-root', str(dt or self.dt), *words[1:]]
        done = subprocess.run(command, capture_output=True, text=True)
        lines = done.stdout.strip().splitlines()
        return done.returncode, json.loads(lines[-1]) if lines else {'stderr': done.stderr}

    def check(self, name, condition, detail=''):
        self.results.append((name, bool(condition)))
        print(('PASS  ' if condition else 'FAIL  ') + name + ('' if condition else f'  {detail}'), flush=True)

    def write_dt(self, directory, compatible=b'apple,j313\0apple,t8103\0apple,arm-platform\0',
                 stage2=esp.ORIGINAL_STAGE2):
        (directory / 'chosen').mkdir(parents=True, exist_ok=True)
        (directory / 'compatible').write_bytes(compatible)
        (directory / 'chosen/asahi,m1n1-stage2-version').write_bytes(stage2.encode() + b'\0')

    def setup(self):
        self.work.mkdir(mode=0o700)
        self.mount.mkdir()
        self.write_dt(self.dt)
        with open(self.image, 'wb') as stream:
            stream.truncate(IMAGE_BYTES)
        subprocess.run(['mkfs.vfat', '-F', '32', '-n', 'G2TEST', str(self.image)], check=True, capture_output=True)
        self.device = sudo('losetup', '--find', '--show', str(self.image)).strip()
        sudo('mount', '-t', 'vfat', '-o', 'rw,uid=0,gid=0,umask=022', self.device, str(self.mount))
        self.mounted = True
        # The backup is the source only; root reads it and writes into the image.
        sudo('cp', '-r', '--no-preserve=all', str(self.args.backup) + '/.', str(self.mount))
        sudo('sync')

    def cleanup(self):
        if self.mounted:
            subprocess.run(['sudo', '-n', 'umount', str(self.mount)], check=False)
            self.mounted = False
        if self.device:
            subprocess.run(['sudo', '-n', 'losetup', '-d', self.device], check=False)
            self.device = None

    def own(self, name):
        return self.mount / name

    def sha(self, name):
        path = self.own(name)
        result = subprocess.run(['sudo', '-n', 'sha256sum', str(path)], capture_output=True, text=True)
        return result.stdout.split()[0] if result.returncode == 0 else None

    def others_unchanged(self, baseline):
        now = tree(self.mount)
        return {k: v for k, v in now.items() if k not in OWN} == {k: v for k, v in baseline.items() if k not in OWN}

    def fsck_clean(self):
        sudo('sync')
        sudo('umount', str(self.mount))
        self.mounted = False
        done = subprocess.run(['sudo', '-n', 'fsck.vfat', '-n', self.device], capture_output=True, text=True)
        sudo('mount', '-t', 'vfat', '-o', 'rw,uid=0,gid=0,umask=022', self.device, str(self.mount))
        self.mounted = True
        return done.returncode == 0

    def execute(self, *words, dt=None):
        return self.tool(*words, '--execute', '--confirm', esp.CONFIRM, dt=dt)

    def scenarios(self):
        candidate = str(self.args.candidate)
        baseline = tree(self.mount)
        self.check('copied ESP holds the original boot.bin', baseline.get(esp.TARGET) == esp.ORIGINAL_SHA)
        print(f'      image holds {len(baseline)} files', flush=True)

        code, out = self.tool('status')
        self.check('status reports the original', code == 0 and out['boot_bin'] == 'original', out)
        code, out = self.tool('install', '--candidate', candidate)
        self.check('install is a dry run by default', code == 0 and out['status'] == 'DRY_RUN_NOTHING_WRITTEN' and
                   len(out['steps']) == 2, out)
        self.check('dry run wrote nothing', tree(self.mount) == baseline)

        code, out = self.tool('install', '--candidate', candidate, '--execute')
        self.check('execute without the confirmation text is refused', code == 2, out)
        code, out = self.tool('install', '--candidate', candidate, '--execute', '--confirm', 'yes')
        self.check('wrong confirmation text is refused', code == 2, out)
        self.check('refused installs wrote nothing', tree(self.mount) == baseline)

        wrong = self.work / 'wrong.bin'
        data = bytearray(Path(candidate).read_bytes())
        data[0x1000] ^= 1
        wrong.write_bytes(data)
        code, out = self.execute('install', '--candidate', str(wrong))
        self.check('a modified candidate is refused', code == 2 and 'reviewed' in out.get('reason', ''), out)

        board = self.work / 'dt-j293'
        self.write_dt(board, compatible=b'apple,j293\0apple,t8103\0apple,arm-platform\0')
        code, out = self.execute('install', '--candidate', candidate, dt=board)
        self.check('another board is refused', code == 2 and 'J313' in out.get('reason', ''), out)

        saved = self.work / 'saved-target.bin'
        sudo('cp', str(self.own(esp.TARGET)), str(saved))
        sudo('sh', '-c', f'printf x >> {self.own(esp.TARGET)}')
        code, out = self.execute('install', '--candidate', candidate)
        self.check('install refuses a boot.bin that is not the original',
                   code == 2 and 'not the backed-up original' in out.get('reason', ''), out)
        self.check('that refusal created no kept copy or temporary file',
                   self.sha(esp.KEPT) is None and self.sha(esp.TEMP) is None)
        sudo('cp', str(saved), str(self.own(esp.TARGET)))
        sudo('sync')
        self.check('test put the original back', self.sha(esp.TARGET) == esp.ORIGINAL_SHA)

        sudo('sh', '-c', f'echo stale > {self.own(esp.KEPT)}')
        code, out = self.execute('install', '--candidate', candidate)
        self.check('install refuses a wrong kept copy', code == 2 and 'pre-g2' in out.get('reason', ''), out)
        sudo('rm', str(self.own(esp.KEPT)))

        sudo('sh', '-c', f'echo stale > {self.own(esp.TEMP)}')
        code, out = self.execute('install', '--candidate', candidate)
        self.check('install succeeds and clears a stale temporary file',
                   code == 0 and out['status'] == 'DONE' and out['boot_bin'] == 'window build', out)
        self.check('boot.bin is the window build', self.sha(esp.TARGET) == esp.CANDIDATE_SHA)
        self.check('the original is kept alongside', self.sha(esp.KEPT) == esp.ORIGINAL_SHA)
        self.check('no temporary file remains', self.sha(esp.TEMP) is None)
        self.check('every other ESP file is unchanged after install', self.others_unchanged(baseline))
        self.check('filesystem is clean after install', self.fsck_clean())

        code, out = self.execute('install', '--candidate', candidate)
        self.check('a second install changes nothing', code == 0 and out['status'] == 'NOTHING_TO_DO', out)
        code, out = self.execute('finalize')
        self.check('finalize refuses while the window build is installed', code == 2, out)

        code, out = self.tool('restore')
        self.check('restore is a dry run by default', code == 0 and out['status'] == 'DRY_RUN_NOTHING_WRITTEN', out)
        self.check('dry-run restore wrote nothing', self.sha(esp.TARGET) == esp.CANDIDATE_SHA)

        sudo('sh', '-c', f'printf x >> {self.own(esp.TARGET)}')
        code, out = self.execute('restore')
        self.check('restore refuses an unknown boot.bin by default', code == 2 and 'neither' in out.get('reason', ''), out)
        code, out = self.execute('restore', '--replace-unknown-target')
        self.check('restore can replace an unknown boot.bin when told to',
                   code == 0 and self.sha(esp.TARGET) == esp.ORIGINAL_SHA, out)
        code, out = self.execute('install', '--candidate', candidate)
        self.check('install again after that restore', code == 0 and self.sha(esp.TARGET) == esp.CANDIDATE_SHA, out)

        sudo('rm', str(self.own(esp.TARGET)))
        code, out = self.execute('restore')
        self.check('restore works when boot.bin is missing', code == 0 and self.sha(esp.TARGET) == esp.ORIGINAL_SHA, out)
        code, out = self.execute('install', '--candidate', candidate)
        self.check('install again after the missing-file restore', code == 0, out)

        keep_bytes = self.work / 'saved-kept.bin'
        sudo('cp', str(self.own(esp.KEPT)), str(keep_bytes))
        sudo('sh', '-c', f'printf x >> {self.own(esp.KEPT)}')
        code, out = self.execute('restore')
        self.check('restore refuses a damaged kept copy', code == 2 and 'verified original' in out.get('reason', ''), out)
        self.check('that refusal left boot.bin in place', self.sha(esp.TARGET) == esp.CANDIDATE_SHA)
        sudo('cp', str(keep_bytes), str(self.own(esp.KEPT)))

        code, out = self.execute('restore')
        self.check('restore puts the original back', code == 0 and out['boot_bin'] == 'original', out)
        self.check('boot.bin hash is the original', self.sha(esp.TARGET) == esp.ORIGINAL_SHA)
        self.check('the kept copy stays after restore', self.sha(esp.KEPT) == esp.ORIGINAL_SHA)
        code, out = self.execute('restore')
        self.check('a second restore changes nothing', code == 0 and out['status'] == 'NOTHING_TO_DO', out)

        window = self.work / 'dt-window'
        self.write_dt(window, stage2='121fcbf35d4501814b58ca5347926a4173b6a512-darwin-lab-j313-window-v1')
        code, out = self.execute('finalize', dt=window)
        self.check('finalize refuses before a reboot on the original', code == 2 and 'reboot first' in out.get('reason', ''), out)
        self.check('that refusal kept the copy', self.sha(esp.KEPT) == esp.ORIGINAL_SHA)
        code, out = self.execute('finalize')
        self.check('finalize deletes the kept copy after that reboot', code == 0 and self.sha(esp.KEPT) is None, out)
        self.check('the ESP is byte-identical to the starting copy', tree(self.mount) == baseline)
        self.check('filesystem is clean at the end', self.fsck_clean())

    def unit(self):
        info = ('36 25 0:31 / /boot/efi rw,relatime shared:1 - vfat /dev/nvme0n1p4 rw,fmask=0022\n'
                '37 25 0:32 / /media/a\\040b ro - ext4 /dev/sda1 ro\n')
        mount = esp.parse_mount(info, '/boot/efi')
        self.check('mount table parser finds the ESP', mount and mount['fstype'] == 'vfat' and 'rw' in mount['options'])
        self.check('mount table parser handles escapes', esp.parse_mount(info, '/media/a b')['fstype'] == 'ext4')
        self.check('mount table parser refuses a non-mount', esp.parse_mount(info, '/boot') is None)
        uuid = '01234567-89ab-cdef-0123-456789abcdef'
        target = {'/dev/disk/by-partuuid/' + uuid: '/dev/nvme0n1p4', '/dev/nvme0n1p4': '/dev/nvme0n1p4',
                  '/dev/nvme0n1p9': '/dev/nvme0n1p9'}
        esp.check_identity({'source': '/dev/nvme0n1p4'}, uuid, target.get)
        self.check('identity check accepts the booted ESP', True)
        for source, value in (('/dev/nvme0n1p9', uuid), ('/dev/nvme0n1p4', 'bad'),
                              ('/dev/nvme0n1p4', '11111111-89ab-cdef-0123-456789abcdef')):
            try:
                esp.check_identity({'source': source}, value, target.get)
                refused = False
            except esp.Refused:
                refused = True
            self.check(f'identity check refuses {source} with {value[:8]}', refused)
        code, out = run_main(['status', '--esp', '/definitely/not/mounted'])
        self.check('a path that is not a mount point is refused', code == 2, out)
        code, out = run_main(['status', '--esp', '/', '--dt-root', str(self.dt)])
        self.check('--dt-root is refused outside loop tests', code == 2, out)
        code, out = run_main(['status', '--esp', '/', '--loop-test', '--dt-root', str(self.dt)])
        self.check('a non-FAT path is refused', code == 2, out)


def run_main(words):
    done = subprocess.run([sys.executable, '-B', '-I', TOOL, *words], capture_output=True, text=True)
    return done.returncode, json.loads(done.stdout.strip().splitlines()[-1])


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--backup', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    if args.work.exists():
        raise SystemExit('--work must not exist')
    original = args.backup / esp.TARGET
    before = (original.stat().st_mtime_ns, hashlib.sha256(original.read_bytes()).hexdigest())
    harness = Harness(args)
    try:
        harness.setup()
        harness.unit()
        harness.scenarios()
    finally:
        harness.cleanup()
        if args.work.exists():
            shutil.rmtree(args.work, ignore_errors=True)
    after = (original.stat().st_mtime_ns, hashlib.sha256(original.read_bytes()).hexdigest())
    harness.check('the backup was not modified', before == after)
    failed = [name for name, passed in harness.results if not passed]
    print(f'{len(harness.results) - len(failed)}/{len(harness.results)} checks passed')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
