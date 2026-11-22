# SPDX-License-Identifier: MIT
# /usr/lib/libobjc.A.dylib for SiliconForest's (../rebase/pd.nix's libobjc-arm64, which the
# root has: objc4 compiled -Os -DNDEBUG, as Apple builds it) with one change (GitHub issue 52;
# docs/roadmap/issues/SF-Y-terminal-app.md, "Performance: optimised core libraries"):
#   - patches/objc-pool-trace-read-once.patch: SiliconForest's pool trace asked getenv("SF_POOL_TRACE") at
#     every autorelease and at every object released by a pool pop; getenv walks the whole environment
#     (strncmp per variable) each time. The variable is now read once with the runtime's other
#     variables (environ_init at _objc_init): SF_POOL_TRACE still works when it is set at start.
# A core file (every Objective-C program loads it): QEMU rehearsal and the guarded installer only
# (SF-Y, "Installing"); its proof is probe/sf-objc-probe.m.
#
#   nix-build --extra-experimental-features 'nix-command flakes' --no-out-link build-libobjc.nix
let
  pd = (import ../rebase/pd.nix).pd;
  p = pd.packages.${pd.buildSystem};
in p.libobjc-arm64.overrideAttrs (old: {
  pname = "siliconforest-libobjc";
  patches = (old.patches or [ ]) ++ [ ./patches/objc-pool-trace-read-once.patch ];
})
