# SPDX-License-Identifier: MIT
# Link the read compatibility exports and keep rendering in CoreGraphics/Onyx2D.
{ cgpdf ? import ../CGPDF/build-o2.nix }:
(import ./build.nix).overrideAttrs (old: {
  pname = "siliconforest-finch-PDFKit-reader-arm64";
  patches = old.patches ++ [ ./patches/0003-retained-reader.patch ./patches/0004-missing-page-box-fallback.patch ];
  buildPhase = builtins.replaceStrings
    [ "$CF -c userland/PDFKit/PDFKit.m" "-lCoreGraphics" ]
    [ "$CF -I${cgpdf}/include -include ${./retained-reader.h} -c userland/PDFKit/PDFKit.m"
      "-L${cgpdf}/usr/lib -lSFCGPDFRead -lCoreGraphics" ]
    old.buildPhase;
})
