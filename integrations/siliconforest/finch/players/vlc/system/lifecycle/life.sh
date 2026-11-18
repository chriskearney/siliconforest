#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# SYSINSTALL: the lifecycle set (SF-AH proposal) as five gui.lock holds: Firefox, Terminal + the four themes, Activity
# Monitor, VLC (12 drags recorded, fullscreen), QuickTime (QTP2's set).   life.sh <label> [ff term am vlc qt]
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd); LAB=${SF_LAB:-$(cd "$HERE" && cd "$(git rev-parse --git-common-dir)/.." && pwd)}
H=$LAB/runs/sysinstall; L=${1:?label}; shift; P=${*:-ff term am about vlc qt}
AMX=${AMX:-512 674 818 968 364}; AMY=${AMY:-61}; export STEP=$L
for p in $P; do
  case $p in
  ff) CAP=200 bash $HERE/m1.sh $L-ff "lifecycle $L: my Firefox (own profile and home): page, video, second window, quit by process" $HERE/m1/ff.sh;;
  term) CAP=200 bash $HERE/m1.sh $L-term "lifecycle $L: my Terminal (two tabs, typing), the four themes (owner's look put back), quit by process" $HERE/m1/term.sh;;
  am) { echo "AMX='$AMX'; AMY='${AMY:-60}'"; cat $HERE/m1/am.sh; } > $H/work/am-$L.sh; CAP=150 bash $HERE/m1.sh $L-am "lifecycle $L: my Activity Monitor, its tabs, quit by process" $H/work/am-$L.sh;;
  vlc) CAP=260 bash $HERE/m1.sh $L-vlc "lifecycle $L: VLC through /Applications/VLC.app, 3-min clip, hardware decoding, Half Size and Normal Size recorded (no drags), full screen and back, TERM" $HERE/m1/vlc.sh && python3 $HERE/vlcrec.py $L-vlc | tee $H/work/out-$L-vlcrec.txt;;
  about) CAP=200 bash $HERE/m1.sh $L-about "lifecycle $L: About <app> in my Terminal and my Activity Monitor (appears, closes, reopens), quit by process" $HERE/m1/about.sh;;
  ff7) CAP=240 bash $HERE/m1.sh $L-ff7 "lifecycle $L: my Firefox: menus, full screen in and out, quit from its menu" $HERE/m1/ff7.sh;;
  term7) CAP=200 bash $HERE/m1.sh $L-term7 "lifecycle $L: my Terminal: menus, Shell > New Tab and New Window, full-resolution text" $HERE/m1/term7.sh;;
  am7) CAP=150 bash $HERE/m1.sh $L-am7 "lifecycle $L: my Activity Monitor: its menus" $HERE/m1/am7.sh;;
  qt7s) { echo "QAPPKIT=system"; cat $HERE/m1/qt7.sh; } > $H/work/qt7s-$L.sh; CAP=240 bash $HERE/m1.sh $L-qt7s "lifecycle $L: QuickTime on the SYSTEM AppKit (qtp_m1.py appkit system, then private again): play, panel, full screen, About, Open Recent" $H/work/qt7s-$L.sh;;
  qt7p) { echo "QAPPKIT=private"; cat $HERE/m1/qt7.sh; } > $H/work/qt7p-$L.sh; CAP=240 bash $HERE/m1.sh $L-qt7p "lifecycle $L: QuickTime on QTP2's private AppKit: play, panel, full screen, About, Open Recent" $H/work/qt7p-$L.sh;;
  qt) CAP=150 bash $HERE/m1.sh $L-qt "lifecycle $L: QuickTime Player from QTP2's private set (own home): launch, play, stop" $HERE/m1/qt.sh;;
  esac
  sleep 5
done
grep -a -h '^LIFE\|^VLCREC' $H/work/out-$L-*.txt 2>/dev/null | grep -c PASS | sed "s/^/$L: PASS lines /"; grep -a -h '^LIFE.*FAIL' $H/work/out-$L-*.txt
