#!/bin/bash
# Verification only: builds the package WITH the real-disk compile key in a separate scratch directory
# and runs the suites that need it. Those suites use fake runners and canned plists: they never read
# or write a real disk. The result is never installed, signed or shipped, and CI never runs this.
set -euo pipefail
cd "$(dirname "$0")/.."
SCRATCH=.build-gate
swift build --scratch-path "$SCRATCH" --product sfinstallkit-selftest -Xswiftc -DSF_REAL_DISK_WRITES
BIN="$(swift build --scratch-path "$SCRATCH" --show-bin-path -Xswiftc -DSF_REAL_DISK_WRITES)"
scripts/check-real-disk-gate.sh --expect-compiled "$BIN/sfinstallkit-selftest"
SF_IMAGE_TESTS=0 "$BIN/sfinstallkit-selftest" --no-parallel --filter 'InternalDiskAuthorityTests|RealDiskGateTests|ProtectionReceiptTests'
