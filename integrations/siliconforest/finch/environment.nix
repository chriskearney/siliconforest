# SPDX-License-Identifier: MIT
let
  base = import ../rebase/pd.nix;
  p = base.pd.packages.${base.pd.buildSystem};
in {
  inherit p;
  inherit (base) pkgs pd;
  finch = import ./source.nix;
  libsystem = p.libsystem-arm64;
  sdk = "${p.apple-sdk}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
  cc = "${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-clang";
  ld = "${p.native-ld}/bin/ld";
}
