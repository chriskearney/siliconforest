#!/bin/bash
# SPDX-License-Identifier: MIT
# Builds the ChonkCraft-only framework fills: JavaRuntimeSupport, CoreMIDI
# and ExceptionHandling. Each links libSystem only. They are staged in a
# private framework directory that only the ChonkCraft launch puts on
# DYLD_FRAMEWORK_PATH; nothing is written under /System.
#
#   OUT=<dir> build.sh        (CC LD SDK LIBSYSTEM default to the finch toolchain)
# Built binaries are not committed.
set -euo pipefail
S=$(cd "$(dirname "$0")" && pwd)
: "${OUT:?}"
CC=${CC:-/nix/store/p8x57y0mi788srcls95cpcf2nbjz6la8-darwin-cross-toolchain-nix/bin/arm64-apple-darwin20.4-clang}
LD=${LD:-/nix/store/ikix61c2brfm9cf9f4pwdh80mhy1f2xp-siliconforest-native-ld-0.1/bin/ld}
SDK=${SDK:-/nix/store/hzmqaqrhaam2nszdb95zbl913gc23ayp-siliconforest-oss-sdk-26.5/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk}
LIBSYSTEM=${LIBSYSTEM:-/nix/store/qxkrrfhc2anc1zl8qv9gkr0856ra4f42-siliconforest-libsystem-0.1}
build() { # name version source
  local name=$1 ver=$2 src=$3
  local dir="$OUT/$name.framework/Versions/A"
  mkdir -p "$dir"
  "$CC" -O2 -Wall -Werror -fno-stack-protector -isysroot "$SDK" -c "$S/$src" -o "$OUT/$name.o"
  "$CC" -dynamiclib "$OUT/$name.o" --ld-path="$LD" -nostdlib -isysroot "$SDK" \
    -L"$LIBSYSTEM/usr/lib" -lSystem \
    -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:"$LIBSYSTEM/usr/lib/system/libdyld.dylib" \
    -Wl,-platform_version,macos,26.5,26.5 \
    -Wl,-install_name,/System/Library/Frameworks/$name.framework/Versions/A/$name \
    -Wl,-compatibility_version,1 -Wl,-current_version,"$ver" \
    -o "$dir/$name"
  rm -f "$OUT/$name.o"
  ln -sfn A "$OUT/$name.framework/Versions/Current"
  ln -sfn "Versions/Current/$name" "$OUT/$name.framework/$name"
}
build JavaRuntimeSupport 80 JavaRuntimeSupport.c
build CoreMIDI 69 CoreMIDI.c
build ExceptionHandling 15 ExceptionHandling.c
