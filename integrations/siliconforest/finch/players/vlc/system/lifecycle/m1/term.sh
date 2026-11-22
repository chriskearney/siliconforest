# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# Apple's Terminal: opens, two tabs, typing; the four themes applied with it on screen (owner's look put back); quits by process
req "list $T-l0\n" > /dev/null; say "to Space 2: $(space_next)"
state_save; term_start; WT=$(win $T com.apple.Terminal 40); ok "Terminal window mapped ($WT)" '[ -n "$WT" ]'
SET=$(tree "$(cat $W/term.pid 2>/dev/null)")
if [ -n "$WT" ]; then
  mods_clear $WT > /dev/null; sleep 2; typ $WT "$TY1" > /dev/null; sleep 1
  CW=1800 chord $WT $WT 17 e3 > /dev/null; typ $WT "$TY2" > /dev/null; sleep 1.2; cap $T-a 100
  say "title: $(title_of $WT)"; n=$(for p in $(tree "$(cat $W/term.pid 2>/dev/null)"); do ps -o command= -p $p; done | grep -c "zsh -f -i")
  ok "two tabs, each with its shell ($n shells under my Terminal)" '[ "$n" -ge 2 ]'
  CW=900 chord $WT $WT 2f e3 e1 > /dev/null; cap $T-b 300
  for th in sf-clearing sf-canopy sf-wafer sf-dieshot; do say "theme $th: $(look $th)"; sleep 2.5; cap $T-th-$th 100; done
  say "owner's theme back: $(look $(cat $W/state-owner/theme))"
  wp=$(cat $W/state-owner/wallpaper 2>/dev/null); [ -n "$wp" ] && say "owner's wallpaper back: $($(BIN) --desktop-request wallpaper $wp 2>&1 | tail -1)"; sleep 2
  cap $T-c 100; SET=$(tree "$(cat $W/term.pid 2>/dev/null)")
fi
state_check
say "processes of my Terminal: $(nw $SET)"
quit_set "$(cat $W/term.pid 2>/dev/null)" 15 $SET
say "back to Space 1: $(space_back)"
