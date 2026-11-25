#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""sap-build: publish a SAP update channel (docs/sap/OPERATOR.md), and the Python reference verifier.

    sap_build.py scan TREE > root.manifest.tsv            a per-file manifest for a tree (installer format)
    sap_build.py publish --repo DIR --release R --tree TREE [--root-tsv TSV] [--spec SPEC.json]
                         [--kc-release RELDIR] [--boot-bin boot.bin [--boot-bin-b slot-b-boot.bin]] [--sequence N] [--expires-days 30]
                         [--base-sums SHA256SUMS] [--min-sap V] [--trust-keys FILE --trust-version N]
                         [--bump-changed] (--key KEY | --unsigned)
    sap_build.py sign --key KEY FILE                      offline signing step (ssh-keygen -Y sign)
    sap_build.py verify --repo DIR --allowed-signers FILE [--deep]
    sap_build.py seed-db --repo DIR --root ROOT [--allowed-signers FILE]
    sap_build.py anchor-token PUB... [--version N]        the sf_trust= boot argument for a key set
    sap_build.py test-key DIR                             a throwaway TEST-ONLY key (never for releases)

Layout of a channel (static files, servable over HTTPS or any mirror):

    DIR/v1/stable/manifest.json, manifest.json.sig
    DIR/v1/stable/pool/<name>_<version>.record.json, .files.tsv, .sappkg

The private key is never read by this tool: signing runs ssh-keygen with the key path, exactly as the
release's SHA256SUMS is signed. Real releases are signed offline on the M3 (`publish --unsigned` here,
`sign` there). Tests and rehearsals use a TEST-ONLY key made by `test-key`.
"""

import argparse
import datetime as dt
import fnmatch
import hashlib
import io
import json
import lzma
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[1]
sys.path.insert(0, str(REPO_ROOT / "installer" / "payload" / "release"))
import kc_release as KC  # noqa: E402  (read-only reuse of the installer's kernel-collection rules)
import sfrelease as R  # noqa: E402

NAMESPACE = R.NAMESPACE
SCHEMA = "siliconforest-update/1"
RECORD_SCHEMA = "siliconforest-package/1"
PAYLOAD_FORMAT = "xz-bodies/1"
HEADER = "# path\ttype\tmode\tuid\tgid\tsize\tsha256 or link target"
PROTECTED = {"/private/var/db/sf-firmware-slot", "/private/var/db/sf-boot-receipt", "/var/db/sf-firmware-slot", "/var/db/sf-boot-receipt"}
NAME = re.compile(r"\A[a-z0-9][a-z0-9+._-]{0,127}\Z")
VERSION = re.compile(r"\A[A-Za-z0-9][A-Za-z0-9.+~-]{0,63}\Z")
KINDS = {"base", "files", "kc-input", "kc-recipe", "boot-stage2"}
# Where kernel-collection inputs live in the root (design Q5; a proposal until the image recipe agrees).
KC_ROOT = "/System/Library/SiliconForest/KernelCollection"
KC_TOOL_PATH = "/usr/libexec/sap/kc-builder"
KC_LICENSE_PATH = "/usr/share/sap/LICENSE.kc-tools"


class BuildError(Exception):
    pass


def sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()


def sha256_file(p):
    return R.sha256_file(p)


def utc(t):
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


def vkey(v):
    """The client's version order (sap/client/src/version.rs)."""
    up, _, rev = v.rpartition("-") if "-" in v else (v, "", "0")
    parts = re.split(r"[.+~]", up)
    key = []
    for p in parts:
        key.append((0, int(p), "") if p.isdigit() else (1, 0, p))
    return key, int(rev) if rev.isdigit() else 0


def vcmp(a, b):
    ka, kb = vkey(a), vkey(b)
    # Component-wise, shorter is smaller when equal so far (as compare() in version.rs).
    for x, y in zip(ka[0], kb[0]):
        if x != y:
            return -1 if x < y else 1
    if len(ka[0]) != len(kb[0]):
        return -1 if len(ka[0]) < len(kb[0]) else 1
    return (ka[1] > kb[1]) - (ka[1] < kb[1])


