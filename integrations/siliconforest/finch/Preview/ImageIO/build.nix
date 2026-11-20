# SPDX-License-Identifier: MIT
let
  e = import ../../environment.nix;
  cocoa = import ../../../cocoa/arm64.nix;
  graphics = (import ../../../cocoa/patched.nix).coregraphics;
  cross = import ../../Network/toolchain.nix;
in e.pkgs.runCommand "siliconforest-preview-imageio-arm64" {} ''
  sdk=${cross}/sdk
  export DARWIN_SDK_ROOT="$sdk"
  source=${e.finch}/userland/ImageIO/ImageIOConstants.c
  echo "ed64b000fca095d02ec49aef49196652e8f3a6068d36779ac85debec51e4d3b8  $source" | sha256sum -c
  cat > Keys.c <<'C'
  #include <CoreFoundation/CoreFoundation.h>
  #define K(name, value) const CFStringRef name = CFSTR(value);
  C
  while IFS= read -r key; do
    grep "^K($key, " "$source" >> Keys.c
  done < ${./keys.txt}

  framework="$out/System/Library/Frameworks/ImageIO.framework"
  mkdir -p "$framework/Versions/A" "$out/bin" "$out/share/licenses/Finch"
  compile=(
    -O2 -fblocks -fno-objc-arc -isysroot "$sdk" -DXNU_PLATFORM_MacOSX=1
    -F${graphics}/System/Library/Frameworks
  )
  link=(
    --ld-path=${e.ld} -nostdlib -isysroot "$sdk" -L${e.libsystem}/usr/lib
    -L${e.p.coreFoundation-arm64}/usr/lib -L${e.p.foundation-arm64}/usr/lib -L${e.p.libobjc-arm64}/usr/lib
    -F${cocoa.appDeps.onyx2d}/System/Library/Frameworks
    -framework CoreGraphics -framework Onyx2D -lFoundation -lCoreFoundation -lobjc -lSystem
    "-Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib"
    -Wl,-platform_version,macos,26.5,26.5
  )
  printf '%s\n' 'static const int empty = 0;' > Under.c
  ${e.cc} "''${compile[@]}" "''${link[@]}" -dynamiclib Under.c \
    -Wl,-install_name,@loader_path/ImageIO.sf-under -o ImageIO.sf-under
  imageio=/System/Library/Frameworks/ImageIO.framework/Versions/A/ImageIO
  build_image() {
    ${e.cc} "''${compile[@]}" "''${link[@]}" -dynamiclib Keys.c ${./Sources.m} ${./ImageScaling.c} ${./Destinations.m} ${./Metadata.c} ${./OFD.m} \
      -Wl,-not_for_dyld_shared_cache -Wl,-reexport_library,"$PWD/ImageIO.sf-under" \
      -Wl,-compatibility_version,1 -Wl,-current_version,1 -Wl,-install_name,"$1" -o "$2"
  }
  build_image "$imageio.sf-preview" "$framework/Versions/A/ImageIO"
  ln -s A "$framework/Versions/Current"
  ln -s Versions/Current/ImageIO "$framework/ImageIO"
  # Bind the probe to the public framework request, just as a normal client does.
  build_image "$imageio" ImageIO-link-only
  ${e.cc} "''${compile[@]}" ${./probe.c} "$PWD/ImageIO-link-only" "''${link[@]}" \
    -Wl,-dylib_file,@loader_path/ImageIO.sf-under:"$PWD/ImageIO.sf-under" \
    -o "$out/bin/imageio-probe"
  cp ${e.finch}/LICENSE-MIT ${e.finch}/LICENSE-APACHE "$out/share/licenses/Finch/"
''
