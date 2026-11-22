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
# DYLD_FRAMEWORK_PATH. OUT/fwlib/ holds legacy leaf-name fallbacks for pre-bakein
# systems; since bake-in step 5 (bk5 Java2D->Metal fallback fix), the system
# provides OpenGL.framework/Versions/Current/Libraries/libGL.dylib -> ../OpenGL
# and /usr/lib/libEGL.1.dylib directly, so sf-open-chonkcraft no longer sets
# DYLD_LIBRARY_PATH=$B/fwlib. The DMG and the M1's /System are not modified.
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
