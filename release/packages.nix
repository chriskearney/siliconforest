# SPDX-License-Identifier: MIT
# Copyright (c) 2026 SiliconForest contributors
{ base ? import ./base.nix }:
let
  inherit (base) pkgs;
  sf = ../integrations/siliconforest;
  sourceManifest = builtins.readFile ../sources.lock;
  # The x86_64 source manifest excludes archives used only by the aarch64 Linux host.
  nativeHostArchive = "\n    \"[^\"]+-(aarch64-unknown-linux-gnu|ubuntu24[.]04-aarch64)\": [{][^}]*[}],";
  x86SourceManifest = builtins.concatStringsSep "" (builtins.filter builtins.isString
    (builtins.split nativeHostArchive sourceManifest));
  p = base.pd.packages.x86_64-linux;
  desktop = import ./desktop.nix { inherit base; };
  boot = import ./boot-stages.nix { inherit base; };
  version = "0.1.0";
  releaseBoot = import ./boot-stages.nix {
    inherit base;
    rootUUID = (import ./identity.nix { inherit version; }).rootUUID;
  };
  templateBoot = import ./boot-stages.nix {
    inherit base;
    rootUUID = "53465f52-4f4f-5455-5549-445f5f5f5f5f";
  };
  recipe = path: import (sf + "/${path}");
  rootLayout = name: source: subdir: pkgs.runCommand "siliconforest-${name}-root" { } ''
    mkdir -p "$out"
    cp -RL ${source}${subdir}/. "$out/"
  '';
  pieces = {
    inherit (desktop) desktop terminal;
    macos-apps-root = recipe "terminal-app/build-macos-apps-root.nix";
    homebrew-overlay = recipe "homebrew/build-overlay.nix";
    cgl = recipe "firefox/perf/tools/term12/cgl.nix" { };
    corevideo = recipe "cocoa/corevideo-displaylink-0149.nix";
    iosurface = recipe "cocoa/iosurface.nix";
    cocoa-root = recipe "cocoa/build-cocoa-root.nix" { };
    system-perl = recipe "macos-compat/build-perl.nix";
    foundation-networking = recipe "terminal-app/build-foundation-networking.nix";
    libcompression = recipe "finch/libcompression/build.nix";
    fonts-thai = recipe "cocoa/fonts-thai.nix";
    # Keep all direct release pins in sources.lock and reject a drifting bottle manifest.
    homebrew = let
      pinned = (builtins.fromJSON (builtins.readFile ../sources.lock)).homebrew;
    in assert pinned == builtins.fromJSON (builtins.readFile ./image/homebrew.lock.json);
      import ./image/homebrew.nix { inherit pkgs; };
    activity-monitor = import ./image/activity-monitor.nix {
      inherit pkgs;
      linkRoot = image.rootTree;
    };
    finch-frameworks = let
      paths = map (name: recipe "finch/${name}/build.nix") [
        "Accounts" "CloudKit" "CoreBluetooth" "CoreLocation" "CoreWLAN"
        "CryptoTokenKit" "LocalAuthentication" "OpenDirectory" "StoreKit"
        "UserNotifications" "CFNetwork"
      ];
    in pkgs.runCommand "siliconforest-finch-frameworks" { } ''
      mkdir -p "$out"
      for layer in ${pkgs.lib.concatStringsSep " " paths}; do
        cp -RP "$layer"/. "$out/"
        chmod -R u+w "$out"
      done
    '';
    vulkan-system = rootLayout "graphics" (recipe "m1-vulkan/system.nix") "/root";
    mesa-libdrm = recipe "m1-mesa-asahi/agx-offscreen-test.nix";
    netd = recipe "m1-bwfm/netd/build-pd-netd.nix";
    mdnsd-quiet = recipe "m1-bwfm/netd/build-mdnsd-quiet.nix";
    wifipm = recipe "m1-bwfm/tools/build-pd-wifipm.nix";
    sf-backlight = recipe "m1-dcp/dcp-flip-test.nix";
    sysaudio = (recipe "m1-sound/sysaudio/build-sysaudio.nix").all;
    sfplay = recipe "m1-sound/build-sfplay.nix";
    audiotoolbox = import ./audio-family.nix {
      inherit pkgs;
      family = recipe "finch/AudioToolbox/install.nix";
      provider = recipe "finch/AudioToolbox/units/build.nix";
    };
    coremedia = recipe "finch/CoreMedia/build.nix";
    videotoolbox = recipe "finch/VideoToolbox/encoder/build.nix";
    avfaudio = recipe "finch/AVFAudio/engine/realtime.nix";
    avfoundation = recipe "finch/media/bottle/avfoundation.nix";
    colorsync = recipe "finch/ColorSync/build.nix";
    accelerate = recipe "finch/Accelerate/installed-graphics.nix";
    coreimage = recipe "finch/media/bottle/coreimage.nix";
    metal = recipe "finch/Metal/build.nix";
    firefox-sandbox = recipe "firefox/sandbox.nix" { };
    firefox-io = recipe "firefox/io-policy.nix";
    firefox-avfoundation = recipe "firefox/avfoundation.nix";
    firefox-surface = recipe "firefox/surface-session-build.nix" { gpuBacking = true; nv12Backing = true; };
    firefox-clocked-providers = recipe "finch/firefox-media/clocked-providers.nix";
    firefox-clock-family = recipe "finch/firefox-media/clock-family.nix";
    # The release runtime's three override inputs expose Frameworks at their root.
    # Keep the provider's installed-system layout unchanged for its other callers.
    firefox-sc-network = pkgs.runCommand "siliconforest-firefox-network-override" { } ''
      mkdir -p "$out"
      cp -R --no-preserve=ownership ${recipe "firefox/sc-network.nix"}/System/Library/Frameworks "$out/Frameworks"
    '';
    firefox-runtime = import ./image/firefox-runtime.nix {
      inherit pkgs;
      overrides = {
        "network-v1" = pieces.firefox-sc-network;
        "audio-clock-v1" = pieces.firefox-clock-family;
        "video-clock-0172-v1" = pieces.firefox-clocked-providers;
      };
    };
    system-tools = recipe "m1-storage/build-system-tools.nix";
    rename-commit = recipe "m1-storage/build-sf-rename-commit.nix";
    openssh = recipe "m1-storage/userland/build-openssh.nix";
    ffmpeg-x264 = recipe "desktop/recording/build-ffmpeg-x264.nix";
    # Match the installed hardware-decoder/GL variant and its local-bin layout.
    sfvideo = pkgs.runCommand "siliconforest-sfvideo-release" { } ''
      src=${recipe "m1-avd/build-sfvideo-sfavd.nix" { gl = true; }}
      mkdir -p "$out/usr/local/bin" "$out/usr/local/lib"
      cp "$src/usr/bin/sfvideo-gl" "$out/usr/local/bin/"
      cp -R "$src/usr/local/lib/mesa-asahi-wl" "$out/usr/local/lib/"
    '';
  };
  image = import ./image.nix {
    inherit pkgs pieces version;
    base = p.image-arm64-virt-minimal-release;
    qemuBase = recipe "qemu-dev/build-image.nix" { };
    kernel = recipe "m1-kernel50/build-kc.nix";
    boot = {
      stage1 = "${boot.stage1}/sf-stage1.bin";
      stage2 = "${releaseBoot.stage2}/boot.bin";
    };
  };
