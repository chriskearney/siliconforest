# SPDX-License-Identifier: MIT
# The disk root's own system tools (./system): sf-clock (the time from the hardware clock at
# boot) and sf-halt (the clean stop: processes, sync, root downgraded, write fence sealed,
# controller stopped, restart or power-off). arm64 Mach-O against libSystem only; toolchain
# and link shape as ./build-sfnvme-test.nix.
let
  pd = (import ../rebase/pd.nix).pd;
  pkgs = pd.buildPkgs;
  p = pd.packages.${pd.buildSystem};
  libSystem = import ../m1-userspace-diagnostics/build-libsystem-spawnattr.nix;
in pkgs.stdenv.mkDerivation {
  name = "siliconforest-system-tools-arm64";
  dontUnpack = true;
  buildPhase = ''
    export DARWIN_SDK_ROOT=${p.apple-sdk}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    build() {
      ${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-clang \
        -std=c11 -Wall -Wextra -Werror -O1 \
        -isystem "$DARWIN_SDK_ROOT/usr/include" \
        "$1" \
        --ld-path=${p.native-ld}/bin/ld -nostdlib \
        -L${libSystem}/usr/lib -L${libSystem}/usr/lib/system \
        -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libSystem}/usr/lib/system/libdyld.dylib \
        -Wl,-platform_version,macos,26.5,26.5 -Wl,-fixup_chains \
        -lSystem -o "$2"
    }
    build ${./system/sf-clock.c} sf-clock
    build ${./system/sf-halt.c} sf-halt
  '';
  installPhase = ''
    mkdir -p "$out/sbin" "$out/usr/sbin"
    cp sf-halt "$out/sbin/"
    cp sf-clock "$out/usr/sbin/"
  '';
  dontFixup = true;
  dontStrip = true;
}
