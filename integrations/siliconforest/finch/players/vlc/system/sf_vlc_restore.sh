#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# VLC's changes system-wide, one step at a time, and the way back (docs/roadmap/issues/SF-AH-vlc.md,
# "Proposal: installing VLC's changes system-wide"). Runs on the target as root:
#   sh sf_vlc_restore.sh forward <stage> <step>   install one step of the stage (sf_vlc_system.sh stage)
#   sh sf_vlc_restore.sh back [<step> ...]        put back what the steps replaced (default: every installed
#                                                 step, the last installed first)
#   sh sf_vlc_restore.sh status                   the installed steps and their files
#   sh sf_vlc_restore.sh snapshot <stage> <out>   the state of every path the stage names, for comparisons
# A stage step is <stage>/step<N>/list, lines "<f|l> <absolute path> <sha256|link target> <mode>", the new
# files under <stage>/step<N>/files/<path>, and for a file every program loads <stage>/step<N>/core, one line
# "<probe> [program ...]": its files go through the guarded installer (<stage>/sf-lib-install.sh).
# Forward: the new file is written beside the path as <path>.sf-new and hashed there (nothing has mapped it,
# so the bytes read are the bytes written), the file in use gets the second name <path>.pre-vlc (a hard link:
# the same inode, so the way back is the same bytes, whatever the page cache shows of a file in use), and the
# new file takes the name by rename(2). A path that did not exist is recorded as absent, a directory made is
# recorded. Back: <path>.pre-vlc takes its name again by rename(2), what was absent is removed, the
# directories made are removed, the guarded installer's own .old name of the same inode is removed, and the
# state is compared with the record: the same inode, mode, owner and size at every path, nothing left over.
# A failure part-way through a step puts that step back at once. Records: /private/var/db/sfvlc-system.
PATH=/bin:/sbin:/usr/bin:/usr/sbin; export PATH
R=${SFVLC_SYSTEM_RECORDS:-/private/var/db/sfvlc-system}
say() { echo "SFVLCSYS $*"; }
die() { say "FAIL $*"; exit 1; }
sum() { sha256sum "$1" 2>/dev/null | cut -c1-64; }
ino() { ls -id "$1" 2>/dev/null | awk '{print $1}'; }
meta() { ls -ldn "$1" 2>/dev/null | awk '{print $1, $3, $4, $5}'; }   # mode uid gid size
exists() { [ -e "$1" ] || [ -L "$1" ]; }

# put back what a record lists (last line first); $1 the record, $2 the directories made
undo() {
    rec=$1; dirs=$2; bad=0
    [ -r "$rec" ] || return 0
    awk '{a[NR]=$0} END {for (i = NR; i > 0; i--) print a[i]}' "$rec" > "$rec.rev"
    while read -r kind path was oino osum ometa old; do
        case "$was" in
        file)
            if [ -e "$path.pre-vlc" ] && [ "$(ino "$path.pre-vlc")" = "$oino" ]; then
                mv -f "$path.pre-vlc" "$path" || { say "could not rename $path.pre-vlc to $path"; bad=1; }
            elif [ "$(ino "$path")" = "$oino" ]; then say "$path is the file of before already"
            else say "$path: no $path.pre-vlc of inode $oino"; bad=1; fi
            if [ "$old" != - ] && [ -e "$old" ]; then
                if [ "$(ino "$old")" = "$oino" ]; then rm -f "$old"; else say "$old is not inode $oino: left"; bad=1; fi
            fi;;
        absent) rm -f "$path";;
        esac
        rm -f "$path.sf-new"
    done < "$rec.rev"
    rm -f "$rec.rev"
    if [ -r "$dirs" ]; then
        awk '{a[NR]=$0} END {for (i = NR; i > 0; i--) print a[i]}' "$dirs" | while read -r d; do
            rmdir "$d" 2>/dev/null || say "directory $d not empty: left"
        done
    fi
    sync
    # the state against the record
    while read -r kind path was oino osum ometa old; do
        rest=$(echo "$ometa" | tr , ' ')
        case "$was" in
        file)
            [ "$(ino "$path")" = "$oino" ] || { say "AFTER $path is inode $(ino "$path"), was $oino"; bad=1; }
            [ "$(meta "$path")" = "$rest" ] || { say "AFTER $path is $(meta "$path"), was $rest"; bad=1; }
            s=$(sum "$path"); [ "$s" = "$osum" ] || say "AFTER $path reads as sha256 $s, before $osum (the same inode: the page cache of a file in use)";;
        absent) ! exists "$path" || { say "AFTER $path is still there"; bad=1; };;
        esac
        ! exists "$path.pre-vlc" || { say "AFTER $path.pre-vlc is left"; bad=1; }
        ! exists "$path.sf-new" || { say "AFTER $path.sf-new is left"; bad=1; }
    done < "$rec"
    return $bad
}

