# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
#
# Static checks on the build machine that every name in additions/symbols.json is exported where QuickTime
# Player binds it from, in the three arrangements:
#   full        additions.nix { movedInFrameworks = false; } and the staged AVKit: all 112 (the M1 as installed
#               on 18 November 2026, without the patched frameworks)
#   shrunk      additions.nix (the default) and the staged AVKit: the names the prefix still supplies
#   frameworks  the frameworks with the Cocoa patches 0340-0347 and 0364 and the framework wrappers: the names that moved
# The libraries are checked by themselves, without the system images they stand in front of. This predicts
# dyld's binding verdict for these names; it runs nothing.
let
 e=import ../environment.nix;
 full=import ./additions.nix { movedInFrameworks = false; };
 shrunk=import ./additions.nix {};
 avkit=import ../AVKit/build.nix;
 cocoa=import ../../cocoa/patched.nix;
 compat=import ../../terminal-app/build-compat.nix;
 sysaudio=(import ../../m1-sound/sysaudio/build-sysaudio.nix).audiotoolbox;
 F="System/Library/Frameworks";
 place=additions: tree: ''
  python3 - <<'PLACE'
import json, os, shutil
for entry in json.load(open("${additions}/additions/manifest.json")):
    target = "${tree}" + entry["load_path"]
    os.makedirs(os.path.dirname(target), exist_ok=True)
    shutil.copyfile("${additions}/additions/" + entry["name"], target)
PLACE
  mkdir -p ${tree}/${F}/AVKit.framework/Versions/A
  cp ${avkit}/${F}/AVKit.framework/Versions/A/AVKit ${tree}/${F}/AVKit.framework/Versions/A/
 '';
 check=tree: provided: report: ''
  python3 ${./loader/check_exports.py} --imports ${./additions/symbols.json} --root ${tree} --macho ${../../homebrew} ${provided} > ${report} || { cat ${report}; exit 1; }
  cat ${report}
 '';
in e.pkgs.runCommand "siliconforest-quicktime-additions-check" { nativeBuildInputs=[e.pkgs.python3]; } ''
 ${place full "full"}
 ${check "full" "" "full.txt"}
 ${place shrunk "shrunk"}
 ${check "shrunk" "--provided additions" "shrunk.txt"}
 # the frameworks as the system will have them: AppKit reached through Versions/C as on the root
 T=frameworks
 mkdir -p $T/${F}/AppKit.framework/Versions/A $T/${F}/QuartzCore.framework/Versions/A $T/${F}/CoreGraphics.framework/Versions/A \
   $T/${F}/CoreAudio.framework/Versions/A $T/${F}/CoreFoundation.framework/Versions/A $T/${F}/Foundation.framework/Versions/C
 cp ${cocoa.appkit}/${F}/AppKit.framework/Versions/A/AppKit $T/${F}/AppKit.framework/Versions/A/
 ln -s A $T/${F}/AppKit.framework/Versions/C
 cp ${cocoa.quartzcore}/${F}/QuartzCore.framework/Versions/A/QuartzCore $T/${F}/QuartzCore.framework/Versions/A/
 cp ${cocoa.coregraphics}/${F}/CoreGraphics.framework/Versions/A/CoreGraphics $T/${F}/CoreGraphics.framework/Versions/A/
 cp ${sysaudio}/${F}/CoreAudio.framework/Versions/A/CoreAudio $T/${F}/CoreAudio.framework/Versions/A/
 cp -L ${compat}/${F}/CoreFoundation.framework/Versions/A/CoreFoundation $T/${F}/CoreFoundation.framework/Versions/A/
 cp -L ${compat}/${F}/Foundation.framework/Versions/C/Foundation $T/${F}/Foundation.framework/Versions/C/
 ${check "frameworks" "--provided frameworks" "frameworks.txt"}
 mkdir -p $out; cp full.txt shrunk.txt frameworks.txt $out/
''
