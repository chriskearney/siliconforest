# SPDX-License-Identifier: MIT
# The base disk image of the QEMU desktop loop: upstream's arm64 `virt` minimal image
# (GPT: ESP with loader, kernel collection and boot-args.txt; ext4 root) with
#   * the kernel collection of ./build-kc.nix (one kext patch: /dev/usb_hid_kbd for QEMU's
#     USB keyboard),
#   * the loader patched to honour sfgopmode=WxH (./loader-gop-mode.patch).
# Everything else, including the root's userland, is upstream's at the commit ../rebase/pd.nix
# selects (the tip; SF_PD=pin: the old pin e7aa00a6, the same derivations as before the switch).
# qd_image.py adds our userland and boot arguments to a copy of this image.
#   [SF_PD=pin] nix-build ... build-image.nix [--argstr kernelConfig debug] --no-out-link
# variant "wayland" starts from upstream's image-arm64-virt-wayland instead: the full userland
# without X11 (clang, git, curl, openssl, openssh, python, cmake, ...), a 3 GiB class root.
# source is the base to build from; the flake passes its aarch64-linux base for the minimal image.
args@{ kernelConfig ? "release", variant ? "minimal", source ? import ../rebase/pd.nix }:
let
  # the SiliconForest source: ../rebase/pd.nix (the tip by default, SF_PD=pin for e7aa00a6). The
  # full userland comes from ./sf-userland.nix: at the tip upstream's Security package, and so
  # the wayland image, builds only with the tree patch named there.
  pd = if variant == "wayland" then import ./sf-userland.nix else source.pd;
  p = assert variant != "wayland" || !(args ? source) ||
    throw "the wayland variant is built from ./sf-userland.nix and takes no source";
    pd.packages.${source.pkgs.stdenv.hostPlatform.system};
  base = if variant == "wayland" then (if kernelConfig == "debug" then p.image-arm64-virt-wayland-debug else p.image-arm64-virt-wayland)
    else if kernelConfig == "debug" then p.image-arm64-virt-minimal else p.image-arm64-virt-minimal-release;
in base.override (old: {
  kc = import ./build-kc.nix { inherit kernelConfig source; };
  xnuLoader = old.xnuLoader.overrideAttrs (o: {
    patches = (o.patches or [ ]) ++ [ ./loader-gop-mode.patch ];
  });
} // source.pkgs.lib.optionalAttrs (source.parallelsGuest or false) {
  bootArgs = old.bootArgs + " sf_net_autoname=1";
})
