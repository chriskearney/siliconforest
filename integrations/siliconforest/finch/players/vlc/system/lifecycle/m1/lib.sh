# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# SYSINSTALL M1-side helpers (after DEMO's lib.sh and lib-vlc.sh, which follow THEME's). Everything drives MY OWN
# windows on the instrument's virtual seat, on Space 2; nothing is quit by a synthetic Command-Q (by process only).
D=/private/var/run/gpu-desktop/inject; L=/var/log/desktop-session.log; W=/private/var/db/sfsysinst
ST=/private/var/db/desktop-state/chonkstep
export XDG_RUNTIME_DIR=/private/var/run/gpu-desktop WAYLAND_DISPLAY=wayland-0 LANG=en_US.UTF-8
req() { rm -f $D/done; printf "seat virtual\n$1" > $D/request.part && mv $D/request.part $D/request; _rq=0; while [ ! -e $D/done ] && [ $_rq -lt ${2:-600} ]; do sleep 0.1; _rq=$((_rq+1)); done; cat $D/done 2>/dev/null || echo "no done file"; }
ax() { echo $(( $1 * 65535 / 2559 )); }; ay() { echo $(( $1 * 65535 / 1599 )); }
owner_active() { grep -q '^active=1' /private/var/run/gpu-desktop/owner-input 2>/dev/null; }
desk_pid() { pgrep -x chonkstep-darwin-desktop.next || pgrep -x chonkstep-darwin-desktop; }
BIN() { echo /usr/bin/$(ps -o comm= -p $(desk_pid) | xargs basename); }
nw() { set -- $*; echo $#; }
say() { echo "LIFE $T $*"; }
ok() { if eval "$2"; then say "PASS $1"; else say "FAIL $1"; fi; }
run() { tag=$1; home=$2; shift 2; mkdir -p $home; ( cd /; env -i HOME=$home CFFIXED_USER_HOME=$home XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR WAYLAND_DISPLAY=wayland-0 PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin LANG=en_US.UTF-8 "$@" > $W/$tag.log 2>&1 & echo $! > $W/$tag.pid; wait ) > /dev/null 2>&1 & sleep 0.5; }
# processes whose command line holds <text> (fixed string), as "pid command"
procs() { ps ax -o pid=,command= | grep -F -- "$1" | grep -v -e 'grep -F' -e 'sh -s' | cut -c1-160; }
# quit by process: TERM to <pids>, then wait up to <s> for no process holding <text>; KILL only after that (reported)
pid_ok() { case "${1:-}" in ''|0*|*[!0-9]*) return 1;; esac; [ "$1" -gt 1 ]; }
quit_by_term() { text=$1; s=$2; shift 2
  _pids=""; for p in "$@"; do pid_ok "$p" && _pids="$_pids $p"; done
  [ -n "$_pids" ] && kill -TERM $_pids 2>/dev/null; i=0
  while [ -n "$(procs "$text")" ] && [ $i -lt $((s * 5)) ]; do sleep 0.2; i=$((i+1)); done
  left=$(procs "$text"); if [ -z "$left" ]; then say "quit by TERM: no process left after $((i / 5)).$((i % 5 * 2)) s"; return 0; fi
  say "quit by TERM: still there after $s s: $(echo "$left" | tr '\n' '|')"
  _kp=""; for p in $(echo "$left" | awk '{print $1}'); do pid_ok "$p" && _kp="$_kp $p"; done
  [ -n "$_kp" ] && kill -KILL $_kp 2>/dev/null; return 1; }
term_start() { mkdir -p $W/home-term/Library/Preferences; cat > $W/home-term/Library/Preferences/com.apple.Terminal.plist <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Shell</key><string>$W/shell.sh</string></dict></plist>
P
  run term $W/home-term /Applications/Utilities/Terminal.app/Contents/MacOS/Terminal; }
am_start() { run am $W/home-am "/System/Applications/Utilities/Activity Monitor.app/Contents/MacOS/Activity Monitor"; }
FFP=$W/p-ff
ff_start() { mkdir -p $FFP $W/home-ff; cp $W/user.js $FFP/user.js; ( cd /; env -i HOME=$W/home-ff CFFIXED_USER_HOME=$W/home-ff XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR WAYLAND_DISPLAY=wayland-0 PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin LANG=en_US.UTF-8 MOZ_CRASHREPORTER_DISABLE=1 MOZ_NO_REMOTE=1 /Applications/Firefox.app/Contents/MacOS/firefox-sf -no-remote -profile $FFP -width ${FFW:-1280} -height ${FFH:-860} "$@" > $W/ff.log 2>&1 < /dev/null & echo $! > $W/ff.pid ); sleep 0.5; }
# the newest mapped window of <app id> not in the list taken at the start of the pass (<tag>-l0)
win() { Wn=""; until=$(( $(date +%s) + ${3:-30} )); while [ $(date +%s) -lt $until ] && [ -z "$Wn" ]; do sleep 0.5
  req "list $1-l1\n" 30 > /dev/null
  Wn=$(grep '^window' $D/$1-l1.txt 2>/dev/null | grep "app_id=\"$2\"" | grep 'mapped=true' | grep -v 'size: Size { w: 1, h: 1 }' | while read -r line; do id=$(echo "$line" | cut -d' ' -f2); grep -q "^window $id " $D/$1-l0.txt || echo "$id"; done | tail -1); done; echo "$Wn"; }
