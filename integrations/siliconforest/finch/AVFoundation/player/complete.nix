# SPDX-License-Identifier: MIT
# Private complete prefix: retain browser speech/display/auth wrapper, replace
# only its source-built asset/capture child with our player-bearing superset.
let e=import ../../environment.nix; current=import ../../media/bottle/avfoundation-complete.nix; player=import ./build.nix; notices=import ../../AudioToolbox/ffmpeg-licenses.nix;
in e.pkgs.runCommand "siliconforest-avfoundation-player-complete-stage-arm64" {} ''
 mkdir -p $out/System/Library
 cp -R ${current}/System/Library/Frameworks $out/System/Library/
 chmod -R u+w $out
 F=$out/System/Library/Frameworks/AVFoundation.framework/Versions/A
 cp ${player}/System/Library/Frameworks/AVFoundation.framework/Versions/A/AVFoundation $F/AVFoundation.pd
 ${e.p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-install_name_tool -id @loader_path/AVFoundation.pd $F/AVFoundation.pd
 ${e.pkgs.python3}/bin/python3 ${../../../m1-mesa-asahi/tools/cs-rehash.py} $F/AVFoundation.pd
 cp ${./include}/AVFoundation/* $F/Headers/
 cp ${../include}/AVFoundation/AVFoundation.h $F/Headers/SFAssetCore.h
 substituteInPlace $F/Headers/SFAssetCore.h --replace-fail ',*AVCustomMediaSelectionScheme;' '; @class AVCustomMediaSelectionScheme;'
 mkdir -p $F/Resources/Licenses/FFmpeg
 cp ${notices}/* $F/Resources/Licenses/FFmpeg/
 mkdir -p $F/Resources/PlayerSource
 cp ${./SFPlayerMedia.m} $F/Resources/PlayerSource/SFPlayerMedia.m
 cp ${./SFPlayerMedia.h} $F/Resources/PlayerSource/SFPlayerMedia.h
 cp ${./SFPlaybackClock.h} $F/Resources/PlayerSource/SFPlaybackClock.h
''
