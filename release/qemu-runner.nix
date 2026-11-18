# SPDX-License-Identifier: MIT
# Copyright (c) 2026 SiliconForest contributors
{ pkgs }:
let
  firmware = pkgs.pkgsCross.aarch64-multiplatform.OVMF.fd;
in pkgs.writeShellApplication {
  name = "siliconforest-qemu";
  runtimeInputs = [ pkgs.qemu pkgs.python3 ];
  text = ''
    export QD_AAVMF=${firmware}/FV
    exec python3 ${../integrations/siliconforest/qemu-dev/qd_run.py} "$@"
  '';
}
