#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check the additive UUID ABI and baseline exports without executing a target."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("candidate", "baseline", "macho"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    sys.path.insert(0, args.macho)
    import hb_macho

    root = Path(args.candidate)
    library = root / "usr/lib/swift/libswiftFoundation.dylib"
    required = {
        "_$s10Foundation4UUIDV10uuidStringACSgSSh_tcfC",
        "_$s10Foundation4UUIDV10uuidStringSSvg",
        "_$s10Foundation4UUIDVACycfC",
        "_$s10Foundation4UUIDVMa",
        "_$s10Foundation4UUIDVMn",
    }
    exports = hb_macho.load(library).exported()[0]
    baseline = hb_macho.load(args.baseline).exported()[0]
    lost = sorted(baseline - exports)
    missing = sorted(required - exports)
    problems, images = [], {}
    base_root = Path(args.baseline).parents[3]
    for source in (base_root / "share/Source").glob("*.swift"):
        if source.name.endswith("probe.swift"):
            continue
        if source.read_bytes() != (root / "share/Source" / source.name).read_bytes():
            problems.append("Changed baseline source: " + source.name)
    if (base_root / "bin/url-probe").read_bytes() != (root / "bin/legacy-url-probe").read_bytes():
        problems.append("Legacy consumer executable changed")
    for path in (library, root / "lib/libUUIDInteropClient.dylib",
                 root / "bin/uuid-probe", root / "bin/legacy-url-probe"):
        data = path.read_bytes()
        image = hb_macho.MachO(data)
        bad = hb_macho.verify(data)
        if image.cputype != hb_macho.CPU_ARM64 or image.cpusubtype != 0 or bad:
            problems.append(str(path) + ": arm64/signature failure")
        images[str(path.relative_to(root))] = {
            "sha256": hashlib.sha256(data).hexdigest(), "signature_bad_pages": bad}
    undefined = set(subprocess.check_output(
        ["llvm-nm", "--undefined-only", "-j", str(library)], text=True).splitlines())
    operations = {"_uuid_generate_random", "_uuid_parse", "_uuid_unparse_upper"}
    if not operations.issubset(undefined):
        problems.append("Missing real libSystem UUID imports")
    if lost or missing:
        problems.append("Missing baseline or required UUID exports")
    result = {"pass": not problems, "problems": problems, "images": images,
              "baseline_exports": len(baseline), "candidate_exports": len(exports),
              "lost_exports": lost, "missing_uuid_exports": missing,
              "libsystem_uuid_imports": sorted(operations & undefined)}
    print(json.dumps(result, indent=2))
    return int(bool(problems))


if __name__ == "__main__":
    raise SystemExit(main())
