# SPDX-License-Identifier: MIT
# Private original reader candidate only; no installation or target execution.
let
  e = import ../environment.nix;
  a = import ../../cocoa/arm64.nix;
  foundation = a.base.foundation;
  cf = a.base.corefoundation;
  objc = a.base.libobjc;
  cg = a.appDeps.coregraphics;
  onyx = a.appDeps.onyx2d;
in e.pkgs.runCommand "siliconforest-preview-annotationkit-reader-arm64" {} ''
  export DARWIN_SDK_ROOT=${e.sdk}
  cp ${./AnnotationKit.h} AnnotationKit.h
  CF="-O2 -Wall -Wextra -Werror -Wno-unused-parameter -fblocks -fobjc-exceptions -fexceptions -fobjc-arc-exceptions -fobjc-arc -isysroot ${e.sdk} -I$PWD -isystem ${e.libsystem}/usr/include -isystem ${objc}/usr/include -isystem ${foundation}/usr/include -isystem ${cf}/include -isystem ${cg}/usr/include -isystem ${onyx}/usr/include -isystem ${a.appDeps.appkit}/usr/include -isystem ${a.appDeps.quartzcore}/usr/include -isystem ${a.src}/src/Frameworks -isystem ${a.mesa}/usr/include -F${a.openglFramework}/System/Library/Frameworks"
  LF="--ld-path=${e.ld} -nostdlib -isysroot ${e.sdk} -L${e.libsystem}/usr/lib -L${objc}/usr/lib -L${foundation}/usr/lib -L${cf}/usr/lib -L${cg}/usr/lib -L${a.appDeps.appkit}/usr/lib -lAppKit -lCoreGraphics -lFoundation -lCoreFoundation -lobjc -lSystem -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib -Wl,-platform_version,macos,26.5,26.5"
  F=$out/System/Library/PrivateFrameworks/AnnotationKit.framework
  mkdir -p $F/Versions/A/Resources/Source $F/Versions/A/Resources/Licenses $out/bin
  ${e.cc} $CF -c ${./AnnotationKit.m} -o AnnotationKit.o
  ${e.cc} -dynamiclib AnnotationKit.o $LF -Wl,-compatibility_version,1 -Wl,-current_version,1 \
    -Wl,-install_name,/System/Library/PrivateFrameworks/AnnotationKit.framework/Versions/A/AnnotationKit \
    -o $F/Versions/A/AnnotationKit
  ln -s A $F/Versions/Current
  ln -s Versions/Current/AnnotationKit $F/AnnotationKit
  ${e.cc} $CF ${./annotationkit-probe.m} $LF -F$out/System/Library/PrivateFrameworks \
    -framework AnnotationKit -o $out/bin/annotationkit-probe
  cp ${./AnnotationKit.h} ${./AnnotationKit.m} ${./annotationkit-probe.m} $F/Versions/A/Resources/Source/
  cp ${./ANNOTATIONKIT.md} $F/Versions/A/Resources/
  cp ${../../../../LICENSE} $F/Versions/A/Resources/Licenses/LICENSE-MIT
  cat >$F/Versions/A/Resources/Info.plist <<'PLIST'
  <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>AnnotationKit</string>
  <key>CFBundleIdentifier</key><string>org.siliconforest.AnnotationKit</string>
  <key>CFBundleName</key><string>AnnotationKit</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleVersion</key><string>1</string>
  </dict></plist>
  PLIST
  ln -s Versions/Current/Resources $F/Resources
''
