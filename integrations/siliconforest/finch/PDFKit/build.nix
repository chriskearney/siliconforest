# SPDX-License-Identifier: MIT
# Build against the supplied CoreGraphics library and its public CGPDF headers.
let
  e = import ../environment.nix;
  a = import ../../cocoa/arm64.nix;
  inherit (e) pkgs p finch libsystem sdk cc ld;
  appkit = a.appDeps.appkit;
in pkgs.stdenv.mkDerivation {
  pname = "siliconforest-finch-PDFKit-arm64";
  version = "1451.4.2";
  src = finch;
  patches = [ ./patches/0001-appkit-graphics-port.patch ./patches/0005-preview-annotation-notifications.patch ];
  coregraphics = p.coregraphics-arm64;
  dontConfigure = true;
  buildPhase = ''
    export DARWIN_SDK_ROOT=${sdk}
    CF="-isysroot ${sdk} -mmacosx-version-min=26.5 -O2 -fblocks -fobjc-exceptions -fno-objc-arc -D_DARWIN_C_SOURCE -Wno-nullability-completeness -Wno-macro-redefined -Wno-incomplete-implementation -I${./include} -I${appkit}/usr/include -I${p.foundation-arm64}/usr/include -I${p.coreFoundation-arm64}/include -I${p.libobjc-arm64}/usr/include -I$coregraphics/usr/include -I${p.coretext-arm64}/usr/include -I${p.onyx2d-arm64}/usr/include -I${e.pd.outPath}/src/Frameworks -I${e.pd.outPath}/src/Frameworks/OpenGL/include -I${a.mesa}/usr/include"
    ${cc} $CF -c userland/PDFKit/PDFView.m -o PDFView.o
    ${cc} $CF -c userland/PDFKit/PDFKit.m -o PDFKit.o
    ${cc} $CF -c ${./PreviewSupport.m} -o PreviewSupport.o
    ${cc} -dynamiclib PDFKit.o PDFView.o PreviewSupport.o --ld-path=${ld} -nostdlib -isysroot ${sdk} -L${libsystem}/usr/lib -L${libsystem}/usr/lib/system -L${p.foundation-arm64}/usr/lib -L${p.coreFoundation-arm64}/usr/lib -L${p.libobjc-arm64}/usr/lib -L$coregraphics/usr/lib -L${p.coretext-arm64}/usr/lib -F${appkit}/System/Library/Frameworks -framework AppKit -lCoreGraphics -lCoreText -lFoundation -lCoreFoundation -lobjc -lSystem -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libsystem}/usr/lib/system/libdyld.dylib -Wl,-platform_version,macos,26.5,26.5 -install_name /System/Library/Frameworks/PDFKit.framework/Versions/A/PDFKit -current_version 1451.4.2 -compatibility_version 1 -o PDFKit
  '';
  installPhase = ''
    fw=$out/System/Library/Frameworks/PDFKit.framework
    mkdir -p $fw/Versions/A/Resources/Licenses
    cp PDFKit $fw/Versions/A/
    cp -r ${./include}/PDFKit $fw/Versions/A/Headers
    ln -s A $fw/Versions/Current
    ln -s Versions/Current/PDFKit $fw/PDFKit
    ln -s Versions/Current/Headers $fw/Headers
    cp LICENSE* $fw/Versions/A/Resources/Licenses/
  '';
  dontFixup = true;
  dontStrip = true;
}