def bump(v):
    up, sep, rev = v.rpartition("-")
    if sep and rev.isdigit():
        return f"{up}-{int(rev) + 1}"
    return f"{v}-1"


# ---- per-file manifests ----

def row(path, kind, mode, uid, gid, size, data):
    return f"{path}\t{kind}\t{mode:04o}\t{uid}\t{gid}\t{size}\t{data}"


def parse_tsv(text):
    rows = []
    for n, line in enumerate(text.splitlines(), 1):
        if not line or line.startswith("#"):
            continue
        c = line.split("\t")
        if len(c) != 7 or c[1] not in ("f", "d", "l") or not re.fullmatch(r"[0-7]{4}", c[2]):
            raise BuildError(f"TSV line {n} is malformed")
        p = c[0]
        if not p.startswith("/") or p == "/" or any(x in ("", ".", "..") for x in p[1:].split("/")):
            raise BuildError(f"TSV line {n}: unsafe path {p!r}")
        rows.append({"path": p, "type": c[1], "mode": int(c[2], 8), "uid": int(c[3]), "gid": int(c[4]), "size": int(c[5]), "data": c[6]})
    return rows


def render_tsv(rows):
    return HEADER + "\n" + "".join(row(r["path"], r["type"], r["mode"], r["uid"], r["gid"], r["size"], r["data"]) + "\n" for r in rows)


def scan(tree, owners_from_stat=False):
    tree = Path(tree)
    rows = []
    for dirpath, dirnames, filenames in os.walk(tree):
        dirnames.sort()
        for name in sorted(dirnames + filenames):
            p = Path(dirpath) / name
            rel = "/" + p.relative_to(tree).as_posix()
            st = os.lstat(p)
            uid, gid = (st.st_uid, st.st_gid) if owners_from_stat else (0, 0)
            mode = stat.S_IMODE(st.st_mode)
            if stat.S_ISLNK(st.st_mode):
                t = os.readlink(p)
                rows.append({"path": rel, "type": "l", "mode": 0o777, "uid": uid, "gid": gid, "size": len(t), "data": t})
            elif stat.S_ISDIR(st.st_mode):
                rows.append({"path": rel, "type": "d", "mode": mode, "uid": uid, "gid": gid, "size": 0, "data": "-"})
            elif stat.S_ISREG(st.st_mode):
                h, n = sha256_file(p)
                rows.append({"path": rel, "type": "f", "mode": mode, "uid": uid, "gid": gid, "size": n, "data": h})
            else:
                raise BuildError(f"{rel}: only files, directories and symlinks")
    rows.sort(key=lambda r: r["path"])
    return rows


# ---- packages ----

def matches(path, pattern):
    if pattern.endswith("/**"):
        base = pattern[:-3]
        return path == base or path.startswith(base + "/")
    return fnmatch.fnmatchcase(path, pattern)


def xz(data):
    return lzma.compress(data, format=lzma.FORMAT_XZ, check=lzma.CHECK_CRC64, preset=6)


class Pkg:
    def __init__(self, name, kind, version=None, explicit=False, **kw):
        if not NAME.match(name):
            raise BuildError(f"bad package name {name!r}")
        if kind not in KINDS:
            raise BuildError(f"{name}: unknown kind {kind}")
        self.name, self.kind, self.version, self.explicit = name, kind, version, explicit
        self.rows = []          # TSV rows
        self.bodies = {}        # path -> bytes source (Path)
        self.depends = kw.get("depends", [])
        self.conflicts = kw.get("conflicts", [])
        self.replaces = kw.get("replaces", [])
        self.config_files = kw.get("config_files", [])
        self.services = kw.get("services", [])
        self.activate = kw.get("activate", "none")
        self.summary = kw.get("summary", "")
        self.target = kw.get("target", "root")
        self.extra = kw.get("extra", {})
        self.components = kw.get("components")

    def semantic(self):
        """Everything that defines the package except its version: same semantic => same package."""
        return json.dumps({"kind": self.kind, "tsv": render_tsv(self.rows), "depends": self.depends, "conflicts": self.conflicts,
                           "replaces": self.replaces, "config_files": self.config_files, "services": self.services,
                           "activate": self.activate, "target": self.target, "extra": self.extra, "summary": self.summary},
                          sort_keys=True)


