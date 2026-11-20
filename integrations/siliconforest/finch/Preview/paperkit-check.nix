# SPDX-License-Identifier: MIT
let
  e = import ../environment.nix;
  paper = import ./paperkit.nix;
  foundation = import ./foundation-url.nix;
  baseline = import ../../terminal-app/build-swift-runtime.nix;
in e.pkgs.runCommand "siliconforest-preview-paperkit-static-check" {
  nativeBuildInputs = [ e.pkgs.python3 ];
} ''
  mkdir -p $out
  python3 ${./check-paperkit.py} --paper ${paper} --foundation ${foundation} \
    --baseline ${baseline}/usr/lib/swift/libswiftFoundation.dylib --macho ${../../homebrew} \
    >$out/report.json || { cat $out/report.json; exit 1; }
  cat $out/report.json
''
