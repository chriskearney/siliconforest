#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
#
# Image tests for sf-ext4grow with e2fsprogs as the external oracle (never shipped or linked).
#   scripts/oracle-test.sh [WORKDIR]
# Needs mke2fs, e2fsck, dumpe2fs, debugfs, resize2fs on PATH or in $E2FSPROGS_SBIN, python3, and macOS
# (hdiutil) for the disk-image case. Writes only files under WORKDIR and disk images it attaches itself.
# Optional: SF_REAL_ROOT_DIR=<dir with siliconforest-root.ext4 and root.json> adds the real-root run.
set -euo pipefail
unset SF_REAL_DISK_WRITES SF_ALLOW_REAL_DISK_WRITES || true

here="$(cd "$(dirname "$0")/.." && pwd)"
work="${1:-$(mktemp -d /tmp/sf-ext4grow-test.XXXXXX)}"
mkdir -p "$work"
[[ -n "${E2FSPROGS_SBIN:-}" ]] && export PATH="$E2FSPROGS_SBIN:$PATH"
for t in mke2fs e2fsck dumpe2fs debugfs resize2fs python3; do command -v "$t" >/dev/null || { echo "missing $t" >&2; exit 2; }; done

(cd "$here" && swift build -c release >/dev/null)
"$here/.build/release/sfext4grow-selftest" | tail -1
BIN="$here/.build/release/sf-ext4grow"
DIFF="$here/scripts/diffcheck.py"
FEATURES="has_journal,ext_attr,resize_inode,dir_index,filetype,extent,64bit,flex_bg,sparse_super,large_file,huge_file,dir_nlink,extra_isize,metadata_csum,metadata_csum_seed,^orphan_file"
UUID="37215ab4-59b9-8afb-ab76-394c5ee48edf"
pass=0; failn=0
ok() { echo "ok   $*"; pass=$((pass + 1)); }
bad() { echo "FAIL $*"; failn=$((failn + 1)); }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
fsck_clean() { e2fsck -fn "$1" >"$work/fsck.log" 2>&1; }
norm() { dumpe2fs "$1" 2>/dev/null | grep -Ev '^(Last write time|Lifetime writes|Checksum|Reserved blocks gid):'; }
blocks() { dumpe2fs -h "$1" 2>/dev/null | awk -F: '/^Block count/ {gsub(/ /,"",$2); print $2}'; }
copy() { cp "$1" "$2"; truncate -s "$3" "$2"; }

# A tree with the kinds of entries a root has: files of many sizes, links, nested directories.
make_tree() {
  local t="$1"; rm -rf "$t"; mkdir -p "$t/usr/lib" "$t/etc" "$t/private/var/db" "$t/Library/Firmware"
  python3 - "$t" <<'PY'
import os, random, sys
t = sys.argv[1]; r = random.Random(48)
for i in range(400):
    d = os.path.join(t, "usr/lib", f"d{i % 23}")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, f"f{i}"), "wb") as f:
        f.write(r.randbytes(r.choice([0, 1, 100, 4096, 5000, 70000, 200000])))
for i in range(50):
    os.symlink(f"../usr/lib/d{i % 23}/f{i}", os.path.join(t, "etc", f"l{i}"))
with open(os.path.join(t, "private/var/db/big"), "wb") as f:
    f.write(r.randbytes(8 << 20))
PY
}
make_base() {  # make_base OUT SIZE
  E2FSPROGS_FAKE_TIME=1 mke2fs -q -F -t ext4 -b 4096 -O "$FEATURES" -L SiliconForest -U "$UUID" \
    -E "root_owner=0:0,hash_seed=$UUID,lazy_itable_init=0" -d "$work/tree" "$1" "$2"
}
tree_hash() {  # file contents, link targets and modes, read back through debugfs rdump
  local img="$1" out="$work/rdump"; rm -rf "$out"; mkdir -p "$out"
  debugfs -R "rdump / $out" "$img" >/dev/null 2>&1 || true
  python3 - "$out" <<'PY'
import hashlib, os, sys
root, total = sys.argv[1], hashlib.sha256()
for d, dirs, files in sorted(os.walk(root)):
    dirs.sort()
    for n in sorted(files + [x for x in dirs if os.path.islink(os.path.join(d, x))]):
        p = os.path.join(d, n); rel = os.path.relpath(p, root)
        if os.path.islink(p):
            total.update(f"{rel} l {os.readlink(p)}\n".encode())
        elif os.path.isfile(p):
            h = hashlib.sha256()
            with open(p, "rb") as f:
                for c in iter(lambda: f.read(1 << 20), b""):
                    h.update(c)
            total.update(f"{rel} f {os.stat(p).st_mode & 0o7777:o} {h.hexdigest()}\n".encode())
print(total.hexdigest())
PY
}

