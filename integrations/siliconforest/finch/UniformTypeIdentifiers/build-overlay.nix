# SPDX-License-Identifier: MIT
{ foundationURL }:
let
  e = import ../environment.nix;
  a = import ../../cocoa/arm64.nix;
  cross = import ../Network/toolchain.nix;
  runtime = import ../../terminal-app/build-swift-runtime.nix;
in e.pkgs.runCommand "siliconforest-finch-SwiftUTType-arm64" { } ''
  export DARWIN_SDK_ROOT=${foundationURL}/compiler-sdk
  mkdir -p $out/include/SFUTTypeBridge $out/usr/lib/swift/UniformTypeIdentifiers.swiftmodule
  cp ${./UTTypeBridge.h} $out/include/SFUTTypeBridge/UTTypeBridge.h
  cat >$out/include/SFUTTypeBridge/module.modulemap <<'MAP'
  module SFUTTypeBridge [system] {
    header "UTTypeBridge.h"
    export *
  }
  MAP
  ${e.p.swift-toolchain}/bin/swiftc -target arm64-apple-macosx26.5 -sdk "$DARWIN_SDK_ROOT" \
    -resource-dir ${cross}/resource -I${foundationURL}/usr/lib/swift -I${runtime.dev}/usr/lib/swift -I$out/include \
    -Xcc -fmodule-map-file=${runtime.dev}/usr/lib/swift/shims/module.modulemap \
    -Xcc -DXNU_PLATFORM_MacOSX=1 -Xcc -U__OPTIMIZE__ -Xfrontend -disable-objc-attr-requires-foundation-module \
    -swift-version 5 -parse-as-library -enable-library-evolution -O -module-cache-path "$TMPDIR/modules" \
    -module-name UniformTypeIdentifiers -module-link-name swiftUniformTypeIdentifiers \
    -emit-module -emit-module-path $out/usr/lib/swift/UniformTypeIdentifiers.swiftmodule/arm64-apple-macos.swiftmodule \
    -emit-object ${./UTType.swift} -o UTType.o
  ${e.cc} -dynamiclib UTType.o --ld-path=${e.ld} -nostdlib -isysroot "$DARWIN_SDK_ROOT" \
    -L${e.libsystem}/usr/lib -L${a.base.libobjc}/usr/lib -L${foundationURL}/usr/lib/swift -L${runtime}/usr/lib/swift \
    -F${a.appFrameworks}/System/Library/Frameworks -framework UniformTypeIdentifiers \
    -lobjc -lswiftFoundation -lswiftCoreFoundation -lswiftDarwin -lswiftObjectiveC -lswiftCore -lSystem \
    -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib \
    -Wl,-platform_version,macos,26.5,26.5 -Wl,-compatibility_version,1 -Wl,-current_version,1 \
    -Wl,-install_name,/usr/lib/swift/libswiftUniformTypeIdentifiers.dylib \
    -o $out/usr/lib/swift/libswiftUniformTypeIdentifiers.dylib
''
