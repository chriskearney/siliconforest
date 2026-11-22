# sf-netd and sf-dhcp for the SiliconForest M1 guest (arm64 Mach-O, libSystem only), laid out as they
# install into the root: same toolchain and link shape as ../dhcp/build-pd-dhcp.nix.
let
  pd = (import ../../rebase/pd.nix).pd;
  pkgs = pd.buildPkgs;
  p = pd.packages.${pd.buildSystem};
  libSystem = import ../../m1-userspace-diagnostics/build-libsystem-spawnattr.nix;
in pkgs.stdenv.mkDerivation {
  name = "darwin-lab-pd-netd-arm64";
  dontUnpack = true;
  buildPhase = ''
    export DARWIN_SDK_ROOT=${p.apple-sdk}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    build() {
      ${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-clang \
        -std=c11 -Wall -Wextra -O1 \
        -isystem "$DARWIN_SDK_ROOT/usr/include" \
        "$1" \
        --ld-path=${p.native-ld}/bin/ld -nostdlib \
        -L${libSystem}/usr/lib -L${libSystem}/usr/lib/system \
        -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libSystem}/usr/lib/system/libdyld.dylib \
        -Wl,-platform_version,macos,26.5,26.5 -Wl,-fixup_chains \
        -lSystem -o "$2"
    }
    build ${./sf-netd.c} sf-netd
    build ${../dhcp/sf-dhcp.c} sf-dhcp
  '';
  installPhase = ''
    mkdir -p "$out/usr/sbin" "$out/usr/bin" "$out/System/Library/LaunchDaemons"
    cp sf-netd "$out/usr/sbin/"
    cp sf-dhcp "$out/usr/bin/"
    install -m 0755 ${../dhcp/sf-net-up} "$out/usr/bin/sf-net-up"
    install -m 0644 ${./org.siliconforest.sf-netd.plist} "$out/System/Library/LaunchDaemons/org.siliconforest.sf-netd.plist"
  '';
  dontFixup = true;
  dontStrip = true;
}
