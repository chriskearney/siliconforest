#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""The kernel protection receipt of a J313 G2 packet, derived from the real build. Offline.

The guest launcher (m1-bringup/host_progress.py, configure_kernel_text_policy) starts a kernel only if
the packet's build record says, in components.native_kernel.development_protection_configuration,
that the kernel was built without CTRR, the PPL monitor and PMAP_CS. The first G2 packet had no such
receipt, so the launcher stopped before the kernel ran (23 November 2026).

Nothing here is copied from another packet or typed in. Every field is checked against the build:

  1. the collection's derivation names exactly one SiliconForest T8103 kernel derivation,
  2. that derivation's configure phase selects the DEVELOPMENT configuration,
  3. its patch list contains this repository's bring-up patch byte for byte, and that patch both
     defines DARWIN_LAB_M1_BRINGUP=1 for T8103 and, in board_config.h, undefines
     KERNEL_INTEGRITY_CTRR and leaves PMAP_CS, PMAP_CS_ENABLE and XNU_MONITOR undefined under it,
  4. the built kernel's symbol table has none of the CTRR lockdown, PPL or PMAP_CS implementation
     symbols, and does have ml_unsafe_kernel_text, which the receipt's boot property feeds.

  protection_receipt.py show --collection <kc store path>
  protection_receipt.py repack --collection <kc store path> --packet <packet-001> --out <packet-002>

`repack` copies the kernel, RAM root and source note unchanged, adds the receipt to the build record
and writes a new manifest. Pin the new manifest hash in g2-pins.json.
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
import subprocess

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
BRINGUP_PATCH = REPO / 'integrations/siliconforest/m1-bringup/kernel-patches-tip/0001-xnu-m1-bringup-on-upstream-t8103.patch'
KERNEL_DRV = re.compile(r'/nix/store/[0-9a-z]{32}-siliconforest-kernel-arm64-t8103-siliconforest-0\.1\.drv')
OMITTED = ['KERNEL_INTEGRITY_CTRR', 'XNU_MONITOR', 'PMAP_CS', 'PMAP_CS_ENABLE']
# Present only when the selector is built in (xnu osfmk/arm64: rorgn for CTRR lockdown, the PPL
# dispatch and trampolines for XNU_MONITOR, pmap_cs_* for PMAP_CS).
FORBIDDEN_SYMBOLS = re.compile(r'^_(rorgn_\w+|ppl_handler_table|ppl_trampoline_\w+|ppl_bootstrap_dispatch|'
                               r'ppl_dispatch_\w+|pmap_ppl_\w+|pmap_cs_\w+)$')
REQUIRED_SYMBOLS = ('_ml_unsafe_kernel_text', '_ml_unsafe_kernel_text_init')


