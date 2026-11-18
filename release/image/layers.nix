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
  common = [ "nix-support/*" ];
  headers = [ "*.h" "*/Headers/*" "include/*" "usr/include/*" ];
in [
  # the Cocoa root first: the macOS-apps tree below replaces its core libraries
  # (not its demo applications, its own Terminal.app, keyboard data or the Finder/Dock/MenuBar
  # of upstream's desktop, which SiliconForest does not run)
  { name = "cocoa-root"; optional = true; exclude = common ++ [ "Applications/*" "System/Library/CoreServices/*"
      "usr/share/xkeyboard-config-2/*" "System/Library/Desktop Pictures/*" "usr/share/vulkan/*"
      # its own libbsm: the system keeps the base's, a link to libSystem
      "usr/lib/libbsm.dylib" "usr/lib/libbsm.0.dylib" ]; }
  { name = "macos-apps-root"; exclude = common ++ [ "usr/share/sf-test/*" ]; }  # (its test fixtures)
  { name = "system-perl"; exclude = common; optional = true; }
  # FoundationNetworking's CA bundle and licences (its libraries are in macos-apps-root)
  { name = "foundation-networking"; optional = true;
    only = [ "System/Library/Frameworks/Foundation.framework/Versions/A/Resources/*" ]; }
  # (not its libSystem: the system's is macos-apps-root's)
  { name = "homebrew-overlay"; exclude = common ++ [ "usr/lib/libSystem.B.dylib" "usr/lib/libhbcrash.dylib" ]; }
  { name = "iosurface"; exclude = common ++ headers; }
  { name = "corevideo"; exclude = common ++ headers; }
  { name = "cgl"; prefix = "/System/Library"; only = [ "Frameworks/OpenGL.framework/Versions/A/OpenGL" ]; }
  { name = "cgl-dispatch"; piece = "cgl"; prefix = "/usr/local/lib/siliconforest/opengl/v1"; only = [ "lib/*" ]; }
  { name = "vulkan-system"; exclude = common ++ headers; }
  # only libdrm of this Mesa bundle: the GL libraries are vulkan-system's
  { name = "mesa-libdrm"; only = [ "usr/local/lib/mesa-asahi/libdrm.2.dylib" ]; optional = true; }
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
  # The Finch family owns AudioToolbox; sysaudio supplies CoreAudio/AudioUnit.
  { name = "sysaudio"; exclude = common ++ [ "System/Library/Frameworks/AudioToolbox.framework/*" ]; }
  { name = "sfplay"; exclude = common; }
  { name = "system-tools"; exclude = common; }
  { name = "rename-commit"; exclude = common; optional = true; }
  { name = "openssh"; exclude = common; }
  { name = "ffmpeg-x264"; exclude = common ++ [ "include/*" "usr/include/*" ]; }
  { name = "sfvideo"; exclude = common; }
  # the Thai fonts (cocoa/fonts-thai.nix: Noto, OFL-1.1)
  { name = "fonts-thai"; exclude = common; optional = true; }
  # /opt/homebrew (./homebrew.nix: the system's bottles, pinned, poured; the brew client)
  { name = "homebrew"; exclude = common; }
  # Activity Monitor's support libraries and tools (./activity-monitor.nix); built against the
  # root assembled from the layers before it ("late": the libraries link to the root's own)
  { name = "activity-monitor"; exclude = common; late = true; }
  # the desktop
  # the compositor and the dock (not .next, the inject-capable test build), then the terminal alone
  { name = "desktop"; exclude = common ++ [ "usr/bin/*.next" "usr/bin/chonk-terminal-darwin" ]; }
  { name = "terminal"; only = [ "usr/bin/chonk-terminal-darwin" ]; }
  # Firefox's runtime, launcher and desktop entry (./firefox-runtime.nix, a tree at installed paths;
  # Mozilla's bundle arrives at install time)
  { name = "firefox-runtime"; exclude = common; }
]
