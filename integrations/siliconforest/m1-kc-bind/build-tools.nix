# SPDX-License-Identifier: MIT
# kc-tools as ../m1-bringup/kc-tools-fixed.nix builds it, with ./kc-tools-bind.patch: a kext's
# imports bind by its declared libraries (then the kernel), never by where a bisection over
# duplicate names lands; an import that stays ambiguous fails the build.
(import ../m1-bringup/kc-tools-fixed.nix).overrideAttrs (old: {
  pname = "kc-tools-arm64-text-bind";
  patches = (old.patches or [ ]) ++ [ ./kc-tools-bind.patch ];
})
