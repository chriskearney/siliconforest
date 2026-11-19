# SPDX-License-Identifier: MIT OR Apache-2.0
# SceneKit load subset. It does not parse or draw 3D scenes.
# appkit and coregraphics default to the cached retained PDFKit toolchain.
# The package AppKit attribute rebuilds LLVM, so this file does not use it.
{ appkit ? "/nix/store/cx4yvkwbcm6xdicdj43d5srxkwvcjajs-puredarwin-appkit-0.1"
, coregraphics ? "/nix/store/jrcb39irvzmh95cd8wwiabsvsjxy5k58-puredarwin-coregraphics-0.1"
}:
let
  e = import ../environment.nix;
  inherit (e) pkgs;
  sp = builtins.storePath;
  # Plain store strings are invisible in the sandbox. storePath records them
  # and their closures without rebuilding the cached toolchain.
  sdkRoot = sp "/nix/store/6zpwyx6p9swad42f0vx6rl4z0dp2kj1g-puredarwin-oss-sdk-26.5";
  sdk = "${sdkRoot}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
  toolchain = sp "/nix/store/v0x4y2cjbasgmrqsbka2bp8allw8j9ph-darwin-cross-toolchain-nix";
  cc = "${toolchain}/bin/arm64-apple-darwin20.4-clang";
  nm = "${toolchain}/bin/arm64-apple-darwin20.4-nm";
  ld = "${sp "/nix/store/n19v2yzd05pirxz38xjhghknchx3fg1i-puredarwin-native-ld-0.1"}/bin/ld";
  libsystem = sp "/nix/store/jll17vb2bl849knd0b68n358c53wh1gl-puredarwin-libsystem-0.1";
  foundation = sp "/nix/store/1ckkk3a7wxm9chd7nllrghdzraajfa0s-puredarwin-foundation-1";
  cf = sp "/nix/store/fnk08vbghiqlvxwmbch7w2k9f40a9hf7-puredarwin-corefoundation-1338";
  objc = sp "/nix/store/m12qv34g2njbwmcrryz3fxgm0lay698x-puredarwin-libobjc-1";
  coretext = sp "/nix/store/dny0xzqw5mh1lnzzb0aq20v19m2dz0ab-puredarwin-coretext-0.1";
  headers = sp "/nix/store/fg0fkyrgy6q6v3ldkyqpnw63m3ym49q8-include";
  onyx = sp "/nix/store/fsayqy35pv82qpz4a795qncqkfkmakgg-puredarwin-onyx2d-0.1";
  frameworks = sp "/nix/store/sjcahlnky79w8mq11gg9vm8spxlv6z80-source";
  mesa = sp "/nix/store/kks507ivyszy33njp9h78y5znigl20h6-puredarwin-mesa-nox-msm-26.1.6";
  readlib = sp "/nix/store/9yjfx30kdpsc9hfch3igiis362nsngy3-siliconforest-finch-SFCGPDFRead-arm64-0.1.0";
  appkitP = sp appkit;
  coregraphicsP = sp coregraphics;
in pkgs.stdenv.mkDerivation {
  pname = "siliconforest-finch-SceneKit-arm64";
  version = "608.255.0";
  src = pkgs.lib.cleanSource ./.;
  dontConfigure = true;
  buildPhase = ''
    unset NIX_CFLAGS_COMPILE NIX_LDFLAGS NIX_CFLAGS_LINK || true
    export DARWIN_SDK_ROOT=${sdk}
    INC="-Iinclude -I${headers} -I${appkitP}/usr/include -I${foundation}/usr/include -I${cf}/include -I${objc}/usr/include -I${coregraphicsP}/usr/include -I${coretext}/usr/include -I${onyx}/usr/include -I${frameworks}/src/Frameworks -I${frameworks}/src/Frameworks/OpenGL/include -I${mesa}/usr/include"
    CF="-isysroot ${sdk} -mmacosx-version-min=26.5 -O2 -fblocks -fobjc-exceptions -fno-objc-arc -D_DARWIN_C_SOURCE -Wno-nullability-completeness -Wno-macro-redefined -Wno-incomplete-implementation $INC"
    ${cc} $CF -c sf_scenekit.m -o scene.o
    ${cc} -dynamiclib scene.o --ld-path=${ld} -nostdlib -isysroot ${sdk} \
      -L${libsystem}/usr/lib -L${libsystem}/usr/lib/system \
      -L${foundation}/usr/lib -L${cf}/usr/lib -L${objc}/usr/lib \
      -L${coregraphicsP}/usr/lib -L${coretext}/usr/lib \
      -F${appkitP}/System/Library/Frameworks -framework AppKit \
      -L${readlib}/usr/lib \
      -lCoreGraphics -lCoreText -lFoundation -lCoreFoundation -lobjc -lSystem \
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
      -L${coregraphicsP}/usr/lib -L${coretext}/usr/lib \
      -F${appkitP}/System/Library/Frameworks -framework AppKit \
      -L${readlib}/usr/lib \
      -lCoreGraphics -lCoreText -lFoundation -lCoreFoundation -lobjc -lSystem \
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
