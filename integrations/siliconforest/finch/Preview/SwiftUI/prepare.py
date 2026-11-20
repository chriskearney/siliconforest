#!/usr/bin/env python3
"""Prepare pinned open renderer sources in a NEW local directory. No build/install/exec of target code."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

HERE = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def revision(root, expected):
    actual = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    if actual != expected:
        raise ValueError(f"source revision mismatch: {root}: {actual}")
    subprocess.run(["git", "-C", str(root), "diff", "--quiet", "HEAD", "--"], check=True)


def copy(root, dest):
    shutil.copytree(root, dest, symlinks=True,
                    ignore=shutil.ignore_patterns(".git", ".build", "build", ".swiftpm"))


def patch(root, source):
    subprocess.run(["patch", "--batch", "--fuzz=0", "-p1", "-i", str(source)], cwd=root, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--finch", type=Path, required=True)
    parser.add_argument("--sources", type=Path, required=True, help="Directory containing the pinned named checkouts")
    parser.add_argument("--output", type=Path, required=True, help="Must not exist")
    parser.add_argument("--diagnostic-headers", action="store_true",
                        help="Opt in to compile-only declarations; output must never be staged as a provider")
    args = parser.parse_args()
    spec = json.loads((HERE / "sources.json").read_text())
    finch = args.finch.resolve()
    roots = args.sources.resolve()
    output = args.output.absolute()
    if output.exists() or output.is_symlink():
        raise ValueError("fresh nonexistent output required")
    revision(finch, spec["finch_revision"])
    for name, expected in spec["finch_files"].items():
        if sha(finch / name) != expected:
            raise ValueError(f"Finch input bytes changed: {name}")
    for name, pin in spec["pins"].items():
        root = roots / name if name != "swift-runtime-headers" else roots / "Compute/Submodules/swift-runtime-headers"
        revision(root, pin["revision"])
    output.mkdir(parents=True)
    for name in ["OpenSwiftUI", "Compute", "OpenAttributeGraph", "OpenCoreGraphics", "OpenRenderBox"]:
        copy(roots / name, output / name)
    ui = output / "OpenSwiftUI"
    subtree = finch / "userland/SwiftUI"
    subprocess.run(["python3", str(subtree / "adapt.py"), str(ui)], check=True)
    for source in sorted((subtree / "patches").glob("OpenSwiftUI*.patch")):
        patch(ui, source)
    patch(ui, HERE / "observation-collection.patch")
    patch(ui, HERE / "accessibility-failable.patch")
    compute = output / "Compute"
    patch(compute, subtree / "patches/Compute/0001-finch.patch")
    subprocess.run(["git", "apply", "--include=include/*",
                    str(finch / "userland/swift/patches/0001-arm64e-runtime-metadata.patch")],
                   cwd=compute / "Submodules/swift-runtime-headers", check=True)
    patch(compute, HERE / "compute-cross.patch")
    patch(output / "OpenAttributeGraph", HERE / "oag-cross.patch")
    orb = output / "OpenRenderBox"
    patch(orb, subtree / "patches/OpenRenderBox/0001-path-retain-release-and-cgpath-copy.patch")
    patch(orb, HERE / "orb-cross.patch")
    if args.diagnostic_headers:
        patch(ui, HERE / "diagnostics/source-annotations.patch")
        patch(orb, HERE / "diagnostics/orb-protocol-forwards.patch")
    # The independent primitive build preserves the existing binding subset.
    # It omits only a package-only Axis conversion that requires the whole layout graph.
    primitive = output / "primitive"
    primitive.mkdir()
    edge = (ui / "Sources/SwiftUICore/Layout/Edge/Edge.swift").read_text()
    start = edge.index("extension Edge.Set {\n    package init(_ axes: Axis.Set)")
    end = edge.index("// MARK: - HorizontalEdge", start)
    (primitive / "Edge.swift").write_text(edge[:start] + edge[end:])
    debug = (ui / "Sources/SwiftUICore/View/ViewDebug.swift").read_text()
    start = debug.index("package protocol CustomViewDebugValueConvertible {")
    end = debug.index("\n}", start) + 2
    (primitive / "ViewDebugProtocol.swift").write_text(debug[start:end] + "\n")
    shutil.copy2(HERE.parents[1] / "QuickTime/loader/SwiftUI.swift", primitive / "SwiftUI.swift")
    shutil.copy2(finch / "userland/swift/overlays/CoreFoundation/CGFloat.swift", primitive / "CGFloat.swift")
    # Preserve the real nominal module and unchanged upstream equality body.
    # The earlier compiler input exposed CGGeometry C declarations only.
    geometry = output / "geometry"
    geometry.mkdir()
    cg = (finch / "userland/CoreGraphics/swift/CoreGraphics.swift").read_text()
    start = cg.index("extension CGPoint : Equatable {")
    end = cg.index("\nextension CGPoint : Codable", start)
    license_header = cg[:cg.index("@_exported import CoreGraphics")]
    (geometry / "CGPointEquatable.swift").write_text(
        license_header + "@_exported import CoreGraphics\n" + cg[start:end])
    shutil.copy2(subtree / "demangle.cpp", output / "demangle.cpp")
    shutil.copy2(HERE / "backtrace_image_offsets.c", output / "backtrace_image_offsets.c")
    manifest = {str(p.relative_to(output)): sha(p) for p in sorted(output.rglob("*"))
                if p.is_file() and not p.is_symlink()}
    receipt = {"source_spec_sha256": sha(HERE / "sources.json"),
               "target_execution": False, "installation": False,
               "diagnostic_headers": args.diagnostic_headers,
               "provider_staging_allowed": False,
               "regular_files": manifest}
    (output / "preparation.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"output": str(output), "files": len(manifest),
                      "diagnostic_headers": args.diagnostic_headers, "built": False}))


if __name__ == "__main__":
    main()
