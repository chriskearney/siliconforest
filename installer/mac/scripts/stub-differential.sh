#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
#
# SFStub differential test (ENGINE.md section 10, M1): builds the stub content with the pinned Asahi
# v0.9.2 code (reference oracle) and with SFStub, each on its own APFS container of 2,499,805,184 bytes
# inside a sparse disk image under installer/mac/.build-images, from the same 13.5 (22G74) restore image,
# then compares the four volumes' trees and the command sequences.
#
# TEST MACHINES ONLY (the M5 or the i9-hosted Macs). Disk images only: every diskutil target is proved to
# be an image (hdiutil info, then diskutil) before it is touched. No bless, bputil, kmutil, nvram, asr.
# Needs passwordless sudo for the two builds (upstream ran as root; the helper will too) and network
# access to Apple's CDN (about 690 MB per build; SFStub's stage is cached in $WORK).
#
#   SF_ASAHI_REF   pinned checkout (default ~/sf-payload-work/ref/asahi-installer, must be dffbb38e)
#   SF_STUB_OUT    output directory (default ~/sf-payload-work/stubdiff/<run>)
#   SF_KEEP=1      leave the images attached
#   SF_ORACLE_FROM reuse the oracle side (oracle.json, oracle.ops, oracle-tree.json) of an earlier run's output
set -euo pipefail
cd "$(dirname "$0")/.."
MAC="$(pwd)"
ASAHI="${SF_ASAHI_REF:-$HOME/sf-payload-work/ref/asahi-installer}"
PROFILE="$MAC/../profiles/J313.json"
IMAGES="$MAC/.build-images"
RUNID="stubdiff-$(date +%Y%m%d-%H%M%S)"
RUN="$IMAGES/$RUNID"
OUT="${SF_STUB_OUT:-$HOME/sf-payload-work/stubdiff/$RUNID}"
WORK="${SF_STUB_WORK:-$HOME/sf-payload-work/sfstub-stage}"
DIFF="$MAC/Tests/StubDifferential"
STUB_BYTES=$(python3 -c "import json;print(json.load(open('$PROFILE'))['stub']['partition_bytes'])")
mkdir -p "$RUN" "$OUT" "$WORK"
sudo -n true || { echo "needs passwordless sudo (test machine only)" >&2; exit 2; }
[ "$(git -C "$ASAHI" rev-parse HEAD)" = dffbb38ef0c00c0431c609ecd8a00f42deb5b24c ] || { echo "Asahi reference is not v0.9.2 dffbb38e" >&2; exit 2; }
unset SF_REAL_DISK_WRITES SF_ALLOW_REAL_DISK_WRITES || true

swift build -c release --product sfstubctl
BIN="$(swift build -c release --show-bin-path)/sfstubctl"

# Inputs both builders get. Synthetic: no Apple or Asahi artwork, no real user.
python3 - "$OUT" <<'PY'
import hashlib, sys, os
out = sys.argv[1]
def blob(seed, n):
    b = b""; i = 0
    while len(b) < n:
        b += hashlib.sha256(f"{seed}{i}".encode()).digest(); i += 1
    return b[:n]
open(os.path.join(out, "test-volume-icon.icns"), "wb").write(b"icns" + (4104).to_bytes(4, "big") + blob("icon", 4096))
open(os.path.join(out, "test-stage1.bin"), "wb").write(blob("stage1-placeholder", 262144))
PY
ADMIN="$DIFF/fixtures/AdminUserRecoveryInfo.plist"
VARS=(--var "chosen.asahi,efi-system-partition=00000000-5f00-4000-8000-000000000001"
      --var "chainload=00000000-5f00-4000-8000-000000000001;sf/boot.bin")
