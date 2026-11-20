# SPDX-License-Identifier: MIT
# Private Hydra model and unavailable 3D renderer for Preview bring-up.
let
  e = import ../environment.nix;
  a = import ../../cocoa/arm64.nix;
  foundation = a.base.foundation;
  cf = a.base.corefoundation;
  objc = a.base.libobjc;
in e.pkgs.runCommand "siliconforest-preview-hydra-arm64" {} ''
  export DARWIN_SDK_ROOT=${e.sdk}
  CF="-O2 -Wall -Wextra -Werror -fblocks -fobjc-exceptions -fexceptions -fobjc-arc -isysroot ${e.sdk} -I${./.} -isystem ${e.libsystem}/usr/include -isystem ${objc}/usr/include -isystem ${foundation}/usr/include -isystem ${cf}/include"
  LF="--ld-path=${e.ld} -nostdlib -isysroot ${e.sdk} -L${e.libsystem}/usr/lib -L${objc}/usr/lib -L${foundation}/usr/lib -L${cf}/usr/lib -lFoundation -lCoreFoundation -lobjc -lSystem -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib -Wl,-platform_version,macos,26.5,26.5"
  F=$out/System/Library/PrivateFrameworks/Hydra.framework
  mkdir -p $F/Versions/C/Resources/Licenses $out/include $out/bin
  ${e.cc} $CF -c ${./Hydra.m} -o Hydra.o
  ${e.cc} -dynamiclib Hydra.o $LF -Wl,-install_name,/System/Library/PrivateFrameworks/Hydra.framework/Versions/C/Hydra -o $F/Versions/C/Hydra
  ${e.cc} $CF ${./probe.m} $LF $F/Versions/C/Hydra -o $out/bin/hydra-probe
  ln -s C $F/Versions/Current
  ln -s Versions/Current/Hydra $F/Hydra
  cp ${./SFHydra.h} $out/include/
  cp ${../../../../LICENSE} $F/Versions/C/Resources/Licenses/LICENSE-MIT
''
