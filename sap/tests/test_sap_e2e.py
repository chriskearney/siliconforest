# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""End-to-end tests of SAP: publish channels with sap_build.py into temp directories, install into fake
roots (temp directories only), upgrade, and attack every check. TEST-ONLY keys made here; never the
release key; never a real root or disk.

    python3 -m unittest discover -s sap/tests -v
"""

import contextlib
import io
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import saptest as T

SB = T.SB


def write(p, data, mode=0o644):
    p = Path(p)
    p.parent.mkdir(parents=True, exist_ok=True)
    if p.exists() or p.is_symlink():
        p.unlink()
    p.write_bytes(data if isinstance(data, bytes) else data.encode())
    os.chmod(p, mode)


SPEC = {
    "base": {"name": "sf-base"},
    "packages": [
        {"name": "vim", "version": "9.1.0-1", "summary": "Vi IMproved",
         "paths": ["/usr/bin/vim", "/usr/bin/vi", "/usr/share/vim/**", "/private/etc/vimrc"],
         "config_files": ["/private/etc/vimrc"], "depends": ["libncurses >= 6.4"],
         "services": [{"label": "org.siliconforest.vimd", "activate": "restart"}]},
        {"name": "libncurses", "version": "6.4-1", "paths": ["/usr/lib/libncurses*"]},
        {"name": "sap", "version": "1.0.0-1", "paths": ["/usr/bin/sap"]},
    ],
}


def spec(**changes):
    s = json.loads(json.dumps(SPEC))
    for name, ch in changes.items():
        p = next(x for x in s["packages"] if x["name"] == name.replace("_", "-"))
        p.update(ch)
    return s


def tree_v1(d):
    d = Path(d)
    write(d / "usr/bin/vim", b"vim 9.1.0 binary\n" * 100, 0o755)
    os.symlink("vim", d / "usr/bin/vi")
    write(d / "usr/share/vim/vim91/doc/help.txt", "help v1\n")
    write(d / "usr/share/vim/vim91/syntax/c.vim", "syntax c\n")
    write(d / "private/etc/vimrc", "set nocompatible\n")
    write(d / "usr/lib/libncurses.6.dylib", b"ncurses 6.4\n" * 50, 0o755)
    write(d / "usr/bin/sap", "#!/bin/sh\necho fake sap 1\n", 0o755)
    write(d / "usr/bin/ls", b"ls binary\n" * 30, 0o755)
    write(d / "System/Library/LaunchDaemons/org.siliconforest.firstboot.plist", "<plist/>\n")
    write(d / "private/var/db/sf-boot-receipt", bytes(64))
    os.symlink("private/var", d / "var")
    return d


def tree_v2(d):
    d = tree_v1(d)
    write(d / "usr/share/vim/vim91/doc/help.txt", "help v2, longer\n")
    write(d / "usr/share/vim/vim91/doc/new.txt", "new in v2\n")
    (d / "usr/share/vim/vim91/syntax/c.vim").unlink()
    write(d / "private/etc/vimrc", "set nocompatible\nsyntax on\n")
    write(d / "usr/bin/vim", b"vim 9.1.1 binary\n" * 100, 0o755)
    return d


V2 = spec(vim={"version": "9.1.1-1"})


class Env:
    """A temp workspace: keys, a repo, a fake root and a fake SFBOOT."""

    def __init__(self, tc):
        self.tc = tc
        self.d = Path(tempfile.mkdtemp(prefix="sap-e2e-"))
        tc.addCleanup(shutil.rmtree, self.d, True)
        self.keys = T.Keys(self.d)
        self.repo = self.d / "repo"
        self.root = self.d / "root"
        self.root.mkdir()
        self.sfboot = self.d / "sfboot"
        (self.sfboot / "sf").mkdir(parents=True)
        self.sap, self.sf = T.binaries()
        self.url = f"file://{self.repo}/v1/stable/manifest.json"
        self.launch_log = self.d / "launchctl.log"
        lc = self.d / "launchctl"
        lc.write_text(f"#!/bin/sh\necho \"$@\" >> {self.launch_log}\n")
        os.chmod(lc, 0o755)
        self.env = {**os.environ, "SAP_ALLOW_NONROOT": "1", "SAP_LAUNCHCTL": str(lc)}
        self.n = 0

    def publish(self, release, tree=None, spec=SPEC, key=None, extra=(), kc=None, boot=None):
        args = ["publish", "--repo", str(self.repo), "--release", release]
        if tree:
            self.n += 1
            sp = self.d / f"spec-{self.n}.json"
            sp.write_text(json.dumps(spec))
            args += ["--tree", str(tree), "--spec", str(sp)]
        if kc:
            args += ["--kc-release", str(kc)]
        if boot:
            args += ["--boot-bin", str(boot)]
        args += ["--key", str(key or self.keys.key), *extra]
        with contextlib.redirect_stdout(io.StringIO()):
            rc = SB.main(args)
        self.tc.assertEqual(rc, 0)

    def tree(self, fn):
        self.n += 1
        return fn(self.d / f"tree-{self.n}")

    def run(self, *args, env=None, url=None, anchor=True, check=None):
        cmd = [str(self.sap), "--root", str(self.root), "--sfboot", str(self.sfboot), "--manifest-url", url or self.url]
        if anchor:
            cmd += ["--trust-anchor", str(self.keys.signers if anchor is True else anchor)]
        p = subprocess.run(cmd + list(args), capture_output=True, text=True, env={**self.env, **(env or {})})
        if check is not None:
            self.tc.assertEqual(p.returncode, check, f"sap {' '.join(args)}\n--stdout--\n{p.stdout}\n--stderr--\n{p.stderr}")
        return p

    def chan(self):
        return self.repo / "v1" / "stable"

    def history(self):
        return json.loads(self.run("--json", "history", check=0).stdout)


class Basics(unittest.TestCase):
    def test_install_upgrade_only_changed_rollback(self):
        e = Env(self)
        e.publish("0.1.0", e.tree(tree_v1))
        SB.verify_repo(e.repo, e.keys.signers, deep=True)
        e.run("install", "--all", check=0)
        self.assertEqual(os.readlink(e.root / "usr/bin/vi"), "vim")
        self.assertEqual((e.root / "private/etc/vimrc").read_text(), "set nocompatible\n")
        self.assertFalse((e.root / "private/var/db/sf-boot-receipt").exists(), "protected paths are never shipped")
        self.assertEqual(os.stat(e.root / "usr/bin/vim").st_mode & 0o777, 0o755)
        e.run("verify", check=0)
        e.run("check", check=0)
        v1 = T.snapshot(e.root)
        e.publish("0.1.1", e.tree(tree_v2), spec=V2)
        e.run("check", check=10)
        srv = T.Server(e.repo)
        self.addCleanup(srv.close)
        e.run("upgrade", url=srv.url(), check=0)
        fetched = [x for x in srv.log if x.endswith(".sappkg")]
        self.assertEqual(len(fetched), 1, srv.log)
        self.assertIn("/vim_", fetched[0])
        self.assertFalse(any("libncurses" in x or "sf-base" in x for x in srv.log), srv.log)
        self.assertEqual((e.root / "usr/share/vim/vim91/doc/help.txt").read_text(), "help v2, longer\n")
        self.assertFalse((e.root / "usr/share/vim/vim91/syntax/c.vim").exists())
        self.assertEqual((e.root / "private/etc/vimrc").read_text(), "set nocompatible\nsyntax on\n")
        e.run("verify", check=0)
        self.assertIn("org.siliconforest.vimd", e.launch_log.read_text())
        e.run("list", check=0)
        e.run("show", "vim", check=0)
        # Rollback restores exactly the v1 tree, and the database agrees with it.
        e.run("rollback", check=0)
        self.assertEqual(T.snapshot(e.root), v1)
        e.run("verify", check=0)
        self.assertEqual([h["kind"] for h in e.history()][-1], "rollback")
        up = json.loads(e.run("--json", "list", "--upgradable", check=0).stdout)
        self.assertEqual([x["name"] for x in up], ["vim"])

    def test_sf_dispatch(self):
        sap, sf = T.binaries()
        p = subprocess.run([str(sf), "sap", "version"], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertTrue(p.stdout.startswith("sap "))

    def test_config_file_kept_when_edited(self):
        e = Env(self)
        e.publish("0.1.0", e.tree(tree_v1))
        e.run("install", "--all", check=0)
        write(e.root / "private/etc/vimrc", "my own settings\n")
        e.publish("0.1.1", e.tree(tree_v2), spec=V2)
        e.run("upgrade", check=0)
        self.assertEqual((e.root / "private/etc/vimrc").read_text(), "my own settings\n")
        self.assertEqual((e.root / "private/etc/vimrc.sap-new").read_text(), "set nocompatible\nsyntax on\n")

    def test_verify_and_repair(self):
        e = Env(self)
        e.publish("0.1.0", e.tree(tree_v1))
        e.run("install", "--all", check=0)
        write(e.root / "usr/bin/ls", "tampered", 0o755)
        os.chmod(e.root / "usr/bin/vim", 0o777)
        p = e.run("verify", check=20)
        self.assertIn("/usr/bin/ls", p.stdout)
        self.assertIn("/usr/bin/vim", p.stdout)
        e.run("verify", "--repair", check=0)
        e.run("verify", check=0)
        self.assertEqual((e.root / "usr/bin/ls").read_bytes(), b"ls binary\n" * 30)

    def test_holds(self):
        e = Env(self)
        e.publish("0.1.0", e.tree(tree_v1))
        e.run("install", "--all", check=0)
        e.run("hold", "vim", check=0)
        e.publish("0.1.1", e.tree(tree_v2), spec=V2)
        before = T.snapshot(e.root)
        e.run("upgrade", check=0)
        self.assertEqual(T.snapshot(e.root), before)
        e.run("upgrade", "vim", check=30)
        e.run("unhold", "vim", check=0)
        e.run("upgrade", check=0)
        self.assertEqual((e.root / "usr/share/vim/vim91/doc/help.txt").read_text(), "help v2, longer\n")

    def test_dry_run_download_only_offline(self):
        e = Env(self)
        e.publish("0.1.0", e.tree(tree_v1))
        e.run("install", "--all", check=0)
        e.publish("0.1.1", e.tree(tree_v2), spec=V2)
        before = T.snapshot(e.root)
        e.run("upgrade", "--dry-run", check=0)
        e.run("upgrade", "--download-only", check=0)
        self.assertEqual(T.snapshot(e.root), before)
        shutil.rmtree(e.repo)
        e.run("--offline", "upgrade", check=0)
        self.assertEqual((e.root / "usr/share/vim/vim91/doc/new.txt").read_text(), "new in v2\n")

    def test_seed_db_bootstrap(self):
        """An image built from the channel's files gets its database from seed-db and is then clean."""
        e = Env(self)
        t = e.tree(tree_v1)
        e.publish("0.1.0", t)
        shutil.rmtree(e.root)
        shutil.copytree(t, e.root, symlinks=True)
        SB.seed_db(e.repo, e.root, allowed_signers=e.keys.signers)
        e.run("verify", check=0)
        e.run("check", check=0)
        e.publish("0.1.1", e.tree(tree_v2), spec=V2)
        e.run("upgrade", check=0)
        e.run("verify", check=0)

    def test_publisher_keeps_unchanged_versions(self):
        e = Env(self)
        e.publish("0.1.0", e.tree(tree_v1))
        v1 = {p["name"]: p["version"] for p in json.loads((e.chan() / "manifest.json").read_text())["packages"]}
        t = e.tree(tree_v1)
        write(t / "usr/bin/ls", b"ls v2\n", 0o755)
        e.publish("0.1.1", t)
        m = json.loads((e.chan() / "manifest.json").read_text())
        v2 = {p["name"]: p["version"] for p in m["packages"]}
        self.assertEqual({k for k in v1 if v1[k] != v2[k]}, {"sf-base"})
        self.assertEqual(m["sequence"], 2)
        # An explicit version kept while content changed is refused.
        t = e.tree(tree_v2)
        sp = e.d / "spec-explicit.json"
        sp.write_text(json.dumps(SPEC))  # vim stays 9.1.0-1 although its files changed
        a = ["publish", "--repo", str(e.repo), "--release", "0.1.2", "--tree", str(t), "--spec", str(sp), "--key", str(e.keys.key)]
        self.assertEqual(SB.main(a), 1)


