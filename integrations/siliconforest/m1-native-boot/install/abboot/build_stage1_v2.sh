#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
#
# build_stage1_v2.sh OUT    stage 1 v2: stage 1 v1 plus the A/B try-once slot choice (README.md here)
#
# NOT the installer's stage 1. installer/payload/boot/build_stage1.sh still builds v1 (44c1ef0b...)
# and the installer still ships it; nothing here changes that. v2 is v1's recipe (Omacom m1n1 at the
# profile's pin, patches/*.patch, RELEASE=1 CHAINLOADING=1 SF_INSTALLED=1, our logo) plus
# patches/stage1-v2/*.patch, sf_ab.[ch] and sf_ab_stage1.c from this directory, SF_AB_BOOT=1, and the
# version tag <pin>-siliconforest-stage1-v2. With the v1 toolchain (clang/ld.lld 22.1.8, rustc 1.98.1)
# it is byte-identical to STAGE1_V2_SHA256; another toolchain stops unless SF_NEW_STAGE1=1.
#
# Inputs (environment): SF_M1N1_SRC, SF_BOOT_LOGO, SF_CARGO_ONLINE, SF_NEW_STAGE1 as build_stage1.sh.
# Outputs: OUT/sf-stage1-v2.bin, OUT/sf-stage1-v2.json, OUT/sf-stage1-v2.log. Host only: no device is
# opened, nothing is installed or published, OUT is never committed.
set -euo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd); ROOT=$(cd "$HERE/../../../../.." && pwd)
PROFILE=$ROOT/installer/profiles/J313.json
PIN=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["boot"]["stage1"]["source_revision"])' "$PROFILE")
FOOTPRINT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["boot"]["stage1"]["max_stage2_span_bytes"])' "$PROFILE")
TAG="$PIN-siliconforest-stage1-v2"
STAGE1_V1_SHA256=44c1ef0bda96224f5fe8c6228cc12ec1966b7781f38844cea960b21b47654318
STAGE1_V2_SHA256=c4be30876d39f7416145e56f56b021bc96e54c3b35899be12658a4406421994d
PATCHES=$ROOT/integrations/siliconforest/m1-native-boot/install/patches
SRC=${SF_M1N1_SRC:-$ROOT/sources/m1n1-baseline}
LOGO=${SF_BOOT_LOGO:-$ROOT/integrations/siliconforest/branding/siliconforest-boot.svg}
OUT=$(mkdir -p "${1:?usage: build_stage1_v2.sh OUT}" && cd "$1" && pwd)
die() { echo "build_stage1_v2: $*" >&2; exit 2; }

