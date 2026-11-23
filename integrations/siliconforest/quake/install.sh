#!/bin/bash
# SPDX-License-Identifier: MIT
# Run on the builder. Fetches the QuakeSpasm macOS app and the Quake 1.06 shareware, checks every
# hash, builds the private frameworks and stages all of it on the M1 under /private/var/db/sfquake,
# with /usr/bin/sf-open-quake and the desktop entry. The app's files are not changed. Nothing
# fetched here goes into git.
#
#   quake/install.sh            (takes runs/m1-coord/gui.lock for the M1 part)
set -euo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
SF=$(cd "$HERE/.." && pwd)
LAB=${SF_LAB:-$(cd "$HERE" && cd "$(git rev-parse --git-common-dir)/.." && pwd)}
B=/private/var/db/sfquake

# The official 0.97.0 Mac zip has no arm64 main executable (i386 x86_64), so this is the Mac
# Source Ports universal build. Its DMG says 0.96.3; the engine inside prints v0.97.0.
DMG_URL=https://github.com/MacSourcePorts/MSPBuildSystem/releases/download/Quakespasm_2026-07-22/QuakeSpasm-0.96.3.dmg
DMG_SHA=012478fc3953bf68d63b9e261a699e50ee82c99c6e9f89b601ca58abf7332a63
EXE_SHA=470424be8d0470f28539057a2ab0de77ee82f051e94054a7a7f6a6ef4046a2fd
# The app's own icon (CFBundleIconFile). The dock decodes it from the bundle in place.
ICNS_SHA=fc13de7c0cd8b26bc2a91c9e2e31f7730f53363d22e9fe2d8989a6631acdea70
DOCK_ID=com.macsourceports.QuakeSpasm
ZIP_URL=https://ftp.idtech.space/idstuff/quake/quake106.zip
ZIP_SHA=ec6c9d34b1ae0252ac0066045b6611a7919c2a0d78a3a66d9387a8f597553239
PAK_MD5=5906e5998fc3d896ddaf5e6a62e03abb
PAK_SIZE=18689235

M1=(ssh -o ConnectTimeout=8 -o UserKnownHostsFile="$HOME/.ssh/known_hosts_m1_siliconforest"
    -o GlobalKnownHostsFile=/dev/null -o StrictHostKeyChecking=yes
    -o HostKeyAlias=m1-siliconforest -o BatchMode=yes root@10.1.1.211)
