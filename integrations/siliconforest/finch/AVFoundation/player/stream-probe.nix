# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# stream-probe (./stream-probe.m): the streamed SFPlayerMedia on the machine, no window, sound at volume 0.
let
 e=import ../../environment.nix;
 a=import ../../../cocoa/arm64.nix;
 inherit(e) pkgs p cc ld sdk libsystem;
 player=import ./complete.nix;
 cm=import ../../CoreMedia/build.nix;
 av=import ../../AVFAudio/build.nix;
 at=import ../../AudioToolbox/build.nix;
 headers=import ../../media/headers.nix;
in pkgs.runCommand "siliconforest-avfoundation-stream-probe-arm64" {} ''
 export DARWIN_SDK_ROOT=${sdk}
 mkdir -p $out/bin headers/AudioToolbox headers/AVFoundation
 cp ${at}/System/Library/Frameworks/AudioToolbox.framework/Versions/A/Headers/Generated.h headers/AudioToolbox/
 cp ${../include}/AVFoundation/AVFoundation.h headers/AVFoundation/SFAssetCore.h
 substituteInPlace headers/AVFoundation/SFAssetCore.h --replace-fail ',*AVCustomMediaSelectionScheme;' '; @class AVCustomMediaSelectionScheme;'
 ${cc} -isysroot ${sdk} -mmacosx-version-min=26.5 -O2 -fblocks -fobjc-exceptions -fobjc-arc -I$PWD/headers -I${./.} -I${./include} -I${../include} -I${../../AVFAudio/engine/include} -I${../../AVFAudio/include} -I${../../AudioToolbox/include} -I${headers} -I${libsystem}/usr/include -I${p.foundation-arm64}/usr/include -I${p.coreFoundation-arm64}/include -I${p.libobjc-arm64}/usr/include -I${p.coregraphics-arm64}/usr/include -I${p.onyx2d-arm64}/usr/include -I${a.appDeps.appkit}/usr/include -I${a.appDeps.quartzcore}/usr/include -I${e.pd.outPath}/src/Frameworks -I${a.mesa}/usr/include -F${a.openglFramework}/System/Library/Frameworks ${./stream-probe.m} --ld-path=${ld} -nostdlib -L${libsystem}/usr/lib -L${p.foundation-arm64}/usr/lib -L${p.coreFoundation-arm64}/usr/lib -L${p.libobjc-arm64}/usr/lib -L${p.coregraphics-arm64}/usr/lib -L${a.appDeps.quartzcore}/usr/lib -F${player}/System/Library/Frameworks -F${av}/System/Library/Frameworks -F${cm}/System/Library/Frameworks -framework CoreMedia -framework AVFoundation -Wl,-dylib_file,@loader_path/AVFoundation.pd:${player}/System/Library/Frameworks/AVFoundation.framework/Versions/A/AVFoundation.pd -lCoreGraphics -lFoundation -lCoreFoundation -lobjc -lSystem -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libsystem}/usr/lib/system/libdyld.dylib -Wl,-platform_version,macos,26.5,26.5 -o $out/bin/stream-probe
''
