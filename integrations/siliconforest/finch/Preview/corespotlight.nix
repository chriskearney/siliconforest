# SPDX-License-Identifier: MIT OR Apache-2.0
# Explicit coordinator-owned UTType input; no private artifacts or global install.
{ uniformTypeIdentifiers, foundationURL ? import ./foundation-url.nix }:
let
  e = import ../environment.nix;
  cross = import ../Network/toolchain.nix;
  runtime = import ../../terminal-app/build-swift-runtime.nix;
  finch = import ../source.nix;
in e.pkgs.runCommand "siliconforest-preview-corespotlight-attributes-swift-arm64" {} ''
  export DARWIN_SDK_ROOT=${foundationURL}/compiler-sdk
  F=$out/System/Library/Frameworks/CoreSpotlight.framework
  mkdir -p $F/Versions/A/Resources/Source $F/Versions/A/Resources/Licenses \
    $out/include/SFCoreSpotlightAttributesBridge $out/usr/lib/swift/CoreSpotlight.swiftmodule $out/bin
  cp ${./CoreSpotlightAttributes.h} CoreSpotlightAttributes.h
  cp ${./CoreSpotlightAttributes.h} $out/include/SFCoreSpotlightAttributesBridge/CoreSpotlightAttributes.h
  cat >$out/include/SFCoreSpotlightAttributesBridge/module.modulemap <<'MAP'
  module SFCoreSpotlightAttributesBridge [system] {
    header "CoreSpotlightAttributes.h"
    export *
  }
  MAP
  CF="-O2 -Wall -Wextra -Werror -Wno-unused-parameter -Wno-nullability-completeness -fblocks -fobjc-exceptions -fexceptions -fobjc-arc-exceptions -fobjc-arc -isysroot ${e.sdk} -I$PWD -isystem ${e.libsystem}/usr/include -isystem ${e.p.libobjc-arm64}/usr/include -isystem ${e.p.foundation-arm64}/usr/include -isystem ${e.p.coreFoundation-arm64}/include"
  ${e.cc} $CF -c ${./CoreSpotlightAttributes.m} -o Attributes.o
  SW="-target arm64-apple-macosx26.5 -sdk $DARWIN_SDK_ROOT -resource-dir ${cross}/resource -I${foundationURL}/usr/lib/swift -I${runtime.dev}/usr/lib/swift -I${uniformTypeIdentifiers}/usr/lib/swift -I${uniformTypeIdentifiers}/include -I$out/include -Xcc -fmodule-map-file=${runtime.dev}/usr/lib/swift/shims/module.modulemap -Xcc -DXNU_PLATFORM_MacOSX=1 -Xcc -U__OPTIMIZE__ -Xfrontend -disable-objc-attr-requires-foundation-module -module-cache-path $TMPDIR/modules -parse-as-library -O -wmo"
  ${e.p.swift-toolchain}/bin/swiftc $SW -enable-library-evolution -module-name CoreSpotlight \
    -module-link-name CoreSpotlight -emit-module \
    -emit-module-path $out/usr/lib/swift/CoreSpotlight.swiftmodule/arm64-apple-macos.swiftmodule \
    -emit-object -o CoreSpotlightSwift.o ${./CoreSpotlightAttributes.swift}
  LF="--ld-path=${e.ld} -nostdlib -isysroot ${e.sdk} -L${e.libsystem}/usr/lib -L${e.p.libobjc-arm64}/usr/lib -L${e.p.foundation-arm64}/usr/lib -L${e.p.coreFoundation-arm64}/usr/lib -L${foundationURL}/usr/lib/swift -L${runtime}/usr/lib/swift -L${uniformTypeIdentifiers}/usr/lib/swift -lFoundation -lCoreFoundation -lobjc -lSystem -lswiftFoundation -lswiftCoreFoundation -lswiftObjectiveC -lswiftDarwin -lswiftCore -lswiftUniformTypeIdentifiers -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib -Wl,-platform_version,macos,26.5,26.5"
  ${e.cc} -dynamiclib Attributes.o CoreSpotlightSwift.o $LF \
    -Wl,-install_name,/System/Library/Frameworks/CoreSpotlight.framework/Versions/A/CoreSpotlight \
    -Wl,-compatibility_version,1 -Wl,-current_version,2418.4.13 -o $F/Versions/A/CoreSpotlight
  ln -s A $F/Versions/Current
  ln -s Versions/Current/CoreSpotlight $F/CoreSpotlight
  ${e.p.swift-toolchain}/bin/swiftc $SW -I$out/usr/lib/swift -emit-object -o SwiftProbe.o ${./corespotlight-swift-probe.swift}
  ${e.cc} SwiftProbe.o $LF -F$out/System/Library/Frameworks -framework CoreSpotlight -o $out/bin/corespotlight-swift-probe
  ${e.cc} $CF -fno-objc-arc -Wno-nonnull ${./corespotlight-attributes-probe.m} $LF \
    -F$out/System/Library/Frameworks -framework CoreSpotlight -o $out/bin/corespotlight-attributes-probe
  cp ${./CoreSpotlightAttributes.h} ${./CoreSpotlightAttributes.m} ${./CoreSpotlightAttributes.swift} \
    ${./corespotlight-attributes-probe.m} ${./corespotlight-swift-probe.swift} $F/Versions/A/Resources/Source/
  cp ${./CORESPOTLIGHT.md} $F/Versions/A/Resources/
  cp ${finch}/LICENSE-MIT ${finch}/LICENSE-APACHE $F/Versions/A/Resources/Licenses/
  cat >$F/Versions/A/Resources/Info.plist <<'PLIST'
  <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>CoreSpotlight</string>
  <key>CFBundleIdentifier</key><string>org.siliconforest.CoreSpotlight.Attributes</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleVersion</key><string>2418.4.13</string>
  </dict></plist>
  PLIST
  ln -s Versions/Current/Resources $F/Resources
''
