#!/bin/bash
# Runs the SFInstallKit test suite.
# With Xcode, `swift test` runs it. Command Line Tools build the Swift Testing bundle but don't run
# it, so this also runs the same tests as a plain executable (sfinstallkit-selftest).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --build-tests
if [ -d /Library/Developer/CommandLineTools/Library/Developer/Frameworks/Testing.framework ] && ! xcode-select -p | grep -q Xcode.app; then
  swift build --product sfinstallkit-selftest
  swift build --product sfinstallctl
  BIN="$(swift build --show-bin-path)"
  # Afterwards, detach and delete every per-test disk image (SF_KEEP=1 keeps them for inspection).
  [ "${SF_KEEP:-0}" = 1 ] || trap '"$BIN/sfinstallctl" image-clean --runs > /dev/null' EXIT
  # Serially: the disk-image suites each attach images and run real diskutil.
  "$BIN/sfinstallkit-selftest" --no-parallel "$@"
else
  exec swift test --no-parallel "$@"
fi
