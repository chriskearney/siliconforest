#!/bin/bash
# SPDX-License-Identifier: MIT
# TextEdit-only RecapPerformanceTesting front. It defines the two classes
# TextEdit binds and reexports a copy of the Preview Recap library. The
# copy's install name is @loader_path/RecapPerformanceTesting.sf-under, so
# dyld does not fold it onto this front. The front's install name is
# RecapPerformanceTesting.sf-textedit.
#
#   CC LD SDK LIBSYSTEM OBJC FOUNDATION CF BASE OUT
# BASE is the Preview Recap executable. OUT receives RecapPerformanceTesting
# and RecapPerformanceTesting.sf-under. Neither binary is committed.
set -euo pipefail
: "${CC:?}" "${LD:?}" "${SDK:?}" "${LIBSYSTEM:?}" "${OBJC:?}" "${FOUNDATION:?}" "${CF:?}" "${BASE:?}" "${OUT:?}"
S=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"
cp "$BASE" "$OUT/RecapPerformanceTesting.sf-under"
python3 - "$OUT/RecapPerformanceTesting.sf-under" <<'PY'
import struct, sys
path = sys.argv[1]
data = bytearray(open(path, "rb").read())
if struct.unpack_from("<I", data, 0)[0] != 0xFEEDFACF:
    raise SystemExit("not a 64-bit Mach-O")
ncmds, = struct.unpack_from("<I", data, 16)
off = 32
old = b"/System/Library/PrivateFrameworks/RecapPerformanceTesting.framework/Versions/A/RecapPerformanceTesting"
new = b"@loader_path/RecapPerformanceTesting.sf-under"
found = 0
for _ in range(ncmds):
    cmd, size = struct.unpack_from("<II", data, off)
    if cmd == 0xD:
        name_off, = struct.unpack_from("<I", data, off + 8)
        end = data.index(0, off + name_off)
        got = bytes(data[off + name_off:end])
        if got != old:
            raise SystemExit("unexpected install name %r" % got)
        if name_off + len(new) + 1 > size:
            raise SystemExit("new install name does not fit")
        data[off + name_off:off + size] = new + b"\0" * (size - name_off - len(new))
        found += 1
    off += size
if found != 1:
    raise SystemExit("expected one LC_ID_DYLIB, found %d" % found)
open(path, "wb").write(data)
PY
CFC="-O2 -fno-objc-arc -fno-stack-protector -isysroot $SDK -I$LIBSYSTEM/usr/include -I$OBJC/usr/include -I$FOUNDATION/usr/include -I$CF/include -Wno-deprecated-declarations -Wno-nullability-completeness -Wno-arc-bridge-casts-disallowed-in-nonarc"
"$CC" $CFC -c "$S/RecapTextEdit.m" -o "$OUT/RecapTextEdit.o"
"$CC" -dynamiclib "$OUT/RecapTextEdit.o" \
  --ld-path="$LD" -nostdlib -isysroot "$SDK" \
  -L"$LIBSYSTEM/usr/lib" -L"$OBJC/usr/lib" -L"$FOUNDATION/usr/lib" -L"$CF/usr/lib" \
  -lSystem -lobjc -lFoundation \
  -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:"$LIBSYSTEM/usr/lib/system/libdyld.dylib" \
  -Wl,-platform_version,macos,26.5,26.5 \
  -Wl,-reexport_library,"$OUT/RecapPerformanceTesting.sf-under" \
  -Wl,-install_name,/System/Library/PrivateFrameworks/RecapPerformanceTesting.framework/Versions/A/RecapPerformanceTesting.sf-textedit \
  -Wl,-compatibility_version,1 -Wl,-current_version,1 \
  -o "$OUT/RecapPerformanceTesting"
rm -f "$OUT/RecapTextEdit.o"
