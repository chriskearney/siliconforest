#!/bin/sh
# SPDX-License-Identifier: MIT
# Install Minecraft.app on this machine. The bundle is a launcher around
# /private/var/db/sfminecraft/run-1.21.11.sh. The icon is drawn here (a green
# and brown block); it is not extracted from Mojang's client and is not
# committed. Run on the M1 as root after sf-open-minecraft is in /usr/bin.
set -eu
B=${SFMINECRAFT:-/private/var/db/sfminecraft}
# Other dock apps live in /Applications (Preview, Terminal). The game data stays under $B.
APP=${SFMINECRAFT_APP:-/Applications/Minecraft.app}
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
 <key>CFBundleExecutable</key><string>Minecraft</string>
 <key>CFBundleIdentifier</key><string>net.minecraft.Minecraft</string>
 <key>CFBundleName</key><string>Minecraft</string>
 <key>CFBundleDisplayName</key><string>Minecraft</string>
 <key>CFBundleIconFile</key><string>Minecraft</string>
 <key>CFBundlePackageType</key><string>APPL</string>
 <key>CFBundleShortVersionString</key><string>1.21.11</string>
</dict></plist>
EOF
cat > "$APP/Contents/MacOS/Minecraft" <<'EOF'
#!/bin/sh
# An inherited runtime dir with no wayland-0 socket is not this desk (an SSH session).
if [ ! -S "${XDG_RUNTIME_DIR:-}/wayland-0" ]; then
    XDG_RUNTIME_DIR=/private/var/run/gpu-desktop
fi
export XDG_RUNTIME_DIR
export XDG_STATE_HOME="${XDG_STATE_HOME:-/private/var/db/desktop-state}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
exec /usr/bin/sf-open-minecraft "$@"
EOF
chmod 755 "$APP/Contents/MacOS/Minecraft"
python3 - "$APP/Contents/Resources/Minecraft.png" <<'PY'
import struct, zlib, sys
path = sys.argv[1]
w = h = 128
rows = []
for y in range(h):
    row = bytearray([0])
    for x in range(w):
        edge = x < 4 or y < 4 or x >= w - 4 or y >= h - 4
        if edge:
            r, g, b = 40, 24, 12
        elif y < 48:
            r, g, b = 86 + (x * 3 + y) % 40, 168 + (x + y) % 30, 52
        else:
            r, g, b = 120 + (x * 5) % 28, 78 + (y * 3) % 20, 42
        row += bytes((r, g, b, 255))
    rows.append(row)
raw = b"".join(rows)
def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
open(path, "wb").write(png)
# ic07 is a 128x128 PNG inside an icns container. The bytes are generated here.
icns = b"icns" + struct.pack(">I", 8 + 8 + len(png)) + b"ic07" + struct.pack(">I", 8 + len(png)) + png
open(path.replace(".png", ".icns"), "wb").write(icns)
PY
echo "installed $APP"
