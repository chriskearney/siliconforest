# SPDX-License-Identifier: MIT
# sf-rename-commit (userland/sf-rename-commit.c) for the SiliconForest M1 (arm64 Mach-O, libSystem only): the one
# process that renames the core files into place for tools/sf_rename_switch.sh and sf_rename_restore.sh. It goes
# into the staged directory beside the scripts, not onto the system. The toolchain and link shape of
# ../m1-bwfm/tools/build-pd-wifipm.nix.
let
  pd = (import ../rebase/pd.nix).pd;
  pkgs = pd.buildPkgs;
  p = pd.packages.${pd.buildSystem};
  libSystem = import ../m1-userspace-diagnostics/build-libsystem-spawnattr.nix;
in pkgs.stdenv.mkDerivation {
  name = "darwin-lab-sf-rename-commit-arm64";
  dontUnpack = true;
  buildPhase = ''
    export DARWIN_SDK_ROOT=${p.apple-sdk}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    ${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-clang \
      -std=c11 -Wall -Wextra -O1 \
      -isystem "$DARWIN_SDK_ROOT/usr/include" \
      ${./userland/sf-rename-commit.c} \
      --ld-path=${p.native-ld}/bin/ld -nostdlib \
      -L${libSystem}/usr/lib -L${libSystem}/usr/lib/system \
      -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libSystem}/usr/lib/system/libdyld.dylib \
      -Wl,-platform_version,macos,26.5,26.5 -Wl,-fixup_chains \
      -lSystem -o sf-rename-commit
  '';
  installPhase = ''
    mkdir -p "$out/bin"
    cp sf-rename-commit "$out/bin/"
  '';
  dontFixup = true;
  dontStrip = true;
}
