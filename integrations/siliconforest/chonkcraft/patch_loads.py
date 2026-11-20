#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Point a JBR image's framework load commands at the fills.

  patch_loads.py IMAGE NAME...

Each NAME (AppKit, CoreGraphics, ...) whose framework IMAGE loads by
LC_LOAD_DYLIB is renamed to @loader_path/sffill/NAME.dylib in place (the
new name is shorter, the command keeps its size). Only for the staged
copy of the ChonkCraft runtime; never for Apple binaries."""
import struct, sys

LC_LOAD_DYLIB = 0xC
path, names = sys.argv[1], sys.argv[2:]
data = bytearray(open(path, "rb").read())
if struct.unpack_from("<I", data, 0)[0] != 0xFEEDFACF:
    raise SystemExit("not a 64-bit Mach-O")
ncmds, = struct.unpack_from("<I", data, 16)
off = 32
done = set()
for _ in range(ncmds):
    cmd, size = struct.unpack_from("<II", data, off)
    if cmd == LC_LOAD_DYLIB:
        noff, = struct.unpack_from("<I", data, off + 8)
        end = data.index(0, off + noff)
        got = bytes(data[off + noff:end]).decode()
        for n in names:
            if got.startswith("/System/Library/Frameworks/%s.framework/" % n):
                new = ("@loader_path/sffill/%s.dylib" % n).encode()
                if noff + len(new) + 1 > size:
                    raise SystemExit("%s does not fit" % new)
                data[off + noff:off + size] = new + b"\0" * (size - noff - len(new))
                print("%s: %s -> %s" % (path.split("/")[-1], got, new.decode()))
                done.add(n)
    off += size
missing = set(names) - done
if missing:
    raise SystemExit("not loaded by %s: %s" % (path, " ".join(sorted(missing))))
open(path, "wb").write(data)
