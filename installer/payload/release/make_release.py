#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Assemble and sign a SiliconForest installer release (docs/installer/PAYLOAD.md section 7).

    make_release.py --root-dir R --boot-dir B --firmware-names F.tsv --profiles DIR \\
                    --kc-inputs KC --kc-builder TOOL [--kc-builder-signing S] [--kc-link-tool T] [--kc-expect SHA] \\
                    --version V --sequence N --key KEY --out OUT [--rehearsal]
                    --unsigned --public-key PUB   assemble without the private key; sign SHA256SUMS offline

OUT receives the files of one release, all listed in SHA256SUMS, which KEY signs (SSH Ed25519
signature, namespace siliconforest-release, SHA256SUMS.sig):

    siliconforest-V-root.ext4.xz.NN   the installer root (prepare_root.py), xz, parts below 2 GiB
    siliconforest-V-root.manifest.tsv every entry of that root
    sf-stage1.bin, boot.bin, bootargs.template   stage 1, stage 2 and the boot-argument template, as built
    boot-b.bin                        slot B's stage 2 (A/B boot, abboot), when the boot directory has it
    bootstate.bin                     the A/B boot record for a fresh install (sf-bootslot init: slot A as
                                      installed, good), only with stage 1 v2 and boot-b.bin (--slots)
    sf-trust.txt                      SAP's trust anchor, sf_trust=<version>:<key> for the signing key; also
                                      appended to bootargs.template when the personalised arguments still
                                      fit m1n1's 607 characters (docs/sap/README.md)
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
STAGE2_B = "boot-b.bin"
BOOTSTATE = "bootstate.bin"
TRUST = "sf-trust.txt"
REPO = Path(__file__).resolve().parents[3]
ABBOOT = REPO / "integrations/siliconforest/m1-native-boot/install/abboot"
BOOTARGS_CAPACITY = 608   # m1n1 xnuboot.h v2, with the NUL (SFEngine PDSF.bootargsCapacity)
# Worst case of the fields the installer fills in, and the slot marker SAP adds for slot B
PERSONALISED = {"@SF_FSUUID@": 36, "@SF_PARTUUID@": 36, "@SF_PART_LBA@": 10, "@SF_PART_BLOCKS@": 10}
SLOT_MARK = " sf_slot=b"


def template_args(text):
    """The command line a bootargs.template holds: lines not starting with #, joined by spaces."""
    return " ".join(l.strip() for l in text.splitlines() if l.strip() and not l.lstrip().startswith("#"))


def personalised_length(args):
    n = len(args)
    for field, width in PERSONALISED.items():
        n += args.count(field) * (width - len(field))
    return n + len(SLOT_MARK)


def trust_token(pub_path, version=1):
    import base64
    blob = base64.b64decode(Path(pub_path).read_text().split("ssh-ed25519", 1)[1].split()[0])
    if blob[:15] != b"\0\0\0\x0bssh-ed25519" or len(blob) != 51:
        raise R.ReleaseError(f"{pub_path}: not an Ed25519 public key")
    return f"sf_trust={version}:" + base64.b64encode(blob[-32:]).decode().rstrip("=")


