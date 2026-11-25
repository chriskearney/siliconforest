#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
#
# build_stage1.sh OUT      the release's sf-stage1.bin, from source (docs/installer/PAYLOAD.md section 12)
#
# Stage 1 is the m1n1 that goes into the stub as the boot object (SFStub/S55 append the profile's
# variables and four NULs). It is built exactly as the installed machine's stage 1 was
# (integrations/siliconforest/m1-native-boot/install/build.sh, "sf-stage1"): Omacom m1n1 at the
# profile's pin, our patches in m1-native-boot/install/patches/ (not the stage 2 ones), RELEASE=1
# CHAINLOADING=1 SF_INSTALLED=1, our boot logo, the version tag <pin>-siliconforest-stage1-v1.
# With the same toolchain it is byte-identical to that stage 1 (44c1ef0b..., 13 November 2026); a
# build that differs stops unless SF_NEW_STAGE1=1 (a different stage 1 is a new install: it is
# written only from recovery mode).
#
# Inputs (environment)
#   SF_M1N1_SRC     a clean checkout of https://github.com/omacom/m1n1 at the pin, with its artwork
#                   submodule (default: <repo>/sources/m1n1-baseline, the lab layout)
#   SF_BOOT_LOGO    another logo (svg or png); default integrations/siliconforest/branding/siliconforest-boot.svg
#   SF_CARGO_ONLINE=1  let cargo fetch the Rust crates (CI); otherwise --offline, as the lab builds
#   SF_NEW_STAGE1=1 accept a stage 1 that is not the installed one (records it as such)
# Outputs: OUT/sf-stage1.bin, OUT/sf-stage1.json (provenance: pin, patches, tools, size, SHA-256),
# OUT/sf-stage1.log. Host only: no device is opened, nothing is published, OUT is never committed.
set -euo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd); ROOT=$(cd "$HERE/../../.." && pwd)
PROFILE=$ROOT/installer/profiles/J313.json
PIN=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["boot"]["stage1"]["source_revision"])' "$PROFILE")
FOOTPRINT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["boot"]["stage1"]["max_stage2_span_bytes"])' "$PROFILE")
TAG="$PIN-siliconforest-stage1-v1"
STAGE1_INSTALLED=44c1ef0bda96224f5fe8c6228cc12ec1966b7781f38844cea960b21b47654318
PATCHES=$ROOT/integrations/siliconforest/m1-native-boot/install/patches
SRC=${SF_M1N1_SRC:-$ROOT/sources/m1n1-baseline}
LOGO=${SF_BOOT_LOGO:-$ROOT/integrations/siliconforest/branding/siliconforest-boot.svg}
OUT=$(mkdir -p "${1:?usage: build_stage1.sh OUT}" && cd "$1" && pwd)
die() { echo "build_stage1: $*" >&2; exit 2; }

