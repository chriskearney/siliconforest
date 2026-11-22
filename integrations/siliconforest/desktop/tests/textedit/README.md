# TextEdit on the SiliconForest desk

Unmodified TextEdit 1.20 (executable SHA-256
`98db1c6a0170fd624cee7b1f06a5f396f24e56bcd00831cf8e7cb17de6f0a13f`,
782,384 bytes; bundle manifest
`71348ff33b71b71191619662832d0126ac6c759a701b2a48b9b05f0324ef579c`,
69 files, 1,926,987 bytes). The AppKit front is
`integrations/siliconforest/finch/TextEdit`. The open wrapper is
`desktop/system/sf-open-textedit`.

`scene.py` holds `/home/chrisk/src/darwin-lab/runs/m1-coord/gui.lock`, turns on `window_position`
for the launch, opens the three documents in `docs/`, opens Apple
Terminal 2.15 with two extra tabs, hides Terminal's menu strip only,
switches the desk to the built-in theme `sf-wafer`, and takes a
screenshot. It turns `window_position` back off before it returns.
The theme stays on `sf-wafer`.

Terminal is the unmodified system binary. The only extra library is
`libSFTermPlace.dylib`, inserted so the window opens in the top-right
cell and two more tabs open in that window. The TextEdit AppKit overlay
is not on Terminal's library path. With that overlay, dyld aborts while
loading `libc++`. After the shells start, the harness writes one short
note into each tab with `TIOCSTI` and clears zsh's `_title_precmd`,
which would otherwise put `user@host` back in the tab title. The insert
itself cannot see the pty file descriptors (`SF_TERM_TABS` reports
`wrote=0`). The tab titles it leaves are `forest`, `wafer`, and `menu`.

Revert the theme:

```
XDG_RUNTIME_DIR=/private/var/run/gpu-desktop WAYLAND_DISPLAY=wayland-0 \
  /usr/bin/chonkstep-darwin-desktop --desktop-request theme sf-canopy
```

or `desk_m1.sh theme sf-canopy` with those two variables set.

Show Terminal's menu strip again, while that process is still up:

```
printf 'menubar show\n' | nc -U /private/var/run/gpu-desktop/app-menu/<pid>
```

The answer is `ok shown`. TextEdit's strip is never hidden.
`window_position=off` is the desk default; the scene script writes it
back. Do not relaunch the compositor for any of this.
