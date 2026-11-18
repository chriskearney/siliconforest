# dcp-flip-test for the SiliconForest M1 guest (arm64 Mach-O) with the libdrm it runs on, laid
# out like ../m1-mesa-asahi/agx-offscreen-test.nix:
#   usr/local/bin/dcp-flip-test
#   usr/local/lib/mesa-asahi/libdrm.2.dylib
let
  c = import ../m1-mesa-asahi/common.nix;
  inherit (c) pkgs p triple sdkRoot;
  libdrm = p.libdrm-dri-arm64;
  libSystem = p.libsystem-arm64;
  tc = p.arm64-cross-toolchain;
  prefix = "/usr/local/lib/mesa-asahi";
in pkgs.stdenv.mkDerivation {
  name = "darwin-lab-dcp-flip-test-arm64-darwin";
  dontUnpack = true;
  buildPhase = ''
    # the GPU driver's uAPI (for --prime-from), from the pin; its "drm.h" is libdrm's
    mkdir uapi && cp ${(import ../../../release/sources.nix).linux-aurora.outPath}/include/uapi/drm/asahi_drm.h uapi/asahi_drm.h
    ${tc}/bin/${triple}-clang -std=gnu11 -O2 -Wall -Wextra \
      -isysroot ${sdkRoot} -mmacosx-version-min=26.5 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 \
      -fno-stack-protector -I${libSystem}/usr/include \
      -I${libdrm}/include -I${libdrm}/include/libdrm -Iuapi \
      ${./test/dcp-flip-test.c} \
      -fuse-ld=${p.native-ld}/bin/ld -nostdlib -L${libSystem}/usr/lib -L${libdrm}/lib \
      -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libSystem}/usr/lib/system/libdyld.dylib \
      -Wl,-platform_version,macos,26.5,26.5 -Wl,-fixup_chains \
      -ldrm -lSystem -o dcp-flip-test
    # sf-backlight (tool/sf-backlight.c): the panel backlight through hw.sf_backlight.*
    ${tc}/bin/${triple}-clang -std=gnu11 -O2 -Wall -Wextra \
      -isysroot ${sdkRoot} -mmacosx-version-min=26.5 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 \
      -fno-stack-protector -I${libSystem}/usr/include \
      ${./tool/sf-backlight.c} \
      -fuse-ld=${p.native-ld}/bin/ld -nostdlib -L${libSystem}/usr/lib \
      -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libSystem}/usr/lib/system/libdyld.dylib \
      -Wl,-platform_version,macos,26.5,26.5 -Wl,-fixup_chains \
      -lSystem -o sf-backlight
  '';
  installPhase = ''
    INT=${tc}/bin/${triple}-install_name_tool
    OTOOL=${tc}/bin/${triple}-otool
    lib=$out${prefix}
    mkdir -p $out/usr/local/bin $lib
    cp dcp-flip-test sf-backlight $out/usr/local/bin/
    cp ${libdrm}/lib/libdrm.2.dylib $lib/
    chmod u+w $lib/* $out/usr/local/bin/*
    "$INT" -id "${prefix}/libdrm.2.dylib" $lib/libdrm.2.dylib
    for old in $("$OTOOL" -L $out/usr/local/bin/dcp-flip-test | awk 'NR>1 {print $1}' | grep '/libdrm.2.dylib$' || true); do
      "$INT" -change "$old" "${prefix}/libdrm.2.dylib" $out/usr/local/bin/dcp-flip-test
    done
    "$OTOOL" -L $out/usr/local/bin/dcp-flip-test
  '';
  dontFixup = true;
}
