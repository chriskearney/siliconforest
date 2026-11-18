# SPDX-License-Identifier: MIT
# Copyright (c) 2026 SiliconForest contributors
# An early desktop check, separate from IMAGE's complete release root.
{ base ? import ./base.nix }:
let
  inherit (base) pkgs;
  p = base.pd.packages.x86_64-linux;
  sf = ../integrations/siliconforest;
  desktop = import ./desktop.nix { inherit base; };
  libsystem = import (sf + "/libsystem-default/build-libsystem.nix");
  qemuBase = import (sf + "/qemu-dev/build-image.nix") { };
  tokens = {
    # TCG startup can consume more than 45 seconds on a busy build host.
    SECONDS = "180"; AUTOPILOT = "1"; STATS = "1"; SOUND = "0";
    RENDERER = "cpu"; TERMINALS = "1"; FETCH = "0"; PERSIST = "0";
    SCALE = "1"; THEME = "sf-canopy"; ONLY = "settle,type"; ENV = "";
  };
  session = pkgs.writeText "qemu-desktop-session" (builtins.replaceStrings
    (map (name: "@${name}@") (builtins.attrNames tokens))
    (builtins.attrValues tokens)
    (builtins.readFile (sf + "/qemu-dev/guest/qemu-desktop-session.in")));
  file = source: executable: { inherit source executable; };
  config = pkgs.writeText "qemu-smoke-inputs.json" (builtins.toJSON {
    base = qemuBase;
    overlays = [ desktop.desktop desktop.terminal libsystem p.xkeyboardConfig-arm64 ];
    files = {
      "/usr/bin/qemu-desktop-session" = file session true;
      "/System/Library/LaunchDaemons/org.siliconforest.qemu-desktop.plist" =
        file (sf + "/qemu-dev/guest/org.siliconforest.qemu-desktop.plist") false;
      "/usr/share/darwin-desktop/DejaVuSans.ttf" =
        file "${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf" false;
      "/usr/share/darwin-desktop/DejaVuSans-Bold.ttf" =
        file "${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans-Bold.ttf" false;
      "/usr/share/terminfo/x/xterm-256color" =
        file (sf + "/chonkstep-darwin/terminfo/xterm-256color") false;
      "/usr/share/terminfo/78/xterm-256color" =
        file (sf + "/chonkstep-darwin/terminfo/xterm-256color") false;
    };
  });
in pkgs.runCommand "siliconforest-qemu-smoke-image" {
  nativeBuildInputs = [ pkgs.python3 pkgs.e2fsprogs pkgs.mtools ];
  E2FSPROGS_FAKE_TIME = "1";
} ''
  python3 ${./qemu-smoke.py} ${config} "$out"
''
