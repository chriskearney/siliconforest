#!/bin/bash
# SPDX-License-Identifier: MIT
# Links SFAppleAVE into an installed desktop collection and packs the pair for sf-bootbin-install.sh.
# The default collection (rebase/build-kc.nix) has no room for it: with this kext its prelink info
# runs into the kernel's text. This keeps the installed collection's stripped members instead.
#   pack-collection.sh <kc phase script> <installed kernel.bin> <installed boot.bin> <new empty directory>
# <kc phase script>: the kc-builder command of the installed collection, with one -kext line
# naming a SFAppleAVE.kext. The boot arguments and the rest of the configuration are kept byte for byte.
# Writes kernel, kernel.bin, boot.bin and hashes.txt. Refuses a collection whose segments overlap.
set -euo pipefail
PHASE=$(readlink -f "${1:?kc phase script}"); OLD=$(readlink -f "${2:?installed kernel.bin}")
BOOT=$(readlink -f "${3:?installed boot.bin}"); OUT=${4:?new empty directory}
HERE=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd); SF=$(cd "$HERE/.." && pwd)
export PATH=$HOME/.nix-profile/bin:$PATH
[ ! -e "$OUT" ] || [ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 2; }
mkdir -p "$OUT/kext" "$OUT/tmp"; OUT=$(cd "$OUT" && pwd)
[ "$(grep -c '/SFAppleAVE\.kext"' "$PHASE")" = 1 ] || { echo "$PHASE: not exactly one SFAppleAVE -kext line" >&2; exit 2; }

built=$(nix-build --extra-experimental-features nix-command --extra-experimental-features flakes \
  --no-out-link "$HERE/build-kext.nix")
cp -rL "$built/System/Library/Extensions/SFAppleAVE.kext" "$OUT/kext/"
chmod -R u+w "$OUT/kext"
llvm-strip -S -x "$OUT/kext/SFAppleAVE.kext/Contents/MacOS/SFAppleAVE"

sed -E "s#-kext \"[^\"]*/SFAppleAVE\.kext\"#-kext \"$OUT/kext/SFAppleAVE.kext\"#" "$PHASE" > "$OUT/kc.sh"
(cd "$OUT" && TMPDIR="$OUT/tmp" bash kc.sh > kc.log 2>&1) || { tail -20 "$OUT/kc.log" >&2; exit 1; }
python3 "$SF/m1-rust-kext/tools/kc_overlap.py" "$OUT/kernel"

python3 -B - "$OLD" "$OUT/kernel" "$OUT/kernel.bin" "$SF/m1-native-boot/b1" <<'PY'
import gzip, pathlib, sys
sys.path.insert(0, sys.argv[4])
from pdsf_pack import parse, records, F_GZIP, CONFIG
old = pathlib.Path(sys.argv[1]).read_bytes()
found, end = parse(old, 0)
assert end == len(old), 'trailing bytes in the installed kernel.bin'
config = None
for kind, flags, stored, raw, ok, off in found:
    assert ok, 'bad record checksum'
    if kind == CONFIG:
        body = old[off:off + stored]
        config = gzip.decompress(body) if flags & F_GZIP else body
assert config is not None, 'no configuration record'
args = config.decode('ascii').split('bootargs=', 1)[1].split('\n', 1)[0].split()
assert not any(a == 'sfave' or a.startswith('sfave=') for a in args), 'boot arguments set sfave'
kernel = pathlib.Path(sys.argv[2]).read_bytes()
assert b'org.siliconforest.driver.SFAppleAVE' in kernel, 'SFAppleAVE is not in the collection'
out = records(config, kernel)
assert parse(out, 0)[1] == len(out)
pathlib.Path(sys.argv[3]).write_bytes(out)
PY
cp "$BOOT" "$OUT/boot.bin"
(cd "$OUT" && sha256sum boot.bin kernel.bin kernel kext/SFAppleAVE.kext/Contents/MacOS/SFAppleAVE | tee hashes.txt)
