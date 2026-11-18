#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# The guest of sf_vlc_system.sh qemu (through ../../../../m1-storage/tools/dr_qemu_userland.sh): the rehearsal of
# VLC's system install (docs/roadmap/issues/SF-AH-vlc.md, "Proposal") on the M1's root image.
# First boot: the state of every path the stage names (snapshot), the checks on the system as it is, then each
# step forward with the checks after it, then every step back (sf_vlc_restore.sh back), the checks and a
# snapshot that must equal the first, then the six steps forward again, left installed. Second boot (the root
# the first left): the checks on the system with the six steps as it starts, then every step back, the checks,
# and the last snapshot; the host compares the root images file by file (sf_vlc_system.sh compare).
# The checks: sf-vlc-features-probe (what of the six steps the system has), the probes of the replaced core
# files, ls and sh, the programs, and VLC itself without a desktop (dummy interface, video and audio outputs:
# it plays two seconds of a clip and quits), with only what its launcher keeps after a system install. VLC's bundle
# has no plugins.dat: with --no-plugins-scan it loads no plugin at all and exits 1 without a word (seen in r6, and on
# the M1 with the private prefix), so the plugins are scanned.
PATH=/bin:/sbin:/usr/bin:/usr/sbin; export PATH
echo QDDESK_BEGIN
T=/usr/share/sf-test
bad=0; ok() { if eval "$2"; then echo "VLCSYS_VERDICT ok   $1"; else echo "VLCSYS_VERDICT FAIL $1"; bad=$((bad + 1)); fi; }
sh /usr/share/sf-userland/sf-userland-install.sh /usr/share/sf-userland / 2>&1 | grep -E 'done|rc=|FAIL' | sed 's/^/VLCSYS_INSTALL /'
for d in /dev/disk0s1 /dev/disk1s1 /dev/disk2s1 /dev/disk3s1; do
    [ -b "$d" ] || continue
    if mount -t ext4 "$d" /opt/homebrew 2>/dev/null; then [ -d /opt/homebrew/Cellar ] && break; umount /opt/homebrew; fi
