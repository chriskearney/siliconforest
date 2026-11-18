# SPDX-License-Identifier: MIT
# Non-GUI asset demux/mux, metadata, sample cursors and compressed passthrough.
let
  e = import ../environment.nix;
  a = import ../../cocoa/arm64.nix;
  inherit (e) pkgs p finch libsystem sdk cc ld;
  cm = import ../CoreMedia/build.nix;
  cv = import ../CoreVideo/build.nix;
  at = import ../AudioToolbox/build.nix;
  av = import ../AVFAudio/build.nix;
  headers = import ../media/headers.nix;
in pkgs.stdenv.mkDerivation {
  name = "siliconforest-finch-AVFoundation-assets-arm64";
  src = finch;
  patches = [ ./patches/0001-asset-reader-without-video-composition.patch ./patches/0002-retained-foundation-date-and-file-apis.patch ./patches/0003-retained-locale-scanner-methods.patch ./patches/0004-retained-nsvalue-getvalue.patch ./patches/0005-media-selection-locale-api.patch ./patches/0006-full-track-video-edit-offset.patch ];
  dontConfigure = true;
  buildPhase = ''
    export DARWIN_SDK_ROOT=${sdk}
    mkdir -p objects headers/AudioToolbox
    cp ${at}/System/Library/Frameworks/AudioToolbox.framework/Versions/A/Headers/Generated.h headers/AudioToolbox/
    CF="-isysroot ${sdk} -mmacosx-version-min=26.5 -O2 -fblocks -fobjc-exceptions -fobjc-arc -D_DARWIN_C_SOURCE -Wno-nullability-completeness -Wno-macro-redefined -Wno-incomplete-implementation -I${./include} -I${headers} -I${../AudioToolbox/include} -I${../AVFAudio/include} -I$PWD/headers -I${p.foundation-arm64}/usr/include -I${p.coreFoundation-arm64}/include -I${p.libobjc-arm64}/usr/include -I${libsystem}/usr/include -I${p.coreServices-arm64}/usr/include -I${p.coregraphics-arm64}/usr/include -I${p.onyx2d-arm64}/usr/include -I${e.pd.outPath}/src/Frameworks -I${a.mesa}/usr/include -F${a.openglFramework}/System/Library/Frameworks"
    for name in AVFMovie AVAsset AVAssetReader AVAssetWriter AVMetadataItem AVMetadataTables AVFConstants AVFTypes AVTime AVTimedMetadataGroup AVMediaSelection AVSampleCursor AVAssetWriterInputGroup; do
      ${cc} $CF -c userland/AVFoundation/$name.m -o objects/$name.o
    done
    ${cc} $CF -c ${./media-dates.m} -o objects/media-dates.o
    ${cc} -dynamiclib objects/*.o --ld-path=${ld} -nostdlib -isysroot ${sdk} -L${libsystem}/usr/lib -L${libsystem}/usr/lib/system -L${p.foundation-arm64}/usr/lib -L${p.coreFoundation-arm64}/usr/lib -L${p.libobjc-arm64}/usr/lib -L${p.coregraphics-arm64}/usr/lib -L${p.onyx2d-arm64}/usr/lib -F${cm}/System/Library/Frameworks -F${cv}/System/Library/Frameworks -F${at}/System/Library/Frameworks -F${av}/System/Library/Frameworks -F${a.appFrameworks}/System/Library/Frameworks -framework CoreMedia -framework CoreVideo -framework AudioToolbox -Wl,-reexport_framework,AVFAudio -framework UniformTypeIdentifiers -lCoreGraphics -lFoundation -lCoreFoundation -lobjc -lSystem -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libsystem}/usr/lib/system/libdyld.dylib -Wl,-platform_version,macos,26.5,26.5 -install_name /System/Library/Frameworks/AVFoundation.framework/Versions/A/AVFoundation -current_version 2 -compatibility_version 1 -o AVFoundation
  '';
  installPhase = ''
    fw=$out/System/Library/Frameworks/AVFoundation.framework
    mkdir -p $fw/Versions/A/Resources/Licenses
    cp AVFoundation $fw/Versions/A/
    cp -r ${./include}/AVFoundation $fw/Versions/A/Headers
    ln -s A $fw/Versions/Current
    ln -s Versions/Current/AVFoundation $fw/AVFoundation
    ln -s Versions/Current/Headers $fw/Headers
    ln -s Versions/Current/Resources $fw/Resources
    cp LICENSE* $fw/Versions/A/Resources/Licenses/
  '';
  dontFixup = true;
  dontStrip = true;
}
