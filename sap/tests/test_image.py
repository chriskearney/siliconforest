# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""SAP in the root image (docs/sap/IMAGE.md): sf-mount-sfboot finding SFBOOT, and prepare_root.py
--sap-bin putting SAP into a synthetic root with its database seeded, checked by the client itself.
Host binaries stand in for the aarch64-apple-darwin ones; image steps need e2fsprogs (skipped without)."""
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from saptest import REPO, SAP, Keys, binaries, bootslot

sys.path.insert(0, str(SAP / "tools"))
sys.path.insert(0, str(REPO / "installer/payload/image"))
import sap_image  # noqa: E402

E2FS = all(shutil.which(t) or Path("/sbin", t).exists() or Path("/usr/sbin", t).exists() for t in ("mkfs.ext4", "debugfs"))
os.environ["PATH"] += ":/sbin:/usr/sbin"


def fat32(label=b"SFBOOT"):
    s = bytearray(512)
    s[0:3] = b"\xebX\x90"
    struct.pack_into("<H", s, 11, 512)
    s[0x42] = 0x29
    s[0x47:0x52] = label.ljust(11)
    s[0x52:0x5A] = b"FAT32   "
    s[510:512] = b"\x55\xaa"
    return bytes(s)


class MountSFBOOT(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp(prefix="sap-mount-"))
        cc = shutil.which("cc") or shutil.which("clang") or shutil.which("gcc")
        cls.tool = cls.tmp / "sf-mount-sfboot"
        subprocess.run([cc, "-std=c11", "-Wall", "-Werror", str(SAP / "image/sf-mount-sfboot.c"), "-o", str(cls.tool)], check=True)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def run_in(self, devs):
        d = Path(tempfile.mkdtemp(dir=self.tmp))
        for name, data in devs.items():
            (d / name).write_bytes(data)
        return subprocess.run([str(self.tool), "--dev-dir", str(d), "--dry-run", str(self.tmp / "mnt")], capture_output=True, text=True)

    def test_finds_the_one_sfboot(self):
        p = self.run_in({"rdisk0s1": b"\0" * 512, "rdisk0s4": fat32(b"EFI"), "rdisk0s5": fat32(), "disk0s5": fat32()})
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertRegex(p.stdout, r"device=\S*/disk0s5\n")

    def test_none_or_two_are_refused(self):
        self.assertNotEqual(self.run_in({"rdisk0s4": fat32(b"EFI")}).returncode, 0)
        self.assertNotEqual(self.run_in({"rdisk0s5": fat32(), "rdisk1s2": fat32()}).returncode, 0)

    def test_not_fat32_is_ignored(self):
        fat16 = bytearray(fat32())
        fat16[0x52:0x5A] = b"FAT16   "
        self.assertNotEqual(self.run_in({"rdisk0s5": bytes(fat16)}).returncode, 0)


class ImageFiles(unittest.TestCase):
    def test_binaries_must_be_arm64_macho(self):
        with tempfile.TemporaryDirectory() as d:
            for n in sap_image.BINARIES.values():
                Path(d, n).write_bytes(b"\x7fELF" + b"\0" * 60)
            with self.assertRaises(sap_image.ImageError):
                sap_image.files(d)
            for n in sap_image.BINARIES.values():
                Path(d, n).write_bytes(bytes.fromhex("cffaedfe0c000001") + b"\0" * 56)
            got = {t: m for t, _, m in sap_image.files(d)}
            self.assertNotIn("/usr/libexec/sap/kc-builder", got)
            Path(d, "kc-builder").write_bytes(bytes.fromhex("cffaedfe0c000001") + b"\0" * 56)
            Path(d, "LICENSE.kc-tools").write_text("BSD-3-Clause\n")
            got = {t: m for t, _, m in sap_image.files(d)}
        self.assertEqual(got["/usr/bin/sap"], 0o755)
        self.assertEqual(got["/System/Library/LaunchDaemons/org.siliconforest.sap-boot.plist"], 0o644)
        self.assertIn("/etc/sap.conf", got)

    def test_conf_names_the_slots_tool_and_power_rule(self):
        t = sap_image.conf_text("https://example.invalid/v1/stable/manifest.json").decode()
        self.assertIn("manifest_url = https://example.invalid/v1/stable/manifest.json", t)
        self.assertIn("bootslot_tool = /usr/libexec/sf-bootslot", t)
        self.assertIn("require_ac = yes", t)


@unittest.skipUnless(E2FS, "needs e2fsprogs (mkfs.ext4, debugfs)")
class PreparedRoot(unittest.TestCase):
    """prepare_root.py --sap-bin on a synthetic base: the image carries SAP and a seeded database
    that the client verifies against the image's own channel."""

    @classmethod
    def setUpClass(cls):
        import synthetic_base
        import prepare_root
        cls.tmp = Path(tempfile.mkdtemp(prefix="sap-image-"))
        t = cls.tmp
        synthetic_base.build(t / "base", 64)
        sap, sf = binaries()
        b = t / "bin"
        b.mkdir()
        for n, src in (("sap", sap), ("sf", sf), ("sf-bootslot", bootslot())):
            shutil.copyfile(src, b / n)
        cc = shutil.which("cc") or shutil.which("clang") or shutil.which("gcc")
        subprocess.run([cc, "-std=c11", str(SAP / "image/sf-mount-sfboot.c"), "-o", str(b / "sf-mount-sfboot")], check=True)
        cls.keys = Keys(t)
        cls.info = prepare_root.prepare(t / "base", t / "root", 32, {
            "bin": b, "channel": t / "channel", "release": "0.0.1", "sequence": 1, "key": cls.keys.key,
            "manifest_url": None, "host_binaries": True})
        img = t / "root" / json.loads((t / "root/root.json").read_text())["image"]
        cls.tree = t / "tree"
        cls.tree.mkdir()
        subprocess.run(["debugfs", "-R", f"rdump / {cls.tree}", str(img)], check=True, capture_output=True)
        cls.tsv = (t / "root/root.manifest.tsv").read_text()

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def sap(self, *args):
        env = dict(os.environ, SAP_ALLOW_NONROOT="1")
        url = (self.tmp / "channel/v1/stable/manifest.json").as_uri()
        return subprocess.run([str(binaries()[0]), "--root", str(self.tree), "--manifest-url", url,
                               "--trust-anchor", str(self.keys.signers), *args], capture_output=True, text=True, env=env)

    def test_files_and_database_are_in_the_image_and_its_manifest(self):
        for p in ("/usr/bin/sap", "/usr/libexec/sf-bootslot", "/usr/libexec/sap/sap-boot", "/etc/sap.conf",
                  "/System/Library/LaunchDaemons/org.siliconforest.sap-mark-good.plist"):
            self.assertIn("\n" + p + "\t", self.tsv, p)
            self.assertTrue((self.tree / p.lstrip("/")).exists(), p)
        self.assertIn("\n/private/var/db/sap/", self.tsv)
        self.assertTrue(any((self.tree / "private/var/db/sap").iterdir()))

    def test_the_client_verifies_the_seeded_image(self):
        p = self.sap("verify")
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        p = self.sap("list")
        self.assertIn("sap", p.stdout)
        self.assertIn("0.0.1-1", p.stdout)
        p = self.sap("check")
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)


if __name__ == "__main__":
    unittest.main()
