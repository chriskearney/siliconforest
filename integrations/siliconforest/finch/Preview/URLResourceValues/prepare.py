#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Prepare a private URL resource source slice and additive compiler overlay; never build or execute an app."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def sha(data):
    return hashlib.sha256(data).hexdigest()


def git_bytes(root, revision, name):
    return subprocess.check_output(['git', '-C', str(root), 'show', revision + ':' + name])


def declaration(source, marker):
    start = source.index(marker)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        if source[end] == '{':
            depth += 1
        elif source[end] == '}':
            depth -= 1
        end += 1
    return source[start:end]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--foundation-source', required=True, type=Path)
    parser.add_argument('--finch-source', required=True, type=Path)
    parser.add_argument('--baseline-overlay', required=True, type=Path)
    parser.add_argument('--coregraphics-header', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if args.output.exists() or args.output.is_symlink():
        raise ValueError('Fresh nonexistent owned source output required')
    here = Path(__file__).resolve().parent
    manifest = json.loads((here / 'sources.json').read_text())
    foundation = git_bytes(args.foundation_source, manifest['revision'], manifest['source'])
    if sha(foundation) != manifest['sha256']:
        raise ValueError('Foundation pin digest differs')
    finch = {}
    for name, digest in manifest['finch_files'].items():
        value = git_bytes(args.finch_source, manifest['finch_revision'], name)
        if sha(value) != digest:
            raise ValueError('Finch pin digest differs: ' + name)
        finch[name] = value
    for name, digest in manifest['prepared_files'].items():
        if sha((here / name).read_bytes()) != digest:
            raise ValueError('Reviewed adaptation changed: ' + name)
    adapted = (here / 'URLResourceValuesReader.swift').read_text()
    for marker in manifest['mined_declarations']:
        expected = declaration(foundation.decode(), marker)
        expected = expected.replace('?.intValue', '?.integerValue').replace('NSNumber(value: value)', 'NSNumber(bool: value)')
        if expected not in adapted:
            raise ValueError('Pinned value declaration differs: ' + marker)
    getter = declaration(finch['userland/swift/overlays/UniformTypeIdentifiers/UTType.swift'].decode(), 'extension URLResourceValues {')
    if getter not in (here / 'ContentType.swift').read_text():
        raise ValueError('Pinned UTI getter differs')
    overlay = json.loads(args.baseline_overlay.read_text())
    headers = {}
    for entry in overlay['roots']:
        source = Path(entry['external-contents'])
        name = source.name
        data = source.read_bytes()
        if name in headers and headers[name] != data:
            raise ValueError('Conflicting baseline header basename')
        headers[name] = data
    if b'SFURLResourceReader.h' in headers['Foundation.h']:
        raise ValueError('Choose a baseline without this slice already applied')
    if not args.coregraphics_header.is_file():
        raise ValueError('Existing CoreGraphics declaration header required')
    # Complete verification precedes all writes; no shared SDK or baseline edits.
    args.output.mkdir()
    for name in manifest['prepared_files']:
        shutil.copyfile(here / name, args.output / name)
    target = args.output / 'overlay'
    target.mkdir()
    for name, data in headers.items():
        if name == 'Foundation.h':
            data += b'\n#import <Foundation/SFURLResourceReader.h>\n'
        (target / name).write_bytes(data)
    for name in ['SFURLResourceReader.h', 'UTTypeBridge.h']:
        shutil.copyfile(here / name, target / name)
    for entry in overlay['roots']:
        entry['external-contents'] = str((target / Path(entry['external-contents']).name).resolve())
    for entry in list(overlay['roots']):
        if Path(entry['name']).name == 'Foundation.h':
            overlay['roots'].append({'type': 'file',
                                     'name': str(Path(entry['name']).with_name('SFURLResourceReader.h')),
                                     'external-contents': str((target / 'SFURLResourceReader.h').resolve())})
    (target / 'foundation-overlay.json').write_text(json.dumps(overlay, indent=2) + '\n')
    (target / 'cross.modulemap').write_text(
        'module CoreGraphics [system] { header ' + json.dumps(str(args.coregraphics_header)) + ' export * }\n'
        'module SFUTTypeBridge [system] { header "UTTypeBridge.h" export * }\n')
    licenses = args.output / 'licenses'
    licenses.mkdir()
    shutil.copyfile(here.parents[4] / 'LICENSES/Swift-Foundation.txt', licenses / 'Swift-Foundation.txt')
    (licenses / 'Finch-MIT.txt').write_bytes(finch['LICENSE-MIT'])
    (licenses / 'Finch-Apache-2.0.txt').write_bytes(finch['LICENSE-APACHE'])
    shutil.copyfile(here / 'sources.json', args.output / 'sources.json')
    print(json.dumps({'scope': 'Private open source/overlay preparation only; no Data/name/error edits or app execution',
                      'source_files': len(manifest['prepared_files']), 'output': str(args.output)}))


if __name__ == '__main__':
    main()
