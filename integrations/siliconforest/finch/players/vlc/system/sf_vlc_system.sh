#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# VLC's changes system-wide (docs/roadmap/issues/SF-AH-vlc.md, "Proposal: installing VLC's changes
# system-wide"): the stage of the six steps and their rehearsal in QEMU on the M1's root image.
#   sf_vlc_system.sh stage       runs/sf-vlc-system/stage: step1 ... step6 (list, files/, core), the restore
#                                script, the guarded installer, the probes; each file what the system tree
#                                (../../../../terminal-app/build-macos-apps-root.nix) of this checkout has where
#                                the tree of SF_VLC_BASE (a checkout of what the M1 has installed) differs, and
#                                only there: a difference outside the six steps stops the stage
#   sf_vlc_system.sh qemu <name> [second]
#                                the rehearsal (./qemu-vlc-system.sh through ../../../../m1-storage/tools/
#                                dr_qemu_userland.sh): the root is the rehearsal's root image with the base tree
#                                laid over it (the M1's files), VLC's bundle (SF_VLC_APP, never committed) and a
#                                clip; first boot forward, back, forward; `second` boots the root the first left
#   sf_vlc_system.sh compare <name>
#                                the root images before the first boot and after the second, file by file
#                                (debugfs, cold: no page cache in between), for every path the stage names
# SF_VLC_BASE: a checkout of the commit whose system tree the M1 has (default runs/vlc/mainwt).
# runs/ and artifacts/ are the lab's (the checkout that holds the git directory; a worktree has none of its own):
# the QEMU chain runs from there.
set -euo pipefail
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/../../../../../.." && pwd); cd "$ROOT"
LAB=$(cd "$(git -C "$ROOT" rev-parse --git-common-dir)/.." && pwd)
export PATH=$HOME/.nix-profile/bin:$PATH
I=integrations/siliconforest; H=$ROOT/$I/finch/players/vlc/system; W=$LAB/runs/sf-vlc-system; ST=$W/stage
BASE=${SF_VLC_BASE:-$LAB/runs/vlc/mainwt}; F=System/Library/Frameworks
APP=${SF_VLC_APP:-$LAB/runs/vlc/scan/ov/Applications/VLC.app}; CLIP=${SF_VLC_CLIP:-$LAB/runs/vlc/clips/bbb-1080p-h264-aac-30s.mp4}
nb() { (cd "$1" && nice -n 5 nix-build --extra-experimental-features 'nix-command flakes' --no-out-link --cores 8 "${@:2}" 2>>"$W/build.log" | tail -1); }
case "${1:-}" in
stage)
  mkdir -p $W; : > $W/build.log
  M=$(nb $BASE/$I/terminal-app build-macos-apps-root.nix); V=$(nb $I/terminal-app build-macos-apps-root.nix)
  LS=$(nb $I/libsystem-default build-libsystem-legacy-exports.nix); FW=$(nb $I/finch/players/compat frameworks-system-foundation.nix)
  MP=$(nb $I/finch/MediaPlayer build.nix); PR=$(nb $H build-probes.nix)
  for x in "$M" "$V" "$LS" "$FW" "$MP" "$PR"; do [ -d "$x" ] || { echo "a build failed: $W/build.log" >&2; exit 2; }; done
  echo "base tree $M"; echo "this tree $V"
  chmod -R u+w $ST 2>/dev/null || true; rm -rf $ST; mkdir -p $ST
  # which step a differing file of the system tree belongs to
  step_of() { case "$1" in
      $F/CoreFoundation.framework/*|$F/Foundation.framework/*|$F/CoreServices.framework/*) echo 2;;
      $F/QuartzCore.framework/*) echo 3;;
      $F/AppKit.framework/*) echo 4;;
      $F/Onyx2D.framework/*) echo 7a;;     # step 7 (QuickTime set; installed from runs/sysinstall/stage7, not rehearsed)
      usr/lib/libFoundation.dylib) echo 5;;
      usr/share/sf-test/*) echo probe;;
      *) echo none;; esac; }
  add() {  # <step> <source file> <installed path without the leading slash>
      mkdir -p "$ST/step$1/files/$(dirname "$3")"; cp "$2" "$ST/step$1/files/$3"; chmod 755 "$ST/step$1/files/$3"
      echo "f /$3 $(sha256sum "$2" | cut -c1-64) 0755" >> "$ST/step$1/list"; }
  bad=0
  while read -r f; do
      if [ -e "$M/$f" ] && cmp -s "$M/$f" "$V/$f"; then continue; fi
      s=$(step_of "$f")
      case "$s" in none) echo "DIFFERS OUTSIDE THE SIX STEPS: $f"; bad=1;; probe) ;; *) add "$s" "$V/$f" "$f";; esac
  done < <(cd "$V" && find . -type f -printf '%P\n' | LC_ALL=C sort)
  [ "$bad" = 0 ] || { echo "the trees differ outside the six steps: not staged" >&2; exit 1; }
  # step 1: the frameworks the system lacks (files and links), step 6: libSystem
  mkdir -p $ST/step1
  for n in AddressBook ScriptingBridge WebKit; do
      (cd "$FW/Frameworks" && find $n.framework \( -type f -o -type l \) | LC_ALL=C sort) | while read -r p; do
          if [ -L "$FW/Frameworks/$p" ]; then echo "l /$F/$p $(readlink "$FW/Frameworks/$p") -" >> $ST/step1/list
          else add 1 "$FW/Frameworks/$p" "$F/$p"; fi
      done
  done
  (cd "$MP/$F" && find MediaPlayer.framework \( -type f -o -type l \) -not -path '*/Headers*' -not -path '*/Resources/Source*' | LC_ALL=C sort) | while read -r p; do
      if [ -L "$MP/$F/$p" ]; then echo "l /$F/$p $(readlink "$MP/$F/$p") -" >> $ST/step1/list
      else add 1 "$MP/$F/$p" "$F/$p"; fi
  done
  sort -o $ST/step1/list $ST/step1/list
  add 6 "$LS/usr/lib/libSystem.B.dylib" usr/lib/libSystem.B.dylib
  T=/usr/share/sf-test; P="/opt/homebrew/bin/node /usr/local/bin/claude /opt/homebrew/bin/python3 /opt/homebrew/bin/bash /opt/homebrew/bin/git /opt/homebrew/bin/vim /opt/homebrew/bin/nvim /opt/homebrew/bin/tmux"
  echo "$T/sf-kvo-probe $P" > $ST/step5/core
  echo "$T/sf-vlc-libsystem-probe $P" > $ST/step6/core
  cp $H/sf_vlc_restore.sh $ROOT/$I/macos-compat/sf-lib-install.sh $ST/
  mkdir -p $ST/test; cp $V/usr/share/sf-test/* $PR/usr/share/sf-test/* $ST/test/; chmod -R u+w $ST
  for n in 1 2 3 4 5 6; do [ -s $ST/step$n/list ] || { echo "step $n is empty" >&2; exit 1; }; echo "step $n: $(grep -c . $ST/step$n/list) paths"; done
  echo "$M" > $W/base-tree; echo "$V" > $W/this-tree;;
qemu)
  N=${2:?name}; [ -s $ST/step6/list ] || { echo "sf_vlc_system.sh stage first" >&2; exit 2; }
  M=$(cat $W/base-tree); T=usr/share/sf-test; Q=$W/qemu-$N; U=$LAB/runs/sf-userland/stage
  if [ "${3:-}" != second ]; then
      # the root: the rehearsal's image, the userland's sys part, and over them the base tree as the M1 has it,
      # VLC's bundle with its stand-in Sparkle and a clip, the stage, the probes. New paths go in with the sys
      # part; the base tree's files that the image has already are written again (DR_QEMU_ROOT_FILES: removed,
      # then written), so every library is the M1's
      rm -rf $Q; mkdir -p $Q/stage
      cp -a --reflink=auto $U/sys $Q/stage/sys; chmod -R u+w $Q/stage/sys
      cp -a --reflink=auto --remove-destination $M/. $Q/stage/sys/; chmod -R u+w $Q/stage/sys
      rm -rf $Q/stage/sys/$T; mkdir -p $Q/stage/sys/$T/vlc/Frameworks
      cp $ST/test/* $ST/sf_vlc_restore.sh $Q/stage/sys/$T/
      cp -a "$APP" $Q/stage/sys/$T/vlc/VLC.app
      FW=$(nb $I/finch/players/compat frameworks-system-foundation.nix); cp -a $FW/Frameworks/Sparkle.framework $Q/stage/sys/$T/vlc/Frameworks/
      cp "$CLIP" $Q/stage/sys/$T/vlc/clip.mp4; cp -a $ST $Q/stage/sys/$T/vlc/stage; chmod -R u+w $Q/stage/sys
      cp $U/sys.sha256 $Q/stage/sys.sha256; ln -s "$(readlink -f $U/brew)" $Q/stage/brew; ln -s "$(readlink -f $U/claude)" $Q/stage/claude
      # the core runtime goes together, as the M1 has it: the base tree's dyld, libSystem, libobjc, and the two files
      # of the M1's core class the system tree does not build (libdyld, libIOKitCF; SF_VLC_CORE: the stage of the
      # switch that installed them, default runs/rebuild/stage/main/root). With dyld and libSystem of one build and
      # libdyld of another, launchd did not start ("dyld cache load error: shared cache file open() failed")
      CORE=${SF_VLC_CORE:-$LAB/runs/rebuild/stage/main/root}
      FILES=$( (cd $M && find . -type f -not -path './usr/share/*' -not -path './System/Library/Fonts/*' -printf '%P\n') | while read -r f; do printf '%s=/%s ' "$M/$f" "$f"; done)
      for f in usr/lib/system/libdyld.dylib usr/lib/libIOKitCF.dylib; do [ -s "$CORE/$f" ] || { echo "no $CORE/$f" >&2; exit 2; }; FILES="$FILES $CORE/$f=/$f"; done
      # what AppKit, QuartzCore and VLC load that the image lacks (the graphics stack, fontconfig ...), from copies of
      # the M1's files (SF_VLC_M1_COPIES, first match wins): without them neither AppKit nor VLC loads in the rehearsal
      IMG=$LAB/artifacts/m1-desktop-010/pcie-enum-candidate-sw01/ramdisk.img
      COPIES=${SF_VLC_M1_COPIES:-$LAB/runs/vlc/m1root $LAB/runs/sf-gaps/m1root $LAB/runs/sf-terminal/install/core/new}
      python3 -B $H/root_closure.py "$IMG" "$APP" $M $COPIES > $Q/closure.txt
      while read -r a b c; do
          case "$a" in
          LINK) mkdir -p "$Q/stage/sys$(dirname "$b")"; [ -e "$Q/stage/sys$b" ] || [ -L "$Q/stage/sys$b" ] || ln -s "$c" "$Q/stage/sys$b";;
          MISSING) echo "the M1 copies lack $b (AppKit or VLC may not load in the rehearsal)" >&2;;
          *) case "$a" in "$M"/*) ;; *) FILES="$FILES $a"; d=${a#*=}; mkdir -p "$Q/stage/sys$(dirname "$d")"; cp -L "${a%%=*}" "$Q/stage/sys$d";; esac;;
          esac
      done < $Q/closure.txt
      echo "the root gets $(grep -c '=' $Q/closure.txt) libraries of the M1's beyond the system tree (closure: $Q/closure.txt)"
      export DR_QEMU_STAGE=$Q/stage DR_QEMU_ROOT_FILES="$FILES"; RUN=vlcsys-$N
  else
      export DR_QEMU_ROOT_IMAGE=$LAB/runs/m1-storage/qemu-dr/vlcsys-$N-after.img; RUN=vlcsys-$N-2
      [ -s "$DR_QEMU_ROOT_IMAGE" ] || { echo "no $DR_QEMU_ROOT_IMAGE" >&2; exit 2; }
  fi
  DR_QEMU_GUEST=$H/qemu-vlc-system.sh DR_QEMU_TIMEOUT=${DR_QEMU_TIMEOUT:-7200} DR_QEMU_FS_SIZE=${DR_QEMU_FS_SIZE:-4G} \
  DR_QEMU_PREFIX=${SF_VLC_PREFIX:-$LAB/runs/sf-gaps/m1root/opt/homebrew} \
    $LAB/$I/m1-storage/tools/dr_qemu_userland.sh "$RUN" quick
  grep -a '^VLCSYS_\|QDDESK_PASS\|panic' $LAB/runs/m1-storage/qemu-dr/$RUN/serial.log | cut -c1-400 > $W/qemu-$RUN.txt || true
  echo "$(grep -c 'VERDICT ok' $W/qemu-$RUN.txt) checks ok, $(grep -c 'VERDICT FAIL' $W/qemu-$RUN.txt) failed: $W/qemu-$RUN.txt";;
compare)
  N=${2:?name}; A=$LAB/runs/m1-storage/qemu-dr/vlcsys-$N-fs.img; B=$LAB/runs/m1-storage/qemu-dr/vlcsys-$N-2-after.img
  [ -s "$A" ] && [ -s "$B" ] || { echo "no $A or $B" >&2; exit 2; }
  out=$W/compare-$N; rm -rf $out; mkdir -p $out/a $out/b
  cat $ST/step*/list | awk '{print $2}' | LC_ALL=C sort -u > $out/paths
  same=0; differ=0
  while read -r p; do
      for s in a b; do img=$A; [ $s = b ] && img=$B
          debugfs -R "dump -p $p $out/$s/x" "$img" > /dev/null 2>&1 || rm -f $out/$s/x
          debugfs -R "stat $p" "$img" 2>/dev/null | awk '/Type:|Inode:/{print}/Links:/{print}' | head -2 > $out/$s/st; done
      ha=$( [ -e $out/a/x ] && sha256sum < $out/a/x | cut -c1-64 || echo absent); hb=$( [ -e $out/b/x ] && sha256sum < $out/b/x | cut -c1-64 || echo absent)
      if [ "$ha" = "$hb" ] && cmp -s $out/a/st $out/b/st; then same=$((same + 1)); else differ=$((differ + 1)); echo "DIFFERS $p: $ha / $hb"; fi
      for x in .pre-vlc .sf-new; do debugfs -R "stat $p$x" "$B" 2>/dev/null | grep -q Inode && { echo "LEFT OVER $p$x"; differ=$((differ + 1)); }; done
  done < $out/paths
  echo "paths compared cold (root image before the first boot, after the second): $same the same (bytes, inode, type), $differ differ";;
*) sed -n '4,18p' "$0"; exit 2;;
esac
