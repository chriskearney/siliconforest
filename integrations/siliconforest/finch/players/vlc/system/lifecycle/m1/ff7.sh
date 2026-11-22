# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# Step 7's Firefox extras: the strip's menus open and close; full screen in and out (Control-Command-F), the strip
# hidden in full screen and shown with the pointer at the top edge (AppKit 0362); quit from its menu
req "list $T-l0\n" > /dev/null; say "to Space 2: $(space_next)"
ff_start https://en.wikipedia.org/wiki/XNU
WF=$(win $T org.mozilla.firefox 60); ok "Firefox window mapped ($WF)" '[ -n "$WF" ]'; SET=$(tree "$(cat $W/ff.pid 2>/dev/null)")
if [ -n "$WF" ]; then
  mods_clear $WF > /dev/null; sleep 7; SET=$(tree "$(cat $W/ff.pid 2>/dev/null)"); before=$(wrect $WF)
  menu_oc $WF 45 firefox; menu_oc $WF 125 file; menu_oc $WF 189 edit; menu_oc $WF 262 view
  CW=2500 chord $WF $WF 09 e0 e3 > /dev/null; fs=$(wrect $WF); park 1300 800 1500; cap $T-fs 50
  req "abs $(ax 1300) $(ay 1)\nwait 1200\n" 50 > /dev/null; cap $T-fs-top 50; park 1300 800 1200
  fw=$(echo $fs | cut -d' ' -f3); fh=$(echo $fs | cut -d' ' -f4)
  ok "full screen ($before -> $fs)" '[ "${fw:-0}" -ge 2500 ] && [ "${fh:-0}" -ge 1500 ]'
  CW=2500 chord $WF $WF 09 e0 e3 > /dev/null; after=$(wrect $WF); cap $T-fsback 50
  ok "out of full screen ($after, before $before)" '[ "$after" = "$before" ]'
  main=$(for p in $SET; do ps -o pid=,command= -p $p; done | grep -F "Contents/MacOS/firefox" | grep -v -e contentproc -e surface-session | awk '{print $1}' | head -1)
  quit_menu $WF "${main:-$(cat $W/ff.pid 2>/dev/null)}" $SET
else quit_set "$(cat $W/ff.pid 2>/dev/null)" 25 $SET; fi
ok "no process with my profile left" '[ -z "$(procs "$FFP")" ]'
say "back to Space 1: $(space_back)"