# my mapped windows of <app id> (ids), from a fresh list
wins_of() { req "list $T-wo\n" 30 > /dev/null; grep '^window' $D/$T-wo.txt | grep "app_id=\"$1\"" | grep 'mapped=true' | grep -v 'size: Size { w: 1, h: 1 }' | while read -r line; do id=$(echo "$line" | cut -d' ' -f2); grep -q "^window $id " $D/$T-l0.txt || echo "$id"; done | tr '\n' ' '; }
title_of() { req "list $T-ti\n" 30 > /dev/null; grep "^window $1 " $D/$T-ti.txt | sed -E 's/.* title="([^"]*)".*/\1/'; }
rect() { grep -o 'content=Rect { pos: Point { x: [-0-9]*, y: [-0-9]* }, size: Size { w: [0-9]*, h: [0-9]* }' | head -1 | grep -o '[-0-9][0-9]*' | tr '\n' ' '; }
wrect() { req "list $T-wr\n" 30 > /dev/null; grep "^window $1 " $D/$T-wr.txt | rect; }
click() { req "abs $(ax $1) $(ay $2)\nwait 80\nbuttons 1\nwait 70\nbuttons 0\nwait ${3:-300}\n" 100 > /dev/null; }
dclick() { req "abs $(ax $1) $(ay $2)\nwait 100\nbuttons 1\nwait 60\nbuttons 0\nwait 90\nbuttons 1\nwait 60\nbuttons 0\nwait ${3:-400}\n" 100 > /dev/null; }
park() { req "abs $(ax ${1:-1300}) $(ay ${2:-1575})\nwait ${3:-400}\n" 50 > /dev/null; }
space_next() { touch $W/on-space2; req "swipe begin 3 0 0\nwait 16\nswipe update 3 -20 0\nwait 16\nswipe update 3 -40 0\nwait 16\nswipe update 3 -40 0\nwait 16\nswipe update 3 -40 0\nwait 16\nswipe update 3 -40 0\nwait 16\nswipe end 3 0 0\nwait 900\n" 100 | cut -c1-80; }
space_back() { rm -f $W/on-space2; req "swipe begin 3 0 0\nwait 16\nswipe update 3 20 0\nwait 16\nswipe update 3 40 0\nwait 16\nswipe update 3 40 0\nwait 16\nswipe update 3 40 0\nwait 16\nswipe update 3 40 0\nwait 16\nswipe end 3 0 0\nwait 900\n" 100 | cut -c1-80; }
look() { $(BIN) --desktop-request theme $1 2>&1 | tail -1; }
cap() { req "wait ${2:-300}\ncapture $1\n" 100 | cut -c1-120; }
mods_clear() { [ -n "$1" ] && req "target $1\nkey e0 down\nkey e0 up\nkey e1 down\nkey e1 up\nkey e2 down\nkey e2 up\nkey e3 down\nkey e3 up\nkey e4 down\nkey e4 up\nkey e5 down\nkey e5 up\nkey e6 down\nkey e6 up\nkey e7 down\nkey e7 up\nwait 100\n" 50 | cut -c1-40; }
# a chord <mods...> <key> (usage codes) to window <id>, then every modifier released on <window to clear> (the target
# may be gone after the chord, and a refused key-up leaves the modifier held on the virtual seat)
chord() { id=$1; clr=$2; k=$3; shift 3; l="target $id\n"; for m in "$@"; do l="${l}key $m down\n"; done; l="${l}key $k down\nkey $k up\n"
  for m in "$@"; do l="${l}key $m up\n"; done; req "${l}wait ${CW:-1200}\n" 100 | cut -c1-80; mods_clear $clr > /dev/null; }
