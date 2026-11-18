# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
#
# Activity Monitor's support libraries and tools for the SiliconForest root: what
# activity-monitor/tools/sf_actmon.sh `libs` and `install` put on the owner's M1, as one tree at
# installed paths. Activity Monitor itself is Apple's and is not here; the user copies it from
# their own macOS (docs/release/IMAGE.md). These are this repository's own sources (MIT):
#   activity-monitor/libs/build.sh   libsysmon, libIOReport, libsystemstats, libquit,
#                                    libLaunchServicesSupport and the framework stubs
#                                    (NetworkStatistics, CoreSymbolication, RemoteServiceDiscovery,
#                                    SafeEjectGPU, AssetCacheServicesExtensions,
#                                    UniformTypeIdentifiers, SecurityFoundation, OpenCL, Suggestions,
#                                    CrashReporterSupport). Its wrappers of CoreFoundation, Foundation,
#                                    CoreServices and IOKit and its Metal stub are left out, as the
#                                    M1's install left them out: the root's own frameworks (Metal is
#                                    Finch's) stay. Its UniformTypeIdentifiers replaces the Cocoa
#                                    root's, as on the M1.
#   activity-monitor/tools/sf-sample.c  /usr/bin/sample
#   activity-monitor/tools/sf-lsof.c    /usr/sbin/lsof
#   linkRoot   the root these link against (release/image.nix: rootTree)
{ pkgs, tree ? ../../integrations/siliconforest, linkRoot }:
let
  a = import (tree + "/cocoa/arm64.nix");
  xnu = (import (tree + "/rebase/pd.nix")).pd.packages.x86_64-linux.xnu-headers-arm64;
  sdk = "${a.common.appleSdk}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
in pkgs.runCommand "siliconforest-activity-monitor-support" {
  nativeBuildInputs = [ pkgs.python3 ];
} ''
  set -euo pipefail
  export CC=${a.common.darwinCrossToolchain}/bin/arm64-apple-darwin20.4-clang
  export LD=${a.common.nativeLd}/bin/ld SDK=${sdk}
  export INC="-I${a.common.libSystem}/usr/include -I${a.base.libobjc}/usr/include -I${a.base.corefoundation}/include -I${a.base.foundation}/usr/include"
  export LINKROOT=${linkRoot} PY=python3 HB=${tree}/homebrew
  export NTSTAT_INC=${xnu}/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders
  bash ${tree}/activity-monitor/libs/build.sh $PWD/all > build.log 2>&1 || { tail -30 build.log >&2; exit 1; }
  mkdir -p $out
  (cd all && find . \( -type f -o -type l \) | sed 's#^\./##' \
     | grep -Ev '(AppKit|CoreFoundation|CoreGraphics|CoreServices|Foundation|IOKit|Metal)\.framework/' \
     | while read -r f; do mkdir -p "$out/$(dirname "$f")"; cp -P "$f" "$out/$f"; done)
  # the links build.sh makes for each framework (Versions/Current, the top-level name)
  (cd all && find . -type l | sed 's#^\./##' | grep -Ev '(AppKit|CoreFoundation|CoreGraphics|CoreServices|Foundation|IOKit|Metal)\.framework' \
     | while read -r f; do [ -L "$out/$f" ] || { mkdir -p "$out/$(dirname "$f")"; cp -P "$f" "$out/$f"; }; done)
  LDF="-fuse-ld=$LD -nostdlib -Wl,-syslibroot,$LINKROOT -L$LINKROOT/usr/lib -Wl,-platform_version,macos,26.5,26.5"
  mkdir -p $out/usr/bin $out/usr/sbin
  $CC -isysroot $SDK -mmacosx-version-min=26.5 -O1 -isystem $SDK/usr/include $INC ${tree}/activity-monitor/tools/sf-sample.c $LDF -lSystem -o $out/usr/bin/sample
  $CC -isysroot $SDK -mmacosx-version-min=26.5 -O1 -isystem $SDK/usr/include $INC ${tree}/activity-monitor/tools/sf-lsof.c $LDF -lSystem -o $out/usr/sbin/lsof
''
