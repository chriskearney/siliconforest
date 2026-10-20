#!/bin/bash
# SPDX-License-Identifier: MIT
# Generated-by: LLM
# Owner-attended candidate. No Apple firmware or security-level changes.
# Interfaces/provenance: AsahiLinux/asahi-installer src/{osenum.py,step2/step2.sh}.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export LC_ALL=C
umask 077

fail() { printf '\nSTOP: %s\nNo automatic reboot will be performed.\n' "$*" >&2; exit 1; }
sha() {
  local output
  if command -v shasum >/dev/null && output=$(shasum -a 256 "$1" 2>/dev/null); then printf '%s\n' "$output" | awk '{print $1}'
  else openssl dgst -sha256 "$1" | awk '{print $NF}'; fi
}
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }
same_uuid() { [ "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" = "$(printf '%s' "$2" | tr 'A-Z' 'a-z')" ]; }
hash_check() { [ -f "$1" ] && [ ! -L "$1" ] && [ "$(sha "$1")" = "$2" ] || fail "File changed: $1"; }
mount_volume() {
  diskutil mount "$1" >/dev/null
  diskutil info -plist "$1" > "$work/mount.plist"
  plist "$work/mount.plist" MountPoint
}
policy() {
  bputil -d -v "$vgid" > "$1"
  grep -q ': Paired' "$1" || fail 'Wrong Recovery. Return to Linux, then shut down and hold Power continuously; choose Options.'
  grep -q 'one true recoveryOS' "$1" || fail 'Hold Power continuously from shutdown to enter the required Recovery mode.'
}
policy_hash() {
  local value
  value=$(sed -n "s/^.*($2): \([0-9A-Fa-f]*\)[[:space:]]*$/\1/p" "$1")
  [[ "$value" =~ ^[0-9A-Fa-f]+$ ]] && { [ "${#value}" = 64 ] || [ "${#value}" = 96 ]; } || fail "Cannot identify $2 in boot policy"
  printf '%s' "$value"
}
contains_payload() {
  # Both files are this user's m1n1 custom image; no Apple firmware is decoded.
  local outer inner size
  size=$(stat -f '%z' "$1"); [ "$size" -le 16777216 ] || fail 'Unexpected custom-image size'
  size=$(stat -f '%z' "$2"); [ "$size" -le 4194304 ] || fail 'Unexpected raw stage-1 size'
  outer=$(od -An -v -tx1 "$1" | tr -d ' \n')
  inner=$(od -An -v -tx1 "$2" | tr -d ' \n')
  [ -n "$inner" ] && [[ "$outer" == *"$inner"* ]]
}
protected_hashes() {
  local path digest
  for path in "$esp/limine.conf" "$esp"/EFI/Linux/*.efi "$esp"/m1n1/boot.bin*; do
    [ -f "$path" ] && [ ! -L "$path" ] || fail "Unsafe/missing boot-chain file: $path"
    digest=$(sha "$path") || fail "Cannot hash $path"
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || fail "Invalid digest for $path"
    printf '%s  %s\n' "$digest" "$path"
  done
}

[ "$#" -le 1 ] || fail 'Usage: prepare.sh [--inspect | --install]'
mode=${1:---inspect}
case "$mode" in --inspect|--install) ;; *) fail 'Usage: prepare.sh [--inspect | --install]' ;; esac
[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] || fail 'Run only on Apple Silicon in Recovery.'
[ "$(id -u)" = 0 ] || fail 'Open Terminal from the Recovery Utilities menu.'
here=$(cd -- "$(dirname -- "$0")" && pwd -P)
work=$(mktemp -d /tmp/siliconforest-stage1.XXXXXX)
trap 'rm -rf -- "$work"' EXIT

# This file is generated from this Mac's live DT and stub metadata, never guessed.
[ -f "$here/target.conf" ] && [ ! -L "$here/target.conf" ] || fail 'Missing target identity'
# target.conf contains only verified hexadecimal hashes/UUIDs and a board label.
# shellcheck source=/dev/null
[ "$(sha "$here/target.conf")" = '@TARGET_CONF_SHA@' ] || fail 'Target metadata changed'
while IFS='=' read -r key value; do
  case "$key" in
    board) board=$value ;;
    vgid) vgid=$value ;;
    esp_uuid) esp_uuid=$value ;;
    raw_sha) raw_sha=$value ;;
    image_sha) image_sha=$value ;;
    stage2_sha) stage2_sha=$value ;;
    old_version) old_version=$value ;;
    *) fail 'Unexpected target metadata key' ;;
  esac
done < "$here/target.conf"
[[ "$vgid" =~ ^[0-9A-Fa-f-]{36}$ ]] && [[ "$esp_uuid" =~ ^[0-9a-f-]{36}$ ]] || fail 'Invalid target identity'
[[ "$raw_sha" =~ ^[0-9a-f]{64}$ ]] && [[ "$image_sha" =~ ^[0-9a-f]{64}$ ]] || fail 'Invalid candidate hashes'
hash_check "$here/m1n1-neutral-stage1.bin" "$raw_sha"
hash_check "$here/m1n1-stage1.bin" "$image_sha"
diskutil info -plist "$esp_uuid" > "$work/esp.plist"
same_uuid "$(plist "$work/esp.plist" DiskUUID)" "$esp_uuid" || fail 'Wrong EFI partition'
[ "$(plist "$work/esp.plist" Content)" = EFI ] || fail 'Target partition is not EFI'
esp=$(plist "$work/esp.plist" MountPoint)
[ "$here" = "$esp/siliconforest/recovery-stage1" ] || fail 'Run the capsule on this Mac’s identified EFI partition'
hash_check "$esp/m1n1/boot.bin" "$stage2_sha"
policy "$work/policy.before.txt"
coih=$(policy_hash "$work/policy.before.txt" coih)
nsih=$(policy_hash "$work/policy.before.txt" nsih)

# Match the exact live Linux volume-group UUID, then its System and Preboot roles.
diskutil apfs list -plist > "$work/apfs.plist"
matches=0; ci=0; system_device=; container=
while plist "$work/apfs.plist" "Containers:$ci:ContainerReference" > "$work/value" 2>/dev/null; do
  current_container=$(cat "$work/value"); gi=0
  diskutil apfs listVolumeGroups "$current_container" -plist > "$work/groups.plist"
  while current_uuid=$(plist "$work/groups.plist" "Containers:0:VolumeGroups:$gi:APFSVolumeGroupUUID" 2>/dev/null); do
    if same_uuid "$current_uuid" "$vgid"; then
      matches=$((matches + 1)); container=$current_container; vi=0; system_matches=0
      while role=$(plist "$work/groups.plist" "Containers:0:VolumeGroups:$gi:Volumes:$vi:Role" 2>/dev/null); do
        if [ "$role" = System ]; then
          system_matches=$((system_matches + 1))
          system_device=$(plist "$work/groups.plist" "Containers:0:VolumeGroups:$gi:Volumes:$vi:DeviceIdentifier")
        fi
        vi=$((vi + 1))
      done
      [ "$system_matches" = 1 ] || fail 'System volume is ambiguous'
    fi
    gi=$((gi + 1))
  done
  ci=$((ci + 1))
done
[ "$matches" = 1 ] || fail 'Expected exactly one matching Linux stub volume group'
[[ "$system_device" =~ ^disk[0-9]+s[0-9]+$ ]] || fail 'Unexpected System device identifier'
preboot_matches=0; ci=0; preboot_device=; system_uuid=
while current_container=$(plist "$work/apfs.plist" "Containers:$ci:ContainerReference" 2>/dev/null); do
  if [ "$current_container" = "$container" ]; then
    vi=0
    while volume_device=$(plist "$work/apfs.plist" "Containers:$ci:Volumes:$vi:DeviceIdentifier" 2>/dev/null); do
      if [ "$volume_device" = "$system_device" ]; then
        system_uuid=$(plist "$work/apfs.plist" "Containers:$ci:Volumes:$vi:APFSVolumeUUID")
      fi
      role=$(plist "$work/apfs.plist" "Containers:$ci:Volumes:$vi:Roles:0" 2>/dev/null || true)
      if [ "$role" = Preboot ]; then preboot_matches=$((preboot_matches + 1)); preboot_device=$volume_device; fi
      vi=$((vi + 1))
    done
  fi
  ci=$((ci + 1))
done
[ "$preboot_matches" = 1 ] && [[ "$preboot_device" =~ ^disk[0-9]+s[0-9]+$ ]] || fail 'Preboot volume is ambiguous'
[[ "$system_uuid" =~ ^[0-9A-Fa-f-]{36}$ ]] || fail 'Cannot identify a durable System-volume UUID for rollback'
system_dir=$(mount_volume "$system_device")
preboot=$(mount_volume "$preboot_device")
old="$system_dir/Finish Installation.app/Contents/Resources/boot.bin"
installed="$preboot/$vgid/boot/$nsih/System/Library/Caches/com.apple.kernelcaches/kernelcache.custom.$coih"
[ -f "$old" ] && [ ! -L "$old" ] && [ -f "$installed" ] && [ ! -L "$installed" ] || fail 'Cannot preserve the original stage 1'
if contains_payload "$installed" "$here/m1n1-stage1.bin"; then
  printf 'Neutral stage 1 is already installed for this Linux volume. No change made.\n'
  exit 0
fi
[ "$(stat -f '%z' "$old")" -ge 524288 ] || fail 'Original raw stage1 is unexpectedly small'
printf '##m1n1_ver##%s\000' "$old_version" > "$work/old-version.bin"
contains_payload "$old" "$work/old-version.bin" || fail 'Original raw stage1 identity differs from the version exported by the running machine'
contains_payload "$installed" "$old" || fail 'The installer’s original stage 1 differs from the active custom image; keep the current loader and inspect before replacing it.'

# The existing stage-1 variables must agree with the live ESP binding.
marker=$(grep -aob STACKBOT "$old" | cut -d: -f1)
[[ "$marker" =~ ^[0-9]+$ ]] || fail 'Cannot identify one stage-1 payload marker'
tail -c "+$((marker + 9))" "$old" | tr '\000' '\n' | sed '/^$/q' > "$work/vars"
chosen=0; chainload=0
while IFS= read -r line; do
  case "$line" in
    "chosen.asahi,efi-system-partition=$esp_uuid") chosen=$((chosen + 1)) ;;
    "chainload=$esp_uuid;m1n1/boot.bin") chainload=$((chainload + 1)) ;;
    '') ;;
    *) fail 'Unexpected stage-1 variable. Preserve and review it before migration.' ;;
  esac
done < "$work/vars"
[ "$chosen" = 1 ] && [ "$chainload" = 1 ] || fail 'The old stage-1 ESP binding differs from the running Linux binding'
protected_hashes > "$work/boot-chain.sha256"
printf '\nVerified %s, paired 1TR, original custom image, and the exact Linux EFI binding.\n' "$board"
printf 'Only early stage 1 would change. Kernel, stage 2, menu and recovery entries remain untouched.\n'
if [ "$mode" = --inspect ]; then
  printf 'Inspection passed. No boot-policy or boot-image changes made.\n'
  exit 0
fi

free_kib=$(df -Pk "$esp" | awk 'NR==2 {print $4}')
[[ "$free_kib" =~ ^[0-9]+$ ]] && [ "$free_kib" -ge 32768 ] || fail 'Need32MiB free on the EFI partition for verified backups'
backup=$(mktemp -d "$here/backup-$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")
printf '%s\n' preparing > "$backup/status"
cp -p "$old" "$backup/original-stage1.bin"
cp -p "$installed" "$backup/original-installed-custom-image"
cp "$work/policy.before.txt" "$backup/policy.before.txt"
cp "$work/boot-chain.sha256" "$backup/boot-chain.sha256"
cp "$here/m1n1-stage1.bin" "$backup/neutral-stage1.bin"
old_sha=$(sha "$old"); installed_sha=$(sha "$installed")
hash_check "$backup/original-stage1.bin" "$old_sha"
hash_check "$backup/original-installed-custom-image" "$installed_sha"
hash_check "$backup/neutral-stage1.bin" "$image_sha"
printf '%s\n' preparing > "$backup/status"

# Store a restoration command with the exact old raw image and volume binding.
{
  printf '#!/bin/bash\nset -euo pipefail\nexport PATH=/usr/bin:/bin:/usr/sbin:/sbin\n'
  printf 'vgid=%q\nsystem_uuid=%q\nexpected=%q\n' "$vgid" "$system_uuid" "$old_sha"
  declare -f fail sha plist
  cat <<'RESTORE'
[ "$(uname -s)" = Darwin ] && [ "$(id -u)" = 0 ]
work=$(mktemp -d /tmp/siliconforest-restore.XXXXXX)
trap 'rm -rf -- "$work"' EXIT
bputil -d -v "$vgid" > "$work/policy"
grep -q ': Paired' "$work/policy"
grep -q 'one true recoveryOS' "$work/policy"
backup_dir=$(cd -- "$(dirname -- "$0")" && pwd -P)
image="$backup_dir/original-stage1.bin"
[ -f "$image" ] && [ ! -L "$image" ]
[ "$(sha "$image")" = "$expected" ]
diskutil mount "$system_uuid" >/dev/null
diskutil info -plist "$system_uuid" > "$work/system.plist"
os=$(plist "$work/system.plist" MountPoint)
printf 'Restoring the preserved original early loader. Apple will ask for owner authentication.\n'
kmutil configure-boot -c "$image" --raw --entry-point 2048 --lowest-virtual-address 0 -v "$os"
printf 'Original stage1 reinstalled. Restart and select your Linux installation.\n'
RESTORE
} > "$backup/restore.sh"
sync
hash_check "$old" "$old_sha"
hash_check "$installed" "$installed_sha"
hash_check "$backup/original-stage1.bin" "$old_sha"
hash_check "$here/m1n1-stage1.bin" "$image_sha"
policy "$work/policy.recheck.txt"
[ "$(policy_hash "$work/policy.recheck.txt" coih)" = "$coih" ] && [ "$(policy_hash "$work/policy.recheck.txt" nsih)" = "$nsih" ] || fail 'Boot policy changed during preparation'
protected_hashes > "$work/boot-chain.recheck"
cmp -s "$work/boot-chain.sha256" "$work/boot-chain.recheck" || fail 'Linux boot files changed during preparation'
printf '\nFirst attended hardware trial: this candidate has passed build/source checks, not a Recovery boot test.\n'
printf 'Verified backup: %s\n' "$backup"
printf 'Recovery rollback command: bash %q\n' "$backup/restore.sh"
printf 'Install the neutral early loader on this Linux volume? Type yes: '
IFS= read -r answer
[ "$answer" = yes ] || { printf '%s\n' cancelled > "$backup/status"; sync; printf 'Cancelled. Verified backups kept; loader unchanged.\n'; exit 0; }
# The owner may spend time at the prompt; check again immediately before kmutil.
hash_check "$backup/neutral-stage1.bin" "$image_sha"
hash_check "$backup/original-stage1.bin" "$old_sha"
hash_check "$installed" "$installed_sha"
policy "$work/policy.final.txt"
[ "$(policy_hash "$work/policy.final.txt" coih)" = "$coih" ] && [ "$(policy_hash "$work/policy.final.txt" nsih)" = "$nsih" ] || fail 'Boot policy changed while waiting for confirmation'
protected_hashes > "$work/boot-chain.final"
cmp -s "$work/boot-chain.sha256" "$work/boot-chain.final" || fail 'Linux boot files changed while waiting for confirmation'
printf '%s\n' applying > "$backup/status"
sync
if ! kmutil configure-boot -c "$backup/neutral-stage1.bin" --raw --entry-point 2048 --lowest-virtual-address 0 -v "$system_dir"; then
  printf '%s\n' apply-unverified > "$backup/status"; sync
  fail "kmutil did not complete. Keep Recovery open. Backup and restore.sh: $backup"
fi
printf '%s\n' apply-unverified > "$backup/status"
sync
policy "$backup/policy.after.txt"
new_coih=$(policy_hash "$backup/policy.after.txt" coih)
[ "$(policy_hash "$backup/policy.after.txt" nsih)" = "$nsih" ] || fail "Unexpected firmware identity; keep Recovery open. Backup: $backup"
new_installed="$preboot/$vgid/boot/$nsih/System/Library/Caches/com.apple.kernelcaches/kernelcache.custom.$new_coih"
contains_payload "$new_installed" "$backup/neutral-stage1.bin" || fail "New custom image not verified. Keep Recovery open. Backup: $backup"
protected_hashes > "$backup/boot-chain.after.sha256"
cmp -s "$backup/boot-chain.sha256" "$backup/boot-chain.after.sha256" || fail "Linux boot files changed unexpectedly. Keep Recovery open. Backup: $backup"
printf '%s\n' installed-awaiting-linux-boot-test > "$backup/status"
sync
printf '\nNeutral early stage1 installed; Linux boot files unchanged.\n'
printf 'Restart, then select your Linux installation. Keep this backup for rollback:\n%s\n' "$backup"
printf 'We still need to verify the first Linux boot. Future splash/logo changes can stay in Linux.\n'