typ() { req "target $1\n$2wait 300\n" 200 | cut -c1-60; }
rec_start() { OUT=$W/$1.mov; rm -f "$OUT"; ( exec $(BIN) --screencapture -V $2 -F $OUT ) > $W/cli-$1.txt 2>&1 & CLI=$!; sleep ${3:-1.2}; }
rec_wait() { w=0; while pid_ok "${CLI:-}" && kill -0 "$CLI" 2>/dev/null && [ $w -lt 900 ]; do sleep 0.2; w=$((w+1)); done; echo "CLI: $(tr '\n' ' ' < $W/cli-$1.txt | cut -c1-200)"; ls -la $W/$1.mov | cut -c24-; }
grow2() { set -- $1 $2 $3 ${4:-40} ${5:-50} $(wrect $1); rx=$(( $6 + $8 - 3 )); ry=$(( $7 + $9 - 3 ))
  lines="abs $(ax $rx) $(ay $ry)\nwait 100\nbuttons 1\nwait 100\n"; i=1
  while [ $i -le $4 ]; do lines="${lines}abs $(ax $(( rx + $2 * i / $4 ))) $(ay $(( ry + $3 * i / $4 )))\nwait $5\n"; i=$((i+1)); done
  req "${lines}wait 150\nbuttons 0\nwait 200\n" 300 > /dev/null; }
avd() { sysctl -n kern.sf_avd.stats | awk '{print $2}'; }
# owner's desk state, kept before a pass that changes the look and compared after (theme, wallpaper, scale, policy, dock ...)
STATEF="theme wallpaper scale policy dock dock-clock appearance"
state_save() { mkdir -p $W/state-owner; ( cd $ST && for f in $STATEF; do [ -e $f ] && cp -p $f $W/state-owner/$f; done; shasum -a 256 $STATEF > $W/state-owner.sha 2>/dev/null ); }
state_check() { ( cd $ST; for f in $STATEF; do [ -e $W/state-owner/$f ] || continue; cmp -s $W/state-owner/$f $f || { cp -p $W/state-owner/$f $f.sfsys && mv -f $f.sfsys $f; echo "STATE $f put back from the copy"; }; done
  shasum -a 256 $STATEF > $W/state-after.sha 2>/dev/null; cmp -s $W/state-owner.sha $W/state-after.sha && say "PASS owner's desk state identical ($(wc -l < $W/state-owner.sha) files: theme=$(cat theme) scale=$(cat scale))" || { say "FAIL owner's desk state differs"; diff $W/state-owner.sha $W/state-after.sha; } ); }
