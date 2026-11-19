#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Prepare digest-verified open AttributedString sources without editing a checkout."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True,
                        help='Local swift-foundation Git checkout containing the pinned revision')
    parser.add_argument('--output', type=Path, required=True,
                        help='Fresh, nonexistent owned output directory')
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    manifest = json.loads((here / 'sources.json').read_text())
    verified = {}
    for name, digest in manifest['files'].items():
        data = subprocess.check_output(['git', '-C', str(args.source), 'show',
                                        manifest['revision'] + ':' + name])
        if hashlib.sha256(data).hexdigest() != digest:
            raise ValueError('Pinned source digest mismatch: ' + name)
        leaf = Path(name).name
        if leaf in verified:
            raise ValueError('Duplicate source basename: ' + name)
        verified[leaf] = data
    args.output.mkdir()
    for name, data in verified.items():
        (args.output / name).write_bytes(data)
    patch = json.loads((here / 'compatibility.json').read_text())
    if patch['format'] != 'unified-diff-lines':
        raise ValueError('Unknown compatibility patch format')
    subprocess.run(['patch', '--batch', '--fuzz=0', '-p1'],
                   input=''.join(patch['lines']), text=True, cwd=args.output, check=True)
    shutil.copyfile(here / 'AttributeInterop.swift', args.output / 'AttributeInterop.swift')
    shutil.copytree(here / 'include', args.output / 'include')
    for name in ['sources.json', 'collections.json']:
        shutil.copyfile(here / name, args.output / name)
    for name in ['Swift-Foundation.txt', 'Swift-Collections.txt']:
        shutil.copyfile(here.parents[4] / 'LICENSES' / name, args.output / name)
    print(json.dumps({'revision': manifest['revision'], 'source_files': len(verified),
                      'output': str(args.output), 'scope': 'No Data edits or execution'}))


if __name__ == '__main__':
    main()
