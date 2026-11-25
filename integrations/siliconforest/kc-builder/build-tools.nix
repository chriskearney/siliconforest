# SPDX-License-Identifier: MIT
# kc-tools for the installer and the release: ../m1-bringup/kc-tools-fixed.nix (the locked PureDarwin
# kc-tools with the ARM64 layout fix) plus ./kc-tools-sym-order.patch, which makes the symbol table's
# order and a duplicated name's binding independent of the host C library. On glibc the collections are
# byte-identical to kc-tools-fixed.nix's (README.md); on macOS they now match them too.
(import ../m1-bringup/kc-tools-fixed.nix).overrideAttrs (old: {
  pname = "kc-tools-arm64-text-sym-order";
  patches = (old.patches or [ ]) ++ [ ./kc-tools-sym-order.patch ];
})