in {
  inherit pieces desktop image;
  packages = pieces // {
    source-manifest = pkgs.writeText "siliconforest-sources.json"
      (if pkgs.stdenv.buildPlatform.system == "x86_64-linux" then x86SourceManifest else sourceManifest);
    base-source = base.renamed;
    base-build-source = base.buildSource;
    rust-toolchain = desktop.rust;
    m1-kernel = recipe "m1-kernel50/build-kc.nix";
    boot-stage1 = boot.stage1;
    boot-stage2 = boot.stage2;
    boot-stage2-template = templateBoot.stage2;
    boot-stage2-release = releaseBoot.stage2;
    root-tree = image.rootTree;
    root-image = image.rootfs;
    bootfiles = image.bootfiles;
    release = image.release;
    qemu-reference-image = image.qemu;
    qemu-image = import ./qemu-image.nix { inherit pkgs; disk = image.qemu; };
    qemu-proof-image = import ./qemu-image.nix { inherit pkgs; disk = image.qemu; proof = true; };
    default = image.release;
    # x86_64-linux keeps the recipe's own source, ../rebase/pd.nix, and with it the SF_PD check
    qemu-base = recipe "qemu-dev/build-image.nix"
      (if pkgs.stdenv.hostPlatform.system == "aarch64-linux" then { source = base; } else { });
    qemu-runner = import ./qemu-runner.nix { inherit pkgs; };
    qemu-smoke-image = import ./qemu-smoke.nix { inherit base; };
    root-base = p.image-arm64-virt-minimal-release;
  };
}
