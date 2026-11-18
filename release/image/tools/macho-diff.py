#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Where two builds of one file differ.

    macho-diff.py A B

Nix store hashes (/nix/store/<32 chars>) are masked first. For a 64-bit Mach-O, each differing byte is
placed in the N_OSO entries of the debug map (object timestamps), the LC_UUID, the code signature, or
"other"; prints the counts. For other files, prints how many bytes differ.
"""
import struct, sys
import re
a, b = open(sys.argv[1], 'rb').read(), open(sys.argv[2], 'rb').read()
# build-time Nix store paths embedded in the file: same length, compare with the hashes masked
norm = lambda d: re.sub(rb'/nix/store/[a-z0-9]{32}', b'/nix/store/' + b'x' * 32, d)
masked = norm(a) != a or norm(b) != b
a, b = norm(a), norm(b)
if len(a) != len(b): print('sizes differ', len(a), len(b)); sys.exit()
uuid = []
def regions(d):
    if d[:4] != b'\xcf\xfa\xed\xfe': return None
    n = struct.unpack_from('<I', d, 16)[0]; off = 32; oso = []; sig = None; uuid.clear()
    for _ in range(n):
        c, s = struct.unpack_from('<II', d, off)
        if c == 0x2:   # LC_SYMTAB
            symoff, nsyms = struct.unpack_from('<II', d, off + 8)
            for i in range(nsyms):
                e = symoff + 16 * i
                if d[e + 4] == 0x66: oso.append((e + 8, e + 16))   # n_value of N_OSO
        if c == 0x1d: sig = struct.unpack_from('<II', d, off + 8)
        if c == 0x1b: uuid.append((off + 8, off + 24))
        off += s
    return oso, sig
r = regions(a)
diff = [i for i in range(len(a)) if a[i] != b[i]]
if r is None: print('not Mach-O, %d bytes differ%s' % (len(diff), ' after masking store paths' if masked else '')); sys.exit()
oso, sig = r
def where(i):
    if any(s <= i < e for s, e in oso): return 'oso'
    if sig and sig[0] <= i < sig[0] + sig[1]: return 'sig'
    if any(s <= i < e for s, e in uuid): return 'uuid'
    return 'other'
import collections
c = collections.Counter(where(i) for i in diff)
print(dict(c) if c else {}, 'store-paths-masked' if masked else '')