[ "$(git -C "$SRC" rev-parse HEAD)" = "$PIN" ] || die "$SRC is not m1n1 at $PIN"
[ -z "$(git -C "$SRC" status --porcelain --untracked-files=no)" ] || die "$SRC has local changes"
[ -f "$LOGO" ] || die "logo $LOGO missing"
ls "$PATCHES"/*.patch >/dev/null || die "no patches in $PATCHES"
# The toolchain the installed stage 1 was built with: clang/ld.lld 22.1.8, rustc 1.98.1 (rustup stable) with the
# aarch64-unknown-none-softfloat target. Another toolchain builds a working stage 1 with another SHA-256.
for t in clang ld.lld rustc cargo make rsvg-convert magick; do command -v $t >/dev/null || die "$t missing"; done
[ -d "$(rustc --print sysroot)/lib/rustlib/aarch64-unknown-none-softfloat" ] ||
  die "rustc $(rustc --version | cut -d' ' -f2) has no aarch64-unknown-none-softfloat target (rustup target add aarch64-unknown-none-softfloat; Arch's system rustc has none)"
NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu)
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# m1n1's built-in logo: raw RGBA on black, as data/makelogo.sh makes it (the same commands as install/build.sh)
for s in 128 256; do
  case "$LOGO" in *.svg) rsvg-convert -w $s -h $s "$LOGO" -o "$WORK/boot_$s.png";; *) magick "$LOGO" -resize "${s}x$s" "$WORK/boot_$s.png";; esac
  magick "$WORK/boot_$s.png" -background black -flatten -depth 8 "rgba:$WORK/siliconforest_$s.bin"
  [ "$(wc -c < "$WORK/siliconforest_$s.bin")" -eq $((s * s * 4)) ] || die "logo $s: wrong size"
done

W=$WORK/m1n1; cp -a "$SRC" "$W"
(
  cd "$W"
  # stale objects of the source tree are not used; the Rust library is rebuilt with chainloading
  if [ -d build ]; then
    find build -maxdepth 1 -type f -delete
    rm -rf build/.deps build/chickens build/dcp build/hv build/math build/tinf build/minilzlib build/dlmalloc build/libfdt
  fi
  cargo="--locked --features chainload"; [ "${SF_CARGO_ONLINE:-0}" = 1 ] || cargo="$cargo --offline"
  for p in "$PATCHES"/*.patch; do git apply "$p"; done
  cp "$WORK/siliconforest_128.bin" "$WORK/siliconforest_256.bin" data/
  M1N1_VERSION_TAG=$TAG make -j"$NPROC" USE_CLANG=1 CARGO_FLAGS="$cargo" RELEASE=1 SF_INSTALLED=1 \
    BUILTIN_LOGO=siliconforest CHAINLOADING=1 build/m1n1.bin > "$OUT/sf-stage1.log" 2>&1 || { tail -30 "$OUT/sf-stage1.log" >&2; exit 1; }
  ! grep -n 'warning:' "$OUT/sf-stage1.log" | grep 'utils.c\|main.c' || die "warnings in our sources"
  grep -a -q "##m1n1_ver##$TAG" build/m1n1.bin || die "the image does not carry its tag"
  grep -a -q 'SF_STOPPED' build/m1n1.bin || die "the image is not the installed variant"
  for c in RELEASE SF_INSTALLED CHAINLOADING; do grep -q "^#define $c\$" build/build_cfg.h || die "build configuration lacks $c"; done
  ! grep -q '^#define SF_KERNEL_FILE$' build/build_cfg.h || die "stage 1 is built as a stage 2"
  cp build/m1n1.bin "$OUT/sf-stage1.bin"
)
python3 "$ROOT/installer/payload/release/sfrelease.py" check-stage1 "$OUT/sf-stage1.bin" --revision "$PIN" --footprint "$FOOTPRINT"

SHA=$( (sha256sum "$OUT/sf-stage1.bin" 2>/dev/null || shasum -a 256 "$OUT/sf-stage1.bin") | cut -d' ' -f1)
INSTALLED=false; [ "$SHA" = "$STAGE1_INSTALLED" ] && INSTALLED=true
[ "$INSTALLED" = true ] || [ "${SF_NEW_STAGE1:-0}" = 1 ] ||
  die "sf-stage1.bin ($SHA) is not the stage 1 that is installed ($STAGE1_INSTALLED); SF_NEW_STAGE1=1 builds a new one, which needs a new install"
python3 -B - "$OUT" "$PIN" "$TAG" "$SHA" "$INSTALLED" "$PATCHES" <<'PY'
import hashlib, json, pathlib, platform, subprocess, sys
out, pin, tag, sha, installed, patches = sys.argv[1:]
def ver(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True).stdout.splitlines()[0]
    except Exception:
        return None
rec = dict(file="sf-stage1.bin", bytes=(pathlib.Path(out) / "sf-stage1.bin").stat().st_size, sha256=sha,
           source="https://github.com/omacom/m1n1", source_revision=pin, version_tag=tag,
           make=["USE_CLANG=1", "RELEASE=1", "SF_INSTALLED=1", "BUILTIN_LOGO=siliconforest", "CHAINLOADING=1"],
           patches={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(pathlib.Path(patches).glob("*.patch"))},
           same_as_installed_stage1=installed == "true", host=platform.platform(),
           tools={t: ver([t, "--version"]) for t in ("clang", "ld.lld", "rustc", "cargo")})
(pathlib.Path(out) / "sf-stage1.json").write_text(json.dumps(rec, indent=1) + "\n")
print("sf-stage1.bin %d %s%s" % (rec["bytes"], sha, "  (the installed stage 1)" if rec["same_as_installed_stage1"] else "  (NEW stage 1)"))
PY
