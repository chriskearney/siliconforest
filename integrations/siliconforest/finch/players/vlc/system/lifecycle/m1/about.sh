# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# "About <app>" from the app's menu (the desk's strip inside the window), for Apple's Terminal and Activity Monitor:
# the panel appears (a new window of the app), is closed by its title-bar Close button, opens again, closes; quit by process
req "list $T-l0\n" > /dev/null; say "to Space 2: $(space_next)"
open_about() { # <main window> <tag>: click the app menu's title, then its first row
  set -- $1 $2 $(wrect $1); click $(( $3 + 45 )) $(( $4 + 17 )) 900; m=$(newest_shell_rect); say "app menu at: $m"; cap $T-$2-menu 50
  set -- $m; [ -n "$4" ] || return 1; click $(( $1 + 80 )) $(( $2 + ${ROW1:-47} )) 2200; }
about_win() { req "list $T-ab\n" 30 > /dev/null; grep '^window' $D/$T-ab.txt | grep "app_id=\"$1\"" | grep 'mapped=true' | while read -r line; do id=$(echo "$line" | cut -d' ' -f2); [ "$id" = "$2" ] && continue; grep -q "^window $id " $D/$T-l0.txt || echo "$line"; done | tail -1; }
close_btn() { echo "$1" | grep -o '("Close", [0-9]*, [0-9]*)' | grep -o '[0-9][0-9]*' | tr '\n' ' '; }
about_check() { # <label> <app id> <main window>
  for round in 1 2; do
    open_about $3 $1-$round; a=$(about_win $2 $3); id=$(echo "$a" | cut -d' ' -f2)
    title=$(echo "$a" | sed -E 's/.* title="([^"]*)".*/\1/'); r=$(echo "$a" | rect)
    ok "$1 About panel appears, round $round (window ${id:-none} \"$title\" $r)" '[ -n "$id" ]'
    cap $T-$1-about$round 300
    [ -n "$id" ] || { esc_all $3; continue; }
    set -- $1 $2 $3 $(close_btn "$a"); [ -n "$5" ] && click $4 $5 1200
    a2=$(about_win $2 $3); ok "$1 About panel closed by its Close button, round $round" '[ -z "$a2" ]'
  done; }
esc_all() { req "target $1\nkey 29 down\nkey 29 up\nwait 300\n" 50 > /dev/null; }
term_start; WT=$(win $T com.apple.Terminal 40); ok "Terminal window mapped ($WT)" '[ -n "$WT" ]'
[ -n "$WT" ] && { mods_clear $WT > /dev/null; sleep 2; about_check term com.apple.Terminal $WT; }
SET=$(tree "$(cat $W/term.pid 2>/dev/null)"); quit_set "$(cat $W/term.pid 2>/dev/null)" 15 $SET
am_start; WA=$(win $T com.apple.ActivityMonitor 40); ok "Activity Monitor window mapped ($WA)" '[ -n "$WA" ]'
[ -n "$WA" ] && { mods_clear $WA > /dev/null; sleep 3; about_check am com.apple.ActivityMonitor $WA; }
SET=$(tree "$(cat $W/am.pid 2>/dev/null)"); quit_set "$(cat $W/am.pid 2>/dev/null)" 15 $SET
say "back to Space 1: $(space_back)"
