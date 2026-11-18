#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Lay build outputs over an unpacked base root and write the root's manifest.

    assemble.py stage  --root DIR --layers layers.json --files DIR --remove FILE
    assemble.py owners --root DIR --perms FILE --manifest OUT     (run under fakeroot)

`stage` copies every layer (a JSON list of {name, path, prefix, exclude, only}) into DIR
in order (`only`, when given, keeps just the files that match one of its patterns), then the repository's own files (--files, a tree at installed paths), then
deletes the paths listed in --remove. Nothing is read from the build machine outside
the given paths. It prints one line per layer: files written, files replaced.

`owners` gives every entry its owner, group and mode (root:wheel; directories 0755,
files 0755 when any execute bit is set and 0644 otherwise; then the exceptions in
--perms), sets every time stamp to 1 (1970-01-01T00:00:01Z, as Nix does), and writes
the manifest: one line per entry, sorted by path,
    path <TAB> type(f,d,l) <TAB> mode <TAB> uid <TAB> gid <TAB> size <TAB> sha256 or link target
Under fakeroot the owners only exist inside that session: mke2fs must run in the same one.
"""
import argparse, fnmatch, hashlib, json, os, shutil, stat, sys

def excluded(rel, patterns):
    return any(fnmatch.fnmatchcase(rel, p) for p in patterns)

def merge_into(src, dst):
    """Move the entries of directory src into dst; entries dst already has stay as they are."""
    os.makedirs(dst, exist_ok=True)
    for n in sorted(os.listdir(src)):
        s, t = os.path.join(src, n), os.path.join(dst, n)
        if os.path.isdir(s) and not os.path.islink(s) and os.path.isdir(t) and not os.path.islink(t):
            merge_into(s, t)
        elif not os.path.lexists(t):
            os.rename(s, t)

def copy_layer(src, dst_root, prefix, patterns, only=None):
    written = replaced = 0
    base = os.path.join(dst_root, prefix.strip('/'))
    for d, dirs, files in os.walk(src):
        dirs.sort(); files.sort()
        reld = os.path.relpath(d, src)
        reld = '' if reld == '.' else reld
        keep = []
        for n in dirs:
            rel = os.path.join(reld, n)
            p = os.path.join(d, n)
            if excluded(rel, patterns) or excluded(rel + '/', patterns):
                continue
            if os.path.islink(p):
                files.append(n)          # a link to a directory is copied as a link
            else:
                keep.append(n)
                if not only:
                    os.makedirs(os.path.join(base, rel), exist_ok=True)
        dirs[:] = keep
        for n in sorted(set(files)):
            rel = os.path.join(reld, n)
            if excluded(rel, patterns) or (only and not excluded(rel, only)):
                continue
            s, t = os.path.join(d, n), os.path.join(base, rel)
            os.makedirs(os.path.dirname(t), exist_ok=True)
            if os.path.lexists(t):
                if os.path.isdir(t) and not os.path.islink(t):
                    link = os.readlink(s) if os.path.islink(s) else None
                    if not link or '/' in link.strip('/') or link.startswith('/'):
                        sys.exit('layer would replace the directory %s with a file' % t)
                    # a framework's Versions/Current: an earlier layer made it a directory, this
                    # one makes it the link to a sibling version: keep the earlier files there
                    sib = os.path.join(os.path.dirname(t), link)
                    merge_into(t, sib)
                    shutil.rmtree(t)
                else:
                    os.unlink(t)
                replaced += 1
            if os.path.islink(s):
                os.symlink(os.readlink(s), t)
            else:
                shutil.copyfile(s, t)
                os.chmod(t, 0o755 if os.stat(s).st_mode & 0o111 else 0o644)
            written += 1
    return written, replaced

def stage(a):
    for layer in json.load(open(a.layers)):
        w, r = copy_layer(layer['path'], a.root, layer.get('prefix', '/'), layer.get('exclude', []), layer.get('only'))
        print('layer %-28s %6d files, %5d replaced  -> %s' % (layer['name'], w, r, layer.get('prefix', '/')))
    if a.files:
        w, r = copy_layer(a.files, a.root, '/', [])
        print('layer %-28s %6d files, %5d replaced' % ('repository files', w, r))
    if a.remove:
        n = 0
        for line in open(a.remove):
            line = line.split('#', 1)[0].strip()
            if not line:
                continue
            p = os.path.join(a.root, line.strip('/'))
            if os.path.isdir(p) and not os.path.islink(p):
                shutil.rmtree(p); n += 1
            elif os.path.lexists(p):
                os.unlink(p); n += 1
        print('removed %d paths' % n)

def owners(a):
    exceptions = []   # (pattern, mode or None, uid, gid)
    for line in open(a.perms):
        line = line.split('#', 1)[0].strip()
        if not line:
            continue
        pat, mode, owner = line.split()
        uid, gid = owner.split(':')
        exceptions.append((pat, None if mode == '-' else int(mode, 8), int(uid), int(gid)))
    rows = []
    for d, dirs, files in os.walk(a.root):
        dirs.sort()
        for n in sorted(dirs) + sorted(files) + (['.'] if d == a.root else []):
            p = os.path.normpath(os.path.join(d, n))
            rel = '/' + os.path.relpath(p, a.root) if p != os.path.normpath(a.root) else '/'
            st = os.lstat(p)
            if stat.S_ISLNK(st.st_mode):
                t, mode = 'l', 0o777
            elif stat.S_ISDIR(st.st_mode):
                t, mode = 'd', 0o755
            elif stat.S_ISREG(st.st_mode):
                t, mode = 'f', 0o755 if st.st_mode & 0o111 else 0o644
            else:
                sys.exit('unexpected file type: ' + rel)
            uid = gid = 0
            for pat, m, u, g in exceptions:
                if fnmatch.fnmatchcase(rel, pat):
                    if m is not None and t != 'l':
                        mode = m
                    uid, gid = u, g
            os.lchown(p, uid, gid)
            if t != 'l':
                os.chmod(p, mode)
            os.utime(p, (1, 1), follow_symlinks=False)
            if t == 'f':
                h = hashlib.sha256()
                with open(p, 'rb') as fh:
                    for b in iter(lambda: fh.read(1 << 20), b''):
                        h.update(b)
                what, size = h.hexdigest(), st.st_size
            elif t == 'l':
                what, size = os.readlink(p), len(os.readlink(p))
            else:
                what, size = '-', 0
            rows.append((rel, t, '%04o' % mode, uid, gid, size, what))
    rows.sort()
    with open(a.manifest, 'w', encoding='utf-8', errors='surrogateescape') as o:
        o.write('# path\ttype\tmode\tuid\tgid\tsize\tsha256 or link target\n')
        for r in rows:
            o.write('%s\t%s\t%s\t%d\t%d\t%d\t%s\n' % r)
    print('manifest: %d entries, %d files, %d bytes' % (len(rows), sum(r[1] == 'f' for r in rows), sum(r[5] for r in rows if r[1] == 'f')))

def main():
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest='cmd', required=True)
    s = sp.add_parser('stage'); s.add_argument('--root', required=True); s.add_argument('--layers', required=True)
    s.add_argument('--files'); s.add_argument('--remove')
    o = sp.add_parser('owners'); o.add_argument('--root', required=True); o.add_argument('--perms', required=True)
    o.add_argument('--manifest', required=True)
    a = ap.parse_args()
    stage(a) if a.cmd == 'stage' else owners(a)

if __name__ == '__main__':
    main()
