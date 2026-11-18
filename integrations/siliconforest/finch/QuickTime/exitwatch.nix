# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# qtp-exitwatch (tools/exitwatch.c): records why a program we test ends, or where it waits.
let e=import ../environment.nix; a=import ../../cocoa/arm64.nix; in
e.pkgs.runCommand "siliconforest-qtp-exitwatch-arm64" {} ''
 export DARWIN_SDK_ROOT=${e.sdk};mkdir -p $out/lib
 ${e.cc} -O1 -isysroot ${e.sdk} -I${e.libsystem}/usr/include -I${a.base.libobjc}/usr/include -dynamiclib ${./tools/exitwatch.c} \
  --ld-path=${e.ld} -nostdlib -L${e.libsystem}/usr/lib -L${a.base.libobjc}/usr/lib -lobjc -lSystem \
  -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib \
  -Wl,-platform_version,macos,26.5,26.5 -Wl,-install_name,/usr/local/lib/qtp-exitwatch.dylib -o $out/lib/qtp-exitwatch.dylib
''
