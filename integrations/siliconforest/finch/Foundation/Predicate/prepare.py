#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Copy this Predicate slice and patch a private PredicateExpression.swift.

Does not modify the pinned source. The output directory must not exist.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil


OLD = (
    "        case .undefinedVariable:\n"
    "            return rhs == .undefinedVariable\n"
)
NEW = (
    "        case .undefinedVariable:\n"
    "            if case .undefinedVariable = rhs._error {\n"
    "                return true\n"
    "            }\n"
    "            return false\n"
)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expression", type=Path, required=True,
                        help="Pinned PredicateExpression.swift. Read only.")
    parser.add_argument("--output", type=Path, required=True,
                        help="Fresh, nonexistent output directory")
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    manifest = json.loads((here / "sources.json").read_text())
    expression = args.expression.resolve()
    output = args.output.resolve()
    if output == expression.parent or expression.is_relative_to(output):
        raise ValueError("Refusing to write the pin")
    if digest(expression) != manifest["predicate_expression_sha256"]:
        raise ValueError("PredicateExpression.swift digest mismatch")
    text = expression.read_text()
    if text.count(OLD) != 1:
        raise ValueError("Pinned equality case was not found once")
    patched = text.replace(OLD, NEW, 1)
    if hashlib.sha256(patched.encode()).hexdigest() != manifest["patched_predicate_expression_sha256"]:
        raise ValueError("Patched PredicateExpression.swift digest mismatch")
    for name, expected in manifest["files"].items():
        if digest(here / name) != expected:
            raise ValueError(name + " digest mismatch")
    output.mkdir()
    (output / "PredicateExpression.swift").write_text(patched)
    for name in manifest["files"]:
        shutil.copyfile(here / name, output / name)
    shutil.copyfile(here / "sources.json", output / "sources.json")
    shutil.copyfile(here / "README.md", output / "README.md")
    print(json.dumps({
        "predicate_expression_sha256": manifest["predicate_expression_sha256"],
        "patched_predicate_expression_sha256": manifest["patched_predicate_expression_sha256"],
        "tested_library_sha256": manifest["tested_library_sha256"],
        "output": str(output),
        "pin_unchanged": digest(expression) == manifest["predicate_expression_sha256"],
    }))


if __name__ == "__main__":
    main()
