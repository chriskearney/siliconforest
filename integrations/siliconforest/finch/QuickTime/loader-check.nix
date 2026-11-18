# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
#
# Static check of loader.nix on the build machine: every symbol in loader/imports.json is
# exported by the library with that install name (through re-exports for an umbrella), and
# each library's own undefined symbols are found in the libraries it links. This predicts
# dyld's binding verdict for these six libraries; it does not run them.
let
 e=import ../environment.nix;
 runtime=import ../../terminal-app/build-swift-runtime.nix;
 a=import ../../cocoa/arm64.nix;
 loader=import ./loader.nix;
in e.pkgs.runCommand "siliconforest-quicktime-loader-check" { nativeBuildInputs=[e.pkgs.python3]; } ''
 python3 ${./loader/check_exports.py} --imports ${./loader/imports.json} --root ${loader} \
   --under ${runtime} --under ${e.libsystem} --under ${a.base.libobjc} --under ${a.base.foundation} --under ${a.base.corefoundation} \
   --macho ${../../homebrew} > report.txt
 cat report.txt
 mkdir -p $out;cp report.txt $out/
''
