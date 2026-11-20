#!/bin/bash
# SPDX-License-Identifier: MIT
# Terminal placement and tab insert. A side library: it does not satisfy
# binds and it is not an AppKit overlay. The built dylib is not committed.
#
#   CC LD SDK LIBSYSTEM OBJC OUT
set -euo pipefail
: "${CC:?}" "${LD:?}" "${SDK:?}" "${LIBSYSTEM:?}" "${OBJC:?}" "${OUT:?}"
S=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"
CFC="-O2 -fno-objc-arc -fno-stack-protector -isysroot $SDK -I$LIBSYSTEM/usr/include -I$OBJC/usr/include -Wno-deprecated-declarations"
"$CC" $CFC -c "$S/PlaceTabs.m" -o "$OUT/PlaceTabs.o"
"$CC" -dynamiclib "$OUT/PlaceTabs.o" \
  --ld-path="$LD" -nostdlib -isysroot "$SDK" \
  -L"$LIBSYSTEM/usr/lib" -L"$OBJC/usr/lib" \
  -lSystem -lobjc \
  -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:"$LIBSYSTEM/usr/lib/system/libdyld.dylib" \
  -Wl,-platform_version,macos,26.5,26.5 \
  -Wl,-install_name,/private/var/db/sfterminal/libSFTermPlace.dylib \
  -o "$OUT/libSFTermPlace.dylib"
rm -f "$OUT/PlaceTabs.o"
