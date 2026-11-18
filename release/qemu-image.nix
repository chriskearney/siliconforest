# SPDX-License-Identifier: MIT
# Copyright (c) 2026 SiliconForest contributors
# Keep the release's complete user space and adapt the session to the virt machine.
{ pkgs, disk, proof ? false }:
let
  guest = ../integrations/siliconforest/qemu-dev/guest;
  tokens = {
    SECONDS = if proof then "900" else "3153600000";
    AUTOPILOT = if proof then "1" else "0";
    STATS = if proof then "1" else "0";
    SOUND = "0"; RENDERER = "cpu"; TERMINALS = "1"; FETCH = "0";
    PERSIST = "0"; SCALE = "1"; THEME = "sf-canopy"; ONLY = "settle";
    ENV = if proof then "( sleep 240; sh /usr/libexec/sf-image-check ) &" else "";
  };
  session = pkgs.writeText "qemu-release-session" (builtins.replaceStrings
    (map (name: "@${name}@") (builtins.attrNames tokens))
    (builtins.attrValues tokens) (builtins.readFile (guest + "/qemu-desktop-session.in")));
  file = source: executable: { inherit source executable; };
  config = pkgs.writeText "qemu-release-inputs.json" (builtins.toJSON {
    base = disk;
    name = "siliconforest-qemu.img";
    scope = "Complete release root with a QEMU CPU-rendered session; M1 release root unchanged.";
    overlays = [ ];
    remove = [ "/System/Library/LaunchDaemons/org.siliconforest.desktop.plist" ];
    bootArgs = null; # IMAGE's disk already carries the emulated-guest boot arguments.
    files = {
      "/usr/bin/qemu-desktop-session" = file session true;
      "/System/Library/LaunchDaemons/org.siliconforest.qemu-desktop.plist" =
        file (guest + "/org.siliconforest.qemu-desktop.plist") false;
    } // pkgs.lib.optionalAttrs proof {
      "/usr/libexec/sf-image-check" = file ./image/qemu/sf-image-check true;
    };
  });
in pkgs.runCommand "siliconforest-qemu-${if proof then "proof" else "desktop"}-image" {
  nativeBuildInputs = [ pkgs.python3 pkgs.e2fsprogs pkgs.mtools ];
  E2FSPROGS_FAKE_TIME = "1";
} ''
  python3 ${./qemu-smoke.py} ${config} "$out"
''
