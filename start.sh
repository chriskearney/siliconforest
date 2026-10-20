#!/bin/bash
# SPDX-License-Identifier: MIT
# Generated-by: LLM
# First attended Recovery candidate; never downloads or replaces a boot image.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export LC_ALL=C
umask 077

stop() { printf 'SiliconForest: %s\n' "$*" >&2; exit 1; }
sha() { "$sha_tool" "$1"; }

plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }
[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] && [ "$(id -u)" = 0 ] || stop 'Open Terminal from Utilities in Apple Silicon Recovery.'
work=$(mktemp -d /tmp/siliconforest-recovery.XXXXXX)
trap 'rm -rf -- "$work"' EXIT

# Pin the whole already-staged helper. It pins its private per-Mac metadata and
# both binary images. No UUIDs, original images, credentials or keys are public.
expected_old=3b1c6dbdb4e554f77a7a99c06f57af163b5dc0858e3f7a9b9724287037f341ed
expected_previous=113ab917bf000bb3ce21f98607232ebbb3c9eba097b2d04ef5a2d4655ee9b78d
expected_new=e37936f3e84555f0562f1945758255e206c1a6dc421ab1db7bf3f2b05739065a
expected_metadata=d0e3a2b6414e615d4fd6618fb23c83b0ff0b090f08df9b5920f2b09705345b49
expected_template=b5633438e3bd7eeb838ef336aab897ccbd70e237b151f15559938c77b2007335
expected_tool=9f9c8c3e68055c8d3ceb1aed3c0edb15fcc11613bf345aa3e9745ea9725ba33e
# This executable and this launcher share the authenticated HTTPS publication
# origin. No system checksum tool is assumed. The utility is built from the
# public Go source, has known-answer tests, and never accepts owner credentials.
sha_tool="$work/sf-sha256"
curl --proto '=https' -fsSL https://github.com/iconidentify/siliconforest/releases/download/v2026.10.20-recovery2/sf-sha256-darwin-arm64 -o "$sha_tool"
chmod 700 "$sha_tool"
"$sha_tool" --self-test
[ "$(sha "$sha_tool")" = "$expected_tool" ] || stop 'Checksum utility differs from its pinned build'
curl --proto '=https' -fsSL https://raw.githubusercontent.com/iconidentify/siliconforest/recovery3/scripts/stage1-recovery-prepare.sh -o "$work/prepare-template.sh"
[ "$(sha "$work/prepare-template.sh")" = "$expected_template" ] || stop 'Repair template differs from its pinned source'
diskutil list -plist > "$work/disks.plist"
di=0; found=; count=0
while plist "$work/disks.plist" "AllDisksAndPartitions:$di:DeviceIdentifier" >/dev/null 2>&1; do
  pi=0
  while content=$(plist "$work/disks.plist" "AllDisksAndPartitions:$di:Partitions:$pi:Content" 2>/dev/null); do
    if [ "$content" = EFI ]; then
      device=$(plist "$work/disks.plist" "AllDisksAndPartitions:$di:Partitions:$pi:DeviceIdentifier")
      [[ "$device" =~ ^disk[0-9]+s[0-9]+$ ]] || stop 'Unexpected EFI device identifier'
      if diskutil mount "$device" >/dev/null 2>&1 && diskutil info -plist "$device" > "$work/efi.plist"; then
        mountpoint=$(plist "$work/efi.plist" MountPoint)
        capsule="$mountpoint/siliconforest/recovery-stage1"
        if [ -f "$capsule/prepare.sh" ] && [ ! -L "$capsule/prepare.sh" ]; then
          digest=$(sha "$capsule/prepare.sh")
          if [ "$digest" = "$expected_old" ] || [ "$digest" = "$expected_previous" ] || [ "$digest" = "$expected_new" ]; then
            count=$((count + 1)); found=$capsule
          fi
        fi
      fi
    fi
    pi=$((pi + 1))
  done
  di=$((di + 1))
done
[ "$count" = 1 ] || stop 'Expected one verified staged capsule. Keep Recovery open and tell Codex this message; nothing was installed.'
[ -f "$found/target.conf" ] && [ ! -L "$found/target.conf" ] && [ "$(sha "$found/target.conf")" = "$expected_metadata" ] || stop 'Per-Mac metadata differs from the original staged capsule'
sed "s/@TARGET_CONF_SHA@/$expected_metadata/" "$work/prepare-template.sh" > "$work/prepare-fixed.sh"
[ "$(sha "$work/prepare-fixed.sh")" = "$expected_new" ] || stop 'Repaired helper differs from the reviewed source'
# Repair only our own capsule files, preserving the old helper. Kernel, loader,
# UKIs, menu, metadata and image bytes are never replaced by this launcher.
[ ! -L "$found/sf-sha256" ] && [ ! -L "$found/.sf-sha256-new" ] && [ ! -L "$found/.prepare-new.sh" ] || stop 'Unsafe capsule repair slot'
if [ -e "$found/prepare-before-sha-fix.sh" ] || [ -L "$found/prepare-before-sha-fix.sh" ]; then
  [ -f "$found/prepare-before-sha-fix.sh" ] && [ ! -L "$found/prepare-before-sha-fix.sh" ] && [ "$(sha "$found/prepare-before-sha-fix.sh")" = "$expected_old" ] || stop 'Original helper backup differs'
elif [ "$(sha "$found/prepare.sh")" = "$expected_old" ]; then
  cp "$found/prepare.sh" "$found/prepare-before-sha-fix.sh"
  [ "$(sha "$found/prepare-before-sha-fix.sh")" = "$expected_old" ] || stop 'Original helper backup could not be verified'
fi
if [ -e "$found/prepare-before-cmp-fix.sh" ] || [ -L "$found/prepare-before-cmp-fix.sh" ]; then
  [ -f "$found/prepare-before-cmp-fix.sh" ] && [ ! -L "$found/prepare-before-cmp-fix.sh" ] && [ "$(sha "$found/prepare-before-cmp-fix.sh")" = "$expected_previous" ] || stop 'Previous helper backup differs'
elif [ "$(sha "$found/prepare.sh")" = "$expected_previous" ]; then
  cp "$found/prepare.sh" "$found/prepare-before-cmp-fix.sh"
  [ "$(sha "$found/prepare-before-cmp-fix.sh")" = "$expected_previous" ] || stop 'Previous helper backup could not be verified'
fi
cp "$sha_tool" "$found/.sf-sha256-new"
[ "$(sha "$found/.sf-sha256-new")" = "$expected_tool" ] || stop 'Copied checksum utility differs'
cp "$work/prepare-fixed.sh" "$found/.prepare-new.sh"
[ "$(sha "$found/.prepare-new.sh")" = "$expected_new" ] || stop 'Copied repaired helper differs'
sync
mv -f "$found/.sf-sha256-new" "$found/sf-sha256"
mv -f "$found/.prepare-new.sh" "$found/prepare.sh"
sync
[ "$(sha "$found/prepare.sh")" = "$expected_new" ] && [ "$(sha "$found/sf-sha256")" = "$expected_tool" ] || stop 'Capsule repair verification failed'
printf 'Verified checksum repair; original helper preserved.\n'
printf 'Found the verified SiliconForest Recovery helper.\n'
printf 'It will verify the paired Linux volume and preserve the original loader.\n'
# Keep stdin attached to this Terminal for confirmation and native Apple owner
# authentication. Do not pipe this script into bash; use bash <(curl ...).
bash "$found/prepare.sh" --install
