# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
#
# QuickTime additions: for each framework from which QuickTime Player binds names that
# SiliconForest lacks, a small library with that framework's install name which defines the
# missing names (additions/*.m, *.c) and re-exports "@loader_path/<Name>.sf-under". The
# launcher's preparation step (qt_prefix.py) puts the system's own image of the framework
# there, so the additions sit in front of whatever the machine has today, in a private
# prefix found through DYLD_FRAMEWORK_PATH. Nothing here replaces a system file.
#
# Install names. Each additions library is FOUND at the framework's own path in the prefix, but
# CARRIES the install name "<that path>.sf-additions". dyld (dyld2.cpp, checkandAddImage) folds a
# newly loaded library onto any loaded image with the same install name; with equal names the
# system image under ours was folded onto ours, giving our library itself, or a cycle through a
# SiliconForest wrapper, as its re-exported library ("image not found", or unbounded recursion in
# ImageLoaderMachO::findExportedSymbol: found on the M1, 18 November 2026). dyld matches requests
# by path, never by install name, so a different name changes nothing else.
#
# omit: names of additions to leave out (-DSF_OMIT_<name>) when the system gained them.
#
# movedInFrameworks: the general names have moved into the frameworks themselves (../../cocoa/patches 0340-0347
# and the wrappers of ../../terminal-app/compat, docs/roadmap/issues/SF-AI-quicktime.md "The 112 names", column
# "Provided by"). True (the default): built for a system with those frameworks; the moved names are left out
# (-DSF_MOVED), and CoreFoundation and CoreAudio need no additions at all. False: everything, for a system
# without them (the M1 as installed on 18 November 2026).
{ omit ? [], movedInFrameworks ? true }:
let
 e=import ../environment.nix;
 a=import ../../cocoa/arm64.nix;
 cm=import ../CoreMedia/build.nix;
 # name, the path programs load it by, source, selector macro, link-time stand-in kind
 libs=[
  ["AppKit" "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit" "AppKit.m" "" 1 ""]
  ["Foundation" "/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation" "Foundation.m" "" 4 "-Wl,-reexported_symbols_list,${./additions/foundation-reexports.txt} standin/AppKit-public"]
  ["CoreFoundation" "/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation" "plain.c" "-DSF_LIB=1" 0 ""]
  ["CoreGraphics" "/System/Library/Frameworks/CoreGraphics.framework/Versions/A/CoreGraphics" "plain.c" "-DSF_LIB=2" 0 ""]
  ["CoreServices" "/System/Library/Frameworks/CoreServices.framework/Versions/A/CoreServices" "plain.c" "-DSF_LIB=3" 0 ""]
  ["CoreText" "/System/Library/Frameworks/CoreText.framework/Versions/A/CoreText" "plain.c" "-DSF_LIB=4" 0 ""]
  ["ImageIO" "/System/Library/Frameworks/ImageIO.framework/Versions/A/ImageIO" "plain.c" "-DSF_LIB=5" 0 ""]
  ["Security" "/System/Library/Frameworks/Security.framework/Versions/A/Security" "plain.c" "-DSF_LIB=6" 0 ""]
  ["CoreMedia" "/System/Library/Frameworks/CoreMedia.framework/Versions/A/CoreMedia" "plain.c" "-DSF_LIB=7" 0 ""]
  ["MediaToolbox" "/System/Library/Frameworks/MediaToolbox.framework/Versions/A/MediaToolbox" "plain.c" "-DSF_LIB=8" 0 ""]
  ["CoreAudio" "/System/Library/Frameworks/CoreAudio.framework/Versions/A/CoreAudio" "plain.c" "-DSF_LIB=9" 0 ""]
  ["QuartzCore" "/System/Library/Frameworks/QuartzCore.framework/Versions/A/QuartzCore" "QuartzCore.m" "" 2 ""]
  ["AVFoundation" "/System/Library/Frameworks/AVFoundation.framework/Versions/A/AVFoundation" "AVFoundation.m" "" 3 ""]
  ["AVFAudio" "/System/Library/Frameworks/AVFAudio.framework/Versions/A/AVFAudio" "small.m" "-DSF_LIB=1" 0 ""]
  ["CoreImage" "/System/Library/Frameworks/CoreImage.framework/Versions/A/CoreImage" "small.m" "-DSF_LIB=2" 0 ""]
  ["WebKit" "/System/Library/Frameworks/WebKit.framework/Versions/A/WebKit" "small.m" "-DSF_LIB=3" 0 ""]
 ];
 omitFlags=builtins.concatStringsSep " " (map (n: "-DSF_OMIT_${n}") omit) + (if movedInFrameworks then " -DSF_MOVED" else "");
 # with the moved names in the frameworks these two have nothing left to add
 emptyWhenMoved=[ "CoreFoundation" "CoreAudio" ];
 built=if movedInFrameworks then builtins.filter (l: !(builtins.elem (builtins.elemAt l 0) emptyWhenMoved)) libs else libs;
 one=l: let name=builtins.elemAt l 0; in ''
  ${e.cc} $CF -DSF_STANDIN=${toString (builtins.elemAt l 4)} -dynamiclib ${./additions/standin.m} $LF -Wl,-install_name,@loader_path/${name}.sf-under -o standin/${name}.sf-under
  ${e.cc} $CF ${builtins.elemAt l 3} ${omitFlags} -I${./additions} -dynamiclib ${./additions + "/${builtins.elemAt l 2}"} $LF \
    -Wl,-reexport_library,standin/${name}.sf-under -Wl,-compatibility_version,1 -Wl,-current_version,1 \
    -Wl,-install_name,${builtins.elemAt l 1}.sf-additions ${builtins.elemAt l 5} -o $out/additions/${name}
 '';
 manifest=builtins.toJSON (map (l: { name=builtins.elemAt l 0; load_path=builtins.elemAt l 1; }) built
   ++ [ { name="VideoToolbox"; load_path="/System/Library/Frameworks/VideoToolbox.framework/Versions/A/VideoToolbox"; } ]);
