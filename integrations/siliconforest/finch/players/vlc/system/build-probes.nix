# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# The probes of VLC's system install (../../../../../../docs/roadmap/issues/SF-AH-vlc.md, "Proposal"):
#   usr/share/sf-test/sf-vlc-features-probe    what of the six steps the system in use has (dlopen only)
#   usr/share/sf-test/sf-vlc-libsystem-probe   status 0 only with step 6's libSystem (the installer's proof)
#   usr/share/sf-test/sf-bookmark-probe        status 0 only with a libFoundation that has NSURL bookmarks (step 7b)
# (step 5's proof is the system tree's own sf-kvo-probe, whose twelfth check is the queued perform).
#   nix-build --extra-experimental-features 'nix-command flakes' --no-out-link build-probes.nix
let
  pd = (import ../../../../rebase/pd.nix).pd;
  p = pd.packages.x86_64-linux;
  pkgs = import pd.inputs.nixpkgs { system = "x86_64-linux"; };
  libsystem = import ../../../../terminal-app/build-libsystem.nix;
  legacy = import ../../../../libsystem-default/build-libsystem-legacy-exports.nix;
  foundation = import ../../../../terminal-app/build-foundation-networking.nix;
  sdk = "${p.apple-sdk}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
in pkgs.runCommand "siliconforest-vlc-system-probes-arm64" { } ''
  CC=${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-clang
  CF="-isysroot ${sdk} -mmacosx-version-min=26.5 -O1 -fno-objc-arc -fobjc-exceptions -fblocks -Wno-nullability-completeness -Wno-objc-root-class -Wno-deprecated-declarations -isystem ${sdk}/usr/include -I${libsystem}/usr/include -I${p.libobjc-arm64}/usr/include -I${p.coreFoundation-arm64}/include -I${foundation}/usr/include"
  mkdir -p $out/usr/share/sf-test lib-now lib-legacy
  ln -s ${libsystem}/usr/lib/libSystem.B.dylib lib-now/libSystem.dylib
  ln -s ${legacy}/usr/lib/libSystem.B.dylib lib-legacy/libSystem.dylib
  ln -s ${foundation}/usr/lib/libFoundation.dylib lib-now/libFoundation.dylib
  LF="-fuse-ld=${p.native-ld}/bin/ld -nostdlib -L${p.libobjc-arm64}/usr/lib -L${p.coreFoundation-arm64}/usr/lib -Wl,-platform_version,macos,26.5,26.5"
  $CC $CF ${./probe/sf-vlc-features-probe.m} $LF -Llib-now -lobjc -lFoundation -lSystem -o $out/usr/share/sf-test/sf-vlc-features-probe
  $CC $CF ${./probe/sf-vlc-libsystem-probe.c} $LF -Llib-legacy -lSystem -o $out/usr/share/sf-test/sf-vlc-libsystem-probe
  $CC $CF ${./probe/sf-bookmark-probe.m} $LF -Llib-now -lobjc -lFoundation -lSystem -o $out/usr/share/sf-test/sf-bookmark-probe
  chmod 755 $out/usr/share/sf-test/*
''
