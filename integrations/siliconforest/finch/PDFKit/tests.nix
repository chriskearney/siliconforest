# SPDX-License-Identifier: MIT
# Public PDF probes link the retained providers and load PDFKit at runtime.
let
  e = import ../environment.nix;
  a = import ../../cocoa/arm64.nix;
  inherit (e) pkgs p finch libsystem sdk cc ld;
  appkit = a.appDeps.appkit;
in pkgs.stdenv.mkDerivation {
  name = "siliconforest-finch-PDFKit-documents-tests-arm64";
  dontUnpack = true;
  dontConfigure = true;
  buildPhase = ''
    export DARWIN_SDK_ROOT=${sdk}
    CF="-isysroot ${sdk} -mmacosx-version-min=26.5 -O2 -fblocks -fobjc-exceptions -fno-objc-arc -D_DARWIN_C_SOURCE -Wno-nullability-completeness -Wno-macro-redefined -Wno-incomplete-implementation -I${./include} -I${appkit}/usr/include -I${p.foundation-arm64}/usr/include -I${p.coreFoundation-arm64}/include -I${p.libobjc-arm64}/usr/include -I${p.coregraphics-arm64}/usr/include -I${p.coretext-arm64}/usr/include -I${p.onyx2d-arm64}/usr/include -I${e.pd.outPath}/src/Frameworks -I${e.pd.outPath}/src/Frameworks/OpenGL/include -I${a.mesa}/usr/include"
    linkFlags="--ld-path=${ld} -nostdlib -isysroot ${sdk} -L${libsystem}/usr/lib -L${libsystem}/usr/lib/system -L${p.foundation-arm64}/usr/lib -L${p.coreFoundation-arm64}/usr/lib -L${p.libobjc-arm64}/usr/lib -L${p.coregraphics-arm64}/usr/lib -L${p.coretext-arm64}/usr/lib -lCoreGraphics -lCoreText -lFoundation -lCoreFoundation -lobjc -lSystem -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libsystem}/usr/lib/system/libdyld.dylib -Wl,-platform_version,macos,26.5,26.5"
    ${cc} $CF -c ${./probe.m} -o document.o
    ${cc} $CF -c ${./view-probe.m} -o view.o
    ${cc} $CF -c ${./preview-support-probe.m} -o preview-support.o
    ${cc} preview-support.o $linkFlags -o pdfkit-preview-support-probe
    ${cc} document.o $linkFlags -o pdfkit-document-probe
    ${cc} view.o $linkFlags -o pdfkit-view-probe
  '';
  installPhase = ''mkdir -p $out/bin; cp pdfkit-{document,view,preview-support}-probe $out/bin/'';
  dontFixup = true;
  dontStrip = true;
}
