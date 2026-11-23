#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Build the J313 proxy-window stage 2 from the pinned source. Offline; touches no device.

The build copies the J293 window source into a private directory, builds the J293 image as a
control (it must reproduce the image that ran on the Pro), applies j313-window.patch, builds the
J313 image, and appends the Air's own payloads (device trees and U-Boot) unchanged. The result
and its receipt go to --out. The Air's stage 2 is read from --original and never written.

The J313 tag changes the merged string table, so string references move. compare() checks each
difference from the control: the only code change is the two board-identity compares, and every
other changed instruction or relocation must still refer to the same string.
"""
from __future__ import annotations

import argparse
import collections
import gzip
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
import zlib

HERE = Path(__file__).resolve().parent
PIN = '121fcbf35d4501814b58ca5347926a4173b6a512'
J293_TAG = PIN + '-darwin-lab-j293-window-v1'
J313_TAG = PIN + '-darwin-lab-j313-window-v1'
J293_RAW_SHA = 'ba5bf4b396168ac540df852e3507c4342dd289eef7bf2c1fc29c50f11f0822bf'
ORIGINAL_SHA = '54fa07e4f5cbeecd90e67e335657c40b33c25aede7015a84afb1427333b4f923'
ORIGINAL_BYTES = 10107602
PAYLOAD_OFFSET = 0x400000
RAW_BYTES = 4325376
WINDOW_FILES = {
    'Makefile': '7110933cebd76507656d752104cab30196a4e2664c2cc2df3a0ebd4a3494d103',
    'src/main.c': 'c40920d8ba715736f41022cde2255a3361cab8a26517ff6a680ed737d5d3f266',
    'src/uartproxy.c': 'b842794d10dd16813c2c68ccfcbd0260a0363e9f199206603cf02cc43cbf783e',
    'src/uartproxy.h': '1121de61b3cff9f11b883f2ca9a2595683e9b44caaee7a2794693af8f672f7d6',
    'src/m1_boot_window.c': 'e293b9355bbbba41f7ab59bc799e37c1e0beef5ba59cff15e718b92cac06e454',
    'src/m1_boot_window.h': 'f05a597ec3733065a4e886af35cbb2401fbb4afdfef465ce94e4e8d5ffb55a95',
}
TOOLS = {'clang': 'clang version 22.1.8', 'ld.lld': 'LLD 22.1.8 (compatible with GNU linkers)',
         'rustc': 'rustc 1.98.1 (48a229cea 2026-09-01)', 'cargo': 'cargo 1.98.1 (797e8a9bc 2026-08-05)',
         'make': 'GNU Make 4.4.1'}
BUILD = ['make', '-j8', 'USE_CLANG=1', 'CHAINLOADING=1', 'ESP_STAGE2=1', 'M1_BOOT_WINDOW=1',
         'CARGO_FLAGS=--locked --offline --features chainload', 'V=1']
# Text that legitimately differs between the two images.
STRING_CHANGES = {
    J293_TAG.encode(): J313_TAG.encode(),
    b'##m1n1_ver##' + J293_TAG.encode(): b'##m1n1_ver##' + J313_TAG.encode(),
    b'chosen.asahi,m1n1-stage1-version=' + J293_TAG.encode():
        b'chosen.asahi,m1n1-stage1-version=' + J313_TAG.encode(),
    b'J293 CDC window expired; checking original payloads\n':
        b'J313 CDC window expired; checking original payloads\n',
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def need(condition, message):
    if not condition:
        raise SystemExit('REFUSED: ' + message)


def elf(path):
    data = Path(path).read_bytes()
    shoff = struct.unpack_from('<Q', data, 40)[0]
    entsize, count, names_index = struct.unpack_from('<HHH', data, 58)
    headers = [struct.unpack_from('<IIQQQQIIQQ', data, shoff + i * entsize) for i in range(count)]
    names = data[headers[names_index][4]:headers[names_index][4] + headers[names_index][5]]
    sections = {}
    for header in headers:
        name = names[header[0]:names.index(b'\0', header[0])].decode()
        sections[name] = dict(type=header[1], flags=header[2], addr=header[3], off=header[4], size=header[5])
    return data, sections


def section(image, name):
    data, sections = image
    item = sections[name]
    return data[item['off']:item['off'] + item['size']], item['addr']


def symbols(image):
    data, sections = image
    table = sections['.symtab']
    names = sections['.strtab']
    out = []
    for offset in range(table['off'], table['off'] + table['size'], 24):
        name, info, _, _, value, size = struct.unpack_from('<IBBHQQ', data, offset)
        if info & 0xf == 2 and size:
            end = data.index(b'\0', names['off'] + name)
            out.append((value, size, data[names['off'] + name:end].decode()))
    return sorted(out)


def c_string(blob, base, address):
    offset = address - base
    if not 0 <= offset < len(blob):
        return None
    end = blob.find(b'\0', offset)
    return blob[offset:end] if end >= 0 else None


def same_text(left, right):
    if left is None or right is None:
        return False
    if left == right:
        return True
    # A reference may point into the middle of a merged string, so compare on the known changes.
    for old, new in STRING_CHANGES.items():
        at = old.find(left)
        if at >= 0 and new[at:at + len(left)] == right:
            return True
    return False


def adrp_page(word, pc):
    immediate = ((word >> 29) & 3) | (((word >> 5) & 0x7ffff) << 2)
    if immediate & (1 << 20):
        immediate -= 1 << 21
    return (pc & ~0xfff) + (immediate << 12)


def adr_target(word, pc):
    immediate = ((word >> 29) & 3) | (((word >> 5) & 0x7ffff) << 2)
    if immediate & (1 << 20):
        immediate -= 1 << 21
    return pc + immediate


def compare(control_elf, candidate_elf):
    """Explain every difference between the control and the J313 image, or fail."""
    a, b = elf(control_elf), elf(candidate_elf)
    alloc = [name for name, item in a[1].items() if item['flags'] & 2 and item['type'] != 8]
    need(alloc == [name for name, item in b[1].items() if item['flags'] & 2 and item['type'] != 8],
         'allocated sections differ')
    layout = {}
    for name in alloc:
        x, y = a[1][name], b[1][name]
        need((x['addr'], x['size']) == (y['addr'], y['size']), 'section moved: ' + name)
        left, _ = section(a, name)
        right, _ = section(b, name)
        layout[name] = sum(1 for p, q in zip(left, right) if p != q)
    for name in ('.init', '.data', '.stack', '.stack_el3'):
        need(layout[name] == 0, 'unexpected change in ' + name)
    need(symbols(a) == symbols(b), 'function addresses or sizes differ')

    rodata_a, rodata_base = section(a, '.rodata')
    rodata_b, _ = section(b, '.rodata')
    # The USB descriptors carry the tag twice as UTF-16; compare those copies as the J313 text.
    wide_old, wide_new = (name.encode('utf-16-le') for name in
                          ('darwin-lab-j293-window-v1', 'darwin-lab-j313-window-v1'))
    need(rodata_a.count(wide_old) == 2 and rodata_b.count(wide_new) == 2 and wide_old not in rodata_b,
         'unexpected UTF-16 copies of the version tag')
    left_strings = collections.Counter(rodata_a.replace(wide_old, wide_new).split(b'\0'))
    right_strings = collections.Counter(rodata_b.split(b'\0'))
    removed = left_strings - right_strings
    added = right_strings - left_strings
    translated = collections.Counter({STRING_CHANGES.get(key, key): count for key, count in removed.items()})
    need(translated == added, 'string table differs beyond the J313 identity strings')
    need(set(removed) <= set(STRING_CHANGES), 'unexpected removed string')

    text_a, text_base = section(a, '.text')
    text_b, _ = section(b, '.text')
    functions = symbols(a)
    allowed = next(item for item in functions if item[2] == 'm1_boot_window_allowed')
    pages_a, pages_b = {}, {}
    identity, adrp, resolved = [], 0, 0
    unused = {}
    current = None
    index = 0
    def use_page(rn, pc):
        for key in [key for key in unused if key[1] == rn and key[0] < pc]:
            del unused[key]

    for offset in range(0, len(text_a) - 3, 4):
        pc = text_base + offset
        while index < len(functions) and functions[index][0] + functions[index][1] <= pc:
            index += 1
        function = functions[index][2] if index < len(functions) and functions[index][0] <= pc else None
        if function != current:
            current, pages_a, pages_b = function, {}, {}
        x = struct.unpack_from('<I', text_a, offset)[0]
        y = struct.unpack_from('<I', text_b, offset)[0]
        if x & 0x9f000000 == 0x90000000 and y & 0x9f000000 == 0x90000000:
            need(x & 31 == y & 31, 'ADRP register changed')
            pages_a[x & 31], pages_b[y & 31] = adrp_page(x, pc), adrp_page(y, pc)
            if x != y:
                adrp += 1
                unused[(pc, x & 31)] = True
            continue
        rn = (x >> 5) & 31
        tracked = rn in pages_a and rn in pages_b
        if x != y and allowed[0] <= pc < allowed[0] + allowed[1]:
            identity.append((pc, x, y))
        elif x != y and x & 0x9f000000 == 0x10000000 and y & 0x9f000000 == 0x10000000:
            need(x & 31 == y & 31, f'ADR register changed at {pc:#x}')
            left = c_string(rodata_a, rodata_base, adr_target(x, pc))
            right = c_string(rodata_b, rodata_base, adr_target(y, pc))
            need(same_text(left, right), f'string reference changed at {pc:#x}: {left!r} {right!r}')
            resolved += 1
        elif x != y:
            need(x & 0xffc00000 == 0x91000000 and y & 0xffc00000 == 0x91000000 and x & 0x3ff == y & 0x3ff,
                 f'unexplained instruction change at {pc:#x}: {x:08x} {y:08x}')
            need(tracked, f'ADD without a known page at {pc:#x}')
            left = c_string(rodata_a, rodata_base, pages_a[rn] + ((x >> 10) & 0xfff))
            right = c_string(rodata_b, rodata_base, pages_b[rn] + ((y >> 10) & 0xfff))
            need(same_text(left, right), f'string reference changed at {pc:#x}: {left!r} {right!r}')
            use_page(rn, pc)
            resolved += 1
        elif tracked and pages_a[rn] != pages_b[rn]:
            # An unchanged low half on a changed page still has to reach the same data.
            if x & 0xffc00000 == 0x91000000:
                target = (x >> 10) & 0xfff
                left = c_string(rodata_a, rodata_base, pages_a[rn] + target)
                right = c_string(rodata_b, rodata_base, pages_b[rn] + target)
                need(same_text(left, right), f'string reference changed at {pc:#x}: {left!r} {right!r}')
                use_page(rn, pc)
                resolved += 1
            elif x & 0x3b000000 == 0x39000000 and x & (1 << 22):
                size = 1 << (x >> 30)
                target = pages_a[rn] + ((x >> 10) & 0xfff) * size - rodata_base
                other = pages_b[rn] + ((x >> 10) & 0xfff) * size - rodata_base
                need(rodata_a[target:target + size] == rodata_b[other:other + size] and
                     len(rodata_a[target:target + size]) == size, f'loaded constant changed at {pc:#x}')
                use_page(rn, pc)
                resolved += 1
        # Forget a page once its register is written. Calls clobber the argument registers.
        if x & 0xfc000000 == 0x94000000 or x & 0xfffffc1f == 0xd63f0000:
            for number in [*range(19), 30]:
                pages_a.pop(number, None)
                pages_b.pop(number, None)
        elif not (x & 0x3b000000 == 0x39000000 and not x & (1 << 22)):   # a store writes no register
            pages_a.pop(x & 31, None)
            pages_b.pop(x & 31, None)
    need(not unused, 'ADRP page change without a checked use: ' + str([hex(key[0]) for key in unused][:8]))
    expected = {(0x7100c91f, 0x7100cd1f), (0x7100e51f, 0x7100c51f)}
    need({(x, y) for _, x, y in identity} == expected and len(identity) == 2,
         'board-identity change is not exactly J293 to J313: ' +
         str([(hex(p), hex(x), hex(y)) for p, x, y in identity]))

    rela_a, _ = section(a, '.rela.dyn')
    rela_b, _ = section(b, '.rela.dyn')
    need(len(rela_a) == len(rela_b) and len(rela_a) % 24 == 0, 'relocation table size differs')
    relocations = 0
    for offset in range(0, len(rela_a), 24):
        p = struct.unpack_from('<QQq', rela_a, offset)
        q = struct.unpack_from('<QQq', rela_b, offset)
        need(p[:2] == q[:2], 'relocation target or type changed')
        if p[2] != q[2]:
            left = c_string(rodata_a, rodata_base, p[2])
            right = c_string(rodata_b, rodata_base, q[2])
            need(same_text(left, right), f'relocated string changed: {left!r} {right!r}')
            relocations += 1
    return dict(section_bytes_differing=layout, function_table_identical=True,
                board_identity_instructions_changed=[hex(p) for p, _, _ in identity],
                adrp_page_changes=adrp, add_references_resolved_to_same_string=resolved,
                pointer_relocations_resolved_to_same_string=relocations,
                strings_changed=sorted(item.decode(errors='replace').strip() for item in removed))


def dtb_compatible(blob):
    magic, size, off, strings, _, version, _, _, string_size, struct_size = struct.unpack_from('>10I', blob)
    need(magic == 0xd00dfeed and size == len(blob) and version >= 17, 'bad DTB')
    depth, end = 0, off + struct_size
    while off < end:
        token = struct.unpack_from('>I', blob, off)[0]
        off += 4
        if token == 1:
            off = (blob.index(b'\0', off, end) + 4) & ~3
            depth += 1
        elif token == 2:
            depth -= 1
        elif token == 3:
            length, nameoff = struct.unpack_from('>II', blob, off)
            off += 8
            name = blob[strings + nameoff:blob.index(b'\0', strings + nameoff, strings + string_size)]
            if depth == 1 and name == b'compatible':
                return blob[off:off + length].rstrip(b'\0').decode().split('\0')
            off = (off + length + 3) & ~3
        elif token == 9:
            break
        elif token != 4:
            raise SystemExit('REFUSED: bad DTB token')
    return []


def inspect_payload(trailer):
    offset, dtbs, j313 = 0, 0, []
    while trailer[offset:offset + 4] == b'\xd0\x0d\xfe\xed':
        length = struct.unpack_from('>I', trailer, offset + 4)[0]
        blob = trailer[offset:offset + length]
        compatible = dtb_compatible(blob)
        if 'apple,j313' in compatible:
            need('apple,t8103' in compatible, 'J313 tree is not T8103')
            j313.append(dict(offset=offset, bytes=length, sha256=sha(blob)))
        dtbs += 1
        offset += length
    need(trailer[offset:offset + 3] == b'\x1f\x8b\x08', 'expected gzip U-Boot after the device trees')
    decoder = zlib.decompressobj(31)
    uboot = decoder.decompress(trailer[offset:], 16 << 20)
    need(decoder.eof and not decoder.unused_data, 'unknown data after U-Boot')
    need(uboot[0x38:0x3c] == b'ARMd' and b'U-Boot' in uboot, 'gzip member is not ARM64 U-Boot')
    need(len(j313) == 1, 'expected one J313 device tree')
    return dict(bytes=len(trailer), sha256=sha(trailer), device_trees=dtbs, j313_device_tree=j313[0],
                uboot_gzip_offset=offset, uboot_gzip_bytes=len(trailer) - offset,
                uboot_uncompressed_sha256=sha(uboot))


def strings_of(blob):
    return set(re.findall(rb'[\x20-\x7e]{8,}', blob))


def run_build(directory, tag, log):
    environment = {**os.environ, 'M1N1_VERSION_TAG': tag, 'CARGO_NET_OFFLINE': 'true',
                   'PYTHONDONTWRITEBYTECODE': '1'}
    for name in ('MAKEFLAGS', 'MAKEOVERRIDES', 'MFLAGS'):
        environment.pop(name, None)
    with open(log, 'xb') as output:
        subprocess.run(BUILD, cwd=directory, stdout=output, stderr=subprocess.STDOUT, env=environment, check=True)
    raw = (directory / 'build/m1n1.bin').read_bytes()
    need(len(raw) == RAW_BYTES and raw[0x808:0x810] == b'AURALOAD', 'unexpected raw image layout')
    need(struct.unpack_from('<IIQQ', raw, 0x810) == (1, 1, RAW_BYTES, 0), 'unexpected load header')
    need(b'##m1n1_ver##' + tag.encode() + b'\0' in raw, 'tag missing from image')
    config = (directory / 'build/build_cfg.h').read_text().splitlines()
    need(set(config) == {'#define CHAINLOADING', '#define ESP_STAGE2', '#define M1_BOOT_WINDOW',
                         '#define BUILTIN_LOGO bootlogo'}, 'unexpected build selection')
    return raw


def copy_source(source, target):
    def ignored(directory, names):
        return {'build', 'target'} & set(names) if Path(directory) in (source, source / 'rust') else set()
    shutil.copytree(source, target, symlinks=True, ignore=ignored)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--source', type=Path, required=True, help='the J293 window checkout (read only)')
    parser.add_argument('--original', type=Path, required=True, help="the Air's backed-up m1n1/boot.bin (read only)")
    parser.add_argument('--out', type=Path, required=True, help='a new directory outside the repository')
    parser.add_argument('--receipt', type=Path, help='also write the receipt here')
    args = parser.parse_args()

    source = args.source.resolve(strict=True)
    need(not args.out.exists(), '--out already exists')
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source, text=True).strip()
    need(head == PIN, 'source is not at the pin')
    for name, expected in WINDOW_FILES.items():
        need(sha((source / name).read_bytes()) == expected, 'source file differs: ' + name)
    tools = {tool: subprocess.check_output([tool, '--version'], text=True).splitlines()[0] for tool in TOOLS}
    need(tools == TOOLS, 'toolchain differs from the recorded one: ' + json.dumps(tools))
    original = args.original.read_bytes()
    need(len(original) == ORIGINAL_BYTES and sha(original) == ORIGINAL_SHA, 'original stage 2 differs')
    payload = original[PAYLOAD_OFFSET:]
    payload_record = inspect_payload(payload)

    args.out.mkdir(mode=0o700, parents=True)
    work = args.out / 'work'
    work.mkdir()
    copy_source(source, work / 'control')
    control = run_build(work / 'control', J293_TAG, work / 'control.log')
    need(sha(control) == J293_RAW_SHA, 'control does not reproduce the J293 window; toolchain or path changed')

    copy_source(source, work / 'j313')
    subprocess.run(['patch', '-s', '-p1', '-i', str(HERE / 'j313-window.patch')], cwd=work / 'j313', check=True)
    subprocess.run(['clang', '-std=c11', '-g', '-fsanitize=address,undefined', '-fno-sanitize-recover=all',
                    '-I', str(work / 'j313/src'), str(HERE / 'test_j313_window.c'),
                    str(work / 'j313/src/m1_boot_window.c'), '-o', str(work / 'test_j313_window')], check=True)
    subprocess.run([str(work / 'test_j313_window')], check=True, env={**os.environ, 'ASAN_OPTIONS': 'detect_leaks=0'})
    raw = run_build(work / 'j313', J313_TAG, work / 'j313.log')
    comparison = compare(work / 'control/build/m1n1-raw.elf', work / 'j313/build/m1n1-raw.elf')

    image = raw + payload
    need(image[len(raw):] == payload and args.original.read_bytes() == original, 'payload changed while packaging')
    (args.out / 'j313-window-raw.bin').write_bytes(raw)
    (args.out / 'j313-window-boot.bin').write_bytes(image)
    prefix = original[:PAYLOAD_OFFSET]
    old_strings, new_strings = strings_of(prefix), strings_of(raw)
    receipt = {
        'status': 'BUILT_OFFLINE_NOT_INSTALLED_NOT_BOOTED',
        'source_commit': PIN, 'build_tag': J313_TAG, 'build_command': BUILD,
        'patch_sha256': sha((HERE / 'j313-window.patch').read_bytes()),
        'tool_versions': tools,
        'control': {'build_tag': J293_TAG, 'raw_sha256': sha(control), 'reproduces_pro_window': True},
        'raw': {'bytes': len(raw), 'sha256': sha(raw)},
        'boot_bin': {'bytes': len(image), 'sha256': sha(image)},
        'original': {'bytes': len(original), 'sha256': ORIGINAL_SHA, 'payload_offset': PAYLOAD_OFFSET},
        'payload': {**payload_record, 'byte_identical_to_original': True},
        'difference_from_pro_window': comparison,
        'difference_from_air_stage2': {
            'comparable': False,
            'reason': 'The Air runs f5a82fdb, whose source is not in this lab. Only the payloads can be compared exactly.',
            'code_bytes_air': PAYLOAD_OFFSET, 'code_bytes_candidate': len(raw),
            'printable_strings_only_in_air': len(old_strings - new_strings),
            'printable_strings_only_in_candidate': len(new_strings - old_strings),
        },
        'hardware_tested': False,
    }
    encoded = json.dumps(receipt, indent=2) + '\n'
    (args.out / 'build-receipt.json').write_text(encoded)
    if args.receipt:
        args.receipt.write_text(encoded)
    shutil.rmtree(work)
    print(json.dumps({key: receipt[key] for key in ('status', 'raw', 'boot_bin')}, indent=2))
    print(json.dumps(comparison, indent=2))


if __name__ == '__main__':
    main()
