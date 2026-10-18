#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Bind the checked C/Rust layouts to the kernel artifact being packaged."""
import hashlib
import json
from pathlib import Path
import sys


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def verify(build):
    build = Path(build)
    data = json.loads((build / 'layout-checks.json').read_text())
    if data.get('schema') != 1 or data.get('checked') is not True:
        raise ValueError('Kernel needs completed C/Rust layout checks')
    for name, expected in data['files'].items():
        if digest(build / name) != expected:
            raise ValueError('Kernel layout evidence changed: ' + name)
    generator = Path(data['bindgen']['path'])
    if digest(generator) != data['bindgen']['sha256']:
        raise ValueError('Checked bindings generator changed')
    return data


def record(build, generator):
    build, generator = Path(build).resolve(), Path(generator).resolve(strict=True)
    names = ['.config', 'kernelrelease', 'arch/arm64/boot/Image']
    for crate, generated in [('bindings', 'bindings'), ('uapi', 'uapi')]:
        source = 'rust/' + crate + '/' + generated + '_generated.rs'
        command = 'rust/' + crate + '/.' + generated + '_generated.rs.cmd'
        obj = 'rust/' + crate + '.o'
        text = (build / source).read_text()
        if 'Offset of field: task_struct::group_leader' not in text:
            raise ValueError('Missing unconditional task layout assertions')
        if '--no-layout-tests' in (build / command).read_text().splitlines()[0]:
            raise ValueError('Bindings were generated without layout checks')
        if (build / obj).stat().st_mtime_ns < (build / source).stat().st_mtime_ns:
            raise ValueError('Bindings object predates checked source')
        names += [source, command, obj]
    data = {'schema': 1, 'checked': True,
            'bindgen': {'path': str(generator), 'sha256': digest(generator)},
            'files': {name: digest(build / name) for name in names}}
    (build / 'layout-checks.json').write_text(json.dumps(data, indent=2) + '\n')
    verify(build)


if __name__ == '__main__':
    record(sys.argv[1], sys.argv[2])
