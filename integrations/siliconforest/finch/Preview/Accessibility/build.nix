# SPDX-License-Identifier: MIT
let
  e = import ../../environment.nix;
  cocoa = import ../../../cocoa/arm64.nix;
  cross = import ../../Network/toolchain.nix;
in e.pkgs.runCommand "siliconforest-preview-accessibility-arm64" {} ''
  sdk=${cross}/sdk
  export DARWIN_SDK_ROOT="$sdk"
  source=${e.finch}/userland/Accessibility/Accessibility.m
  echo "db88f4a009f6bf5022b142db2fee98a7cfc6549b1d506f838e45e60910b2115e  $source" | sha256sum -c
  printf '%s\n' '// SPDX-License-Identifier: MIT OR Apache-2.0' '#import <Accessibility/Accessibility.h>' > ChartObjects.m
  sed -n '/^#pragma mark - Charts$/,/^@implementation AXLiveAudioGraph$/{ /^@implementation AXLiveAudioGraph$/d; p; }' "$source" >> ChartObjects.m
  sed -n '/^#pragma mark - Custom content$/,/^#pragma mark - Math expressions$/{ /^#pragma mark - Math expressions$/d; p; }' "$source" >> ChartObjects.m
  framework="$out/System/Library/Frameworks/Accessibility.framework"
  mkdir -p "$framework/Versions/A/Headers" "$framework/Versions/A/Modules" "$out/share/licenses/Finch"
  cp ${./include/Accessibility/Accessibility.h} "$framework/Versions/A/Headers/Accessibility.h"
  cat > "$framework/Versions/A/Modules/module.modulemap" <<'MAP'
  framework module Accessibility {
    umbrella header "Accessibility.h"
    export *
  }
  MAP
  ln -s A "$framework/Versions/Current"
  ln -s Versions/Current/Accessibility "$framework/Accessibility"
  ln -s Versions/Current/Headers "$framework/Headers"
  ln -s Versions/Current/Modules "$framework/Modules"
  common=(
    -O2 -fblocks -fno-objc-arc --ld-path=${e.ld} -nostdlib -isysroot "$sdk"
    -Wno-nullability-completeness -DXNU_PLATFORM_MacOSX=1 -I${./include}
    -F${cocoa.appDeps.coregraphics}/System/Library/Frameworks
    -L${e.libsystem}/usr/lib -L${e.p.libobjc-arm64}/usr/lib -L${e.p.foundation-arm64}/usr/lib
    -L${e.p.coreFoundation-arm64}/usr/lib -lFoundation -lCoreFoundation -lobjc -lSystem
    -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib
    -Wl,-platform_version,macos,26.5,26.5
  )
  ${e.cc} -dynamiclib "''${common[@]}" \
    -Wl,-install_name,/System/Library/Frameworks/Accessibility.framework/Versions/A/Accessibility \
    -Wl,-compatibility_version,1 -Wl,-current_version,1 \
    ChartObjects.m ${./ChartArchive.m} -o "$framework/Versions/A/Accessibility"
  mkdir -p "$out/bin"
  ${e.cc} "''${common[@]}" -F"$out/System/Library/Frameworks" -framework Accessibility \
    ${./probe.m} -o "$out/bin/accessibility-probe"
  cp ${e.finch}/LICENSE-MIT ${e.finch}/LICENSE-APACHE "$out/share/licenses/Finch/"
''