done
mkdir -p /private/var/db /private/tmp
cd /var/root
V=$T/vlc; R=/private/var/db/sfvlc-system; PY=/opt/homebrew/bin/python3
PROGRAMS="/opt/homebrew/bin/node /usr/local/bin/claude /opt/homebrew/bin/python3 /opt/homebrew/bin/bash /opt/homebrew/bin/git /opt/homebrew/bin/vim /opt/homebrew/bin/nvim /opt/homebrew/bin/tmux"
features() {  # <expected steps installed, e.g. "1 2 3"> <label>
    want=$1; label=$2
    $T/sf-vlc-features-probe > /private/tmp/f.out 2>&1; rc=$?
    sed "s/^/VLCSYS_FEATURE $label: /" /private/tmp/f.out | grep -E 'SFVLCFEATURE|SFVLCLOADERROR'
    wrong=0
    while read -r tag step name yes; do
        [ "$tag" = SFVLCFEATURE ] || continue
        [ "$step" = 3 ] && continue                 # QuartzCore loads either way
        [ "$yes" = unloadable ] && { echo "VLCSYS_FEATURE $label: step $step $name not judged: the framework does not load in this root"; continue; }
        case " $want " in *" $step "*) e=yes;; *) e=no;; esac
        [ "$yes" = "$e" ] || { wrong=$((wrong + 1)); echo "VLCSYS_FEATURE $label: step $step $name is $yes, expected $e"; }
    done < /private/tmp/f.out
    ok "features $label: rc $rc, every change as expected (installed: ${want:-none})" '[ "$rc" = 0 ] && [ "$wrong" = 0 ]'
}
programs() {  # <label> [quick]: ls, sh, the probes of the core files, and (unless quick) the programs
    label=$1; quick=${2:-}
    /bin/ls / > /dev/null 2>&1; rc=$?; ok "ls ($label)" '[ "$rc" = 0 ]'
    [ "$(/bin/sh -c 'echo x | cat' 2>&1)" = x ]; rc=$?; ok "sh with a pipe ($label)" '[ "$rc" = 0 ]'
    for p in $T/sf-kvo-probe $T/sf-libsystem26-probe $T/sf-corefoundation-framework-probe $T/sf-foundation-framework-probe; do
        [ -x $p ] || continue
        $p > /private/tmp/p.out 2>&1; rc=$?
        echo "VLCSYS_PROBE $label $(basename $p) rc=$rc $(tail -n 1 /private/tmp/p.out | cut -c1-200)"
    done
    [ -n "$quick" ] && return 0
    for p in $PROGRAMS; do
        [ -x "$p" ] || continue
        v=--version; [ "$(basename "$p")" = tmux ] && v=-V
        "$p" $v > /private/tmp/p.out 2>&1 < /dev/null; rc=$?
        # the status a program had before anything of VLC's was installed is the one expected (vim does not start
        # in the rehearsal's root at all)
        b=/private/var/db/vlcsys-rc-$(basename "$p"); [ -e $b ] || echo $rc > $b
        ok "$(basename "$p") $v ($label): status $rc, before $(cat $b)" '[ "$rc" = "$(cat $b)" ]'
    done
}
vlc() {  # <expected: plays|fails> <label>
    want=$1; label=$2
    rm -f /private/tmp/vlc.out
    mkdir -p /private/tmp/vlchome; chown 501:20 /private/tmp/vlchome
    ( cd / && env HOME=/private/tmp/vlchome DYLD_FRAMEWORK_PATH=$V/Frameworks $PY -c 'import os, sys; os.setgid(20); os.setuid(501); os.execv(sys.argv[1], sys.argv[1:])' \
        $V/VLC.app/Contents/MacOS/VLC -I dummy --no-video-title-show --vout=dummy --aout=dummy --codec=avcodec \
        --play-and-exit --stop-time=2 $V/clip.mp4 > /private/tmp/vlc.out 2>&1 < /dev/null ) &
    pid=$!; n=0
    while kill -0 $pid 2>/dev/null && [ $n -lt 600 ]; do sleep 1; n=$((n + 1)); done
    kill -0 $pid 2>/dev/null && { kill -9 $pid; echo "VLCSYS_VLC $label: still running after 600 s, stopped"; }
    wait $pid; rc=$?
    echo "VLCSYS_VLC $label: rc=$rc after ${n} s; $(grep -c . /private/tmp/vlc.out) lines; first: $(head -n 3 /private/tmp/vlc.out | tr '\n' '|' | cut -c1-300) last: $(tail -n 1 /private/tmp/vlc.out | cut -c1-200)"
    if [ "$want" = plays ]; then ok "VLC plays two seconds without a desktop and quits ($label)" '[ "$rc" = 0 ]'
    else ok "VLC does not start, as before the install ($label)" '[ "$rc" != 0 ] && grep -Eq "Symbol not found|Library not loaded|symbol" /private/tmp/vlc.out'; fi
}
snap() { sh $T/sf_vlc_restore.sh snapshot $V/stage "$1"; echo "VLCSYS_SNAPSHOT $1: $(grep -c . "$1") lines, sha256 $(sha256sum "$1" | cut -c1-16)"; }
same() {  # <a> <b> <label>: the snapshots agree but for the sha256 read of a file in use (inode, mode, owner, size compared)
    awk '{ if ($2 == "file") print $1, $2, $3, $4, $5, $6, $7; else print }' "$1" > /private/tmp/s1
    awk '{ if ($2 == "file") print $1, $2, $3, $4, $5, $6, $7; else print }' "$2" > /private/tmp/s2
    d=$(diff /private/tmp/s1 /private/tmp/s2 | grep -c '^[<>]')
    diff /private/tmp/s1 /private/tmp/s2 | head -n 20 | sed "s/^/VLCSYS_DIFF $3: /"
    h=$(diff "$1" "$2" | grep -c '^[<>]')
    ok "$3: every path as before (inode, mode, owner, size; $d lines differ), sha256 as read: $h lines differ" '[ "$d" = 0 ]'
}
forward_all() {  # <label>
    have=
    for n in 1 2 3 4 5 6; do
        sh $T/sf_vlc_restore.sh forward $V/stage $n < /dev/null 2>&1 | sed "s/^/VLCSYS_FORWARD $1 /"
        ok "step $n installed ($1)" '[ -e $R/step$n.done ]'
        have="$have $n"
        for f in $(awk '$1 == "f" {print $2}' $V/stage/step$n/list); do
            [ "$(sha256sum "$f" | cut -c1-64)" = "$(awk -v p="$f" '$2 == p {print $3}' $V/stage/step$n/list)" ] || echo "VLCSYS_FORWARD $1 $f is not the staged file"
        done
        features "$have" "after step $n ($1)"
        programs "after step $n ($1)" quick
    done
}
if [ ! -e /etc/vlcsys-first-done ]; then
    echo "VLCSYS_BOOT first: the M1's system, nothing of VLC's install"
    snap /private/var/db/vlcsys-0.txt
    features "" "before"
    programs "before"
    vlc fails "before"
    forward_all "first"
    programs "with the six steps"
    vlc plays "with the six steps"
    sh $T/sf_vlc_restore.sh back < /dev/null 2>&1 | sed 's/^/VLCSYS_BACK first /'
    ok "every step put back (first)" '[ ! -s $R/order ]'
    features "" "after the way back"
    programs "after the way back"
    vlc fails "after the way back"
    snap /private/var/db/vlcsys-1.txt
    same /private/var/db/vlcsys-0.txt /private/var/db/vlcsys-1.txt "forward and back in one boot"
    forward_all "again"
    touch /etc/vlcsys-first-done
else
    echo "VLCSYS_BOOT second: a fresh boot of the root the first boot left, the six steps installed"
    sh $T/sf_vlc_restore.sh status < /dev/null 2>&1 | grep -Ec ' file | absent ' | sed 's/^/VLCSYS_STATUS recorded paths: /'
    features "1 2 3 4 5 6" "fresh boot with the six steps"
    programs "fresh boot with the six steps"
    vlc plays "fresh boot with the six steps"
    sh $T/sf_vlc_restore.sh back < /dev/null 2>&1 | sed 's/^/VLCSYS_BACK second /'
    ok "every step put back (second)" '[ ! -s $R/order ]'
    features "" "after the way back (second boot)"
    programs "after the way back (second boot)"
    vlc fails "after the way back (second boot)"
    snap /private/var/db/vlcsys-2.txt
    same /private/var/db/vlcsys-0.txt /private/var/db/vlcsys-2.txt "forward, a boot, and back"
fi
sync; umount /opt/homebrew 2>/dev/null
echo "VLCSYS_VERDICT failed=$bad"
[ "$bad" = 0 ] && echo QDDESK_PASS
echo QDDESK_END
