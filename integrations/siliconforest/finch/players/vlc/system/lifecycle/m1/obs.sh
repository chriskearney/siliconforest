# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# BAKEIN observe mode (after lib.sh): passes that need NO test-inject compositor. The daily desktop
# (/usr/bin/chonkstep-darwin-desktop without test-inject) answers only --desktop-request and --screencapture, so a
# pass here: launches the app as the dock does (or the harness's own private-home launch), watches the session log
# (WMRESTORE window presence, WMCLIENT, WMPACING, WMCOST, WMDMABUF), captures stills/recordings through the
# compositor, reads the decoder's job count, and quits by process (TERM). No synthetic input, no window list, no drags.
# Display power: only real input wakes the display; with it off captures still render, recordings/pacing may not.
obs_mark() { LM=$(wc -l < $L); say "log mark $LM; display $(grep WMPOWER $L | tail -1 | cut -c9-40)"; }
obs_since() { tail -n +$((LM + 1)) $L; }
# the newest "applications with windows now" list since the mark
obs_apps() { obs_since | grep -a 'WMRESTORE applications with windows now' | tail -1 | sed 's/.*now: //'; }
# wait up to <s> for <app id> in that list; prints the list
obs_win() { _u=$(( $(date +%s) + ${2:-40} )); while [ $(date +%s) -lt $_u ]; do obs_apps | grep -q -F "\"$1" && break; sleep 1; done; obs_apps; }
obs_gone() { _u=$(( $(date +%s) + ${2:-20} )); while [ $(date +%s) -lt $_u ]; do obs_apps | grep -q -F "\"$1" || return 0; sleep 1; done; return 1; }
# a still through the compositor: <name> -> $W/<T>-<name>.png (pulled to the i9's caps/)
scap() { [ -n "${NOCAP:-}" ] && { say "SKIP capture $1: NOCAP (a compositor capture with a GPU-buffer window on screen panics the daily desktop: effects.rs:261)"; return 0; }; _f=$W/$T-$1.png; rm -f $_f; $(BIN) --screencapture $_f > $W/cli-$T-$1.txt 2>&1; if [ -s $_f ]; then say "capture $1: $(wc -c < $_f) bytes"; else say "capture $1 FAILED: $(tr '\n' ' ' < $W/cli-$T-$1.txt | cut -c1-160)"; fi; }
# a recording <name> <secs> -> $W/<T>-<name>.mov
srec() { [ -n "${NOCAP:-}" ] && { say "SKIP recording $1: NOCAP"; return 0; }; _f=$W/$T-$1.mov; rm -f $_f; timeout $(( $2 + 20 )) $(BIN) --screencapture -V $2 -F $_f > $W/cli-$T-$1.txt 2>&1; [ -s $_f ] && say "recording $1: $(wc -c < $_f) bytes" || say "recording $1 FAILED: $(tr '\n' ' ' < $W/cli-$T-$1.txt | cut -c1-160)"; }
obs_metrics() { obs_since > $W/$T-log.txt
  say "log since mark: $(wc -l < $W/$T-log.txt) lines; WMPACING: $(grep -a WMPACING $W/$T-log.txt | tail -1 | cut -c1-200)"
  say "WMCOST lines $(grep -a -c WMCOST $W/$T-log.txt); WMDMABUF zero_copy=1 imports $(grep -a WMDMABUF $W/$T-log.txt | grep -c 'zero_copy=1'); WMSTALL lines $(grep -a -c WMSTALL $W/$T-log.txt) (max $(grep -a WMSTALL $W/$T-log.txt | sed -E 's/.*turn ([0-9.]+) ms.*/\1/' | sort -n | tail -1) ms)"
  _e=$(grep -a -i -E 'panic|fatal|abort|segfault|crash' $W/$T-log.txt | grep -v WMSTALL | head -3 | cut -c1-200); [ -n "$_e" ] && say "log mentions: $_e"; }
desk_ok() { _p=$(desk_pid); [ -n "$_p" ] && [ "$_p" = "$DESK0" ] && [ -n "$(pgrep -x chonkstep-dock)" ]; }
DESK0=$(desk_pid)   # the desktop at the start of this pass
# log-tail of a launcher log for the report
ltail() { [ -e "$1" ] && tail -n ${2:-3} "$1" | tr '\n' '|' | cut -c1-300; }