def make_bootstate(stage2, generation):
    """sf/bootstate.bin as `sf-bootslot init` writes it for a fresh install (slot A = stage2, good),
    by running a host build of sf-bootslot on a scratch SFBOOT."""
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        tool = td / "sf-bootslot"
        cc = shutil.which("cc") or shutil.which("clang") or shutil.which("gcc")
        if not cc:
            raise R.ReleaseError("no C compiler for sf-bootslot (bootstate.bin)")
        subprocess.run([cc, "-std=c11", "-O1", "-I", str(ABBOOT), str(ABBOOT / "sf_ab.c"), str(ABBOOT / "sf-bootslot.c"), "-o", str(tool)],
                       check=True, capture_output=True)
        (td / "boot/sf").mkdir(parents=True)
        shutil.copyfile(stage2, td / "boot/sf/boot.bin")
        subprocess.run([str(tool), "--boot", str(td / "boot"), "--running", "a", "--generation", str(generation), "init"],
                       check=True, capture_output=True)
        st = subprocess.run([str(tool), "--boot", str(td / "boot"), "status"], check=True, capture_output=True, text=True).stdout
        if "default=a" not in st or "file:matches" not in st:
            raise R.ReleaseError(f"sf-bootslot init did not record slot A:\n{st}")
        return (td / "boot/sf/bootstate.bin").read_bytes()


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
    if a.unsigned:
        if a.key is not None:
            raise R.ReleaseError("--unsigned does not take --key (the private key stays offline)")
        if a.public_key is None:
            raise R.ReleaseError("--unsigned needs --public-key")
        key = R.key_info(a.public_key)
    else:
        if a.key is None:
            raise R.ReleaseError("--key is required unless --unsigned")
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
    stage1_tag = None
    for role, name in BOOT_ROLES.items():
        src = a.boot_dir / name
        if not src.is_file():
            raise R.ReleaseError(f"boot file {name} missing from {a.boot_dir}")
        if role == "stage1":
            # A release carries our real stage 1 (boot/build_stage1.sh); only a rehearsal may use a placeholder.
            data = src.read_bytes()
            if not a.rehearsal or R.STAGE1_MARK in data:
                stage1_tag = R.check_stage1(data, *R.profile_stage1(a.profiles))
        shutil.copyfile(src, out / name)
        add(out / name, f"boot-{role}")
        boot[role] = name
    if stage1_tag:
        boot["stage1_tag"] = stage1_tag
    # A/B boot (abboot): slot B's stage 2, and the record for slot A, only for stage 1 v2
    if (a.boot_dir / STAGE2_B).is_file():
        shutil.copyfile(a.boot_dir / STAGE2_B, out / STAGE2_B)
        add(out / STAGE2_B, "boot-stage2-b")
        boot["stage2_b"] = STAGE2_B
    v2 = bool(stage1_tag and stage1_tag.endswith("-siliconforest-stage1-v2"))
    slots = a.slots == "yes" or (a.slots == "auto" and v2 and "stage2_b" in boot)
    if slots:
        if "stage2_b" not in boot:
            raise R.ReleaseError(f"--slots needs {STAGE2_B} in {a.boot_dir}")
        if not v2 and not a.rehearsal:
            raise R.ReleaseError("A/B slots need stage 1 v2 (abboot/build_stage1_v2.sh); stage 1 v1 never reads the record")
        (out / BOOTSTATE).write_bytes(make_bootstate(out / boot["stage2"], a.sequence))
        add(out / BOOTSTATE, "boot-state")
        boot["bootstate"] = BOOTSTATE
    boot["slots"] = slots
    # SAP's trust anchor (design 8.2): the signing key, in sf-trust.txt (written to SFBOOT as sf/trust)
    # and, when it fits, in the boot arguments themselves
    pub = a.public_key if a.unsigned else Path(str(a.key) + ".pub")
    token = trust_token(pub)
    (out / TRUST).write_text(token + "\n")
    add(out / TRUST, "boot-trust")
    boot["trust"] = TRUST
    tmpl = (out / boot["bootargs"]).read_text()
    args = template_args(tmpl)
    boot["trust_in_bootargs"] = False
    if "sf_trust=" in args:
        raise R.ReleaseError("bootargs.template already has an sf_trust= token")
    if personalised_length(args + " " + token) < BOOTARGS_CAPACITY:
        (out / boot["bootargs"]).write_text(tmpl.rstrip("\n") + "\n" + token + "\n")
        add(out / boot["bootargs"], "boot-bootargs")
        boot["trust_in_bootargs"] = True
    boot["bootargs_personalised_max"] = personalised_length(template_args((out / boot["bootargs"]).read_text()))

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
    if a.unsigned:
        return install
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
    ap.add_argument("--key", type=Path, help="private key; signs SHA256SUMS. Omit with --unsigned.")
    ap.add_argument("--public-key", type=Path, help="public key only, for --unsigned (fingerprint in install.json)")
    ap.add_argument("--unsigned", action="store_true", help="write SHA256SUMS but do not sign; sign offline with the release key")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--kc-inputs", type=Path, required=True, help="release-inputs directory (kernel, kexts/, codeless/, link-args.txt)")
    ap.add_argument("--kc-builder", type=Path, required=True, help="the kc-builder the Mac runs (build-macos.sh output)")
    ap.add_argument("--kc-builder-signing", choices=KC.TOOL_SIGNING, default="developer-id")
    ap.add_argument("--kc-link-tool", type=Path, help="a kc-builder that runs on this host, for the expected hash")
    ap.add_argument("--kc-expect", help="the SHA-256 the collection must have (e.g. release-inputs.nix's kernel)")
    ap.add_argument("--rehearsal", action="store_true")
    ap.add_argument("--slots", choices=("auto", "yes", "no"), default="auto",
                    help="A/B boot record (bootstate.bin): auto = with stage 1 v2 and boot-b.bin; yes in a rehearsal also with a placeholder stage 1")
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
