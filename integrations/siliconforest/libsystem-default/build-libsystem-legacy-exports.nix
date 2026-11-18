# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# Candidate for the default arm64 libSystem: the optimised default (./build-libsystem-opt.nix)
# plus patches/legacy-mach-and-errno-exports.patch, seven exports that programs built for older
# macOS releases still import and that this tree compiles but did not export:
#   sys_errlist, sys_nerr                    libc's errno table (VLC's libvlccore)
#   exc_server, exception_raise              the Mach exception interface (Breakpad)
#   bootstrap_subset, bootstrap_create_server, bootstrap_create_service
#                                            launchd's legacy bootstrap calls (Breakpad)
# A core file: tried from a private directory (DYLD_LIBRARY_PATH) first; a system install goes
# through the QEMU rehearsal and the guarded installer (docs/roadmap/issues/SF-AH-vlc.md).
#
#   nix-build --extra-experimental-features 'nix-command flakes' --no-out-link build-libsystem-legacy-exports.nix
(import ./build-libsystem-opt.nix { }).overrideAttrs (old: {
  pname = "siliconforest-libsystem-legacy-exports";
  patches = old.patches ++ [ ./patches/legacy-mach-and-errno-exports.patch ];
})
