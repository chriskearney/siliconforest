# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
#
# Firefox's runtime for the SiliconForest root, as a tree at installed paths:
#   usr/local/lib/siliconforest/firefox/160-system1/   the private providers, the three selected
#                                                      overrides and release.json
#   Applications/Firefox.app/Contents/MacOS/firefox-sf the launcher (firefox/daily-launch.py) and
#                                                      system-runtime.json naming the runtime
#   usr/share/applications/org.mozilla.firefox.desktop the desktop entry
# It is what firefox/prepare-install.py --system-layout and then install-system.py,
# install-system-ui.py, install-network-runtime.py, install-audio-runtime.py,
# install-video-clock.py, install-codec-policy.py and install-damage-path.py made on the owner's
# M1, without what does not belong in a release:
#   - Mozilla's bundle (Applications/Firefox.app/Contents/Resources/Mozilla.app) and the outer
#     bundle's Info.plist, which copies keys of Mozilla's: both arrive at install time
#     (sf_firefox_bundle.py, from the release Mozilla publishes, checked against mozilla_sha512);
#   - install receipts, build logs, ledgers, the maintenance-* rollback copies, owner-install
#     notes, the overrides that were tried and are not selected (glyph-generation, memory-font,
#     nv12, surface-lookup, video-shared, frame-id-diagnostic).
#
#   providers  name -> build output for the 13 providers. Default: built here from the recipes
#              release.json records, with the arguments it records.
#   overrides  { network-v1, audio-clock-v1, video-clock-0172-v1 } -> trees laid at overrides/<name>
#   selection  ./firefox-selection.json: the release.json values that are choices, not records
{ pkgs, tree ? ../../integrations/siliconforest, providers ? null, overrides, selection ? ./firefox-selection.json }:
let
  lib = pkgs.lib;
  fx = tree + "/firefox";
  target = "/usr/local/lib/siliconforest/firefox/160-system1";
  sel = removeAttrs (builtins.fromJSON (builtins.readFile selection)) [ "_comment" ];
  # the recipes of release.json "recipes", with its arguments (paths relative to firefox/)
  recipes = {
    gl = { file = "cgl-gpu.nix"; args = { prefix = "${target}/gl"; }; };
    sandbox = { file = "sandbox.nix"; args = { prefix = "${target}/sandbox"; coldAVDFirmware = true; fontDirectory = "${target}/fonts"; }; };
    appkit = { file = "appkit-ui.nix"; args = { menuGeometry = true; preciseScroll = true; gpuPresentation = true; pasteboardProvider = true; }; };
    onyx = { file = "onyx-font.nix"; };
    quartz = { file = "quartzcore.nix"; args = { gpuPresentation = true; releaseContextResources = true; coalesceNotifications = false; }; };
    surface = { file = "surface-gpu.nix"; };
    avfoundation = { file = "avfoundation.nix"; };
    compat = { file = "compat.nix"; args = { }; };
    io = { file = "io-policy.nix"; };
    open = { file = "open-url.nix"; };
    windowserver = { file = "windowserver-ui.nix"; };
    fonts = { file = "fontconfig.nix"; args = { prefix = "${target}/fonts"; }; };
    coretext = { file = "coretext.nix"; };
  };
  expr = r: "import ./${r.file}" + lib.optionalString (r ? args)
    (" {" + lib.concatStrings (lib.mapAttrsToList (k: v: "${k}=${builtins.toJSON v};") r.args) + "}");
  built = if providers != null then providers else
    lib.mapAttrs (_: r: let f = import (fx + "/${r.file}"); in if r ? args then f r.args else f) recipes;
  frameworksOnly = [ "appkit" "onyx" "coretext" ];
  release = pkgs.writeText "release.json" (builtins.toJSON (sel // {
    target = target;
    recipes = lib.mapAttrs (_: expr) recipes;
    builds = lib.mapAttrs (_: toString) built;
    provider_overrides = { };
    framework_aliases = { "AppKit.framework/Versions/C" = "A"; };
    original_bundle = "/Applications/Firefox.app/Contents/Resources/Mozilla.app";
    network_override = "${target}/overrides/network-v1/Frameworks";
    audio_override = "${target}/overrides/audio-clock-v1/Frameworks";
    video_override = "${target}/overrides/video-clock-0172-v1/Frameworks";
  }));
in
assert lib.assertMsg (builtins.attrNames built == builtins.attrNames recipes) "firefox-runtime: providers must be exactly ${toString (builtins.attrNames recipes)}";
assert lib.assertMsg (builtins.attrNames overrides == [ "audio-clock-v1" "network-v1" "video-clock-0172-v1" ]) "firefox-runtime: overrides must be the three selected ones";
pkgs.runCommand "siliconforest-firefox-runtime" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  set -euo pipefail
  r=$out${target}
  mkdir -p $r/overrides
  ${lib.concatStrings (lib.mapAttrsToList (name: src: if builtins.elem name frameworksOnly then ''
    mkdir -p $r/${name}
    cp -R --no-preserve=ownership ${src}/System/Library/Frameworks $r/${name}/Frameworks
  '' else ''
    cp -R --no-preserve=ownership ${src} $r/${name}
  '') built)}
  chmod -R u+w $r
  rm -rf $r/*/nix-support
  # Firefox loads AppKit as Versions/C, the provider builds Versions/A (prepare-install.py)
  v=$r/appkit/Frameworks/AppKit.framework/Versions
  [ -f $v/A/AppKit ] && [ ! -e $v/C ] && ln -s A $v/C
  ${lib.concatStrings (lib.mapAttrsToList (name: src: ''
    mkdir -p $r/overrides/${name}
    cp -R --no-preserve=ownership ${src}/Frameworks $r/overrides/${name}/Frameworks
  '') overrides)}
  chmod -R u+w $r/overrides
  for o in network-v1 audio-clock-v1 video-clock-0172-v1; do [ -d $r/overrides/$o/Frameworks ] || { echo "override $o has no Frameworks" >&2; exit 1; }; done
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); json.dump(d, open(sys.argv[2], "w"), indent=2); open(sys.argv[2], "a").write("\n")' ${release} $r/release.json
  # the outer bundle: the launcher and the runtime it serves (Info.plist and Mozilla.app at install time)
  m=$out/Applications/Firefox.app/Contents
  mkdir -p $m/MacOS $m/Resources
  cp ${fx}/daily-launch.py $m/MacOS/firefox-sf; chmod 755 $m/MacOS/firefox-sf
  printf '{"target": "%s"}\n' ${target} > $m/MacOS/system-runtime.json
  ln -s Mozilla.app/Contents/Resources/firefox.icns $m/Resources/firefox.icns
  mkdir -p $out/usr/share/applications
  sed 's|^TryExec=/Applications/Firefox.app/Contents/MacOS/firefox$|TryExec=/Applications/Firefox.app/Contents/MacOS/firefox-sf|' \
    ${fx}/org.mozilla.firefox.desktop > $out/usr/share/applications/org.mozilla.firefox.desktop
  grep -q 'firefox-sf$' $out/usr/share/applications/org.mozilla.firefox.desktop
''
