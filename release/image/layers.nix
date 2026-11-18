# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
#
# Where each build output goes in the SiliconForest root, in the order they are laid
# over the upstream base (a later layer replaces an earlier one's file at the same path).
# Each entry names a piece of release/packages.nix; `prefix` is where the output's own
# tree lands, `exclude` are shell patterns relative to the output, `optional` pieces may
# be absent from the set (the build then records them as missing in image.json), `only`
# keeps just the matching files, `piece` lets two entries take parts of one output.
#
# The order and the prefixes come from the installed M1 (read-only listing of
# 18 November 2026, classified file by file against the build outputs); see
# docs/release/IMAGE.md, "Where the layers come from".
let
  fx = "/usr/local/lib/siliconforest/firefox/160-system1";
  common = [ "nix-support/*" ];
  headers = [ "*.h" "*/Headers/*" "include/*" "usr/include/*" ];
in [
  # the Cocoa root first: the macOS-apps tree below replaces its core libraries
  # (not its demo applications, its own Terminal.app, keyboard data or the Finder/Dock/MenuBar
  # of upstream's desktop, which SiliconForest does not run)
  { name = "cocoa-root"; optional = true; exclude = common ++ [ "Applications/*" "System/Library/CoreServices/*"
      "usr/share/xkeyboard-config-2/*" "System/Library/Desktop Pictures/*" "usr/share/vulkan/*" ]; }
  { name = "macos-apps-root"; exclude = common; }
  { name = "system-perl"; exclude = common; optional = true; }
  { name = "foundation-networking"; exclude = common; optional = true; }
  { name = "homebrew-overlay"; exclude = common; }
  { name = "iosurface"; exclude = common ++ headers; }
  { name = "corevideo"; exclude = common ++ headers; }
  { name = "cgl"; prefix = "/System/Library"; only = [ "Frameworks/OpenGL.framework/Versions/A/OpenGL" ]; }
  { name = "cgl-dispatch"; piece = "cgl"; prefix = "/usr/local/lib/siliconforest/opengl/v1"; only = [ "lib/*" ]; }
  { name = "vulkan-system"; exclude = common ++ headers; }
  { name = "mesa-libdrm"; exclude = common ++ [ "bin/*" "share/*" ]; optional = true; }
  # Finch frameworks
  { name = "audiotoolbox"; exclude = common; }
  { name = "coremedia"; exclude = common; }
  { name = "videotoolbox"; exclude = common ++ [ "test-root/*" ]; }
  { name = "avfaudio"; exclude = common; }
  { name = "avfoundation"; exclude = common; }
  { name = "colorsync"; exclude = common; }
  { name = "accelerate"; exclude = common; }
  { name = "coreimage"; exclude = common; }
  { name = "metal"; exclude = common; }
  { name = "libcompression"; exclude = common; optional = true; }
  { name = "finch-frameworks"; exclude = common; optional = true; }
  # system services and tools
  { name = "netd"; exclude = common; }
  { name = "mdnsd-quiet"; exclude = common; }
  { name = "wifipm"; exclude = common; }
  { name = "sf-backlight"; exclude = common; }
  { name = "sysaudio"; exclude = common; }
  { name = "sfplay"; exclude = common; }
  { name = "system-tools"; exclude = common; }
  { name = "rename-commit"; exclude = common; optional = true; }
  { name = "openssh"; exclude = common; }
  { name = "ffmpeg-x264"; exclude = common ++ [ "include/*" "usr/include/*" ]; }
  { name = "sfvideo"; exclude = common; }
  # the desktop
  { name = "desktop"; exclude = common ++ [ "usr/bin/*.next" ]; }  # .next: the inject-capable test build
  { name = "terminal"; exclude = common; }
  # Firefox's runtime (everything but Mozilla's bundle, which is downloaded at first run)
  { name = "firefox-runtime"; prefix = fx; exclude = common ++ [ "original/*" ]; optional = true; }
  { name = "firefox-sandbox"; prefix = fx + "/sandbox"; exclude = common; }
  { name = "firefox-io"; prefix = fx + "/io"; exclude = common; }
  { name = "firefox-avfoundation"; prefix = fx + "/avfoundation"; exclude = common; }
  { name = "firefox-surface"; prefix = fx + "/surface"; exclude = common; }
  { name = "firefox-clocked-providers"; prefix = fx + "/overrides/video-shared-v1"; exclude = common; }
  { name = "firefox-clock-family"; prefix = fx + "/overrides/audio-clock-v1"; exclude = common; }
  { name = "firefox-sc-network"; prefix = fx + "/overrides/network-v1"; exclude = common; }
]
