#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Assemble QuickTime Player's private library prefix.

  qt_prefix.py --out PREFIX --root ROOT --additions DIR [--stage TREE ...] [--framework X.framework ...]
               [--copy-under] [--macho DIR]

PREFIX gets System/Library/{Frameworks,PrivateFrameworks} and usr/lib, to be found through
DYLD_FRAMEWORK_PATH and DYLD_LIBRARY_PATH by one process. Nothing outside PREFIX is written.

  --stage      a tree with System/Library/... or usr/lib (the staged providers), copied in order
  --framework  a single framework directory, copied to System/Library/Frameworks
  --additions  the output directory of additions.nix (manifest.json and one library per
               framework). Each library goes where programs load that framework from, and
               the image it stands in front of becomes "<Name>.sf-under" beside it:
                 - a staged framework already in PREFIX is renamed;
                 - otherwise the system's own image under ROOT is linked (ROOT "/" on the
                   machine: a symbolic link, so the process still loads the system's file
                   and only once) or, with --copy-under, copied (for a scan of a root copy).
  --macho      directory of hb_macho.py; with it, names that an additions library and the
               image under it both export are reported (the system gained them: rebuild
               additions.nix with those names in `omit`). A class defined twice is an error.
Prints a JSON report; exit status 1 if a framework to stand in front of is missing or a
class is defined twice.
"""
import argparse
import json
import os
import shutil
import sys
from pathlib import Path

FRAMEWORK_DIRS = ('System/Library/Frameworks', 'System/Library/PrivateFrameworks')


def copy_tree(source, target):
    for directory, _dirs, files in os.walk(source):
        relative = Path(directory).relative_to(source)
        (target / relative).mkdir(parents=True, exist_ok=True)
        for entry in list(_dirs) + files:
            s, t = Path(directory) / entry, target / relative / entry
            if s.is_symlink():
                if t.is_symlink() or t.exists():
                    t.unlink()
                os.symlink(os.readlink(s), t)
            elif s.is_file():
                if t.exists() or t.is_symlink():
                    t.unlink()
                shutil.copyfile(s, t)
                t.chmod(0o755)
    # symbolic links to directories are entries of _dirs above and are not descended into


def mirror_links(root_framework, prefix_framework):
    """Recreate the framework's symbolic links (Versions/Current, Versions/C -> A, top-level
    names) so that every path the system offers for it exists in the prefix too."""
    for directory, dirs, files in os.walk(root_framework):
        relative = Path(directory).relative_to(root_framework)
        if len(relative.parts) > 2:
            dirs[:] = []
            continue
        for entry in list(dirs) + files:
            s = Path(directory) / entry
            t = prefix_framework / relative / entry
            if s.is_symlink() and not (t.exists() or t.is_symlink()):
                t.parent.mkdir(parents=True, exist_ok=True)
                os.symlink(os.readlink(s), t)
        dirs[:] = [d for d in dirs if not (Path(directory) / d).is_symlink()]


def exports(path, find, hb_macho, seen=None):
    seen = set() if seen is None else seen
    real = os.path.realpath(path)
    if real in seen or not os.path.isfile(real):
        return set()
    seen.add(real)
    image = hb_macho.load(real, prefer='arm64')
    own, individually = image.exported()
    out = set(own) | set(individually)
    for lib in image.dylibs:
        if lib['kind'] == 'reexport':
            name = lib['name']
            target = os.path.join(os.path.dirname(real), name[len('@loader_path/'):]) if name.startswith('@loader_path/') else find(name)
            if target:
                out |= exports(target, find, hb_macho, seen)
    return out


def assemble(out, root, additions, stages=(), frameworks=(), copy_under=False, hb_macho=None):
    out, root, additions = Path(os.path.abspath(out)), Path(os.path.abspath(root)), Path(additions)
    if out.exists():
        raise SystemExit(f'{out} exists: a fresh prefix is required')
    for d in FRAMEWORK_DIRS:
        (out / d).mkdir(parents=True)
    for stage in stages:
        for sub in FRAMEWORK_DIRS + ('usr/lib',):
            if (Path(stage) / sub).is_dir():
                copy_tree(Path(stage) / sub, out / sub)
    for framework in frameworks:
        copy_tree(Path(framework), out / FRAMEWORK_DIRS[0] / Path(framework).name)

    def find(install):
        for base in (out, root):
            p = base / install.lstrip('/')
            if p.exists():
                return str(p)
        return None

    report = {'prefix': str(out), 'root': str(root), 'libraries': [], 'problems': []}
    for entry in json.loads((additions / 'manifest.json').read_text()):
        name, load_path = entry['name'], entry['load_path'].lstrip('/')
        row = {'name': name, 'load_path': '/' + load_path}
        staged, system = out / load_path, root / load_path
        if staged.exists():
            place = staged.resolve()
            under = place.with_name(name + '.sf-under')
            place.rename(under)
            row['under'] = 'staged provider'
        elif system.exists():
            real = system.resolve()
            framework_root = next(p for p in [system, *system.parents] if p.name.endswith('.framework'))
            prefix_framework = out / framework_root.relative_to(root)
            place = prefix_framework / real.relative_to(framework_root.resolve())
            place.parent.mkdir(parents=True, exist_ok=True)
            mirror_links(framework_root, prefix_framework)
            under = place.with_name(name + '.sf-under')
            if copy_under:
                shutil.copyfile(real, under)
                for sibling in real.parent.iterdir():
                    if sibling.is_file() and sibling.name.startswith(name + '.') and not (place.parent / sibling.name).exists():
                        shutil.copyfile(sibling, place.parent / sibling.name)
            else:
                os.symlink(real, under)
            row['under'] = str(real)
        else:
            report['problems'].append(f'{name}: neither a staged provider nor {system} exists')
            report['libraries'].append(row)
            continue
        shutil.copyfile(additions / name, place)
        place.chmod(0o755)
        # where the framework is also reachable through a link in another directory
        # (Versions/C/AppKit -> ../A/AppKit), "@loader_path" may be taken from that directory
        framework_dir = next(p for p in [place, *place.parents] if p.name.endswith('.framework'))
        for alias in framework_dir.rglob(name):
            if alias.is_symlink() and alias.parent.resolve() != place.parent and alias.resolve() == place:
                twin = alias.with_name(under.name)
                if not (twin.exists() or twin.is_symlink()):
                    os.symlink(os.path.relpath(under, alias.parent), twin)
        row['placed'] = str(place.relative_to(out))
        if not (out / load_path).exists():
            report['problems'].append(f'{name}: {load_path} does not resolve in the prefix after placing')
        if hb_macho is not None:
            mine, _ = hb_macho.load(str(place), prefer='arm64').exported()
            shadowed = sorted(mine & exports(str(under), find, hb_macho))
            row['adds'] = len(mine)
            row['already_in_system'] = shadowed
            report['problems'] += [f'{name}: class defined twice: {s}' for s in shadowed if s.startswith('_OBJC_CLASS_$_')]
        report['libraries'].append(row)
    report['environment'] = {
        'DYLD_FRAMEWORK_PATH': f'{out}/System/Library/PrivateFrameworks:{out}/System/Library/Frameworks',
        'DYLD_LIBRARY_PATH': f'{out}/usr/lib/swift',
    }
    return report


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--out', required=True)
    ap.add_argument('--root', required=True)
    ap.add_argument('--additions', required=True)
    ap.add_argument('--stage', action='append', default=[])
    ap.add_argument('--framework', action='append', default=[])
    ap.add_argument('--copy-under', action='store_true')
    ap.add_argument('--macho')
    args = ap.parse_args(argv)
    hb_macho = None
    if args.macho:
        sys.path.insert(0, args.macho)
        import hb_macho
    report = assemble(args.out, args.root, args.additions, args.stage, args.framework, args.copy_under, hb_macho)
    print(json.dumps(report, indent=1))
    return 1 if report['problems'] else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
