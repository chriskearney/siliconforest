# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
#
# Static check of additions.nix and the staged AVKit on the build machine: every name in
# additions/symbols.json is exported by the library programs load from that path. The
# libraries are checked by themselves, without the system images they stand in front of.
# This predicts dyld's binding verdict for these names; it runs nothing.
let
 e=import ../environment.nix;
 additions=import ./additions.nix {};
 avkit=import ../AVKit/build.nix;
in e.pkgs.runCommand "siliconforest-quicktime-additions-check" { nativeBuildInputs=[e.pkgs.python3]; } ''
 python3 - <<'PLACE'
import json, os, shutil
for entry in json.load(open("${additions}/additions/manifest.json")):
    target = "tree" + entry["load_path"]
    os.makedirs(os.path.dirname(target), exist_ok=True)
    shutil.copyfile("${additions}/additions/" + entry["name"], target)
PLACE
 mkdir -p tree/System/Library/Frameworks/AVKit.framework/Versions/A
 cp ${avkit}/System/Library/Frameworks/AVKit.framework/Versions/A/AVKit tree/System/Library/Frameworks/AVKit.framework/Versions/A/
 python3 ${./loader/check_exports.py} --imports ${./additions/symbols.json} --root tree --macho ${../../homebrew} > report.txt || { cat report.txt; exit 1; }
 cat report.txt
 mkdir -p $out;cp report.txt $out/
''
