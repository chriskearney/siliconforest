#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Generate the J313 launcher tree from the frozen J293 launcher tree. Offline; touches no device.

The base tree stays as it is. Each change below is an exact text replacement with an expected
count, so a change in the base tree stops the generator rather than producing a different tool.
Hash pins that name a changed file are then rewritten to the new hashes. The board checks stay:
they now require J313 and refuse J293.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys

HERE = Path(__file__).resolve().parent
BOOTSTRAP = 'integrations/m1-boot-window/bootstrap.py'
BOOTSTRAP_PROGRESS = 'integrations/puredarwin/m1-bringup/bootstrap_progress.py'
HOST_CONSOLE = 'integrations/puredarwin/m1-firstboot/host_console.py'
HOST_PROGRESS = 'integrations/puredarwin/m1-bringup/host_progress.py'
NORMAL_IMAGE = 'integrations/puredarwin/m1-bringup/normal_image.py'
PREFLIGHT = 'tools/m1_proxy_preflight.py'
KERNEL_CYCLE = 'tools/m1_kernel_cycle.py'
BRINGUP_CYCLE = 'tools/m1_bringup_cycle.py'

PRO_WINDOW_RAW = 'ba5bf4b396168ac540df852e3507c4342dd289eef7bf2c1fc29c50f11f0822bf'
J313_WINDOW_RAW = 'a5bbd1430acc0fa0c44f9ff1ebed79f3ca5af12c0af7fee117d79f5df8b7c5e9'
PRO_LOADER = 'e4ead838bb87a04dd00909edf8a598f813056ee2f9611777a4a77c4bf7351e27'
J313_LOADER = 'c688793a85af45b1a71254798da10f56c4f861584b1dc1e606b559f964f5664c'
TIP_COMMIT = 'cd001928e0223fd77a7850f09e43580b51bde239'
PIN_COMMIT = 'e7aa00a60f0b56ef35aa24252e81467787bf71ea'

BOARD = [("'J293' and tree.model == 'MacBookPro17,1'", "'J313' and tree.model == 'MacBookAir10,1'", 1)]
BOARD_DOUBLE = [('"J293" and tree.model == "MacBookPro17,1"', '"J313" and tree.model == "MacBookAir10,1"', 1)]
WINDOW = [('-darwin-lab-j293-window-v1', '-darwin-lab-j313-window-v1', 1),
          (PRO_WINDOW_RAW, J313_WINDOW_RAW, 1),
          ('CONFIRMATION = "J293_RECOVERY_READY"', 'CONFIRMATION = "J313_RECOVERY_READY"', 1)]

EDITS = {
    BOOTSTRAP: BOARD_DOUBLE + WINDOW,
    BOOTSTRAP_PROGRESS: BOARD_DOUBLE + WINDOW,
    HOST_CONSOLE: BOARD + [
        ("{'apple,j293', 'apple,t8103'}", "{'apple,j313', 'apple,t8103'}", 1),
        ("'Saved Linux inventory is not J293/T8103'", "'Saved Linux inventory is not J313/T8103'", 1),
        ("'J293 launcher requires an already working USB0/USB1 proxy'",
         "'J313 launcher requires an already working USB0/USB1 proxy'", 1),
        ("CONFIRMATION = 'J293_RECOVERY_READY'", "CONFIRMATION = 'J313_RECOVERY_READY'", 1),
    ],
    HOST_PROGRESS: BOARD + [
        ("'J293 launcher requires an already working USB0/USB1 proxy'",
         "'J313 launcher requires an already working USB0/USB1 proxy'", 1),
        ('pdtextboot=1', 'sftextboot=1', 1),
        ("' pdm1kbd=1'", "' sfm1kbd=1'", 1),
        ("' pddartsurvey=1'", "' sfdartsurvey=1'", 1),
        ("' pdm1trackpadenum=1'", "' sfm1trackpadenum=1'", 1),
        ("' pdm1trackpadchild=1'", "' sfm1trackpadchild=1'", 1),
        ("' pdapciebridge=1'", "' sfapciebridge=1'", 1),
    ],
    NORMAL_IMAGE: [("doc.get('target') == 'm1-mbp13-j293'", "doc.get('target') == 'm1-mba13-j313'", 1),
                   (f"'puredarwin': '{PIN_COMMIT}'", f"'puredarwin': '{TIP_COMMIT}'", 1)],
    PREFLIGHT: [("if target != 'J293':", "if target != 'J313':", 1),
                ("'product.target_type is not J293'", "'product.target_type is not J313'", 1),
                ("if model != 'MacBookPro17,1':", "if model != 'MacBookAir10,1':", 1),
                ("'product.model is not MacBookPro17,1'", "'product.model is not MacBookAir10,1'", 1),
                ("for required in ('apple,j293', 'apple,t8103'):", "for required in ('apple,j313', 'apple,t8103'):", 1)],
    KERNEL_CYCLE: [("{'apple,j293', 'apple,t8103'}", "{'apple,j313', 'apple,t8103'}", 1),
                   ("CONFIRMATION = 'J293_RECOVERY_READY'", "CONFIRMATION = 'J313_RECOVERY_READY'", 1),
                   (f"LOADER_SHA = '{PRO_LOADER}'", f"LOADER_SHA = '{J313_LOADER}'", 1)],
}
# Editor and history copies in the base tree are not part of the J313 tree.
DROPPED = re.compile(r'(\.orig-debug-only|\.before-tip-[0-9]+)$')
MODES = {'cpufreq_mode.txt': 'on', 'dcp_probe_mode.txt': 'off', 'gpu_probe_mode.txt': 'off',
         'pcie_linkup_mode.txt': 'none', 'done_mode.txt': 'marker', 'time_wait_mode.txt': 'off',
         'usb_chunk_mode.txt': 'off'}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def rename_members(text):
    """The collection's names since the SiliconForest rename (docs/design/siliconforest-naming.md)."""
    text = re.sub(r'org\.puredarwin\.(driver|kext|iokit|filesystems)\.(PD)?([A-Za-z0-9]+)',
                  lambda m: f"org.siliconforest.{m[1]}.{'SF' if m[2] else ''}{m[3]}", text)
    text = text.replace("startswith('org.puredarwin.')", "startswith('org.siliconforest.')")
    for old, new in (('PDM1', 'SFM1'), ('PDApcieT8103Bridge', 'SFApcieT8103Bridge'),
                     ('PDDARTSurvey', 'SFDARTSurvey'), ('PDBwfm', 'SFBwfm'), ('PDRustHello', 'SFRustHello'),
                     ('PDSerialHID', 'SFSerialHID'), ('pdhid', 'sfhid')):
        text = text.replace(old, new)
    return text


