# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
#
# PROPOSAL, not used by any other recipe: the Swift runtime of build-swift-runtime.nix with
# CGFloat in the CoreFoundation overlay (libswiftCoreFoundation), where macOS has it.
#
# Why: Swift code that names CGFloat (SwiftUI's frame modifier, anything with a size) is
# mangled with CoreGraphics.CGFloat, and client binaries bind CGFloat's metadata and
# witnesses from libswiftCoreFoundation. Our overlay is the Swift 5.4.3 CoreFoundation.swift
# alone and has no CGFloat. Until this lands, ../finch/QuickTime/loader.nix compiles the same
# source into its private SwiftUI subset.
#
# The source is the Finch project's userland/swift/overlays/CoreFoundation/CGFloat.swift
# (Apache-2.0 with the Swift Runtime Library Exception; the Swift project's historical
# CGFloat.swift.gyb expanded for 64-bit, in module CoreFoundation with
# @_originallyDefinedIn(module: "CoreGraphics")), taken from the pinned Finch revision.
#
# To adopt: make this the body of build-swift-runtime.nix (it changes that derivation, so
# every Swift recipe rebuilds and libswiftCoreFoundation.dylib on the disk root changes:
# a core-library swap, to be rehearsed in QEMU first), then drop CGFloat.swift from loader.nix.
#
#   nix-build --extra-experimental-features 'nix-command flakes' --no-out-link build-swift-runtime-cgfloat.nix
let
  finch = import ../finch/source.nix;
  line = ''$B CoreFoundation "$D/CoreFoundation/CoreFoundation.swift" -framework CoreFoundation'';
in (import ./build-swift-runtime.nix).overrideAttrs (old:
  let
    fixed = builtins.replaceStrings [ line ]
      [ ''$B CoreFoundation "$D/CoreFoundation/CoreFoundation.swift" ${finch}/userland/swift/overlays/CoreFoundation/CGFloat.swift -framework CoreFoundation'' ]
      old.buildPhase;
  in assert fixed != old.buildPhase; {
    pname = "siliconforest-swift-runtime-cgfloat";
    buildPhase = fixed;
  })