def deps(spec_list):
    out = []
    for d in spec_list or []:
        if isinstance(d, str):
            name, _, c = d.partition(" ")
            out.append({"name": name, "version": c.strip() or None})
        else:
            out.append({"name": d["name"], "version": d.get("version")})
    for d in out:
        if not NAME.match(d["name"]):
            raise BuildError(f"bad dependency {d['name']!r}")
        if d["version"] is None:
            del d["version"]
    return out


def build_root_packages(rows, tree, spec, release):
    """Split the root manifest into the spec's packages; sf-base owns every file no other package claims."""
    tree = Path(tree)
    specs = spec.get("packages", [])
    base_spec = spec.get("base", {})
    base = Pkg(base_spec.get("name", "sf-base"), "base", base_spec.get("version"), explicit="version" in base_spec,
               summary=base_spec.get("summary", "SiliconForest base system"), depends=deps(base_spec.get("depends")))
    pkgs = []
    for s in specs:
        if s.get("kind", "files") not in ("files",):
            raise BuildError(f"{s['name']}: root packages are kind files")
        pkgs.append(Pkg(s["name"], "files", s.get("version"), explicit="version" in s, depends=deps(s.get("depends")),
                        conflicts=deps(s.get("conflicts")), replaces=s.get("replaces", []), config_files=s.get("config_files", []),
                        services=s.get("services", []), activate=s.get("activate", "none"), summary=s.get("summary", "")))
        pkgs[-1].patterns = s.get("paths", [])
    for r in rows:
        if r["path"] in PROTECTED:
            continue   # fixed-extent installer files are never part of any package
        owner = next((p for p in pkgs if any(matches(r["path"], pat) for pat in p.patterns)), None)
        if owner is None:
            owner = base
        owner.rows.append(r)
        if r["type"] == "f":
            src = tree / r["path"][1:]
            if not src.is_file():
                raise BuildError(f"{r['path']} is in the manifest but not in the tree")
            owner.bodies[r["path"]] = src
    for p in pkgs:
        for pat in p.patterns:
            if any(matches(x, pat) for x in PROTECTED):
                raise BuildError(f"{p.name} claims a protected path ({pat})")
        if not p.rows:
            raise BuildError(f"{p.name}: no files match {p.patterns}")
    return [base] + pkgs


def kext_package_name(d):
    n = d.split("/", 1)[1][:-5].lower()
    return "sf-kext-" + re.sub(r"[^a-z0-9+.-]", "-", n)