cleanup() {
  [ "${SF_KEEP:-0}" = 1 ] && return
  for i in oracle sfstub; do [ -e "$RUN/$i.sparseimage" ] && "$BIN" detach --path "$RUN/$i.sparseimage" --images-root "$IMAGES" >/dev/null 2>&1 || true; done
}
trap cleanup EXIT
store() { python3 -c 'import json,sys;print(json.load(sys.stdin)["store"])'; }

if [ -n "${SF_ORACLE_FROM:-}" ]; then
  echo "== A: reusing the oracle from $SF_ORACLE_FROM"
  cp "$SF_ORACLE_FROM"/oracle.json "$SF_ORACLE_FROM"/oracle.ops "$SF_ORACLE_FROM"/oracle-tree.json "$OUT/"
  cp "$SF_ORACLE_FROM"/test-volume-icon.icns "$SF_ORACLE_FROM"/test-stage1.bin "$OUT/"
else
echo "== A: Asahi v0.9.2 oracle"
STORE_A=$("$BIN" make-image --path "$RUN/oracle.sparseimage" --label SiliconForest --bytes "$STUB_BYTES" --images-root "$IMAGES" | store)
sudo -n /usr/bin/env python3 "$DIFF/asahi_oracle.py" --asahi "$ASAHI" --profile "$PROFILE" --store "$STORE_A" --images-root "$IMAGES" \
  --admin-users "$ADMIN" --icon "$OUT/test-volume-icon.icns" --stage1 "$OUT/test-stage1.bin" "${VARS[@]}" \
  --ops "$OUT/oracle.ops" --out "$OUT/oracle.json" > "$OUT/oracle.log" 2>&1 || { tail -30 "$OUT/oracle.log"; exit 1; }
sudo -n /usr/bin/env python3 "$DIFF/stubtree.py" dump --info "$OUT/oracle.json" --store "$STORE_A" --out "$OUT/oracle-tree.json"
[ "${SF_KEEP:-0}" = 1 ] || "$BIN" detach --path "$RUN/oracle.sparseimage" --images-root "$IMAGES"
fi

echo "== B: SFStub"
STORE_B=$("$BIN" make-image --path "$RUN/sfstub.sparseimage" --label SiliconForest --bytes "$STUB_BYTES" --images-root "$IMAGES" | store)
APP="$ASAHI/src/step2/Finish Installation.app"
sudo -n "$BIN" build --profile "$PROFILE" --work "$WORK" --store "$STORE_B" --label SiliconForest --images-root "$IMAGES" \
  --admin-users "$ADMIN" --icon "$OUT/test-volume-icon.icns" --app "$APP" --app-name "Finish Installation.app" \
  --script-path Contents/Resources/step2.sh --script "$ASAHI/src/step2/step2.sh" \
  --token "##DISTRO##=literal:Asahi Linux" --token "##VGID##=vgid" --token "##PREBOOT##=preboot" \
  --physical-media "$ASAHI/src/step2/IAPhysicalMedia.plist" \
  --boot-object-path Contents/Resources/boot.bin --stage1 "$OUT/test-stage1.bin" "${VARS[@]}" \
  --ops "$OUT/sfstub.ops" --out "$OUT/sfstub.json" > "$OUT/sfstub.log" 2>&1 || { tail -30 "$OUT/sfstub.log"; exit 1; }
sudo -n /usr/bin/env python3 "$DIFF/stubtree.py" dump --info "$OUT/sfstub.json" --store "$STORE_B" --out "$OUT/sfstub-tree.json"

echo "== compare"
rc=0
python3 "$DIFF/stubtree.py" compare "$OUT/oracle-tree.json" "$OUT/sfstub-tree.json" --report "$OUT/report.txt" || rc=1
python3 "$DIFF/stubtree.py" ops "$OUT/oracle.ops" "$OUT/oracle.json" "$OUT/sfstub.ops" "$OUT/sfstub.json" \
  --fixture "$DIFF/fixtures/asahi-v0.9.2-commands.txt" | tee -a "$OUT/report.txt" || rc=1
echo "output: $OUT"
exit $rc
