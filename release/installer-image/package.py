# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Build the install descriptor and checksums from the files we actually produced."""

import hashlib
import json
import sys
from pathlib import Path


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def describe(path):
    return {"file": path.name, "bytes": path.stat().st_size, "sha256": sha(path)}


def package(version, root, boot, output):
    stem = f"siliconforest-{version}"
    image = describe(root / "siliconforest-root.ext4")
    boot_files = json.loads((boot / "boot.json").read_text())
    if boot_files["release"] != version:
        raise ValueError("boot file release does not match the installer release")
    offset = int((root / "firmware-offset").read_text())
    parts = sorted(output.glob(f"{stem}-root.ext4.xz.*"))
    if not parts or any(part.stat().st_size > 1_900_000_000 for part in parts):
        raise ValueError("missing or oversized xz parts")
    descriptor = {
        "format": "siliconforest-install/1",
        "release": version,
        "models": ["J293"],
        "macos": {"min": "13.5", "max_major": 26},
        "stub_firmware": ["13.5"],
        "boot": describe(output / f"{stem}-boot.tar.xz"),
        "root": {
            "fs_uuid": boot_files["root_uuid"],
            "compression": "xz",
            "image_bytes": image["bytes"],
            "image_sha256": image["sha256"],
            "sizing": "fixed",
            "min_bytes": image["bytes"],
            "default_bytes": image["bytes"],
            "parts": [describe(part) for part in parts],
        },
        "firmware_slot": {"offset": offset, "length": 32 << 20},
    }
    (output / f"{stem}-install.json").write_text(json.dumps(descriptor, indent=2) + "\n")
    files = [describe(path) for path in sorted(output.iterdir())]
    manifest = output / "MANIFEST.tsv"
    with manifest.open("w") as stream:
        stream.write("# File, bytes, SHA-256. Root parts concatenate to one xz stream.\n")
        for item in files:
            stream.write("{file}\t{bytes}\t{sha256}\n".format(**item))
        stream.write("{file}\t{bytes}\t{sha256}\tuncompressed\n".format(**image))
    with (output / "SHA256SUMS").open("w") as stream:
        for item in files + [describe(manifest)]:
            stream.write("{sha256}  {file}\n".format(**item))


if __name__ == "__main__":
    version, root, boot, output = sys.argv[1:]
    package(version, Path(root), Path(boot), Path(output))
