#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
#
# build_stage2.sh OUT [a|b]    an installed stage 2 (the file sf/boot.bin of SFBOOT), from source
#
# Stage 2 is the m1n1 stage of m1-native-boot/b1 built as the installer ships it
# (m1-native-boot/install/build.sh, "sf-stage2"): Omacom m1n1 at the profile's pin, b1's patches and
# sources, install/patches (the installed variant) and install/patches/stage2 (it reads its records
# from a file of the boot partition, one EL3 stack), RELEASE=1 CHAINLOADING=1 SF_INSTALLED=1
# SF_KERNEL_FILE=1, our boot logo.
#
#   a   reads sf/kernel.bin   -> OUT/boot-a.bin   (slot A; the installer ships the stage 2 it already
#                                                  has, so this is for comparison and for rebuilding it)
#   b   reads sf/b/kernel.bin -> OUT/boot-b.bin   (slot B, A/B boot: abboot/README.md; the release's
#                                                  `boot-b.bin`, installed as sf/b/boot.bin)
# The two differ only in the kernel file's name (PDSF_KERNEL_FILE in pdsf.h, 13 vs 15 characters).
#
# Inputs (environment)
#   SF_M1N1_SRC       a clean checkout of https://github.com/omacom/m1n1 at the pin, with its submodule
#   SF_ROOT_FSUUID    the root filesystem's UUID, compiled into stage 2 (the release root's `fs_uuid`
#                     in root.json; default: read from SF_ROOT_JSON)
#   SF_ROOT_JSON      the installer root's root.json
#   SF_BOOT_LOGO, SF_CARGO_ONLINE=1  as build_stage1.sh
# The result must fit stage 1's footprint (profile). Host only: no device is opened, nothing is
# published, OUT is never committed.
set -euo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd); ROOT=$(cd "$HERE/../../.." && pwd)
SLOT=${2:-b}; case "$SLOT" in a|b) ;; *) echo "slot must be a or b" >&2; exit 2;; esac
PROFILE=$ROOT/installer/profiles/J313.json
PIN=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["boot"]["stage1"]["source_revision"])' "$PROFILE")
FOOTPRINT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["boot"]["stage1"]["max_stage2_span_bytes"])' "$PROFILE")
INST=$ROOT/integrations/siliconforest/m1-native-boot/install
B1=$ROOT/integrations/siliconforest/m1-native-boot/b1
SRC=${SF_M1N1_SRC:-$ROOT/sources/m1n1-baseline}
LOGO=${SF_BOOT_LOGO:-$ROOT/integrations/siliconforest/branding/siliconforest-boot.svg}
OUT=$(mkdir -p "${1:?usage: build_stage2.sh OUT [a|b]}" && cd "$1" && pwd)
die() { echo "build_stage2: $*" >&2; exit 2; }
FSUUID=${SF_ROOT_FSUUID:-}
[ -n "$FSUUID" ] || { [ -f "${SF_ROOT_JSON:-}" ] && FSUUID=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["fs_uuid"])' "$SF_ROOT_JSON"); }
[[ "$FSUUID" =~ ^[0-9a-fA-F-]{36}$ ]] || die "set SF_ROOT_FSUUID or SF_ROOT_JSON (the root's filesystem UUID)"
TAG="$PIN-siliconforest-boot-v2"; KFILE="sf/kernel.bin"
[ "$SLOT" = b ] && { TAG="$TAG-b"; KFILE="sf/b/kernel.bin"; }

[ "$(git -C "$SRC" rev-parse HEAD)" = "$PIN" ] || die "$SRC is not m1n1 at $PIN"
[ -z "$(git -C "$SRC" status --porcelain --untracked-files=no)" ] || die "$SRC has local changes"
[ -f "$LOGO" ] || die "logo $LOGO missing"
for t in clang ld.lld llvm-objcopy rustc cargo make rsvg-convert magick; do command -v $t >/dev/null || die "$t missing"; done
[ -d "$(rustc --print sysroot)/lib/rustlib/aarch64-unknown-none-softfloat" ] || die "rustc has no aarch64-unknown-none-softfloat target"
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
  for p in "$B1"/patches/*.patch; do git apply "$p"; done
  cp "$B1"/src/pdsf.c "$B1"/src/pdsf.h "$B1"/src/pdsf_boot.c "$B1"/src/pdsf_el2.S src/
  printf '#define PDSF_ROOT_UUID "%s"\n' "$FSUUID" > src/pdsf_root.h
  mkdir -p build
  clang --target=aarch64-none-elf -march=armv8.5-a -c "$B1/../stub/el2_drop.S" -o build/pdsf_el2_stub.o
  llvm-objcopy -O binary build/pdsf_el2_stub.o build/pdsf_el2.bin
  [ "$(sha256sum build/pdsf_el2.bin | cut -d' ' -f1)" = "$(sed -n "s/^STUB_SHA256 = '\(.*\)'/\1/p" "$B1/../native_stub.py")" ] || die "el2_drop.S does not assemble to the booted page"
  for p in "$INST"/patches/*.patch "$INST"/patches/stage2/*.patch; do git apply "$p"; done
  cp "$INST/src/pdsf_file.c" src/
  if [ "$SLOT" = b ]; then
    grep -q '^#define PDSF_KERNEL_FILE "sf/kernel.bin"$' src/pdsf.h || die "pdsf.h does not name sf/kernel.bin"
    sed -i 's|^#define PDSF_KERNEL_FILE "sf/kernel.bin"$|#define PDSF_KERNEL_FILE "sf/b/kernel.bin"|' src/pdsf.h
  fi
  cp "$WORK/siliconforest_128.bin" "$WORK/siliconforest_256.bin" data/
  M1N1_VERSION_TAG=$TAG make -j"$NPROC" USE_CLANG=1 CARGO_FLAGS="$cargo" RELEASE=1 SF_INSTALLED=1 \
    BUILTIN_LOGO=siliconforest CHAINLOADING=1 SF_KERNEL_FILE=1 build/m1n1.bin > "$OUT/boot-$SLOT.log" 2>&1 ||
    { tail -30 "$OUT/boot-$SLOT.log" >&2; exit 1; }
  ! grep -n 'warning:' "$OUT/boot-$SLOT.log" | grep 'pdsf\|utils.c\|main.c' || die "warnings in our sources"
  grep -a -q "##m1n1_ver##$TAG" build/m1n1.bin || die "the image does not carry its tag"
  grep -a -q 'SF_STOPPED' build/m1n1.bin || die "the image is not the installed variant"
  grep -q '^#define SF_KERNEL_FILE$' build/build_cfg.h || die "stage 2 does not read its kernel from a file"
  grep -a -q "$KFILE" build/m1n1.bin || die "stage 2 does not name $KFILE"
  [ "$SLOT" = a ] || ! grep -a -q '[^/]sf/kernel.bin' build/m1n1.bin || die "stage 2 B still names sf/kernel.bin"
  [ "$(grep -a -c -F "$FSUUID" build/m1n1.bin)" -ge 1 ] || die "stage 2 does not carry the root's filesystem UUID"
  cp build/m1n1.bin "$OUT/boot-$SLOT.bin"
)
SIZE=$(wc -c < "$OUT/boot-$SLOT.bin")
[ "$SIZE" -le "$FOOTPRINT" ] || die "boot-$SLOT.bin is $SIZE bytes, more than stage 1's footprint $FOOTPRINT"
echo "boot-$SLOT.bin $SIZE $(sha256sum "$OUT/boot-$SLOT.bin" | cut -d' ' -f1)  (tag $TAG, reads $KFILE)"
