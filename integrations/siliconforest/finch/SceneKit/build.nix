# SPDX-License-Identifier: MIT OR Apache-2.0
# SceneKit load subset. It does not parse or draw 3D scenes.
let
  e = import ../environment.nix;
  a = import ../../cocoa/arm64.nix;
  inherit (e) pkgs sdk cc ld libsystem;
  appkit = a.appDeps.appkit;
  coregraphics = a.appDeps.coregraphics;
  onyx = a.appDeps.onyx2d;
  foundation = a.base.foundation;
  cf = a.base.corefoundation;
  objc = a.base.libobjc;
  nm = "${e.p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-nm";
in pkgs.stdenv.mkDerivation {
  pname = "siliconforest-finch-SceneKit-arm64";
  version = "608.255.0";
  src = pkgs.lib.cleanSource ./.;
  dontConfigure = true;
  buildPhase = ''
    export DARWIN_SDK_ROOT=${sdk}
    INC="-Iinclude -isystem ${appkit}/usr/include -isystem ${foundation}/usr/include -isystem ${cf}/include -isystem ${objc}/usr/include -isystem ${coregraphics}/usr/include -isystem ${onyx}/usr/include -isystem ${a.appDeps.quartzcore}/usr/include -isystem ${a.src}/src/Frameworks -isystem ${a.mesa}/usr/include -F${a.openglFramework}/System/Library/Frameworks"
    CF="-isysroot ${sdk} -mmacosx-version-min=26.5 -O2 -fblocks -fobjc-exceptions -fno-objc-arc -D_DARWIN_C_SOURCE -Wno-nullability-completeness -Wno-macro-redefined -Wno-incomplete-implementation $INC"
    ${cc} $CF -c sf_scenekit.m -o scene.o
    ${cc} -dynamiclib scene.o --ld-path=${ld} -nostdlib -isysroot ${sdk} \
      -L${libsystem}/usr/lib -L${libsystem}/usr/lib/system \
      -L${foundation}/usr/lib -L${cf}/usr/lib -L${objc}/usr/lib \
      -L${coregraphics}/usr/lib \
      -F${appkit}/System/Library/Frameworks -framework AppKit \
      -lCoreGraphics -lFoundation -lCoreFoundation -lobjc -lSystem \
      -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libsystem}/usr/lib/system/libdyld.dylib \
      -Wl,-platform_version,macos,26.5,26.5 \
      -Wl,-exported_symbols_list,exports.txt \
      -install_name /System/Library/Frameworks/SceneKit.framework/Versions/A/SceneKit \
      -current_version 608.255 -compatibility_version 1 \
      -o libSceneKit.dylib
    ${nm} -g -U libSceneKit.dylib | awk '{print $NF}' | sort -u > defined.txt
    sort exports.txt > exports.sorted
    diff -u exports.sorted defined.txt
    ${cc} $CF -c sf_scenekit_probe.m -o probe.o
    ${cc} probe.o libSceneKit.dylib --ld-path=${ld} -nostdlib -isysroot ${sdk} \
      -L${libsystem}/usr/lib -L${libsystem}/usr/lib/system \
      -L${foundation}/usr/lib -L${cf}/usr/lib -L${objc}/usr/lib \
      -L${coregraphics}/usr/lib \
      -F${appkit}/System/Library/Frameworks -framework AppKit \
      -lCoreGraphics -lFoundation -lCoreFoundation -lobjc -lSystem \
      -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libsystem}/usr/lib/system/libdyld.dylib \
      -Wl,-platform_version,macos,26.5,26.5 \
      -o sfscenekit-load-probe
  '';
  installPhase = ''
    fw=$out/System/Library/Frameworks/SceneKit.framework
    mkdir -p $fw/Versions/A/Headers $out/bin $out/share
    cp libSceneKit.dylib $fw/Versions/A/SceneKit
    cp include/SFSceneKit.h $fw/Versions/A/Headers/SFSceneKit.h
    ln -s A $fw/Versions/Current
    ln -s Versions/Current/SceneKit $fw/SceneKit
    ln -s Versions/Current/Headers $fw/Headers
    cp sfscenekit-load-probe $out/bin/sfscenekit-load-probe
    cp defined.txt $out/share/exports.txt
    sha256sum $fw/Versions/A/SceneKit > $out/share/SceneKit.sha256
    sha256sum $out/bin/sfscenekit-load-probe > $out/share/probe.sha256
  '';
  dontFixup = true;
  dontStrip = true;
}
