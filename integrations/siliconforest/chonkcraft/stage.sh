#!/bin/bash
# SPDX-License-Identifier: MIT
# Stage the ChonkCraft macOS app for the M1 under SiliconForest.
#
#   stage.sh APP OUT
# APP is ChonkCraft.app from the published macos-arm64 DMG. OUT receives a
# copy whose runtime has:
#   lib/sffill/*.dylib            fills built by fills.py (re-export + missing symbols)
#   libawt_lwawt.dylib            framework loads pointed at those fills
# and OUT/fw/ holds JavaRuntimeSupport, CoreMIDI and ExceptionHandling for
# DYLD_FRAMEWORK_PATH, and OUT/fwlib/ the two leaf-name links for
# DYLD_LIBRARY_PATH: libGL.dylib (the JBR opens OpenGL's Libraries/libGL.dylib,
# which SiliconForest does not have) and libEGL.1.dylib (Mesa's EGL, which
# AppKit and QuartzCore look for at /usr/lib). The DMG and the M1's /System
# are not modified.
# Needs ROOT (a copy of the M1's /System and /usr/lib) for linking.
set -euo pipefail
S=$(cd "$(dirname "$0")" && pwd)
APP=$1; OUT=$2; : "${ROOT:?}"
rm -rf "$OUT"; mkdir -p "$OUT"
cp -a "$APP" "$OUT/ChonkCraft.app"
L="$OUT/ChonkCraft.app/Contents/runtime/Contents/Home/lib"
python3 "$S/fills.py" "$L/sffill" "$ROOT" 2>&1 | grep -v "two min versions" || true
python3 "$S/patch_loads.py" "$L/libawt_lwawt.dylib" AppKit ApplicationServices CoreFoundation CoreGraphics IOKit
OUT="$OUT/fw" "$S/frameworks/build.sh" 2>&1 | grep -v -E "two min versions|static initializer" || true
mkdir -p "$OUT/fwlib"
ln -sfn /System/Library/Frameworks/OpenGL.framework/Versions/A/OpenGL "$OUT/fwlib/libGL.dylib"
ln -sfn /usr/local/lib/mesa-asahi/libEGL.1.dylib "$OUT/fwlib/libEGL.1.dylib"
