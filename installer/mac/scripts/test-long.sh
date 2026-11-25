#!/bin/bash
# The long tier: the whole SFInstallKit suite on disk images, including every image-backed test that CI
# skips (CI sets SF_IMAGE_TESTS=0 and SF_IMAGE_LONG=0; see .github/workflows/installer-mac.yml).
# Run this on the M5. Disk images only: the real-disk write gates must stay unset.
set -euo pipefail
cd "$(dirname "$0")/.."
unset SF_REAL_DISK_WRITES SF_ALLOW_REAL_DISK_WRITES || true
export SF_IMAGE_TESTS=1 SF_IMAGE_LONG=1 SF_FAULT_SWEEP=1 SF_LIVE_HEAVY=1
exec scripts/test.sh "$@"
