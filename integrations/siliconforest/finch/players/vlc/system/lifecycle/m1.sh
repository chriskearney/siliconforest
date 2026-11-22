#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# SYSINSTALL (after DEMO's m1.sh): run a pass script on the M1 inside gui.lock (logged), wall-clock capped; owner idle
# and the standard state first; pull captures named <tag>-* into raw/ (png in caps/).
#   m1.sh <tag> <what> <script file>      CAP=<s> (default 200)  IDLE=<s> owner idle at least (default 60)
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd); LAB=${SF_LAB:-$(cd "$HERE" && cd "$(git rev-parse --git-common-dir)/.." && pwd)}
H=$LAB; M=$H/runs/sysinstall; LOCK=$H/runs/m1-coord/gui.lock; LOG=$H/runs/m1-coord/log.txt
SF=(ssh -o UserKnownHostsFile="$HOME/.ssh/known_hosts_m1_siliconforest" -o GlobalKnownHostsFile=/dev/null -o StrictHostKeyChecking=yes -o HostKeyAlias=m1-siliconforest -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=10 root@10.1.1.211)
note() { echo "$(date -u +%FT%TZ) SYSINSTALL $*" >> $LOG; }
T=$1; WHAT=$2; S=$3; CAP=${CAP:-200}; IDLE=${IDLE:-60}
exec 9>"$LOCK"; flock -w 900 9 || { echo "gui.lock not free within 900 s"; exit 6; }
"${SF[@]}" "f=/private/var/run/gpu-desktop/owner-input; grep -q '^active=0' \$f || exit 3; last=\$(grep '^last_real_input_unix_ms=' \$f | cut -d= -f2); now=\$(date +%s); [ \"\${last:-0}\" = 0 ] || [ \$(( now - last / 1000 )) -ge $IDLE ] || exit 3; s=\$(grep -a -n -E 'GPUDESK_DESKTOP_START|WMSTAT selected renderer=' /var/log/desktop-session.log 2>/dev/null | tail -1 | cut -d: -f1); if pgrep -x chonkstep-darwin-desktop.next >/dev/null && [ -d /private/var/run/gpu-desktop/inject ] && ! tail -n +\${s:-1} /var/log/desktop-session.log 2>/dev/null | grep -a -q 'WMINJECT absent'; then exit 0; elif pgrep -x chonkstep-darwin-desktop.next >/dev/null || pgrep -x chonkstep-darwin-desktop >/dev/null; then exit 10; else exit 4; fi"
g=$?
# BAKEIN (21 November): the installed desktop is the daily /usr/bin/chonkstep-darwin-desktop, built without test-inject.
# 0: the test-inject desktop (.next with inject module): every pass. 10: daily or .next without inject: observe mode,
# only passes named obs-*.sh (m1/obs.sh: no synthetic input, no window list). 4: no desktop. 3: the owner is active.
case $g in 0) MODE=inject;; 10) MODE=observe;; *) echo "OWNER ACTIVE (3) or no desktop (4): $g: nothing done"; flock -u 9; exit 5;; esac
case "$MODE:$(basename "$S")" in observe:obs-*) ;; observe:*) echo "$(basename "$S") needs the test-inject desktop (.next); the daily desktop is running: nothing done"; flock -u 9; exit 7;; esac
note "gui.lock: $T ($MODE): $WHAT (virtual seat, my own windows under /private/var/db/sfsysinst on Space 2), cap ${CAP} s"
for f in lib.sh obs.sh shell.sh user.js video.html keys.sh; do "${SF[@]}" "mkdir -p /private/var/db/sfsysinst && cat > /private/var/db/sfsysinst/$f.part && mv -f /private/var/db/sfsysinst/$f.part /private/var/db/sfsysinst/$f && chmod 755 /private/var/db/sfsysinst/$f" < "$HERE/m1/$f"; done
"${SF[@]}" "[ -s /private/var/db/sfsysinst/bbb.mp4 ] || cat > /private/var/db/sfsysinst/bbb.mp4" < "$M/m1/bbb.mp4"
{ echo ". /private/var/db/sfsysinst/lib.sh; T=$T; STEP='${STEP:-}'; SFMODE=$MODE; ${PASSENV:-} echo \$\$ > \$W/pass.pid"; echo 'owner_active && { echo "OWNER ACTIVE: nothing done"; exit 3; }'; cat "$S"; } | timeout --kill-after=10 $CAP "${SF[@]}" "sh -s" 2>&1 | tee "$M/work/out-$T.txt"
rc=${PIPESTATUS[1]}
if [ "$rc" != 0 ]; then   # a pass cut short: its shell and my apps ended, the view back on Space 1
  { echo ". /private/var/db/sfsysinst/lib.sh; T=$T-cleanup"; cat "$HERE/m1/cleanup.sh"; } | timeout 90 "${SF[@]}" "sh -s" 2>&1 | tee -a "$M/work/out-$T.txt"
fi
"${SF[@]}" "mkdir -p /private/var/db/sfsysinst/fetched; cd /private/var/run/gpu-desktop/inject && ls | grep '^$T-' > /private/var/db/sfsysinst/fetch.lst; tar -cf - -T /private/var/db/sfsysinst/fetch.lst && sh -c 'while read -r f; do rm -f \"/private/var/run/gpu-desktop/inject/\$f\"; done < /private/var/db/sfsysinst/fetch.lst'" | tar -xf - -C "$M/raw" 2>/dev/null
# observe-mode captures (compositor --screencapture into the work dir): <T>-*.png / *.mov / *-log.txt, copied here
# (copied, not removed on the M1: each run uses its own tag)
mkdir -p "$M/caps/$T"; "${SF[@]}" "cd /private/var/db/sfsysinst && ls | grep -E '^$T-.*[.](png|mov|txt)\$' > fetch2-$T.lst; tar -cf - -T fetch2-$T.lst" | tar -xf - -C "$M/caps/$T" 2>/dev/null
note "gui.lock released ($T, rc $rc)"
flock -u 9
for f in "$M"/raw/$T-*.ppm; do [ -e "$f" ] || continue
  case "$f" in *-ff-a.ppm) magick "$f" -crop 1000x560+240+300 +repage "$M/caps/$(basename "${f%.ppm}")-full.png";;   # text at full resolution
    *-term7-a.ppm) magick "$f" -crop 1000x300+124+60 +repage "$M/caps/$(basename "${f%.ppm}")-full.png";; esac
  magick "$f" -resize 50% "$M/caps/$(basename "${f%.ppm}").png" && rm -f "$f"; done
grep -a '^LIFE' "$M/work/out-$T.txt" | grep -c PASS | sed 's/^/passes: /'; grep -a '^LIFE.*FAIL' "$M/work/out-$T.txt"
exit $rc