make_tree "$work/tree"

# 1. Differential against resize2fs, from three base sizes to several targets (in 4 KiB blocks),
#    including targets that end inside a group and tails too small to keep.
for base_mib in 64 300 2100; do
  base="$work/base-$base_mib.ext4"; make_base "$base" "${base_mib}M"
  fsck_clean "$base" || { bad "base $base_mib MiB is not clean"; continue; }
  files=$(tree_hash "$base")
  bb=$(blocks "$base")
  # Tails around the last-group rule: 0 + itb + 52 for a plain group, + its backup area for a backup group.
  itb=$(dumpe2fs -h "$base" 2>/dev/null | awk -F: '/^Inode blocks per group/ {gsub(/ /,"",$2); print $2}')
  rsv=$(dumpe2fs -h "$base" 2>/dev/null | awk -F: '/^Reserved GDT blocks/ {gsub(/ /,"",$2); print $2}')
  for target in $((bb + 1)) $((bb + 1000)) 32768 98304 $((32768 * 25 + 40)) $((32768 * 25 + 300)) 262145 2097152 $((10 * 262144 + 12345)) \
                $((32768 * 18 + itb + 51)) $((32768 * 18 + itb + 52)) $((32768 * 25 + 2 + rsv + itb + 51)) $((32768 * 25 + 2 + rsv + itb + 52)); do
    (( target > bb )) || continue
    for mode in default lazy; do
      a="$work/a.ext4"; r="$work/r.ext4"
      copy "$base" "$a" $((target * 4096))
      flags=(); [[ $mode == lazy ]] && flags=(--lazy-itables)
      name="base ${base_mib}MiB -> $target blocks ($mode)"
      if ! "$BIN" grow "$a" ${flags[@]+"${flags[@]}"} --write-map "$work/a.map" >"$work/grow.log" 2>&1; then bad "$name: grow failed: $(tail -1 "$work/grow.log")"; continue; fi
      fsck_clean "$a" && ok "$name: e2fsck -fn clean" || bad "$name: e2fsck: $(tail -3 "$work/fsck.log" | tr '\n' ' ')"
      [[ "$(tree_hash "$a")" == "$files" ]] && ok "$name: files identical" || bad "$name: files differ"
      python3 "$DIFF" "$base" "$a" --map "$work/a.map" >"$work/diff.json" && ok "$name: no unlisted block changed" || bad "$name: $(cat "$work/diff.json")"
      if [[ $mode == default ]]; then
        copy "$base" "$r" $((target * 4096)); resize2fs "$r" "$target" >/dev/null 2>&1
        if diff <(norm "$r") <(norm "$a") >"$work/dump.diff"; then ok "$name: dumpe2fs identical to resize2fs"
        else bad "$name: differs from resize2fs ($(blocks "$r") vs $(blocks "$a") blocks): $(head -6 "$work/dump.diff" | tr '\n' ' ')"; fi
      fi
      "$BIN" grow "$a" ${flags[@]+"${flags[@]}"} 2>&1 | grep -q "already grown" && ok "$name: second run is a no-op" || bad "$name: second run not a no-op"
    done
  done
done

