# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# QuickTime Player from QTP2's private set (runs/qtp/FOR-DEMO.md, requests-for-QTP.md): launches, plays (space), stops
B=/private/var/db/sfqtp/load-20261118T091237Z; QH=$W/home-qt; QT="QTP_BUNDLE=$B /opt/homebrew/bin/python3 $B/qtp_m1.py"
req "list $T-l0\n" > /dev/null; say "to Space 2: $(space_next)"
rm -rf $QH; mkdir -p $QH; a0=$(avd)
say "launch: $(cd $B && env QTP_BUNDLE=$B /opt/homebrew/bin/python3 $B/qtp_m1.py launch sysi-$T ARGS=-NSOpen+/Users/sf/Movies/bbb-1080p-h264-aac-30s.mp4 HOME=$QH CFFIXED_USER_HOME=$QH 2>&1 | tail -2 | tr '\n' ' ')"
sleep 9; req "list $T-q\n" 30 > /dev/null
WQ=$(grep '^window' $D/$T-q.txt | grep 'app_id="com.apple.QuickTimePlayerX"' | grep 'mapped=true' | cut -d' ' -f2 | sort -n | tail -1)
ok "QuickTime window mapped ($WQ: $(grep "^window $WQ " $D/$T-q.txt | sed -E 's/.* title="([^"]*)".*/\1/'))" '[ -n "$WQ" ]'
if [ -n "$WQ" ]; then
  mods_clear $WQ > /dev/null; a1=$(avd); typ $WQ "$SPACE" > /dev/null; sleep 3; cap $T-a 50; sleep 2.5; cap $T-b 50; a2=$(avd)
  ok "QuickTime plays (decoder jobs $a0 -> $a1 -> $a2)" '[ "$a2" -gt $(( a1 + 30 )) ]'
fi
say "stop: $(cd $B && env QTP_BUNDLE=$B /opt/homebrew/bin/python3 $B/qtp_m1.py stop sysi-$T 2>&1 | tail -2 | tr '\n' ' ')"; sleep 1
say "status: $(cd $B && env QTP_BUNDLE=$B /opt/homebrew/bin/python3 $B/qtp_m1.py status sysi-$T 2>&1 | tail -3 | tr '\n' ' ' | cut -c1-300)"
ok "no QuickTime process left" '[ -z "$(pgrep -f "QuickTime Player.app/Contents/MacOS")" ]'
say "back to Space 1: $(space_back)"
