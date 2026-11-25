# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Shared fixtures for SAP's end-to-end tests: build the client, make TEST-ONLY keys, publish channels into
temp directories, and fake roots/boot partitions. Nothing here touches a real root, disk or key."""

import gzip
import hashlib
import http.server
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import threading
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
SAP = HERE.parent
REPO = SAP.parent
sys.path.insert(0, str(SAP / "tools"))
sys.path.insert(0, str(REPO / "installer" / "payload" / "release"))
import sap_build as SB  # noqa: E402
import kc_release as KC  # noqa: E402

_BIN = None


def binaries():
    """(sap, sf) built with the `testing` feature (SAP_FAULT, SAP_NOW, SAP_ALLOW_NONROOT, SAP_LAUNCHCTL)."""
    global _BIN
    if _BIN:
        return _BIN
    if os.environ.get("SAP_BIN"):
        b = Path(os.environ["SAP_BIN"])
        _BIN = (b, b.parent / "sf")
        return _BIN
    target = Path(os.environ.get("SAP_TARGET_DIR", SAP / "client" / "target"))
    subprocess.run(["cargo", "build", "--quiet", "--locked", "--features", "testing", "--target-dir", str(target)], cwd=SAP / "client", check=True)
    _BIN = (target / "debug" / "sap", target / "debug" / "sf")
    return _BIN


_SLOT = None
AB = REPO / "integrations/siliconforest/m1-native-boot/install/abboot"


def bootslot():
    """A host build of sf-bootslot (abboot), the A/B boot record tool SAP drives in slots mode."""
    global _SLOT
    if _SLOT:
        return _SLOT
    cc = os.environ.get("CC") or shutil.which("cc") or shutil.which("clang") or shutil.which("gcc")
    out = Path(tempfile.mkdtemp(prefix="sap-bootslot-")) / "sf-bootslot"
    # On Darwin, sf-bootslot.c's _POSIX_C_SOURCE hides the BSD types <sys/sysctl.h> needs (u_int);
    # _DARWIN_C_SOURCE brings them back without touching the abboot sources.
    darwin = ["-D_DARWIN_C_SOURCE"] if sys.platform == "darwin" else []
    subprocess.run([cc, "-std=c11", "-O1", *darwin, "-I", str(AB), str(AB / "sf_ab.c"), str(AB / "sf-bootslot.c"), "-o", str(out)], check=True)
    _SLOT = out
    return out


def slot_status(sfboot, running=None):
    cmd = [str(bootslot()), "--boot", str(sfboot)] + (["--running", running] if running else []) + ["status"]
    p = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return dict(l.split("=", 1) for l in p.stdout.splitlines() if "=" in l)


def slot_tool(sfboot, *args, running=None, check=0):
    cmd = [str(bootslot()), "--boot", str(sfboot)] + (["--running", running] if running else []) + list(args)
    p = subprocess.run(cmd, capture_output=True, text=True)
    assert p.returncode == check, (cmd, p.returncode, p.stdout, p.stderr)
    return p


def sha(b):
    return hashlib.sha256(b).hexdigest()


class Keys:
    def __init__(self, d, name="k"):
        self.dir = Path(d) / name
        self.key = SB.test_key(self.dir)
        self.pub = Path(str(self.key) + ".pub")
        self.signers = self.dir / "allowed_signers"


def snapshot(root, skip=("private/var/db/sap", "private/var/cache/sap", "private/var/lib/sap")):
    """path -> (type, mode, content) of everything under root except SAP's own state."""
    root = Path(root)
    out = {}
    for dirpath, dirnames, filenames in os.walk(root):
        rel_dir = os.path.relpath(dirpath, root)
        if any(rel_dir == s or rel_dir.startswith(s + "/") for s in skip):
            dirnames[:] = []
            continue
        for n in dirnames + filenames:
            p = Path(dirpath) / n
            rel = os.path.relpath(p, root)
            if any(rel == s or rel.startswith(s + "/") for s in skip):
                continue
            st = os.lstat(p)
            if os.path.islink(p):
                out[rel] = ("l", os.readlink(p))
            elif os.path.isdir(p):
                out[rel] = ("d", st.st_mode & 0o7777)
            else:
                out[rel] = ("f", st.st_mode & 0o7777, sha(p.read_bytes()))
    return out


# ---- PDSF (installer/mac/Sources/SFEngine/Engine/KernelCollection.swift) ----

def _rec(kind, data, raw, flags):
    h = struct.pack("<IHHIIQQ", 0x46534450, 1, kind, flags, zlib.crc32(data) & 0xffffffff, len(data), raw)
    r = h + data
    return r + bytes((16 - len(r) % 16) % 16)


def kernel_bin(bootargs, collection):
    cfg = f"bootargs={bootargs}\n".encode()
    return _rec(1, cfg, len(cfg), 0) + _rec(2, gzip.compress(collection, mtime=0), len(collection), 1) + struct.pack("<IHHIIQQ", 0x46534450, 1, 0, 0, 0, 0, 0)


def read_kernel_bin(b):
    out, o = {}, 0
    while o + 32 <= len(b):
        magic, ver, kind, flags, crc, size, raw = struct.unpack_from("<IHHIIQQ", b, o)
        assert magic == 0x46534450
        if kind == 0:
            return out
        body = b[o + 32:o + 32 + size]
        assert zlib.crc32(body) & 0xffffffff == crc
        out[kind] = gzip.decompress(body) if flags & 1 else body
        o += 32 + size
        o += (16 - o % 16) % 16
    raise AssertionError("no END")


