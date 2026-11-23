#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Function by function: what changed between two builds of the arm64 kernel member.

  compare-kernel-functions.py OLD_KERNEL NEW_KERNEL     (unstripped kernel.development.t8103)

For every function of __TEXT_EXEC,__text (symbols from llvm-nm, a function ends where the next
symbol starts, trailing zero padding dropped) its instruction words are compared with every field
that depends on where things were placed masked out: branch and compare-and-branch distances,
PC-relative literal loads, the 12-bit page offset of loads, stores and add-immediates, and the
address-forming instructions themselves (adrp, adr, nop), which the linker rewrites by distance
(adrp+add -> adr+nop, adrp+ldr -> nop+ldr literal, an adrp dropped when a register already holds
the page). Prints the functions only in one file and the common functions whose masked code
differs; those are then read as disassembly. Host only.
"""
import struct, subprocess, sys


def sections(data):
    out = {}
    ncmds = struct.unpack_from('<I', data, 16)[0]
    o = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', data, o)
        if cmd == 0x19:
            for i in range(struct.unpack_from('<I', data, o + 64)[0]):
                s = o + 72 + 80 * i
                sect = data[s:s + 16].rstrip(b'\0').decode()
                seg = data[s + 16:s + 32].rstrip(b'\0').decode()
                addr, size2, off = struct.unpack_from('<QQI', data, s + 32)
                out[(seg, sect)] = (addr, size2, off)
        o += size
    return out


def mask(op):
    if (op & 0x7c000000) == 0x14000000:
        return op & 0xfc000000          # b, bl
    if (op & 0xff000010) == 0x54000000:
        return op & 0xff00001f          # b.cond
    if (op & 0x7e000000) == 0x34000000:
        return op & 0xff00001f          # cbz, cbnz
    if (op & 0x7e000000) == 0x36000000:
        return op & 0xfff8001f          # tbz, tbnz
    if (op & 0x3b000000) == 0x18000000:
        return op & 0xff00001f          # ldr literal
    if (op & 0x3b000000) == 0x39000000:
        return op & 0xffc003ff          # load/store, unsigned 12-bit immediate
    return op


def placement_only(op):
    """address forming the linker rewrites: adrp, adr, nop, add-immediate"""
    return op == 0xd503201f or (op & 0x1f000000) == 0x10000000 or (op & 0xff800000) == 0x91000000


def functions(path):
    data = open(path, 'rb').read()
    addr, size, off = sections(data)[('__TEXT_EXEC', '__text')]
    nm = subprocess.run(['llvm-nm', '--defined-only', '-n', path], capture_output=True, text=True, check=True)
    syms = sorted((int(f[0], 16), f[2]) for f in (l.split() for l in nm.stdout.splitlines())
                  if len(f) == 3 and f[1] in 'tTsS' and addr <= int(f[0], 16) < addr + size)
    out = {}
    for i, (a, name) in enumerate(syms):
        end = syms[i + 1][0] if i + 1 < len(syms) else addr + size
        raw = data[off + a - addr:off + end - addr]
        words = list(struct.unpack_from('<%dI' % (len(raw) // 4), raw))
        while words and words[-1] == 0:
            words.pop()
        out.setdefault(name, tuple(mask(w) for w in words if not placement_only(w)))
    return out


def main():
    old, new = functions(sys.argv[1]), functions(sys.argv[2])
    common = set(old) & set(new)
    changed = sorted(n for n in common if old[n] != new[n])
    print('functions: old %d, new %d, common %d' % (len(old), len(new), len(common)))
    print('only in new (%d): %s' % (len(set(new) - set(old)), ' '.join(sorted(set(new) - set(old)))))
    print('only in old (%d): %s' % (len(set(old) - set(new)), ' '.join(sorted(set(old) - set(new)))))
    print('common, masked code differs (%d): %s' % (len(changed), ' '.join(changed)))


if __name__ == '__main__':
    main()
