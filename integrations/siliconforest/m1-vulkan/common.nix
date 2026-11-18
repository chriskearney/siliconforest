# SPDX-License-Identifier: MIT
# Inputs of the Vulkan port: those of ../m1-mesa-asahi/common.nix (the SiliconForest flake, its
# nixpkgs, the cross toolchain) with the Mesa source that Omacom's omarchy-pkgs `mesa-aurora`
# packages with -Dvulkan-drivers=asahi: omacom/mesa integration/aurora b7b03c5b3b8 (26.3.0-devel,
# 8 November 2026), built there with no patches.
(import ../m1-mesa-asahi/common.nix) // rec {
  mesaRev = (builtins.fromJSON (builtins.readFile ../../../sources.lock)).auxiliarySources.mesa-vulkan.revision;
  mesaVersion = "26.3.0-devel-${builtins.substring 0 11 mesaRev}";
  mesaSrc = (import ../../../release/fetch.nix { pkgs = (import ../m1-mesa-asahi/common.nix).pkgs; }) "mesa-vulkan";
}
