#!/bin/bash
# SPDX-License-Identifier: MIT
# Generated-by: LLM
# Apple startup-picker metadata only. Volume discovery follows the verified
# Recovery helper and AsahiLinux/asahi-installer src/{stub.py,osenum.py}.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export LC_ALL=C
umask 077
fail() { printf '\nSTOP: %s\nKeep Recovery open. No automatic reboot is performed.\n' "$*" >&2; exit 1; }
sha_tool_expected=9f9c8c3e68055c8d3ceb1aed3c0edb15fcc11613bf345aa3e9745ea9725ba33e
sha() { "$sha_tool" "$1"; }
files_equal() {
  local left right
  left=$(sha "$1") && right=$(sha "$2") &&
    [[ "$left" =~ ^[0-9a-f]{64}$ ]] && [ "$left" = "$right" ]
}
init_sha() {
  [ -f "$1" ] && [ ! -L "$1" ] || fail 'Missing self-contained SHA-256 utility'
  cp "$1" "$work/sf-sha256"
  chmod 700 "$work/sf-sha256"
  sha_tool="$work/sf-sha256"
  "$sha_tool" --self-test >/dev/null || fail 'SHA-256 utility failed its self-test'
  [ "$(sha "$sha_tool")" = "$sha_tool_expected" ] || fail 'SHA-256 utility differs from the pinned build'
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
protected_hashes() {
  local path digest
  for path in "$esp/limine.conf" "$esp"/EFI/Linux/*.efi "$esp"/m1n1/boot.bin*; do
    [ -f "$path" ] && [ ! -L "$path" ] || fail "Unsafe/missing boot-chain file: $path"
    digest=$(sha "$path") || fail "Cannot hash $path"
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || fail "Invalid digest for $path"
    printf '%s  %s\n' "$digest" "$path"
  done
  local raw="$system_dir/Finish Installation.app/Contents/Resources/boot.bin"
  [ -f "$raw" ] && [ ! -L "$raw" ] && [ -f "$installed" ] && [ ! -L "$installed" ] || fail 'Unsafe loader path'
  digest=$(sha "$raw") || fail 'Cannot hash the raw loader'
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || fail 'Invalid raw-loader digest'
  printf '%s  system-raw-loader\n' "$digest"
  digest=$(sha "$installed") || fail 'Cannot hash the custom loader'
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || fail 'Invalid custom-loader digest'
  printf '%s  active-custom-loader\n' "$digest"
}


resolve_system() {
  system_dir=$(mount_volume "$system_uuid") || return 1
  current_name=$(plist "$work/mount.plist" VolumeName) || return 1
  system_device=$(plist "$work/mount.plist" DeviceIdentifier) || return 1
  [[ "$system_device" =~ ^disk[0-9]+s[0-9]+$ ]] &&
    [ -n "$current_name" ] && [ -d "$system_dir" ] && [ ! -L "$system_dir" ]
}
replace_icon() {
  local source=$1 expected=$2 mode=${3:-644} tmp
  resolve_system || return 1
  [ -f "$source" ] && [ ! -L "$source" ] || return 1
  [ -f "$system_dir/.VolumeIcon.icns" ] && [ ! -L "$system_dir/.VolumeIcon.icns" ] || return 1
  tmp=$(mktemp "$system_dir/.siliconforest-icon.XXXXXX") || return 1
  if cp -p "$source" "$tmp" && chmod "$mode" "$tmp" && [ "$(sha "$tmp")" = "$expected" ]; then
    sync
    mv -f "$tmp" "$system_dir/.VolumeIcon.icns" || { rm -f "$tmp"; return 1; }
    sync
    [ "$(sha "$system_dir/.VolumeIcon.icns")" = "$expected" ]
  else
    rm -f "$tmp"
    return 1
  fi
}
set_name() {
  resolve_system || return 1
  if [ "$current_name" != "$1" ]; then
    diskutil renameVolume "$system_device" "$1" >/dev/null || return 1
  fi
  resolve_system && [ "$current_name" = "$1" ]
}

mode=${1:---inspect}
[ "$#" -le 1 ] || fail 'Usage: update.sh [--inspect|--apply]'
case "$mode" in --inspect|--apply) ;; *) fail 'Usage: update.sh [--inspect|--apply]' ;; esac
[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] && [ "$(id -u)" = 0 ] || fail 'Use Apple Silicon Recovery Terminal.'
missing=
for required in uname id dirname mktemp rm cp chmod tr diskutil bputil grep sed cat df awk date sync mv mkdir stat; do
  command -v "$required" >/dev/null 2>&1 || missing="$missing $required"
done
[ -z "$missing" ] || fail "Missing Recovery tools:$missing"
here=$(cd -- "$(dirname -- "$0")" && pwd -P)
work=$(mktemp -d /tmp/siliconforest-picker.XXXXXX)
mutated=0; own_lock=0; backup=
finish() {
  local rc=$1
  trap - EXIT
  if [ "$rc" != 0 ] && [ "$mutated" = 1 ]; then
    if { resolve_system && [ "$current_name" = "$old_name" ] && [ "$(sha "$system_dir/.VolumeIcon.icns")" = "$old_icon_sha" ]; } ||
       { replace_icon "$backup/original.icns" "$old_icon_sha" "$old_icon_mode" && set_name "$old_name"; }; then
      printf '%s\n' failed-restored > "$backup/status"
      printf 'Original icon and name restored. Backup: %s\n' "$backup" >&2
    else
      printf '%s\n' restore-incomplete > "$backup/status"
      printf 'Restore incomplete. Keep Recovery open; run: bash %q\n' "$backup/restore.sh" >&2
    fi
    sync
  fi
  [ "$own_lock" = 0 ] || rm -rf -- "$here/.picker-lock"
  rm -rf -- "$work"
  exit "$rc"
}
trap 'finish $?' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
init_sha "$here/sf-sha256"
hash_check "$here/target.conf" '@TARGET_CONF_SHA@'
while IFS='=' read -r key value; do
  case "$key" in
    board) board=$value ;;
    vgid) vgid=$value ;;
    esp_uuid) esp_uuid=$value ;;
    system_uuid) target_system_uuid=$value ;;
    stage2_sha) stage2_sha=$value ;;
    *) fail 'Unexpected picker target metadata key' ;;
  esac
done < "$here/target.conf"
[ "$board" = j516s ] || fail 'This attended capsule targets J516S only'
[[ "$vgid" =~ ^[0-9A-Fa-f-]{36}$ ]] && [[ "$target_system_uuid" =~ ^[0-9A-Fa-f-]{36}$ ]] && [[ "$esp_uuid" =~ ^[0-9a-f-]{36}$ ]] || fail 'Invalid target identity'
[[ "$stage2_sha" =~ ^[0-9a-f]{64}$ ]] || fail 'Invalid loader digest'
icon_sha=f23e743bd20e5569bacaeb86650080156a4f379978e2436dc718a3d448d04302
new_name='SiliconForest Linux'
hash_check "$here/siliconforest-volume.icns" "$icon_sha"
diskutil info -plist "$esp_uuid" > "$work/esp.plist"
same_uuid "$(plist "$work/esp.plist" DiskUUID)" "$esp_uuid" || fail 'Wrong EFI identity'
[ "$(plist "$work/esp.plist" Content)" = EFI ] || fail 'Target partition is not EFI'
esp=$(plist "$work/esp.plist" MountPoint)
[ "$here" = "$esp/siliconforest/apple-picker" ] || fail 'Use the staged capsule on its exact EFI partition'
hash_check "$esp/m1n1/boot.bin" "$stage2_sha"
policy "$work/policy.before"
coih=$(policy_hash "$work/policy.before" coih); nsih=$(policy_hash "$work/policy.before" nsih)

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
same_uuid "$system_uuid" "$target_system_uuid" || fail 'Wrong System-volume UUID'
system_dir=$(mount_volume "$system_uuid")
preboot=$(mount_volume "$preboot_device")

installed="$preboot/$vgid/boot/$nsih/System/Library/Caches/com.apple.kernelcaches/kernelcache.custom.$coih"
[ -f "$installed" ] && [ ! -L "$installed" ] || fail 'Cannot identify the active custom loader'
resolve_system || fail 'Cannot read the System-volume name'
icon="$system_dir/.VolumeIcon.icns"
[ -f "$icon" ] && [ ! -L "$icon" ] || fail 'Existing custom volume icon not found; inspect before adding icon flags'
old_name=$current_name; old_icon_sha=$(sha "$icon"); old_icon_mode=$(stat -f '%Lp' "$icon")
[[ "$old_icon_mode" =~ ^[0-7]{3,4}$ ]] || fail 'Invalid icon mode'
printf 'Verified %s startup volume. Current name: %s\n' "$board" "$old_name"
if [ "$old_name" = "$new_name" ] && [ "$old_icon_sha" = "$icon_sha" ]; then
  printf 'Apple picker already has the selected icon and name. No change made.\n'
  exit 0
fi
protected_hashes > "$work/boot.before"
if [ "$mode" = --inspect ]; then
  printf 'Inspection passed; no icon, volume-name or boot-policy changes made.\n'
  exit 0
fi
[ -w "$system_dir" ] || fail 'The identified System volume is read-only. Keep Recovery open; no security-setting change is needed.'
free_kib=$(df -Pk "$esp" | awk 'NR==2 {print $4}')
[[ "$free_kib" =~ ^[0-9]+$ ]] && [ "$free_kib" -ge 16384 ] || fail 'Need16MiB free on the EFI partition for backups'
mkdir "$here/.picker-lock" || fail 'Another picker operation or interrupted operation needs inspection'
own_lock=1
backup=$(mktemp -d "$here/backup-$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")
printf '%s\n' preparing > "$backup/status"
cp "$here/sf-sha256" "$backup/sf-sha256"
cp -p "$icon" "$backup/original.icns"
printf '%s\n' "$old_name" > "$backup/original-name.txt"
cp "$work/boot.before" "$backup/boot.before.sha256"
hash_check "$backup/sf-sha256" "$sha_tool_expected"
hash_check "$backup/original.icns" "$old_icon_sha"
# Constants are shell-escaped, never sourced from a mutable metadata file.
{
  printf '#!/bin/bash\nset -euo pipefail\nexport PATH=/usr/bin:/bin:/usr/sbin:/sbin\nexport LC_ALL=C\numask 077\n'
  printf 'system_uuid=%q\nold_name=%q\nold_icon_sha=%q\nnew_name=%q\nicon_sha=%q\nsha_tool_expected=%q\nold_icon_mode=%q\nesp_uuid=%q\n' "$system_uuid" "$old_name" "$old_icon_sha" "$new_name" "$icon_sha" "$sha_tool_expected" "$old_icon_mode" "$esp_uuid"
  declare -f fail sha init_sha plist same_uuid mount_volume resolve_system replace_icon set_name
  cat <<'RESTORE'
[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] && [ "$(id -u)" = 0 ] || fail 'Use Apple Silicon Recovery Terminal.'
backup_dir=$(cd -- "$(dirname -- "$0")" && pwd -P)
work=$(mktemp -d /tmp/siliconforest-picker-restore.XXXXXX)
own_lock=0
lock_dir=
trap '[ "$own_lock" = 0 ] || rm -rf -- "$lock_dir"; rm -rf -- "$work"' EXIT
init_sha "$backup_dir/sf-sha256"
diskutil info -plist "$esp_uuid" > "$work/esp.plist"
same_uuid "$(plist "$work/esp.plist" DiskUUID)" "$esp_uuid" && [ "$(plist "$work/esp.plist" Content)" = EFI ] || fail 'Wrong restoration EFI identity'
lock_dir="$(plist "$work/esp.plist" MountPoint)/siliconforest/apple-picker/.picker-lock"
mkdir "$lock_dir" || fail 'Another picker operation or interrupted operation needs inspection'
own_lock=1
[ -f "$backup_dir/original.icns" ] && [ ! -L "$backup_dir/original.icns" ] && [ "$(sha "$backup_dir/original.icns")" = "$old_icon_sha" ] || fail 'Original icon backup changed'
resolve_system || fail 'Cannot identify the original System volume'
[ "$current_name" = "$new_name" ] || [ "$current_name" = "$old_name" ] || fail 'Volume was renamed independently; inspect before restoring'
current_sha=$(sha "$system_dir/.VolumeIcon.icns")
[ "$current_sha" = "$icon_sha" ] || [ "$current_sha" = "$old_icon_sha" ] || fail 'Icon changed independently; inspect before restoring'
printf '%s\n' restoring > "$backup_dir/status"
replace_icon "$backup_dir/original.icns" "$old_icon_sha" "$old_icon_mode" && set_name "$old_name" || fail 'Restore incomplete; originals retained. Keep Recovery open.'
printf '%s\n' restored > "$backup_dir/status"
sync
printf 'Original startup-picker icon and volume name restored. No boot policy was written.\n'
RESTORE
} > "$backup/restore.sh"
sync
printf 'Verified backup: %s\nRestore command: bash %q\n' "$backup" "$backup/restore.sh"
printf 'Set the startup-picker name to SiliconForest Linux and replace its icon? Type yes: '
IFS= read -r answer
[ "$answer" = yes ] || { printf '%s\n' cancelled > "$backup/status"; sync; printf 'Cancelled; no startup metadata changed.\n'; exit 0; }
resolve_system || fail 'System volume disappeared'
[ "$current_name" = "$old_name" ] || fail 'Volume name changed while waiting'
hash_check "$system_dir/.VolumeIcon.icns" "$old_icon_sha"
hash_check "$backup/original.icns" "$old_icon_sha"
hash_check "$here/siliconforest-volume.icns" "$icon_sha"
protected_hashes > "$work/boot.recheck"
files_equal "$work/boot.before" "$work/boot.recheck" || fail 'Boot inputs changed while waiting'
policy "$work/policy.recheck"
[ "$(policy_hash "$work/policy.recheck" coih)" = "$coih" ] && [ "$(policy_hash "$work/policy.recheck" nsih)" = "$nsih" ] || fail 'Boot policy changed while waiting'
printf '%s\n' applying > "$backup/status"; sync
mutated=1
replace_icon "$here/siliconforest-volume.icns" "$icon_sha" || fail 'Icon replacement failed'
set_name "$new_name" || fail 'Volume rename failed'
protected_hashes > "$work/boot.after"
files_equal "$work/boot.before" "$work/boot.after" || fail 'Boot inputs changed unexpectedly'
policy "$work/policy.after"
[ "$(policy_hash "$work/policy.after" coih)" = "$coih" ] && [ "$(policy_hash "$work/policy.after" nsih)" = "$nsih" ] || fail 'Boot policy changed unexpectedly'
printf '%s\n' applied-awaiting-visual-check > "$backup/status"; sync
mutated=0
printf '\nStartup-picker icon and name updated. No m1n1, kernel or boot-policy write was performed.\n'
printf 'Shut down, hold Power, and check the SiliconForest Linux icon. Backup: %s\n' "$backup"
