#!/bin/bash
# Fetches the installer's typefaces (VISUAL-DESIGN §4): Inter and Source Code Pro, both SIL OFL 1.1.
# Pinned by SHA-256; extracted into build/fonts (git-ignored), bundled by make-app.sh, and picked up by
# `swift run` and `--snapshot` from the source tree. Without them the app falls back to SF Pro / SF Mono.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="build/fonts"
CACHE="build/fonts-cache"
mkdir -p "$OUT" "$CACHE"

fetch() { # url sha256 file
  if [ ! -f "$CACHE/$3" ] || ! echo "$2  $CACHE/$3" | shasum -a 256 -c --status; then
    curl -fsSL -o "$CACHE/$3" "$1"
  fi
  echo "$2  $CACHE/$3" | shasum -a 256 -c --status || { echo "checksum mismatch: $3" >&2; exit 1; }
}

fetch "https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip" \
      9883fdd4a49d4fb66bd8177ba6625ef9a64aa45899767dde3d36aa425756b11e inter-4.1.zip
fetch "https://github.com/adobe-fonts/source-code-pro/releases/download/2.042R-u%2F1.062R-i%2F1.026R-vf/TTF-source-code-pro-2.042R-u_1.062R-i.zip" \
      0c85bac90d15c040b82939aa92bc8404420fccc02e37bbcb9c93a7f21abb52c6 source-code-pro-2.042.zip
# The TTF release zip carries no licence file; take LICENSE.md from the same release tag.
fetch "https://raw.githubusercontent.com/adobe-fonts/source-code-pro/2.042R-u%2F1.062R-i%2F1.026R-vf/LICENSE.md" \
      7c940e28a5388e9bba866cf0e408edda45fe0899ba98665b8f6ab31dc5e4b8ff source-code-pro-2.042-LICENSE.md

unzip -o -q -j "$CACHE/inter-4.1.zip" extras/ttf/Inter-Regular.ttf extras/ttf/Inter-Medium.ttf extras/ttf/Inter-SemiBold.ttf \
  extras/ttf/InterDisplay-SemiBold.ttf extras/ttf/InterDisplay-Medium.ttf -d "$OUT"
unzip -o -q -j "$CACHE/inter-4.1.zip" LICENSE.txt -d "$CACHE" && cp "$CACHE/LICENSE.txt" "$OUT/Inter-OFL.txt"
unzip -o -q -j "$CACHE/source-code-pro-2.042.zip" TTF/SourceCodePro-Regular.ttf TTF/SourceCodePro-Medium.ttf -d "$OUT"
cp "$CACHE/source-code-pro-2.042-LICENSE.md" "$OUT/SourceCodePro-OFL.txt"
cat > "$OUT/SOURCES.md" <<TXT
Inter 4.1 (https://github.com/rsms/inter, SIL OFL 1.1, see Inter-OFL.txt)
Source Code Pro 2.042 (https://github.com/adobe-fonts/source-code-pro, SIL OFL 1.1, see SourceCodePro-OFL.txt)
TXT
echo "✓ fonts in $OUT"
