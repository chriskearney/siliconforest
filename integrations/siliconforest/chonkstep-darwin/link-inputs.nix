# SPDX-License-Identifier: MIT
# The link inputs of the Rust desktop binaries (compositor, terminal) for the SiliconForest source
# ../rebase/pd.nix selects, as one JSON file: what darwin-linker.py carries as literal store
# paths for the pinned revision. Used by darwin-linker-inputs.py.
#
#   nix-build --extra-experimental-features 'nix-command flakes' --no-out-link link-inputs.nix
#   -> a file: {"toolchain": ..., "ld": ..., "sdk": ..., "system": ..., "sfgop": ..., "xkb": ..., "iconv": ...}
#
# At the tip the binaries link against the lab's default libSystem (../libsystem-default, what
# the RAM root and the QEMU images carry); at the pin against upstream's unpatched one, as
# darwin-linker.py does, so that SF_PD=pin names exactly the paths written there.
let
  source = import ../rebase/pd.nix;
  pd = source.pd;
  pkgs = source.pkgs;
  p = pd.packages.${pd.buildSystem};
  xkb = p.xkbcommon-arm64.override { withX11 = false; libxcb = null; libXau = null; libXdmcp = null; };
  system = source.pick { pin = p.libsystem-arm64; tip = import ../libsystem-default/build-libsystem.nix; };
in pkgs.writeText "siliconforest-chonkstep-link-inputs.json" (builtins.toJSON {
  source = source.which;
  rev = source.rev;
  toolchain = "${p.arm64-cross-toolchain}";
  ld = "${p.native-ld}/bin/ld";
  sdk = "${p.apple-sdk}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
  system = "${system}/usr/lib";
  sfgop = "${import ./build-sfgop.nix}/lib";
  xkb = "${xkb}/lib";
  iconv = "${p.libiconv-arm64}/usr/lib";
})
