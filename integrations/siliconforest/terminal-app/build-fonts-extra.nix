# SPDX-License-Identifier: MIT
# Open fonts for the characters the root's fonts (Inter, Source Code Pro, URW base35, DejaVu Sans)
# have no glyphs for, found by CoreText's fallback through fontconfig (its directories include
# /System/Library/Fonts):
#   NotoSansMonoCJK/NotoSansMonoCJK-VF.otf.ttc   Noto Sans Mono CJK 2.004 (Chinese, Japanese,
#                                                Korean; full-width ideographs, half-width Latin)
#   NotoEmoji/NotoEmoji.ttf                      Noto Emoji 3.000, the monochrome outlines: Noto
#                                                Color Emoji is colour bitmaps (CBDT), which the
#                                                drawing path here does not draw
# Both SIL Open Font License 1.1; the licence text goes beside each font.
#
#   nix-build --extra-experimental-features 'nix-command flakes' --no-out-link build-fonts-extra.nix
let
  pd = (import ../rebase/pd.nix).pd;
  pkgs = pd.buildPkgs;
  cjk = pkgs.noto-fonts-cjk-sans;
  emoji = pkgs.noto-fonts-monochrome-emoji;
in pkgs.runCommand "siliconforest-fonts-extra" { } ''
  set -o pipefail
  F=$out/System/Library/Fonts
  mkdir -p $F/NotoSansMonoCJK $F/NotoEmoji
  cp ${cjk}/share/fonts/opentype/noto-cjk/NotoSansMonoCJK-VF.otf.ttc $F/NotoSansMonoCJK/
  cp ${emoji}/share/fonts/noto/NotoEmoji.ttf $F/NotoEmoji/
  cp ${cjk.src}/LICENSE $F/NotoSansMonoCJK/OFL.txt
  cp ${emoji.src}/ofl/notoemoji/OFL.txt $F/NotoEmoji/OFL.txt
  for d in NotoSansMonoCJK NotoEmoji; do
    [ -s $F/$d/OFL.txt ] || { echo "no licence text for $d" >&2; exit 1; }
  done
  chmod -R u+w $out
''
