# SPDX-License-Identifier: MIT
# A thin arm64 consumer only; does not build/install/replace PerformanceAnalysis.
let e = import ../environment.nix; in
e.pkgs.runCommand "siliconforest-preview-performance-probe-arm64" {} ''
  export DARWIN_SDK_ROOT=${e.sdk}
  mkdir -p $out/bin
  ${e.cc} -O2 -Wall -Wextra -Werror -isysroot ${e.sdk} -isystem ${e.libsystem}/usr/include \
    ${./performance-probe.c} --ld-path=${e.ld} -nostdlib -L${e.libsystem}/usr/lib -lSystem \
    -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib \
    -Wl,-platform_version,macos,26.5,26.5 -o $out/bin/performance-probe
''
