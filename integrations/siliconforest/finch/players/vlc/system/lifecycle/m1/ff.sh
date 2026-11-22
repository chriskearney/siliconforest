# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# Firefox: starts, loads a page, plays a video, opens and closes a second window, quits from its own menu (Firefox >
# Quit Firefox; TERM only after 10 s) with no process left
req "list $T-l0\n" > /dev/null; say "to Space 2: $(space_next)"
a0=$(avd); ff_start https://en.wikipedia.org/wiki/XNU file://$W/video.html
WF=$(win $T org.mozilla.firefox 60); ok "Firefox window mapped ($WF)" '[ -n "$WF" ]'
SET=$(tree "$(cat $W/ff.pid 2>/dev/null)")
if [ -n "$WF" ]; then
  mods_clear $WF > /dev/null; sleep 7; SET=$(tree "$(cat $W/ff.pid 2>/dev/null)")
  t1=$(title_of $WF); say "title tab 1: $t1"; cap $T-a 100
  ok "a web page loaded (title names XNU)" 'echo "$t1" | grep -q XNU'
  say "RECT $(wrect $WF)"; set -- $(wrect $WF); cx=$(( $1 + $3 / 2 )); cy=$(( $2 + $4 / 2 ))
  req "abs $(ax $cx) $(ay $cy)\nwait 150\nwheel -1\nwait 40\nwheel -1\nwait 40\nwheel -1\nwait 40\nwheel -1\nwait 40\nwheel -1\nwait 40\nwheel -1\nwait 40\nwheel -1\nwait 40\nwheel -1\nwait 900\ncapture $T-s1\nwheel -1\nwait 40\nwheel -1\nwait 40\nwheel -1\nwait 40\nwheel -1\nwait 900\ncapture $T-s2\n" 200 | cut -c1-60
  CW=1500 chord $WF $WF 1f e3 > /dev/null; sleep 2.5; a1=$(avd); cap $T-b 50; sleep 2; cap $T-c 50; a2=$(avd)
  t2=$(title_of $WF); say "title tab 2: $t2"
  ok "video plays through the hardware decoder (jobs $a0 -> $a1 -> $a2)" '[ "$a2" -gt "$a1" ] && [ "$a1" -gt "$a0" ]'
  CW=2500 chord $WF $WF 11 e3 > /dev/null; ids=$(wins_of org.mozilla.firefox); W2=$(echo $ids | tr ' ' '\n' | grep -v "^$WF\$" | tail -1)
  ok "second window opened (my Firefox windows: $ids)" '[ "$(nw $ids)" = 2 ] && [ -n "$W2" ]'
  cap $T-d 300
  [ -n "$W2" ] && { CW=1500 chord $W2 $WF 1a e3 > /dev/null; sleep 1; }
  ids=$(wins_of org.mozilla.firefox); ok "second window closed (my Firefox windows: $ids)" '[ "$(nw $ids)" = 1 ]'
  cap $T-e 200; SET=$(tree "$(cat $W/ff.pid 2>/dev/null)")
fi
say "processes of my Firefox: $(nw $SET): $(for p in $SET; do ps -o comm= -p $p | sed "s|.*/||"; done | sort | uniq -c | tr -s ' ' | tr '\n' ',')"
main=$(for p in $SET; do ps -o pid=,command= -p $p; done | grep -F "Contents/MacOS/firefox" | grep -v -e contentproc -e surface-session | awk '{print $1}' | head -1)
if [ -n "$WF" ]; then quit_menu $WF "${main:-$(cat $W/ff.pid 2>/dev/null)}" $SET; else quit_set "${main:-$(cat $W/ff.pid 2>/dev/null)}" 25 $SET; fi
left=$(procs "$FFP"); ok "no process with my profile left" '[ -z "$left" ]'
say "back to Space 1: $(space_back)"
