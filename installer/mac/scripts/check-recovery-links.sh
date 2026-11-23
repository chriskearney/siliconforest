#!/bin/bash
# DESIGN §7.3: SFRecovery must run in macOS 13.5's recoveryOS, which has AppKit but no SwiftUI,
# Combine or CryptoKit. Fails if the binary links anything outside the allowed set. Swift overlays
# that are only weakly linked are allowed (absent in recoveryOS means nil, not a dyld failure).
#   scripts/check-recovery-links.sh [path/to/SFRecovery]
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="${1:-$(swift build --show-bin-path)/SFRecovery}"
[ -x "$BIN" ] || { echo "no SFRecovery at $BIN (swift build --product SFRecovery)" >&2; exit 2; }
allowed_frameworks="AppKit Foundation CoreGraphics CoreText QuartzCore IOKit Security"
# libswiftCore, Darwin, Dispatch, ObjectiveC, _Concurrency per §7.3, plus the overlays of allowed
# frameworks that AppKit pulls in strongly (CoreFoundation, CoreGraphics). Spike S3 confirms these
# exist in the 13.5 recoveryOS.
allowed_swift="libswiftCore libswiftDarwin libswiftDispatch libswiftObjectiveC libswift_Concurrency libswiftCoreFoundation libswiftCoreGraphics"
forbidden="SwiftUI Combine CryptoKit libswiftSwiftUI libswiftCombine libswiftCryptoKit"
fail=0
while read -r line; do
  path="$(echo "$line" | awk '{print $1}')"
  weak=0; if [[ "$line" == *", weak)"* ]]; then weak=1; fi
  name="$(basename "$path" .dylib)"
  for f in $forbidden; do if [[ "$path" == *"/$f"* ]]; then echo "✗ forbidden: $path"; fail=1; fi; done
  case "$path" in
    /usr/lib/libSystem.B.dylib|/usr/lib/libobjc.A.dylib) ;;
    /System/Library/Frameworks/*)
      fw="$(echo "$path" | sed -E 's#/System/Library/Frameworks/([^.]+)\.framework.*#\1#')"
      if [[ " $allowed_frameworks " != *" $fw "* ]]; then echo "✗ framework not allowed in recoveryOS: $fw"; fail=1; fi ;;
    /usr/lib/swift/*)
      if [[ " $allowed_swift " != *" $name "* ]] && [ "$weak" -eq 0 ]; then echo "✗ strong Swift overlay not allowed: $name"; fail=1; fi ;;
    *) echo "✗ unexpected library: $path"; fail=1 ;;
  esac
done < <(otool -L "$BIN" | tail -n +2 | sed 's/^[[:space:]]*//')
minos="$(otool -l "$BIN" | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/&&!m{print $2; m=1}')"
if [ "$(printf '%s\n' "$minos" 13.5 | sort -V | head -1)" != "$minos" ] && [ "$minos" != "13.5" ]; then
  echo "✗ deployment target $minos is newer than recoveryOS 13.5"; fail=1
fi
if [ "$fail" -eq 0 ]; then echo "✓ SFRecovery links only what recoveryOS 13.5 allows (minos $minos)"; fi
exit "$fail"
