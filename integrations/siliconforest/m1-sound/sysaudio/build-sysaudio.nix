# SPDX-License-Identifier: MIT
# The system audio path of the SiliconForest M1 guest, arm64 Mach-O, from the tree ../../rebase/pd.nix
# selects (the tip; SF_PD=pin: e7aa00a6, the same derivations as before the switch):
#   coreaudiod    the tree's audio server with the /dev backend (plays through the device nodes of
#                 SFAppleSound when there is no IOAudioEngine): ./coreaudiod-dev-backend-tip.patch
#                 at the tip, ./coreaudiod-dev-backend.patch at the pin (the same change; upstream's
#                 capture and device-interest additions moved the context)
#   audiotoolbox  the tree's CoreAudio (with ../../cocoa/patches/0346: block-based property listeners),
#                 AudioToolbox and AudioUnit frameworks
#   pcmplay       the tree's test player, unchanged
#   tools         ./user: sftone (a tone through an AudioQueue) and sfvolume (the volume keys' command)
#   all           the four joined as one root
#   nix-build --extra-experimental-features nix-command --extra-experimental-features flakes build-sysaudio.nix -A all
let
  source = import ../../rebase/pd.nix;
  pd = source.pd;
  pkgs = import pd.inputs.nixpkgs { system = "x86_64-linux"; };
  p = pd.packages.x86_64-linux;
  # the libSystem of the RAM root the binaries run on
  libSystem = source.pick {
    pin = import ../../m1-userspace-diagnostics/build-libsystem-spawnattr.nix;
    tip = import ../../libsystem-default/build-libsystem.nix;
  };
  backend = source.pick { pin = ./coreaudiod-dev-backend.patch; tip = ./coreaudiod-dev-backend-tip.patch; };
  common = {
    darwinCrossToolchain = p.arm64-cross-toolchain;
    nativeLd = p.native-ld;
    appleSdk = p.apple-sdk;
    inherit libSystem;
    corefoundation = p.coreFoundation-arm64;
    targetTriple = "arm64-apple-darwin20.4";
  };
  src = pd.outPath;
  sdk = "${p.apple-sdk}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
  fw = "System/Library/Frameworks";
in rec {
  audiotoolbox = pkgs.callPackage "${src}/nix/pkgs/apple/audiotoolbox.nix" (common // {
    src = "${src}/src/Frameworks/AudioToolbox";
    coreAudioSrc = coreAudioSrc;
  });

  # the tree's CoreAudio with ../../cocoa/patches/0346 (block-based property listeners; first user: Apple's
  # QuickTime Player, docs/roadmap/issues/SF-AI-quicktime.md)
  coreAudioSrc = pkgs.runCommand "siliconforest-coreaudio-src" { nativeBuildInputs = [ pkgs.patch ]; } ''
    mkdir -p tree/src/Frameworks
    cp -r ${src}/src/Frameworks/CoreAudio tree/src/Frameworks/
    chmod -R u+w tree
    (cd tree && patch -p1 --no-backup-if-mismatch < ${../../cocoa/patches/0346-coreaudio-property-listener-blocks.patch})
    cp -r tree/src/Frameworks/CoreAudio $out
  '';

  pcmplay = pkgs.callPackage "${src}/nix/pkgs/apple/pcmplay.nix" (common // {
    inherit audiotoolbox;
    src = "${src}/src/Userspace/pcmplay";
  });

  coreaudiod = (pkgs.callPackage "${src}/nix/pkgs/apple/coreaudiod.nix" (common // { iokit = p.iokit-arm64; })).overrideAttrs (old: {
    pname = "siliconforest-coreaudiod-dev";
    # the recipe's source is the tree's src directory, the patch is against the tree
    src = pkgs.runCommand "siliconforest-coreaudiod-dev-source" { nativeBuildInputs = [ pkgs.patch ]; } ''
      cp -R ${old.src} "$out"
      chmod -R u+w "$out"
      patch -d "$out" -p2 < ${backend}
    '';
  });

  tools = pkgs.stdenv.mkDerivation {
    name = "darwin-lab-sysaudio-tools-arm64";
    dontUnpack = true;
    buildPhase = ''
      CC=${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-clang
      mkdir -p cf-headers
      ln -s ${p.coreFoundation-arm64}/include cf-headers/CoreFoundation
      for t in sftone sfvolume; do
        $CC -isysroot ${sdk} -mmacosx-version-min=26.5 -std=c11 -O2 -Wall -Wextra -Icf-headers -I${libSystem}/usr/include \
          -I${audiotoolbox}/usr/include -c ${./user}/$t.c -o $t.o
        $CC -isysroot ${sdk} -mmacosx-version-min=26.5 -fuse-ld=${p.native-ld}/bin/ld -nostdlib \
          -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libSystem}/usr/lib/system/libdyld.dylib \
          -Wl,-dylib_file,/${fw}/CoreAudio.framework/Versions/A/CoreAudio:${audiotoolbox}/${fw}/CoreAudio.framework/Versions/A/CoreAudio \
          -Wl,-platform_version,macos,26.5,26.5 -L${libSystem}/usr/lib -L${p.coreFoundation-arm64}/usr/lib \
          $t.o ${audiotoolbox}/${fw}/AudioToolbox.framework/Versions/A/AudioToolbox \
          ${audiotoolbox}/${fw}/CoreAudio.framework/Versions/A/CoreAudio -lCoreFoundation -lSystem -o $t
      done
    '';
    installPhase = ''
      install -Dm755 sftone "$out/usr/bin/sftone"
      install -Dm755 sfvolume "$out/usr/bin/sfvolume"
    '';
    dontFixup = true;
    dontStrip = true;
  };

  all = pkgs.runCommand "darwin-lab-sysaudio-arm64" {} ''
    mkdir -p "$out/usr/sbin" "$out/usr/bin" "$out/${fw}"
    cp ${coreaudiod}/usr/sbin/coreaudiod "$out/usr/sbin/"
    cp ${pcmplay}/bin/pcmplay ${tools}/usr/bin/sftone ${tools}/usr/bin/sfvolume "$out/usr/bin/"
    for f in CoreAudio AudioToolbox AudioUnit; do
      install -Dm755 ${audiotoolbox}/${fw}/$f.framework/Versions/A/$f "$out/${fw}/$f.framework/Versions/A/$f"
    done
  '';
}
