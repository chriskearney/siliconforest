#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Stand-in for kc-builder in rehearsals on synthetic inputs (no kernel, no kexts, no Apple parts).

Accepts exactly the release link format (kc_release.parse_link_args) and writes a deterministic
"collection": a header, then the SHA-256 of every option and every input file's path and
bytes, in link order. Any change to any input or option changes the output, which is all the engine's
checks need. It is not a linker; a release that names it can only be a rehearsal
(kernel_collection.tool.signing = rehearsal-stand-in).

    rehearsal_kc_builder.py --synthetic DIR     make a synthetic release-inputs directory
"""
import hashlib
import os
import sys
from pathlib import Path

# Self-contained: the release ships this file as `kc-builder`, run from the engine's private directory.
MAGIC = b"SFKC-REHEARSAL-STAND-IN 1\n"
OPTIONS = {"-kc-base", "-kernel", "-kext", "-codeless", "-o"}


def link(args):
    if len(args) % 2 or any(o not in OPTIONS for o in args[0::2]):
        sys.exit("rehearsal kc-builder: options outside the release link format")
    pairs = list(zip(args[0::2], args[1::2]))
    out = Path(dict(pairs)["-o"])
    h = hashlib.sha256()
    for opt, val in pairs:
        h.update(opt.encode() + b"\0" + (b"@OUTPUT@" if opt == "-o" else val.encode()) + b"\0")
        if opt in ("-kernel", "-kext", "-codeless"):
            p = Path(val)
            for f in [p] if p.is_file() else sorted(x for x in p.rglob("*") if x.is_file()):
                h.update(f.as_posix().encode() + b"\0")   # paths and bytes, as kc-builder reads them; not modes
                h.update(hashlib.sha256(f.read_bytes()).digest())
    body = MAGIC + h.hexdigest().encode() + b"\n"
    out.write_bytes(body + bytes(4096 - len(body)))
    print(f"wrote {out} (4096 bytes)", file=sys.stderr)


def synthetic(d):
    d = Path(d)
    (d / "kexts").mkdir(parents=True)
    (d / "codeless").mkdir()
    (d / "kernel").write_bytes(b"SF-REHEARSAL synthetic kernel\n" * 64)
    args = ["-kc-base", "fffffe0006000000", "-kernel", "kernel"]
    for name in ("SFRehearsalA", "SFRehearsalB", "SFRehearsalC"):
        c = d / "kexts" / f"{name}.kext" / "Contents"
        (c / "MacOS").mkdir(parents=True)
        (c / "Info.plist").write_text(f"<plist><dict><key>CFBundleIdentifier</key><string>org.siliconforest.rehearsal.{name}</string></dict></plist>\n")
        exe = c / "MacOS" / name
        exe.write_bytes(f"SF-REHEARSAL {name} executable\n".encode() * 32)
        os.chmod(exe, 0o755)
        args += ["-kext", f"kexts/{name}.kext"]
    (d / "kexts" / "SFRehearsalC.kext" / "Contents" / "NOTICE").write_text("rehearsal notice\n")
    c = d / "codeless" / "SFRehearsalKPI.kext"
    c.mkdir()
    (c / "Info.plist").write_text("<plist><dict><key>CFBundleIdentifier</key><string>org.siliconforest.rehearsal.kpi</string></dict></plist>\n")
    args += ["-codeless", "codeless/SFRehearsalKPI.kext", "-o", "@OUTPUT@"]
    (d / "link-args.txt").write_text("\n".join(args) + "\n")
    return d


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--synthetic":
        print(synthetic(sys.argv[2]))
    else:
        link(sys.argv[1:])
