# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""The kernel collection in a release, as separate files linked on the user's Mac (docs/installer/PAYLOAD.md
section 13). Shared by make_release.py, verify_release.py and the tests; the Swift engine (S17, S42)
implements the same rules and is tested against this module.

A release does not carry the collection. It carries:

    kc-builder, LICENSE.kc-tools        the macOS linker (signed), and kc-tools' BSD-3-Clause licence
    kc.kernel                           the kernel
    kc.<kind>.<Bundle>.kext.<path>      every file of every bundle, one artifact each (kind: kexts, codeless;
                                        the path's "/" written ".")

and in install.json `kernel_collection`: each bundle's files with their artifact names and modes, in link
order; the exact kc-builder options (`link_args`, input paths relative to the assembly directory, the
output as @OUTPUT@); and the SHA-256 and size the linked collection must have. That hash is computed at
release time by linking the same files with the same options; the collection itself is never an artifact.

Assembly (the engine's S17, assemble() here): check every input against the signed hashes, lay the files
out in a fresh private directory, run kc-builder with exactly link_args, and accept the output only if it
has exactly collection_sha256 and collection_bytes. PDSF packing (S42) takes only an accepted collection.
"""

import hashlib
import os
import re
import shutil
import stat
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sfrelease as R  # noqa: E402

KC_FORMAT = "siliconforest-kc/1"
TOOL = "kc-builder"
TOOL_LICENSE = "LICENSE.kc-tools"
KERNEL = "kc.kernel"
OUTPUT = "@OUTPUT@"
KINDS = {"-kext": "kexts", "-codeless": "codeless"}
VALUE_OPTIONS = {"-kc-base": re.compile(r"\A[0-9a-f]{1,16}\Z")}
BUNDLE = re.compile(r"\A[A-Za-z0-9][A-Za-z0-9._+-]{0,80}\.kext\Z")
PART = re.compile(r"\A[A-Za-z0-9][A-Za-z0-9._+-]{0,80}\Z")
TOOL_SIGNING = ("developer-id", "ad-hoc", "rehearsal-stand-in")


def artifact_name(kind, bundle, path):
    return R.check_name(f"kc.{kind}.{bundle}.{path.replace('/', '.')}")


def parse_link_args(args):
    """The options of one link: (kernel path, [(option, bundle dir)], kc_base). Anything else is refused."""
    kernel, bundles, base, out, seen = None, [], None, False, set()
    i = 0
    while i < len(args):
        opt = args[i]
        if i + 1 >= len(args):
            raise R.ReleaseError(f"link option {opt} has no value")
        val = args[i + 1]
        if opt == "-kernel":
            if kernel is not None or val != "kernel":
                raise R.ReleaseError("link_args: -kernel must be given once, as 'kernel'")
            kernel = val
        elif opt in KINDS:
            kind, _, name = val.partition("/")
            if kind != KINDS[opt] or not BUNDLE.match(name) or val in seen:
                raise R.ReleaseError(f"link_args: bad or repeated bundle {val!r}")
            seen.add(val)
            bundles.append((opt, val))
        elif opt in VALUE_OPTIONS:
            if not VALUE_OPTIONS[opt].match(val) or base is not None:
                raise R.ReleaseError(f"link_args: bad {opt} {val!r}")
            base = val
        elif opt == "-o":
            if val != OUTPUT or out:
                raise R.ReleaseError("link_args: -o must be given once, as @OUTPUT@")
            out = True
        else:
            raise R.ReleaseError(f"link_args: option {opt!r} is not part of the release link format")
        i += 2
    if kernel is None or not out or base is None:
        raise R.ReleaseError("link_args: -kernel, -kc-base and -o are required")
    return kernel, bundles, base


def bundle_files(bundle_dir):
    """Every regular file in a bundle, as (relative path, mode). Links and other types are refused."""
    files = []
    for p in sorted(bundle_dir.rglob("*")):
        rel = p.relative_to(bundle_dir).as_posix()
        if p.is_symlink() or not (p.is_file() or p.is_dir()):
            raise R.ReleaseError(f"{bundle_dir.name}/{rel}: only regular files and directories")
        if p.is_file():
            if not all(PART.match(x) for x in rel.split("/")):
                raise R.ReleaseError(f"{bundle_dir.name}/{rel}: unusual path")
            files.append((rel, 0o755 if os.stat(p).st_mode & stat.S_IXUSR else 0o644))
    if not files:
        raise R.ReleaseError(f"{bundle_dir.name} has no files")
    return files


def stage(inputs, out, add):
    """Copy a release-inputs directory (kernel, kexts/, codeless/, link-args.txt, as
    integrations/siliconforest/kc-builder/release-inputs.nix makes it) into the release directory OUT as
    flat artifacts; add(path, role) registers each. Returns install.json's kernel_collection without
    the tool and the expected hash."""
    args = [line for line in (inputs / "link-args.txt").read_text().splitlines() if line]
    _, bundles, base = parse_link_args(args)
    shutil.copyfile(inputs / "kernel", out / KERNEL)
    add(out / KERNEL, "kc-kernel")
    listed = []
    for opt, rel in bundles:
        kind, name = rel.split("/", 1)
        entries = []
        for path, mode in bundle_files(inputs / rel):
            art = artifact_name(kind, name, path)
            if (out / art).exists():
                raise R.ReleaseError(f"two bundle files map to {art}")
            shutil.copyfile(inputs / rel / path, out / art)
            add(out / art, "kc-bundle-file")
            entries.append({"path": path, "artifact": art, "mode": mode})
        listed.append({"dir": rel, "files": entries})
    on_disk = {f"{k}/{p.name}" for k in KINDS.values() if (inputs / k).is_dir() for p in (inputs / k).iterdir()}
    unused = on_disk - {rel for _, rel in bundles}
    if unused:
        raise R.ReleaseError(f"bundles not named by link-args.txt: {sorted(unused)}")
    return {"format": KC_FORMAT, "kernel": KERNEL, "bundles": listed, "link_args": args, "kc_base": base}


def check_section(kc, listed):
    """verify_release.py's rules for kernel_collection, against the listed artifacts {name: entry}."""
    if kc.get("format") != KC_FORMAT:
        raise R.ReleaseError("kernel_collection: unknown format")
    _, bundles, base = parse_link_args(kc["link_args"])
    if base != kc.get("kc_base"):
        raise R.ReleaseError("kernel_collection: kc_base disagrees with link_args")
    if [rel for _, rel in bundles] != [b["dir"] for b in kc["bundles"]]:
        raise R.ReleaseError("kernel_collection: bundles are not exactly link_args' bundles, in order")
    want = {kc["kernel"]: "kc-kernel", kc["tool"]["artifact"]: "kc-tool"}
    if kc["tool"].get("license_artifact"):
        want[kc["tool"]["license_artifact"]] = "kc-tool-license"
    for b in kc["bundles"]:
        paths = set()
        kind, name = b["dir"].split("/", 1)
        for f in b["files"]:
            if f["artifact"] != artifact_name(kind, name, f["path"]) or f["path"] in paths or f["mode"] not in (0o644, 0o755):
                raise R.ReleaseError(f"kernel_collection: bad file entry {f}")
            if not all(PART.match(x) for x in f["path"].split("/")):
                raise R.ReleaseError(f"kernel_collection: unusual path {f['path']!r}")
            paths.add(f["path"])
            want[f["artifact"]] = "kc-bundle-file"
    for art, role in want.items():
        if art not in listed or listed[art]["role"] != role:
            raise R.ReleaseError(f"kernel_collection: {art} is not a listed {role}")
    if any(e["role"].startswith("kc-") and n not in want for n, e in listed.items()):
        raise R.ReleaseError("kernel_collection: a kc artifact is listed but not used")
    if kc["tool"].get("signing") not in TOOL_SIGNING:
        raise R.ReleaseError("kernel_collection: unknown kc-builder signing")
    if not re.fullmatch(r"[0-9a-f]{64}", kc.get("collection_sha256", "")) or int(kc.get("collection_bytes", 0)) <= 0:
        raise R.ReleaseError("kernel_collection: no expected collection hash")


def assemble(kc, files, workdir, timeout=600):
    """Link the collection from verified inputs. files maps an artifact name to (path, sha256 expected).
    Every input is hashed before use; the tool must match its signed hash; the output must match
    collection_sha256/bytes. Returns the path of the accepted collection; leaves nothing else on a refusal."""
    workdir = Path(workdir)
    if workdir.exists():
        shutil.rmtree(workdir)
    tree = workdir / "inputs"
    tree.mkdir(parents=True)
    try:
        def take(art, dest, mode):
            src, want = files[art]
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dest)
            if R.sha256_file(dest)[0] != want:
                raise R.ReleaseError(f"{art} does not match its signed hash")
            os.chmod(dest, mode)

        take(kc["tool"]["artifact"], workdir / "kc-builder", 0o755)
        take(kc["kernel"], tree / "kernel", 0o444)
        for b in kc["bundles"]:
            for f in b["files"]:
                take(f["artifact"], tree / b["dir"] / f["path"], f["mode"])
        out = workdir / "collection"
        args = [str(out) if a == OUTPUT else a for a in kc["link_args"]]
        r = subprocess.run([str(workdir / "kc-builder"), *args], cwd=tree, env={"PATH": "/usr/bin:/bin", "LC_ALL": "C"},
                           stdin=subprocess.DEVNULL, capture_output=True, timeout=timeout)
        (workdir / "kc-builder.log").write_bytes(r.stdout + r.stderr)
        if r.returncode != 0:
            raise R.ReleaseError(f"kc-builder failed ({r.returncode})")
        digest, n = R.sha256_file(out)
        if digest != kc["collection_sha256"] or n != int(kc["collection_bytes"]):
            raise R.ReleaseError(f"the linked collection is {digest[:16]}… ({n} B), not the release's "
                                 f"{kc['collection_sha256'][:16]}… ({kc['collection_bytes']} B)")
        shutil.rmtree(tree)
        return out
    except BaseException:
        out = workdir / "collection"
        if out.exists():
            out.unlink()
        raise


def link_reference(inputs, tool, out):
    """Release time: link a release-inputs directory with a host kc-builder; returns (sha256, bytes)."""
    args = [line for line in (Path(inputs) / "link-args.txt").read_text().splitlines() if line]
    parse_link_args(args)
    out = Path(out).resolve()
    r = subprocess.run([str(tool), *[str(out) if a == OUTPUT else a for a in args]], cwd=inputs,
                       stdin=subprocess.DEVNULL, capture_output=True)
    if r.returncode != 0:
        raise R.ReleaseError(f"reference link failed: {r.stderr.decode(errors='replace')[-400:]}")
    return R.sha256_file(out)
