# SPDX-License-Identifier: MIT OR Apache-2.0
let e = import ../environment.nix; candidate = import ./corespotlight-attributes.nix;
in e.pkgs.runCommand "siliconforest-preview-corespotlight-attributes-static-check" {
  nativeBuildInputs = [ e.pkgs.python3 ];
} ''
  mkdir -p $out
  python3 ${./check-recap.py} --root ${candidate} --macho ${../../homebrew} \
    --framework CoreSpotlight --framework-area Frameworks --probe corespotlight-attributes-probe --current 2418.4.13 \
    --class CSSearchableItemAttributeSet --class CSCustomAttributeKey \
    --under ${e.libsystem} --under ${e.p.libobjc-arm64} --under ${e.p.foundation-arm64} \
    --under ${e.p.coreFoundation-arm64} >$out/report.json || { cat $out/report.json; exit 1; }
  cat $out/report.json
''
