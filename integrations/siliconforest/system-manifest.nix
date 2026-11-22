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
  opengl = import ./firefox/perf/tools/term12/cgl.nix { with0303 = true; with0009 = true; };
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
    # Bake-in step 5 (bk5 Java2D->Metal fallback): install canonical OpenGL.framework
    # (Versions/Current -> A, Versions/A/Libraries/libGL.dylib -> ../OpenGL,
    # OpenGL -> Versions/A/OpenGL, Libraries -> Versions/Current/Libraries) and One GL in /usr/lib.
    rm -rf $out/System/Library/Frameworks/OpenGL.framework
    cp -a ${opengl}/Frameworks/OpenGL.framework $out/System/Library/Frameworks/
    chmod -R u+w $out/System/Library/Frameworks/OpenGL.framework
    [ "$(readlink $out/System/Library/Frameworks/OpenGL.framework/Versions/Current)" = "A" ]
    [ "$(readlink $out/System/Library/Frameworks/OpenGL.framework/Versions/A/Libraries/libGL.dylib)" = "../OpenGL" ]
    [ "$(readlink $out/System/Library/Frameworks/OpenGL.framework/OpenGL)" = "Versions/A/OpenGL" ]
    [ "$(readlink $out/System/Library/Frameworks/OpenGL.framework/Libraries)" = "Versions/Current/Libraries" ]
    [ -f $out/System/Library/Frameworks/OpenGL.framework/Versions/Current/Libraries/libGL.dylib ]
    cp -L ${opengl}/lib/libGL.1.dylib $out/usr/lib/libGL.1.dylib
    ln -sfn libGL.1.dylib $out/usr/lib/libGL.dylib
    ln -sfn /usr/local/lib/mesa-asahi/libEGL.1.dylib $out/usr/lib/libEGL.1.dylib
    cp -L ${launchers}/usr/bin/sf-open-* $out/usr/bin/
    chmod 0755 $out/usr/lib/libSystem.B.dylib $out/usr/lib/libGL.1.dylib \
      $out/System/Library/Frameworks/AudioToolbox.framework/Versions/A/AudioToolbox \
      $out/usr/bin/sf-open-*
  '';
in {
  inherit macosAppsRoot cocoa libsystemLegacy colorsync audiotoolbox opengl iosurface surfaceSession corevideo videotoolbox launchers systemRoot;
  chonkcraftFillsScript = ./chonkcraft/fills.py;
}
