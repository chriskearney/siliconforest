# SPDX-License-Identifier: MIT
# Private cross-build using open AppKit and a narrow Clang bridge module.
let
  e = import ../environment.nix;
  a = import ../../cocoa/arm64.nix;
  cross = import ../Network/toolchain.nix;
  runtime = import ../../terminal-app/build-swift-runtime.nix;
  url = import ./foundation-url.nix;
in e.pkgs.runCommand "siliconforest-preview-paperkit-view-adapter-arm64" {} ''
  export DARWIN_SDK_ROOT=${e.sdk}
  cp ${./PaperBridge.h} PaperBridge.h
  mkdir framework-headers
  for path in ${a.src}/src/Frameworks/*; do
    name=$(basename "$path")
    case "$name" in Foundation|CoreFoundation) continue;; esac
    ln -s "$path" "framework-headers/$name"
  done
  cat >module.modulemap <<'MAP'
  module SFPaperBridge [system] {
    header "PaperBridge.h"
    export *
  }
  MAP
  CF="-O2 -Wall -Wextra -Werror -Wno-unused-parameter -Wno-nullability-completeness -Wno-arc-bridge-casts-disallowed-in-nonarc -fblocks -fobjc-exceptions -fno-objc-arc -isysroot ${e.sdk} -I$PWD -isystem ${e.libsystem}/usr/include -isystem ${a.base.libobjc}/usr/include -isystem ${a.base.foundation}/usr/include -isystem ${a.base.corefoundation}/include -isystem ${a.appDeps.appkit}/usr/include -isystem ${a.appDeps.coregraphics}/usr/include -isystem ${a.appDeps.onyx2d}/usr/include -isystem ${a.appDeps.quartzcore}/usr/include -isystem ${a.src}/src/Frameworks -isystem ${a.mesa}/usr/include -F${a.openglFramework}/System/Library/Frameworks"
  ${e.cc} $CF -c ${./PaperBridge.m} -o PaperBridge.o
  ${e.p.swift-toolchain}/bin/swiftc -target arm64-apple-macosx26.5 -sdk ${url}/compiler-sdk \
    -resource-dir ${cross}/resource -I${url}/usr/lib/swift -I${runtime.dev}/usr/lib/swift \
    -Xcc -DXNU_PLATFORM_MacOSX=1 -Xcc -U__OPTIMIZE__ -Xfrontend -disable-objc-attr-requires-foundation-module \
    -module-cache-path $TMPDIR/modules -parse-as-library -enable-library-evolution -O -wmo \
    -module-name PaperKit -emit-object -o PaperKit.o -I$PWD \
    -Xcc -isystem -Xcc ${a.appDeps.appkit}/usr/include -Xcc -isystem -Xcc ${a.appDeps.coregraphics}/usr/include \
    -Xcc -isystem -Xcc ${a.appDeps.onyx2d}/usr/include -Xcc -isystem -Xcc ${a.appDeps.quartzcore}/usr/include \
    -Xcc -isystem -Xcc $PWD/framework-headers -Xcc -isystem -Xcc ${a.mesa}/usr/include \
    -Xcc -F${a.openglFramework}/System/Library/Frameworks ${./PaperKit.swift}
  F=$out/System/Library/Frameworks/PaperKit.framework
  mkdir -p $F/Versions/A/Resources/Source $F/Versions/A/Resources/Licenses $out/bin
  ${e.cc} -dynamiclib PaperKit.o PaperBridge.o --ld-path=${e.ld} -nostdlib -isysroot ${e.sdk} \
    -L${e.libsystem}/usr/lib -L${a.base.libobjc}/usr/lib -L${a.base.foundation}/usr/lib \
    -L${a.base.corefoundation}/usr/lib -L${a.appDeps.appkit}/usr/lib -L${url}/usr/lib/swift -L${runtime}/usr/lib/swift \
    -lAppKit -lFoundation -lCoreFoundation -lobjc -lSystem \
    -lswiftFoundation -lswiftCoreFoundation -lswiftObjectiveC -lswiftDarwin -lswiftCore \
    -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib \
    -Wl,-platform_version,macos,26.5,26.5 -Wl,-compatibility_version,1 -Wl,-current_version,344.4.2 \
    -Wl,-install_name,/System/Library/Frameworks/PaperKit.framework/Versions/A/PaperKit \
    -o $F/Versions/A/PaperKit
  ln -s A $F/Versions/Current
  ln -s Versions/Current/PaperKit $F/PaperKit
  ${e.cc} $CF ${./paperkit-probe.m} --ld-path=${e.ld} -nostdlib -isysroot ${e.sdk} \
    -F$out/System/Library/Frameworks -framework PaperKit \
    -L${e.libsystem}/usr/lib -L${a.base.libobjc}/usr/lib -L${a.base.foundation}/usr/lib \
    -L${a.base.corefoundation}/usr/lib -L${a.appDeps.appkit}/usr/lib \
    -lAppKit -lFoundation -lCoreFoundation -lobjc -lSystem \
    -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib \
    -Wl,-platform_version,macos,26.5,26.5 -o $out/bin/paperkit-probe
  cp ${./PaperKit.swift} ${./PaperBridge.h} ${./PaperBridge.m} $F/Versions/A/Resources/Source/
  cp ${./paperkit-probe.m} $F/Versions/A/Resources/Source/
  cp ${./PAPERKIT.md} $F/Versions/A/Resources/
  cp ${../../../../LICENSE} $F/Versions/A/Resources/Licenses/LICENSE-MIT
  cat >$F/Versions/A/Resources/Info.plist <<'PLIST'
  <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>PaperKit</string>
  <key>CFBundleIdentifier</key><string>org.siliconforest.PaperKit</string>
  <key>CFBundleName</key><string>PaperKit</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleVersion</key><string>344.4.2</string>
  </dict></plist>
  PLIST
  ln -s Versions/Current/Resources $F/Resources
''
