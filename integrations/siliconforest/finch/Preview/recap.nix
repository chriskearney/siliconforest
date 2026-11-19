# SPDX-License-Identifier: MIT OR Apache-2.0
# Cross-build only. This output is a private provider candidate, never an install.
let
  e = import ../environment.nix;
  foundation = e.p.foundation-arm64;
  cf = e.p.coreFoundation-arm64;
  objc = e.p.libobjc-arm64;
in e.pkgs.runCommand "siliconforest-preview-recap-unsupported-arm64" {} ''
  export DARWIN_SDK_ROOT=${e.sdk}
  cp ${./RecapPerformanceTesting.h} RecapPerformanceTesting.h
  CF="-O2 -Wall -Wextra -Werror -Wno-unused-parameter -fblocks -fobjc-exceptions -fno-objc-arc -isysroot ${e.sdk} -I$PWD -isystem ${e.libsystem}/usr/include -isystem ${objc}/usr/include -isystem ${foundation}/usr/include -isystem ${cf}/include"
  LF="--ld-path=${e.ld} -nostdlib -isysroot ${e.sdk} -L${e.libsystem}/usr/lib -L${objc}/usr/lib -L${foundation}/usr/lib -L${cf}/usr/lib -lFoundation -lCoreFoundation -lobjc -lSystem -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib -Wl,-platform_version,macos,26.5,26.5"
  F=$out/System/Library/PrivateFrameworks/RecapPerformanceTesting.framework
  mkdir -p $F/Versions/A/Resources/Source $F/Versions/A/Resources/Licenses $out/bin
  ${e.cc} $CF -c ${./RecapPerformanceTesting.m} -o Recap.o
  ${e.cc} -dynamiclib Recap.o $LF -Wl,-compatibility_version,1 -Wl,-current_version,50 \
    -Wl,-install_name,/System/Library/PrivateFrameworks/RecapPerformanceTesting.framework/Versions/A/RecapPerformanceTesting \
    -o $F/Versions/A/RecapPerformanceTesting
  ln -s A $F/Versions/Current
  ln -s Versions/Current/RecapPerformanceTesting $F/RecapPerformanceTesting
  ${e.cc} $CF ${./recap-probe.m} $LF -F$out/System/Library/PrivateFrameworks \
    -framework RecapPerformanceTesting -o $out/bin/recap-probe
  cp ${./RecapPerformanceTesting.h} ${./RecapPerformanceTesting.m} ${./recap-probe.m} $F/Versions/A/Resources/Source/
  cp ${./NOTICE} $F/Versions/A/Resources/
  cp ${e.finch}/LICENSE-MIT ${e.finch}/LICENSE-APACHE $F/Versions/A/Resources/Licenses/
  cat >$F/Versions/A/Resources/Info.plist <<'PLIST'
  <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>RecapPerformanceTesting</string>
  <key>CFBundleIdentifier</key><string>org.siliconforest.RecapPerformanceTesting</string>
  <key>CFBundleName</key><string>RecapPerformanceTesting</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleVersion</key><string>50</string>
  </dict></plist>
  PLIST
  ln -s Versions/Current/Resources $F/Resources
''
