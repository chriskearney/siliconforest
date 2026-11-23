#!/bin/bash
# Runs the SFInstallKit test suite.
# With Xcode, `swift test` runs it. Command Line Tools build the Swift Testing bundle but don't run
# it, so this also runs the same tests as a plain executable (sfinstallkit-selftest).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --build-tests
if [ -d /Library/Developer/CommandLineTools/Library/Developer/Frameworks/Testing.framework ] && ! xcode-select -p | grep -q Xcode.app; then
  swift build --product sfinstallkit-selftest
  # Serially: the disk-image suites each attach images and run real diskutil.
  exec "$(swift build --show-bin-path)/sfinstallkit-selftest" --no-parallel "$@"
else
  exec swift test --no-parallel "$@"
fi
