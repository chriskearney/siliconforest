#!/bin/bash
# SPDX-License-Identifier: MIT
# Generated-by: LLM
# First attended Recovery candidate; never downloads or replaces a boot image.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export LC_ALL=C
umask 077

stop() { printf 'SiliconForest: %s\n' "$*" >&2; exit 1; }
sha() {
  local output
  if command -v shasum >/dev/null && output=$(shasum -a 256 "$1" 2>/dev/null); then printf '%s\n' "$output" | awk '{print $1}'
  else openssl dgst -sha256 "$1" | awk '{print $NF}'; fi
}
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }
[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] && [ "$(id -u)" = 0 ] || stop 'Open Terminal from Utilities in Apple Silicon Recovery.'
work=$(mktemp -d /tmp/siliconforest-recovery.XXXXXX)
trap 'rm -rf -- "$work"' EXIT

# Pin the whole already-staged helper. It pins its private per-Mac metadata and
# both binary images. No UUIDs, original images, credentials or keys are public.
expected=3b1c6dbdb4e554f77a7a99c06f57af163b5dc0858e3f7a9b9724287037f341ed
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
        if [ -f "$capsule/prepare.sh" ] && [ ! -L "$capsule/prepare.sh" ] && [ "$(sha "$capsule/prepare.sh")" = "$expected" ]; then
          count=$((count + 1)); found=$capsule
        fi
      fi
    fi
    pi=$((pi + 1))
  done
  di=$((di + 1))
done
[ "$count" = 1 ] || stop 'Expected one verified staged capsule. Keep Recovery open and tell Codex this message; nothing was installed.'
printf 'Found the verified SiliconForest Recovery helper.\n'
printf 'It will verify the paired Linux volume and preserve the original loader.\n'
# Keep stdin attached to this Terminal for confirmation and native Apple owner
# authentication. Do not pipe this script into bash; use bash <(curl ...).
bash "$found/prepare.sh" --install
