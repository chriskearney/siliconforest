#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""ChonkCraft perf: draw the terrain from a visible slice at every game scale.

At game scale 1 GameScreen.drawTerrain draws the whole map image (8-bit indexed,
recoloured for palette cycling every 5 ticks) straight onto the window's OpenGL
surface. Java2D's OGLGeneralBlit converts the WHOLE source image to IntArgbPre
before the upload (the clip is applied only afterwards), and every recoloured
image is a new managed image cached again in full: on the M1 the EDT spent ~27%
of its time in ByteIndexedToIntArgbPreConvert and the flusher uploaded the map.
The slice path the game already uses above scale 1 converts only the visible
rectangle into an IntRgb image and draws that 1:1: same pixels, a fraction of
the work.

The change is one byte in drawTerrain: `gameScale <= 1.0` becomes `gameScale
<= 0.0` (dconst_1 -> dconst_0). The script checks the class it patches.

  terrain_slice.py IN.jar OUT.jar      patch the app's bootstrap-game.jar
  terrain_slice.py --class IN OUT      patch a GameScreen.class (classpath overlay)
The game's jar and classes are not committed."""
import hashlib, sys, zipfile

ENTRY = "net/chonkbase/chonkcraft/desktop/GameScreen.class"
BEFORE = "e97a37bf07e8ebe0"
AFTER = "d3e5f5eb83d348d5"
# aload_0; getfield #701 gameScale:D; dconst_1; dcmpg; ifgt +21
PATTERN = bytes([0x2a, 0xb4, 0x02, 0xbd, 0x0f, 0x98, 0x9d, 0x00, 0x15])


def short(data):
    return hashlib.sha256(data).hexdigest()[:16]


def patch(data):
    if short(data) == AFTER:
        return data
    if short(data) != BEFORE or data.count(PATTERN) != 1:
        sys.exit("GameScreen.class is not the one this patch was made for (sha %s)" % short(data))
    i = data.index(PATTERN) + 4
    out = data[:i] + b"\x0e" + data[i + 1:]
    assert short(out) == AFTER
    return out


def main():
    if sys.argv[1] == "--class":
        open(sys.argv[3], "wb").write(patch(open(sys.argv[2], "rb").read()))
        return
    src, dst = sys.argv[1], sys.argv[2]
    with zipfile.ZipFile(src) as zin, zipfile.ZipFile(dst, "w") as zout:
        for info in zin.infolist():
            data = zin.read(info)
            if info.filename == ENTRY:
                data = patch(data)
            zout.writestr(info, data, compress_type=info.compress_type)
    print("patched", ENTRY, "->", AFTER)


if __name__ == "__main__":
    main()
