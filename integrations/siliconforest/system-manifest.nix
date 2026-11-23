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
  audiotoolboxClock = import ./finch/firefox-media/clock-family.nix;
  opengl = import ./firefox/perf/tools/term12/cgl.nix { with0303 = true; with0009 = true; };
  iosurface = import ./cocoa/iosurface.nix;
  surfaceSession = import ./firefox/surface-session.nix;
  # Bake-in step 8: clocked CoreVideo (DisplayLink + frame-lifetime/0172), full
  # 172-symbol VideoToolbox (encoder + VTSupplement + VTMoreConstants + cb809571e
  # IOSurface GL texture compatibility fix; bare m1-avd/build-videotoolbox.nix only
  # exports 42 symbols and broke VLC HW decode and QuickTime launch in bk8).
  corevideo = import ./finch/firefox-media/clocked-corevideo.nix;
  videotoolbox = import ./finch/VideoToolbox/encoder/build.nix;
  firefoxCompat = import ./firefox/compat.nix { };
  firefoxFonts = import ./firefox/fonts.nix { };
  previewCombine = import ./finch/Preview/Combine/build.nix;
  previewPaperKit = import ./finch/Preview/paperkit.nix;
  previewAnnotationKit = import ./finch/Preview/annotationkit.nix;
  previewVisionKit = import ./finch/Preview/visionkit.nix;
  previewLeaf = import ./finch/Preview/leaf/build.nix;
  previewObservation = import ./finch/Preview/Observation/build.nix;
  previewSynchronization = import ./finch/Preview/Synchronization/build.nix;
  libsystemBase = import ./libsystem-default/build-libsystem.nix;
  p = pd.packages.x86_64-linux;
  sdk = "${p.apple-sdk}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
  # Bake-in step 9a: additive system stub frameworks (Accessibility, AuthenticationServices,
  # unified CoreMIDI, ExceptionHandling, IOBluetooth, MetalKit, ScreenCaptureKit,
  # ServiceManagement, Vision, and /usr/lib/libcups.2.dylib).
  systemStubs = pkgs.runCommand "siliconforest-system-stubs-arm64" { } ''
    F=$out/System/Library/Frameworks
    mkdir -p "$F" "$out/usr/lib"
    for fw in Accessibility AuthenticationServices IOBluetooth MetalKit ScreenCaptureKit ServiceManagement Vision; do
      cp -a "${firefoxCompat}/System/Library/Frameworks/$fw.framework" "$F/"
    done
    cp -L "${firefoxCompat}/usr/lib/libcups.2.dylib" "$out/usr/lib/libcups.2.dylib"
    CC="${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-clang"
    LD="${p.native-ld}/bin/ld"
    build_stub() {
      name=$1; ver=$2; src=$3
      dir="$F/$name.framework/Versions/A"
      mkdir -p "$dir"
      "$CC" -O2 -Wall -Werror -fno-stack-protector -isysroot "${sdk}" -c "$src" -o "$name.o"
      "$CC" -dynamiclib "$name.o" --ld-path="$LD" -nostdlib -isysroot "${sdk}" \
        -L"${libsystemBase}/usr/lib" -lSystem \
        -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:"${libsystemBase}/usr/lib/system/libdyld.dylib" \
        -Wl,-platform_version,macos,26.5,26.5 \
        -Wl,-install_name,"/System/Library/Frameworks/$name.framework/Versions/A/$name" \
        -Wl,-compatibility_version,1 -Wl,-current_version,"$ver" \
        -o "$dir/$name"
      ln -sfn A "$F/$name.framework/Versions/Current"
      ln -sfn "Versions/Current/$name" "$F/$name.framework/$name"
    }
    build_stub CoreMIDI 69 ${./chonkcraft/frameworks/CoreMIDI.c}
    build_stub ExceptionHandling 15 ${./chonkcraft/frameworks/ExceptionHandling.c}
  '';
  # Bake-in step 9c: additive Preview/Swift frameworks (Combine, PaperKit, AnnotationKit,
  # VisionKitCore, _LocationEssentials, SoftLinking, libswiftObservation,
  # libswiftSynchronization) and NotoSansDevanagari font. RecapPerformanceTesting stays
  # private to TextEdit; Preview's SwiftUI/libSystem.sf-extra overlay stays until step 10.
  previewFrameworks = pkgs.runCommand "siliconforest-preview-frameworks-arm64" { } ''
    F=$out/System/Library/Frameworks
    PF=$out/System/Library/PrivateFrameworks
    mkdir -p "$F" "$PF" "$out/usr/lib/swift" "$out/System/Library/Fonts"
    cp -a ${previewCombine}/System/Library/Frameworks/Combine.framework "$F/"
    cp -a ${previewPaperKit}/System/Library/Frameworks/PaperKit.framework "$F/"
    cp -a ${previewAnnotationKit}/System/Library/PrivateFrameworks/AnnotationKit.framework "$PF/"
    cp -a ${previewVisionKit}/System/Library/PrivateFrameworks/VisionKitCore.framework "$PF/"
    cp -a ${previewLeaf}/System/Library/Frameworks/_LocationEssentials.framework "$F/"
    cp -a ${previewLeaf}/System/Library/PrivateFrameworks/SoftLinking.framework "$PF/"
    chmod -R u+w "$F/_LocationEssentials.framework" "$PF/SoftLinking.framework"
    ln -sfn A "$F/_LocationEssentials.framework/Versions/Current"
    ln -sfn Versions/Current/_LocationEssentials "$F/_LocationEssentials.framework/_LocationEssentials"
    ln -sfn A "$PF/SoftLinking.framework/Versions/Current"
    ln -sfn Versions/Current/SoftLinking "$PF/SoftLinking.framework/SoftLinking"
    cp -L ${previewObservation}/usr/lib/swift/libswiftObservation.dylib "$out/usr/lib/swift/"
    cp -L ${previewSynchronization}/usr/lib/swift/libswiftSynchronization.dylib "$out/usr/lib/swift/"
    cp -L ${firefoxFonts}/NotoSansDevanagari-Regular.ttf "$out/System/Library/Fonts/"
  '';
  launchers = pkgs.runCommand "siliconforest-system-launchers" { } ''
    mkdir -p $out/usr/bin
    install -m 0755 ${./desktop/system/sf-open-chonkcraft} $out/usr/bin/sf-open-chonkcraft
    install -m 0755 ${./desktop/system/sf-open-preview} $out/usr/bin/sf-open-preview
    install -m 0755 ${./desktop/system/sf-open-textedit} $out/usr/bin/sf-open-textedit
    install -m 0755 ${./desktop/system/sf-open-minecraft} $out/usr/bin/sf-open-minecraft
    install -m 0755 ${./desktop/system/sf-open-quake} $out/usr/bin/sf-open-quake
    install -m 0755 ${./desktop/system/sf-screenrecord} $out/usr/bin/sf-screenrecord
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
    cp -L ${audiotoolboxClock}/Frameworks/AudioToolbox.framework/Versions/A/AudioToolbox.output-sf \
      $out/System/Library/Frameworks/AudioToolbox.framework/Versions/A/AudioToolbox.output-sf
    cp -L ${corevideo}/System/Library/Frameworks/CoreVideo.framework/Versions/A/CoreVideo \
      $out/System/Library/Frameworks/CoreVideo.framework/Versions/A/CoreVideo
    mkdir -p $out/System/Library/Frameworks/VideoToolbox.framework/Versions/A
    cp -L ${videotoolbox}/System/Library/Frameworks/VideoToolbox.framework/Versions/A/VideoToolbox \
      $out/System/Library/Frameworks/VideoToolbox.framework/Versions/A/VideoToolbox
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
    cp -a ${systemStubs}/System/Library/Frameworks/*.framework $out/System/Library/Frameworks/
    cp -L ${systemStubs}/usr/lib/libcups.2.dylib $out/usr/lib/libcups.2.dylib
    mkdir -p $out/System/Library/PrivateFrameworks $out/System/Library/Fonts $out/usr/lib/swift
    cp -a ${previewFrameworks}/System/Library/Frameworks/*.framework $out/System/Library/Frameworks/
    cp -a ${previewFrameworks}/System/Library/PrivateFrameworks/*.framework $out/System/Library/PrivateFrameworks/
    cp -L ${previewFrameworks}/usr/lib/swift/*.dylib $out/usr/lib/swift/
    cp -L ${previewFrameworks}/System/Library/Fonts/*.ttf $out/System/Library/Fonts/
    chmod 0755 $out/usr/lib/libSystem.B.dylib $out/usr/lib/libGL.1.dylib $out/usr/lib/libcups.2.dylib \
      $out/System/Library/Frameworks/AudioToolbox.framework/Versions/A/AudioToolbox \
      $out/usr/bin/sf-open-*
  '';
in {
  inherit macosAppsRoot cocoa libsystemLegacy colorsync audiotoolbox audiotoolboxClock opengl iosurface surfaceSession corevideo videotoolbox systemStubs previewFrameworks launchers systemRoot;
  chonkcraftFillsScript = ./chonkcraft/fills.py;
}
