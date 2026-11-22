# sf-wifipm for the SiliconForest M1 (arm64 Mach-O, libSystem only): the same toolchain and link
# shape as ../netd/build-pd-netd.nix.
let
  pd = (import ../../rebase/pd.nix).pd;
  pkgs = pd.buildPkgs;
  p = pd.packages.${pd.buildSystem};
  libSystem = import ../../m1-userspace-diagnostics/build-libsystem-spawnattr.nix;
in pkgs.stdenv.mkDerivation {
  name = "darwin-lab-pd-wifipm-arm64";
  dontUnpack = true;
  buildPhase = ''
    export DARWIN_SDK_ROOT=${p.apple-sdk}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    ${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-clang \
      -std=c11 -Wall -Wextra -O1 \
      -isystem "$DARWIN_SDK_ROOT/usr/include" \
      ${./sf-wifipm.c} \
      --ld-path=${p.native-ld}/bin/ld -nostdlib \
      -L${libSystem}/usr/lib -L${libSystem}/usr/lib/system \
      -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libSystem}/usr/lib/system/libdyld.dylib \
      -Wl,-platform_version,macos,26.5,26.5 -Wl,-fixup_chains \
      -lSystem -o sf-wifipm
  '';
  installPhase = ''
    mkdir -p "$out/usr/sbin"
    cp sf-wifipm "$out/usr/sbin/"
  '';
  dontFixup = true;
  dontStrip = true;
}
