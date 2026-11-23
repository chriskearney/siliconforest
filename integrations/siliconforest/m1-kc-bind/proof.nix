# SPDX-License-Identifier: MIT
# The collections that prove ./kc-tools-bind.patch (results: ../m1-exit-waits/kc-tools-duplicate-names.md):
#   nix-build proof.nix -A kernel50         kernel 50 linked with the fixed tool and ./pins-kernel48.txt
#   nix-build proof.nix -A kernel50-rule    the same without pins (the plain rule)
#   nix-build proof.nix -A kernel51         = ../m1-kernel51/build-kc.nix (which uses the fixed tool)
#   nix-build proof.nix -A variant-old      kernel 51 whose kernel exports the diagnostic's four
#                                           functions (throwaway), linked with the old tool
#   nix-build proof.nix -A variant          the same kernel, the fixed tool and the pins
let
  inherit (import ../m1-rust-kext/pins.nix) pkgs;
  tools = import ./build-tools.nix;
  pins = ./pins-kernel48.txt;
  k50 = import ../m1-kernel50/build-kc.nix;
  k51 = import ../m1-kernel51/build-kc.nix;
  bind = name: kc: withPins: (kc.override (o: { kcTools = tools; })).overrideAttrs (o: {
    inherit name;
  } // (if withPins then { KC_BIND_PINS = pins; } else { }));
  # throwaway: the diagnostic with its cross-file functions exported (as the first kernel 51 build)
  exported = pkgs.runCommand "sf-exitwait-exported-names.patch" { } ''
    sed 's/__private_extern__ //' ${../m1-exit-waits/kernel.patch} > $out
    ! grep -q __private_extern__ $out
  '';
  k48kernel = k50.kernel48.kernel;
  variantKernel = k48kernel.overrideAttrs (o: {
    pname = "siliconforest-kernel-t8103-exitwait-exported";
    name = "siliconforest-kernel-t8103-exitwait-exported-0.1";
    patches = o.patches ++ [ exported ];
  });
  variantOn = base: base.override (o: { kernel = variantKernel; });
in {
  kernel50 = bind "siliconforest-kc-kernel50-bind" k50 true;
  kernel50-rule = bind "siliconforest-kc-kernel50-bind-rule" k50 false;
  kernel51 = k51;
  variant-old = (variantOn k50).overrideAttrs (o: { name = "siliconforest-kc-exitwait-exported-oldtool"; });
  variant = (variantOn (bind "siliconforest-kc-exitwait-exported-bind" k50 true)).overrideAttrs (o: {
    name = "siliconforest-kc-exitwait-exported-bind";
  });
  inherit tools variantKernel;
}