forward() {
    S=$1; N=$2; D=$S/step$N; L=$D/list
    [ -r "$L" ] || die "no $L"
    mkdir -p "$R" || die "cannot make $R"
    [ ! -e "$R/step$N.done" ] || { say "step $N is installed already ($R/step$N.done); back first"; exit 0; }
    rm -f "$R/step$N.partial" "$R/step$N.dirs"
    core=; [ -r "$D/core" ] && core=$(cat "$D/core")
    # 1. checks: nothing is changed before all pass
    while read -r kind path want mode; do
        case "$kind" in
        f) [ "$(sum "$D/files$path")" = "$want" ] || die "the staged $path is not the file expected (sha256 $(sum "$D/files$path"))"
           [ ! -L "$path" ] || die "$path is a link: not replaced by this script"
           [ ! -d "$path" ] || die "$path is a directory";;
        l) ! exists "$path" || [ "$(readlink "$path")" = "$want" ] || die "$path exists: links are only made where nothing is";;
        *) die "line of $L: $kind $path";;
        esac
        ! exists "$path.pre-vlc" || die "$path.pre-vlc exists: an earlier install was not put back"
    done < "$L"
    [ -z "$core" ] || [ -r "$S/sf-lib-install.sh" ] || die "a core step without $S/sf-lib-install.sh"
    say "step $N: $(grep -c . "$L") paths checked${core:+ (core files: the guarded installer, probe ${core%% *})}"
    # 2. the install, recorded line by line; a failure puts the step back
    while read -r kind path want mode; do
        p=$(dirname "$path"); made=
        while [ ! -d "$p" ]; do made="$p $made"; p=$(dirname "$p"); done
        for d in $made; do mkdir "$d" && chmod 755 "$d" && chown 0:0 "$d" && echo "$d" >> "$R/step$N.dirs" || { undo "$R/step$N.partial" "$R/step$N.dirs"; die "mkdir $d"; }; done
        if [ "$kind" = l ]; then
            if exists "$path"; then say "$path is the link wanted already"; continue; fi
            echo "l $path absent - - - -" >> "$R/step$N.partial"
            ln -s "$want" "$path" || { undo "$R/step$N.partial" "$R/step$N.dirs"; die "link $path"; }
            continue
        fi
        if [ -e "$path" ]; then
            oino=$(ino "$path"); osum=$(sum "$path"); ometa=$(meta "$path" | tr ' ' ,)
            olds=$(ls -d "$path".old* 2>/dev/null | tr '\n' ' ')
            ln "$path" "$path.pre-vlc" && [ "$(ino "$path.pre-vlc")" = "$oino" ] || { rm -f "$path.pre-vlc"; undo "$R/step$N.partial" "$R/step$N.dirs"; die "could not keep $path as $path.pre-vlc"; }
            was=file
        else oino=-; osum=-; ometa=-; olds=; was=absent; fi
        cat "$D/files$path" > "$path.sf-new" && sync || { rm -f "$path.sf-new" "$path.pre-vlc"; undo "$R/step$N.partial" "$R/step$N.dirs"; die "write $path.sf-new"; }
        if [ -n "$core" ] && [ "$was" = file ]; then
            # shellcheck disable=SC2086
            sh "$S/sf-lib-install.sh" "$path" "$path.sf-new" "$want" $core < /dev/null 2>&1 | sed 's/^/SFVLCSYS   /' | tee "$R/step$N.lib.out"
            if ! grep -q '^SFVLCSYS   SFLIB 3 installed' "$R/step$N.lib.out" || grep -q 'SFLIB FAIL' "$R/step$N.lib.out"; then
                rm -f "$path.pre-vlc" "$path.sf-new"; undo "$R/step$N.partial" "$R/step$N.dirs"; die "the guarded installer did not install $path"
            fi
            old=-; for k in "$path".old*; do
                case " $olds " in *" $k "*) continue;; esac
                [ "$(ino "$k")" = "$oino" ] && old=$k
            done
            echo "f $path $was $oino $osum $ometa $old" >> "$R/step$N.partial"
        else
            chown 0:0 "$path.sf-new" && chmod "$mode" "$path.sf-new" || { rm -f "$path.sf-new" "$path.pre-vlc"; undo "$R/step$N.partial" "$R/step$N.dirs"; die "owner/mode of $path.sf-new"; }
            [ "$(sum "$path.sf-new")" = "$want" ] || { rm -f "$path.sf-new" "$path.pre-vlc"; undo "$R/step$N.partial" "$R/step$N.dirs"; die "$path.sf-new is not the file staged"; }
            echo "f $path $was $oino $osum $ometa -" >> "$R/step$N.partial"
            mv -f "$path.sf-new" "$path" || { undo "$R/step$N.partial" "$R/step$N.dirs"; die "rename $path.sf-new"; }
        fi
    done < "$L"
    sync
    mv "$R/step$N.partial" "$R/step$N.done"; date -u +%FT%TZ > "$R/step$N.when"; echo "$N" >> "$R/order"
    n=$(grep -c ' file ' "$R/step$N.done"); a=$(grep -c ' absent ' "$R/step$N.done")
    say "step $N installed: $n files replaced (each kept as .pre-vlc), $a paths new; back: sh $0 back $N"
}

