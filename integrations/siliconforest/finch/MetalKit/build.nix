# SPDX-License-Identifier: MIT
# The retained NSView and CAMetalLayer supply the view and its layer backend.
let
  a = import ../../cocoa/arm64.nix;
  appkit = a.appDeps.appkit;
  quartz = a.appDeps.quartzcore;
  graphics = a.appDeps.coregraphics;
  onyx = a.appDeps.onyx2d;
in (import ../objc-framework.nix {
  name = "MetalKit";
  version = "173.7.0";
  extraIncludes = "-I${appkit}/usr/include -I${quartz}/usr/include -I${graphics}/usr/include -I${onyx}/usr/include -I${a.src}/src/Frameworks -I${a.mesa}/usr/include -F${a.openglFramework}/System/Library/Frameworks";
  extraLinks = "-L${appkit}/usr/lib -L${quartz}/usr/lib -L${graphics}/usr/lib -lAppKit -lQuartzCore -lCoreGraphics";
}).overrideAttrs (old: {
  buildPhase = builtins.replaceStrings [ "userland/MetalKit/*.m" ] [ "userland/MetalKit/MTKView.m" ] old.buildPhase;
})
