# SPDX-License-Identifier: MIT
# TERM9 (FX-025): Thai for every application: Noto Sans Thai (regular, bold) and Noto Serif Thai, unmodified official
# Noto data under the SIL Open Font License 1.1 (the licence file beside them), for /System/Library/Fonts.
let
  a = import ./arm64.nix;
  fetch = import ../../../release/fetch.nix { pkgs = a.pkgs; };
  sansRegular = fetch "noto-thai-sans-regular";
  sansBold = fetch "noto-thai-sans-bold";
  serifRegular = fetch "noto-thai-serif-regular";
  license = fetch "noto-thai-license";
in a.pkgs.runCommand "siliconforest-fonts-thai" { } ''
  d=$out/System/Library/Fonts/NotoThai
  mkdir -p $d
  cp ${sansRegular} $d/NotoSansThai-Regular.ttf
  cp ${sansBold} $d/NotoSansThai-Bold.ttf
  cp ${serifRegular} $d/NotoSerifThai-Regular.ttf
  cp ${license} $d/OFL.txt
''
