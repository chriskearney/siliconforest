# SPDX-License-Identifier: MIT
"""Manage only stage 2, with one exact kernel/DTB/U-Boot contract."""
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

from .release import Refusal, digest, require, validate, PACKAGES

BEGIN = '# >>> SiliconForest managed stage 2'
END = '# <<< SiliconForest managed stage 2'
ACTIVE = Path('/var/lib/siliconforest/active.json')
INSTALLING = Path('/run/siliconforest-installing')
CONFIG = Path('/etc/siliconforest/m1n1.conf')


def run(*args):
    subprocess.run(args, check=True)


def dt_string(path):
    raw = Path(path).read_bytes()
    require(raw.endswith(b'\0'), 'Device-tree string has no terminator')
    return raw.rstrip(b'\0').decode('ascii')


def identity():
    root = Path('/proc/device-tree')
    compatibles = (root / 'compatible').read_bytes().rstrip(b'\0').decode('ascii').split('\0')
    board = next((c for c in compatibles if re.fullmatch(r'apple,j[0-9]+[a-z]?', c)), None)
    require(board, 'This is not an identified Apple Silicon Mac')
    return board, dt_string(root / 'chosen/asahi,os-fw-version')


def system_esp():
    partuuid = dt_string('/proc/device-tree/chosen/asahi,efi-system-partition')
    require(bool(re.fullmatch(r'[A-Fa-f0-9-]{36}', partuuid)), 'Missing paired ESP PARTUUID')
    result = subprocess.check_output(['findmnt', '--json', '--output',
        'TARGET,SOURCE,FSTYPE,OPTIONS', '--source', 'PARTUUID=' + partuuid], text=True)
    mounts = json.loads(result).get('filesystems', [])
    require(len(mounts) == 1, 'Mount exactly the paired system ESP before installation')
    mount = mounts[0]
    require(mount['fstype'] == 'vfat' and 'rw' in mount['options'].split(','),
            'The paired ESP must be a writable FAT filesystem')
    esp = Path(mount['target'])
    require((esp / 'm1n1/boot.bin').is_file(), 'Paired ESP has no existing stage 2')
    return esp


def atomic(path, data, mode=0o644):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    require(not path.is_symlink(), 'Refuse a symlink target: ' + str(path))
    fd, temporary = tempfile.mkstemp(prefix=path.name + '.', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
        fd = os.open(path.parent, os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def managed(text, block):
    require(text.count(BEGIN) == text.count(END) and text.count(BEGIN) <= 1,
            'Malformed SiliconForest configuration block')
    if BEGIN in text:
        require(text.index(BEGIN) < text.index(END), 'Configuration markers are out of order')
        before, rest = text.split(BEGIN, 1)
        _, after = rest.split(END, 1)
        text = before + after.lstrip('\n')
    return text.rstrip() + '\n\n' + BEGIN + '\n' + block.rstrip() + '\n' + END + '\n'


def config_lines(text, overrides):
    allowed = []
    keys = {line.split('=', 1)[0] for line in overrides}
    for line in text.splitlines():
        line = line.strip()
        if re.fullmatch(r'(chosen\.[A-Za-z0-9,._-]+|display|mitigations)=[^\r\n\x00]+', line):
            if line.split('=', 1)[0] not in keys:
                allowed.append(line)
        elif line and not line.startswith('#'):
            raise Refusal('Unrecognized existing m1n1 option; review it before migration')
    return ('\n'.join(allowed + overrides) + '\n').encode()


def paths(data):
    modules = Path('/usr/lib/modules') / data['kernel_release']
    return {'kernel_image_sha256': modules / 'vmlinuz',
            'config_sha256': modules / 'config',
            'dtb_sha256': modules / 'dtbs' / data['boot']['dtb'],
            'm1n1_sha256': Path('/usr/lib/siliconforest/m1n1.bin'),
            'uboot_sha256': Path(data['boot']['uboot_path'])}


def check_files(data):
    files = paths(data)
    for key, path in files.items():
        require(path.is_file() and digest(path) == data['boot'][key],
                'Installed boot component differs from release: ' + str(path))
    config = files['config_sha256'].read_text()
    native = '\nCONFIG_SILICONFOREST_M3=y\n' in '\n' + config
    require(native == (data['kernel_variant'] == 'm3-native'), 'Wrong installed kernel configuration')
    return files


def image(data, files, configuration):
    # m1n1 selects the board DTB, then consumes a self-delimiting gzip U-Boot.
    buffers = {k: files[k].read_bytes() for k in ('m1n1_sha256', 'dtb_sha256', 'uboot_sha256')}
    for key, value in buffers.items():
        require(hashlib.sha256(value).hexdigest() == data['boot'][key],
                'Boot input changed before assembly: ' + key)
    options = dict(line.split('=', 1) for line in config_lines(configuration.decode(), []).decode().splitlines())
    for line in data['boot']['m1n1_config']:
        key, value = line.split('=', 1)
        require(options.get(key) == value, 'Required handoff option differs: ' + key)
    return (buffers['m1n1_sha256'] + buffers['dtb_sha256'] +
            gzip.compress(buffers['uboot_sha256'], mtime=0) + configuration)


def boot_update():
    require(os.geteuid() == 0, 'Boot update requires root')
    if INSTALLING.exists() or not ACTIVE.exists():
        return
    data = json.loads(ACTIVE.read_text())
    validate(data, install=True, testing=data['qualification'].get('status') == 'attended-testing')
    board, firmware = identity()
    require(board in data['boards'] and firmware in data['firmware'],
            'Active release does not cover this board/firmware')
    for component, name in PACKAGES.items():
        actual = subprocess.check_output(['pacman', '-Q', name], text=True).split()
        require(actual == [name, data['packages'][component]['version']],
                'Mixed package set; rerun the matched-release installer')
    files = check_files(data)
    esp = system_esp()
    boot = data['boot']
    entry_root = esp if boot['backend'] == 'limine' else Path('/boot')
    entry, kernel_image = entry_root / boot['entry'], entry_root / boot['image']
    require(entry.is_file() and kernel_image.is_file(), 'Missing generated kernel boot entry or image')
    require(kernel_image.stat().st_size <= boot['max_image_bytes'],
            'Generated kernel boot image exceeds its qualified space limit')
    require(entry.resolve().is_relative_to(entry_root.resolve()) and
            kernel_image.resolve().is_relative_to(entry_root.resolve()), 'Boot entry escapes its partition')
    text = entry.read_text()
    require('linux-siliconforest' in text, 'Boot menu has no SiliconForest kernel')
    if boot['backend'] == 'limine':
        require(boot['image'] in text, 'Boot menu does not reference the qualified UKI path')
    else:
        require(data['kernel_release'] in text, 'GRUB does not reference the release kernel')
    configuration = CONFIG.read_bytes()
    expected = image(data, files, configuration)
    require(len(expected) <= boot['max_stage2_bytes'], 'Stage 2 exceeds its qualified space limit')
    target = esp / 'm1n1/boot.bin'
    require(target.resolve().is_relative_to(esp.resolve()), 'Stage 2 escapes its partition')
    if target.read_bytes() != expected:
        atomic(target, expected)
        require(target.read_bytes() == expected, 'Stage 2 readback mismatch')
    print('SiliconForest stage 2 matches its kernel, board DTB and U-Boot')
