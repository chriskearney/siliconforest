# SPDX-License-Identifier: MIT OR Apache-2.0
# Finch attribute/key storage only. No index, query, service, or installation.
let
  e = import ../environment.nix;
  finch = import ../source.nix;
  foundation = e.p.foundation-arm64;
  cf = e.p.coreFoundation-arm64;
  objc = e.p.libobjc-arm64;
in e.pkgs.runCommand "siliconforest-preview-corespotlight-attributes-arm64" {} ''
  export DARWIN_SDK_ROOT=${e.sdk}
  cp ${./CoreSpotlightAttributes.h} CoreSpotlightAttributes.h
  CF="-O2 -Wall -Wextra -Werror -Wno-unused-parameter -Wno-nullability-completeness -fblocks -fobjc-exceptions -fexceptions -fobjc-arc-exceptions -fobjc-arc -isysroot ${e.sdk} -I$PWD -isystem ${e.libsystem}/usr/include -isystem ${objc}/usr/include -isystem ${foundation}/usr/include -isystem ${cf}/include"
  LF="--ld-path=${e.ld} -nostdlib -isysroot ${e.sdk} -L${e.libsystem}/usr/lib -L${objc}/usr/lib -L${foundation}/usr/lib -L${cf}/usr/lib -lFoundation -lCoreFoundation -lobjc -lSystem -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib -Wl,-platform_version,macos,26.5,26.5"
  F=$out/System/Library/Frameworks/CoreSpotlight.framework
  mkdir -p $F/Versions/A/Resources/Source $F/Versions/A/Resources/Licenses $out/bin $out/include
  ${e.cc} $CF -c ${./CoreSpotlightAttributes.m} -o Attributes.o
  ${e.cc} -dynamiclib Attributes.o $LF -Wl,-compatibility_version,1 -Wl,-current_version,2418.4.13 \
    -Wl,-install_name,/System/Library/Frameworks/CoreSpotlight.framework/Versions/A/CoreSpotlight \
    -o $F/Versions/A/CoreSpotlight
  ln -s A $F/Versions/Current
  ln -s Versions/Current/CoreSpotlight $F/CoreSpotlight
  ${e.cc} $CF -fno-objc-arc ${./corespotlight-attributes-probe.m} $LF -F$out/System/Library/Frameworks \
    -framework CoreSpotlight -Wno-nonnull -o $out/bin/corespotlight-attributes-probe
  cp ${./CoreSpotlightAttributes.h} $out/include/CoreSpotlightAttributes.h
  cp ${./CoreSpotlightAttributes.h} ${./CoreSpotlightAttributes.m} ${./corespotlight-attributes-probe.m} $F/Versions/A/Resources/Source/
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
