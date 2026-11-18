# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
{ pkgs, version, rootfs, bootfiles }:
let
  root = pkgs.runCommand "siliconforest-installer-root-${version}" {
    nativeBuildInputs = with pkgs; [ coreutils e2fsprogs python3 ];
  } ''
    mkdir -p "$out"
    python3 -I -B ${./.}/prepare-root.py ${rootfs} "$out" > "$out/firmware-offset"
  '';
in
pkgs.runCommand "siliconforest-installer-release-${version}" {
  nativeBuildInputs = with pkgs; [ coreutils gnutar librsvg python3 xz ];
} ''
  mkdir -p "$out"
  bash ${./.}/pack-assets.sh ${version} ${root} ${bootfiles} \
    ${../../integrations/siliconforest/branding/siliconforest-icon.svg} "$out"
''
