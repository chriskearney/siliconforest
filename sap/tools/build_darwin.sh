#!/bin/bash
# SPDX-License-Identifier: MIT
# Cross-build SAP (sap, sf), sf-bootslot and sf-mount-sfboot for SiliconForest (aarch64-apple-darwin) on the Linux
# build host, against the runtime chonkstep's link inputs name (the toolchain, linker, SDK and
# libSystem of the source ../../integrations/siliconforest/rebase/pd.nix selects).
#
#   sap/tools/build_darwin.sh OUT          -> OUT/sap, OUT/sf, OUT/sf-bootslot, OUT/sf-mount-sfboot, OUT/build.json
#   SAP_FEATURES=testing sap/tools/build_darwin.sh OUT   (test hooks; never for an image)
#   SAP_EXTRA_C="a.c b.c"   also build these one-file C programs (OUT/a, OUT/b; the guest tests' probes)
#   SAP_KC_BUILDER=1        also OUT/kc-builder: kc-tools' kc-builder (integrations/siliconforest/kc-builder,
#                           prepare_source.py; the flags of build-macos.sh) for SiliconForest itself, the
#                           relink tool SAP runs as /usr/libexec/sap/kc-builder (design Q5)
#
# Needs nix and a Rust toolchain with the aarch64-apple-darwin target (rustup target add).
set -euo pipefail
REPO=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
OUT=${1:?output directory}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
export PATH=$HOME/.nix-profile/bin:$HOME/.cargo/bin:$PATH
CD=$REPO/integrations/siliconforest/chonkstep-darwin
INPUTS=$(cd "$CD" && nix-build --extra-experimental-features 'nix-command flakes' --max-jobs 1 --cores 2 --no-out-link link-inputs.nix | tail -1)
[ -f "$INPUTS" ] || { echo "link-inputs.nix did not build" >&2; exit 2; }
install -m 644 "$INPUTS" "$OUT/link-inputs.json"
get() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$OUT/link-inputs.json" "$1"; }
export DARWIN_LINK_INPUTS=$OUT/link-inputs.json CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER=$CD/darwin-linker-inputs.py
(cd "$REPO/sap/client" && DARWIN_SDK_ROOT=$(get sdk) SDKROOT=$(get sdk) cargo build --quiet --locked --release --target aarch64-apple-darwin \
    --target-dir "$OUT/target" ${SAP_FEATURES:+--features "$SAP_FEATURES"})
for b in sap sf; do install -m 755 "$OUT/target/aarch64-apple-darwin/release/$b" "$OUT/$b"; done
# sf-bootslot: C, the same compiler and SDK, linked by the same driver
AB=$REPO/integrations/siliconforest/m1-native-boot/install/abboot
CC=$(get toolchain)/bin/arm64-apple-darwin20.4-clang
for c in sf_ab sf-bootslot; do
  DARWIN_SDK_ROOT=$(get sdk) SDKROOT=$(get sdk) "$CC" -std=c11 -Wall -Wextra -Werror -O2 -isystem "$(get sdk)/usr/include" -I "$AB" -c "$AB/$c.c" -o "$OUT/$c.o"
done
DARWIN_SDK_ROOT=$(get sdk) SDKROOT=$(get sdk) "$CC" -std=c11 -Wall -Wextra -Werror -O2 -isystem "$(get sdk)/usr/include" \
    -c "$REPO/sap/image/sf-mount-sfboot.c" -o "$OUT/sf-mount-sfboot.o"
"$CD/darwin-linker-inputs.py" -lSystem "$OUT/sf_ab.o" "$OUT/sf-bootslot.o" -o "$OUT/sf-bootslot"
"$CD/darwin-linker-inputs.py" -lSystem "$OUT/sf-mount-sfboot.o" -o "$OUT/sf-mount-sfboot"
for c in ${SAP_EXTRA_C:-}; do
  n=$(basename "$c" .c)
  DARWIN_SDK_ROOT=$(get sdk) SDKROOT=$(get sdk) "$CC" -std=c11 -Wall -Wextra -Werror -O2 -isystem "$(get sdk)/usr/include" -c "$c" -o "$OUT/$n.o"
  "$CD/darwin-linker-inputs.py" -lSystem "$OUT/$n.o" -o "$OUT/$n"
done
if [ "${SAP_KC_BUILDER:-0}" = 1 ]; then
  KCS=$(mktemp -d); python3 "$REPO/integrations/siliconforest/kc-builder/prepare_source.py" "$KCS/src" > /dev/null
  objs=()
  for c in src/kc_builder.c src/fileset.c src/auxkc.c lib/linker.c lib/macho_view.c lib/plist.c lib/prelink.c; do
    o="$OUT/kc-$(basename "$c" .c).o"
    (cd "$KCS/src" && DARWIN_SDK_ROOT=$(get sdk) SDKROOT=$(get sdk) "$CC" -std=gnu11 -O2 -Wall -Wno-unused-function -Wno-unused-variable \
      -Wno-pointer-bool-conversion -Iinclude -isystem "$(get sdk)/usr/include" -c "$c" -o "$o")
    objs+=("$o")
  done
  "$CD/darwin-linker-inputs.py" -lSystem "${objs[@]}" -o "$OUT/kc-builder"
  cp "$KCS/src/LICENSE" "$OUT/LICENSE.kc-tools"; rm -rf "$KCS"
fi
rm -f "$OUT"/*.o
python3 - "$OUT" "$REPO" <<'PY'
import hashlib, json, subprocess, sys
from pathlib import Path
out, repo = Path(sys.argv[1]), sys.argv[2]
rev = subprocess.run(['git', '-C', repo, 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip()
files = {n: {'bytes': (out / n).stat().st_size, 'sha256': hashlib.sha256((out / n).read_bytes()).hexdigest()}
         for n in ('sap', 'sf', 'sf-bootslot', 'sf-mount-sfboot')}
(out / 'build.json').write_text(json.dumps({'rev': rev, 'target': 'aarch64-apple-darwin', 'files': files,
                                            'link_inputs': json.loads((out / 'link-inputs.json').read_text())}, indent=1) + '\n')
print(json.dumps(files, indent=1))
PY