SEVENZ=$(command -v 7zz || ls -d /nix/store/*-7zz-*/bin/7zz 2>/dev/null | head -1 || true)
[ -x "$SEVENZ" ] || { echo "install: 7zz not found (needed for the DMG)" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/sfquake-install.XXXXXX")
trap 'rm -rf "${WORK:?}"' EXIT
mkdir -p "$WORK/dmg" "$WORK/app" "$WORK/zip" "$WORK/data" "$WORK/root" "$WORK/fw"

check() { # sha256 file
  echo "$1  $2" | sha256sum -c --quiet - || { echo "install: wrong hash: $2" >&2; exit 1; }
}
curl -fsSL --max-time 300 -o "$WORK/dmg/q.dmg" "$DMG_URL"
check "$DMG_SHA" "$WORK/dmg/q.dmg"
curl -fsSL --max-time 300 -o "$WORK/zip/quake106.zip" "$ZIP_URL"
check "$ZIP_SHA" "$WORK/zip/quake106.zip"

# 7zz refuses five relative dylib links and exits nonzero. They are put back below, and the
# hash of the executable and the arch of every library are checked.
"$SEVENZ" x -y -o"$WORK/app" "$WORK/dmg/q.dmg" >/dev/null 2>&1 || true
A="$WORK/app/QuakeSpasm/QuakeSpasm.app"
F="$A/Contents/Frameworks"
for p in libFLAC:libFLAC.14 libmad:libmad.0 libogg:libogg.0 libopus:libopus.0 libxmp:libxmp.4; do
  l=${p%%:*}
  rm -f "${F:?}/${l:?}.dylib"
  ln -s "${p##*:}.dylib" "$F/$l.dylib"
done
check "$EXE_SHA" "$A/Contents/MacOS/QuakeSpasm"
check "$ICNS_SHA" "$A/Contents/Resources/QuakeSpasm.icns"
for l in FLAC mad ogg opus opusfile vorbis vorbisfile xmp; do
  llvm-lipo -archs "$F/lib$l.dylib" | grep -qw arm64 || { echo "install: lib$l has no arm64" >&2; exit 1; }
done
chmod -R u+rwX,go+rX "$A"

bsdtar -xf "$WORK/zip/quake106.zip" -C "$WORK/zip" resource.1
bsdtar -xf "$WORK/zip/resource.1" -C "$WORK/data" ID1/PAK0.PAK SLICNSE.TXT
[ "$(stat -c %s "$WORK/data/ID1/PAK0.PAK")" = "$PAK_SIZE" ] || { echo "install: wrong pak size" >&2; exit 1; }
[ "$(md5sum < "$WORK/data/ID1/PAK0.PAK" | cut -d' ' -f1)" = "$PAK_MD5" ] || { echo "install: wrong pak md5" >&2; exit 1; }

exec 9>"$LAB/runs/m1-coord/gui.lock"
flock -w 300 9 || { echo "install: gui.lock busy" >&2; exit 75; }
"${M1[@]}" 'tar -C / -cf - System/Library/Frameworks/IOKit.framework/Versions/A/IOKit usr/lib/libIOKitCF.dylib usr/lib/libCoreFoundation.dylib' \
  </dev/null 9>&- | tar -C "$WORK/root" -xf -
TMPDIR="$WORK" OUT="$WORK/fw" ROOT="$WORK/root" SFQUAKE="$B" "$HERE/frameworks/build.sh" 2>&1 |
  grep -v -E 'two min versions|invalid -install_name' || true
[ -f "$WORK/fw/libsfquakestart.dylib" ] && [ -f "$WORK/fw/IOKit.framework/Versions/A/IOKit" ] ||
  { echo "install: framework build failed" >&2; exit 1; }

"${M1[@]}" "mkdir -p $B/game/id1 $B/home $B/logs $B/fw" </dev/null 9>&-
tar -C "$WORK/app/QuakeSpasm" --exclude='*:com.apple.*' --owner=0 --group=0 -cf - QuakeSpasm.app |
  "${M1[@]}" "tar -C $B -xf -" 9>&-
tar -C "$WORK/fw" --owner=0 --group=0 -cf - . | "${M1[@]}" "tar -C $B/fw -xf -" 9>&-
"${M1[@]}" "cat > $B/game/id1/pak0.pak" < "$WORK/data/ID1/PAK0.PAK" 9>&-
"${M1[@]}" "cat > $B/game/SLICNSE.TXT" < "$WORK/data/SLICNSE.TXT" 9>&-
"${M1[@]}" 'cat > /usr/bin/sf-open-quake && chmod 755 /usr/bin/sf-open-quake' < "$SF/desktop/system/sf-open-quake" 9>&-
"${M1[@]}" 'cat > /usr/share/applications/com.macsourceports.QuakeSpasm.desktop' \
  < "$SF/desktop/system/applications/com.macsourceports.QuakeSpasm.desktop" 9>&-
# The dock tile: added to the default pins and to the session's own list, once. An empty session
# list is left alone, because the dock fills it from the defaults.
"${M1[@]}" "D=/usr/share/chonkstep/dock-pins; S=/private/var/db/desktop-state/chonkstep/dock
  if [ -f \$D ] && ! grep -qxF $DOCK_ID \$D; then echo $DOCK_ID >> \$D; fi
  if grep -q '[^[:space:]]' \$S 2>/dev/null && ! grep -qxF $DOCK_ID \$S; then
    [ -e \$S.before-quake ] || cp -p \$S \$S.before-quake
    XDG_STATE_HOME=/private/var/db/desktop-state XDG_RUNTIME_DIR=/private/var/run/gpu-desktop WAYLAND_DISPLAY=wayland-0 \
      /usr/bin/chonkstep-dock --pin $DOCK_ID
  fi
  grep -qxF $DOCK_ID \$D" </dev/null 9>&-
"${M1[@]}" "md5 $B/game/id1/pak0.pak; shasum -a 256 $B/QuakeSpasm.app/Contents/MacOS/QuakeSpasm; ls -la /usr/bin/sf-open-quake" </dev/null 9>&-
echo "installed Quake at $B"
