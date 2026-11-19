#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Static exact-import, export preservation and signature checks; never executes."""
import argparse
import hashlib
import json
from pathlib import Path
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("paper", "foundation", "baseline", "macho"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    sys.path.insert(0, args.macho)
    import hb_macho

    install = "/System/Library/Frameworks/PaperKit.framework/Versions/A/PaperKit"
    paths = {
        "PaperKit": Path(args.paper) / install.lstrip("/"),
        "paperkit-probe": Path(args.paper) / "bin/paperkit-probe",
        "Foundation": Path(args.foundation) / "usr/lib/swift/libswiftFoundation.dylib",
        "url-probe": Path(args.foundation) / "bin/url-probe",
    }
    problems, images, parsed = [], {}, {}
    for name, path in paths.items():
        data = path.read_bytes()
        image = hb_macho.MachO(data)
        parsed[name] = image
        bad = hb_macho.verify(data)
        if image.cputype != hb_macho.CPU_ARM64 or image.cpusubtype != 0 or bad:
            problems.append(f"{name}: arm64/signature check failed")
        images[name] = {"sha256": hashlib.sha256(data).hexdigest(), "signature_bad_pages": bad}
    exports = parsed["PaperKit"].exported()[0]
    required = {
        "_$s8PaperKit0A14ViewControllerCMa",
        "_$s8PaperKit0A14ViewControllerCMn",
        "_$s8PaperKit0A14ViewControllerC7display_8readOnlyy10Foundation3URLV_SbtFTj",
    }
    missing = sorted(required - exports)
    if missing:
        problems.append(f"PaperKit missing requested imports: {missing}")
    identity = parsed["PaperKit"].id
    if not identity or (identity["name"], identity["compat"], identity["current"]) != (install, "1.0", "344.4.2"):
        problems.append("PaperKit install identity/version differs")
    baseline = hb_macho.load(args.baseline).exported()[0]
    replacement = parsed["Foundation"].exported()[0]
    lost = sorted(baseline - replacement)
    if lost:
        problems.append(f"Foundation loses existing exports: {lost}")
    result = {"scope": "Static contract checks; no execution or complete private ABI proof",
              "required_paperkit_exports": len(required), "missing_paperkit_exports": missing,
              "baseline_foundation_exports": len(baseline), "lost_foundation_exports": lost,
              "added_foundation_exports": len(replacement - baseline), "images": images,
              "pass": not problems, "problems": problems}
    print(json.dumps(result, indent=2))
    return int(bool(problems))


if __name__ == "__main__":
    raise SystemExit(main())
