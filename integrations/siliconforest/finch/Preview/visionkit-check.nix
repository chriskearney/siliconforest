# SPDX-License-Identifier: MIT
let
  e = import ../environment.nix;
  visionkit = import ./visionkit.nix;
in e.pkgs.runCommand "siliconforest-preview-visionkit-static-check" {
  nativeBuildInputs = [ e.pkgs.python3 ];
} ''
  mkdir -p $out
  python3 ${./check-recap.py} --root ${visionkit} --macho ${../../homebrew} \
    --framework VisionKitCore --probe visionkit-probe --current 1.0 \
    --class VKCImageAnalysis --class VKCImageAnalyzer --class VKCImageAnalyzerRequest \
    --symbol _vk_cgImageRemoveBackgroundWithDownsizing \
    --under ${e.libsystem} --under ${e.p.libobjc-arm64} --under ${e.p.foundation-arm64} \
    --under ${e.p.coreFoundation-arm64} --under ${e.p.coregraphics-arm64} --under ${e.p.onyx2d-arm64} \
    >$out/report.json || { cat $out/report.json; exit 1; }
  cat $out/report.json
''
