#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# SYSINSTALL: one restart of the M1 so long-running processes load the new core files (after DESK's reboot-next and
# GFX2's sf-kernel-cycle.sh, without any kit): run INSIDE gui.lock by the caller.
# SiliconForest (marks for the .next + inject compositor; sync; reboot) -> Linux (the default boot) -> ONE session:
# the root's identity (private/disk-root/sf-part.env, not printed), e2fsck -fn (read-only, output saved), asahi-bless
# --next (one boot of SiliconForest; the default stays Linux), reboot -> SiliconForest polled every 9 s.
# Never mounts the root, never --set-boot without --next, no partition or boot-file change.
# Gives up (rc 7) if SiliconForest does not answer within 6 minutes of the Linux reboot: then tell the coordinator.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd); LAB=${SF_LAB:-$(cd "$HERE" && cd "$(git rev-parse --git-common-dir)/.." && pwd)}
ROOT=$LAB; cd "$ROOT"; . private/disk-root/sf-part.env
NAME=${1:?name}; OUT=runs/sysinstall/work/restart-$NAME.txt
SF=(ssh -o UserKnownHostsFile="$HOME/.ssh/known_hosts_m1_siliconforest" -o GlobalKnownHostsFile=/dev/null
    -o StrictHostKeyChecking=yes -o HostKeyAlias=m1-siliconforest -o BatchMode=yes -o ConnectTimeout=6 root@10.1.1.211)
LX=(-o HostKeyAlias=10.1.1.127 -o BatchMode=yes -o ConnectTimeout=10)
log() { echo "$(date -u +%FT%TZ) SYSINSTALL $*" >> runs/m1-coord/log.txt; echo "$*" | tee -a "$OUT"; }
: > "$OUT"
"${SF[@]}" 'touch /private/var/db/desktop-next-try /private/var/db/desktop-inject; sync; sync; echo SF_BOOTED $(sysctl -n kern.boottime | cut -c1-40); (sleep 1; reboot) > /dev/null 2>&1 &' 2>&1 | tee -a "$OUT"
log "restart $NAME: SiliconForest rebooting (marks for .next + inject set) -> Linux"
sleep 45
up=0; for i in $(seq 1 40); do ssh "${LX[@]}" chrisk@10.1.1.211 true 2>/dev/null && { up=1; break; }; sleep 15; done
[ $up = 1 ] || { log "restart $NAME: Linux did not answer within 10 min: STOPPED, coordinator to decide (no reset by me)"; exit 7; }
sleep 10
{
  echo "export WANT_PARTUUID=$SF_PARTUUID WANT_LBA=$SF_PART_LBA WANT_BLOCKS=$SF_PART_BLOCKS"
  cat <<'REMOTE'
set -u
P=/dev/nvme0n1p3; S=/sys/block/nvme0n1/nvme0n1p3
ok=1
[ "$(blkid -s PARTUUID -o value $P)" = "$WANT_PARTUUID" ] || { echo "SFL_FAIL PARTUUID"; ok=0; }
[ "$(blkid -s LABEL -o value $P)" = SiliconForest ] || { echo "SFL_FAIL label"; ok=0; }
[ "$(( $(cat $S/start) / 8 ))" = "$WANT_LBA" ] || { echo "SFL_FAIL first block"; ok=0; }
[ "$(( $(cat $S/size) / 8 ))" = "$WANT_BLOCKS" ] || { echo "SFL_FAIL length"; ok=0; }
findmnt -rn -S $P >/dev/null && { echo "SFL_FAIL mounted"; ok=0; }
if [ $ok = 1 ]; then
  echo "SFL_IDENTITY ok"
  e2fsck -fn $P 2>&1 | sed 's/^/SFL_FSCK /'; echo "SFL_FSCK_RC ${PIPESTATUS[0]}"
  asahi-bless --next --set-boot SiliconForest -y 2>&1 | tail -2 | sed 's/^/SFL_BLESS /'
  echo SFL_END
  (sleep 2; systemctl reboot) > /dev/null 2>&1 &
else
  echo "SFL_END not blessed: identity check failed"
fi
REMOTE
} | ssh "${LX[@]}" chrisk@10.1.1.211 'sudo bash -s' 2>&1 | tee -a "$OUT"
grep -q '^SFL_BLESS' "$OUT" || { log "restart $NAME: Linux session did not bless SiliconForest (see $OUT): STOPPED in Linux"; exit 6; }
log "restart $NAME: Linux: root e2fsck -fn rc $(grep -o 'SFL_FSCK_RC [0-9]*' "$OUT" | cut -d' ' -f2) (read-only; $OUT), blessed --next SiliconForest, rebooting"
sleep 40
t0=$(date +%s); up=0
while [ $(( $(date +%s) - t0 )) -lt 360 ]; do "${SF[@]}" true 2>/dev/null && { up=1; break; }; sleep 9; done
[ $up = 1 ] || { log "restart $NAME: SiliconForest NOT back within 6 min of the Linux reboot: STOPPED; coordinator to decide (no reset by me)"; exit 7; }
for i in $(seq 1 40); do "${SF[@]}" 'pgrep -x chonkstep-darwin-desktop.next > /dev/null || pgrep -x chonkstep-darwin-desktop > /dev/null' && break; sleep 5; done
"${SF[@]}" 'echo SF_BOOTED $(sysctl -n kern.boottime | cut -c1-40); pgrep -lx chonkstep-darwin-desktop.next; pgrep -lx chonkstep-darwin-desktop; ls -d /private/var/run/gpu-desktop/inject; grep -E "^(active|last_real_input_unix_ms)=" /private/var/run/gpu-desktop/owner-input' 2>&1 | tee -a "$OUT"
log "restart $NAME: SiliconForest back after $(( $(date +%s) - t0 + 40 )) s ($(grep -c 'chonkstep-darwin-desktop.next' "$OUT") .next compositor lines)"
