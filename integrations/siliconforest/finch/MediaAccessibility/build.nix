# SPDX-License-Identifier: MIT
let e = import ../environment.nix;
in import ../objc-framework.nix {
  name = "MediaAccessibility";
  patches = [
    ./patches/0001-verify-caption-before-rename.patch
    ./patches/0002-image-source-and-metadata-captioning.patch
  ];
  extraIncludes = "-I${e.p.coregraphics-arm64}/usr/include -I${e.p.onyx2d-arm64}/usr/include -I${e.p.coretext-arm64}/usr/include";
  extraLinks = "-L${e.p.coregraphics-arm64}/usr/lib -lCoreGraphics -L${e.p.coretext-arm64}/usr/lib -lCoreText";
}
