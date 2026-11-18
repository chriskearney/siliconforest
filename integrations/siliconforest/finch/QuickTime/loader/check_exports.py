#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Does a staged root export every symbol a program binds from the listed libraries?

  check_exports.py --imports imports.json --root STAGE [--under TREE ...] --macho DIR

imports.json maps an install name to the symbol names bound from it (or is a per-symbol
table: {"symbols": [{"library", "symbol", "kind", "note"}, ...]}). Each library is read
at ROOT + install name; an umbrella's re-exported libraries are followed through ROOT and
the --under trees. Exit status 1 if a library is absent, has an install name other than
its path or "<path>.sf-additions", is not arm64, or lacks a symbol. This predicts dyld's verdict for these libraries; it runs nothing.
--macho is the directory holding hb_macho.py (integrations/siliconforest/homebrew).
"""
import argparse
import json
import os
import sys
from pathlib import Path


ADDITIONS_SUFFIX = '.sf-additions'


ADDITIONS_PROVIDERS = ('QuickTime additions', 'staged AVKit')


def load_imports(path, provided=None):
    """{install name: [symbol, ...]} with the comment entry dropped; raises on a malformed file.
    provided (per-symbol table only): 'additions' keeps the rows the QuickTime prefix supplies,
    'frameworks' the rows the frameworks themselves supply; None keeps all."""
    data = json.loads(Path(path).read_text())
    out = {}
    if isinstance(data.get('symbols'), list):       # the per-symbol table form (additions/symbols.json)
        kinds = {'real', 'constant', 'model', 'absence'}
        for row in data['symbols']:
            if not {'library', 'symbol', 'kind', 'note'} <= set(row) <= {'library', 'symbol', 'kind', 'note', 'provided_by'} \
                    or row['kind'] not in kinds or not row['note']:
                raise ValueError(f'{path}: bad row {row!r}')
            by = row.get('provided_by', ADDITIONS_PROVIDERS[0])
            ours = by.startswith(ADDITIONS_PROVIDERS)
            if (provided == 'additions' and not ours) or (provided == 'frameworks' and ours):
                continue
            if not row['library'].startswith('/') or not row['symbol'].startswith('_'):
                raise ValueError(f'{path}: bad library or symbol in {row!r}')
            out.setdefault(row['library'], []).append(row['symbol'])
        for key, value in out.items():
            if len(set(value)) != len(value):
                raise ValueError(f'{path}: a symbol of {key} is listed twice')
            value.sort()
        return out
    for key, value in data.items():
        if key == 'comment':
            continue
        if not key.startswith('/') or not isinstance(value, list) or not all(isinstance(s, str) and s.startswith('_') for s in value):
            raise ValueError(f'{path}: {key!r} must be an install name mapped to a list of symbol names')
        if sorted(set(value)) != value:
            raise ValueError(f'{path}: the symbols of {key} must be sorted and unique')
        out[key] = value
    return out


def exports_of(install, find, load, seen=None):
    """Every symbol the library at `install` offers: its own and its re-exported libraries'.
    find(install name) -> path or None; load(path) -> an object with id, dylibs, exported()."""
    seen = set() if seen is None else seen
    if install in seen:
        return set()
    seen.add(install)
    path = find(install)
    if path is None:
        return set()
    image = load(path)
    own, individually = image.exported()
    symbols = set(own) | set(individually)
    for lib in image.dylibs:
        if lib['kind'] == 'reexport':
            symbols |= exports_of(lib['name'], find, load, seen)
    return symbols


def check(imports, find, load, resolved=lambda install: install):
    """[problem, ...] (empty when every library is present and exports all it must) and
    {install name: (needed, found)}. resolved(install name): the install path the file found
    there has through version links (Versions/C/AppKit -> Versions/A/AppKit), also accepted."""
    problems, counts = [], {}
    for install, needed in imports.items():
        path = find(install)
        if path is None:
            problems.append(f'{install}: not in the root')
            counts[install] = (len(needed), 0)
            continue
        image = load(path)
        # A library is found by path; its install name is the path (a framework the system does not
        # have) or "<path>.sf-additions" (an additions library: it must not repeat the install name of
        # the system image it re-exports, which dyld would fold onto it).
        if not image.id or image.id['name'] not in (install, install + ADDITIONS_SUFFIX, resolved(install)):
            problems.append(f'{install}: the file there has install name {image.id and image.id["name"]}')
        if not getattr(image, 'arm64', True):
            problems.append(f'{install}: not an arm64 image')
        have = exports_of(install, find, load)
        lacking = [s for s in needed if s not in have]
        counts[install] = (len(needed), len(needed) - len(lacking))
        problems += [f'{install}: does not export {s}' for s in lacking]
    return problems, counts


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--imports', required=True)
    ap.add_argument('--root', required=True)
    ap.add_argument('--under', action='append', default=[])
    ap.add_argument('--macho', required=True)
    ap.add_argument('--provided', choices=('additions', 'frameworks'), help='per-symbol table: check only the rows the prefix (or the frameworks) supply')
    args = ap.parse_args(argv)
    sys.path.insert(0, args.macho)
    import hb_macho

    trees = [Path(args.root), *map(Path, args.under)]

    def find(install):
        for tree in trees:
            p = tree / install.lstrip('/')
            if p.is_file():
                return p
        return None

    def load(path):
        image = hb_macho.load(str(path), prefer='arm64')
        image.arm64 = image.cputype == hb_macho.CPU_ARM64
        return image

    def resolved(install):
        for tree in trees:
            p = tree / install.lstrip('/')
            if p.is_file():
                return '/' + str(Path(os.path.realpath(p)).relative_to(os.path.realpath(tree)))
        return install

    problems, counts = check(load_imports(args.imports, args.provided), find, load, resolved)
    for install, (needed, found) in counts.items():
        print(f'{found:3} of {needed:3}  {install}')
    for p in problems:
        print('MISSING', p)
    print('LOADER_CHECK', 'FAIL' if problems else 'PASS', f'{sum(f for _n, f in counts.values())} of {sum(n for n, _f in counts.values())} symbols')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