def sha(path):
    with open(path, 'rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def need(condition, message):
    if not condition:
        raise SystemExit('REFUSED: ' + message)


def nix_store(*args):
    tool = shutil.which('nix-store') or str(Path.home() / '.nix-profile/bin/nix-store')
    return subprocess.check_output([tool, *args], text=True).strip()


def patch_selects_unprotected(text):
    """The bring-up patch's own lines: the macro is set for T8103 and gates all four selectors."""
    need('-DDARWIN_LAB_M1_BRINGUP=1' in next((l for l in text.splitlines()
                                              if l.startswith('+MACHINE_FLAGS_ARM64_T8103')), ''),
         'the bring-up patch no longer defines DARWIN_LAB_M1_BRINGUP for T8103')
    start = text.index('pexpert/pexpert/arm64/board_config.h\n')
    hunk = text[start:text.index('\ndiff --git', start) if '\ndiff --git' in text[start:] else None]
    need(re.search(r'^\+#if DARWIN_LAB_M1_BRINGUP\n(?:\+.*\n)*?\+#undef KERNEL_INTEGRITY_CTRR\n\+#endif$', hunk, re.M),
         'board_config.h no longer undefines KERNEL_INTEGRITY_CTRR under DARWIN_LAB_M1_BRINGUP')
    guard = re.search(r'^\+#if (.*&& !DARWIN_LAB_M1_BRINGUP)\n #define PMAP_CS +1\n #define PMAP_CS_ENABLE +1\n'
                      r' #define XNU_MONITOR +1', hunk, re.M)
    need(guard, 'board_config.h no longer keeps PMAP_CS, PMAP_CS_ENABLE and XNU_MONITOR out of the bring-up build')
    return guard[1]


def kernel_symbols(path):
    nm = shutil.which('llvm-nm')
    need(nm, 'llvm-nm is needed to read the kernel symbol table')
    out = subprocess.check_output([nm, '--defined-only', '-j', str(path)], text=True)
    return set(out.split())


def derive(collection):
    collection = Path(collection).resolve()
    need(re.fullmatch(r'/nix/store/[0-9a-z]{32}-[\w.+?=-]+', str(collection)) is not None, 'collection is not a store path')
    deriver = nix_store('-q', '--deriver', str(collection))
    need(deriver.endswith('.drv'), 'no derivation recorded for the collection')
    kernels = [r for r in nix_store('-q', '--references', deriver).split() if KERNEL_DRV.fullmatch(r)]
    need(len(kernels) == 1, f'expected one SiliconForest T8103 kernel derivation, found {len(kernels)}')
    kernel_drv = kernels[0]
    configure = nix_store('-q', '--binding', 'configurePhase', kernel_drv)
    configs = set(re.findall(r'-DSILICONFOREST_XNU_KERNEL_CONFIG=([A-Z]+)', configure))
    need(configs == {'DEVELOPMENT'}, f'kernel configuration is {sorted(configs)}, not DEVELOPMENT')
    patches = nix_store('-q', '--binding', 'patches', kernel_drv).split()
    bringup = [p for p in patches if p.endswith('-' + BRINGUP_PATCH.name)]
    need(len(bringup) == 1 and sha(bringup[0]) == sha(BRINGUP_PATCH),
         'the kernel was not built with this repository\'s bring-up patch')
    guard = patch_selects_unprotected(BRINGUP_PATCH.read_text())
    output = nix_store('-q', '--outputs', kernel_drv).split()
    need(len(output) == 1, 'kernel derivation has more than one output')
    binary = Path(output[0]) / 'System/Library/Kernels/kernel.development.t8103'
    need(binary.is_file(), 'built kernel not found (is the kernel output in the store?)')
    symbols = kernel_symbols(binary)
    found = sorted(s for s in symbols if FORBIDDEN_SYMBOLS.match(s))
    need(not found, 'the built kernel has protection implementation symbols: ' + ', '.join(found[:8]))
    need(all(s in symbols for s in REQUIRED_SYMBOLS), 'the built kernel has no ml_unsafe_kernel_text')
    return {
        'scope': 'single-CPU M1 development guest under m1n1 HV',
        'native_hardware_facts_retained': ['HAS_CTRR', 'USE_APPLEARMSMP', 'HAS_IPI', 'HAS_CLUSTER'],
        'implementation_selectors_omitted': list(OMITTED),
        'reason': 'public source lacks private CTRR backend headers and CoreEntitlementsV2 by-value interface; '
                  'no synthetic lock-regs or success stubs',
        'kernel_text_hardware_locked': False,
        'PPL_protection_claimed': False,
        'unsafe_kernel_text_boot_arg_used': False,
        'source_contract': 'integrations/puredarwin/m1-bringup/CONTRACT.md',
        'derived_from_build': {
            'tool': 'integrations/siliconforest/m1-j313-g2/launcher/protection_receipt.py',
            'collection': str(collection), 'collection_drv': deriver,
            'kernel_drv': kernel_drv, 'kernel_config': 'DEVELOPMENT',
            'kernel_binary_sha256': sha(binary),
            'bringup_patch': BRINGUP_PATCH.relative_to(REPO).as_posix(),
            'bringup_patch_sha256': sha(BRINGUP_PATCH),
            'board_config_guard': '#if ' + guard,
            'symbols_absent': FORBIDDEN_SYMBOLS.pattern,
            'symbols_present': list(REQUIRED_SYMBOLS),
            'symbol_count': len(symbols),
        },
    }


def write_json(path, value):
    with open(path, 'x') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')


def repack(collection, packet, out):
    need(not out.exists(), '--out already exists')
    manifest = json.loads((packet / 'manifest.json').read_text())
    for name, item in manifest['artifacts'].items():
        need(sha(packet / item['path']) == item['sha256'], f'source packet {name} does not match its manifest')
    record = json.loads((packet / 'build-record.json').read_text())
    need(record.get('kernel_sha256') == manifest['artifacts']['kernel']['sha256'], 'record and manifest disagree')
    need(record.get('output_path') == str(Path(collection).resolve()), 'the packet was not built from this collection')
    receipt = derive(collection)
    record.setdefault('components', {}).setdefault('native_kernel', {})['development_protection_configuration'] = receipt
    record['receipt_added_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    record['receipt_added_to'] = packet.name
    out.mkdir(mode=0o700, parents=True)
    for name in ('kernel.macho', 'ramdisk.img', 'ramdisk.record.json', 'source.patch', 'mapping.json'):
        if (packet / name).exists():
            shutil.copy2(packet / name, out / name)
            os.chmod(out / name, 0o600)
    write_json(out / 'build-record.json', record)
    artifacts = dict(manifest['artifacts'])
    artifacts['build_record'] = {'path': 'build-record.json', 'sha256': sha(out / 'build-record.json'),
                                 'bytes': (out / 'build-record.json').stat().st_size}
    for name, item in artifacts.items():
        need(sha(out / item['path']) == item['sha256'], f'{name} changed while copying')
    write_json(out / 'manifest.json', {**manifest, 'artifacts': artifacts})
    return dict(packet=str(out), manifest_sha256=sha(out / 'manifest.json'),
                build_record_sha256=artifacts['build_record']['sha256'],
                kernel_sha256=artifacts['kernel']['sha256'], ramdisk_sha256=artifacts['ramdisk']['sha256'])


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('command', choices=('show', 'repack'))
    parser.add_argument('--collection', type=Path, required=True)
    parser.add_argument('--packet', type=Path)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    if args.command == 'show':
        print(json.dumps(derive(args.collection), indent=2))
    else:
        need(args.packet and args.out, 'repack needs --packet and --out')
        print(json.dumps(repack(args.collection, args.packet, args.out), indent=2))


if __name__ == '__main__':
    main()
