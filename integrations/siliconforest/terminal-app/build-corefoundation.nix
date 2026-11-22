# SPDX-License-Identifier: MIT
# /usr/lib/libCoreFoundation.dylib for SiliconForest's (the root's own, ../rebase/pd.nix's
# coreFoundation-arm64) with two changes (GitHub issues 52, 53; docs/roadmap/issues/SF-AA-activity-monitor.md):
#   - compiled with -O2 -fno-strict-aliasing: upstream's CMake configure names no build type, so every
#     CoreFoundation call of every program (strings, dictionaries, run loops, property lists) ran
#     unoptimised code (-O0: each local variable stored to and loaded from the stack)
#   - patches/corefoundation-autorelease.patch: CFAutorelease puts CF's own instances in the autorelease
#     pool, as macOS's does; it returned them unreleased (a leak at every call; libFoundation's
#     SFAutoreleaseCF.h worked around it for Foundation's own calls only)
# A core file (every program loads it): QEMU rehearsal and the guarded installer only (SF-Y, "Installing").
#
#   nix-build --extra-experimental-features 'nix-command flakes' --no-out-link build-corefoundation.nix
#   ... --arg autorelease false      -O2 alone (rehearsed on its own first, so that a fault can be told apart)
{ autorelease ? true }:
let
  pd = (import ../rebase/pd.nix).pd;
  p = pd.packages.${pd.buildSystem};
  flags = "-O2 -fno-strict-aliasing ";
in p.coreFoundation-arm64.overrideAttrs (old: {
  pname = if autorelease then "siliconforest-corefoundation" else "siliconforest-corefoundation-o2";
  patches = (old.patches or [ ]) ++ (if autorelease then [ ./patches/corefoundation-autorelease.patch ] else [ ]);
  configurePhase = builtins.replaceStrings
    [ ''-DCMAKE_C_FLAGS="'' ''-DCMAKE_OBJC_FLAGS="'' ]
    [ ''-DCMAKE_C_FLAGS="${flags}'' ''-DCMAKE_OBJC_FLAGS="${flags}'' ]
    old.configurePhase;
})
