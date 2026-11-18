# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# Step 7's QuickTime check (QTP2's private set, runs/qtp/FOR-DEMO.md): with QAPPKIT=system the prefix's AppKit stands
# on the SYSTEM AppKit (qtp_m1.py appkit system), with QAPPKIT=private on QTP2's own; play (space), the panel's skip
# forward and play/pause, full screen by its button (the strip hidden, shown at the top edge), Esc back, About QuickTime
# Player (its first menu, first row), File > Open Recent (row QROW, its second entry: the movie opened in an earlier
# run in the same HOME, not the one open now) opens a window; stop by process
B=/private/var/db/sfqtp/load-20261118T091237Z; QH=$W/home-qt7; QT() { (cd $B && env QTP_BUNDLE=$B /opt/homebrew/bin/python3 $B/qtp_m1.py "$@" 2>&1 | tail -2 | tr '\n' ' '); }
ln -sf "/Users/sf/Movies/Big Buck Bunny (3 min).mp4" $W/bbb-3min.mp4
req "list $T-l0\n" > /dev/null; say "to Space 2: $(space_next)"
say "appkit ${QAPPKIT:-system}: $(QT appkit ${QAPPKIT:-system})"; mkdir -p $QH; a0=$(avd)
say "launch: $(QT launch sysi-$T ARGS=-NSOpen+$W/bbb-3min.mp4 HOME=$QH CFFIXED_USER_HOME=$QH)"
sleep 9; req "list $T-q\n" 30 > /dev/null
WQ=$(grep '^window' $D/$T-q.txt | grep 'app_id="com.apple.QuickTimePlayerX"' | grep 'mapped=true' | cut -d' ' -f2 | sort -n | tail -1)
ok "QuickTime window mapped ($WQ $(wrect $WQ))" '[ -n "$WQ" ]'
if [ -n "$WQ" ]; then
  mods_clear $WQ > /dev/null; typ $WQ "$SPACE" > /dev/null; sleep 3; a1=$(avd); cap $T-a 50
  ok "plays (decoder jobs $a0 -> $a1)" '[ "$a1" -gt $(( a0 + 30 )) ]'
  set -- $(wrect $WQ); cx=$(( $1 + $3 / 2 )); by=$(( $2 + $4 - 90 ))   # the panel: centre of the window, 90 px above its bottom
  park $(( cx + 70 )) $by 400; click $(( cx + 70 )) $by 1500; cap $T-skip 50
  park $cx $by 400; click $cx $by 2500; p0=$(avd); sleep 2; p1=$(avd); cap $T-paused 50
  ok "paused by the panel's play/pause (jobs $p0 -> $p1 in 2 s)" '[ $(( p1 - p0 )) -lt 10 ]'
  park $cx $by 400; click $cx $by 1500; r0=$(avd); sleep 2; r1=$(avd)
  ok "playing again by the same button (jobs $r0 -> $r1)" '[ $(( r1 - r0 )) -gt 20 ]'
  park $(( cx + 322 )) $by 400; click $(( cx + 322 )) $by 3000; req "list $T-fs\n" 30 > /dev/null
  FS=$(grep '^window' $D/$T-fs.txt | grep 'app_id="com.apple.QuickTimePlayerX"' | grep 'mapped=true' | grep -E 'size: Size \{ w: 25[0-9][0-9], h: 1[5-6][0-9][0-9]' | cut -d' ' -f2 | tail -1)
  park 1300 800 3500; cap $T-fs 50; req "abs $(ax 1300) $(ay 1)\nwait 1200\n" 50 > /dev/null; cap $T-fs-top 50
  ok "full screen by the panel's button ($FS)" '[ -n "$FS" ]'
  park 1300 900 600; park 1602 1510 400; click 1602 1510 3000; park 1300 800 300; cap $T-fsback 50
  fb=$(wrect $WQ); fbw=$(echo $fb | cut -d' ' -f3); ok "out of full screen by the panel's button ($fb)" '[ "${fbw:-9999}" -lt 2560 ]'
  req "target $WQ\n${SPACE}wait 500\n" 50 > /dev/null
  set -- $(wrect $WQ); click $(( $1 + ${QAPPX:-168} )) $(( $2 + 17 )) 900; m=$(newest_shell_rect); cap $T-qtmenu 50; set -- $m
  [ -n "$4" ] && click $(( $1 + 80 )) $(( $2 + 47 )) 2500
  req "list $T-ab\n" 30 > /dev/null; AB=$(grep '^window' $D/$T-ab.txt | grep 'app_id="com.apple.QuickTimePlayerX"' | grep 'mapped=true' | grep -v "^window $WQ " | while read -r line; do id=$(echo "$line" | cut -d' ' -f2); grep -q "^window $id " $D/$T-l0.txt || echo "$line"; done | tail -1)
  cap $T-about 100; ok "About QuickTime Player panel ($(echo "$AB" | cut -d' ' -f2) $(echo "$AB" | rect))" '[ -n "$AB" ]'
  [ -n "$AB" ] && { set -- $(echo "$AB" | grep -o '("Close", [0-9]*, [0-9]*)' | grep -o '[0-9][0-9]*'); [ -n "$2" ] && click $1 $2 1200; }
  [ -n "${QCAL:-}" ] && { set -- $(wrect $WQ); click $(( $1 + ${QFILEX:-224} )) $(( $2 + 17 )) 900; say "file menu: $(newest_shell_rect)"; cap $T-filemenu 50; req "target $WQ\nkey 29 down\nkey 29 up\nwait 500\n" 50 > /dev/null; }
  [ -n "${QCAL:-}" ] || { w0=$(wins_of com.apple.QuickTimePlayerX); menu_pick $WQ ${QFILEX:-224} ${QROW:-+263} sub 2; sleep 4; w1=$(wins_of com.apple.QuickTimePlayerX); cap $T-recent 100
  ok "File > Open Recent opens a window ($w0 -> $w1)" '[ "$(nw $w1)" -gt "$(nw $w0)" ]'; }
fi
say "stop: $(QT stop sysi-$T)"; sleep 1
ok "no QuickTime process left" '[ -z "$(pgrep -f "QuickTime Player.app/Contents/MacOS")" ]'
say "appkit back to private: $(QT appkit private)"
say "back to Space 1: $(space_back)"
