# SPDX-License-Identifier: MIT
# Private cross-build candidate only; no installation or target execution.
let
  e = import ../environment.nix;
  foundation = e.p.foundation-arm64;
  cf = e.p.coreFoundation-arm64;
  objc = e.p.libobjc-arm64;
  cg = e.p.coregraphics-arm64;
  onyx = e.p.onyx2d-arm64;
in e.pkgs.runCommand "siliconforest-preview-visionkit-unsupported-arm64" {} ''
  export DARWIN_SDK_ROOT=${e.sdk}
  cp ${./VisionKitCore.h} VisionKitCore.h
  CF="-O2 -Wall -Wextra -Werror -Wno-unused-parameter -fblocks -fobjc-exceptions -fno-objc-arc -isysroot ${e.sdk} -I$PWD -isystem ${e.libsystem}/usr/include -isystem ${objc}/usr/include -isystem ${foundation}/usr/include -isystem ${cf}/include -isystem ${cg}/usr/include -isystem ${onyx}/usr/include"
  LF="--ld-path=${e.ld} -nostdlib -isysroot ${e.sdk} -L${e.libsystem}/usr/lib -L${objc}/usr/lib -L${foundation}/usr/lib -L${cf}/usr/lib -L${cg}/usr/lib -lCoreGraphics -lFoundation -lCoreFoundation -lobjc -lSystem -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib -Wl,-platform_version,macos,26.5,26.5"
  F=$out/System/Library/PrivateFrameworks/VisionKitCore.framework
  mkdir -p $F/Versions/A/Resources/Source $F/Versions/A/Resources/Licenses $out/bin
  ${e.cc} $CF -c ${./VisionKitCore.m} -o VisionKitCore.o
  ${e.cc} -dynamiclib VisionKitCore.o $LF -Wl,-compatibility_version,1 -Wl,-current_version,1 \
    -Wl,-install_name,/System/Library/PrivateFrameworks/VisionKitCore.framework/Versions/A/VisionKitCore \
    -o $F/Versions/A/VisionKitCore
  ln -s A $F/Versions/Current
  ln -s Versions/Current/VisionKitCore $F/VisionKitCore
  ${e.cc} $CF ${./visionkit-probe.m} $LF -F$out/System/Library/PrivateFrameworks \
    -framework VisionKitCore -o $out/bin/visionkit-probe
  cp ${./VisionKitCore.h} ${./VisionKitCore.m} ${./visionkit-probe.m} $F/Versions/A/Resources/Source/
  cp ${./VISIONKIT.md} $F/Versions/A/Resources/
  cp ${../../../../LICENSE} $F/Versions/A/Resources/Licenses/LICENSE-MIT
  cat >$F/Versions/A/Resources/Info.plist <<'PLIST'
  <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>VisionKitCore</string>
  <key>CFBundleIdentifier</key><string>org.siliconforest.VisionKitCore</string>
  <key>CFBundleName</key><string>VisionKitCore</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleVersion</key><string>1</string>
  </dict></plist>
  PLIST
  ln -s Versions/Current/Resources $F/Resources
''