def build_kc_packages(reldir):
    """kc-input packages (kernel, linker, one per bundle) and the kc-recipe, from an installer release."""
    reldir = Path(reldir)
    inst = json.loads((reldir / "install.json").read_text())
    kc = inst["kernel_collection"]
    listed = {a["name"]: a for a in inst["artifacts"]}
    KC.check_section(kc, listed)
    for a in listed.values():
        h, n = sha256_file(reldir / a["name"])
        if h != a["sha256"] or n != a["bytes"]:
            raise BuildError(f"{a['name']} does not match install.json")
    bootargs = (reldir / inst["boot"]["bootargs"]).read_text() if inst.get("boot", {}).get("bootargs") else ""

    def file_row(path, art, mode):
        h, n = sha256_file(reldir / art)
        return {"path": path, "type": "f", "mode": mode, "uid": 0, "gid": 0, "size": n, "data": h}, reldir / art

    out = []
    tool = Pkg("sf-kc-builder", "kc-input", summary="kc-builder, the kernel-collection linker", activate="none")
    r, src = file_row(KC_TOOL_PATH, kc["tool"]["artifact"], 0o755)
    tool.rows.append(r); tool.bodies[r["path"]] = src
    if kc["tool"].get("license_artifact"):
        r, src = file_row(KC_LICENSE_PATH, kc["tool"]["license_artifact"], 0o644)
        tool.rows.append(r); tool.bodies[r["path"]] = src
    tool.extra = {"signing": kc["tool"].get("signing")}
    out.append(tool)
    kern = Pkg("sf-kc-kernel", "kc-input", summary="the SiliconForest kernel (kernel-collection input)")
    r, src = file_row(f"{KC_ROOT}/kernel", kc["kernel"], 0o644)
    kern.rows.append(r); kern.bodies[r["path"]] = src
    out.append(kern)
    bundles = []
    for b in kc["bundles"]:
        p = Pkg(kext_package_name(b["dir"]), "kc-input", summary=f"{b['dir']} (kernel-collection input)")
        files = []
        for f in b["files"]:
            rp = f"{KC_ROOT}/{b['dir']}/{f['path']}"
            r, src = file_row(rp, f["artifact"], f["mode"])
            p.rows.append(r); p.bodies[rp] = src
            files.append({"path": f["path"], "mode": f["mode"], "root_path": rp})
        p.rows.sort(key=lambda r: r["path"])
        out.append(p)
        bundles.append({"dir": b["dir"], "package": p.name, "files": files})
    recipe = Pkg("sf-kernel-collection", "kc-recipe", summary="kernel collection recipe (link order, options, expected hash)",
                 activate="reboot")
    recipe.extra = {
        "kernel_collection": {
            "format": KC.KC_FORMAT, "link_args": kc["link_args"], "kc_base": kc["kc_base"],
            "kernel": {"path": f"{KC_ROOT}/kernel", "package": kern.name},
            "tool": {"path": KC_TOOL_PATH, "package": tool.name, "signing": kc["tool"].get("signing")},
            "bundles": bundles, "collection_sha256": kc["collection_sha256"], "collection_bytes": int(kc["collection_bytes"]),
        },
        "bootargs_template": bootargs,
    }
    recipe.components = {"collection_sha256": kc["collection_sha256"], "collection_bytes": int(kc["collection_bytes"])}
    return out, recipe


def finalize_versions(pkgs, prev, release, bump_changed):
    """Pick each package's version: unchanged content keeps the published version (nothing to download);
    changed content needs a higher one."""
    for p in pkgs:
        old = prev.get(p.name)
        derived = p.version or f"{release}-1"
        if not VERSION.match(derived):
            raise BuildError(f"{p.name}: bad version {derived!r}")
        if old is None:
            p.version = derived
            continue
        same = old["semantic"] == p.semantic()
        if p.explicit:
            c = vcmp(p.version, old["version"])
            if c < 0:
                raise BuildError(f"{p.name}: version {p.version} is lower than the published {old['version']}")
            if c == 0 and not same:
                if not bump_changed:
                    raise BuildError(f"{p.name} {p.version} changed but keeps its version; raise it or pass --bump-changed")
                p.version = bump(old["version"])
        elif same:
            p.version = old["version"]
        else:
            p.version = derived if vcmp(derived, old["version"]) > 0 else bump(old["version"])


def write_pool(pool, name, data):
    p = pool / name
    if p.exists():
        if p.read_bytes() != data:
            raise BuildError(f"pool/{name} already exists with other content; pool files are immutable")
        return
    tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_bytes(data)
    os.replace(tmp, p)


