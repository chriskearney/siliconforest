# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""The boot receipt as the installer sees it through the raw root partition (DESIGN.md 8.3).

The installer writes the header at S52; sf-boot-receipt (in the root) appends stages at first start;
back in macOS the helper reads the slot read-only and classifies it. This is the reference the
Swift reader is tested against.
"""

import re

MAGIC = b"SFRCPT1\n"
STAGES = ("root-mounted", "launchd-up", "desktop-ready")


def header(install_id):
    if not re.fullmatch(r"[0-9a-f]{32}", install_id):
        raise ValueError("install id is 32 lower-case hex digits")
    return MAGIC + f"install={install_id}\n".encode()


def write_header(dev, offset, size, install_id):
    """S52: write the header into a slot that must still be all zeros (an ordinary file in tests)."""
    with open(dev, "r+b") as f:
        f.seek(offset)
        if f.read(size) != bytes(size):
            raise ValueError("receipt slot is not empty")
        f.seek(offset)
        f.write(header(install_id))
        f.flush()


def classify(slot, install_id):
    """'installed', 'partial:<last stage>', 'empty', 'foreign' (another install's ID) or 'invalid'."""
    if slot == bytes(len(slot)):
        return "invalid"            # no header: S52 never ran
    m = re.match(rb"SFRCPT1\ninstall=([0-9a-f]{32})\n", slot)
    if not m:
        return "invalid"
    if m.group(1).decode() != install_id:
        return "foreign"
    body = slot[m.end():].split(b"\0", 1)[0].decode("ascii", "replace")
    seen = [ln.split(" ")[0] for ln in body.splitlines() if re.fullmatch(r"[a-z][a-z0-9-]* [0-9]+", ln)]
    if "desktop-ready" in seen:
        return "installed"
    last = [s for s in STAGES if s in seen]
    return f"partial:{last[-1]}" if last else "empty"
