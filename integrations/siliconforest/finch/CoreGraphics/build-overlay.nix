# SPDX-License-Identifier: MIT
{ foundationURL }:
let
  e = import ../environment.nix;
  a = import ../../cocoa/arm64.nix;
  graphics = a.appDeps.coregraphics;
  cross = import ../Network/toolchain.nix;
  runtime = import ../../terminal-app/build-swift-runtime.nix;
in e.pkgs.runCommand "siliconforest-finch-SwiftCoreGraphicsGeometry-arm64" { } ''
  export DARWIN_SDK_ROOT=${foundationURL}/compiler-sdk
  mkdir -p $out/include/CoreGraphics $out/usr/lib/swift/CoreGraphics.swiftmodule
  cat >$out/include/CoreGraphics/module.modulemap <<'MAP'
  module CoreGraphics [system] {
    header "${graphics}/usr/include/CoreGraphics/CGGeometry.h"
    export *
  }
  MAP
  ${e.p.swift-toolchain}/bin/swiftc -target arm64-apple-macosx26.5 -sdk "$DARWIN_SDK_ROOT" \
    -resource-dir ${cross}/resource -I${foundationURL}/usr/lib/swift -I${runtime.dev}/usr/lib/swift -I$out/include \
    -Xcc -I${graphics}/usr/include -Xcc -fmodule-map-file=${runtime.dev}/usr/lib/swift/shims/module.modulemap \
    -Xcc -DXNU_PLATFORM_MacOSX=1 -Xcc -U__OPTIMIZE__ -Xfrontend -disable-objc-attr-requires-foundation-module \
    -swift-version 5 -parse-as-library -enable-library-evolution -O -module-cache-path "$TMPDIR/modules" \
    -module-name CoreGraphics -import-underlying-module -module-link-name swiftCoreGraphics \
    -emit-module -emit-module-path $out/usr/lib/swift/CoreGraphics.swiftmodule/arm64-apple-macos.swiftmodule \
    -emit-object ${./Geometry.swift} -o Geometry.o
  ${e.cc} -dynamiclib Geometry.o --ld-path=${e.ld} -nostdlib -isysroot "$DARWIN_SDK_ROOT" \
    -L${e.libsystem}/usr/lib -L${graphics}/usr/lib -L${runtime}/usr/lib/swift -lCoreGraphics -lswiftCore -lSystem \
    -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib \
    -Wl,-platform_version,macos,26.5,26.5 -Wl,-compatibility_version,1 -Wl,-current_version,1 \
    -Wl,-install_name,/usr/lib/swift/libswiftCoreGraphics.dylib -o $out/usr/lib/swift/libswiftCoreGraphics.dylib
''
