# SPDX-License-Identifier: MIT OR Apache-2.0
# Private CorePDF read/layout subset. Does not replace CoreGraphics or Onyx2D.
let
  e = import ../environment.nix;
  inherit (e) pkgs p libsystem sdk cc ld;
  cf = p.coreFoundation-arm64;
  cg = p.coregraphics-arm64;
  onyx = p.onyx2d-arm64;
  nm = "${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-nm";
in pkgs.stdenv.mkDerivation {
  pname = "siliconforest-finch-CorePDF-arm64";
  version = "0.1.0";
  src = pkgs.lib.cleanSource ./.;
  dontConfigure = true;
  buildPhase = ''
    export DARWIN_SDK_ROOT=${sdk}
    INC="-Iinclude -isystem ${cf}/include -isystem ${cg}/usr/include -isystem ${onyx}/usr/include -isystem ${p.foundation-arm64}/usr/include -isystem ${p.libobjc-arm64}/usr/include -isystem ${libsystem}/usr/include"
    CF="-isysroot ${sdk} -mmacosx-version-min=26.5 -O2 -std=c11 -Wall -Wextra -Werror -D_DARWIN_C_SOURCE -Wno-macro-redefined -Wno-literal-range $INC"
    ${cc} $CF -fno-objc-arc -fblocks -fobjc-exceptions -c sf_corepdf.m -o sf_corepdf.o
    ${cc} -dynamiclib sf_corepdf.o --ld-path=${ld} -nostdlib -isysroot ${sdk} \
      -L${libsystem}/usr/lib -L${libsystem}/usr/lib/system \
      -L${cf}/usr/lib -L${onyx}/usr/lib \
      -L${p.foundation-arm64}/usr/lib -L${p.libobjc-arm64}/usr/lib \
      -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libsystem}/usr/lib/system/libdyld.dylib \
      -Wl,-platform_version,macos,26.5,26.5 \
      -Wl,-exported_symbols_list,exports.txt \
      -install_name /System/Library/PrivateFrameworks/CorePDF.framework/Versions/A/CorePDF \
      -compatibility_version 1.0.0 -current_version 1.0.0 \
      -lOnyx2D -lFoundation -lCoreFoundation -lobjc -lSystem \
      -o libCorePDF.dylib
    ${nm} -g -U libCorePDF.dylib | awk '{print $NF}' | sort -u > defined.txt
    sort exports.txt > exports.sorted
    diff -u exports.sorted defined.txt
    ${cc} $CF -c sf_corepdf_probe.c -o sf_corepdf_probe.o
    ${cc} sf_corepdf_probe.o --ld-path=${ld} -nostdlib -isysroot ${sdk} \
      -L${libsystem}/usr/lib -L${libsystem}/usr/lib/system \
      -L${cf}/usr/lib -L${cg}/usr/lib \
      -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libsystem}/usr/lib/system/libdyld.dylib \
      -Wl,-platform_version,macos,26.5,26.5 \
      libCorePDF.dylib -lCoreGraphics -lCoreFoundation -lSystem \
      -o sfcorepdf-layout-probe
  '';
  installPhase = ''
    fw=$out/System/Library/PrivateFrameworks/CorePDF.framework
    mkdir -p $fw/Versions/A/Headers $out/usr/lib $out/include $out/bin $out/share
    cp libCorePDF.dylib $fw/Versions/A/CorePDF
    cp include/SFCorePDF.h $fw/Versions/A/Headers/SFCorePDF.h
    ln -s A $fw/Versions/Current
    ln -s Versions/Current/CorePDF $fw/CorePDF
    ln -s Versions/Current/Headers $fw/Headers
    ln -s ../../System/Library/PrivateFrameworks/CorePDF.framework/Versions/A/CorePDF \
      $out/usr/lib/libCorePDF.dylib
    cp include/SFCorePDF.h $out/include/SFCorePDF.h
    cp sfcorepdf-layout-probe $out/bin/sfcorepdf-layout-probe
    cp defined.txt $out/share/exports.txt
    sha256sum $fw/Versions/A/CorePDF > $out/share/CorePDF.sha256
    sha256sum $out/bin/sfcorepdf-layout-probe > $out/share/probe.sha256
  '';
  dontFixup = true;
  dontStrip = true;
}
