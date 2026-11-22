# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# after a pass that was cut short: its shell tree, then my own apps (pids recorded by the helpers), then Space 1
p=$(cat $W/pass.pid 2>/dev/null); pid_ok "$p" && [ "$p" != "$$" ] && { s=$(alive_of $(tree "$p")); [ -n "$s" ] && { kill -TERM $s 2>/dev/null; say "pass shell tree ended: $s"; }; }
for t in ff term am pv te cc; do q=$(cat $W/$t.pid 2>/dev/null); pid_ok "$q" || continue; s=$(alive_of $(tree "$q")); [ -n "$s" ] && { kill -TERM $s 2>/dev/null; sleep 3; k=$(alive_of $s); [ -n "$k" ] && kill -KILL $k 2>/dev/null; say "ended my $t: $s"; }; done
v=$(alive_of $(pgrep -x VLC)); [ -n "$v" ] && { kill -TERM $v 2>/dev/null; sleep 15; k=$(alive_of $v); [ -n "$k" ] && kill -KILL $k 2>/dev/null; say "ended VLC $v"; }
left=$(procs "$W/p-ff"); k=$(alive_of $(echo "$left" | awk '{print $1}')); [ -n "$k" ] && { kill -KILL $k 2>/dev/null; say "ended leftovers of my Firefox: $k"; }
[ -e $W/on-space2 ] && say "back to Space 1: $(space_back)"
