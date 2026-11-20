# SPDX-License-Identifier: MIT
# Private private FinderKit icon view only; no installation or target execution.
let
  e = import ../environment.nix;
  a = import ../../cocoa/arm64.nix;
  foundation = a.base.foundation;
  cf = a.base.corefoundation;
  objc = a.base.libobjc;
  cg = a.appDeps.coregraphics;
  onyx = a.appDeps.onyx2d;
in e.pkgs.runCommand "siliconforest-preview-finderkit-icon-arm64" {} ''
  export DARWIN_SDK_ROOT=${e.sdk}
  CF="-O2 -Wall -Wextra -Werror -Wno-unused-parameter -fblocks -fobjc-exceptions -fexceptions -fobjc-arc-exceptions -fobjc-arc -isysroot ${e.sdk} -I$PWD -isystem ${e.libsystem}/usr/include -isystem ${objc}/usr/include -isystem ${foundation}/usr/include -isystem ${cf}/include -isystem ${cg}/usr/include -isystem ${onyx}/usr/include -isystem ${a.appDeps.appkit}/usr/include -isystem ${a.appDeps.quartzcore}/usr/include -isystem ${a.src}/src/Frameworks -isystem ${a.mesa}/usr/include -F${a.openglFramework}/System/Library/Frameworks"
  LF="--ld-path=${e.ld} -nostdlib -isysroot ${e.sdk} -L${e.libsystem}/usr/lib -L${objc}/usr/lib -L${foundation}/usr/lib -L${cf}/usr/lib -L${cg}/usr/lib -L${a.appDeps.appkit}/usr/lib -lAppKit -lCoreGraphics -lFoundation -lCoreFoundation -lobjc -lSystem -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib -Wl,-platform_version,macos,26.5,26.5"
  F=$out/System/Library/PrivateFrameworks/FinderKit.framework
  mkdir -p $F/Versions/A/Resources/Licenses
  ${e.cc} $CF -c ${./FIIconView.m} -o FIIconView.o
  ${e.cc} -dynamiclib FIIconView.o $LF -Wl,-compatibility_version,1 -Wl,-current_version,1 \
    -Wl,-install_name,/System/Library/PrivateFrameworks/FinderKit.framework/Versions/A/FinderKit \
    -o $F/Versions/A/FinderKit
  ln -s A $F/Versions/Current
  ln -s Versions/Current/FinderKit $F/FinderKit
  cp ${../../../../LICENSE} $F/Versions/A/Resources/Licenses/LICENSE-MIT
''
