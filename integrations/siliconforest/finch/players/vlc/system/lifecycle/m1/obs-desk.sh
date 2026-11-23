# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# BAKEIN observe pass: desktop basics without test-inject: the four themes through --desktop-request (a capture each),
# the theme and wallpaper copied at the start of this pass put back (state_save -> $W/state-owner, not a literal
# theme name and not the live theme file), the state files compared; the dock's process and its pins file
# unchanged. Resize drags and dock clicks need the test-inject compositor: reported as SKIP.
. $W/obs.sh; obs_mark; state_save; pins0=$(shasum -a 256 $ST/dock 2>/dev/null | cut -c1-16); dk0=$(pgrep -x chonkstep-dock)
scap before
for th in sf-clearing sf-canopy sf-wafer sf-dieshot; do r=$($(BIN) --desktop-request theme $th 2>&1 | tail -1); sleep 2.5
  got=$(obs_since | grep -a WMSET | tail -1 | cut -c1-120); ok "theme $th applied ($r; $got)" 'echo "$got" | grep -q "theme=$th"'; scap th-$th; done
# $own is the theme file copied at the start of this pass. The loop above rewrites the live theme; this does not.
own=$(cat $W/state-owner/theme); say "owner's theme back: $($(BIN) --desktop-request theme $own 2>&1 | tail -1)"
wp=$(cat $W/state-owner/wallpaper 2>/dev/null); [ -n "$wp" ] && say "owner's wallpaper back: $($(BIN) --desktop-request wallpaper $wp 2>&1 | tail -1)"; sleep 2.5
scap after; state_check
ok "theme file is the owner theme ($own)" '[ "$(cat $ST/theme)" = "$own" ]'
ok "dock process unchanged ($dk0) and dock state unchanged" '[ "$(pgrep -x chonkstep-dock)" = "$dk0" ] && [ "$(shasum -a 256 $ST/dock 2>/dev/null | cut -c1-16)" = "$pins0" ]'
say "SKIP resize drags: need the test-inject compositor (synthetic pointer) or a person at the M1"
say "SKIP dock clicks: need the test-inject compositor or a person (the dock's launch path is --desktop-request application, exercised by the app passes)"
obs_metrics
ok "desktop and dock still the same processes (desk $DESK0)" desk_ok
