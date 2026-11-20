# SPDX-License-Identifier: MIT OR Apache-2.0
let e=import ../environment.nix; a=import ../../cocoa/arm64.nix; q=import ./quicklook-reader.nix;
in e.pkgs.runCommand "siliconforest-preview-quicklook-reader-static-check" {
  nativeBuildInputs=[e.pkgs.python3];
} ''
  mkdir -p $out
  python3 ${./check-quicklook.py} --root ${q} --macho ${../../homebrew} \
    --under ${e.libsystem} --under ${a.base.libobjc} --under ${a.base.foundation} \
    --under ${a.base.corefoundation} --under ${a.appDeps.appkit} \
    --under ${a.appDeps.coregraphics} --under ${a.appDeps.onyx2d} \
    >$out/report.json || { cat $out/report.json; exit 1; }
''
