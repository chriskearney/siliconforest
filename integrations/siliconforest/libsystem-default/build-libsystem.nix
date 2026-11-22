# SPDX-License-Identifier: MIT
# The lab's default arm64 libSystem: what the M1 RAM root and the QEMU images stage as
# /usr/lib/libSystem.B.dylib.
#
#   upstream PureDarwin, arm64, at the revision of ../rebase/pd.nix (the tip; SF_PD=pin: e7aa00a6)
#   + ../m1-userspace-diagnostics/fix-root/vm-page-size-symbol.patch
#   + ../m1-userspace-diagnostics/fix-spawnattr/posix-spawnattr-init-zero.patch
#       (those two are the previous default, build-libsystem-spawnattr.nix)
#   + patches/macos-abi.patch (GitHub issue 46):
#       ___chkstk_darwin enters the real stack probe instead of landing on sandbox_check()
#       (every function with a frame over one page lost its first argument);
#       <fenv.h> with the macOS arm64 layout; the long double entry points;
#       getcontext/setcontext/makecontext/swapcontext; exports that programs built
#       against the macOS SDK import. See docs/roadmap/issues/SF-S-homebrew.md.
#   + patches/xpc-copy-description-never-aborts.patch (GitHub issue 51):
#       xpc_copy_description() describes a connection, data and a double, and names any
#       other type, instead of ending the process ("libxpc misuse: Unknown XPC type",
#       exit reason LIBXPC/2). Security's client describes its connection in every error
#       it builds, so any program whose SecItemCopyMatching failed was killed (the Claude
#       Code CLI: docs/roadmap/issues/SF-X-claude-code.md).
#   + patches/strxfrm-without-directives.patch (GitHub issue 45):
#       strxfrm_l()/wcsxfrm_l() called wcslen(NULL) in a locale whose collation table has no
#       directives (en_US.UTF-8 as the tree's locale data has it): SIGSEGV in every program
#       that calls strxfrm() there (perl at start). Now such a locale collates as C does.
#       Also built and exported: timingsafe_bcmp (openssh, libfido2), ualarm.
#   + patches/dyld-arm64e-keys-off.patch, patches/dyld-objc-writes-data-const.patch (GitHub issue 52;
#     both change /usr/lib/dyld, which this recipe's output carries beside libSystem):
#       dyld measures that pointer signing does nothing in the process it starts (this kernel
#       keeps the PAC keys off and lowers PAC instructions in every executable page) and then
#       loads arm64 libraries into an arm64e program and arm64e slices into any program; it opens
#       the read-only __DATA_CONST segment for the Objective-C runtime while it is told an image
#       is mapped (current linkers put Objective-C reference sections there).
#   + patches/macos26-sdk-imports.patch (GitHub issue 52):
#       malloc_type_*, _os_feature_enabled_impl, the qtn_proc calls, os_variant_is_basesystem,
#       strnvis: what programs built against the macOS 26 SDK import.
#     See docs/roadmap/issues/SF-Y-terminal-app.md (rehearsed in QEMU and replaced on the M1 by
#     the guarded procedure, ../terminal-app/tools/sf_terminal.sh).
#   + patches/feature-flags.patch (GitHub issue 52): os_feature_enabled() reads the property lists
#       under /System/Library/FeatureFlags and /Library/Preferences/FeatureFlags as macOS does
#       (Finch's reader, MIT OR Apache-2.0, kept with its notice in stub/sf_featureflags.c);
#       before, every feature was off (Terminal's DirectColor: true colour drawn as bands).
#   + patches/memorystatus-level.patch (GitHub issue 53): memorystatus_get_level(), the wrapper of
#       the kernel's system call 453 (the memory-pressure level Activity Monitor's Memory tab draws).
#
#   nix-build --extra-experimental-features 'nix-command flakes' --no-out-link build-libsystem.nix
let
  pd = (import ../rebase/pd.nix).pd;
in pd.packages.${pd.buildSystem}.libsystem-arm64.overrideAttrs (old: {
  pname = "siliconforest-libsystem-default";
  patches = (old.patches or []) ++ [
    ../m1-userspace-diagnostics/fix-root/vm-page-size-symbol.patch
    ../m1-userspace-diagnostics/fix-spawnattr/posix-spawnattr-init-zero.patch
    ./patches/macos-abi.patch
    ./patches/xpc-copy-description-never-aborts.patch
    ./patches/strxfrm-without-directives.patch
    ./patches/dyld-arm64e-keys-off.patch
    ./patches/dyld-objc-writes-data-const.patch
    ./patches/macos26-sdk-imports.patch
    ./patches/feature-flags.patch
    ./patches/memorystatus-level.patch
  ];
})
