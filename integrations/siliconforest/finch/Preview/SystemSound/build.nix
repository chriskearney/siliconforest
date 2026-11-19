# SPDX-License-Identifier: MIT
let
  e = import ../../environment.nix;
  cross = import ../../Network/toolchain.nix;
in e.pkgs.runCommand "siliconforest-preview-system-sound-arm64" {} ''
  sdk=${cross}/sdk
  export DARWIN_SDK_ROOT="$sdk"
  fw="$out/System/Library/Frameworks/AudioToolbox.framework"
  mkdir -p "$fw/Versions/A" "$out/bin"
  common=(
    -O2 -fblocks --ld-path=${e.ld} -nostdlib -isysroot "$sdk" -DXNU_PLATFORM_MacOSX=1
    -L${e.libsystem}/usr/lib -L${e.p.coreFoundation-arm64}/usr/lib -lCoreFoundation -lSystem
    "-Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib"
    -Wl,-platform_version,macos,26.5,26.5
  )
  install_name=/System/Library/Frameworks/AudioToolbox.framework/Versions/A/AudioToolbox
  build_image() {
    ${e.cc} "''${common[@]}" -dynamiclib ${./SystemSound.c} \
      -Wl,-not_for_dyld_shared_cache -Wl,-reexport_library,${./under.tbd} \
      -Wl,-compatibility_version,1 -Wl,-current_version,1000 -Wl,-install_name,"$1" -o "$2"
  }
  build_image "$install_name.sf-preview" "$fw/Versions/A/AudioToolbox"
  ln -s A "$fw/Versions/Current"
  ln -s Versions/Current/AudioToolbox "$fw/AudioToolbox"
  build_image "$install_name" AudioToolbox-link-only
  ${e.cc} ${./probe.c} "$PWD/AudioToolbox-link-only" "''${common[@]}" \
    -Wl,-dylib_file,@loader_path/AudioToolbox.sf-under:${./under.tbd} \
    -o "$out/bin/system-sound-probe"
''
