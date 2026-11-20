# SPDX-License-Identifier: MIT
let
  e = import ../environment.nix;
  inherit (e.p) foundation-arm64 coreFoundation-arm64 libobjc-arm64;
in e.pkgs.runCommand "siliconforest-preview-synapse-arm64" { } ''
  export DARWIN_SDK_ROOT=${e.sdk}
  cp ${./Synapse.h} Synapse.h
  compile="-O2 -Wall -Wextra -Werror -fblocks -fobjc-arc -isysroot ${e.sdk} -I$PWD -isystem ${e.libsystem}/usr/include -isystem ${foundation-arm64}/usr/include -isystem ${coreFoundation-arm64}/include -isystem ${libobjc-arm64}/usr/include"
  link="--ld-path=${e.ld} -nostdlib -isysroot ${e.sdk} -L${e.libsystem}/usr/lib -L${foundation-arm64}/usr/lib -L${coreFoundation-arm64}/usr/lib -L${libobjc-arm64}/usr/lib -lFoundation -lCoreFoundation -lobjc -lSystem -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib -Wl,-platform_version,macos,26.5,26.5"
  framework="$out/System/Library/PrivateFrameworks/Synapse.framework"
  version="$framework/Versions/A"
  mkdir -p "$version/Resources/Licenses" "$version/Headers" "$out/bin"
  ${e.cc} $compile -c ${./Synapse.m} -o Synapse.o
  ${e.cc} -dynamiclib Synapse.o $link -current_version 1 -compatibility_version 1 \
    -install_name /System/Library/PrivateFrameworks/Synapse.framework/Versions/A/Synapse -o "$version/Synapse"
  ${e.cc} $compile ${./probe.m} $link "$version/Synapse" -o "$out/bin/synapse-probe"
  cp Synapse.h "$version/Headers/"
  cp ${../../../../LICENSE} "$version/Resources/Licenses/LICENSE-MIT"
  cat > "$version/Resources/Info.plist" <<'PLIST'
  <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Synapse</string>
  <key>CFBundleIdentifier</key><string>org.siliconforest.Synapse</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleVersion</key><string>1</string>
  </dict></plist>
  PLIST
  ln -s A "$framework/Versions/Current"
  ln -s Versions/Current/Synapse "$framework/Synapse"
  ln -s Versions/Current/Headers "$framework/Headers"
  ln -s Versions/Current/Resources "$framework/Resources"
''
