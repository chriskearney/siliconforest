#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Check a downloaded SiliconForest release before anything is written to a disk.

    sf_verify_release.py DIR [--allowed-signers FILE] [--unsigned-ok]

1. SHA256SUMS.sig is an SSH signature over SHA256SUMS (namespace siliconforest-release) by a
   key in the allowed-signers file (`ssh-keygen -Y verify`; OpenSSH 8.1 or later, which macOS
   and every current Linux have). Without --allowed-signers, or with --unsigned-ok on a
   release that has no signature, this step is skipped and the result says so.
2. Every file SHA256SUMS names exists and has that sha256; MANIFEST.tsv agrees on sizes.
3. The root parts, concatenated in name order and decompressed (zstd), have the size and
   sha256 of the line marked `uncompressed` in MANIFEST.tsv.
Exit status 0 only when every step that ran passed. Prints one JSON object.
"""
import argparse, hashlib, json, os, subprocess, sys

NAMESPACE = 'siliconforest-release'
IDENTITY = 'release@siliconforest'

def sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('dir'); ap.add_argument('--allowed-signers'); ap.add_argument('--unsigned-ok', action='store_true')
    a = ap.parse_args()
    res = {'signature': 'not checked', 'files': {}, 'root': None, 'ok': False}
    sums = os.path.join(a.dir, 'SHA256SUMS')
    sig = sums + '.sig'
    if a.allowed_signers and os.path.exists(sig):
        with open(sums, 'rb') as f:
            r = subprocess.run(['ssh-keygen', '-Y', 'verify', '-f', a.allowed_signers, '-I', IDENTITY,
                                '-n', NAMESPACE, '-s', sig], stdin=f, capture_output=True, text=True)
        res['signature'] = 'good' if r.returncode == 0 else 'BAD: ' + (r.stderr or r.stdout).strip()
        if r.returncode:
            print(json.dumps(res)); sys.exit(1)
    elif not a.unsigned_ok:
        res['signature'] = 'MISSING (no SHA256SUMS.sig or no --allowed-signers; --unsigned-ok to go on)'
        print(json.dumps(res)); sys.exit(1)
    want = {}
    for line in open(sums):
        d, n = line.rstrip('\n').split('  ', 1)
        if '/' in n or n.startswith('.'):
            sys.exit('SHA256SUMS names a path outside the release: ' + n)
        want[n] = d
    sizes, uncompressed = {}, None
    for line in open(os.path.join(a.dir, 'MANIFEST.tsv')):
        if line.startswith('#'):
            continue
        f = line.rstrip('\n').split('\t')
        if len(f) == 4 and f[3] == 'uncompressed':
            uncompressed = (int(f[1]), f[2])
        else:
            sizes[f[0]] = int(f[1])
    bad = False
    for n, d in sorted(want.items()):
        p = os.path.join(a.dir, n)
        ok = os.path.isfile(p) and sha(p) == d and (n not in sizes or os.path.getsize(p) == sizes[n])
        res['files'][n] = 'ok' if ok else 'BAD'
        bad |= not ok
    parts = sorted(n for n in want if '-root.ext4.zst.' in n)
    if not bad and parts and uncompressed:
        h, size = hashlib.sha256(), 0
        z = subprocess.Popen(['zstd', '-d', '-c', '--long=27'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        import threading
        def feed():
            for n in parts:
                with open(os.path.join(a.dir, n), 'rb') as f:
                    for b in iter(lambda: f.read(1 << 20), b''):
                        z.stdin.write(b)
            z.stdin.close()
        t = threading.Thread(target=feed); t.start()
        for b in iter(lambda: z.stdout.read(1 << 20), b''):
            h.update(b); size += len(b)
        t.join(); z.wait()
        res['root'] = 'ok' if z.returncode == 0 and (size, h.hexdigest()) == uncompressed else 'BAD'
        bad |= res['root'] != 'ok'
    else:
        res['root'] = 'not checked'
        bad = True
    res['ok'] = not bad
    print(json.dumps(res, sort_keys=True))
    sys.exit(0 if res['ok'] else 1)

if __name__ == '__main__':
    main()
