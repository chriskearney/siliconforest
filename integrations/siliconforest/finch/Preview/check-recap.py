#!/usr/bin/env python3
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Check exact class exports and both outputs' direct imports without execution."""
import argparse
import hashlib
import json
from pathlib import Path
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--macho", required=True)
    parser.add_argument("--under", action="append", default=[])
    args = parser.parse_args()
    sys.path.insert(0, args.macho)
    import hb_macho
    from sf_gapscan import Root

    install = "/System/Library/PrivateFrameworks/RecapPerformanceTesting.framework/Versions/A/RecapPerformanceTesting"
    root = Root(args.root, under=args.under)
    root.prefer = "arm64"
    output = {"scope": "static class-export and direct-import checks; no runtime execution", "images": []}
    problems = []
    for logical in (install, "/bin/recap-probe"):
        path = root.resolve(logical)
        if path is None:
            problems.append(f"absent output: {logical}")
            continue
        image = root.macho(path)
        if image is None or image.cputype != hb_macho.CPU_ARM64:
            problems.append(f"not an arm64 Mach-O: {logical}")
            continue
        exports, _ = image.exported()
        classes, _ = image.objc_defined()
        if logical == install:
            if not image.id or image.id["name"] != install:
                problems.append("provider install name differs")
            if not image.id or (image.id["compat"], image.id["current"]) != ("1.0", "50.0"):
                problems.append("provider compatibility/current versions differ")
            expected = {"RPTTestRunner", "RPTActivationTestParameters"}
            if set(classes) != expected:
                problems.append(f"unexpected class set: {sorted(classes)}")
            for name in expected:
                for kind in ("CLASS", "METACLASS"):
                    symbol = f"_OBJC_{kind}_$_{name}"
                    if symbol not in exports:
                        problems.append(f"missing export: {symbol}")
        checked, weak_missing = 0, []
        for symbol, ordinal, weak in image.imports():
            if not 0 < ordinal <= len(image.dylibs):
                problems.append(f"unhandled import ordinal {ordinal}: {symbol}")
                continue
            dependency = image.dylibs[ordinal - 1]
            got = root.find(dependency["name"], logical, logical, image.rpaths)
            if got is None or symbol not in root.exports(*got):
                message = f"{logical}: {dependency['name']} lacks {symbol}"
                if weak or dependency["kind"] == "weak":
                    weak_missing.append(message)
                else:
                    problems.append(message)
            checked += 1
        signature = image.signature()
        mismatches = hb_macho.verify(path.read_bytes()) if signature else None
        if signature is None or mismatches != 0:
            problems.append(f"missing or mismatched code signature: {logical}")
        output["images"].append({"logical": logical, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "classes": sorted(classes), "imports_checked": checked, "weak_missing": weak_missing,
            "install_name": image.id, "signature": signature, "signature_page_mismatches": mismatches})
    output["problems"] = problems
    output["pass"] = not problems
    print(json.dumps(output, indent=2))
    return int(bool(problems))


if __name__ == "__main__":
    raise SystemExit(main())
