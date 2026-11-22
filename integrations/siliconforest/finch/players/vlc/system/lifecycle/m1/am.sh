# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# Activity Monitor: opens, its tabs (clicked at AMX offsets from the window's left, AMY below its top), quits by process
req "list $T-l0\n" > /dev/null; say "to Space 2: $(space_next)"
am_start; WA=$(win $T com.apple.ActivityMonitor 40); ok "Activity Monitor window mapped ($WA)" '[ -n "$WA" ]'
SET=$(tree "$(cat $W/am.pid 2>/dev/null)")
if [ -n "$WA" ]; then
  mods_clear $WA > /dev/null; sleep 5; set -- $(wrect $WA); x=$1; y=$2; say "window $WA at $*"; cap $T-a 100
  n=1; for o in ${AMX:-}; do click $(( x + o )) $(( y + ${AMY:-60} )) 2200; cap $T-tab$n 100; n=$((n+1)); done
  SET=$(tree "$(cat $W/am.pid 2>/dev/null)")
fi
say "processes of my Activity Monitor: $(nw $SET)"
quit_set "$(cat $W/am.pid 2>/dev/null)" 15 $SET
say "back to Space 1: $(space_back)"
