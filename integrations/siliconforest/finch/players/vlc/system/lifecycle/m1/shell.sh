#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# SYSINSTALL: my Terminal's shell: zsh without the owner's rc files, in a home of my own
export TERM=xterm-256color PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin HOME=/private/var/db/sfsysinst/home-term PROMPT='%n@%m %1~ %# '
cd $HOME; exec /bin/zsh -f -i
