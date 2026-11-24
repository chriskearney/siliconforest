#!/bin/bash
# Writes the helper Info.plist that is linked into SFHelper (__TEXT,__info_plist).
# Usage: write-helper-info-plist.sh <version> <build> <dest>
set -euo pipefail
VERSION="${1:?version}"
BUILD="${2:?build}"
DEST="${3:?destination path}"
mkdir -p "$(dirname "$DEST")"
python3 - "$VERSION" "$BUILD" "$DEST" <<'PY'
import plistlib
import sys
from pathlib import Path

version, build, dest = sys.argv[1], sys.argv[2], Path(sys.argv[3])
requirement = (
    'anchor apple generic and identifier "org.siliconforest.installer" '
    "and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ "
    "and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ "
    'and certificate leaf[subject.OU] = "Z642ZK8JK4"'
)
plistlib.dump(
    {
        "CFBundleIdentifier": "org.siliconforest.installer.helper",
        "CFBundleName": "SFHelper",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": build,
        "CFBundleInfoDictionaryVersion": "6.0",
        "SMAuthorizedClients": [requirement],
    },
    dest.open("wb"),
)
PY
