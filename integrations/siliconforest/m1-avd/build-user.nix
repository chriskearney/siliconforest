# SPDX-License-Identifier: MIT
# libsfavd (static, with its headers) and sfavd-replay for the SiliconForest M1 guest (arm64
# Mach-O, libSystem only): same toolchain and link shape as ../m1-sound/build-sfplay.nix.
#   nix-build --extra-experimental-features nix-command --extra-experimental-features flakes build-user.nix
let
  pd = (import ../rebase/pd.nix).pd;
  pkgs = pd.buildPkgs;
  p = pd.packages.${pd.buildSystem};
  libSystem = import ../m1-userspace-diagnostics/build-libsystem-spawnattr.nix;
in pkgs.stdenv.mkDerivation {
  name = "darwin-lab-sfavd-user-arm64";
  dontUnpack = true;
  buildPhase = ''
    export DARWIN_SDK_ROOT=${p.apple-sdk}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    CC="${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-clang -std=c11 -Wall -Wextra -O2
      -isystem $DARWIN_SDK_ROOT/usr/include -I${./include} -I${./user}"
    $CC -c ${./user/sfavd.c} -o sfavd.o
    ${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-ar rcs libsfavd.a sfavd.o
    $CC ${./user/sfavd-replay.c} sfavd.o \
      --ld-path=${p.native-ld}/bin/ld -nostdlib \
      -L${libSystem}/usr/lib -L${libSystem}/usr/lib/system \
      -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libSystem}/usr/lib/system/libdyld.dylib \
      -Wl,-platform_version,macos,26.5,26.5 -Wl,-fixup_chains \
      -lSystem -o sfavd-replay
  '';
  installPhase = ''
    mkdir -p "$out/usr/bin" "$out/lib" "$out/include"
    cp sfavd-replay "$out/usr/bin/"
    cp libsfavd.a "$out/lib/"
    cp -R ${./include}/sfavd "$out/include/"
  '';
  dontFixup = true;
  dontStrip = true;
}
