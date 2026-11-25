# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Shared rules of a SiliconForest installer release (docs/installer/PAYLOAD.md section 7)."""

import hashlib
import json
import re
import subprocess
from pathlib import Path

NAMESPACE = "siliconforest-release"
INSTALL_FORMAT = "siliconforest-install/3"   # 3: kernel_collection replaces boot.kernel
SUMS = "SHA256SUMS"
SIG = "SHA256SUMS.sig"
TEST_MARK = "TEST-ONLY"
PART_LIMIT = 1_900_000_000          # GitHub release assets stay under 2 GiB
NAME = re.compile(r"\A[A-Za-z0-9][A-Za-z0-9._+-]{0,127}\Z")
# Release keys Chris has made, by their SHA256 fingerprint as ssh-keygen -l prints it. The matching
# allowed_signers line is in release/allowed_signers. The private key stays offline, never in git.
RELEASE_KEY_FINGERPRINTS = frozenset({
    "SHA256:y5XAQCFbvtrcB7JG73cXZajUSTrIOewSASbcoVKspQc",  # siliconforest-release offline 2026-11-24 (Ed25519)
})


class ReleaseError(Exception):
    pass


def sha256_file(path):
    h = hashlib.sha256()
    n = 0
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
            n += len(chunk)
    return h.hexdigest(), n


def check_name(name):
    if not NAME.match(name) or name in (SUMS, SIG):
        raise ReleaseError(f"bad artifact name {name!r}")
    return name


def parse_sums(text):
    entries = {}
    for i, line in enumerate(text.splitlines(), 1):
        m = re.fullmatch(r"([0-9a-f]{64})  (\S+)", line)
        if not m:
            raise ReleaseError(f"{SUMS} line {i} is malformed")
        digest, name = m.groups()
        check_name(name)
        if name in entries:
            raise ReleaseError(f"{name} is listed twice")
        entries[name] = digest
    if not entries:
        raise ReleaseError(f"{SUMS} is empty")
    return entries


def key_info(pub_path):
    out = subprocess.run(["ssh-keygen", "-l", "-E", "sha256", "-f", str(pub_path)], capture_output=True, text=True, check=True).stdout
    m = re.match(r"(\d+) (SHA256:\S+) (.*) \((\w+)\)\s*$", out.strip())
    if not m:
        raise ReleaseError("cannot read the signing key's fingerprint")
    bits, fp, comment, kind = m.groups()
    if kind != "ED25519":
        raise ReleaseError("release keys are Ed25519")
    return {"fingerprint": fp, "comment": comment, "test_only": TEST_MARK in comment}


def canonical(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()


def load_json(path):
    return json.loads(Path(path).read_text())


STAGE1_MARK = b"##m1n1_ver##"
STAGE1_TAG = "-siliconforest-stage1-v"


def check_stage1(data, revision, footprint):
    """A release's sf-stage1.bin must be our m1n1 stage 1 (boot/build_stage1.sh): built from the
    profile's m1n1 revision with our stage 1 tag, the installed variant (stops, never falls back to the
    USB proxy) and no larger than the footprint the profile fits stage 2 into. Returns the tag."""
    if not data:
        raise ReleaseError("sf-stage1.bin is empty")
    if len(data) > footprint:
        raise ReleaseError(f"sf-stage1.bin is {len(data)} bytes, more than stage 1's {footprint}")
    m = re.search(re.escape(STAGE1_MARK) + rb"([0-9a-f]{40}" + re.escape(STAGE1_TAG.encode()) + rb"[0-9]+)", data)
    if not m:
        raise ReleaseError("sf-stage1.bin is not a SiliconForest stage 1 (no version tag)")
    tag = m.group(1).decode()
    if not tag.startswith(revision + STAGE1_TAG):
        raise ReleaseError(f"sf-stage1.bin was built from {tag[:40]}, not the profile's {revision}")
    if b"SF_STOPPED" not in data:
        raise ReleaseError("sf-stage1.bin is not the installed variant (it could fall back to the USB proxy)")
    return tag


def profile_stage1(profiles_dir):
    """(revision, footprint) of stage 1, the same in every profile."""
    seen = set()
    for p in sorted(Path(profiles_dir).glob("*.json")):
        if p.name.endswith(".schema.json"):
            continue
        s1 = load_json(p).get("boot", {}).get("stage1")
        if s1:
            seen.add((s1["source_revision"], int(s1["max_stage2_span_bytes"])))
    if len(seen) != 1:
        raise ReleaseError(f"the profiles disagree on stage 1: {sorted(seen)}")
    return seen.pop()


if __name__ == "__main__":
    import argparse
    import sys
    ap = argparse.ArgumentParser(description="checks for release files")
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check-stage1")
    c.add_argument("file")
    c.add_argument("--revision", required=True)
    c.add_argument("--footprint", type=int, required=True)
    a = ap.parse_args()
    try:
        print(check_stage1(Path(a.file).read_bytes(), a.revision, a.footprint))
    except ReleaseError as e:
        print(f"refused: {e}", file=sys.stderr)
        sys.exit(1)
