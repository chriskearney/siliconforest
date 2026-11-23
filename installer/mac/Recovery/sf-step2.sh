#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
#
# SiliconForest Setup, Terminal fallback (DESIGN §7.1, §7.2). The same steps as SFRecovery, for when
# the app can't start. Modelled on the flow of Asahi Linux's step2.sh (MIT); written fresh here.
# bputil and kmutil ask for the macOS owner's password themselves, directly in this Terminal.
#
# Each step leaves a marker in SFInstall/state/, so re-entering recovery resumes where it stopped.
# A LocalPolicy change is never undone; it affects only this volume group.
#
# Test mode: SF_TEST_MODE=1 with every SF_* tool path set replaces the system tools with fakes and
# skips the recoveryOS gate. Outside test mode the overrides are ignored.
set -u

here="$(cd "${0%/*}" && pwd)"
system="$(cd "$here/../../.." && pwd)"          # …/<stub System volume>/SiliconForest Setup.app/Contents/Resources
state="$system/SFInstall/state"
plan="$system/SFInstall/plan.json"

if [ "${SF_TEST_MODE:-0}" = 1 ]; then
  for v in SF_BPUTIL SF_KMUTIL SF_BLESS SF_DISKUTIL SF_REBOOT; do
    eval "val=\${$v:-}"
    [ -n "$val" ] || { echo "test mode needs $v" >&2; exit 64; }
  done
  BPUTIL="$SF_BPUTIL"; KMUTIL="$SF_KMUTIL"; BLESS="$SF_BLESS"; DISKUTIL="$SF_DISKUTIL"; REBOOT="$SF_REBOOT"
else
  BPUTIL=/usr/bin/bputil; KMUTIL=/usr/bin/kmutil; BLESS=/usr/sbin/bless; DISKUTIL=/usr/sbin/diskutil; REBOOT=/sbin/reboot
fi

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\n\033[31m%s\033[0m\n' "$*" >&2; printf 'Nothing else was changed. Press Return to shut down; start up again holding the power button to retry.\n'; read -r _; exit 1; }
done_step() { mkdir -p "$state" && : > "$state/$1.done"; }
is_done()   { [ -f "$state/$1.done" ]; }

say "SiliconForest Setup (Terminal)"
echo "This finishes installing SiliconForest. macOS and your files are not changed."

# R10: gate, fail closed.
if [ "${SF_TEST_MODE:-0}" != 1 ]; then
  [ -e /System/Installation/CDIS ] || fail "This isn't recoveryOS. Shut down, then hold the power button and choose SiliconForest."
  [ "$(id -u)" -eq 0 ] || fail "SiliconForest Setup must run as the recoveryOS user."
fi
[ -f "$plan" ] || fail "The installer's plan is missing from this volume ($plan)."
vgid="$("$DISKUTIL" info -plist "$system" | plutil -extract APFSVolumeGroupID raw -o - - 2>/dev/null)"
[ -n "$vgid" ] || fail "Couldn't find this volume's group."
policy="$("$BPUTIL" -d -v "$vgid" 2>&1)"
case "$policy" in
  *"one true recoveryOS"*) ;;
  *) fail "This is not SiliconForest's own recovery. Shut down, then hold the power button until you see startup options, and choose SiliconForest." ;;
esac
case "$policy" in *Paired*) ;; *) fail "This recovery isn't paired with SiliconForest." ;; esac
done_step R10

# R20: permissive security for this volume group only (bputil asks for the owner's password).
if ! is_done R20; then
  say "Step 1 of 3: allow SiliconForest to start (enter your Mac password when asked)"
  "$BPUTIL" -nc -v "$vgid" || fail "Security settings weren't changed (bputil failed)."
  "$BPUTIL" -d -v "$vgid" 2>&1 | grep -q "Permissive" || fail "The security policy didn't change to Permissive."
  done_step R20
fi

# R30: install the custom boot object.
if ! is_done R30; then
  say "Step 2 of 3: install SiliconForest's startup software"
  "$KMUTIL" configure-boot -c "$here/boot.bin" --raw --entry-point 2048 --lowest-virtual-address 0 -v "$system" \
    || fail "The startup software wasn't installed (kmutil failed)."
  done_step R30
fi

# R40: markers.
if ! is_done R40; then
  [ -f "$system/.IAPhysicalMedia" ] && mv "$system/.IAPhysicalMedia" "$system/IAPhysicalMedia-disabled.plist"
  core="$system/System/Library/CoreServices"
  [ -f "$core/SystemVersion.plist.sf-hidden" ] && mv "$core/SystemVersion.plist.sf-hidden" "$core/SystemVersion.plist"
  done_step R40
fi

# R50: SiliconForest starts next time only; the previous default stays the default (D5).
if ! is_done R50; then
  say "Step 3 of 3: start SiliconForest once"
  "$BLESS" --mount "$system" --setBoot --nextonly || fail "Couldn't choose SiliconForest for the next startup."
  done_step R50
fi

say "Done. Your Mac will restart into SiliconForest."
printf 'Press Return to restart.\n'
read -r _
exec "$REBOOT"
