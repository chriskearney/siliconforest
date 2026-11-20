#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build an inert, digest-checked private Preview packet locally. No SSH or app execution."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import tarfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative(name):
    value = PurePosixPath(name)
    if not name or value.is_absolute() or '..' in value.parts or str(value) == '.':
        raise ValueError('Rooted relative path required: ' + name)
    return Path(*value.parts)


def inventory(root):
    files, links = {}, {}
    # os.walk does not descend into symlink directories.
    for folder, dirs, names in os.walk(root, followlinks=False):
        for name in sorted(dirs + names):
            path = Path(folder) / name
            rel = path.relative_to(root).as_posix()
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode):
                links[rel] = os.readlink(path)
            elif stat.S_ISREG(mode):
                files[rel] = digest(path)
            elif not stat.S_ISDIR(mode):
                raise ValueError('Unsupported packet member: ' + str(path))
    return {'regular_files': dict(sorted(files.items())), 'symlinks': dict(sorted(links.items()))}


def remove_owned(path):
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.exists():
        for folder, dirs, _ in os.walk(path, followlinks=False):
            current = Path(folder)
            current.chmod(current.stat().st_mode | stat.S_IRWXU)
            for name in dirs:
                child = current / name
                if not child.is_symlink():
                    child.chmod(child.stat().st_mode | stat.S_IRWXU)
        shutil.rmtree(path)


def destination(root, name):
    rel = relative(name)
    current = root
    for part in rel.parts[:-1]:
        current = current / part
        # Never write through an inherited baseline alias.
        if current.is_symlink():
            current.unlink()
        current.mkdir(exist_ok=True)
        current.chmod(current.stat().st_mode | stat.S_IRWXU)
    return root / rel


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--spec', required=True, type=Path)
    parser.add_argument('--scratch', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    scratch = args.scratch.resolve(strict=True)
    output = args.output.absolute()
    if output.parent.resolve(strict=True) != scratch or output.exists() or output.is_symlink():
        raise ValueError('Nonexistent direct child of owned scratch required')
    spec = json.loads(args.spec.read_text())
    remote = PurePosixPath(spec['remote_root'])
    if (remote.parent != PurePosixPath('/private/var/db/sfpreview-app')
            or not remote.name.startswith('p13-') or '..' in remote.parts):
        raise ValueError('Unique proposed private P13 root required')
    if spec['app_execution_allowed'] is not False:
        raise ValueError('Preparation packet must explicitly prohibit app execution')
    base = Path(spec['base_packet'])
    if digest(base / 'SHA256SUMS.json') != spec['base_manifest_sha256']:
        raise ValueError('Original packet manifest changed')
    declared = json.loads((base / 'SHA256SUMS.json').read_text())
    actual = inventory(base)
    actual['regular_files'].pop('SHA256SUMS.json')
    if actual != declared:
        raise ValueError('Base packet files or literal links changed')
    original = Path(spec['original_app'])
    if inventory(original)['regular_files'] != spec['app_regular_files']:
        raise ValueError('Owner original app bytes changed')
    if inventory(base / 'Applications/Preview.app')['regular_files'] != spec['app_regular_files']:
        raise ValueError('Base packet app differs from owner original')
    inputs = []
    for entry in spec['entries']:
        rel = relative(entry['destination'])
        if rel.parts[0] not in {'core', 'prefix', 'candidates', 'fixtures'}:
            raise ValueError('Provider entry outside owned overlay: ' + str(rel))
        if entry['kind'] == 'symlink':
            inputs.append(entry)
            continue
        source = Path(entry['source'])
        if entry['kind'] == 'file':
            if not source.is_file() or digest(source) != entry['sha256']:
                raise ValueError('Provider bytes changed: ' + str(source))
        elif entry['kind'] == 'tree':
            if source.is_symlink() or inventory(source) != entry['manifest']:
                raise ValueError('Provider tree changed: ' + str(source))
        else:
            raise ValueError('Unknown entry kind')
        inputs.append(entry)
    # Every source is checked before creating the fresh destination.
    output.mkdir(mode=0o700)
    packet = output / 'packet'
    shutil.copytree(base, packet, symlinks=True)
    copied_base = inventory(packet)
    copied_base['regular_files'].pop('SHA256SUMS.json')
    if copied_base != declared:
        raise ValueError('Base packet changed during copy')
    remove_owned(packet / 'SHA256SUMS.json')
    remove_owned(packet / 'launch-plan.json')
    for entry in inputs:
        target = destination(packet, entry['destination'])
        remove_owned(target)
        if entry['kind'] == 'tree':
            shutil.copytree(entry['source'], target, symlinks=True)
        elif entry['kind'] == 'file':
            shutil.copy2(entry['source'], target)
        else:
            target.symlink_to(entry['target'])
        if entry['kind'] == 'file' and digest(target) != entry['sha256']:
            raise ValueError('Provider changed during copy: ' + str(target))
        if entry['kind'] == 'tree' and inventory(target) != entry['manifest']:
            raise ValueError('Provider tree changed during copy: ' + str(target))
    for name in ['home/Library/Preferences', 'tmp', 'logs', 'readback']:
        path = destination(packet, name + '/.owned')
        path.write_text('P13 private scratch; no launch authorized.\n')
    if inventory(packet / 'Applications/Preview.app')['regular_files'] != spec['app_regular_files']:
        raise ValueError('Fresh app differs from owner original')
    if inventory(original)['regular_files'] != spec['app_regular_files']:
        raise ValueError('Owner original app changed during preparation')
    plan = dict(spec)
    plan['preparation_only'] = True
    plan['spec_sha256'] = digest(args.spec)
    (packet / 'P13-plan.json').write_text(json.dumps(plan, indent=2, sort_keys=True) + '\n')
    manifest = inventory(packet)
    (packet / 'SHA256SUMS.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
    archive = output / 'p13.tar.gz'
    with archive.open('xb') as raw, gzip.GzipFile(filename='', fileobj=raw, mode='wb', mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode='w', format=tarfile.PAX_FORMAT, dereference=False) as tar:
            members = sorted(packet.rglob('*'), key=lambda p: p.relative_to(packet).as_posix())
            for path in members:
                info = tar.gettarinfo(str(path), arcname=path.relative_to(packet).as_posix())
                info.uid = info.gid = info.mtime = 0
                info.uname = info.gname = ''
                info.pax_headers = {}
                if info.isfile():
                    with path.open('rb') as source:
                        tar.addfile(info, source)
                else:
                    tar.addfile(info)
    result = {'scope': 'Local preparation only; nothing sent to M1 or executed',
              'archive': str(archive), 'sha256': digest(archive),
              'regular_files': len(manifest['regular_files']), 'links': len(manifest['symlinks']),
              'app_execution_allowed': False, 'blocking_conditions': spec['blocking_conditions']}
    (output / 'preparation-receipt.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