# 2. Refusals: each leaves the image byte-for-byte untouched.
base="$work/base-300.ext4"; bb=$(blocks "$base")
refuse() {  # refuse NAME CODE IMAGE [args...]
  local name="$1" code="$2" img="$3"; shift 3
  local before; before=$(sha "$img")
  if "$BIN" grow "$img" "$@" >"$work/ref.log" 2>&1; then bad "refuse $name: grow succeeded"; return; fi
  grep -q "refused: $code" "$work/ref.log" || { bad "refuse $name: wrong reason: $(cat "$work/ref.log")"; return; }
  [[ "$(sha "$img")" == "$before" ]] && ok "refuse $name ($code), image untouched" || bad "refuse $name: image changed"
  rm -f "$img.sf-ext4grow-undo"
}
t="$work/t.ext4"
copy "$base" "$t" $((bb * 4096 * 4)); refuse "shrink" shrink "$t" --blocks $((bb - 10))
copy "$base" "$t" $((bb * 4096 * 4)); debugfs -w -R "feature large_dir" "$t" >/dev/null 2>&1; refuse "unknown feature (large_dir)" unsupported-feature "$t"
copy "$base" "$t" $((bb * 4096 * 4)); debugfs -w -R "feature needs_recovery" "$t" >/dev/null 2>&1; refuse "needs_recovery" journal-dirty "$t"
copy "$base" "$t" $((bb * 4096 * 4)); jb=$(debugfs -R "bmap <8> 0" "$t" 2>/dev/null)
printf '\x00\x00\x00\x01' | dd of="$t" bs=1 seek=$((jb * 4096 + 0x1C)) conv=notrunc 2>/dev/null; refuse "journal holds transactions" journal-dirty "$t"
copy "$base" "$t" $((bb * 4096 * 4)); debugfs -w -R "ssv state 0" "$t" >/dev/null 2>&1; refuse "not cleanly unmounted" not-clean "$t"
copy "$base" "$t" $((bb * 4096 * 4)); printf '\x07' | dd of="$t" bs=1 seek=$((4096 + 64 * 1 + 0x10)) conv=notrunc 2>/dev/null; refuse "group descriptor checksum" checksum "$t"
copy "$base" "$t" $((bb * 4096 * 4)); printf '\x07' | dd of="$t" bs=1 seek=$((1024 + 0x30)) conv=notrunc 2>/dev/null; refuse "superblock checksum" checksum "$t"
copy "$base" "$t" $((bb * 4096 * 4)); bm=$(dumpe2fs "$t" 2>/dev/null | awk '/^Group 0:/ {g=1} g && /Block bitmap at/ {print $4; exit}')
printf '\xff' | dd of="$t" bs=1 seek=$((bm * 4096 + 4000)) conv=notrunc 2>/dev/null; refuse "block bitmap checksum" checksum "$t"
copy "$base" "$t" $((bb * 4096 * 4)); refuse "protected range" protected-range "$t" --protect 4096:4096
copy "$base" "$t" $((bb * 4096 * 4)); : > "$t.sf-ext4grow-undo"; refuse "undo log present" interrupted "$t"
if "$BIN" grow /dev/disk99 --undo-log "$work/u" >"$work/ref.log" 2>&1 || ! grep -q "not-disk-image" "$work/ref.log"; then bad "refuse a device that is not an attached image"; else ok "refuse a device that is not an attached image (not-disk-image)"; fi

# 3. Interrupted grows: stop after each phase, undo, and grow again.
for stage in fresh commit; do
  copy "$base" "$t" $((bb * 4096 * 20))
  "$BIN" grow "$t" --test-stop-after "$stage" --write-map /dev/null >/dev/null 2>&1 || true
  [[ -s "$t.sf-ext4grow-undo" ]] && ok "stopped after $stage: undo log kept" || bad "stopped after $stage: no undo log"
  "$BIN" grow "$t" >/dev/null 2>&1 && bad "stopped after $stage: grow did not refuse" || ok "stopped after $stage: grow refuses until undo"
  "$BIN" undo "$t" --undo-log "$t.sf-ext4grow-undo" >/dev/null 2>&1 && ok "stopped after $stage: undo ran" || bad "stopped after $stage: undo failed"
  fsck_clean "$t" && [[ "$(blocks "$t")" == "$bb" ]] && ok "stopped after $stage: after undo, the old filesystem, fsck clean" || bad "stopped after $stage: after undo: $(tail -2 "$work/fsck.log")"
  "$BIN" grow "$t" >/dev/null 2>&1 && fsck_clean "$t" && ok "stopped after $stage: grows cleanly afterwards" || bad "stopped after $stage: regrow failed"
done

