# SPDX-License-Identifier: MIT
# Recompile the EXISTING open Foundation overlay plus a scoped URL value bridge.
# Private output only; no other process's Foundation is replaced or installed.
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
in e.pkgs.runCommand "siliconforest-preview-foundation-url-arm64" {} ''
  mkdir -p $out
  cp -rL ${cross}/sdk $out/compiler-sdk
  chmod -R u+w $out/compiler-sdk
  # Reapply the existing Swift runtime recipe's NSDate contract. The generic
  # cross sysroot does not retain this overlay-specific declaration.
  sed -i 's/^@interface NSDate : NSObject$/@interface NSDate : NSObject <NSCopying>/' $out/compiler-sdk/usr/include/Foundation/NSDate.h
  # NSObject's implemented description getters satisfy the nonoptional Swift
  # protocols. State that contract in this private compiler header only.
  sed -i 's/NSString \*description;/NSString * _Nonnull description;/;s/NSString \*debugDescription;/NSString * _Nonnull debugDescription;/' $out/compiler-sdk/usr/include/objc/NSObject.h
  echo '{"CanonicalName":"macosx14.5","Version":"14.5","MaximumDeploymentTarget":"26.5.99","DefaultDeploymentTarget":"14.5"}' > $out/compiler-sdk/SDKSettings.json
  export DARWIN_SDK_ROOT=$out/compiler-sdk
  mkdir -p foundation ovshims $out/usr/lib/swift/Foundation.swiftmodule
  for f in Foundation String Date ReferenceConvertible Boxing NSStringEncodings NSArray NSFastEnumeration; do
    cp ${swift54}/stdlib/public/Darwin/Foundation/$f.swift foundation/
  done
  chmod u+w foundation/*
  (cd foundation && patch -p1 < ${overlay}/Foundation/swift-5.4.3-foundation.patch)
  cp ${overlay}/Foundation/NSString.swift ${overlay}/Foundation/NSDictionary.swift foundation/
  cp ${../../terminal-app/swift/SFBridging.swift} foundation/SFBridging.swift
  cp ${./FoundationURL.swift} foundation/FoundationURL.swift
  cp ${./FoundationErrors.swift} foundation/FoundationErrors.swift
  cp ${./FoundationLocalization.swift} foundation/FoundationLocalization.swift
  cp ${./FoundationCharacterSet.swift} foundation/FoundationCharacterSet.swift
  cp ${swift54}/stdlib/public/SwiftShims/*OverlayShims.h ${swift54}/stdlib/public/SwiftShims/NS*Shims.h \
    ${swift54}/stdlib/public/SwiftShims/FoundationShimSupport.h ${swift54}/stdlib/public/SwiftShims/CFCharacterSetShims.h \
    ${swift54}/stdlib/public/SwiftShims/CFHashingShims.h ovshims/
  awk '/^module _Swift[A-Za-z]*OverlayShims/{p=1} p{print} /^}/{p=0}' \
    ${swift54}/stdlib/public/SwiftShims/module.modulemap > ovshims/module.modulemap
  ${e.cc} -O2 -fblocks -fno-objc-arc -Wno-nullability-completeness -Wno-arc-bridge-casts-disallowed-in-nonarc -isysroot $out/compiler-sdk -DXNU_PLATFORM_MacOSX=1 \
    -I${e.libsystem}/usr/include -I${e.p.libobjc-arm64}/usr/include \
    -I${e.p.foundation-arm64}/usr/include -I${e.p.coreFoundation-arm64}/include \
    -c ${overlay}/Foundation/SFSwiftStringBridge.m -o StringBridge.o
  ${e.p.swift-toolchain}/bin/swiftc -target arm64-apple-macosx26.5 -sdk $out/compiler-sdk \
    -resource-dir ${cross}/resource -I${runtime.dev}/usr/lib/swift \
    -Xcc -fmodule-map-file=${runtime.dev}/usr/lib/swift/shims/module.modulemap \
    -Xcc -DXNU_PLATFORM_MacOSX=1 -Xcc -U__OPTIMIZE__ -Xfrontend -disable-objc-attr-requires-foundation-module \
    -module-name Foundation -module-link-name swiftFoundation \
    -Xfrontend -autolink-force-load -parse-as-library -enable-library-evolution -import-underlying-module \
    -O -wmo -swift-version 5 -D SWIFT_ENABLE_REFLECTION -I$PWD/ovshims \
    -module-cache-path $TMPDIR/modules -emit-module \
    -emit-module-path $out/usr/lib/swift/Foundation.swiftmodule/arm64-apple-macos.swiftmodule \
    -emit-module-interface-path $out/usr/lib/swift/Foundation.swiftmodule/arm64-apple-macos.swiftinterface \
    -emit-object -o Foundation.o foundation/*.swift
  ${e.cc} -dynamiclib Foundation.o StringBridge.o --ld-path=${e.ld} -nostdlib -isysroot ${cross}/sdk \
    -L${e.libsystem}/usr/lib -L${e.p.libobjc-arm64}/usr/lib -L${e.p.foundation-arm64}/usr/lib \
    -L${e.p.coreFoundation-arm64}/usr/lib -L${runtime}/usr/lib/swift \
    -lFoundation -lCoreFoundation -lobjc -lSystem -lswiftCoreFoundation -lswiftObjectiveC -lswiftDarwin -lswiftCore \
    -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib \
    -Wl,-platform_version,macos,26.5,26.5 -Wl,-compatibility_version,1 -Wl,-current_version,1 \
    -Wl,-install_name,/usr/lib/swift/libswiftFoundation.dylib -o $out/usr/lib/swift/libswiftFoundation.dylib
  mkdir -p $out/share/Source $out/share/Licenses
  cp foundation/* $out/share/Source/
  cp ${swift54}/LICENSE.txt $out/share/Licenses/Swift-LICENSE.txt
  cp ${e.finch}/LICENSE-MIT ${e.finch}/LICENSE-APACHE $out/share/Licenses/
  mkdir -p $out/bin
  ${e.p.swift-toolchain}/bin/swiftc -target arm64-apple-macosx26.5 -sdk $out/compiler-sdk \
    -resource-dir ${cross}/resource -I$out/usr/lib/swift -I${runtime.dev}/usr/lib/swift \
    -Xcc -fmodule-map-file=${runtime.dev}/usr/lib/swift/shims/module.modulemap \
    -Xcc -DXNU_PLATFORM_MacOSX=1 -Xcc -U__OPTIMIZE__ -Xfrontend -disable-objc-attr-requires-foundation-module \
    -parse-as-library -O -module-cache-path $TMPDIR/probe-modules -emit-object \
    ${./url-probe.swift} -o URLProbe.o
  ${e.cc} URLProbe.o --ld-path=${e.ld} -nostdlib -isysroot $out/compiler-sdk \
    -L$out/usr/lib/swift -L${runtime}/usr/lib/swift -L${e.libsystem}/usr/lib -L${e.p.libobjc-arm64}/usr/lib \
    -L${e.p.foundation-arm64}/usr/lib -L${e.p.coreFoundation-arm64}/usr/lib \
    -lswiftFoundation -lswiftCoreFoundation -lswiftObjectiveC -lswiftDarwin -lswiftCore \
    -lFoundation -lCoreFoundation -lobjc -lSystem \
    -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib \
    -Wl,-platform_version,macos,26.5,26.5 -o $out/bin/url-probe
  cp ${./url-probe.swift} $out/share/Source/
''
