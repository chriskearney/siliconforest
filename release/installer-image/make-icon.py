# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Render the project's startup icon as the PNG-based ICNS the installer expects."""

import struct
import subprocess
import sys
from pathlib import Path

artwork, output = sys.argv[1:]
body = bytearray()
for kind, size in [(b"ic11", 32), (b"ic12", 64), (b"ic07", 128), (b"ic08", 256),
                   (b"ic09", 512), (b"ic10", 1024)]:
    png = subprocess.check_output(["rsvg-convert", "-w", str(size), "-h", str(size), artwork])
    body.extend(struct.pack(">4sI", kind, 8 + len(png)))
    body.extend(png)
Path(output).write_bytes(struct.pack(">4sI", b"icns", 8 + len(body)) + body)
