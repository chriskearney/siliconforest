# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# BAKEIN observe pass for one app (set by the header): APP=<key> launched once, its window seen in the session log,
# captures, metrics, quit by TERM, no relaunch. Keys: term am ff vlc qt pv te cc
. $W/obs.sh; obs_mark; a0=$(avd); WAIT=${WAIT:-12}; LP=""; EXPECT=""
case $APP in
term) ID=com.apple.Terminal; EXPECT='Terminal'; term_start; LP=$(cat $W/term.pid 2>/dev/null);;
am)   ID=com.apple.ActivityMonitor; EXPECT='Activity Monitor'; am_start; LP=$(cat $W/am.pid 2>/dev/null);;
ff)   ID=org.mozilla.firefox; EXPECT='firefox|Firefox'; ff_start "file://$W/video.html"; LP=$(cat $W/ff.pid 2>/dev/null); WAIT=20;;
vlc)  ID=org.videolan.vlc; EXPECT='VLC'; [ -z "$(pgrep -x VLC)" ] || say "FAIL a VLC process is already running"
      ( cd /; env -i XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR WAYLAND_DISPLAY=wayland-0 PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin LANG=en_US.UTF-8 /usr/bin/open -a /Applications/VLC.app --args "/Users/sf/Movies/Big Buck Bunny (3 min).mp4" --start-time=60 > $W/vlc-open.log 2>&1 < /dev/null ); sleep 3; LP=$(pgrep -x VLC | head -1);;
qt)   ID=com.apple.QuickTimePlayerX; EXPECT='QuickTime Player'; QB="/Applications/QuickTime Player.app"
      ( cd /; env -i XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR WAYLAND_DISPLAY=wayland-0 PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin LANG=en_US.UTF-8 /usr/bin/open -a "$QB" /Users/sf/Movies/bbb-1080p-h264-aac-30s.mp4 > $W/qt-open.log 2>&1 < /dev/null ); sleep 3
      LP=$(pgrep -f "QuickTime Player.app/Contents/MacOS/QuickTime Player" | head -1); WAIT=15;;
pv)   ID=com.apple.Preview; EXPECT='Preview|sf-open-preview'; DOC=/private/var/db/sfpreview-app/next-preview-20261119T003538Z/fixtures/reading.pdf
      ( cd /; env -i XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR WAYLAND_DISPLAY=wayland-0 LANG=en_US.UTF-8 /usr/bin/sf-open-preview "$DOC" > $W/pv.log 2>&1 < /dev/null & echo $! > $W/pv.pid ); sleep 1; LP=$(cat $W/pv.pid 2>/dev/null); WAIT=15;;
te)   ID=com.apple.TextEdit; EXPECT='TextEdit|sf-open-textedit'; DOC=/private/var/db/sftextedit/docs/03-textedit.rtf
      ( cd /; env -i XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR WAYLAND_DISPLAY=wayland-0 LANG=en_US.UTF-8 /usr/bin/sf-open-textedit "$DOC" > $W/te.log 2>&1 < /dev/null & echo $! > $W/te.pid ); sleep 1; LP=$(cat $W/te.pid 2>/dev/null); WAIT=15;;
cc)   ID=com.jetbrains.jbr.java; EXPECT='ChonkCraft|sf-open-chonkcraft'; CE=/private/var/db/sfchonkcraft/logs/app.err; E0=$(wc -c < $CE 2>/dev/null || echo 0)
      ( cd /; env -i XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR WAYLAND_DISPLAY=wayland-0 LANG=en_US.UTF-8 /usr/bin/sf-open-chonkcraft > $W/cc.log 2>&1 < /dev/null & echo $! > $W/cc.pid ); sleep 1; LP=$(cat $W/cc.pid 2>/dev/null); WAIT=25;;
esac
pid_matches_app() { pid_ok "${1:-}" || return 1; _c=$(ps -o command= -p "$1" 2>/dev/null); [ -n "$_c" ] && [ -n "$EXPECT" ] && echo "$_c" | grep -q -E "$EXPECT"; }
LP_CMD=""; pid_ok "${LP:-}" && LP_CMD=$(ps -o command= -p "$LP" 2>/dev/null | cut -c1-140)
say "launched $APP: pid ${LP:-none} (${LP_CMD:-not running})"
apps=$(obs_win $ID 60); ok "$APP window on the desktop (session log: $apps)" 'echo "$apps" | grep -q -F "\"$ID"'
sleep $WAIT
SET=""
if ! pid_ok "${LP:-}"; then
  say "SKIP tree $APP: empty or unsafe pid '${LP:-none}'"
elif pid_matches_app "$LP"; then
  SET=$(tree "$LP")
else
  _lcmd=$(ps -o command= -p "$LP" 2>/dev/null | cut -c1-120)
  say "SKIP tree $APP: pid $LP is not expected app ($EXPECT): ${_lcmd:-exited}"
fi
[ "$APP" = vlc ] && { _vp=$(alive_of $(pgrep -x VLC)); [ -n "$_vp" ] && SET="$SET $_vp"; }
ok "$APP still running after ${WAIT} s ($(nw $(alive_of $SET)) processes)" '[ -n "$(alive_of $SET)" ]'
scap a
case $APP in vlc|cc|ff) srec rec 6;; esac
sleep 2; scap b; a1=$(avd); say "decoder jobs $a0 -> $a1 ($((a1 - a0)))"
case $APP in vlc) ok "VLC plays through the hardware decoder (jobs +$((a1 - a0)))" '[ $((a1 - a0)) -gt 60 ]';; esac
case $APP in cc) tail -c +$((E0 + 1)) $CE > $W/cc-app.err 2>/dev/null; say "ChonkCraft present path (app.err since launch, $(wc -l < $W/cc-app.err) lines): $(grep -a -E '^(SF_CHONK|FXSURFACE)|CPU layer path' $W/cc-app.err | head -4 | tr '\n' '|' | cut -c1-400)"
  ok "ChonkCraft on the GPU present path (SF_CHONK GPU present on, FXWSPRESENT transport=dmabuf, no launcher fallback)" 'grep -q "^SF_CHONK GPU present on" $W/cc-app.err && grep -q "transport=dmabuf" $W/cc-app.err && ! grep -q "no private iosurfaced" $W/cc-app.err';; esac
obs_metrics
QP=$LP; [ "$APP" = cc ] && { QP=$(pgrep -x ChonkCraft | head -1); [ -n "$QP" ] || QP=$LP; }
if ! pid_ok "${QP:-}"; then
  say "FAIL quit $APP: skipped (empty or unsafe pid '${QP:-none}')"
elif ! pid_matches_app "$QP"; then
  _qcmd=$(ps -o command= -p "$QP" 2>/dev/null | cut -c1-120)
  say "FAIL quit $APP: skipped (pid $QP is not expected app ($EXPECT): ${_qcmd:-exited})"
else
  SET=$(tree "$QP"); [ "$APP" = vlc ] && { _vp=$(alive_of $(pgrep -x VLC)); [ -n "$_vp" ] && SET="$SET $_vp"; }
  quit_set "$QP" 15 $SET
fi
ok "$APP window gone from the desktop" 'obs_gone $ID 20'
say "launcher log tail: $(ltail $W/$APP.log 4)"
ok "desktop and dock still the same processes (desk $DESK0)" desk_ok
