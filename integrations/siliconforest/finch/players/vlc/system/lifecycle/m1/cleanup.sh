# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# after a pass that was cut short: its shell tree, then my own apps (pids recorded by the helpers), then Space 1
p=$(cat $W/pass.pid 2>/dev/null); [ -n "$p" ] && [ "$p" != "$$" ] && { s=$(tree $p); kill -TERM $s 2>/dev/null; say "pass shell tree ended: $s"; }
for t in ff term am; do q=$(cat $W/$t.pid 2>/dev/null); [ -n "$q" ] || continue; s=$(alive_of $(tree $q)); [ -n "$s" ] && { kill -TERM $s; sleep 3; kill -KILL $(alive_of $s) 2>/dev/null; say "ended my $t: $s"; }; done
v=$(pgrep -x VLC); [ -n "$v" ] && { kill -TERM $v; sleep 15; kill -KILL $(alive_of $v) 2>/dev/null; say "ended VLC $v"; }
left=$(procs "$W/p-ff"); [ -n "$left" ] && { echo "$left" | awk '{print $1}' | xargs kill -KILL; say "ended leftovers of my Firefox"; }
[ -e $W/on-space2 ] && say "back to Space 1: $(space_back)"
