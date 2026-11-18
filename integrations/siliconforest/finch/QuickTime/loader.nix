# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
#
# The six libraries QuickTime Player's load commands name that SiliconForest did not have:
# SwiftUI (a binding subset, loader/SwiftUI.swift), DeveloperToolsSupport, libswiftos,
# QuickLook, QuickLookUI and the Quartz umbrella. Linux/Nix with the open Swift toolchain
# and SiliconForest's own headers; no Apple SDK, no Mac. A stage, not an installation.
#
# CGFloat: SwiftUI's frame modifier is mangled with CoreGraphics.CGFloat, which our Swift
# CoreFoundation overlay does not define yet. Finch's CGFloat.swift (Apache-2.0 with the
# Swift Runtime Library Exception, from the Swift project's historical overlay) is compiled
# into the subset from the pinned Finch source; its proper home is libswiftCoreFoundation.
let
 e=import ../environment.nix;
 a=import ../../cocoa/arm64.nix;
 cross=import ../Network/toolchain.nix;
 runtime=import ../../terminal-app/build-swift-runtime.nix;
 headers=import ../media/headers.nix;
in e.pkgs.runCommand "siliconforest-quicktime-loader-libraries-arm64" {} ''
 export DARWIN_SDK_ROOT=${e.sdk}
 CF="-O2 -fblocks -fobjc-exceptions -fno-objc-arc -isysroot ${e.sdk} -I${e.libsystem}/usr/include -I${a.base.libobjc}/usr/include -I${a.base.foundation}/usr/include -I${a.base.corefoundation}/include -I${headers} -I${a.appDeps.coregraphics}/usr/include -I${a.appDeps.onyx2d}/usr/include -I${a.src}/src/Frameworks -I${a.mesa}/usr/include -F${a.openglFramework}/System/Library/Frameworks"
 BASE="--ld-path=${e.ld} -nostdlib -isysroot ${e.sdk} -L${e.libsystem}/usr/lib -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib -Wl,-platform_version,macos,26.5,26.5"
 OBJC="-L${a.base.libobjc}/usr/lib -L${a.base.foundation}/usr/lib -L${a.base.corefoundation}/usr/lib -lFoundation -lCoreFoundation -lobjc -lSystem"
 SWIFT="-L${runtime}/usr/lib/swift -lswiftFoundation -lswiftCoreFoundation -lswiftObjectiveC -lswiftDispatch -lswiftDarwin -lswiftCore -Wl,-rpath,/usr/lib/swift"
 FW=$out/System/Library/Frameworks
 framework() { # name, current version -> directory
  F=$FW/$1.framework;mkdir -p $F/Versions/A/Resources/Source
  ln -s A $F/Versions/Current;ln -s Versions/Current/$1 $F/$1
 }
 swiftlib() { # module, install name, output, sources...
  module=$1;install=$2;output=$3;shift 3
  ${cross}/swiftc -module-cache-path $TMPDIR/modules -parse-as-library -enable-library-evolution -O -wmo -module-name $module -emit-object -o $module.o "$@"
  ${e.cc} -dynamiclib $module.o $BASE $SWIFT $OBJC -Wl,-compatibility_version,1 -Wl,-current_version,1 -Wl,-install_name,$install -o $output
 }

 framework SwiftUI
 swiftlib SwiftUI /System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI $FW/SwiftUI.framework/Versions/A/SwiftUI \
   ${./loader/SwiftUI.swift} ${e.finch}/userland/swift/overlays/CoreFoundation/CGFloat.swift
 cp ${./loader/SwiftUI.swift} $FW/SwiftUI.framework/Versions/A/Resources/Source/
 mkdir -p $FW/SwiftUI.framework/Versions/A/Resources/Licenses
 cp ${e.finch}/LICENSE-APACHE $FW/SwiftUI.framework/Versions/A/Resources/Licenses/CGFloat-LICENSE-APACHE
 cp ${e.finch}/userland/swift/overlays/CoreFoundation/CGFloat.swift $FW/SwiftUI.framework/Versions/A/Resources/Source/

 framework DeveloperToolsSupport
 swiftlib DeveloperToolsSupport /System/Library/Frameworks/DeveloperToolsSupport.framework/Versions/A/DeveloperToolsSupport \
   $FW/DeveloperToolsSupport.framework/Versions/A/DeveloperToolsSupport ${./loader/DeveloperToolsSupport.swift}
 cp ${./loader/DeveloperToolsSupport.swift} $FW/DeveloperToolsSupport.framework/Versions/A/Resources/Source/

 mkdir -p $out/usr/lib/swift
 swiftlib os /usr/lib/swift/libswiftos.dylib $out/usr/lib/swift/libswiftos.dylib ${./loader/os.swift}

 framework QuickLook
 ${e.cc} $CF -DSF_KIND=1 -dynamiclib ${./loader/QuickLook.m} $BASE $OBJC -Wl,-compatibility_version,1 -Wl,-current_version,1 \
   -Wl,-install_name,/System/Library/Frameworks/QuickLook.framework/Versions/A/QuickLook -o $FW/QuickLook.framework/Versions/A/QuickLook
 framework QuickLookUI
 ${e.cc} $CF -DSF_KIND=2 -dynamiclib ${./loader/QuickLook.m} $BASE $OBJC -Wl,-compatibility_version,1 -Wl,-current_version,1 \
   -Wl,-install_name,/System/Library/Frameworks/QuickLookUI.framework/Versions/A/QuickLookUI -o $FW/QuickLookUI.framework/Versions/A/QuickLookUI
 cp ${./loader/QuickLook.m} $FW/QuickLook.framework/Versions/A/Resources/Source/
 cp ${./loader/QuickLook.m} $FW/QuickLookUI.framework/Versions/A/Resources/Source/

 framework Quartz
 ${e.cc} -O2 -isysroot ${e.sdk} -dynamiclib ${./loader/Quartz.c} $BASE -lSystem -Wl,-compatibility_version,1 -Wl,-current_version,1 \
   -Wl,-reexport_library,$FW/QuickLookUI.framework/Versions/A/QuickLookUI \
   -Wl,-install_name,/System/Library/Frameworks/Quartz.framework/Versions/A/Quartz -o $FW/Quartz.framework/Versions/A/Quartz
 cp ${./loader/Quartz.c} $FW/Quartz.framework/Versions/A/Resources/Source/
''
