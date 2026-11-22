# SPDX-License-Identifier: MIT
# The SiliconForest flake for the *full* arm64 userland: upstream's image-arm64-virt-wayland and
# the packages around Security (the Homebrew overlay's frameworks).
#
#   SF_PD=pin   the pin itself (../rebase/pd.nix), unchanged
#   tip         the tip with the tree patches in ./tree-patches applied to a copy of its source:
#                 security-content-protection-header.patch
#                   upstream's Security package does not build at c713d8fb (trustd includes
#                   <System/sys/content_protection.h>, which the package's source set lacks),
#                   and with it SystemConfiguration and the whole full image. One CMake line.
#               The flake's outputs are evaluated from that copy with the tip's own inputs.
#               Package sources are filtered copies named by content, so every package the
#               patch does not reach is the same derivation as with ../rebase/pd.nix (checked:
#               kernel collection, libSystem, curl); only Security and what links it differ.
# The minimal image, the kernel collection and everything the M1 boots keep using
# ../rebase/pd.nix directly.
let
  source = import ../rebase/pd.nix;
  inherit (source) pd pkgs;
  patched = pkgs.applyPatches {
    name = "siliconforest-${builtins.substring 0 8 source.rev}-userland-source";
    src = pd.outPath;
    patches = [ ./tree-patches/security-content-protection-header.patch ];
  };
  # what builtins.getFlake adds to a flake's outputs and the lab's recipes use (outPath, inputs), and the build system base-tree.nix adds
  fixed = (import (patched + "/flake.nix")).outputs (pd.inputs // { self = fixed; })
    // { outPath = "${patched}"; inherit (pd) inputs buildSystem buildPkgs; };
in if source.tip then fixed else pd
