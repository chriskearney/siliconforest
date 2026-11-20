# SPDX-License-Identifier: MIT
let
  e = import ../../environment.nix;
  cross = import ../../Network/toolchain.nix;
in e.pkgs.runCommand "siliconforest-preview-core-foundation-keys-arm64" {} ''
  sdk=${cross}/sdk
  export DARWIN_SDK_ROOT="$sdk"
  source=${e.finch}/userland/CoreFoundation
  echo "5d9165ff97ff9831d68a080e903f590fac9658c751a0c991d8c9111f5dc48965  $source/CFPlatform_Finch.c" | sha256sum -c
  echo "7d7df78516827404826e5656b515d66192db7c285332419834c51a7f95ca9b19  $source/NSConstants_Finch.c" | sha256sum -c
  cat > Additions.c <<'C'
  #include <CoreFoundation/CoreFoundation.h>
  #include <stdarg.h>
  #include <stdio.h>
  #include <stdlib.h>
  #define NS_CONSTANT(name, value) const CFStringRef name = CFSTR(value);
  C
  sed -n '/^CF_EXPORT void CFLogTest(/,/^}/p' "$source/CFPlatform_Finch.c" >> Additions.c
  while IFS= read -r key; do
    grep "^NS_CONSTANT($key, " "$source/NSConstants_Finch.c" >> Additions.c
  done < ${./keys.txt}
  framework="$out/System/Library/Frameworks/CoreFoundation.framework"
  mkdir -p "$framework/Versions/A" "$out/bin" "$out/share/licenses/Finch"
  common=(
    -O2 --ld-path=${e.ld} -nostdlib -isysroot "$sdk" -DXNU_PLATFORM_MacOSX=1
    -L${e.libsystem}/usr/lib -L${e.p.coreFoundation-arm64}/usr/lib -lCoreFoundation -lSystem
    "-Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib"
    -Wl,-platform_version,macos,26.5,26.5
  )
  printf '%s\n' 'static const int empty = 0;' > Under.c
  ${e.cc} "''${common[@]}" -dynamiclib Under.c \
    -Wl,-install_name,@loader_path/CoreFoundation.sf-under -o CoreFoundation.sf-under
  core=/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation
  build_image() {
    ${e.cc} "''${common[@]}" -dynamiclib Additions.c \
      -Wl,-not_for_dyld_shared_cache -Wl,-reexport_library,"$PWD/CoreFoundation.sf-under" \
      -Wl,-compatibility_version,150 -Wl,-current_version,1338 -Wl,-install_name,"$1" -o "$2"
  }
  build_image "$core.sf-preview" "$framework/Versions/A/CoreFoundation"
  ln -s A "$framework/Versions/Current"
  ln -s Versions/Current/CoreFoundation "$framework/CoreFoundation"
  build_image "$core" CoreFoundation-link-only
  ${e.cc} "''${common[@]}" ${./probe.c} \
    -Wl,-dylib_file,@loader_path/CoreFoundation.sf-under:"$PWD/CoreFoundation.sf-under" \
    "$PWD/CoreFoundation-link-only" -o "$out/bin/core-foundation-keys-probe"
  cp ${e.finch}/LICENSE-MIT ${e.finch}/LICENSE-APACHE "$out/share/licenses/Finch/"
''
