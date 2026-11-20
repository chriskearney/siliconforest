# SPDX-License-Identifier: MIT OR Apache-2.0
# CGPDF read/scanner wrappers over retained Onyx2D objects.
# Does not replace CoreGraphics or Onyx2D and does not export page drawing.
# The original reader remains build.nix / libSFCoreGraphicsPDF.
let
  e = import ../environment.nix;
  inherit (e) pkgs p libsystem sdk cc ld;
  cf = p.coreFoundation-arm64;
  cg = p.coregraphics-arm64;
  onyx = p.onyx2d-arm64;
  nm = "${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-nm";
in pkgs.stdenv.mkDerivation {
  pname = "siliconforest-finch-SFCGPDFRead-arm64";
  version = "0.1.0";
  src = pkgs.lib.cleanSource ./.;
  dontConfigure = true;
  buildPhase = ''
    export DARWIN_SDK_ROOT=${sdk}
    INC="-Iinclude -isystem ${cf}/include -isystem ${cg}/usr/include -isystem ${onyx}/usr/include -isystem ${p.foundation-arm64}/usr/include -isystem ${p.libobjc-arm64}/usr/include -isystem ${libsystem}/usr/include"
    CF="-isysroot ${sdk} -mmacosx-version-min=26.5 -O2 -std=c11 -Wall -Wextra -Werror -D_DARWIN_C_SOURCE -Wno-macro-redefined -Wno-literal-range $INC"
    ${cc} $CF -fno-objc-arc -fblocks -fobjc-exceptions -c sf_cgpdf_o2.m -o sf_cgpdf_o2.o
    ${cc} -dynamiclib sf_cgpdf_o2.o --ld-path=${ld} -nostdlib -isysroot ${sdk} \
      -L${libsystem}/usr/lib -L${libsystem}/usr/lib/system \
      -L${cf}/usr/lib -L${onyx}/usr/lib \
      -L${p.foundation-arm64}/usr/lib -L${p.libobjc-arm64}/usr/lib \
      -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libsystem}/usr/lib/system/libdyld.dylib \
      -Wl,-platform_version,macos,26.5,26.5 \
      -Wl,-exported_symbols_list,exports-o2.txt \
      -install_name /System/Library/Frameworks/SFCGPDFRead.framework/Versions/A/SFCGPDFRead \
      -compatibility_version 1 -current_version 1 \
      -lOnyx2D -lFoundation -lCoreFoundation -lobjc -lSystem \
      -o libSFCGPDFRead.dylib
    ${nm} -g -U libSFCGPDFRead.dylib | awk '{print $NF}' | sort -u > defined.txt
    sort exports-o2.txt > exports.sorted
    diff -u exports.sorted defined.txt
    if ${nm} -g -U libSFCGPDFRead.dylib | grep -E '_CGContextDrawPDFPage$|_CGPDFDocumentCreateWithProvider$|_CGPDFContextSetOutline$|_CGPDFPageGetBoxRect$|_CGPDFPageGetDrawingTransform$'; then
      echo "app path must leave draw and document creation to CoreGraphics" >&2
      exit 1
    fi
    ${cc} $CF -c sf_cgpdf_o2_probe.c -o sf_cgpdf_o2_probe.o
    ${cc} sf_cgpdf_o2_probe.o --ld-path=${ld} -nostdlib -isysroot ${sdk} \
      -L${libsystem}/usr/lib -L${libsystem}/usr/lib/system \
      -L${cf}/usr/lib -L${cg}/usr/lib \
      -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libsystem}/usr/lib/system/libdyld.dylib \
      -Wl,-platform_version,macos,26.5,26.5 \
      libSFCGPDFRead.dylib -lCoreGraphics -lCoreFoundation -lSystem \
      -o sfcgpdf-read-probe
  '';
  installPhase = ''
    fw=$out/System/Library/Frameworks/SFCGPDFRead.framework
    mkdir -p $fw/Versions/A/Headers $out/usr/lib $out/include $out/bin $out/share
    cp libSFCGPDFRead.dylib $fw/Versions/A/SFCGPDFRead
    cp include/SFCoreGraphicsPDF.h $fw/Versions/A/Headers/SFCoreGraphicsPDF.h
    ln -s A $fw/Versions/Current
    ln -s Versions/Current/SFCGPDFRead $fw/SFCGPDFRead
    ln -s Versions/Current/Headers $fw/Headers
    ln -s ../../System/Library/Frameworks/SFCGPDFRead.framework/Versions/A/SFCGPDFRead \
      $out/usr/lib/libSFCGPDFRead.dylib
    cp include/SFCoreGraphicsPDF.h $out/include/SFCoreGraphicsPDF.h
    cp sfcgpdf-read-probe $out/bin/sfcgpdf-read-probe
    cp defined.txt $out/share/exports.txt
    sha256sum $fw/Versions/A/SFCGPDFRead > $out/share/SFCGPDFRead.sha256
  '';
  dontFixup = true;
  dontStrip = true;
}
