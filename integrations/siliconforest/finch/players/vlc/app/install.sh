#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# /Applications/VLC.app: a small bundle the desktop starts (its executable is the launcher, vlc-sf),
# beside the untouched VLC bundle in /private/var/db/sfvlc/vendor; and a launcher entry for the dock.
# No framework or library of the system is changed. Undo: uninstall.sh
set -e
V=/private/var/db/sfvlc/vendor/VLC.app
A=/Applications/VLC.app
[ ! -e $A ] || { echo "$A exists already"; exit 1; }
mkdir -p $A/Contents/MacOS
/opt/homebrew/bin/python3 - $V/Contents/Info.plist $A/Contents/Info.plist <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], 'rb'))
d['CFBundleExecutable'] = 'vlc-sf'          # the launcher; VLC's own executable stays in the vendor bundle
plistlib.dump(d, open(sys.argv[2], 'wb'))
PY
cp $V/Contents/PkgInfo $A/Contents/PkgInfo
ln -s $V/Contents/Resources $A/Contents/Resources
cp /private/var/db/sfvlc/bin/vlc-sf $A/Contents/MacOS/vlc-sf
cp /private/var/db/sfvlc/app/vlc-sf.json $A/Contents/MacOS/vlc-sf.json
chmod 755 $A/Contents/MacOS/vlc-sf
cp /private/var/db/sfvlc/app/org.videolan.vlc.desktop /usr/share/applications/org.videolan.vlc.desktop
chmod 644 /usr/share/applications/org.videolan.vlc.desktop
echo installed
