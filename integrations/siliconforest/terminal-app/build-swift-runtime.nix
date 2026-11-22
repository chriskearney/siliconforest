# SPDX-License-Identifier: MIT
# The Swift runtime for the disk root (/usr/lib/swift): upstream PureDarwin's build of Swift
# 6.3.3 from swift.org's sources (Apache-2.0 with the runtime library exception) and the
# open Darwin overlays, at the revision of ../rebase/pd.nix, with one correction:
#
#   swift_isaMask. The runtime carries its own copy of libobjc's isa mask ("the values MUST
#   match the ones from libobjc", stdlib/public/runtime/Private.h). For arm64 macOS it takes
#   0x00007ffffffffff8, which is right for Apple's libobjc (an arm64e build whose packed isa
#   has the class in bits 3..54). This system's libobjc is a plain arm64 build, whose packed
#   isa is objc4's other arm64 layout: class in bits 3..35, a magic value above (ISA_MASK
#   0x0000000ffffffff8). With the wrong mask swift_getObjectType() of any Objective-C object
#   with a packed isa reads the magic bits as part of the class pointer and faults (found
#   with Terminal.app's first Swift call, docs/roadmap/issues/SF-Y-terminal-app.md).
#
# and one correction of the renamed tree, ../rebase/swift-darwin-module.nix (the Darwin module map).
#
# and one addition to the Foundation overlay (libswiftFoundation): ./swift/SFBridging.swift,
# Dictionary <-> NSDictionary and Int, Bool <-> NSNumber bridging.
#
#   nix-build --extra-experimental-features 'nix-command flakes' --no-out-link build-swift-runtime.nix
let
  pd = (import ../rebase/pd.nix).pd;
in (import ../rebase/swift-darwin-module.nix pd.packages.${pd.buildSystem}."swift-runtime-arm64").overrideAttrs (old: {
  pname = "siliconforest-swift-runtime";
  buildPhase = builtins.replaceStrings
    [ "cmake -P $S/Runtimes/Resync.cmake > /dev/null"
      "$FO/NSFastEnumeration.swift $FO/SFSwiftStringBridge.m" ]
    [ ''
      grep -q '#      define SWIFT_ISA_MASK 0x00007ffffffffff8ULL' $S/stdlib/public/runtime/Private.h
      sed -i 's|#      define SWIFT_ISA_MASK 0x00007ffffffffff8ULL|#      define SWIFT_ISA_MASK 0x0000000ffffffff8ULL /* SiliconForest: libobjc is a plain arm64 build */|' $S/stdlib/public/runtime/Private.h
      cmake -P $S/Runtimes/Resync.cmake > /dev/null''
      "$FO/NSFastEnumeration.swift ${./swift/SFBridging.swift} $FO/SFSwiftStringBridge.m" ]
    old.buildPhase;
})
