# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# Step 7's Terminal extras: its menus open and close; Shell > New Tab and Shell > New Window (first profile of each
# submenu) open a tab and a window; a full-resolution text capture (term7-a); quit by process
req "list $T-l0\n" > /dev/null; say "to Space 2: $(space_next)"
term_start; WT=$(win $T com.apple.Terminal 40); ok "Terminal window mapped ($WT)" '[ -n "$WT" ]'; SET=$(tree "$(cat $W/term.pid 2>/dev/null)")
if [ -n "$WT" ]; then
  mods_clear $WT > /dev/null; sleep 2; typ $WT "$TY1" > /dev/null; sleep 1.5; cap $T-a 100
  menu_oc $WT 55 terminal; menu_oc $WT 149 shell; menu_oc $WT 219 edit; menu_oc $WT 289 view; menu_oc $WT 375 window
  n0=$(for p in $(tree "$(cat $W/term.pid 2>/dev/null)"); do ps -o command= -p $p; done | grep -c "zsh -f -i")
  menu_pick $WT 149 2 sub; sleep 1.5; n1=$(for p in $(tree "$(cat $W/term.pid 2>/dev/null)"); do ps -o command= -p $p; done | grep -c "zsh -f -i"); cap $T-newtab 50
  ok "Shell > New Tab: shells $n0 -> $n1" '[ "$n1" -gt "$n0" ]'
  w0=$(wins_of com.apple.Terminal); menu_pick $WT 149 1 sub; sleep 2; w1=$(wins_of com.apple.Terminal); cap $T-newwin 50
  ok "Shell > New Window: windows ($w0) -> ($w1)" '[ "$(nw $w1)" -gt "$(nw $w0)" ]'
  SET=$(tree "$(cat $W/term.pid 2>/dev/null)")
fi
say "processes of my Terminal: $(nw $SET)"
quit_set "$(cat $W/term.pid 2>/dev/null)" 15 $SET
say "back to Space 1: $(space_back)"