def emit(pkg, pool, recipe_deps=None):
    tsv = render_tsv(pkg.rows).encode()
    stem = f"{pkg.name}_{pkg.version}"
    files_name = f"{stem}.files.tsv"
    write_pool(pool, files_name, tsv)
    nbytes = sum(r["size"] for r in pkg.rows if r["type"] == "f")
    payload = None
    if any(r["type"] == "f" for r in pkg.rows):
        pname = f"{stem}.sappkg"
        if (pool / pname).exists():
            body = (pool / pname).read_bytes()
        else:
            raw = b"".join(pkg.bodies[r["path"]].read_bytes() for r in pkg.rows if r["type"] == "f")
            if len(raw) != nbytes:
                raise BuildError(f"{pkg.name}: a file changed while it was read")
            body = xz(raw)
            write_pool(pool, pname, body)
        payload = {"name": pname, "format": PAYLOAD_FORMAT, "bytes": len(body), "sha256": sha256_bytes(body)}
    rec = {
        "schema": RECORD_SCHEMA, "name": pkg.name, "version": pkg.version, "kind": pkg.kind, "summary": pkg.summary,
        "arch": "arm64", "depends": pkg.depends, "conflicts": pkg.conflicts, "replaces": pkg.replaces,
        "files": {"name": files_name, "count": len(pkg.rows), "bytes": nbytes, "sha256": sha256_bytes(tsv)},
        "config_files": pkg.config_files, "services": pkg.services, "activate": pkg.activate, "payload": payload,
        "target": pkg.target,
    }
    rec.update(pkg.extra)
    rb = (json.dumps(rec, indent=2, sort_keys=False) + "\n").encode()
    write_pool(pool, f"{stem}.record.json", rb)
    entry = {"name": pkg.name, "version": pkg.version, "kind": pkg.kind, "depends": pkg.depends, "activate": pkg.activate,
             "bytes": payload["bytes"] if payload else 0,
             "record": {"url": f"pool/{stem}.record.json", "sha256": sha256_bytes(rb)}}
    if payload:
        entry["payload"] = {"url": f"pool/{payload['name']}", "sha256": payload["sha256"]}
    if pkg.components:
        entry["components"] = pkg.components
    return entry


def previous(chan):
    """name -> {version, semantic} of the channel's current manifest (its own bytes, not re-verified here)."""
    mp = chan / "manifest.json"
    if not mp.exists():
        return {}, 0
    m = json.loads(mp.read_text())
    out = {}
    for e in m["packages"]:
        rec = json.loads((chan / e["record"]["url"]).read_text())
        rows = parse_tsv((chan / "pool" / rec["files"]["name"]).read_text())
        p = Pkg(e["name"], e["kind"], e["version"], depends=rec["depends"], conflicts=rec.get("conflicts", []), replaces=rec.get("replaces", []),
                config_files=rec.get("config_files", []), services=rec.get("services", []), activate=rec.get("activate", "none"),
                summary=rec.get("summary", ""), target=rec.get("target", "root"))
        p.rows = rows
        p.extra = {k: v for k, v in rec.items() if k in ("kernel_collection", "bootargs_template", "signing")}
        out[e["name"]] = {"version": e["version"], "semantic": p.semantic()}
    return out, m["sequence"]


def ssh_sign(key, path):
    sig = Path(str(path) + ".sig")
    if sig.exists():
        sig.unlink()
    subprocess.run(["ssh-keygen", "-q", "-Y", "sign", "-n", NAMESPACE, "-f", str(key), str(path)], check=True, stdin=subprocess.DEVNULL)
    return sig