class Trust(unittest.TestCase):
    def setUp(self):
        self.e = Env(self)
        self.e.publish("0.1.0", self.e.tree(tree_v1))
        self.e.run("install", "--all", check=0)
        self.before = T.snapshot(self.e.root)

    def unchanged(self):
        self.assertEqual(T.snapshot(self.e.root), self.before)

    def both_reject(self, code):
        """The Rust client and the Python reference verifier agree (design 9.3, differential)."""
        e = self.e
        p = e.run("upgrade", check=code)
        with self.assertRaises(Exception):
            SB.verify_repo(e.repo, e.keys.signers, deep=True)
        self.unchanged()
        return p

    def v2(self, **kw):
        self.e.publish("0.1.1", self.e.tree(tree_v2), spec=V2, **kw)

    def test_bad_signature(self):
        e = self.e
        self.v2()
        mp = e.chan() / "manifest.json"
        mp.write_text(mp.read_text().replace('"release": "0.1.1"', '"release": "0.1.2"'))
        self.both_reject(20)

    def test_wrong_key(self):
        other = T.Keys(self.e.d, "other")
        self.v2(key=other.key)
        self.both_reject(20)

    def test_wrong_namespace(self):
        e = self.e
        self.v2()
        mp = e.chan() / "manifest.json"
        (e.chan() / "manifest.json.sig").unlink()
        subprocess.run(["ssh-keygen", "-q", "-Y", "sign", "-n", "file", "-f", str(e.keys.key), str(mp)], check=True, stdin=subprocess.DEVNULL)
        self.both_reject(20)

    def test_missing_signature(self):
        self.v2()
        (self.e.chan() / "manifest.json.sig").unlink()
        self.both_reject(20)

    def test_sums_file_is_not_a_manifest(self):
        e = self.e
        mp = e.chan() / "manifest.json"
        mp.write_text("0" * 64 + "  install.json\n")
        SB.ssh_sign(e.keys.key, mp)
        self.both_reject(20)

    def test_expired(self):
        p = None
        self.v2(extra=["--issued", "2026-01-01T00:00:00Z", "--expires-days", "2"])
        p = self.both_reject(21)
        self.assertIn("expired", p.stderr)

    def test_expired_by_clock(self):
        self.v2()
        self.e.run("upgrade", env={"SAP_NOW": "2099-01-01T00:00:00Z"}, check=21)
        self.unchanged()

    def test_sequence_replay(self):
        e = self.e
        saved = {n: (e.chan() / n).read_bytes() for n in ("manifest.json", "manifest.json.sig")}
        self.v2()
        e.run("check", check=10)
        for n, b in saved.items():
            (e.chan() / n).write_bytes(b)
        e.run("upgrade", check=21)
        e.run("check", check=21)
        self.unchanged()

    def test_same_sequence_other_content(self):
        e = self.e
        e.run("check", check=0)
        T.resign(e.repo, e.keys.key, lambda m: m.update({"release": "forked"}))
        e.run("check", check=21)

    def test_unknown_critical(self):
        self.v2(extra=["--critical", "rollout-v9"])
        p = self.both_reject(20)
        self.assertIn("update SAP first", p.stderr)

    def test_wrong_schema(self):
        self.v2()
        T.resign(self.e.repo, self.e.keys.key, lambda m: m.update({"schema": "siliconforest-update/2"}))
        self.both_reject(20)

    def test_unknown_fields_ignored(self):
        e = self.e
        self.v2()

        def ed(m):
            m.update({"x-future": {"a": [1, 2]}, "rollout": {"percent": 10}})
            m["packages"][0]["x-delta"] = [{"from": "x"}]
        T.resign(e.repo, e.keys.key, ed)
        e.run("upgrade", check=0)
        SB.verify_repo(e.repo, e.keys.signers, deep=True)

    def test_duplicate_keys(self):
        e = self.e
        self.v2()
        mp = e.chan() / "manifest.json"
        mp.write_text(mp.read_text().replace('"release": "0.1.1"', '"release": "0.1.1", "release": "9"'))
        SB.ssh_sign(e.keys.key, mp)
        self.both_reject(20)

    def test_float(self):
        e = self.e
        self.v2()
        mp = e.chan() / "manifest.json"
        mp.write_text(mp.read_text().replace('"release": "0.1.1"', '"release": "0.1.1", "x": 1.5'))
        SB.ssh_sign(e.keys.key, mp)
        self.both_reject(20)

    def test_payload_hash_mismatch(self):
        e = self.e
        self.v2()
        m = json.loads((e.chan() / "manifest.json").read_text())
        pkg = e.chan() / next(x for x in m["packages"] if x["name"] == "vim")["payload"]["url"]
        data = bytearray(pkg.read_bytes())
        data[len(data) // 2] ^= 0x40
        pkg.write_bytes(bytes(data))
        self.both_reject(20)
        self.assertFalse(list((e.root / "private/var/cache/sap").rglob("*.part")))

    def test_file_hash_mismatch_inside_valid_payload(self):
        e = self.e
        self.v2()

        def evil(rows, bodies):
            bodies["/usr/bin/vim"] = b"evil" + bodies["/usr/bin/vim"][4:]
            return rows
        T.repin(e.repo, "vim", edit_rows=evil)
        T.resign(e.repo, e.keys.key)
        p = self.both_reject(20)
        self.assertIn("/usr/bin/vim", p.stderr)

    def check_injected(self, rows_to_add, bodies_to_add, code=30):
        e = self.e
        self.v2()

        def add(rows, bodies):
            bodies.update(bodies_to_add)
            return sorted(rows + rows_to_add, key=lambda r: r["path"])
        T.repin(e.repo, "vim", edit_rows=add)
        T.resign(e.repo, e.keys.key)
        p = e.run("upgrade")
        self.assertIn(p.returncode, (20, 30), p.stderr)
        self.unchanged()
        return p

    def frow(self, path, body=b"x"):
        return {"path": path, "type": "f", "mode": 0o644, "uid": 0, "gid": 0, "size": len(body), "data": T.sha(body)}

    def test_protected_path(self):
        self.check_injected([self.frow("/private/var/db/sf-boot-receipt")], {"/private/var/db/sf-boot-receipt": b"x"})

    def test_sap_state_path(self):
        self.check_injected([self.frow("/private/var/db/sap/state.json")], {"/private/var/db/sap/state.json": b"x"})

    def test_dev_path(self):
        self.check_injected([self.frow("/dev/disk0")], {"/dev/disk0": b"x"})

    def test_symlink_escape(self):
        link = {"path": "/usr/share/vim/out", "type": "l", "mode": 0o777, "uid": 0, "gid": 0, "size": 5, "data": "../.."}
        self.check_injected([link, self.frow("/usr/share/vim/out/x")], {"/usr/share/vim/out/x": b"x"})
        self.assertFalse((self.e.d / "x").exists())
        self.assertFalse((self.e.root / "usr/x").exists())

    def test_through_existing_symlink(self):
        # /var -> private/var exists in the root; a file under /var/... must land inside the root.
        e = self.e
        os.symlink("/tmp", e.root / "usr/share/vim/tmplink")
        self.before = T.snapshot(e.root)
        self.check_injected([self.frow("/usr/share/vim/tmplink/sap-escape-test")], {"/usr/share/vim/tmplink/sap-escape-test": b"x"})
        self.assertFalse(Path("/tmp/sap-escape-test").exists())


class Ownership(unittest.TestCase):
    def test_conflicts_and_adopt(self):
        e = Env(self)
        e.publish("0.1.0", e.tree(tree_v1))
        e.run("install", "--all", check=0)
        before = T.snapshot(e.root)
        sp = json.loads(json.dumps(SPEC))
        sp["packages"].append({"name": "vim-extra", "version": "1-1", "paths": ["/usr/share/vim-extra/**"]})
        t2 = e.tree(tree_v1)
        write(t2 / "usr/share/vim-extra/a.txt", "a\n")
        e.publish("0.1.1", t2, spec=sp)
        saved = e.d / "repo-good"
        shutil.copytree(e.repo, saved)

        def steal(rows, bodies):
            bodies["/usr/bin/vim"] = b"vim"
            return sorted(rows + [{"path": "/usr/bin/vim", "type": "f", "mode": 0o755, "uid": 0, "gid": 0, "size": 3, "data": T.sha(b"vim")}], key=lambda r: r["path"])
        T.repin(e.repo, "vim-extra", edit_rows=steal)
        T.resign(e.repo, e.keys.key)
        p = e.run("install", "vim-extra", check=30)
        self.assertIn("vim", p.stderr)
        self.assertEqual(T.snapshot(e.root), before)
        # An unowned file already on disk with other content: refused, unless --adopt.
        shutil.rmtree(e.repo)
        shutil.copytree(saved, e.repo)
        T.resign(e.repo, e.keys.key, lambda m: m.update({"sequence": 3}))  # the client saw the tampered sequence 2
        write(e.root / "usr/share/vim-extra/a.txt", "local\n")
        e.run("install", "vim-extra", check=30)
        e.run("install", "vim-extra", "--adopt", "/usr/share/vim-extra/a.txt", check=0)
        self.assertEqual((e.root / "usr/share/vim-extra/a.txt").read_text(), "a\n")
        e.run("verify", check=0)

    def test_dependency_failures(self):
        e = Env(self)
        e.publish("0.1.0", e.tree(tree_v1))
        e.run("install", "--all", check=0)
        before = T.snapshot(e.root)
        e.publish("0.1.1", e.tree(tree_v2), spec=spec(vim={"version": "9.1.1-1", "depends": ["libncurses >= 7"]}))
        p = e.run("upgrade", check=30)
        self.assertIn("libncurses", p.stderr)
        e.publish("0.1.2", e.tree(tree_v2), spec=spec(vim={"version": "9.1.1-2", "conflicts": ["libncurses"]}))
        p = e.run("upgrade", check=30)
        self.assertIn("libncurses", p.stderr)
        self.assertEqual(T.snapshot(e.root), before)
        # A dependency that would move a held package.
        t = e.tree(tree_v2)
        write(t / "usr/lib/libncurses.6.dylib", b"ncurses 6.5\n", 0o755)
        e.publish("0.1.3", t, spec=spec(vim={"version": "9.1.1-3", "depends": ["libncurses >= 6.5"]}, libncurses={"version": "6.5-1"}))
        e.run("hold", "libncurses", check=0)
        e.run("upgrade", "vim", check=30)
        self.assertEqual(T.snapshot(e.root), before)
        e.run("unhold", "libncurses", check=0)
        e.run("upgrade", "vim", check=0)
        self.assertEqual((e.root / "usr/lib/libncurses.6.dylib").read_bytes(), b"ncurses 6.5\n")
        e.run("verify", check=0)

    def test_file_moves_between_packages(self):
        """/usr/bin/ls moves from sf-base to a new package that replaces sf-base."""
        e = Env(self)
        e.publish("0.1.0", e.tree(tree_v1))
        e.run("install", "--all", check=0)
        sp = json.loads(json.dumps(SPEC))
        sp["packages"].append({"name": "coreutils", "version": "9.5-1", "paths": ["/usr/bin/ls"], "replaces": ["sf-base"]})
        e.publish("0.1.1", e.tree(tree_v1), spec=sp)
        e.run("upgrade", check=0)
        e.run("install", "coreutils", check=0)
        e.run("verify", check=0)
        self.assertIn("/usr/bin/ls", e.run("show", "coreutils", check=0).stdout + "/usr/bin/ls")


class Interrupted(unittest.TestCase):
    """Kill the process after every journal record and every filesystem step; recovery must give all-old
    or all-new, verify must be clean, and the machine must still reach v2 (design 9.3)."""

    def test_every_journal_step(self):
        e = Env(self)
        e.publish("0.1.0", e.tree(tree_v1))
        e.run("install", "--all", check=0)
        base = e.d / "base-root"
        shutil.copytree(e.root, base, symlinks=True)
        v1 = T.snapshot(e.root)
        e.publish("0.1.1", e.tree(tree_v2), spec=V2)
        e.run("upgrade", check=0)
        v2 = T.snapshot(e.root)
        seen = {"old": 0, "new": 0}
        for kind in ("rec", "op"):
            for force_back in (False, True):
                n = 1
                while n < 200:
                    shutil.rmtree(e.root)
                    shutil.copytree(base, e.root, symlinks=True)
                    p = e.run("upgrade", env={"SAP_FAULT": f"{kind}:{n}"})
                    if p.returncode == 0:
                        break
                    self.assertIn("SAP_FAULT", p.stderr, f"{kind}:{n}: {p.stderr}")
                    interrupted = "INTERRUPTED" in e.run("history", check=0).stdout
                    if interrupted:
                        e.run("verify", check=40)
                    e.run(*(["recover", "--rollback"] if force_back else ["recover"]), check=0)
                    snap = T.snapshot(e.root)
                    state = "old" if snap == v1 else "new" if snap == v2 else None
                    if state is None:
                        diff = {k for k in set(snap) | set(v1) | set(v2) if snap.get(k) != v1.get(k) and snap.get(k) != v2.get(k)}
                        self.fail(f"{kind}:{n} rollback={force_back} left a mixed tree: {sorted(diff)}")
                    if force_back and interrupted:
                        # Before the done record, --rollback always gives the old tree; after it the
                        # transaction is complete and there is nothing to recover.
                        self.assertEqual(state, "old", f"{kind}:{n}")
                    seen[state] += 1
                    e.run("verify", check=0)
                    e.run("upgrade", check=0)
                    self.assertEqual(T.snapshot(e.root), v2, f"{kind}:{n}")
                    n += 1
                self.assertGreater(n, 3, kind)
        self.assertGreater(seen["old"], 0)
        self.assertGreater(seen["new"], 0)


class KernelCollection(unittest.TestCase):
    ARGS = "rd=uuid boot-uuid=37215ab4-59b9-8afb-ab76-394c5ee48edf sfnvme_part=1C5E06B2-AAAA-4C2B-9C26-0E3B5D7D4F10 sfnvme_part_lba=1234567"

    def setUp(self):
        e = self.e = Env(self)
        self.rel1, coll1, self.inputs = T.kc_release(e.d / "rel1")
        tok = SB.anchor_token([e.keys.pub], 1)
        self.kb1 = T.kernel_bin(f"{self.ARGS} {tok}", coll1)
        (e.sfboot / "sf/kernel.bin").write_bytes(self.kb1)
        (e.d / "boot1.bin").write_bytes(b"stage2 v1\n" * 10)
        self.t1 = e.tree(tree_v1)
        e.publish("0.1.0", self.t1, kc=self.rel1, boot=e.d / "boot1.bin")
        # No --trust-anchor: the anchor comes from the image's sf/kernel.bin (sf_trust=), as at boot.
        e.run("install", "--all", "--boot", anchor=False, check=50)
        self.assertEqual((e.sfboot / "sf/boot.bin").read_bytes(), b"stage2 v1\n" * 10)
        self.assertEqual(T.read_kernel_bin((e.sfboot / "sf/kernel.bin").read_bytes())[2], coll1)
        e.run("verify", anchor=False, check=0)
        self.kb1 = (e.sfboot / "sf/kernel.bin").read_bytes()

    def test_one_kext_changes(self):
        e = self.e

        def change(src):
            f = next(src.glob("kexts/*/Contents/MacOS/*"))
            f.write_bytes(f.read_bytes() + b"v2\n")
            self.changed = f.parent.parent.parent.name
        rel2, coll2, _ = T.kc_release(e.d / "rel2", inputs=None, mutate=change)
        e.publish("0.1.1", self.t1, kc=rel2, boot=e.d / "boot1.bin")
        # Without --boot the kernel update waits.
        p = e.run("upgrade", anchor=False, check=0)
        self.assertIn("--boot", p.stdout + p.stderr)
        self.assertEqual((e.sfboot / "sf/kernel.bin").read_bytes(), self.kb1)
        srv = T.Server(e.repo)
        self.addCleanup(srv.close)
        e.run("upgrade", "--boot", anchor=False, url=srv.url(), check=50)
        fetched = sorted(x.rsplit("/", 1)[1] for x in srv.log if x.endswith(".sappkg"))
        self.assertEqual(len(fetched), 1, srv.log)
        self.assertTrue(fetched[0].startswith(SB.kext_package_name("kexts/" + self.changed) + "_"), fetched)
        recs = T.read_kernel_bin((e.sfboot / "sf/kernel.bin").read_bytes())
        self.assertEqual(recs[2], coll2)
        self.assertIn(self.ARGS, recs[1].decode())
        self.assertIn("sf_trust=1:", recs[1].decode())
        self.assertEqual((e.sfboot / "sf/kernel.bin.old").read_bytes(), self.kb1)
        e.run("verify", anchor=False, check=0)
        e.run("rollback", anchor=False, check=50)
        self.assertEqual((e.sfboot / "sf/kernel.bin").read_bytes(), self.kb1)

    def test_relink_mismatch_refused(self):
        e = self.e

        def change(src):
            f = next(src.glob("kexts/*/Contents/Info.plist"))
            f.write_bytes(f.read_bytes() + b"<!-- v2 -->\n")
        rel2, _, _ = T.kc_release(e.d / "rel2", mutate=change)
        e.publish("0.1.1", self.t1, kc=rel2, boot=e.d / "boot1.bin")
        T.repin(e.repo, "sf-kernel-collection", edit_record=lambda r: r["kernel_collection"].update({"collection_sha256": "ab" * 32}))
        T.resign(e.repo, e.keys.key)
        before = T.snapshot(e.root)
        p = e.run("upgrade", "--boot", anchor=False, check=20)
        self.assertIn("collection", p.stderr)
        self.assertEqual(T.snapshot(e.root), before)
        self.assertEqual((e.sfboot / "sf/kernel.bin").read_bytes(), self.kb1)

    def test_trust_rotation(self):
        e = self.e
        new = T.Keys(e.d, "newkey")
        both = e.d / "both.pub"
        both.write_text(e.keys.pub.read_text() + new.pub.read_text())
        e.publish("0.1.1", self.t1, kc=self.rel1, boot=e.d / "boot1.bin", extra=["--trust-keys", str(both), "--trust-version", "2"])
        e.run("upgrade", "--boot", anchor=False, check=50)
        args = T.read_kernel_bin((e.sfboot / "sf/kernel.bin").read_bytes())[1].decode()
        self.assertIn("sf_trust=2:", args)
        self.assertIn(self.ARGS, args)
        # The next manifest, signed by the new key alone, is accepted through the rotated anchor.
        e.publish("0.1.2", e.tree(tree_v2), spec=V2, key=new.key, kc=self.rel1, boot=e.d / "boot1.bin")
        e.run("upgrade", anchor=False, check=0)
        # A key outside the anchor still fails.
        rogue = T.Keys(e.d, "rogue")
        e.publish("0.1.3", e.tree(tree_v2), spec=V2, key=rogue.key, kc=self.rel1, boot=e.d / "boot1.bin")
        e.run("check", anchor=False, check=20)

    def test_stage2_update(self):
        e = self.e
        (e.d / "boot2.bin").write_bytes(b"stage2 v2\n" * 12)
        e.publish("0.1.1", self.t1, kc=self.rel1, boot=e.d / "boot2.bin")
        e.run("upgrade", anchor=False, check=0)
        self.assertEqual((e.sfboot / "sf/boot.bin").read_bytes(), b"stage2 v1\n" * 10)
        e.run("upgrade", "--boot", anchor=False, check=50)
        self.assertEqual((e.sfboot / "sf/boot.bin").read_bytes(), b"stage2 v2\n" * 12)
        self.assertEqual((e.sfboot / "sf/boot.bin.old").read_bytes(), b"stage2 v1\n" * 10)
        e.run("verify", anchor=False, check=0)


class Slots(unittest.TestCase):
    """A/B try-once boot (design 10): SAP stages into the slot that is not the default through
    sf-bootslot (begin-stage, write, arm) and never writes the default slot."""

    ARGS = KernelCollection.ARGS
    A1, B1 = b"stage2 A v1\n" * 10, b"stage2 B v1\n" * 10

    def setUp(self):
        e = self.e = Env(self)
        e.env["SAP_BOOTSLOT_TOOL"] = str(T.bootslot())
        self.rel1, self.coll1, _ = T.kc_release(e.d / "rel1")
        tok = SB.anchor_token([e.keys.pub], 1)
        (e.sfboot / "sf/kernel.bin").write_bytes(T.kernel_bin(f"{self.ARGS} {tok}", self.coll1))
        self.bins = {}
        self.t1 = e.tree(tree_v1)
        e.publish("0.1.0", self.t1, kc=self.rel1, boot=self.bin("a1", self.A1), extra=["--boot-bin-b", str(self.bin("b1", self.B1))])
        # Installed with stage 1 v1 (no record): the legacy layout, slot B never written.
        e.run("install", "--all", "--boot", anchor=False, check=50)
        self.assertFalse((e.sfboot / "sf/b").exists())
        e.run("verify", anchor=False, check=0)
        # Stage 1 v2 goes on; the installer or first start runs init.
        T.slot_tool(e.sfboot, "init")
        self.default_a = self.slot_a()
        e.run("verify", anchor=False, check=0)

    def bin(self, name, data):
        p = self.e.d / f"{name}.bin"
        p.write_bytes(data)
        return p

    def slot_a(self):
        sf = self.e.sfboot / "sf"
        return (sf / "boot.bin").read_bytes(), (sf / "kernel.bin").read_bytes()

    def kext_release(self, name, marker):
        def change(src):
            f = next(src.glob("kexts/*/Contents/MacOS/*"))
            f.write_bytes(f.read_bytes() + marker)
        return T.kc_release(self.e.d / name, mutate=change)

    def test_update_confirmed_then_next_goes_to_a(self):
        e = self.e
        rel2, coll2, _ = self.kext_release("rel2", b"v2\n")
        e.publish("0.1.1", self.t1, kc=rel2, boot=self.bin("a1", self.A1), extra=["--boot-bin-b", str(self.bin("b1", self.B1))])
        p = e.run("upgrade", "--boot", anchor=False, check=50)
        self.assertIn("staged slot b", p.stdout)
        self.assertEqual(self.slot_a(), self.default_a, "the default slot is never written")
        self.assertFalse(list((e.sfboot / "sf").glob("*.old")))
        b = T.read_kernel_bin((e.sfboot / "sf/b/kernel.bin").read_bytes())
        self.assertEqual(b[2], coll2)
        args = b[1].decode()
        self.assertIn(self.ARGS, args)
        self.assertIn("sf_slot=b", args)
        self.assertIn("sf_trust=1:", args)
        self.assertEqual((e.sfboot / "sf/b/boot.bin").read_bytes(), self.B1)
        st = T.slot_status(e.sfboot)
        self.assertEqual((st["default"], st["trial"], st["trial_state"]), ("a", "b", "armed"))
        self.assertEqual(st["slot_b"].split()[-1], "file:matches")
        self.assertEqual(st["slot_b"].split()[2], "generation:2")
        e.run("verify", anchor=False, check=0)
        self.assertIn("trial_state=armed", e.run("boot-status", anchor=False, check=0).stdout)
        # Nothing else is staged while a trial waits.
        rel3, _, _ = self.kext_release("rel3", b"v3\n")
        e.publish("0.1.2", self.t1, kc=rel3, boot=self.bin("a1", self.A1), extra=["--boot-bin-b", str(self.bin("b1", self.B1))])
        p = e.run("upgrade", "--boot", anchor=False, check=30)
        self.assertIn("waiting in slot b", p.stderr)
        # The machine starts B once, comes up clean, and marks it good (the OS side of design 10.4).
        T.slot_tool(e.sfboot, "early", running="b")
        T.slot_tool(e.sfboot, "mark-good", running="b")
        st = T.slot_status(e.sfboot)
        self.assertEqual((st["default"], st["trial_state"]), ("b", "none"))
        # The next update goes into A, from B's kernel, and A's kernel names no slot.
        e.run("upgrade", "--boot", anchor=False, check=50)
        self.assertEqual((e.sfboot / "sf/b/boot.bin").read_bytes(), self.B1)
        a = T.read_kernel_bin((e.sfboot / "sf/kernel.bin").read_bytes())
        self.assertNotIn("sf_slot", a[1].decode())
        self.assertIn(self.ARGS, a[1].decode())
        self.assertEqual((e.sfboot / "sf/boot.bin").read_bytes(), self.A1)
        st = T.slot_status(e.sfboot)
        self.assertEqual((st["default"], st["trial"], st["trial_state"]), ("b", "a", "armed"))
        e.run("verify", anchor=False, check=0)

    def test_stage2_only_update(self):
        e = self.e
        A2, B2 = b"stage2 A v2\n" * 11, b"stage2 B v2\n" * 11
        e.publish("0.1.1", self.t1, kc=self.rel1, boot=self.bin("a2", A2), extra=["--boot-bin-b", str(self.bin("b2", B2))])
        e.run("upgrade", "--boot", anchor=False, check=50)
        self.assertEqual(self.slot_a(), self.default_a)
        self.assertEqual((e.sfboot / "sf/b/boot.bin").read_bytes(), B2)
        kb = T.read_kernel_bin((e.sfboot / "sf/b/kernel.bin").read_bytes())
        self.assertEqual(kb[2], self.coll1)
        self.assertIn("sf_slot=b", kb[1].decode())
        e.run("verify", anchor=False, check=0)

    def test_never_confirmed_falls_back_and_restages(self):
        e = self.e
        rel2, _, _ = self.kext_release("rel2", b"v2\n")
        e.publish("0.1.1", self.t1, kc=rel2, boot=self.bin("a1", self.A1), extra=["--boot-bin-b", str(self.bin("b1", self.B1))])
        e.run("upgrade", "--boot", anchor=False, check=50)
        T.slot_tool(e.sfboot, "early", running="b")      # B started once, never marked good
        T.slot_tool(e.sfboot, "early", running="a")      # the next start was A: fallback recorded
        st = T.slot_status(e.sfboot)
        self.assertEqual((st["default"], st["trial_state"]), ("a", "failed"))
        self.assertEqual(self.slot_a(), self.default_a)
        # A fixed release can be staged again (begin-stage clears the failed trial).
        rel3, coll3, _ = self.kext_release("rel3", b"v3\n")
        e.publish("0.1.2", self.t1, kc=rel3, boot=self.bin("a1", self.A1), extra=["--boot-bin-b", str(self.bin("b1", self.B1))])
        e.run("upgrade", "--boot", anchor=False, check=50)
        self.assertEqual(T.read_kernel_bin((e.sfboot / "sf/b/kernel.bin").read_bytes())[2], coll3)
        self.assertEqual(T.slot_status(e.sfboot)["trial_state"], "armed")

    def test_release_without_slot_b_build(self):
        e = self.e
        rel2, _, _ = self.kext_release("rel2", b"v2\n")
        e.publish("0.1.1", self.t1, kc=rel2, boot=self.bin("a1", self.A1))
        before = T.snapshot(e.root)
        p = e.run("upgrade", "--boot", anchor=False, check=30)
        self.assertIn("slot b needs the stage 2 built for it", p.stderr)
        self.assertEqual(T.snapshot(e.root), before)
        self.assertEqual(self.slot_a(), self.default_a)
        self.assertEqual(T.slot_status(e.sfboot)["trial_state"], "none")

    def test_interrupted_staging(self):
        e = self.e
        rel2, coll2, _ = self.kext_release("rel2", b"v2\n")
        e.publish("0.1.1", self.t1, kc=rel2, boot=self.bin("a1", self.A1), extra=["--boot-bin-b", str(self.bin("b1", self.B1))])
        root0 = e.d / "root0"
        sf0 = e.d / "sf0"
        shutil.copytree(e.root, root0, symlinks=True)
        shutil.copytree(e.sfboot, sf0)
        outcomes = set()
        for kind in ("rec", "op"):
            for back in (False, True):
                n = 1
                while n < 100:
                    for src, dst in ((root0, e.root), (sf0, e.sfboot)):
                        shutil.rmtree(dst)
                        shutil.copytree(src, dst, symlinks=True)
                    p = e.run("upgrade", "--boot", anchor=False, env={"SAP_FAULT": f"{kind}:{n}"})
                    if p.returncode == 50:
                        break
                    self.assertIn("SAP_FAULT", p.stderr, p.stderr)
                    e.run(*(["recover", "--rollback"] if back else ["recover"]), anchor=False, check=0)
                    self.assertEqual(self.slot_a(), self.default_a, f"{kind}:{n}: the default slot was written")
                    st = T.slot_status(e.sfboot)
                    if st["trial_state"] == "armed" and back and not (e.sfboot / "sf/b/boot.bin").exists():
                        # Armed before the fault, then rolled back: sf-bootslot has no disarm, so the
                        # trial's stage 2 is renamed away; stage 1 then starts the default (TRIAL_DAMAGED).
                        self.assertTrue((e.sfboot / "sf/b/boot.bin.cancelled").exists())
                        outcomes.add("cancelled")
                    elif st["trial_state"] == "armed":
                        # Armed only with B complete and matching (a fault after the done record leaves the
                        # finished transaction alone, even with --rollback).
                        self.assertEqual(T.read_kernel_bin((e.sfboot / "sf/b/kernel.bin").read_bytes())[2], coll2)
                        self.assertEqual(st["slot_b"].split()[-1], "file:matches")
                        outcomes.add("armed")
                    else:
                        self.assertEqual(st["trial_state"], "none", f"{kind}:{n}")
                        outcomes.add("not armed")
                    e.run("verify", anchor=False, check=0)
                    n += 1
        self.assertEqual(outcomes, {"armed", "not armed", "cancelled"})

    def test_rollback_leaves_slots(self):
        e = self.e
        rel2, _, _ = self.kext_release("rel2", b"v2\n")
        e.publish("0.1.1", self.t1, kc=rel2, boot=self.bin("a1", self.A1), extra=["--boot-bin-b", str(self.bin("b1", self.B1))])
        e.run("upgrade", "--boot", anchor=False, check=50)
        p = e.run("rollback", anchor=False, check=0)
        self.assertIn("slot b (arm) is left as it is", p.stdout)
        self.assertEqual(self.slot_a(), self.default_a)

    def test_legacy_config_refused_with_record(self):
        e = self.e
        conf = e.root / "etc/sap.conf"
        conf.parent.mkdir(parents=True, exist_ok=True)
        conf.write_text("boot_backend = legacy\n")
        rel2, _, _ = self.kext_release("rel2", b"v2\n")
        e.publish("0.1.1", self.t1, kc=rel2, boot=self.bin("a1", self.A1), extra=["--boot-bin-b", str(self.bin("b1", self.B1))])
        p = e.run("upgrade", "--boot", anchor=False, check=30)
        self.assertIn("bootstate.bin", p.stderr)
        self.assertEqual(self.slot_a(), self.default_a)


class SelfUpdate(unittest.TestCase):
    def test_sap_first_then_rest(self):
        e = Env(self)
        e.publish("0.1.0", e.tree(tree_v1))
        e.run("install", "--all", check=0)
        t2 = e.tree(tree_v2)
        write(t2 / "usr/bin/sap", "#!/bin/sh\necho fake sap 2\n", 0o755)
        e.publish("0.1.1", t2, spec=spec(vim={"version": "9.1.1-1"}, sap={"version": "1.0.1-1"}))
        # The fake /usr/bin/sap in the root is not executable as SAP; SAP_SELF_EXEC points the re-exec at us.
        e.run("upgrade", env={"SAP_SELF_EXEC": str(e.sap)}, check=0)
        h = e.history()
        self.assertIn("sap 1.0.0-1->1.0.1-1", h[-2]["detail"])
        self.assertIn("vim", h[-1]["detail"])
        e.run("verify", check=0)

    def test_min_sap(self):
        e = Env(self)
        e.publish("0.1.0", e.tree(tree_v1))
        e.run("install", "--all", check=0)
        e.publish("0.1.1", e.tree(tree_v2), spec=V2, extra=["--min-sap", "99.0"])
        p = e.run("upgrade", check=20)
        self.assertIn("SAP", p.stderr)


if __name__ == "__main__":
    unittest.main()
