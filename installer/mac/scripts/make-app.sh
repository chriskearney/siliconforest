#!/bin/bash
# Builds "SiliconForest Installer.app" into installer/mac/build/ (git-ignored).
#
# Signing here is ad hoc only (`codesign -s -`): enough to run locally, not to distribute.
# Developer ID signing + notarization happen on a machine with the identity (see README.md):
#   SIGN_IDENTITY="Developer ID Application: …" scripts/make-app.sh   (hardened runtime, timestamp)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
VERSION="${VERSION:-0.9.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"
IDENTITY="${SIGN_IDENTITY:--}"

echo "▸ swift build (release)"
swift build -c release --product SFInstaller
swift build -c release --product sfinstallctl
BIN="$(swift build -c release --show-bin-path)"

APP="$ROOT/build/SiliconForest Installer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Profiles" "$APP/Contents/Resources/Fixtures"
cp "$BIN/SFInstaller" "$APP/Contents/MacOS/SiliconForest Installer"
cp "$BIN/sfinstallctl" "$APP/Contents/MacOS/sfinstallctl"

# Device profiles: the canonical installer/profiles/*.json when present, else the test fixture.
if compgen -G "$ROOT/../profiles/*.json" > /dev/null; then
  cp "$ROOT"/../profiles/*.json "$APP/Contents/Resources/Profiles/"
  echo "▸ profiles from installer/profiles"
else
  cp "$ROOT"/Fixtures/profiles/*.json "$APP/Contents/Resources/Profiles/"
  echo "▸ profiles from Fixtures/profiles (installer/profiles not present yet)"
fi
cp -R "$ROOT/Fixtures/disks" "$APP/Contents/Resources/Fixtures/disks"

echo "▸ icon (rendered from our vector mark)"
ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"
"$BIN/SFInstaller" --render-icon "$ICONSET" > /dev/null
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>SiliconForest Installer</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>org.siliconforest.installer</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>SiliconForest Installer</string>
  <key>CFBundleDisplayName</key><string>SiliconForest Installer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
  <key>NSHumanReadableCopyright</key><string>SiliconForest contributors. MIT licence.</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" > /dev/null

echo "▸ codesign ($([ "$IDENTITY" = "-" ] && echo "ad hoc" || echo "$IDENTITY"))"
SIGN_ARGS=(--force --sign "$IDENTITY")
if [ "$IDENTITY" != "-" ]; then SIGN_ARGS+=(--options runtime --timestamp); fi
codesign "${SIGN_ARGS[@]}" "$APP/Contents/MacOS/sfinstallctl"
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "✓ $APP"
echo "  open \"$APP\"                     # fullscreen dry run"
echo "  open \"$APP\" --args --windowed   # in a window"
