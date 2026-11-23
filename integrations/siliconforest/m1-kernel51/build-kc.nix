# SPDX-License-Identifier: MIT
# Kernel 51: kernel 50 (../m1-kernel50/build-kc.nix, unchanged) with ONE member replaced: the
# kernel, built with ../m1-exit-waits/kernel.patch after kernel 48's patch series (the report
# kern.sf_exitwait of what processes stuck in exit wait for; off by default, root only). The 56
# kexts, the link phase and its checks are kernel 50's, by derivation. The link uses kc-tools with
# ../m1-kc-bind/kc-tools-bind.patch and ../m1-kc-bind/pins-kernel48.txt: imports bind by declared
# libraries, never by a bisection over duplicate names (the same bytes as the old tool here).
#   nix-build build-kc.nix --no-out-link                 the collection ($out/kernel)
#   nix-build build-kc.nix -A kernel --no-out-link       the one changed member
#   nix-build build-kc.nix -A members --no-out-link      every member as built (for the proof:
#                                                        kernel 48's members, kernel 50's ext4,
#                                                        this kernel)
let
  inherit (import ../m1-rust-kext/pins.nix) pkgs;
  k50 = import ../m1-kernel50/build-kc.nix;
  k48 = k50.kernel48;
  ext = "System/Library/Extensions";
  old = k48.kernel;
  kernel = old.overrideAttrs (o: {
    pname = "siliconforest-kernel-t8103-devfs-upl-private-exitwait";
    name = "siliconforest-kernel-t8103-devfs-upl-private-exitwait-0.1";
    patches = o.patches ++ [ ../m1-exit-waits/kernel.patch ];
  });
  collection = k50.override (o: {
    kcTools = import ../m1-kc-bind/build-tools.nix;
    kernel = assert o.kernel == old; kernel;
    # the unpatched tree, as for kernel 48 and 50 (the patch adds no header a kext uses)
    kernelSource = assert o.kernelSource == old.src && kernel.src == old.src; o.kernelSource;
  });
  members = pkgs.runCommand "siliconforest-kernel51-members" { } ''
    mkdir -p $out/kexts $out/kernel
    cp -RL ${kernel}/System/Library/Kernels/. $out/kernel/
    cp -RL ${k48.members}/kexts/. $out/kexts/
    chmod -R u+w $out
    rm -rf $out/kexts/ext4.kext
    cp -RL ${k50.ext4}/${ext}/ext4.kext $out/kexts/ext4.kext
  '';
in collection.overrideAttrs (o: {
  name = "siliconforest-kc-kernel51";
  KC_BIND_PINS = ../m1-kc-bind/pins-kernel48.txt;
  passthru = (o.passthru or { }) // { inherit kernel members; kernel50 = k50; };
})
