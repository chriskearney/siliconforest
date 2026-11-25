# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""The keys SAP is built with (sap/trust/release-keys) are the installer's release keys, and the
anchor token round-trips. Public keys only; no private key is read or needed."""

import base64
import unittest

import saptest as T

SB = T.SB


def keys_of(text):
    out = set()
    for line in text.splitlines():
        if line.lstrip().startswith("#") or "ssh-ed25519" not in line:
            continue
        out.add(line.split("ssh-ed25519", 1)[1].split()[0])
    return out


class ReleaseKeys(unittest.TestCase):
    def test_same_keys_as_the_installer(self):
        sap = keys_of((T.SAP / "trust/release-keys").read_text())
        inst = keys_of((T.REPO / "installer/payload/release/allowed_signers").read_text())
        self.assertTrue(sap)
        self.assertEqual(sap, inst, "sap/trust/release-keys must list exactly installer/payload/release/allowed_signers' keys")

    def test_version_line(self):
        self.assertIn("# version 1", (T.SAP / "trust/release-keys").read_text())

    def test_anchor_token(self):
        k = T.SAP / "trust/release-keys"
        tok = SB.anchor_token([k], 1)
        self.assertTrue(tok.startswith("sf_trust=1:"))
        raw = base64.b64decode(tok.split(":", 1)[1] + "=")
        blob = base64.b64decode(next(iter(keys_of(k.read_text()))))
        self.assertEqual(raw, blob[-32:])
        self.assertLess(len(tok), 120, "fits the 608-byte bootargs budget with room for rotation")


if __name__ == "__main__":
    unittest.main()
