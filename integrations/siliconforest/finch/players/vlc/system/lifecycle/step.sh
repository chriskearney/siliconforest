#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# SYSINSTALL: one step of VLC's system install on the M1 (SF-AH proposal), inside core.lock:
#   step.sh <N> forward   sf_vlc_restore.sh forward <stage> N, then the installed files' hashes, the .pre-vlc copies,
#                         the features probe; nothing else (the lifecycle set is life.sh, run after it)
#   step.sh <N> back      sf_vlc_restore.sh back N, then every path's hash against the record of before
#   step.sh <N> check     hashes and the features probe only
# Stage on the M1: /private/var/db/sfsysinst/stage (runs/sf-vlc-system/stage, core probes pointed at its test/).
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd); LAB=${SF_LAB:-$(cd "$HERE" && cd "$(git rev-parse --git-common-dir)/.." && pwd)}
H=$LAB; M=$H/runs/sysinstall; LOG=$H/runs/m1-coord/log.txt; CORE=$H/runs/m1-coord/core.lock
SF=(ssh -o UserKnownHostsFile="$HOME/.ssh/known_hosts_m1_siliconforest" -o GlobalKnownHostsFile=/dev/null -o StrictHostKeyChecking=yes -o HostKeyAlias=m1-siliconforest -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=10 root@10.1.1.211)
note() { echo "$(date -u +%FT%TZ) SYSINSTALL $*" >> $LOG; }
N=${1:?step}; A=${2:?forward|back|check}; S=/private/var/db/sfsysinst/stage; OUT=$M/work/step$N-$A-$(date -u +%H%M%S).txt
CHECK='S=/private/var/db/sfsysinst/stage; N='$N'
while read -r kind pth want mode; do
  if [ "$kind" = l ]; then echo "HASH link $pth -> $(readlink "$pth" 2>/dev/null || echo ABSENT) (want $want)"; continue; fi
  now=$(sha256sum "$pth" 2>/dev/null | cut -c1-64); pre=$(sha256sum "$pth.pre-vlc" 2>/dev/null | cut -c1-64)
  echo "HASH $pth now ${now:-ABSENT} staged $want $([ "$now" = "$want" ] && echo NEW || echo NOT-NEW) inode $(ls -i "$pth" 2>/dev/null | awk "{print \$1}") pre-vlc ${pre:-none} inode $(ls -i "$pth.pre-vlc" 2>/dev/null | awk "{print \$1}")"
done < $S/step$N/list
$S/test/sf-vlc-features-probe 2>&1 | grep -E "SFVLCFEATURE|SFVLCLOADERROR" | sed "s/^/FEATURE /"'
[ "${HAVE_CORE:-}" = 1 ] || { exec 8>"$CORE"; flock -w 1800 8 || { echo "core.lock not free within 1800 s"; exit 6; }; }
case $A in
forward)
  note "core.lock${HAVE_CORE:+ (held by the step run)}: step $N forward: $(cat $H/runs/sf-vlc-system/stage/step$N/list $H/runs/sysinstall/stage7/step$N/list 2>/dev/null | awk '{print $2}' | grep -v Source.m | sed 's|.*/||' | sort -u | tr '\n' ' ')(sf_vlc_restore.sh forward; previous files kept as .pre-vlc; back: sf_vlc_restore.sh back $N)"
  "${SF[@]}" "sh $S/sf_vlc_restore.sh forward $S $N 2>&1; echo RC=\$?" | tee $OUT; printf '%s\n' "$CHECK" | "${SF[@]}" "sh -s" | tee -a $OUT;;
back)
  note "core.lock: step $N BACK (sf_vlc_restore.sh back $N)"
  "${SF[@]}" "sh $S/sf_vlc_restore.sh back $N 2>&1; echo RC=\$?" | tee $OUT; printf '%s\n' "$CHECK" | "${SF[@]}" "sh -s" | tee -a $OUT;;
check)
  printf '%s\n' "$CHECK" | "${SF[@]}" "sh -s" | tee $OUT;;
esac
[ "${HAVE_CORE:-}" = 1 ] || note "core.lock released (step $N $A; record $(basename $OUT))"
