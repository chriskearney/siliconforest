# SPDX-License-Identifier: MIT
# Rebuild the existing coherent Foundation overlay with one additive UUID source.
# No URL/Data edits, system install, target connection or application execution.
{ baseFoundation ? import ./foundation-url.nix }:
let
  e = import ../environment.nix;
  cross = import ../Network/toolchain.nix;
  runtime = import ../../terminal-app/build-swift-runtime.nix;
  overlay = "${e.pd.outPath}/src/Libraries/SwiftOverlays";
  swift54 = e.pkgs.fetchFromGitHub {
    owner = "swiftlang"; repo = "swift"; rev = "swift-5.4.3-RELEASE";
    sparseCheckout = [ "stdlib/public/Darwin" "stdlib/public/SwiftShims" ];
    hash = "sha256-9hXo8I4QAGWJ4ZXIfBtTExQ9+IBmVxeKuyC6guDW9t0=";
  };
in e.pkgs.runCommand "siliconforest-preview-foundation-uuid-arm64" {} ''
  export DARWIN_SDK_ROOT=${baseFoundation}/compiler-sdk
  mkdir -p foundation $out/usr/lib/swift/Foundation.swiftmodule $out/include/SFUUIDRuntime $out/lib $out/bin $out/share/Source $out/share/Licenses
  for source in ${baseFoundation}/share/Source/*.swift; do
    case "$(basename "$source")" in *probe.swift) continue;; esac
    cp "$source" foundation/
  done
  mkdir ovshims
  cp ${swift54}/stdlib/public/SwiftShims/*OverlayShims.h ${swift54}/stdlib/public/SwiftShims/NS*Shims.h \
    ${swift54}/stdlib/public/SwiftShims/FoundationShimSupport.h ${swift54}/stdlib/public/SwiftShims/CFCharacterSetShims.h \
    ${swift54}/stdlib/public/SwiftShims/CFHashingShims.h ovshims/
  awk '/^module _Swift[A-Za-z]*OverlayShims/{p=1} p{print} /^}/{p=0}' \
    ${swift54}/stdlib/public/SwiftShims/module.modulemap > ovshims/module.modulemap
  cp ${./FoundationUUID.swift} foundation/FoundationUUID.swift
  cp ${./UUIDRuntime.h} $out/include/SFUUIDRuntime/UUIDRuntime.h
  cat >$out/include/SFUUIDRuntime/module.modulemap <<'MAP'
  module SFUUIDRuntime [system] {
    header "UUIDRuntime.h"
    export *
  }
  MAP
  # Same open C string bridge and SDK as the baseline; preserve one Foundation.
  ${e.cc} -O2 -fblocks -fno-objc-arc -Wno-nullability-completeness -Wno-arc-bridge-casts-disallowed-in-nonarc \
    -isysroot $DARWIN_SDK_ROOT -DXNU_PLATFORM_MacOSX=1 -I${e.libsystem}/usr/include \
    -I${e.p.libobjc-arm64}/usr/include -I${e.p.foundation-arm64}/usr/include -I${e.p.coreFoundation-arm64}/include \
    -c ${overlay}/Foundation/SFSwiftStringBridge.m -o StringBridge.o
  SW="-target arm64-apple-macosx26.5 -sdk $DARWIN_SDK_ROOT -resource-dir ${cross}/resource -I${runtime.dev}/usr/lib/swift -I$out/include -I$PWD/ovshims -Xcc -fmodule-map-file=${runtime.dev}/usr/lib/swift/shims/module.modulemap -Xcc -DXNU_PLATFORM_MacOSX=1 -Xcc -U__OPTIMIZE__ -Xfrontend -disable-objc-attr-requires-foundation-module -parse-as-library -enable-library-evolution -O -wmo -swift-version 5 -module-cache-path $TMPDIR/modules"
  ${e.p.swift-toolchain}/bin/swiftc $SW -module-name Foundation -module-link-name swiftFoundation \
    -Xfrontend -autolink-force-load -import-underlying-module -D SWIFT_ENABLE_REFLECTION \
    -emit-module -emit-module-path $out/usr/lib/swift/Foundation.swiftmodule/arm64-apple-macos.swiftmodule \
    -emit-module-interface-path $out/usr/lib/swift/Foundation.swiftmodule/arm64-apple-macos.swiftinterface \
    -emit-object -o Foundation.o foundation/*.swift
  LF="--ld-path=${e.ld} -nostdlib -isysroot $DARWIN_SDK_ROOT -L${e.libsystem}/usr/lib -L${e.p.libobjc-arm64}/usr/lib -L${e.p.foundation-arm64}/usr/lib -L${e.p.coreFoundation-arm64}/usr/lib -L${runtime}/usr/lib/swift -lFoundation -lCoreFoundation -lobjc -lSystem -lswiftCoreFoundation -lswiftObjectiveC -lswiftDarwin -lswiftCore -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib -Wl,-platform_version,macos,26.5,26.5"
  ${e.cc} -dynamiclib Foundation.o StringBridge.o $LF \
    -Wl,-install_name,/usr/lib/swift/libswiftFoundation.dylib -Wl,-compatibility_version,1 -Wl,-current_version,1 \
    -o $out/usr/lib/swift/libswiftFoundation.dylib
  ${e.p.swift-toolchain}/bin/swiftc -I$out/usr/lib/swift $SW -module-name UUIDInteropClient \
    -module-link-name UUIDInteropClient -emit-module -emit-module-path $out/lib/UUIDInteropClient.swiftmodule \
    -emit-object -o Client.o ${./uuid-client.swift}
  ${e.cc} -dynamiclib Client.o -L$out/usr/lib/swift $LF -lswiftFoundation \
    -Wl,-install_name,@rpath/libUUIDInteropClient.dylib -o $out/lib/libUUIDInteropClient.dylib
  ${e.p.swift-toolchain}/bin/swiftc -I$out/usr/lib/swift $SW -I$out/lib -emit-object -o Probe.o ${./uuid-probe.swift}
  ${e.cc} Probe.o -L$out/usr/lib/swift $LF -lswiftFoundation -L$out/lib -lUUIDInteropClient \
    -Wl,-rpath,@executable_path/../lib -o $out/bin/uuid-probe
  cp ${baseFoundation}/bin/url-probe $out/bin/legacy-url-probe
  cp foundation/* ${./UUIDRuntime.h} ${./uuid-client.swift} ${./uuid-probe.swift} $out/share/Source/
  cp ${baseFoundation}/share/Licenses/* $out/share/Licenses/
  cp ${../../../../LICENSES/Swift-Foundation.txt} $out/share/Licenses/Swift-Foundation-LICENSE.txt
''
