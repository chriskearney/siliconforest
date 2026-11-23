#!/bin/bash
# Builds "SiliconForest Installer.app" into installer/mac/build/ (git-ignored).
#
# Signing here is ad hoc only (`codesign -s -`): enough to run locally, not to distribute.
# Developer ID signing (team Z642ZK8JK4, SFIdentity) is pending Chris's go.
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
swift build -c release --product SFHelper
swift build -c release --product SFRecovery
BIN="$(swift build -c release --show-bin-path)"
[ -f build/fonts/Inter-Regular.ttf ] && [ -f build/fonts/SourceCodePro-OFL.txt ] || scripts/fetch-fonts.sh

APP="$ROOT/build/SiliconForest Installer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Profiles" "$APP/Contents/Resources/Fixtures" "$APP/Contents/Resources/Fonts"
cp "$BIN/SFInstaller" "$APP/Contents/MacOS/SiliconForest Installer"
cp "$BIN/sfinstallctl" "$APP/Contents/MacOS/sfinstallctl"

# The privileged helper and its LaunchDaemon plist (DESIGN §6.1). SMAppService registers it only
# from a Developer ID-signed app; with an ad hoc signature it is laid out but cannot be registered.
mkdir -p "$APP/Contents/Library/LaunchDaemons" "$APP/Contents/Helpers" "$APP/Contents/Resources/RecoveryPayload"
cp "$BIN/SFHelper" "$APP/Contents/MacOS/SFHelper"
VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" "$BIN/SFHelper" --write-plists "$ROOT/build/helper-plists"
cp "$ROOT/build/helper-plists/org.siliconforest.installer.helper.plist" "$APP/Contents/Library/LaunchDaemons/"
# The recoveryOS pieces the helper assembles onto the stub (DESIGN §7.1).
scripts/check-recovery-links.sh "$BIN/SFRecovery"
cp "$BIN/SFRecovery" "$APP/Contents/Helpers/SFRecovery"
cp Recovery/sf-launcher Recovery/sf-step2.sh "$APP/Contents/Resources/RecoveryPayload/"

# Device profiles: the canonical installer/profiles (with their schema).
cp "$ROOT"/../profiles/*.json "$APP/Contents/Resources/Profiles/"
# Dry-run disks (the simulator's fake Macs; DESIGN says SFSimulator never ships in release builds,
# so drop these when the app stops being dry-run-only).
cp -R "$ROOT/Fixtures/disks" "$APP/Contents/Resources/Fixtures/disks"
# Inter and Source Code Pro (OFL), each with its licence.
cp build/fonts/*.ttf build/fonts/Inter-OFL.txt build/fonts/SourceCodePro-OFL.txt build/fonts/SOURCES.md "$APP/Contents/Resources/Fonts/"

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
  <key>LSMinimumSystemVersion</key><string>13.5</string>
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
# Frozen identifiers (SFIdentity): the helper and the recovery binary are signed as themselves.
codesign "${SIGN_ARGS[@]}" --identifier org.siliconforest.installer.helper "$APP/Contents/MacOS/SFHelper"
codesign "${SIGN_ARGS[@]}" --identifier org.siliconforest.recovery "$APP/Contents/Helpers/SFRecovery"
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "✓ $APP"
echo "  open \"$APP\"                     # full-screen dry run"
echo "  open \"$APP\" --args --windowed   # in a window"
