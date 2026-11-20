#!/bin/bash
# SPDX-License-Identifier: MIT
# TextEdit-only AppKit front. The dock overlay already supplies Preview's
# Swift fill and NSApplicationMain, and reexports AppKit.sf-p44. TextEdit
# also needs CGRect.frame(withWidth:using:) in the AppKit image it loaded.
# This builds that image. It does not modify the dock overlay or any Apple
# bundle.
#
#   CC LD SDK LIBSYSTEM OBJC FOUNDATION CF BASE OUT
# BASE is the dock overlay AppKit (install name AppKit.sf-additions).
# OUT receives AppKit (this front), AppKit.sf-base (a copy of BASE whose
# install name is @loader_path/AppKit.sf-base, so dyld does not fold it onto
# the dock overlay), and copies of AppKit.sf-p44, AppKit.sf-missing, and
# AppKit.sf-under from beside BASE. Those three are copied, not rebuilt.
# None of the binaries are committed.
set -euo pipefail
: "${CC:?}" "${LD:?}" "${SDK:?}" "${LIBSYSTEM:?}" "${OBJC:?}" "${FOUNDATION:?}" "${CF:?}" "${BASE:?}" "${OUT:?}"
S=$(cd "$(dirname "$0")" && pwd)
DOCK=$(cd "$(dirname "$BASE")" && pwd)
mkdir -p "$OUT"
cp "$BASE" "$OUT/AppKit.sf-base"
# The overlay reexports these by @loader_path. The link only needs to open
# them; the copies in OUT are what the launcher ships beside the front.
for part in AppKit.sf-p44 AppKit.sf-missing AppKit.sf-under; do
  cp "$DOCK/$part" "$OUT/$part"
done
python3 - "$OUT/AppKit.sf-base" <<'PY'
import struct, sys
path = sys.argv[1]
data = bytearray(open(path, "rb").read())
magic, = struct.unpack_from("<I", data, 0)
if magic != 0xFEEDFACF:
    raise SystemExit("AppKit.sf-base is not a 64-bit Mach-O")
ncmds, = struct.unpack_from("<I", data, 16)
off = 32
old = b"/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit.sf-additions"
new = b"@loader_path/AppKit.sf-base"
found = 0
for _ in range(ncmds):
    cmd, size = struct.unpack_from("<II", data, off)
    if cmd == 0xD:  # LC_ID_DYLIB
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
"$CC" -isysroot "$SDK" -c "$S/FrameRect.S" -o "$OUT/FrameRect.o"
"$CC" $CFC -c "$S/DocumentSymbols.m" -o "$OUT/DocumentSymbols.o"
"$CC" $CFC -c "$S/TextKitStubs.m" -o "$OUT/TextKitStubs.o"
"$CC" $CFC -c "$S/ExceptionLog.m" -o "$OUT/ExceptionLog.o"
"$CC" $CFC -c "$S/SpellCheckerAdd.m" -o "$OUT/SpellCheckerAdd.o"
"$CC" $CFC -c "$S/DocumentRead.m" -o "$OUT/DocumentRead.o"
"$CC" $CFC -c "$S/LayoutAdd.m" -o "$OUT/LayoutAdd.o"
"$CC" -dynamiclib "$OUT/FrameRect.o" "$OUT/DocumentSymbols.o" "$OUT/TextKitStubs.o" "$OUT/ExceptionLog.o" "$OUT/SpellCheckerAdd.o" "$OUT/DocumentRead.o" "$OUT/LayoutAdd.o" \
  --ld-path="$LD" -nostdlib -isysroot "$SDK" \
  -L"$LIBSYSTEM/usr/lib" -L"$OBJC/usr/lib" -L"$FOUNDATION/usr/lib" -L"$CF/usr/lib" \
  -lSystem -lobjc -lFoundation -lCoreFoundation \
  -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:"$LIBSYSTEM/usr/lib/system/libdyld.dylib" \
  -Wl,-dylib_file,@loader_path/AppKit.sf-p44:"$OUT/AppKit.sf-p44" \
  -Wl,-dylib_file,@loader_path/AppKit.sf-missing:"$OUT/AppKit.sf-missing" \
  -Wl,-dylib_file,@loader_path/AppKit.sf-under:"$OUT/AppKit.sf-under" \
  -Wl,-platform_version,macos,26.5,26.5 \
  -Wl,-reexport_library,"$OUT/AppKit.sf-base" \
  -Wl,-install_name,/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit.sf-textedit \
  -Wl,-compatibility_version,1 -Wl,-current_version,1 \
  -o "$OUT/AppKit"
rm -f "$OUT/FrameRect.o" "$OUT/DocumentSymbols.o" "$OUT/TextKitStubs.o" "$OUT/ExceptionLog.o" "$OUT/SpellCheckerAdd.o" "$OUT/DocumentRead.o" "$OUT/LayoutAdd.o"
