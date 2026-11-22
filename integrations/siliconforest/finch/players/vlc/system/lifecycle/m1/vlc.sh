# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# VLC: the 3-minute clip through /Applications/VLC.app (open -a, as the dock does) with hardware decoding; resized
# WITHOUT pointer drags (coordinator, 16:2xZ: drags then TERM leave VLC stuck in exit, SF-AH item 25): VLC's own
# Half Size (Command-0) and Normal Size (Command-1), recorded by the compositor; full screen by the control bar's
# button and back by Esc (as IOSURF's dsession.py); quit by TERM (no drag happened)
CLIP="/Users/sf/Movies/Big Buck Bunny (3 min).mp4"
req "list $T-l0\n" > /dev/null; say "to Space 2: $(space_next)"
[ -z "$(pgrep -x VLC)" ] || say "FAIL a VLC process is already running: $(pgrep -x VLC | tr '\n' ' ')"
a0=$(avd); ( cd /; env -i XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR WAYLAND_DISPLAY=wayland-0 PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin LANG=en_US.UTF-8 /usr/bin/open -a /Applications/VLC.app --args "$CLIP" --start-time=60 > $W/vlc-open.log 2>&1 < /dev/null ); sleep 1
WV=$(vlc_win $T 40); ok "VLC window mapped ($WV)" '[ -n "$WV" ]'; VP=$(pgrep -x VLC | head -1); SET=""; pid_ok "${VP:-}" && SET=$(tree "$VP")
say "VLC command: $(pid_ok "${VP:-}" && ps -o command= -p "$VP" 2>/dev/null | cut -c1-200 || echo 'not running')"
if [ -n "$WV" ]; then
  mods_clear $WV > /dev/null; sleep 4; a1=$(avd); cap $T-a 50
  ok "VLC plays through the hardware decoder (jobs $a0 -> $a1)" '[ "$a1" -gt $(( a0 + 60 )) ]'
  set -- $(wrect $WV); say "window $WV at $*"; big="$*"
  rec_start $T 14 1.0
  CW=2500 chord $WV $WV 27 e3 > /dev/null; set -- $(wrect $WV); half="$*"; say "RECT $*"; cap $T-half 50
  CW=2500 chord $WV $WV 1e e3 > /dev/null; set -- $(wrect $WV); normal="$*"; cap $T-normal 50
  rec_wait $T
  ok "resized by Half Size and Normal Size (open $big, half $half, normal $normal)" '[ "$half" != "$big" ] && [ "$normal" != "$half" ]'
  set -- $(wrect $WV); click $(( $1 + $3 - 37 )) $(( $2 + $4 - 29 )) 3500
  req "list $T-fs\n" 30 > /dev/null; FS=$(grep '^window' $D/$T-fs.txt | grep "app_id=\"$VLCAPP\"" | grep 'mapped=true' | grep -v 'Fullscreen Controls' | grep -E 'size: Size \{ w: 25[0-9][0-9], h: 1[5-6][0-9][0-9]' | cut -d' ' -f2 | tail -1)
  cap $T-fs 100; ok "full screen by the control bar's button ($FS)" '[ -n "$FS" ]'
  [ -n "$FS" ] && { typ $FS "$ESC" > /dev/null; sleep 3; }
  req "list $T-fb\n" 30 > /dev/null; back=$(grep "^window $WV " $D/$T-fb.txt | rect); cap $T-back 100
  fsm=$(grep "^window ${FS:-none} " $D/$T-fb.txt | grep -o 'mapped=[a-z]*')
  ok "back from full screen by Esc (window $WV mapped at $back; full-screen window ${FS:-none}: ${fsm:-gone})" 'grep "^window $WV " $D/$T-fb.txt | grep -q "mapped=true" && [ -n "$FS" ] && [ "$fsm" != "mapped=true" ]'
  a3=$(avd); ok "decoder still busy (jobs $a1 -> $a3)" '[ "$a3" -gt $(( a1 + 60 )) ]'
  pid_ok "${VP:-}" && SET=$(tree "$VP")
fi
say "processes of my VLC: $(nw $SET)"
if pid_ok "${VP:-}"; then quit_set "$VP" 15 $SET; else say "FAIL quit VLC: skipped (empty or unsafe pid '${VP:-none}')"; fi
ok "no VLC process left" '[ -z "$(pgrep -x VLC)" ]'
say "back to Space 1: $(space_back)"
