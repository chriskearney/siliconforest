# SPDX-License-Identifier: MIT
let
 e=import ../environment.nix;
 a=import ../../cocoa/arm64.nix;
 inherit(e) pkgs p libsystem cc ld sdk finch;
 player=import ../AVFoundation/player/complete.nix;
 mediaHeaders=import ../media/headers.nix;
 cm=import ../CoreMedia/build.nix;
 toolbox=import ../AudioToolbox/build.nix;
 avaudio=import ../AVFAudio/build.nix;
in pkgs.stdenv.mkDerivation {
 name="siliconforest-finch-AVKit-stage-arm64";
 src=finch;
 nativeBuildInputs=[pkgs.python3];
 postPatch=''python3 ${./player-view.py} userland/AVKit/AVKit.m'';
 dontConfigure=true;
 buildPhase=''
  export DARWIN_SDK_ROOT=${sdk}
  mkdir -p playerheaders/AVFoundation objects headers/AudioToolbox
  cp ${toolbox}/System/Library/Frameworks/AudioToolbox.framework/Versions/A/Headers/Generated.h headers/AudioToolbox/
  cp ${../AVFoundation/include}/AVFoundation/AVFoundation.h playerheaders/AVFoundation/SFAssetCore.h
  substituteInPlace playerheaders/AVFoundation/SFAssetCore.h --replace-fail ',*AVCustomMediaSelectionScheme;' '; @class AVCustomMediaSelectionScheme;'
  CF="-isysroot ${sdk} -mmacosx-version-min=26.5 -O2 -fblocks -fobjc-exceptions -fno-objc-arc -D_DARWIN_C_SOURCE -Wno-nullability-completeness -Wno-macro-redefined -I$PWD/headers -I${./.} -I${./include} -I${../AVFoundation/player/include} -I$PWD/playerheaders -I${../AVFoundation/include} -I${mediaHeaders} -I${../AVFAudio/engine/include} -I${../AVFAudio/include} -I${../AudioToolbox/include} -I${p.foundation-arm64}/usr/include -I${p.coreFoundation-arm64}/include -I${p.libobjc-arm64}/usr/include -I${libsystem}/usr/include -I${p.coregraphics-arm64}/usr/include -I${p.onyx2d-arm64}/usr/include -I${a.appDeps.quartzcore}/usr/include -I${a.appDeps.appkit}/usr/include -I${e.pd.outPath}/src/Frameworks -I${a.mesa}/usr/include -F${a.openglFramework}/System/Library/Frameworks"
  ${cc} $CF -c userland/AVKit/AVKit.m -o objects/AVKit.o
  ${cc} $CF -c ${./SFTransport.m} -o objects/SFTransport.o
  ${cc} $CF -c ${./SFAudioLevel.m} -o objects/SFAudioLevel.o
  ${cc} $CF -c ${./SFCaptureInputItem.m} -o objects/SFCaptureInputItem.o
  ${cc} $CF -c ${./SFUnavailableCaptureView.m} -o objects/SFUnavailableCaptureView.o
  ${cc} $CF -c ${./SFPlayerController.m} -o objects/SFPlayerController.o
  ${cc} $CF -c ${./SFQuickTimePlayerView.m} -o objects/SFQuickTimePlayerView.o
  ${cc} $CF -c ${./SFQuickTimeControls.m} -o objects/SFQuickTimeControls.o
  ${cc} $CF -c ${./ranges.c} -o objects/ranges.o
  ${cc} $CF -c ${./values.m} -o objects/values.o
  ${cc} -dynamiclib objects/*.o --ld-path=${ld} -nostdlib -isysroot ${sdk} -L${libsystem}/usr/lib -L${p.foundation-arm64}/usr/lib -L${p.coreFoundation-arm64}/usr/lib -L${p.libobjc-arm64}/usr/lib -L${p.coregraphics-arm64}/usr/lib -F${cm}/System/Library/Frameworks -framework CoreMedia -F${player}/System/Library/Frameworks -F${avaudio}/System/Library/Frameworks -framework AVFoundation -Wl,-dylib_file,@loader_path/AVFoundation.pd:${player}/System/Library/Frameworks/AVFoundation.framework/Versions/A/AVFoundation.pd -L${a.appDeps.appkit}/usr/lib -L${a.appDeps.quartzcore}/usr/lib -lAppKit -lQuartzCore -lFoundation -lCoreFoundation -lCoreGraphics -lobjc -lSystem -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libsystem}/usr/lib/system/libdyld.dylib -Wl,-platform_version,macos,26.5,26.5 -install_name /System/Library/Frameworks/AVKit.framework/Versions/A/AVKit -o AVKit
 '';
 installPhase=''
  fw=$out/System/Library/Frameworks/AVKit.framework
  mkdir -p $fw/Versions/A/Resources/Licenses
  cp AVKit $fw/Versions/A/
  cp -r ${./include}/AVKit $fw/Versions/A/Headers
  ln -s A $fw/Versions/Current
  ln -s Versions/Current/AVKit $fw/AVKit
  cp LICENSE* $fw/Versions/A/Resources/Licenses/
 '';
 dontFixup=true;dontStrip=true;
}