in e.pkgs.runCommand "siliconforest-quicktime-additions${if movedInFrameworks then "" else "-full"}-arm64" {} ''
 export DARWIN_SDK_ROOT=${e.sdk}
 mkdir -p $out/additions $out/source standin
 CF="-O2 -fblocks -fobjc-exceptions -fno-objc-arc -fvisibility=hidden -isysroot ${e.sdk} -I${e.libsystem}/usr/include -I${a.base.libobjc}/usr/include -I${a.base.foundation}/usr/include -I${a.base.corefoundation}/include -I${a.appDeps.coregraphics}/usr/include -I${a.appDeps.onyx2d}/usr/include -I${a.src}/src/Frameworks -I${a.mesa}/usr/include -F${a.openglFramework}/System/Library/Frameworks -Wno-objc-root-class -Wno-incomplete-implementation -Wno-objc-designated-initializers"
 LF="--ld-path=${e.ld} -nostdlib -isysroot ${e.sdk} -L${e.libsystem}/usr/lib -L${a.base.libobjc}/usr/lib -L${a.base.foundation}/usr/lib -L${a.base.corefoundation}/usr/lib -lFoundation -lCoreFoundation -lobjc -lSystem -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib -Wl,-platform_version,macos,26.5,26.5"
 # NSFileWrapper: on this system the class is AppKit's (Cocotron). The Foundation additions
 # re-export AppKit's class symbols instead of defining a second class of the same name.
 ${e.cc} $CF -DSF_STANDIN=5 -dynamiclib ${./additions/standin.m} $LF -Wl,-install_name,/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit -o standin/AppKit-public
 ${builtins.concatStringsSep "\n" (map one built)}
 # VideoToolbox: SF-AB's two capability queries (../QuickTime/VTDecoderQueries.c), packaged the same way.
 ${e.cc} $CF -DSF_STANDIN=0 -dynamiclib ${./additions/standin.m} $LF -Wl,-install_name,@loader_path/VideoToolbox.sf-under -o standin/VideoToolbox.sf-under
 ${e.cc} $CF -fvisibility=default -dynamiclib ${./VTDecoderQueries.c} $LF -F${cm}/System/Library/Frameworks -framework CoreMedia \
   -Wl,-reexport_library,standin/VideoToolbox.sf-under -Wl,-exported_symbol,_VTIsStereoMVHEVCDecodeSupported -Wl,-exported_symbol,_VTCopyVideoDecoderExtensionProperties \
   -Wl,-compatibility_version,1 -Wl,-current_version,1 \
   -Wl,-install_name,/System/Library/Frameworks/VideoToolbox.framework/Versions/A/VideoToolbox.sf-additions -o $out/additions/VideoToolbox
 cp ${./additions}/* ${./VTDecoderQueries.c} $out/source/
 cat > $out/additions/manifest.json <<'MANIFEST'
${manifest}
MANIFEST
''
