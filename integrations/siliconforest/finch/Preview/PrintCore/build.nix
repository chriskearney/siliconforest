# SPDX-License-Identifier: MIT
let
  e = import ../../environment.nix;
  graphics = (import ../../../cocoa/patched.nix).coregraphics;
  cross = import ../../Network/toolchain.nix;
in e.pkgs.runCommand "siliconforest-preview-printcore-arm64" {} ''
  sdk=${cross}/sdk
  export DARWIN_SDK_ROOT="$sdk"
  source=${e.pd.outPath}/src/Frameworks/HIServices/PrintCore.c
  echo "5b1b1f370651cff4d5e684866b71a9cf94babeb752201e2feb9eae049b689465  $source" | sha256sum -c
  cat "$source" ${./Additions.c} > PrintCore.c
  fw="$out/System/Library/Frameworks/ApplicationServices.framework"
  mkdir -p "$fw/Versions/A" "$out/bin"
  common=(
    -O2 --ld-path=${e.ld} -nostdlib -isysroot "$sdk" -DXNU_PLATFORM_MacOSX=1
    -F${graphics}/System/Library/Frameworks
    -L${e.libsystem}/usr/lib -L${e.p.coreFoundation-arm64}/usr/lib
    -framework CoreGraphics -lCoreFoundation -lSystem
    "-Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib"
    -Wl,-platform_version,macos,26.5,26.5
  )
  printf '%s\n' 'static const int empty = 0;' > Under.c
  ${e.cc} "''${common[@]}" -dynamiclib Under.c \
    -Wl,-install_name,@loader_path/ApplicationServices.sf-under -o ApplicationServices.sf-under
  install_name=/System/Library/Frameworks/ApplicationServices.framework/Versions/A/ApplicationServices
  build_image() {
    ${e.cc} "''${common[@]}" -dynamiclib PrintCore.c \
      -Wl,-not_for_dyld_shared_cache -Wl,-reexport_library,"$PWD/ApplicationServices.sf-under" \
      -Wl,-compatibility_version,1 -Wl,-current_version,1 -Wl,-install_name,"$1" -o "$2"
  }
  build_image "$install_name.sf-preview" "$fw/Versions/A/ApplicationServices"
  ln -s A "$fw/Versions/Current"
  ln -s Versions/Current/ApplicationServices "$fw/ApplicationServices"
  build_image "$install_name" ApplicationServices-link-only
  ${e.cc} ${./probe.c} "$PWD/ApplicationServices-link-only" "''${common[@]}" \
    -Wl,-dylib_file,@loader_path/ApplicationServices.sf-under:"$PWD/ApplicationServices.sf-under" \
    -o "$out/bin/printcore-probe"
''
