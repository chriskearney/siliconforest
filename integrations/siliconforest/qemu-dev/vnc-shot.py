#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Pictures of a QEMU guest's screen through QEMU's VNC server on a Unix socket (-vnc unix:PATH),
without QMP (a QMP screen dump hung QEMU on this host while the guest's compositor drew).

This copy sits next to m6-hvf-check.py so the M6 check does not depend on the release tree.

    vnc-shot.py SOCKET OUTDIR [--every SECONDS] [--count N]
    vnc-shot.py SOCKET --type TEXT       type TEXT and Return on the guest's keyboard (VNC key
                                         events: QEMU turns them into its emulated USB keyboard's
                                         reports); lower case, digits, space and - . ; / only

Speaks the plain RFB 3.8 protocol, security "None", raw encoding, 32-bit pixels; writes
OUTDIR/NNN.ppm (portable pixmap: any image tool reads it) every SECONDS until N pictures or the
socket closes. Standard library only.
"""
import argparse, os, socket, struct, time

def recv(s, n):
    b = b''
    while len(b) < n:
        c = s.recv(n - len(b))
        if not c:
            raise EOFError
        b += c
    return b

def connect(path):
    s = socket.socket(socket.AF_UNIX); s.settimeout(120); s.connect(path)
    return s

def handshake(s):
    recv(s, 12); s.sendall(b'RFB 003.008\n')
    n = recv(s, 1)[0]
    types = recv(s, n)
    if 1 not in types:
        raise RuntimeError('VNC server wants authentication')
    s.sendall(b'\x01')
    if struct.unpack('>I', recv(s, 4))[0] != 0:
        raise RuntimeError('VNC security handshake failed')
    s.sendall(b'\x01')                                        # shared
    w, h = struct.unpack('>HH', recv(s, 4)); recv(s, 16); recv(s, struct.unpack('>I', recv(s, 4))[0])
    return w, h

def type_text(path, text):
    s = connect(path); handshake(s)
    allowed = set('abcdefghijklmnopqrstuvwxyz0123456789 -.;/')
    if set(text) - allowed:
        raise SystemExit('vnc-shot: --type takes only ' + ''.join(sorted(allowed)))
    for key in [ord(c) for c in text] + [0xff0d]:
        for down in (1, 0):
            s.sendall(struct.pack('>BBxxI', 4, down, key)); time.sleep(0.08)
        time.sleep(0.25)
    s.close()

def shot(path, out):
    s = connect(path); w, h = handshake(s)
    # 32 bpp, depth 24, little endian, true colour, R at 16, G at 8, B at 0
    s.sendall(struct.pack('>B3xBBBBHHHBBB3x', 0, 32, 24, 0, 1, 255, 255, 255, 16, 8, 0))
    s.sendall(struct.pack('>BxHi', 2, 1, 0))                  # encodings: raw only
    s.sendall(struct.pack('>BBHHHH', 3, 0, 0, 0, w, h))       # full update
    fb = bytearray(w * h * 4)
    while True:
        t = recv(s, 1)[0]
        if t == 0:
            recv(s, 1); nrect = struct.unpack('>H', recv(s, 2))[0]
            for _ in range(nrect):
                x, y, rw, rh, enc = struct.unpack('>HHHHi', recv(s, 12))
                if enc == -223:                                # desktop size
                    w, h = rw, rh; fb = bytearray(w * h * 4)
                    s.sendall(struct.pack('>BBHHHH', 3, 0, 0, 0, w, h)); continue
                if enc != 0:
                    raise RuntimeError('unexpected encoding %d' % enc)
                data = recv(s, rw * rh * 4)
                for row in range(rh):
                    o = ((y + row) * w + x) * 4
                    fb[o:o + rw * 4] = data[row * rw * 4:(row + 1) * rw * 4]
            break
        elif t == 2:
            pass                                               # bell
        elif t == 3:
            recv(s, 3); recv(s, struct.unpack('>I', recv(s, 4))[0])
        else:
            raise RuntimeError('unexpected message %d' % t)
    s.close()
    rgb = bytearray(w * h * 3)
    rgb[0::3] = fb[2::4]; rgb[1::3] = fb[1::4]; rgb[2::3] = fb[0::4]
    with open(out, 'wb') as f:
        f.write(b'P6\n%d %d\n255\n' % (w, h)); f.write(rgb)

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('socket'); ap.add_argument('outdir', nargs='?')
    ap.add_argument('--every', type=float, default=30); ap.add_argument('--count', type=int, default=1000)
    ap.add_argument('--type')
    a = ap.parse_args()
    if a.type is not None:
        type_text(a.socket, a.type); return
    os.makedirs(a.outdir, exist_ok=True)
    for i in range(1, a.count + 1):
        try:
            shot(a.socket, os.path.join(a.outdir, '%03d.ppm' % i))
        except FileNotFoundError:
            pass
        except (EOFError, ConnectionRefusedError, ConnectionResetError, socket.timeout):
            if not os.path.exists(a.socket):
                break
        time.sleep(a.every)

if __name__ == '__main__':
    main()
