#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Assemble the private J313 G2 packet: kernel collection, RAM root and manifest. Offline.

The packet holds this Air's Wi-Fi firmware, read from the ESP backup, so it stays outside the
repository. The kernel must be the G1 RAM-boot collection: it has no Apple NVMe driver and its only
NVMe family matches PCI storage, which the Air's internal storage is not.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tarfile

HERE = Path(__file__).resolve().parent
KC_SHA = 'ef49aa0a376ed1b25054247e708467c020d5c8c95855186a166a5c8f616018c8'
KC_BYTES = 34637870
TIP_COMMIT = 'cd001928e0223fd77a7850f09e43580b51bde239'
CORECRYPTO = 'ea8e6afec1a8666a077c110fc4148fb1ac293ae8'
M1N1 = '121fcbf35d4501814b58ca5347926a4173b6a512'
FORBIDDEN_MEMBERS = re.compile(r'SFAppleNVMe|SFNVMe|nvme', re.I)
ALLOWED_NVME_MEMBER = 'com.apple.iokit.IONVMEFamily'
FIRMWARE = re.compile(r'brcm/(brcmfmac4378b1-pcie\.apple,shikoku(?:-RASP-[mu]\.txt|\.bin|\.clm_blob|\.txcap_blob))$')
EXPERIMENTS = {
    'desktop_experiment': {'version': 1, 'command': '/usr/bin/darwin-desktop-test'},
    'native_trackpad_child_experiment': {
        'version': 1, 'driver': 'SFM1SPIHID', 'child': 'SFM1SPITrackpad', 'interface': 2, 'mode': 'passive_child',
        'input': 'sfhid', 'feature_writes': False, 'host_hid_injection': False,
        'diagnostic_property': 'SFM1TrackpadChildStateV1'},
    'apcie_port_observer_experiment': {'version': 1, 'observer': 'SFApcieT8103Bridge', 'snapshot_bytes': 84,
                                       'read_only': True, 'shared_writes': False},
}


