# SPDX-License-Identifier: MIT
let
  e=import ../environment.nix;
  inherit(e) pkgs p libsystem sdk cc ld;
  ma=import ./installed-graphics.nix;
  graphics=import ../../cocoa/patched.nix;
in pkgs.stdenv.mkDerivation {
  name="siliconforest-finch-MediaAccessibility-tests-arm64";
  dontUnpack=true;dontConfigure=true;
  buildPhase=''
    export DARWIN_SDK_ROOT=${sdk}
    ${cc} -isysroot ${sdk} -mmacosx-version-min=26.5 -O2 -fblocks -D_DARWIN_C_SOURCE -Wno-nullability-completeness -I${./include} \
      -I${p.coreFoundation-arm64}/include -I${libsystem}/usr/include -I${graphics.coregraphics}/usr/include -I${graphics.coretext}/usr/include -I${graphics.onyx2d}/usr/include -I${e.pd.outPath}/src/Frameworks \
      ${./probe.c} --ld-path=${ld} -nostdlib -L${libsystem}/usr/lib -L${libsystem}/usr/lib/system -L${p.coreFoundation-arm64}/usr/lib \
      -F${ma}/System/Library/Frameworks -framework MediaAccessibility -L${graphics.coregraphics}/usr/lib -lCoreGraphics -lCoreFoundation -lSystem \
      -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libsystem}/usr/lib/system/libdyld.dylib -Wl,-platform_version,macos,26.5,26.5 -o media-accessibility-probe
  '';
  installPhase=''mkdir -p $out/bin;cp media-accessibility-probe $out/bin/'';
  dontFixup=true;dontStrip=true;
}
