# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# Top-level manifest of the SiliconForest system components and out-of-root recipes
# folded into one tree on sf-integration (bake-in steps 1-3: launchers, system
# AppKit/libFoundation/CT/CG/CF/Foundation, system libWindowServer 0333w+0375w).
#
#   nix-build --extra-experimental-features 'nix-command flakes' --no-out-link \
#     integrations/siliconforest/system-manifest.nix -A <attr>
let
  pd = (import ./rebase/pd.nix).pd;
  pkgs = import pd.inputs.nixpkgs { system = "x86_64-linux"; };
  macosAppsRoot = import ./terminal-app/build-macos-apps-root.nix;
  cocoa = import ./cocoa/patched.nix;
  libsystemLegacy = import ./libsystem-default/build-libsystem-legacy-exports.nix;
  colorsync = import ./finch/ColorSync/build.nix;
  audiotoolbox = import ./finch/AudioToolbox/install.nix;
  opengl = import ./firefox/perf/tools/term12/cgl.nix { with0303 = true; };
  iosurface = import ./cocoa/iosurface.nix;
  surfaceSession = import ./firefox/surface-session.nix;
  corevideo = import ./cocoa/corevideo-displaylink.nix;
  videotoolbox = import ./m1-avd/build-videotoolbox.nix;
  launchers = pkgs.runCommand "siliconforest-system-launchers" { } ''
    mkdir -p $out/usr/bin
    install -m 0755 ${./desktop/system/sf-open-chonkcraft} $out/usr/bin/sf-open-chonkcraft
    install -m 0755 ${./desktop/system/sf-open-preview} $out/usr/bin/sf-open-preview
    install -m 0755 ${./desktop/system/sf-open-textedit} $out/usr/bin/sf-open-textedit
  '';
  # Combined system root tree: macosAppsRoot plus the three out-of-root system libraries
  # (libSystem legacy exports, Finch ColorSync, Finch AudioToolbox) and graphics/media providers.
  systemRoot = pkgs.runCommand "siliconforest-system-root-arm64" { } ''
    cp -a ${macosAppsRoot} $out
    chmod -R u+w $out
    cp -L ${libsystemLegacy}/usr/lib/libSystem.B.dylib $out/usr/lib/libSystem.B.dylib
    rm -rf $out/System/Library/Frameworks/ColorSync.framework
    cp -a ${colorsync}/System/Library/Frameworks/ColorSync.framework $out/System/Library/Frameworks/
    chmod -R u+w $out/System/Library/Frameworks/ColorSync.framework
    cp -L ${audiotoolbox}/System/Library/Frameworks/AudioToolbox.framework/Versions/A/AudioToolbox \
      $out/System/Library/Frameworks/AudioToolbox.framework/Versions/A/AudioToolbox
    cp -L ${launchers}/usr/bin/sf-open-* $out/usr/bin/
    chmod 0755 $out/usr/lib/libSystem.B.dylib \
      $out/System/Library/Frameworks/AudioToolbox.framework/Versions/A/AudioToolbox \
      $out/usr/bin/sf-open-*
  '';
in {
  inherit macosAppsRoot cocoa libsystemLegacy colorsync audiotoolbox opengl iosurface surfaceSession corevideo videotoolbox launchers systemRoot;
  chonkcraftFillsScript = ./chonkcraft/fills.py;
}
