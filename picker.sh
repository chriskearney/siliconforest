#!/bin/bash
# SPDX-License-Identifier: MIT
# Generated-by: LLM
# Owner-attended Apple startup-picker pilot. No boot image is installed.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export LC_ALL=C
umask 077
stop() { printf 'SiliconForest picker: %s\n' "$*" >&2; exit 1; }
sha() { "$sha_tool" "$1"; }
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }
[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] && [ "$(id -u)" = 0 ] || stop 'Use Utilities > Terminal in Apple Silicon Recovery.'
mode=${1:---apply}
[ "$#" -le 1 ] || stop 'Usage: picker.sh [--inspect|--apply]'
case "$mode" in --inspect|--apply) ;; *) stop 'Usage: picker.sh [--inspect|--apply]' ;; esac
missing=
for required in uname id mktemp rm curl chmod diskutil; do
  command -v "$required" >/dev/null 2>&1 || missing="$missing $required"
done
[ -z "$missing" ] || stop "Missing Recovery tools:$missing"
work=$(mktemp -d /tmp/siliconforest-picker-start.XXXXXX)
trap 'rm -rf -- "$work"' EXIT
expected_tool=9f9c8c3e68055c8d3ceb1aed3c0edb15fcc11613bf345aa3e9745ea9725ba33e
expected_conf=1336da1a5348ee66e56295146ffdf56363fd16c068eead132fe8573be4a1e83a
expected_helper=97404d8a55ea270abcb27a3dd1c6f8ad8e3915afa11fb0fee07bff41d3a89169
expected_icon=f23e743bd20e5569bacaeb86650080156a4f379978e2436dc718a3d448d04302
# Same authenticated HTTPS publication origin as this launcher. Known-answer
# tests and the pinned build digest run before reading any capsule inputs.
sha_tool="$work/sf-sha256"
curl --proto '=https' --proto-redir '=https' -fsSL https://github.com/iconidentify/siliconforest/releases/download/v2026.10.20-recovery2/sf-sha256-darwin-arm64 -o "$sha_tool"
chmod 700 "$sha_tool"
"$sha_tool" --self-test
[ "$(sha "$sha_tool")" = "$expected_tool" ] || stop 'Checksum utility differs from its pinned build'
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
        capsule="$mountpoint/siliconforest/apple-picker"
        if [ -d "$capsule" ] && [ ! -L "$capsule" ] && [ -f "$capsule/update.sh" ] && [ ! -L "$capsule/update.sh" ] && [ "$(sha "$capsule/update.sh")" = "$expected_helper" ]; then
          count=$((count + 1)); found=$capsule
        fi
      fi
    fi
    pi=$((pi + 1))
  done
  di=$((di + 1))
done
[ "$count" = 1 ] || stop 'Expected one verified staged Apple-picker capsule. Keep Recovery open; no startup metadata changed.'
for name in target.conf siliconforest-volume.icns sf-sha256; do
  [ -f "$found/$name" ] && [ ! -L "$found/$name" ] || stop 'Unsafe or incomplete staged capsule'
done
[ "$(sha "$found/target.conf")" = "$expected_conf" ] && [ "$(sha "$found/siliconforest-volume.icns")" = "$expected_icon" ] && [ "$(sha "$found/sf-sha256")" = "$expected_tool" ] || stop 'Staged capsule differs from the reviewed inputs'
printf 'Verified metadata-only Apple-picker updater. Linux boot images will not be replaced.\n'
# Keep stdin on Terminal for the owner's yes/no confirmation.
bash "$found/update.sh" "$mode"