def publish(a):
    repo = Path(a.repo)
    chan = repo / "v1" / a.channel
    pool = chan / "pool"
    pool.mkdir(parents=True, exist_ok=True)
    prev, prev_seq = previous(chan)
    tree = Path(a.tree) if a.tree else None
    pkgs = []
    if tree:
        rows = parse_tsv(Path(a.root_tsv).read_text()) if a.root_tsv else scan(tree)
        spec = json.loads(Path(a.spec).read_text()) if a.spec else {}
        pkgs += build_root_packages(rows, tree, spec, a.release)
    recipe = None
    if a.kc_release:
        kcp, recipe = build_kc_packages(a.kc_release)
        pkgs += kcp
    if a.boot_bin:
        b = Pkg("sf-boot", "boot-stage2", a.boot_version, explicit=bool(a.boot_version), summary="stage 2 (sf/boot.bin)", activate="reboot", target="sfboot")
        h, n = sha256_file(a.boot_bin)
        b.rows.append({"path": "/sf/boot.bin", "type": "f", "mode": 0o644, "uid": 0, "gid": 0, "size": n, "data": h})
        b.bodies["/sf/boot.bin"] = Path(a.boot_bin)
        if a.boot_bin_b:
            # Slot B's stage 2 (built with PDSF_KERNEL_FILE="sf/b/kernel.bin"), for A/B machines (design 10.1).
            h, n = sha256_file(a.boot_bin_b)
            b.rows.append({"path": "/sf/b/boot.bin", "type": "f", "mode": 0o644, "uid": 0, "gid": 0, "size": n, "data": h})
            b.bodies["/sf/b/boot.bin"] = Path(a.boot_bin_b)
            b.rows.sort(key=lambda r: r["path"])
        pkgs.append(b)
    if not pkgs and not recipe:
        raise BuildError("nothing to publish (give --tree, --kc-release or --boot-bin)")
    names = [p.name for p in pkgs] + ([recipe.name] if recipe else [])
    if len(set(names)) != len(names):
        raise BuildError("two packages have the same name")
    finalize_versions(pkgs, prev, a.release, a.bump_changed)
    if recipe:
        recipe.depends = [{"name": p.name, "version": f"= {p.version}"} for p in pkgs if p.kind == "kc-input"]
        finalize_versions([recipe], prev, a.release, a.bump_changed)
    entries = [emit(p, pool) for p in pkgs] + ([emit(recipe, pool)] if recipe else [])
    seq = a.sequence if a.sequence is not None else prev_seq + 1
    if seq <= prev_seq and not a.allow_same_sequence:
        raise BuildError(f"sequence {seq} must be higher than the published {prev_seq}")
    issued = dt.datetime.strptime(a.issued, "%Y-%m-%dT%H:%M:%SZ") if a.issued else dt.datetime.now(dt.timezone.utc).replace(microsecond=0, tzinfo=None)
    expires = issued + dt.timedelta(days=a.expires_days)
    man = {
        "schema": SCHEMA, "channel": a.channel, "release": a.release, "sequence": seq,
        "issued": utc(issued), "expires": utc(expires), "min_sap": a.min_sap, "critical": a.critical or [],
        "base": {"release": a.base_release or a.release, "sums_sha256": sha256_file(a.base_sums)[0] if a.base_sums else None},
        "signing_key": None, "allowed_prefixes": a.allowed_prefix or ["/"], "packages": entries,
        "removed": sorted(set(prev) - set(names)), "rollout": None, "delta": None,
    }
    if a.trust_keys:
        keys = [l.strip() for l in Path(a.trust_keys).read_text().splitlines() if "ssh-ed25519" in l]
        keys = ["ssh-ed25519 " + l.split("ssh-ed25519", 1)[1].split()[0] for l in keys]
        man["trust"] = {"version": a.trust_version, "keys": keys}
    if a.key:
        man["signing_key"] = {"fingerprint": R.key_info(str(a.key) + ".pub")["fingerprint"]}
    mp = chan / "manifest.json"
    tmp = chan / "manifest.json.tmp"
    tmp.write_text(json.dumps(man, indent=2) + "\n")
    os.replace(tmp, mp)
    sig = chan / "manifest.json.sig"
    if sig.exists():
        sig.unlink()
    if a.key:
        ssh_sign(a.key, mp)
    changed = [e["name"] for e in entries if prev.get(e["name"], {}).get("version") != e["version"]]
    print(json.dumps({"manifest": str(mp), "sequence": seq, "packages": len(entries), "changed": changed, "signed": bool(a.key)}))
    return 0


# ---- the Python reference verifier (design 9.3: differential against the Rust client) ----

