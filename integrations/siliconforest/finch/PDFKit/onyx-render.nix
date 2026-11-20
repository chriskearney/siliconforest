# SPDX-License-Identifier: MIT
# Renderer for process-local testing with the retained CoreGraphics framework.
{ onyx2d ? (import ../../cocoa/patched.nix).onyx2d }:
onyx2d.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    ./patches/0002-onyx-pdf-rectangle-operands.patch
    ./patches/0003-onyx-pdf-read-cache-lifetime.patch
  ];
})
