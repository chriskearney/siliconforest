# SPDX-License-Identifier: MIT
# Finch's exact backend version. Keep private ML-KEM/ML-DSA headers with it.
let
  e = import ../environment.nix;
  src = (import ../../../../release/fetch.nix { pkgs = e.pkgs; }) "openssl-finch";
in (e.p.openssl-arm64.override { withThreads = true; }).overrideAttrs (old: {
  version = "3.5.9";
  inherit src;
  # Finch calls OpenSSL's armv8 AES helpers directly, so keep that backend.
  configurePhase = e.pkgs.lib.replaceStrings [ "no-asm " ] [ "" ] old.configurePhase;
  postInstall = (old.postInstall or "") + ''
    mkdir -p $out/internal
    cp -a include/crypto crypto/ml_dsa $out/internal/
    cp -a include/internal $out/internal/
  '';
})