[ "$(git -C "$SRC" rev-parse HEAD)" = "$PIN" ] || die "$SRC is not m1n1 at $PIN"
[ -z "$(git -C "$SRC" status --porcelain --untracked-files=no)" ] || die "$SRC has local changes"
[ -f "$LOGO" ] || die "logo $LOGO missing"
ls "$PATCHES"/*.patch "$PATCHES"/stage1-v2/*.patch >/dev/null || die "patches missing in $PATCHES"
for t in clang ld.lld rustc cargo make rsvg-convert magick; do command -v $t >/dev/null || die "$t missing"; done
[ -d "$(rustc --print sysroot)/lib/rustlib/aarch64-unknown-none-softfloat" ] ||
  die "rustc $(rustc --version | cut -d' ' -f2) has no aarch64-unknown-none-softfloat target"
NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu)
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

for s in 128 256; do
  case "$LOGO" in *.svg) rsvg-convert -w $s -h $s "$LOGO" -o "$WORK/boot_$s.png";; *) magick "$LOGO" -resize "${s}x$s" "$WORK/boot_$s.png";; esac
  magick "$WORK/boot_$s.png" -background black -flatten -depth 8 "rgba:$WORK/siliconforest_$s.bin"
  [ "$(wc -c < "$WORK/siliconforest_$s.bin")" -eq $((s * s * 4)) ] || die "logo $s: wrong size"
done

W=$WORK/m1n1; cp -a "$SRC" "$W"
(
  cd "$W"
  if [ -d build ]; then
    find build -maxdepth 1 -type f -delete
    rm -rf build/.deps build/chickens build/dcp build/hv build/math build/tinf build/minilzlib build/dlmalloc build/libfdt
  fi
  cargo="--locked --features chainload"; [ "${SF_CARGO_ONLINE:-0}" = 1 ] || cargo="$cargo --offline"
  for p in "$PATCHES"/*.patch "$PATCHES"/stage1-v2/*.patch; do git apply "$p"; done
  cp "$HERE/sf_ab.h" "$HERE/sf_ab.c" "$HERE/sf_ab_stage1.c" src/
  cp "$WORK/siliconforest_128.bin" "$WORK/siliconforest_256.bin" data/
  M1N1_VERSION_TAG=$TAG make -j"$NPROC" USE_CLANG=1 CARGO_FLAGS="$cargo" RELEASE=1 SF_INSTALLED=1 \
    BUILTIN_LOGO=siliconforest CHAINLOADING=1 SF_AB_BOOT=1 build/m1n1.bin > "$OUT/sf-stage1-v2.log" 2>&1 ||
    { tail -30 "$OUT/sf-stage1-v2.log" >&2; exit 1; }
  ! grep -n 'warning:' "$OUT/sf-stage1-v2.log" | grep 'utils.c\|main.c\|sf_ab\|chainload.c\|payload.c' || die "warnings in our sources"
  grep -a -q "##m1n1_ver##$TAG" build/m1n1.bin || die "the image does not carry its tag"
  grep -a -q 'SF_STOPPED' build/m1n1.bin || die "the image is not the installed variant"
  grep -a -q 'sf/bootstate.bin' build/m1n1.bin || die "the image has no A/B slot choice"
  for c in RELEASE SF_INSTALLED CHAINLOADING SF_AB_BOOT; do grep -q "^#define $c\$" build/build_cfg.h || die "build configuration lacks $c"; done
  ! grep -q '^#define SF_KERNEL_FILE$' build/build_cfg.h || die "stage 1 is built as a stage 2"
  cp build/m1n1.bin "$OUT/sf-stage1-v2.bin"
)
python3 "$ROOT/installer/payload/release/sfrelease.py" check-stage1 "$OUT/sf-stage1-v2.bin" --revision "$PIN" --footprint "$FOOTPRINT"

SHA=$( (sha256sum "$OUT/sf-stage1-v2.bin" 2>/dev/null || shasum -a 256 "$OUT/sf-stage1-v2.bin") | cut -d' ' -f1)
[ "$SHA" != "$STAGE1_V1_SHA256" ] || die "the v2 build is byte-identical to v1: SF_AB_BOOT did not take effect"
SAME=false; [ "$SHA" = "$STAGE1_V2_SHA256" ] && SAME=true
[ "$SAME" = true ] || [ "${SF_NEW_STAGE1:-0}" = 1 ] ||
  die "sf-stage1-v2.bin ($SHA) is not the recorded stage 1 v2 ($STAGE1_V2_SHA256); SF_NEW_STAGE1=1 accepts it"
python3 -B - "$OUT" "$PIN" "$TAG" "$SHA" "$SAME" "$PATCHES" "$HERE" <<'PY'
import hashlib, json, pathlib, platform, subprocess, sys
out, pin, tag, sha, same, patches, here = sys.argv[1:]
def ver(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True).stdout.splitlines()[0]
    except Exception:
        return None
p = pathlib.Path(patches)
rec = dict(file="sf-stage1-v2.bin", bytes=(pathlib.Path(out) / "sf-stage1-v2.bin").stat().st_size, sha256=sha,
           source="https://github.com/omacom/m1n1", source_revision=pin, version_tag=tag,
           make=["USE_CLANG=1", "RELEASE=1", "SF_INSTALLED=1", "BUILTIN_LOGO=siliconforest", "CHAINLOADING=1", "SF_AB_BOOT=1"],
           patches={q.relative_to(p).as_posix(): hashlib.sha256(q.read_bytes()).hexdigest()
                    for q in sorted(p.glob("*.patch")) + sorted(p.glob("stage1-v2/*.patch"))},
           sources={n: hashlib.sha256((pathlib.Path(here) / n).read_bytes()).hexdigest()
                    for n in ("sf_ab.h", "sf_ab.c", "sf_ab_stage1.c")},
           same_as_recorded_v2=same == "true", installer_stage1=False, host=platform.platform(),
           tools={t: ver([t, "--version"]) for t in ("clang", "ld.lld", "rustc", "cargo")})
(pathlib.Path(out) / "sf-stage1-v2.json").write_text(json.dumps(rec, indent=1) + "\n")
print("sf-stage1-v2.bin %d %s%s" % (rec["bytes"], sha, "  (the recorded stage 1 v2)" if rec["same_as_recorded_v2"] else "  (NEW build)"))
PY
