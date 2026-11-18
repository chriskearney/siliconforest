# SPDX-License-Identifier: MIT
# Copyright (c) 2026 SiliconForest contributors
{ pkgs }:
let
  firmware = pkgs.pkgsCross.aarch64-multiplatform.OVMF.fd;
  runner = pkgs.writeShellApplication {
    name = "siliconforest-qemu";
    runtimeInputs = [ pkgs.qemu pkgs.python3 ];
    text = ''
      export QD_AAVMF=${firmware}/FV
      exec python3 ${../integrations/siliconforest/qemu-dev/qd_run.py} "$@"
    '';
  };
  vnc = pkgs.writeShellApplication {
    name = "siliconforest-qemu-vnc";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec python3 ${./image/qemu/vnc-shot.py} "$@"
    '';
  };
  records = pkgs.writeShellApplication {
    name = "siliconforest-qemu-records";
    runtimeInputs = [ pkgs.qemu pkgs.python3 pkgs.e2fsprogs pkgs.util-linux pkgs.coreutils ];
    text = ''
      exec ${pkgs.runtimeShell} ${./image/qemu/extract-shots.sh} "$@"
    '';
  };
in pkgs.symlinkJoin {
  name = "siliconforest-qemu-tools";
  paths = [ runner vnc records ];
}
