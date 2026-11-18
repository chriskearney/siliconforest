# SPDX-License-Identifier: MIT
# Pinned sources of the Metal experiment (Darling's Metal stack; NOTICE has the licences) and the
# arm64 Darwin toolchain of ../m1-vulkan (the same one Mesa, Honeykrisp and the loader are built with).
let
  v = import ../m1-vulkan/common.nix;
  fetch = import ../../../release/fetch.nix { pkgs = v.pkgs; };
in v // rec {
  # 0BSD: Indium (Metal-like C++ API over Vulkan 1.3) and Iridium (AIR -> SPIR-V, through LLVM's C API)
  indiumRev = "e3a1f2212bdadade0afe2e10728e7673f49d3c98";
  indiumSrc = fetch "darling-indium";
  # MPL-2.0: Metal.framework ABI over Indium (pins indium e3a1f22 and mslc 6964bb3 as submodules)
  darlingMetalRev = "57a8a2d34685f34424b961182e45c2ff2642f37f";
  darlingMetalSrc = fetch "darling-darling-metal";
  # MIT: MSL subset -> Vulkan SPIR-V
  mslcRev = "6964bb3984e26de95bbca89b08f305a6c4ff3317";
  mslcSrc = fetch "darling-mslc";
  # LLVM 21 cross-built for arm64 Darwin by the SiliconForest flake (libLLVM.dylib; Iridium dlopens it)
  llvmArm64 = v.p.llvm-arm64;
  llvmHost = v.pkgs.llvmPackages_21.libllvm;
}
