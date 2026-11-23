#!/bin/bash
# SPDX-License-Identifier: MIT
# Builds the private frameworks only the Quake launch puts on DYLD_FRAMEWORK_PATH:
# ForceFeedback (no devices) and an IOKit that re-exports the real one and adds the
# two calls the engine imports. Nothing is written under /System and the app's own
# files are not changed. Built binaries are not committed.
#
#   OUT=<dir> ROOT=<copy of the M1's /System and /usr/lib> build.sh
#
# The fill re-exports IOKit-real.dylib, a copy of the M1's IOKit with its own install
# name, built into OUT and staged beside it. A symlink to the real file does not work:
# dyld resolves it to the name the fill itself answers to, and the re-export loops.
set -euo pipefail
S=$(cd "$(dirname "$0")" && pwd)
: "${OUT:?}" "${ROOT:?}"
SFQUAKE=${SFQUAKE:-/private/var/db/sfquake}
T=/nix/store/p8x57y0mi788srcls95cpcf2nbjz6la8-darwin-cross-toolchain-nix/bin/arm64-apple-darwin20.4-
CC=${CC:-${T}clang}
LD=${LD:-/nix/store/ikix61c2brfm9cf9f4pwdh80mhy1f2xp-siliconforest-native-ld-0.1/bin/ld}
SDK=${SDK:-/nix/store/hzmqaqrhaam2nszdb95zbl913gc23ayp-siliconforest-oss-sdk-26.5/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk}
LIBSYSTEM=${LIBSYSTEM:-/nix/store/qxkrrfhc2anc1zl8qv9gkr0856ra4f42-siliconforest-libsystem-0.1}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/sfquake-fw.XXXXXX")
trap 'rm -rf "${WORK:?}"' EXIT

build() { # name compat current source [extra link args...]
  local name=$1 compat=$2 cur=$3 src=$4
  shift 4
  local dir="$OUT/$name.framework/Versions/A"
  mkdir -p "$dir"
  "$CC" -O2 -Wall -Werror -fno-stack-protector -isysroot "$SDK" -c "$S/$src" -o "$WORK/$name.o"
  "$CC" -dynamiclib "$WORK/$name.o" --ld-path="$LD" -nostdlib -isysroot "$SDK" \
    -L"$LIBSYSTEM/usr/lib" -lSystem \
    -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:"$LIBSYSTEM/usr/lib/system/libdyld.dylib" \
    -Wl,-platform_version,macos,26.5,26.5 \
    -Wl,-install_name,/System/Library/Frameworks/$name.framework/Versions/A/$name \
    -Wl,-compatibility_version,"$compat" -Wl,-current_version,"$cur" \
    "$@" -o "$dir/$name"
  ln -sfn A "$OUT/$name.framework/Versions/Current"
  ln -sfn "Versions/Current/$name" "$OUT/$name.framework/$name"
}

build ForceFeedback 1 1 ForceFeedback.c

# A copy of the real IOKit under its own install name, staged in the private directory.
cp "$ROOT/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit" "$OUT/IOKit-real.dylib"
chmod u+w "$OUT/IOKit-real.dylib"
"${T}install_name_tool" -id "$SFQUAKE/fw/IOKit-real.dylib" "$OUT/IOKit-real.dylib"
build IOKit 1 275 IOKitFill.c -Wl,-reexport_library,"$OUT/IOKit-real.dylib" \
  -Wl,-dylib_file,/usr/lib/libIOKitCF.dylib:"$ROOT/usr/lib/libIOKitCF.dylib" \
  -Wl,-dylib_file,/usr/lib/libCoreFoundation.dylib:"$ROOT/usr/lib/libCoreFoundation.dylib"

# Inserted at launch: makes the app's SDLMain the delegate (see sfquakestart.c).
# libobjc resolves on the M1, where the app has already loaded it.
"$CC" -O2 -Wall -Werror -fno-stack-protector -isysroot "$SDK" -c "$S/sfquakestart.c" -o "$WORK/sfquakestart.o"
"$CC" -dynamiclib "$WORK/sfquakestart.o" --ld-path="$LD" -nostdlib -isysroot "$SDK" \
  -L"$LIBSYSTEM/usr/lib" -lSystem \
  -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:"$LIBSYSTEM/usr/lib/system/libdyld.dylib" \
  -Wl,-platform_version,macos,26.5,26.5 \
  -Wl,-install_name,"$SFQUAKE/fw/libsfquakestart.dylib" \
  -Wl,-undefined,dynamic_lookup \
  -o "$OUT/libsfquakestart.dylib"