def verify_repo(repo, allowed_signers, channel="stable", deep=False, now=None):
    chan = Path(repo) / "v1" / channel
    mp, sp = chan / "manifest.json", chan / "manifest.json.sig"
    data = mp.read_bytes()
    if len(data) > 4 << 20:
        raise BuildError("manifest larger than 4 MiB")
    with mp.open("rb") as f:
        p = subprocess.run(["ssh-keygen", "-Y", "verify", "-f", str(allowed_signers), "-I", NAMESPACE, "-n", NAMESPACE, "-s", str(sp)],
                           stdin=f, capture_output=True, text=True)
    if p.returncode != 0:
        raise BuildError("signature does not verify")

    def no_dupes(pairs):
        keys = [k for k, _ in pairs]
        if len(keys) != len(set(keys)):
            raise BuildError("duplicate JSON key")
        return dict(pairs)

    def no_float(s):
        raise BuildError("non-integer number")

    m = json.loads(data, object_pairs_hook=no_dupes, parse_float=no_float, parse_constant=no_float)
    if m.get("schema") != SCHEMA:
        raise BuildError("unknown schema")
    if not isinstance(m.get("critical"), list):
        raise BuildError("critical missing")
    understood = {"schema", "channel", "release", "sequence", "issued", "expires", "min_sap", "critical", "base", "signing_key", "packages",
                  "removed", "allowed_prefixes", "trust", "components"} | KINDS
    for c in m["critical"]:
        if c not in understood:
            raise BuildError(f"critical {c!r} not understood")
    if m.get("channel") != channel:
        raise BuildError("wrong channel")
    now = now or dt.datetime.now(dt.timezone.utc).replace(tzinfo=None)
    if dt.datetime.strptime(m["expires"], "%Y-%m-%dT%H:%M:%SZ") <= now:
        raise BuildError("expired")
    for e in m["packages"]:
        if e["kind"] not in KINDS:
            continue
        for pin in [e["record"]] + ([e["payload"]] if e.get("payload") else []):
            u = pin["url"]
            if u.startswith("/") or "://" in u or any(x in ("", ".", "..") for x in u.split("/")):
                raise BuildError(f"unsafe URL {u}")
            if sha256_file(chan / u)[0] != pin["sha256"]:
                raise BuildError(f"{u} does not match its pin")
        rec = json.loads((chan / e["record"]["url"]).read_text(), object_pairs_hook=no_dupes)
        if (rec["name"], rec["version"], rec["kind"]) != (e["name"], e["version"], e["kind"]):
            raise BuildError(f"record of {e['name']} disagrees")
        tsv_path = chan / "pool" / rec["files"]["name"]
        if sha256_file(tsv_path)[0] != rec["files"]["sha256"]:
            raise BuildError(f"file list of {e['name']} does not match")
        rows = parse_tsv(tsv_path.read_text())
        if deep and rec.get("payload"):
            raw = lzma.decompress((chan / e["payload"]["url"]).read_bytes(), format=lzma.FORMAT_XZ)
            off = 0
            for r in rows:
                if r["type"] == "f":
                    if sha256_bytes(raw[off:off + r["size"]]) != r["data"]:
                        raise BuildError(f"{r['path']} does not match")
                    off += r["size"]
            if off != len(raw):
                raise BuildError(f"payload of {e['name']} has extra bytes")
    return m


def seed_db(repo, root, channel="stable", allowed_signers=None, now=None):
    """Bootstrap (design 4.3): the image's installed database, for a root built from this channel's files."""
    chan = Path(repo) / "v1" / channel
    m = verify_repo(repo, allowed_signers, channel, now=now) if allowed_signers else json.loads((chan / "manifest.json").read_text())
    root = Path(root)
    db = root / "private/var/db/sap"
    (db / "installed").mkdir(parents=True, exist_ok=True)
    for e in m["packages"]:
        rec = json.loads((chan / e["record"]["url"]).read_text())
        if rec.get("target", "root") != "root":
            continue
        tsv = (chan / "pool" / rec["files"]["name"]).read_text()
        for r in parse_tsv(tsv):
            p = root / r["path"][1:]
            if r["type"] == "f" and (not p.is_file() or sha256_file(p)[0] != r["data"]):
                raise BuildError(f"{r['path']} on the image is not {e['name']}'s")
        entry = {"schema": "sap-installed/1", "name": e["name"], "version": e["version"], "kind": e["kind"], "txn": "image", "record": rec}
        (db / "installed" / f"{e['name']}.json").write_text(json.dumps(entry, indent=2) + "\n")
        (db / "installed" / f"{e['name']}.files.tsv").write_text(tsv)
    state = {"schema": "sap-state/1", "highest_sequence": m["sequence"], "manifest_sha256": None, "held": [],
             "lineage": (m.get("base") or {}).get("sums_sha256"), "anchor_version": 0}
    (db / "state.json").write_text(json.dumps(state, indent=2) + "\n")
    return m