def generate(base, out, extra_args, cycle):
    base = base.resolve(strict=True)
    if out.exists():
        raise SystemExit('REFUSED: --out already exists')
    files = {}
    for path in sorted(base.rglob('*')):
        rel = path.relative_to(base).as_posix()
        if path.is_symlink():
            raise SystemExit('REFUSED: symbolic link in the base tree: ' + rel)
        if path.is_file() and '__pycache__' not in rel and not DROPPED.search(rel):
            files[rel] = path.read_bytes()
    base_hashes = {rel: sha(data) for rel, data in files.items()}
    for rel, edits in EDITS.items():
        text = files[rel].decode()
        for old, new, count in edits:
            found = text.count(old)
            if found == 0 or (count is not None and found != count):
                raise SystemExit(f'REFUSED: {rel}: expected {count} of {old!r}, found {found}')
            text = text.replace(old, new)
        if rel == HOST_PROGRESS:
            text = rename_members(text)
        if rel == KERNEL_CYCLE:
            # The Pro's address leaves this tree: the M5 never connects to the Air's Linux.
            text, found = re.subn(r"^HOST = '[0-9.]+'$", "HOST = 'air-is-reached-from-the-builder-only.invalid'",
                                  text, flags=re.M)
            if found != 1:
                raise SystemExit('REFUSED: the controller address line changed')
        files[rel] = text.encode()

    # Rewrite hash pins until no file names an old hash of a changed file.
    current = dict(base_hashes)
    changed = {}
    for _ in range(12):
        moved = {current[rel]: sha(data) for rel, data in files.items() if sha(data) != current[rel]}
        if not moved:
            break
        changed.update(moved)
        for rel in files:
            current[rel] = sha(files[rel])
        for rel in list(files):
            if not rel.endswith('.py'):
                continue
            text = files[rel].decode()
            updated = text
            for old, new in changed.items():
                updated = updated.replace(old, current_value(changed, new))
            files[rel] = updated.encode()
    else:
        raise SystemExit('REFUSED: hash pins did not converge')

    leftovers = {}
    for rel in EDITS:
        text = files[rel].decode()
        names = re.findall(r"org\.puredarwin\.[A-Za-z.0-9]+", text)
        if names:
            leftovers[rel] = sorted(set(names))
    if leftovers:
        raise SystemExit('REFUSED: old member names remain: ' + json.dumps(leftovers))

    files['tools/j313_cycle.py'] = cycle.read_bytes()
    prefix = 'integrations/puredarwin/m1-bringup/'
    files[prefix + 'extra_bootargs.txt'] = (extra_args + '\n').encode()
    for name, value in MODES.items():
        files[prefix + name] = (value + '\n').encode()

    out.mkdir(parents=True, mode=0o700)
    for rel, data in files.items():
        destination = out / rel
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        source = base / rel
        if source.exists() and source.stat().st_mode & 0o111:
            destination.chmod(0o755)
    return {
        'base_files': len(base_hashes), 'files': len(files),
        'edited': sorted(EDITS),
        'launcher_sha256': sha(files[HOST_PROGRESS]),
        'inspector_sha256': sha(files[NORMAL_IMAGE]),
        'tree_sha256': sha(json.dumps({rel: sha(data) for rel, data in sorted(files.items())},
                                      sort_keys=True).encode()),
    }


def current_value(changed, value):
    seen = set()
    while value in changed and value not in seen:
        seen.add(value)
        value = changed[value]
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', type=Path, required=True, help='the frozen launcher tree (read only)')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--extra-bootargs', required=True)
    args = parser.parse_args()
    print(json.dumps(generate(args.base, args.out, args.extra_bootargs, HERE / 'j313_cycle.py'), indent=2))


if __name__ == '__main__':
    sys.exit(main())
