# SPDX-License-Identifier: MIT OR Apache-2.0
# Arm64 CGPDF reader for the Finch PDFKit port.
# Link -lSFCoreGraphicsPDF before -lCoreGraphics. This does not replace either
# CoreGraphics or Onyx2D. Writer symbols stay unresolved on purpose.
let
  e = import ../environment.nix;
  inherit (e) pkgs p libsystem sdk cc ld;
  zlib = p.zlib-arm64;
  cf = p.coreFoundation-arm64;
  cg = p.coregraphics-arm64;
  onyx = p.onyx2d-arm64;
  nm = "${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-nm";
in pkgs.stdenv.mkDerivation {
  pname = "siliconforest-finch-SFCoreGraphicsPDF-arm64";
  version = "0.1.0";
  src = pkgs.lib.cleanSource ./.;
  dontConfigure = true;
  buildPhase = ''
    export DARWIN_SDK_ROOT=${sdk}
    INC="-I. -I${zlib}/include -I${cf}/include -I${cg}/usr/include -I${onyx}/usr/include -I${libsystem}/usr/include"
    CF="-isysroot ${sdk} -mmacosx-version-min=26.5 -O2 -std=c11 -Wall -Wextra -Werror -D_DARWIN_C_SOURCE $INC"
    ${cc} $CF -c sf_cgpdf.c -o sf_cgpdf.o
    # The CoreFoundation and CoreGraphics headers redefine TargetConditionals
    # macros and use an out-of-range CGRectNull literal. Those warnings are theirs.
    ${cc} $CF -Wno-macro-redefined -Wno-literal-range -c sf_cgpdf_darwin.c -o sf_cgpdf_darwin.o
    ${cc} -dynamiclib sf_cgpdf.o sf_cgpdf_darwin.o --ld-path=${ld} -nostdlib -isysroot ${sdk} \
      -L${libsystem}/usr/lib -L${libsystem}/usr/lib/system \
      -L${cf}/usr/lib -L${cg}/usr/lib \
      -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libsystem}/usr/lib/system/libdyld.dylib \
      -Wl,-platform_version,macos,26.5,26.5 \
      -Wl,-exported_symbols_list,exports.txt \
      -install_name /System/Library/Frameworks/SFCoreGraphicsPDF.framework/Versions/A/SFCoreGraphicsPDF \
      -compatibility_version 1 -current_version 1 \
      ${zlib}/lib/libz.a -lCoreFoundation -lCoreGraphics -lSystem \
      -o libSFCoreGraphicsPDF.dylib
    ${nm} -g -U libSFCoreGraphicsPDF.dylib | awk '{print $NF}' | sort -u > defined.txt
    sort exports.txt > exports.sorted
    diff -u exports.sorted defined.txt
    if ${nm} -g -U libSFCoreGraphicsPDF.dylib | grep -E '_CGPDFContext(BeginPage|EndPage|SetOutline)$'; then
      echo "writer symbols must stay unresolved" >&2
      exit 1
    fi
  '';
  installPhase = ''
    fw=$out/System/Library/Frameworks/SFCoreGraphicsPDF.framework
    mkdir -p $fw/Versions/A/Headers $out/usr/lib $out/include $out/share
    cp libSFCoreGraphicsPDF.dylib $fw/Versions/A/SFCoreGraphicsPDF
    cp include/SFCoreGraphicsPDF.h $fw/Versions/A/Headers/SFCoreGraphicsPDF.h
    ln -s A $fw/Versions/Current
    ln -s Versions/Current/SFCoreGraphicsPDF $fw/SFCoreGraphicsPDF
    ln -s Versions/Current/Headers $fw/Headers
    ln -s ../../System/Library/Frameworks/SFCoreGraphicsPDF.framework/Versions/A/SFCoreGraphicsPDF \
      $out/usr/lib/libSFCoreGraphicsPDF.dylib
    cp include/SFCoreGraphicsPDF.h $out/include/SFCoreGraphicsPDF.h
    cp defined.txt $out/share/exports.txt
    sha256sum $fw/Versions/A/SFCoreGraphicsPDF > $out/share/SFCoreGraphicsPDF.sha256
    cp ${zlib}/include/zlib.h $out/share/zlib.h
  '';
  dontFixup = true;
  dontStrip = true;
}
