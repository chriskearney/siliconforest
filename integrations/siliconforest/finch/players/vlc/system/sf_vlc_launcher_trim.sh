#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# After the six steps of VLC's system install (docs/roadmap/issues/SF-AH-vlc.md, "Proposal"), the launcher stops
# putting the now-system files in front: its prefix becomes /private/var/db/sfvlc/after-system, which holds only what
# the system does not have:
#   Frameworks/Sparkle.framework   the stand-in for VLC's own Sparkle (must win over the copy inside VLC's bundle)
#   Frameworks/OpenGL.framework, core/libGL.1.dylib, core/libGLU.1.dylib
#                                  CGL with contextHandoff (0009): step 7, deferred; VLC keeps its private CGL
# The account sf and the decoder permission stay in the launcher's code. The full private prefix stays on disk (its
# clean-up is a later, separate job). Runs on the target as root:
#   sh sf_vlc_launcher_trim.sh apply    the after-system directory (copies, hashed against the private ones), then each
#                                       manifest's "prefix" changed; the previous manifest kept as <manifest>.pre-trim
#   sh sf_vlc_launcher_trim.sh undo     each manifest put back from <manifest>.pre-trim (the directory is left)
#   sh sf_vlc_launcher_trim.sh status
P=/private/var/db/sfvlc; K=$P/after-system
MANIFESTS="/Applications/VLC.app/Contents/MacOS/vlc-sf.json $P/app/vlc-sf.json"
say() { echo "SFVLCTRIM $*"; }
die() { say "FAIL $*"; exit 1; }
tree_sum() { (cd "$1" && find . -type f | LC_ALL=C sort | while read -r f; do sha256sum "$f"; done; find . -type l | LC_ALL=C sort | while read -r l; do echo "$l -> $(readlink "$l")"; done) | sha256sum | cut -c1-16; }
case "${1:-}" in
apply)
    for m in $MANIFESTS; do [ -r "$m" ] || die "no $m"; [ ! -e "$m.pre-trim" ] || die "$m.pre-trim exists: applied already (undo first)"; done
    rm -rf "$K.new"; mkdir -p "$K.new/core" "$K.new/Frameworks" || die "mkdir $K.new"
    for f in libGL.1.dylib libGLU.1.dylib; do cp -p "$P/core/$f" "$K.new/core/$f" || die "copy $f"; done
    for d in Sparkle OpenGL; do cp -Rp "$P/Frameworks/$d.framework" "$K.new/Frameworks/" || die "copy $d.framework"; done
    for f in libGL.1.dylib libGLU.1.dylib; do [ "$(sha256sum < "$P/core/$f")" = "$(sha256sum < "$K.new/core/$f")" ] || die "$f differs"; done
    for d in Sparkle OpenGL; do [ "$(tree_sum "$P/Frameworks/$d.framework")" = "$(tree_sum "$K.new/Frameworks/$d.framework")" ] || die "$d.framework differs"; done
    [ ! -e "$K" ] || mv "$K" "$K.old.$(date -u +%Y%m%dT%H%M%SZ)"
    mv "$K.new" "$K" || die "rename $K.new"
    for m in $MANIFESTS; do
        ln "$m" "$m.pre-trim" || die "keep $m"
        /opt/homebrew/bin/python3 - "$m" "$K" <<'PY' || die "rewrite $m"
import json, os, sys
m, k = sys.argv[1], sys.argv[2]
d = json.load(open(m))
d['bundle'] = d.get('bundle') or os.path.join(d.get('prefix', '/private/var/db/sfvlc'), 'vendor/VLC.app')
d['prefix'] = k
d['notes_system'] = ('VLC system install (SF-AH proposal steps 1-6) done: the prefix holds only the Sparkle stand-in and '
                     'CGL 0009 (step 7, deferred); the previous manifest is ' + os.path.basename(m) + '.pre-trim')
open(m + '.sf-new', 'w').write(json.dumps(d, indent=2) + '\n')
os.chmod(m + '.sf-new', 0o644)
os.rename(m + '.sf-new', m)
PY
        say "$m: prefix $K (before: $m.pre-trim)"
    done
    say "applied: $K core [$(ls "$K/core" | tr '\n' ' ')] Frameworks [$(ls "$K/Frameworks" | tr '\n' ' ')]";;
undo)
    for m in $MANIFESTS; do
        [ -e "$m.pre-trim" ] || { say "$m: no $m.pre-trim"; continue; }
        mv -f "$m.pre-trim" "$m" && say "$m put back"
    done;;
status)
    for m in $MANIFESTS; do say "$m: prefix $(/opt/homebrew/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("prefix"))' "$m")$([ -e "$m.pre-trim" ] && echo ' (trimmed; .pre-trim kept)')"; done
    [ -d "$K" ] && say "$K: core [$(ls "$K/core" | tr '\n' ' ')] Frameworks [$(ls "$K/Frameworks" | tr '\n' ' ')]";;
*) sed -n '4,16p' "$0"; exit 2;;
esac
