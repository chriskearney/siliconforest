#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Assemble and sign a SiliconForest installer release (docs/installer/PAYLOAD.md section 7).

    make_release.py --root-dir R --boot-dir B --firmware-names F.tsv --profiles DIR \\
                    --kc-inputs KC --kc-builder TOOL [--kc-builder-signing S] [--kc-link-tool T] [--kc-expect SHA] \\
                    --version V --sequence N --key KEY --out OUT [--rehearsal]

OUT receives the files of one release, all listed in SHA256SUMS, which KEY signs (SSH Ed25519
signature, namespace siliconforest-release, SHA256SUMS.sig):

    siliconforest-V-root.ext4.xz.NN   the installer root (prepare_root.py), xz, parts below 2 GiB
    siliconforest-V-root.manifest.tsv every entry of that root
    sf-stage1.bin, boot.bin, bootargs.template   stage 1, stage 2 and the boot-argument template, as built
    kc-builder, LICENSE.kc-tools, kc.kernel, kc.<kind>.<Bundle>.kext.<path>
                                      the kernel collection as separate files, linked on the Mac
                                      (kc_release.py; PAYLOAD.md section 13). The collection itself is
                                      never in a release: install.json carries the SHA-256 and size it
                                      must have, computed here by linking the same files (--kc-link-tool,
                                      a kc-builder for this host; default --kc-builder)
    install.json                      what the installer needs, including the names, sizes and
                                      SHA-256 of the Apple firmware it must extract on the Mac
                                      (never the firmware itself) and the slot offsets

