# SPDX-License-Identifier: MIT
# The kernel collection of the QEMU desktop loop: upstream's arm64 `virt` collection (RELEASE
# kernel by default) with patched USB keyboard and firmware framebuffer kexts.
# The Parallels guest source supplies its own opt-in BSD interface naming.
# ramfb-normal-memory.patch maps the platform firmware framebuffer as Normal non-cacheable
# DRAM: Device attributes fault on unaligned memcpy stores when a terminal redraws.
#   [SF_PD=pin] nix-build ... build-kc.nix [--argstr kernelConfig debug] --no-out-link   ->  <out>/kernel
# source is the base to build from (build-image.nix passes its own on).
{ kernelConfig ? "release", source ? import ../rebase/pd.nix }:
let
  # the SiliconForest source: ../rebase/pd.nix (the tip by default, SF_PD=pin for e7aa00a6)
  inherit (source) pd pkgs;
  p = pd.packages.${pkgs.stdenv.hostPlatform.system};
  kexts = p.kexts-arm64.overrideAttrs (old: {
    src = pkgs.applyPatches {
      name = "siliconforest-qemu-dev-kexts-source";
      src = old.src;
      patches = [ ./sfhid-publish-keyboard.patch ]
        ++ pkgs.lib.optional (!(source.parallelsGuest or false)) ./virtio-net-name-interface.patch
        ++ [ ./ramfb-normal-memory.patch ];
    };
  });
  kc = if kernelConfig == "debug" then p.kc-arm64-debug else p.kc-arm64;
in kc.override ({
  inherit kexts;
} // pkgs.lib.optionalAttrs (source.parallelsGuest or false) {
  extraKexts = [ "${kexts}/System/Library/Extensions/IOVirtIOSocket.kext" ];
})
