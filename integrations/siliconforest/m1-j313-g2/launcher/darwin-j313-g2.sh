#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
#
# Guest side of the first J313 RAM boot (G2/G3). Console only: no compositor, GPU, sound or Touch
# Bar. It stops first if anything has attached to the NVMe controller, reports what it finds,
# asks the person at the Air to use the trackpad, then leaves a shell for typing until the time is
# up. Nothing here is written outside the RAM root. A Wi-Fi scan reports only a count, so nearby
# network names stay out of the log.
nonce=${1:-none}
PATH=/bin:/sbin:/usr/bin:/usr/sbin; export PATH
SESSION=@SECONDS@
TRACKPAD=30
get() { sysctl -n "$1" 2>/dev/null; }
printf '\nG2_BEGIN_%s seconds=%s\n' "$nonce" "$SESSION"

# Ends the session (exit 97, end marker) if a driver is on the NVMe controller.
. /usr/bin/rb-prologue

printf 'G2_ID %s %s %s\n' "$(uname -s)" "$(uname -m)" "$(uname -r)"
printf 'G2_ROOT %s\n' "$(mount | head -1)"

# Heat, every 20 s for the whole session. The Air has no fan.
(
    while :; do
        printf 'G2_THERMAL valid=%s die_mc=%s\n' "$(get kern.sf_thermal.valid)" "$(get kern.sf_thermal.die_mc)"
        sleep 20
    done
) &
thermal=$!

# Wi-Fi: the driver and this Air's firmware. Scan only, never join.
n=0
until wifiutil info 2>/dev/null | grep -q '^interface: *en0'; do
    n=$((n + 1)); [ "$n" -le 100 ] || break; sleep 0.2
done
if [ "$n" -le 100 ]; then
    wifiutil on > /dev/null 2>&1
    sleep 2
    printf 'G2_WIFI interface=en0 scan_lines=%s\n' "$(wifiutil scan 2>/dev/null | wc -l | tr -d ' ')"
else
    printf 'G2_WIFI interface=none\n'
fi

n=0
while [ ! -c /dev/usb_hid_kbd ] || [ ! -c /dev/usb_hid_mouse ]; do
    n=$((n + 1)); [ "$n" -le 100 ] || break; sleep 0.1
done
# Listed, never opened: opening the keyboard device would take it from the text console.
printf 'G2_INPUT kbd=%s mouse=%s\n' "$([ -c /dev/usb_hid_kbd ] && echo yes || echo no)" \
    "$([ -c /dev/usb_hid_mouse ] && echo yes || echo no)"

if [ -c /dev/usb_hid_mouse ]; then
    printf '\n>>> TRACKPAD: move a finger on the trackpad for %s seconds <<<\n' "$TRACKPAD"
    dd if=/dev/usb_hid_mouse of=/private/tmp/g2-trackpad bs=64 2>/dev/null &
    reader=$!
    sleep "$TRACKPAD"
    kill "$reader" 2>/dev/null
    wait "$reader" 2>/dev/null
    printf 'G2_TRACKPAD bytes=%s\n' "$(wc -c < /private/tmp/g2-trackpad 2>/dev/null | tr -d ' ')"
fi

left=$((SESSION - TRACKPAD - 15))
[ "$left" -ge 30 ] || left=30
printf '\n>>> KEYBOARD: type  uname -a  and press Return. You have about %s seconds. <<<\n' "$left"
printf 'G2_READY_FOR_PERSON_%s\n' "$nonce"
(
    sleep "$left"
    kill "$thermal" 2>/dev/null
    printf '\nG2_END_%s\n' "$nonce"
    # ends the capture; the M5 then returns the Air to Linux
    printf '\nPD_BENCH_DONE\n'
) &
exit 0
