#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# SYSINSTALL: step <N> on the M1 inside ONE core.lock hold: install (step.sh forward), then the lifecycle set (life.sh,
# each pass under gui.lock). Whether to keep the step is decided after it; back is step.sh <N> back (its own hold).
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd); LAB=${SF_LAB:-$(cd "$HERE" && cd "$(git rev-parse --git-common-dir)/.." && pwd)}
H=$LAB; M=$H/runs/sysinstall; N=${1:?step}; LOG=$H/runs/m1-coord/log.txt
exec 8>"$H/runs/m1-coord/core.lock"; flock -w 1800 8 || { echo "core.lock busy"; exit 6; }
echo "$(date -u +%FT%TZ) SYSINSTALL core.lock: step $N (install, then the lifecycle set under gui.lock per pass)" >> $LOG
HAVE_CORE=1 bash $HERE/step.sh $N forward; grep -q "^SFVLCSYS step $N installed" $M/work/step$N-forward-*.txt 2>/dev/null || { echo "STEP $N NOT INSTALLED"; echo "$(date -u +%FT%TZ) SYSINSTALL step $N not installed (see work/step$N-forward-*); core.lock released" >> $LOG; exit 2; }
bash $HERE/life.sh s$N ${LIFE:-}
echo "$(date -u +%FT%TZ) SYSINSTALL core.lock released (step $N installed; lifecycle set s$N run)" >> $LOG