def sha(path):
    with open(path, 'rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def need(condition, message):
    if not condition:
        raise SystemExit('REFUSED: ' + message)


def members(data):
    count = struct.unpack_from('<I', data, 16)[0]
    offset, names = 32, []
    for _ in range(count):
        command, size = struct.unpack_from('<II', data, offset)
        if command == 0x80000035:
            name = struct.unpack_from('<I', data, offset + 24)[0]
            names.append(data[offset + name:data.index(b'\0', offset + name)].decode())
        offset += size
    return names


def check_kernel(path):
    need(os.path.getsize(path) == KC_BYTES and sha(path) == KC_SHA, 'this is not the G1 RAM-boot collection')
    data = Path(path).read_bytes()
    names = members(data)
    bad = [name for name in names if FORBIDDEN_MEMBERS.search(name) and name != ALLOWED_NVME_MEMBER]
    need(not bad, 'the collection has a storage driver: ' + ', '.join(bad))
    need(b'SFAppleNVMe' not in data and b'SFAppleNVMeRW' not in data, 'the collection contains the NVMe driver')
    index = data.find(b'<string>' + ALLOWED_NVME_MEMBER.encode() + b'</string>')
    need(index >= 0, 'IONVMEFamily personality not found')
    window = data[max(index - 200, 0):index + 9000].decode('utf8', 'replace')
    need('0x01080200&amp;0xffffff00' in window and '<string>IOPCIDevice</string>' in window,
         'IONVMEFamily no longer matches PCI NVMe only')
    return names


def write_json(path, value):
    with open(path, 'x') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kernel', type=Path, required=True)
    parser.add_argument('--base-image', type=Path, required=True, help='read-only RAM root base image')
    parser.add_argument('--base-packet', type=Path, required=True, help='packet whose mapping and record are the base')
    parser.add_argument('--firmware-tar', type=Path, required=True, help="vendorfw/firmware.tar in the Air's ESP backup")
    parser.add_argument('--ioreg', type=Path, required=True, help="the ioreg build (a Nix store path)")
    parser.add_argument('--stager', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--seconds', type=int, default=240)
    args = parser.parse_args()
    need(not args.out.exists(), '--out already exists')
    need(60 <= args.seconds <= 600, '--seconds must be 60 to 600')
    names = check_kernel(args.kernel)
    kernel_path = args.kernel.resolve()
    output = kernel_path.parent
    need(re.fullmatch(r'/nix/store/[0-9a-z]{32}-[A-Za-z0-9+._?=-]+', str(output)) is not None, 'kernel is not a store path')
    deriver = subprocess.check_output([str(Path.home() / '.nix-profile/bin/nix-store'), '-q', '--deriver', str(output)],
                                      text=True).strip()
    need(deriver.endswith('.drv'), 'no derivation recorded for the collection')
    ioreg = args.ioreg / 'usr/sbin/ioreg'
    need(ioreg.is_file(), 'no ioreg in ' + str(args.ioreg))

    args.out.mkdir(mode=0o700, parents=True)
    private = args.out / 'staged'
    private.mkdir()
    firmware = []
    with tarfile.open(args.firmware_tar) as archive:
        for member in archive.getmembers():
            match = FIRMWARE.search(member.name)
            if not match:
                continue
            # The .bin name is a link inside the archive, to the firmware this module shares.
            source = archive.getmember(member.linkname) if member.islnk() or member.issym() else member
            need(source.isfile() and source.size > 0, 'firmware entry is not a file: ' + member.name)
            target = private / match[1]
            with archive.extractfile(source) as stream:
                target.write_bytes(stream.read())
            firmware.append(target)
    need(len(firmware) == 5, f'expected 5 shikoku firmware files, found {len(firmware)}')

    guest = private / 'darwin-j313-g2'
    guest.write_text((HERE / 'darwin-j313-g2.sh').read_text().replace('@SECONDS@', str(args.seconds)))
    guest.chmod(0o755)
    prologue = HERE.parents[1] / 'rebase/guest/rb-prologue.sh'
    base = json.loads((args.base_packet / 'mapping.json').read_text())['files']
    mapping = []
    for entry in base:
        entry = dict(entry)
        if entry['destination'] == '/usr/bin/darwin-desktop-test':
            entry['source'] = str(guest)
        need(Path(entry['source']).is_file(), 'missing mapped file: ' + entry['source'])
        mapping.append(entry)
    need(any(e['source'] == str(guest) for e in mapping), 'the base mapping has no guest entry')
    extra = [(ioreg, '/usr/sbin/ioreg', True), (prologue, '/usr/bin/rb-prologue', True)]
    extra += [(path, '/Library/Firmware/brcm/' + path.name, False) for path in firmware]
    taken = {destination for _, destination, _ in extra}
    mapping = [entry for entry in mapping if entry['destination'] not in taken]
    mapping += [dict(source=str(source), destination=destination, executable=executable)
                for source, destination, executable in extra]
    write_json(args.out / 'mapping.json', dict(files=mapping))

    environment = {**os.environ, 'BS_RAMDISK_CACHE': '0', 'PYTHONDONTWRITEBYTECODE': '1'}
    # The stager only writes under the artifacts directory of the tree it runs from (ignored by Git).
    staging = args.stager.resolve().parents[4] / 'artifacts' / ('j313-g2-stage-' + args.out.name)
    need(not staging.exists(), 'stale staging directory: ' + str(staging))
    staging.mkdir(parents=True, mode=0o700)
    with open(args.out / 'stage.log', 'x') as log:
        subprocess.run([sys.executable, '-B', str(args.stager), '--base', str(args.base_image),
                        '--mapping', str(args.out / 'mapping.json'), '--output', str(staging / 'ramdisk.img')],
                       stdout=log, stderr=subprocess.STDOUT, check=True, env=environment)
    for name in ('ramdisk.img', 'ramdisk.record.json'):
        shutil.move(str(staging / name), str(args.out / name))
    shutil.rmtree(staging)
    ram_record = json.loads((args.out / 'ramdisk.record.json').read_text())
    need(ram_record['e2fsck_exit_code'] == 0, 'the RAM root failed its filesystem check')

    shutil.copyfile(kernel_path, args.out / 'kernel.macho')
    os.chmod(args.out / 'kernel.macho', 0o600)
    patch = (f'# J313 G2 packet. Kernel collection {KC_SHA}\n# built at SiliconForest {TIP_COMMIT} '
             f'from the recipe integrations/siliconforest/rebase/build-kc.nix\n')
    (args.out / 'source.patch').write_text(patch)
    record = {
        'status': 'BUILT_NOT_BOOTED', 'build_exit_code': 0,
        'recorded_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'source_commit': TIP_COMMIT, 'corecrypto_commit': CORECRYPTO,
        'corecrypto_note': 'launcher pin field; the collection takes corecrypto from the source flake',
        'source_patch_sha256': sha(args.out / 'source.patch'), 'kernel_sha256': KC_SHA,
        'drv_path': deriver, 'output_path': str(output), **EXPERIMENTS,
        'ramdisk': {'sha256': sha(args.out / 'ramdisk.img'),
                    'payload_record_sha256': sha(args.out / 'ramdisk.record.json'),
                    'guest_script_sha256': sha(guest)},
        'hardware_gate': 'NOT_BOOTED_WAITING_FOR_OWNER_APPROVAL',
        'not_claimed': ['any boot on J313', 'display, keyboard, trackpad, Wi-Fi or thermal behaviour'],
    }
    write_json(args.out / 'build-record.json', record)
    artifacts = {key: {'path': name, 'sha256': sha(args.out / name), 'bytes': (args.out / name).stat().st_size}
                 for key, name in (('kernel', 'kernel.macho'), ('source_patch', 'source.patch'),
                                   ('build_record', 'build-record.json'), ('ramdisk', 'ramdisk.img'))}
    write_json(args.out / 'manifest.json', {
        'schema_version': 1, 'target': 'm1-mba13-j313', 'purpose': 'continuing-xnu',
        'source_pins': {'puredarwin': TIP_COMMIT, 'corecrypto': CORECRYPTO, 'm1n1': M1N1}, 'artifacts': artifacts})
    shutil.rmtree(private)
    print(json.dumps({'members': len(names), 'mapped_files': len(mapping),
                      'kernel': artifacts['kernel'], 'ramdisk': artifacts['ramdisk'],
                      'manifest_sha256': sha(args.out / 'manifest.json')}, indent=2))


if __name__ == '__main__':
    main()
