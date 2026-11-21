#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# Undoes install.sh (nothing else of the system was changed by it). Names each file it removes.
rm -f /usr/share/applications/org.videolan.vlc.desktop
rm -f /Applications/VLC.app/Contents/MacOS/vlc-sf /Applications/VLC.app/Contents/MacOS/vlc-sf.json
rm -f /Applications/VLC.app/Contents/Info.plist /Applications/VLC.app/Contents/PkgInfo /Applications/VLC.app/Contents/Resources
rmdir /Applications/VLC.app/Contents/MacOS /Applications/VLC.app/Contents /Applications/VLC.app
echo removed
