# SPDX-License-Identifier: MIT
let
  e = import ../../environment.nix;
in e.pkgs.runCommand "siliconforest-preview-leaf-arm64" {} ''
  export DARWIN_SDK_ROOT=${e.sdk}
  CF="-O2 -std=c11 -Wall -Wextra -Werror -D_DARWIN_C_SOURCE -isysroot ${e.sdk} -isystem ${e.libsystem}/usr/include"
  LF="--ld-path=${e.ld} -nostdlib -isysroot ${e.sdk} -L${e.libsystem}/usr/lib -lSystem -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib -Wl,-platform_version,macos,26.5,26.5"
  location=/System/Library/Frameworks/_LocationEssentials.framework/Versions/A/_LocationEssentials
  soft=/System/Library/PrivateFrameworks/SoftLinking.framework/Versions/A/SoftLinking
  mkdir -p "$(dirname "$out$location")" "$(dirname "$out$soft")" $out/bin $out/share/licenses/Finch
  ${e.cc} $CF -dynamiclib ${./location.c} $LF -Wl,-install_name,"$location" \
    -Wl,-compatibility_version,1 -Wl,-current_version,1 -o "$out$location"
  ${e.cc} $CF -dynamiclib ${e.finch}/userland/SmallPrivate/SoftLinking.c $LF -Wl,-install_name,"$soft" \
    -Wl,-compatibility_version,1 -Wl,-current_version,71 -o "$out$soft"
  ${e.cc} $CF ${./probe.c} "$out$location" "$out$soft" $LF -o $out/bin/preview-leaf-probe
  cp ${e.finch}/LICENSE* $out/share/licenses/Finch/
''
