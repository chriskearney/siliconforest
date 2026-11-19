# SPDX-License-Identifier: MIT OR Apache-2.0
{ uniformTypeIdentifiers, foundationURL ? import ./foundation-url.nix }:
let
  e = import ../environment.nix;
  a = import ../../cocoa/arm64.nix;
  runtime = import ../../terminal-app/build-swift-runtime.nix;
  candidate = import ./corespotlight.nix { inherit uniformTypeIdentifiers foundationURL; };
in e.pkgs.runCommand "siliconforest-preview-corespotlight-swift-static-check" {
  nativeBuildInputs = [ e.pkgs.python3 ];
} ''
  mkdir -p $out
  for probe in corespotlight-attributes-probe corespotlight-swift-probe; do
    python3 ${./check-recap.py} --root ${candidate} --macho ${../../homebrew} \
      --framework CoreSpotlight --framework-area Frameworks --probe "$probe" --current 2418.4.13 \
      --class CSSearchableItemAttributeSet --class CSCustomAttributeKey \
      --under ${e.libsystem} --under ${e.p.libobjc-arm64} --under ${e.p.foundation-arm64} \
      --under ${e.p.coreFoundation-arm64} --under ${runtime} --under ${foundationURL} \
      --under ${uniformTypeIdentifiers} --under ${a.appFrameworks} \
      >$out/$probe.json || { cat $out/$probe.json; exit 1; }
  done
''
