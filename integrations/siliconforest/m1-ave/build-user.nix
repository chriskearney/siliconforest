# SPDX-License-Identifier: MIT
let
 e=import ../finch/environment.nix;
 inherit(e) pkgs cc ld sdk libsystem;
in pkgs.runCommand "siliconforest-sfave-info-arm64" {} ''
 export DARWIN_SDK_ROOT=${sdk}
 mkdir -p $out/bin
 ${cc} -isysroot ${sdk} -mmacosx-version-min=26.5 -O2 -I${./include} -I${libsystem}/usr/include ${./user/sfave-info.c} --ld-path=${ld} -nostdlib -L${libsystem}/usr/lib -lSystem -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libsystem}/usr/lib/system/libdyld.dylib -Wl,-platform_version,macos,26.5,26.5 -o $out/bin/sfave-info
 ${cc} -isysroot ${sdk} -mmacosx-version-min=26.5 -O2 -I${./include} -I${libsystem}/usr/include ${./user/sfave-enc.c} --ld-path=${ld} -nostdlib -L${libsystem}/usr/lib -lSystem -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libsystem}/usr/lib/system/libdyld.dylib -Wl,-platform_version,macos,26.5,26.5 -o $out/bin/sfave-enc
 ''
