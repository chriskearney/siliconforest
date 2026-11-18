# SPDX-License-Identifier: MIT
# Copyright (c) 2026 SiliconForest contributors
{ base ? import ./base.nix }:
let
  inherit (base) pkgs;
  sf = ../integrations/siliconforest;
  p = base.pd.packages.x86_64-linux;
  desktop = import ./desktop.nix { inherit base; };
  boot = import ./boot-stages.nix { inherit base; };
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
    vulkan-system = rootLayout "graphics" (recipe "m1-vulkan/system.nix") "/root";
    mesa-libdrm = recipe "m1-mesa-asahi/agx-offscreen-test.nix";
    netd = recipe "m1-bwfm/netd/build-pd-netd.nix";
    mdnsd-quiet = recipe "m1-bwfm/netd/build-mdnsd-quiet.nix";
    wifipm = recipe "m1-bwfm/tools/build-pd-wifipm.nix";
    sf-backlight = recipe "m1-dcp/dcp-flip-test.nix";
    sysaudio = (recipe "m1-sound/sysaudio/build-sysaudio.nix").all;
    sfplay = recipe "m1-sound/build-sfplay.nix";
    audiotoolbox = recipe "finch/AudioToolbox/install.nix";
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
    firefox-sc-network = recipe "firefox/sc-network.nix";
    system-tools = recipe "m1-storage/build-system-tools.nix";
    rename-commit = recipe "m1-storage/build-sf-rename-commit.nix";
    openssh = recipe "m1-storage/userland/build-openssh.nix";
    ffmpeg-x264 = recipe "desktop/recording/build-ffmpeg-x264.nix";
    sfvideo = recipe "m1-avd/player/build-sfvideo.nix";
  };
in {
  inherit pieces desktop;
  packages = pieces // {
    source-manifest = pkgs.writeText "siliconforest-sources.json" (builtins.readFile ../sources.lock);
    base-source = base.renamed;
    rust-toolchain = desktop.rust;
    m1-kernel = recipe "m1-kernel50/build-kc.nix";
    boot-stage1 = boot.stage1;
    boot-stage2 = boot.stage2;
    boot-stage2-template = templateBoot.stage2;
    qemu-base = recipe "qemu-dev/build-image.nix" { };
    root-base = p.image-arm64-virt-minimal-release;
  };
}