back() {
    steps=$*
    [ -n "$steps" ] || steps=$(awk '{a[NR]=$0} END {for (i = NR; i > 0; i--) print a[i]}' "$R/order" 2>/dev/null)
    [ -n "$steps" ] || { say "nothing installed"; exit 0; }
    rc=0
    for N in $steps; do
        [ -r "$R/step$N.done" ] || { say "step $N is not installed"; continue; }
        if undo "$R/step$N.done" "$R/step$N.dirs"; then
            t=$(date -u +%Y%m%dT%H%M%SZ); mkdir -p "$R/history"
            for x in done dirs when lib.out; do [ -e "$R/step$N.$x" ] && mv "$R/step$N.$x" "$R/history/step$N.$x.$t"; done
            grep -v "^$N\$" "$R/order" > "$R/order.new"; mv "$R/order.new" "$R/order"
            say "step $N put back: every path as before (inode, mode, owner, size), nothing left over"
        else say "FAIL step $N: see the lines above; the record stays ($R/step$N.done)"; rc=1; fi
    done
    sync; return $rc
}

case "${1:-}" in
forward) [ $# = 3 ] || die "forward <stage> <step>"; forward "$2" "$3";;
back) shift; back "$@";;
status) for f in "$R"/step*.done; do [ -r "$f" ] && { say "$(basename "$f" .done) installed $(cat "${f%.done}.when" 2>/dev/null):"; sed 's/^/SFVLCSYS   /' "$f"; }; done; [ -r "$R/order" ] || say "nothing installed";;
snapshot)
    [ $# = 3 ] || die "snapshot <stage> <out>"
    : > "$3"
    cat "$2"/step*/list | while read -r kind path want mode; do
        for x in "$path" "$path.pre-vlc" "$path.sf-new"; do
            if [ -L "$x" ]; then echo "$x link $(readlink "$x")"
            elif [ -e "$x" ]; then echo "$x file $(ino "$x") $(meta "$x") $(sum "$x")"
            elif [ "$x" = "$path" ]; then echo "$x absent"; fi
        done
    done >> "$3";;
*) sed -n '4,9p' "$0"; exit 2;;
esac