# the newest mapped shell surface (a menu) not in the list taken at the start of the pass: x y w h
# (taller than 60 px: the dock's one-line tool tips are not menus)
newest_shell_rect() { req "list $T-sh\n" 30 > /dev/null; grep '^shell' $D/$T-sh.txt | grep 'mapped=true' | while read -r line; do id=$(echo "$line" | cut -d' ' -f2); grep -q "^shell $id " $D/$T-l0.txt || echo "$line"; done | grep -o 'rect=Rect { pos: Point { x: [-0-9]*, y: [-0-9]* }, size: Size { w: [0-9]*, h: [0-9]* }' | while read -r r; do set -- $(echo "$r" | grep -o '[-0-9][0-9]*'); [ "$4" -gt 60 ] && echo "$1 $2 $3 $4"; done | tail -1; }
# quit from the app's own menu (its first menu, last row: "Quit <app>", 48 px above the menu surface's bottom), as the
# owner does; <window> <pid to TERM after 10 s> <processes that must end>
quit_menu() { w=$1; sig=${2:-}; [ $# -ge 2 ] && shift 2 || shift $#
  set_=""; for p in "$@"; do pid_ok "$p" && set_="$set_ $p"; done
  if ! pid_ok "$sig" && [ -z "$set_" ]; then say "FAIL quit_menu refused empty/unsafe pid '${sig:-empty}'"; return 1; fi
  [ -n "$set_" ] || set_="$sig"
  set -- $(wrect $w); [ -n "$4" ] || { quit_set "$sig" 15 $set_; return; }
  click $(( $1 + 45 )) $(( $2 + 17 )) 900; m=$(newest_shell_rect); cap $T-quitmenu 50
  set -- $m; if [ -n "$4" ]; then click $(( $1 + 80 )) $(( $2 + $4 - 48 )) 200; fi; i=0
  while [ -n "$(alive_of $set_)" ] && [ $i -lt 50 ]; do sleep 0.2; i=$((i+1)); done
  if [ -z "$(alive_of $set_)" ]; then say "PASS quit from its menu: all $(nw $set_) processes gone after $((i / 5)).$((i % 5 * 2)) s"; return 0; fi
  say "FAIL quit from its menu: processes left after 10 s ($(alive_of $set_)): TERM as the fallback"; quit_set "$sig" 15 $set_; return 1; }
# every descendant of <pid> and itself (refuses empty or pid <= 1)
tree() { pid_ok "${1:-}" || return 1
  ps ax -o pid=,ppid= > $W/ps.txt; t=" $1 "; n=0; m=1; while [ $n -lt $m ]; do n=$m
  for p in $(awk -v T="$t" 'index(T, " " $2 " ") && !index(T, " " $1 " ") {print $1}' $W/ps.txt); do pid_ok "$p" && t="$t$p "; done; set -- $t; m=$#; done; echo $t; }
alive_of() { for p in "$@"; do pid_ok "$p" && kill -0 "$p" 2>/dev/null && echo "$p"; done | tr '\n' ' '; }
# quit by process: TERM to <pid to signal>; wait up to <s> for every pid of <set> to end; KILL only after that (reported)
quit_set() { sig=${1:-}; s=${2:-15}; [ $# -ge 2 ] && shift 2 || shift $#
  if ! pid_ok "$sig"; then say "FAIL quit_set refused unsafe pid '${sig:-empty}'"; return 1; fi
  set_=""; for p in "$@"; do pid_ok "$p" && set_="$set_ $p"; done
  [ -n "$set_" ] || set_="$sig"
  kill -TERM "$sig" 2>/dev/null; i=0
  while [ -n "$(alive_of $set_)" ] && [ $i -lt $((s * 5)) ]; do sleep 0.2; i=$((i+1)); done
  left=$(alive_of $set_); if [ -z "$left" ]; then say "PASS quit by TERM to $sig: all $(nw $set_) processes gone after $((i / 5)).$((i % 5 * 2)) s"; return 0; fi
  say "FAIL quit by TERM to $sig: still alive after $s s: $left ($(for p in $left; do ps -o comm= -p "$p"; done | tr '\n' ' '))"; kill -KILL $left 2>/dev/null; return 1; }
VLCAPP=org.videolan.vlc
vlc_win() { Wn=""; until=$(( $(date +%s) + ${2:-40} )); while [ $(date +%s) -lt $until ] && [ -z "$Wn" ]; do sleep 0.7
  req "list $1-vw\n" 30 > /dev/null
  Wn=$(grep "^window" $D/$1-vw.txt | grep "app_id=\"$VLCAPP\"" | grep 'mapped=true' | grep -v 'title=""' | grep -v 'Fullscreen Controls' | while read -r line; do
    set -- $(echo "$line" | rect); [ -n "$4" ] && [ "$3" -gt 1000 ] && echo "$(( $3 * $4 )) $(echo "$line" | cut -d' ' -f2)"; done | sort -n | tail -1 | cut -d' ' -f2); done; echo "$Wn"; }
[ -e $W/keys.sh ] && . $W/keys.sh
# a menu of <window>'s strip: its title at <x offset> clicked; PASS when a menu surface appears and Esc closes it
menu_oc() { w=$1; xo=$2; name=$3; set -- $(wrect $w); [ -n "$4" ] || { say "FAIL menu $name: window $w not listed"; return 1; }
  click $(( $1 + xo )) $(( $2 + 17 )) 900; m=$(newest_shell_rect); cap $T-menu-$name 50
  req "target $w\nkey 29 down\nkey 29 up\nwait 600\n" 50 > /dev/null; m2=$(newest_shell_rect)
  ok "menu $name opens ($m) and closes by Esc (${m2:-gone})" '[ -n "$m" ] && [ "$m2" != "$m" ]'; }
# a row of the menu whose title is at <x offset>: <row 1..> (34 px apart, the first 47 px below the surface's top);
# (+N: N px below the surface's top, for menus with separators); with <sub> the row is hovered and the first row of its submenu is clicked
menu_pick() { w=$1; xo=$2; row=$3; sub=${4:-}; srow=${5:-1}; set -- $(wrect $w); click $(( $1 + xo )) $(( $2 + 17 )) 900; m=$(newest_shell_rect)
  set -- $m; [ -n "$4" ] || { say "no menu at $xo"; return 1; }; mx=$(( $1 + 80 )); case $row in +*) my=$(( $2 ${row} ));; *) my=$(( $2 + 47 + 34 * (row - 1) ));; esac
  if [ -z "$sub" ]; then click $mx $my 1200; return 0; fi
  req "abs $(ax $mx) $(ay $my)\nwait 900\n" 50 > /dev/null; s=$(newest_shell_rect); cap $T-sub$(echo $row | tr -d +) 50; set -- $s
  [ -n "$4" ] || { say "no submenu"; return 1; }; click $(( $1 + 80 )) $(( $2 + 47 + 34 * (srow - 1) )) 1500; }