A rehearsal must be signed with a TEST-ONLY key (make_test_key.sh) and says so in install.json.
Anything else needs a key in sfrelease.RELEASE_KEY_FINGERPRINTS (the offline release key Chris
made on 24 Nov 2026; its allowed_signers line is release/allowed_signers). Nothing here publishes anything.
"""

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sfrelease as R  # noqa: E402
import kc_release as KC  # noqa: E402
import tempfile  # noqa: E402

BOOT_ROLES = {"stage1": "sf-stage1.bin", "stage2": "boot.bin", "bootargs": "bootargs.template"}


def read_firmware_names(path):
    boards = {}
    meta = {}
    for line in Path(path).read_text().splitlines():
        if line.startswith("#"):
            if ":" in line:
                k, v = line[1:].split(":", 1)
                meta[k.strip()] = v.strip()
            continue
        if not line.strip():
            continue
        board, name, size, digest = line.split("\t")
        if not name.startswith(("brcm/", "apple/")) or ".." in name:
            raise R.ReleaseError(f"bad firmware name {name}")
        boards.setdefault(board, []).append({"name": name, "bytes": int(size), "sha256": digest})
    return meta, boards


def kernel_collection(a, out, add):
    signing = a.kc_builder_signing
    if signing == "rehearsal-stand-in" and not a.rehearsal:
        raise R.ReleaseError("the rehearsal stand-in for kc-builder is for rehearsals only")
    if not a.rehearsal and signing != "developer-id":
        raise R.ReleaseError("a release ships a Developer ID signed kc-builder")
    kc = KC.stage(a.kc_inputs, out, add)
    shutil.copyfile(a.kc_builder, out / KC.TOOL)
    add(out / KC.TOOL, "kc-tool")
    kc["tool"] = {"artifact": KC.TOOL, "signing": signing}
    lic = a.kc_builder.parent / KC.TOOL_LICENSE
    if lic.is_file():
        shutil.copyfile(lic, out / KC.TOOL_LICENSE)
        add(out / KC.TOOL_LICENSE, "kc-tool-license")
        kc["tool"]["license_artifact"] = KC.TOOL_LICENSE
    elif signing != "rehearsal-stand-in":
        raise R.ReleaseError(f"{KC.TOOL_LICENSE} must sit next to kc-builder (build-macos.sh puts it there)")
    with tempfile.TemporaryDirectory() as td:
        digest, n = KC.link_reference(a.kc_inputs, a.kc_link_tool or a.kc_builder, Path(td) / "collection")
    if a.kc_expect and a.kc_expect != digest:
        raise R.ReleaseError(f"the collection linked here is {digest}, not --kc-expect {a.kc_expect}")
    kc["collection_sha256"], kc["collection_bytes"] = digest, n
    return kc


def build(a):
    out = a.out
    if out.exists() and any(out.iterdir()):
        raise R.ReleaseError(f"{out} is not empty")
    out.mkdir(parents=True, exist_ok=True)
    key = R.key_info(Path(str(a.key) + ".pub"))
    if a.rehearsal != key["test_only"]:
        raise R.ReleaseError("a rehearsal is signed only with a TEST-ONLY key, and a TEST-ONLY key signs only rehearsals")
    if not a.rehearsal and key["fingerprint"] not in R.RELEASE_KEY_FINGERPRINTS:
        raise R.ReleaseError("not a known release key (the offline release key does not exist yet)")

    root = R.load_json(a.root_dir / "root.json")
    stem = f"siliconforest-{a.version}"
    artifacts = {}

    def add(path, role):
        name = R.check_name(path.name)
        digest, n = R.sha256_file(path)
        artifacts[name] = {"name": name, "bytes": n, "sha256": digest, "role": role}

    # root: xz in parts (one stream; the parts concatenate)
    xz = subprocess.Popen(["xz", f"-T{a.threads}", f"-{a.xz_level}", "--stdout", str(a.root_dir / root["image"])], stdout=subprocess.PIPE)
    parts, idx = [], 0
    while True:
        chunk_path = out / f"{stem}-root.ext4.xz.{idx:02d}"
        written = 0
        with chunk_path.open("wb") as f:
            while written < R.PART_LIMIT:
                buf = xz.stdout.read(min(1 << 20, R.PART_LIMIT - written))
                if not buf:
                    break
                f.write(buf)
                written += len(buf)
        if written == 0:
            chunk_path.unlink()
            break
        parts.append(chunk_path)
        idx += 1
        if written < R.PART_LIMIT:
            break
    if xz.wait() != 0 or not parts:
        raise R.ReleaseError("xz failed")
    for p in parts:
        add(p, "root-part")
    shutil.copyfile(a.root_dir / "root.manifest.tsv", out / f"{stem}-root.manifest.tsv")
    add(out / f"{stem}-root.manifest.tsv", "root-manifest")

    boot = {}
    for role, name in BOOT_ROLES.items():
        src = a.boot_dir / name
        if not src.is_file():
            raise R.ReleaseError(f"boot file {name} missing from {a.boot_dir}")
        shutil.copyfile(src, out / name)
        add(out / name, f"boot-{role}")
        boot[role] = name

    kc = kernel_collection(a, out, add)

    fw_meta, fw_boards = read_firmware_names(a.firmware_names)
    profiles = {}
    for p in sorted(a.profiles.glob("*.json")):
        if p.name.endswith(".schema.json"):
            continue
        prof = json.loads(p.read_text())
        board = prof.get("id") or p.stem
        profiles[board] = {"sha256": R.sha256_file(p)[0], "stub_version": prof.get("stub", {}).get("version")}

    install = {
        "format": R.INSTALL_FORMAT,
        "release": a.version,
        "sequence": a.sequence,
        "rehearsal": a.rehearsal,
        "signing_key": {"fingerprint": key["fingerprint"], "test_only": key["test_only"]},
        "models": sorted(set(profiles) & set(fw_boards)) if fw_boards else sorted(profiles),
        "profiles": profiles,
        "macos": {"min": "13.5", "max_major": 26},
        "stub": {"version": fw_meta.get("version", "13.5"), "build": fw_meta.get("build", "22G74"),
                 "restore_image": {"url": fw_meta.get("url", ""), "bytes": int(fw_meta.get("bytes", "0") or 0)},
                 "build_manifest_sha256": fw_meta.get("build_manifest_sha256", "")},
        "root": {
            "fs_uuid": root["fs_uuid"],
            "compression": "xz",
            "image_bytes": root["image_bytes"],
            "image_sha256": root["image_sha256"],
            "sizing": "grow",
            "min_bytes": root["image_bytes"],
            "grow": root["grow"],
            "parts": [p.name for p in parts],
            "manifest": f"{stem}-root.manifest.tsv",
        },
        "firmware_slot": root["firmware_slot"],
        "receipt_slot": root["receipt_slot"],
        "boot": boot,
        "kernel_collection": kc,
        "firmware": {"policy": "extract-on-this-mac-never-redistribute", "source": "apple-restore-image",
                     "build": fw_meta.get("build", ""), "boards": fw_boards},
        "artifacts": sorted(artifacts.values(), key=lambda x: x["name"]),
    }
    (out / "install.json").write_text(json.dumps(install, indent=2, sort_keys=True) + "\n")
    add(out / "install.json", "install-descriptor")

    with (out / R.SUMS).open("w") as f:
        for name in sorted(artifacts):
            f.write(f"{artifacts[name]['sha256']}  {name}\n")
    subprocess.run(["ssh-keygen", "-q", "-Y", "sign", "-n", R.NAMESPACE, "-f", str(a.key), str(out / R.SUMS)], check=True,
                   stdin=subprocess.DEVNULL)
    return install


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root-dir", type=Path, required=True)
    ap.add_argument("--boot-dir", type=Path, required=True)
    ap.add_argument("--firmware-names", type=Path, required=True)
    ap.add_argument("--profiles", type=Path, required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--sequence", type=int, required=True)
    ap.add_argument("--key", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--kc-inputs", type=Path, required=True, help="release-inputs directory (kernel, kexts/, codeless/, link-args.txt)")
    ap.add_argument("--kc-builder", type=Path, required=True, help="the kc-builder the Mac runs (build-macos.sh output)")
    ap.add_argument("--kc-builder-signing", choices=KC.TOOL_SIGNING, default="developer-id")
    ap.add_argument("--kc-link-tool", type=Path, help="a kc-builder that runs on this host, for the expected hash")
    ap.add_argument("--kc-expect", help="the SHA-256 the collection must have (e.g. release-inputs.nix's kernel)")
    ap.add_argument("--rehearsal", action="store_true")
    ap.add_argument("--xz-level", type=int, default=6)
    ap.add_argument("--threads", type=int, default=0)
    a = ap.parse_args(argv)
    try:
        install = build(a)
    except (R.ReleaseError, subprocess.CalledProcessError, OSError) as e:
        print(f"make_release: {e}", file=sys.stderr)
        return 1
    print(json.dumps({"release": install["release"], "rehearsal": install["rehearsal"], "artifacts": len(install["artifacts"]),
                      "key": install["signing_key"]["fingerprint"]}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
