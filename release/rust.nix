# SPDX-License-Identifier: MIT
# Copyright (c) 2026 SiliconForest contributors
# Host Rust and the exact matching standard libraries for both cross targets.
{ pkgs }:
let
  sources = import ./sources.nix;
  components = [
    "rustc-1.98.1-x86_64-unknown-linux-gnu"
    "cargo-1.98.1-x86_64-unknown-linux-gnu"
    "rust-std-1.98.1-x86_64-unknown-linux-gnu"
    "rust-std-1.98.1-aarch64-apple-darwin"
    "rust-std-1.98.1-aarch64-unknown-none-softfloat"
  ];
in pkgs.stdenv.mkDerivation {
  pname = "siliconforest-rust";
  version = "1.98.1";
  dontUnpack = true;
  nativeBuildInputs = [ pkgs.autoPatchelfHook pkgs.xz ];
  buildInputs = [ pkgs.stdenv.cc.cc.lib pkgs.zlib ];
  installPhase = ''
    runHook preInstall
    ${pkgs.lib.concatMapStrings (name: ''
      mkdir component
      tar -xJf ${sources.${name}} -C component --strip-components=1
      (cd component; bash ./install.sh --prefix="$out" --disable-ldconfig)
      rm -rf component
    '') components}
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    "$out/bin/rustc" --version
    "$out/bin/cargo" --version
    test -d "$out/lib/rustlib/aarch64-apple-darwin/lib"
    test -d "$out/lib/rustlib/aarch64-unknown-none-softfloat/lib"
  '';
}
