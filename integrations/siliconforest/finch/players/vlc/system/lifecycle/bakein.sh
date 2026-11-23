#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# BAKEIN baseline (observe mode, the daily desktop): each app launched ONCE, then the desktop basics. One gui.lock hold
# per pass (m1.sh). After every pass the M1 is checked: no answer over ssh twice (30 s apart) = stop and report (no
# automatic hpm0 reset; reset by hand only if wedged). The desktop gone (ssh fine) = stop, no reset.
#   bakein.sh <label> [term am ff vlc qt pv te cc desk]
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd); LAB=${SF_LAB:-$(cd "$HERE" && cd "$(git rev-parse --git-common-dir)/.." && pwd)}; H=$LAB/runs/sysinstall; mkdir -p $H/work; L=${1:?label}; shift; P=${*:-term am ff vlc qt pv te cc desk}
SF=(ssh -o UserKnownHostsFile="$HOME/.ssh/known_hosts_m1_siliconforest" -o GlobalKnownHostsFile=/dev/null -o StrictHostKeyChecking=yes -o HostKeyAlias=m1-siliconforest -o BatchMode=yes -o ConnectTimeout=10 root@10.1.1.211)
M5=(ssh -o BatchMode=yes -o ConnectTimeout=10 chriskearney@100.115.210.75)
VDM='sudo -n $HOME/maclab/macvdmtool/macvdmtool'
log() { echo "$(date '+%F %T %Z') BAKEIN $*" | tee -a $H/work/bakein-$L.txt; }
m1_alive() { timeout 25 "${SF[@]}" 'pgrep -x chonkstep-darwin-desktop.next || pgrep -x chonkstep-darwin-desktop' 2>/dev/null; }
check() { d=$(m1_alive); if [ -z "$d" ]; then sleep 30; d=$(m1_alive); fi
  if [ -n "$d" ]; then log "after $1: M1 answers, desktop pid $d"; return 0; fi
  if timeout 25 "${SF[@]}" true 2>/dev/null; then log "after $1: M1 answers but NO desktop process: STOP (no reset)"; exit 20; fi
  log "after $1: M1 not answering: STOP, no automatic reset; reset by hand only if wedged"; exit 21; }
log "start $L: passes $P; hpm0 link: $("${M5[@]}" "$VDM nop" 2>&1 | grep -E 'Found|Status|Connection' | tr '\n' ' ' | cut -c1-200)"
check start; D0=$(m1_alive)
for p in $P; do
  case $p in
  desk) CAP=120 bash $HERE/m1.sh $L-desk "bakein $L: desktop basics (four themes by request, the theme saved at the start of the run put back, state compared; dock observed)" $HERE/m1/obs-desk.sh;;
  *) nc=""; case " ${NOCAP_APPS:-ff vlc qt cc} " in *" $p "*) nc="NOCAP=1;";; esac
     PASSENV="APP=$p; $nc" CAP=200 bash $HERE/m1.sh $L-$p "bakein $L: $p launched once (observe mode: session log, captures, TERM)" $HERE/m1/obs-app.sh;;
  esac
  log "pass $p rc $?"; check $p
  d1=$(timeout 25 "${SF[@]}" 'pgrep -x chonkstep-darwin-desktop.next || pgrep -x chonkstep-darwin-desktop' 2>/dev/null); [ -z "$D0" ] && D0=$d1
  if [ -n "$d1" ] && [ "$d1" != "$D0" ]; then log "after $p: the desktop process changed ($D0 -> $d1): it ended during the pass: STOP"; exit 22; fi
  sleep 5
done
grep -a -h '^LIFE' $H/work/out-$L-*.txt | grep -c PASS | sed "s/^/$L: PASS lines /"; grep -a -h '^LIFE.*\(FAIL\|SKIP\)' $H/work/out-$L-*.txt
