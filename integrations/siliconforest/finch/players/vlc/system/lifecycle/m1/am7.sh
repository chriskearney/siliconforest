# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# Step 7's Activity Monitor extras: each menu of its strip opens and closes; quit by process
req "list $T-l0\n" > /dev/null; say "to Space 2: $(space_next)"
am_start; WA=$(win $T com.apple.ActivityMonitor 40); ok "Activity Monitor window mapped ($WA)" '[ -n "$WA" ]'; SET=$(tree "$(cat $W/am.pid 2>/dev/null)")
if [ -n "$WA" ]; then
  mods_clear $WA > /dev/null; sleep 4
  menu_oc $WA 87 app; menu_oc $WA 205 file; menu_oc $WA 269 edit; menu_oc $WA 339 view; menu_oc $WA 429 window; menu_oc $WA 518 help
fi
quit_set "$(cat $W/am.pid 2>/dev/null)" 15 $SET
say "back to Space 1: $(space_back)"
