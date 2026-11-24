# SPDX-License-Identifier: MIT
# Copyright (c) 2021 The Asahi Linux contributors
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
#
# Ported from asahi_firmware/wifi.py of the Asahi Linux installer, tag v0.9.2
# (commit dffbb38ef0c00c0431c609ecd8a00f42deb5b24c), MIT. Changes: no printing or logging, files
# are read lazily by path, Python 3.9 compatible, and a filter by output name.
"""Name Apple's Wi-Fi firmware files the way the brcmfmac driver family expects them."""

import hashlib
import os


class FWFile(object):
    def __init__(self, name, data):
        self.name = name
        self.data = data
        self.sha = hashlib.sha256(data).hexdigest()

    def __eq__(self, other):
        return other is not None and self.sha == other.sha

    def __hash__(self):
        return hash(self.sha)


class FWNode(object):
    def __init__(self, this=None, leaves=None):
        self.this = this
        self.leaves = {} if leaves is None else leaves

    def __eq__(self, other):
        return self.this == other.this and self.leaves == other.leaves

    def __hash__(self):
        return hash((self.this, tuple(self.leaves.items())))


class WiFiFWCollection(object):
    EXTMAP = {"trx": "bin", "txt": "txt", "clmb": "clm_blob", "txcb": "txcap_blob", "sig": "sig"}
    DIMS = ["C", "s", "P", "M", "V", "m", "A"]

    def __init__(self, source_path):
        self.root = FWNode()
        self.load(source_path)
        self.prune()

    def load(self, source_path):
        for dirpath, dirnames, filenames in os.walk(source_path):
            dirnames.sort()
            for skip in ("perf", "assert", "C-4388__s-C2"):
                if skip in dirnames:
                    dirnames.remove(skip)
            subpath = os.path.relpath(dirpath, source_path)
            for name in sorted(filenames):
                if not any(name.endswith("." + i) for i in self.EXTMAP):
                    continue
                if "_gen" in name:
                    continue
                path = os.path.join(dirpath, name)
                relpath = os.path.join(subpath, name)
                if not name.endswith(".txt"):
                    name = "P-" + name
                idpath, ext = os.path.join(subpath, name).rsplit(".", 1)
                props = {}
                for i in idpath.replace("/", "_").split("_"):
                    if not i or i == ".":
                        continue
                    k, v = i.split("-", 1)
                    if k == "P" and "-" in v:
                        plat, ant = v.split("-", 1)
                        props["P"] = plat
                        props["A"] = ant
                    else:
                        props[k] = v
                ident = [ext]
                for dim in self.DIMS:
                    if dim in props:
                        ident.append(props.pop(dim))
                if props:
                    raise ValueError("unexpected Wi-Fi firmware name dimensions in %s" % relpath)
                node = self.root
                for k in ident:
                    node = node.leaves.setdefault(k, FWNode())
                with open(path, "rb") as fd:
                    data = fd.read()
                if name.endswith(".txt"):
                    data = self.process_nvram(data)
                node.this = FWFile(relpath, data)

    def prune(self, node=None, depth=0):
        if node is None:
            node = self.root
        for i in node.leaves.values():
            self.prune(i, depth + 1)
        if node.this is None and node.leaves and depth > 3:
            first = next(iter(node.leaves.values()))
            if all(i == first for i in node.leaves.values()):
                node.this = first.this
        for i in node.leaves.values():
            if not i.this or not node.this:
                break
            if i.this != node.this:
                break
        else:
            node.leaves = {}

    def _walk_files(self, node, ident):
        if node.this is not None:
            yield ident, node.this
        for k, subnode in node.leaves.items():
            yield from self._walk_files(subnode, ident + [k])

    def files(self):
        for ident, fwfile in self._walk_files(self.root, []):
            (ext, chip, rev), rest = ident[:3], ident[3:]
            rev = rev.lower()
            ext = self.EXTMAP[ext]
            rest = ("," + "-".join(rest)) if rest else ""
            yield "brcm/brcmfmac%s%s-pcie.apple%s.%s" % (chip, rev, rest, ext), fwfile

    @staticmethod
    def process_nvram(data):
        lines = []
        for line in data.decode("ascii").split("\n"):
            if not line:
                continue
            key, value = line.split("=", 1)
            lines.append("%s=%s\n" % (key.strip(), value))
        return "".join(lines).encode("ascii")