def anchor_token(pubs, version):
    import base64
    keys = []
    for p in pubs:
        line = Path(p).read_text()
        b64 = line.split("ssh-ed25519", 1)[1].split()[0]
        blob = base64.b64decode(b64)
        raw = blob[-32:]
        if blob[:4] != b"\0\0\0\x0b" or len(blob) != 51:
            raise BuildError(f"{p}: not an Ed25519 public key")
        keys.append(base64.b64encode(raw).decode().rstrip("="))
    return f"sf_trust={version}:{','.join(keys)}"


def test_key(d):
    d = Path(d)
    d.mkdir(parents=True, exist_ok=True)
    os.chmod(d, 0o700)
    key = d / "TEST-ONLY-sap-key"
    if key.exists():
        raise BuildError(f"{key} exists")
    subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", "siliconforest-release TEST-ONLY sap-test", "-f", str(key)], check=True)
    (d / "allowed_signers").write_text(f'siliconforest-release namespaces="{NAMESPACE}" {(d / "TEST-ONLY-sap-key.pub").read_text()}')
    return key


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("scan"); s.add_argument("tree"); s.add_argument("--owners-from-stat", action="store_true")
    p = sub.add_parser("publish")
    p.add_argument("--repo", required=True); p.add_argument("--channel", default="stable"); p.add_argument("--release", required=True)
    p.add_argument("--tree"); p.add_argument("--root-tsv"); p.add_argument("--spec"); p.add_argument("--kc-release"); p.add_argument("--boot-bin"); p.add_argument("--boot-bin-b")
    p.add_argument("--boot-version"); p.add_argument("--sequence", type=int); p.add_argument("--allow-same-sequence", action="store_true")
    p.add_argument("--issued"); p.add_argument("--expires-days", type=int, default=30); p.add_argument("--base-sums"); p.add_argument("--base-release")
    p.add_argument("--min-sap"); p.add_argument("--critical", action="append"); p.add_argument("--allowed-prefix", action="append")
    p.add_argument("--trust-keys"); p.add_argument("--trust-version", type=int, default=2); p.add_argument("--bump-changed", action="store_true")
    g = p.add_mutually_exclusive_group(required=True); g.add_argument("--key"); g.add_argument("--unsigned", action="store_true")
    g2 = sub.add_parser("sign"); g2.add_argument("--key", required=True); g2.add_argument("file")
    v = sub.add_parser("verify"); v.add_argument("--repo", required=True); v.add_argument("--allowed-signers", required=True)
    v.add_argument("--channel", default="stable"); v.add_argument("--deep", action="store_true")
    d = sub.add_parser("seed-db"); d.add_argument("--repo", required=True); d.add_argument("--root", required=True)
    d.add_argument("--channel", default="stable"); d.add_argument("--allowed-signers")
    t = sub.add_parser("anchor-token"); t.add_argument("pub", nargs="+"); t.add_argument("--version", type=int, default=1)
    k = sub.add_parser("test-key"); k.add_argument("dir")
    a = ap.parse_args(argv)
    try:
        if a.cmd == "scan":
            sys.stdout.write(render_tsv(scan(a.tree, a.owners_from_stat)))
        elif a.cmd == "publish":
            return publish(a)
        elif a.cmd == "sign":
            print(ssh_sign(a.key, a.file))
        elif a.cmd == "verify":
            m = verify_repo(a.repo, a.allowed_signers, a.channel, a.deep)
            print(f"OK: {a.channel} release {m['release']} sequence {m['sequence']}, {len(m['packages'])} packages")
        elif a.cmd == "seed-db":
            m = seed_db(a.repo, a.root, a.channel, a.allowed_signers)
            print(f"seeded {len(m['packages'])} packages")
        elif a.cmd == "anchor-token":
            print(anchor_token(a.pub, a.version))
        elif a.cmd == "test-key":
            print(test_key(a.dir))
    except (BuildError, R.ReleaseError, KeyError, ValueError) as e:
        print(f"sap-build: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