# ---- synthetic kernel-collection release (rehearsal stand-in linker, no Apple parts) ----

def kc_release(d, inputs=None, mutate=None):
    """A release directory with install.json's kernel_collection and the kc artifacts, as make_release
    lays them out, linked with release/rehearsal_kc_builder.py. Returns (dir, collection bytes)."""
    d = Path(d)
    d.mkdir(parents=True)
    src = Path(inputs) if inputs else Path(tempfile.mkdtemp()) / "inputs"
    if not inputs:
        KC_TOOL = REPO / "installer/payload/release/rehearsal_kc_builder.py"
        subprocess.run([sys.executable, str(KC_TOOL), "--synthetic", str(src)], check=True, capture_output=True)
    if mutate:
        mutate(src)
    arts = []

    def add(p, role):
        h, n = SB.sha256_file(p)
        arts.append({"name": Path(p).name, "role": role, "sha256": h, "bytes": n})

    kc = KC.stage(src, d, add)
    tool = d / "kc-builder"
    shutil.copyfile(REPO / "installer/payload/release/rehearsal_kc_builder.py", tool)
    os.chmod(tool, 0o755)
    add(tool, "kc-tool")
    (d / "bootargs.template").write_text("rd=uuid boot-uuid=@SF_FSUUID@ sfnvme_part=@SF_PARTUUID@ sfnvme_part_lba=@SF_PART_LBA@\n")
    add(d / "bootargs.template", "bootargs")
    out = Path(tempfile.mkdtemp()) / "collection"
    h, n = KC.link_reference(src, tool, out)
    kc["tool"] = {"artifact": "kc-builder", "signing": "rehearsal-stand-in"}
    kc["collection_sha256"], kc["collection_bytes"] = h, n
    (d / "install.json").write_text(json.dumps({"format": "siliconforest-install/3", "artifacts": arts, "kernel_collection": kc, "boot": {"bootargs": "bootargs.template"}}, indent=1))
    return d, out.read_bytes(), src


# ---- serving a channel over HTTP, logging requests ----

class Server:
    def __init__(self, root):
        self.log = []
        log = self.log

        class H(http.server.SimpleHTTPRequestHandler):
            def __init__(s, *a, **k):
                super().__init__(*a, directory=str(root), **k)

            def log_message(s, *a):
                pass

            def do_GET(s):
                log.append(s.path)
                return super().do_GET()

        self.httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
        self.port = self.httpd.server_address[1]
        self.t = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.t.start()

    def url(self, channel="stable"):
        return f"http://127.0.0.1:{self.port}/v1/{channel}/manifest.json"

    def close(self):
        self.httpd.shutdown()
        self.httpd.server_close()


def resign(repo, key, edit_manifest=None, channel="stable"):
    """Re-sign a channel after a test edited it; edit_manifest(m) may change the manifest dict first."""
    chan = Path(repo) / "v1" / channel
    m = json.loads((chan / "manifest.json").read_text())
    if edit_manifest:
        edit_manifest(m)
    (chan / "manifest.json").write_text(json.dumps(m, indent=2) + "\n")
    SB.ssh_sign(key, chan / "manifest.json")


def repin(repo, name, edit_rows=None, edit_record=None, channel="stable", body_for=None):
    """Rewrite one package in place (file list, record, payload) and fix every pin above it; the caller
    re-signs. Used to build malicious-but-validly-pinned packages that only the client's checks catch."""
    chan = Path(repo) / "v1" / channel
    m = json.loads((chan / "manifest.json").read_text())
    e = next(x for x in m["packages"] if x["name"] == name)
    rec_path = chan / e["record"]["url"]
    rec = json.loads(rec_path.read_text())
    rows = SB.parse_tsv((chan / "pool" / rec["files"]["name"]).read_text())
    bodies = {}
    if rec.get("payload"):
        import lzma
        raw = lzma.decompress((chan / e["payload"]["url"]).read_bytes())
        off = 0
        for r in rows:
            if r["type"] == "f":
                bodies[r["path"]] = raw[off:off + r["size"]]
                off += r["size"]
    if edit_rows:
        rows = edit_rows(rows, bodies)
    tsv = SB.render_tsv(rows).encode()
    stem = f"{name}_{e['version']}_t{sha(tsv)[:8]}"
    (chan / "pool" / f"{stem}.files.tsv").write_bytes(tsv)
    rec["files"] = {"name": f"{stem}.files.tsv", "count": len(rows), "bytes": sum(r["size"] for r in rows if r["type"] == "f"), "sha256": sha(tsv)}
    if any(r["type"] == "f" for r in rows):
        raw = b"".join(bodies[r["path"]] for r in rows if r["type"] == "f")
        body = SB.xz(raw)
        (chan / "pool" / f"{stem}.sappkg").write_bytes(body)
        rec["payload"] = {"name": f"{stem}.sappkg", "format": SB.PAYLOAD_FORMAT, "bytes": len(body), "sha256": sha(body)}
        e["payload"] = {"url": f"pool/{stem}.sappkg", "sha256": sha(body)}
    if edit_record:
        edit_record(rec)
    rb = (json.dumps(rec, indent=2) + "\n").encode()
    (chan / "pool" / f"{stem}.record.json").write_bytes(rb)
    e["record"] = {"url": f"pool/{stem}.record.json", "sha256": sha(rb)}
    e["depends"] = rec["depends"]
    (chan / "manifest.json").write_text(json.dumps(m, indent=2) + "\n")