# 4. Through an attached disk image (raw, not mounted), the way the helper reaches a partition.
if command -v hdiutil >/dev/null; then
  img="$work/dev.img"; copy "$base" "$img" $((8 << 30))
  dev=$(hdiutil attach -nomount -imagekey diskimage-class=CRawDiskImage "$img" | awk 'NR==1 {print $1}')
  if [[ "$dev" == /dev/disk* ]] && hdiutil info | grep -q "$dev"; then
    if "$BIN" grow "$dev" --undo-log "$work/dev.undo" >"$work/dev.log" 2>&1; then ok "grow through $dev (attached image)"; else bad "grow through $dev: $(tail -2 "$work/dev.log")"; fi
    hdiutil detach "$dev" >/dev/null
    fsck_clean "$img" && [[ "$(blocks "$img")" == $((8 << 18)) ]] && ok "disk image: fsck clean at 8 GiB" || bad "disk image: $(tail -2 "$work/fsck.log")"
  else
    bad "could not attach $img"; [[ "$dev" == /dev/disk* ]] && hdiutil detach "$dev" >/dev/null || true
  fi
  # A mounted image is refused (an HFS+ volume stands in for anything mounted).
  hdiutil create -quiet -size 8m -fs HFS+ -volname sfx-mounted "$work/mounted.dmg"
  mdev=$(hdiutil attach -nobrowse "$work/mounted.dmg" | awk 'NR==1 {print $1}')
  if "$BIN" grow "$mdev" --undo-log "$work/m.undo" >"$work/ref.log" 2>&1 || ! grep -q "refused: mounted" "$work/ref.log"; then bad "mounted image not refused: $(cat "$work/ref.log")"; else ok "refuse a mounted disk image (mounted)"; fi
  hdiutil detach "$mdev" >/dev/null
  # An image file that is attached is refused as a file target.
  copy "$base" "$img" $((8 << 30)); dev=$(hdiutil attach -nomount -imagekey diskimage-class=CRawDiskImage "$img" | awk 'NR==1 {print $1}')
  refuse "file attached as an image" busy "$img"
  hdiutil detach "$dev" >/dev/null
fi

# 5. The real installer root (M5): 96 GiB, slots, files, and the resize2fs comparison.
if [[ -n "${SF_REAL_ROOT_DIR:-}" ]]; then
  src="$SF_REAL_ROOT_DIR/siliconforest-root.ext4"; files=$(tree_hash "$src")
  for mode in default lazy; do
    a="$work/real-$mode.ext4"; flags=(); [[ $mode == lazy ]] && flags=(--lazy-itables)
    cp "$src" "$a"; truncate -s $((96 << 30)) "$a"
    "$BIN" grow "$a" ${flags[@]+"${flags[@]}"} --root-json "$SF_REAL_ROOT_DIR/root.json" --write-map "$work/real.map" >"$work/grow.log" 2>&1 \
      && ok "real root -> 96 GiB ($mode)" || bad "real root ($mode): $(tail -2 "$work/grow.log")"
    fsck_clean "$a" && ok "real root ($mode): e2fsck -fn clean: $(tail -1 "$work/fsck.log")" || bad "real root ($mode): $(tail -3 "$work/fsck.log")"
    [[ "$(tree_hash "$a")" == "$files" ]] && ok "real root ($mode): every file identical" || bad "real root ($mode): files differ"
    python3 "$DIFF" "$src" "$a" --map "$work/real.map" --root-json "$SF_REAL_ROOT_DIR/root.json" >"$work/real-$mode.json" \
      && ok "real root ($mode): slots identical, untouched; no unlisted change" || bad "real root ($mode): $(cat "$work/real-$mode.json")"
  done
  r="$work/real-rz.ext4"; cp "$src" "$r"; truncate -s $((96 << 30)) "$r"; resize2fs "$r" $((96 << 18)) >/dev/null 2>&1
  diff <(norm "$r") <(norm "$work/real-default.ext4") >/dev/null && ok "real root: dumpe2fs identical to resize2fs" || bad "real root: dumpe2fs differs from resize2fs"
  python3 "$DIFF" "$src" "$work/real-default.ext4" --map "$work/real.map" --reference "$r" >"$work/real-ref.json" || true
  echo "     blocks differing from resize2fs: $(python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["differs_from_reference"]; print(d["count"], d["blocks"])' "$work/real-ref.json")"
fi

echo "oracle-test: $pass passed, $failn failed (work: $work)"
[[ $failn == 0 ]]
