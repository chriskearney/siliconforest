#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Checks that stubtree.py's SiliconForest-payload comparison (sf-compare, sf-ops) accepts exactly the declared
delta and rejects everything else. Synthetic trees, no Apple bits, no disks: runs anywhere (CI)."""
import copy, json, os, sys, tempfile, unittest

sys.path.insert(0, os.path.dirname(__file__))
import stubtree  # noqa: E402

DELTA = os.path.join(os.path.dirname(__file__), "fixtures", "sf-payload-delta.json")


def f(sha, size=10, mode="0o644"):
    return {"type": "file", "mode": mode, "uid": 0, "gid": 20, "flags": "0x0", "xattrs": [], "sha256": sha, "size": size}


def d(mode="0o755"):
    return {"type": "dir", "mode": mode, "uid": 0, "gid": 20, "flags": "0x0", "xattrs": []}


VOLS = {"System": {"bootable": True, "roles": ["System"], "name": "SiliconForest", "group": "<VGID>", "filevault": False, "encryption": False}}
SUM = {"b": "b" * 64}


def asahi():
    e = {"System:/": d(), "System:/usr/standalone/bootcaches.plist": f("a" * 64), "Preboot:/<VGID>/x": f("c" * 64),
         "System:/.VolumeIcon.icns": f("1" * 64, 4104), "System:/.IAPhysicalMedia": f("2" * 64, 399),
         "System:/Finish Installation.app": d(), "System:/Finish Installation.app/Contents": d(),
         "System:/Finish Installation.app/Contents/Resources": d(),
         "System:/Finish Installation.app/Contents/Resources/boot.bin": f("9" * 64, 500),
         "System:/Finish Installation.app/Contents/Resources/step2.sh": f("normalised:" + "3" * 64, 4000, "0o755")}
    return {"entries": e, "volumes": VOLS, "container_bytes": 2499805184, "artifacts": ["System:/.fseventsd"],
            "normalised_contents": ["System:/Finish Installation.app/Contents/Resources/step2.sh"]}


def manifest():
    app = "SiliconForest Setup.app"
    rows = [("dir", app, 0o755, 0, ""), ("dir", app + "/Contents", 0o755, 0, ""), ("dir", app + "/Contents/Resources", 0o755, 0, ""),
            ("file", app + "/Contents/Resources/boot.bin", 0o644, 500, "9" * 64),
            ("file", app + "/Contents/Resources/sf-step2.sh", 0o755, 700, "7" * 64),
            ("dir", "SFInstall", 0o755, 0, ""), ("file", "SFInstall/plan.json", 0o644, 80, "6" * 64),
            ("file", ".IAPhysicalMedia", 0o644, 300, "5" * 64), ("file", ".VolumeIcon.icns", 0o644, 4104, "4" * 64)]
    return {"entries": [{"type": t, "path": p, "mode": m, "size": s, "sha256": h} for t, p, m, s, h in rows]}


def sf(man):
    a = asahi()
    e = {k: v for k, v in a["entries"].items() if "Finish Installation" not in k}
    for m in man["entries"]:
        k = "System:/" + m["path"]
        e[k] = d() if m["type"] == "dir" else f(m["sha256"], m["size"], oct(m["mode"]))
    return {"entries": e, "volumes": copy.deepcopy(VOLS), "container_bytes": 2499805184, "artifacts": ["System:/.fseventsd"],
            "normalised_contents": []}


class T(unittest.TestCase):
    def run_cmp(self, a, b, man):
        with tempfile.TemporaryDirectory() as t:
            paths = []
            for n, o in (("a", a), ("b", b), ("m", man)):
                p = os.path.join(t, n + ".json"); json.dump(o, open(p, "w")); paths.append(p)
            import io, contextlib
            with contextlib.redirect_stdout(io.StringIO()) as out:
                rc = stubtree.sf_compare(paths[0], paths[1], DELTA, paths[2])
            return rc, out.getvalue()

    def test_the_declared_delta_passes(self):
        man = manifest()
        rc, out = self.run_cmp(asahi(), sf(man), man)
        self.assertEqual(rc, 0, out)

    def test_each_undeclared_difference_fails(self):
        man = manifest()
        def mut(fn):
            b = sf(man); m = copy.deepcopy(man); fn(b, m); return self.run_cmp(asahi(), b, m)
        cases = {
            "asahi file leaks into the SF side": lambda b, m: b["entries"].update({"System:/Finish Installation.app": d()}),
            "an extra file under a payload prefix": lambda b, m: b["entries"].update({"System:/SFInstall/extra": f("e" * 64)}),
            "an extra file outside the payload": lambda b, m: b["entries"].update({"System:/stray": f("e" * 64)}),
            "an apple-owned file changed": lambda b, m: b["entries"].update({"Preboot:/<VGID>/x": f("d" * 64)}),
            "an apple-owned file's mode changed": lambda b, m: b["entries"].update({"System:/usr/standalone/bootcaches.plist": f("a" * 64, mode="0o600")}),
            "a payload file's content differs from the manifest": lambda b, m: b["entries"].update({"System:/SFInstall/plan.json": f("0" * 64, 80)}),
            "a payload file's mode differs from the manifest": lambda b, m: b["entries"].update({"System:/SiliconForest Setup.app/Contents/Resources/sf-step2.sh": f("7" * 64, 700, "0o644")}),
            "a manifest file is missing": lambda b, m: b["entries"].pop("System:/SFInstall/plan.json"),
            "the manifest names a file that is not on the stub": lambda b, m: m["entries"].append({"type": "file", "path": "SFInstall/ghost", "mode": 0o644, "size": 1, "sha256": "8" * 64}),
            "the boot object differs from the baseline's": lambda b, m: (b["entries"].update({"System:/SiliconForest Setup.app/Contents/Resources/boot.bin": f("8" * 64, 500)}),
                                                                         [x.update({"sha256": "8" * 64}) for x in m["entries"] if x["path"].endswith("boot.bin")]),
            "the icon's flags changed": lambda b, m: b["entries"]["System:/.VolumeIcon.icns"].update({"flags": "0x20000"}),
            "a volume role changed": lambda b, m: b["volumes"]["System"].update({"roles": ["Data"]}),
            "the bootable flag changed": lambda b, m: b["volumes"]["System"].update({"bootable": False}),
            "the container size changed": lambda b, m: b.update({"container_bytes": 1}),
            "a content normalisation appeared on the SF side": lambda b, m: b.update({"normalised_contents": ["System:/SFInstall/plan.json"]}),
        }
        for name, fn in cases.items():
            rc, out = mut(fn)
            self.assertEqual(rc, 1, f"{name}: accepted\n{out}")

    def test_a_baseline_without_the_asahi_payload_is_refused(self):
        man = manifest(); a = asahi()
        a["entries"] = {k: v for k, v in a["entries"].items() if "Finish Installation" not in k}
        rc, _ = self.run_cmp(a, sf(man), man)
        self.assertEqual(rc, 1)

    def test_commands(self):
        import io, contextlib
        with tempfile.TemporaryDirectory() as t:
            def w(name, lines, roots):
                open(os.path.join(t, name + ".ops"), "w").write("\n".join(lines) + "\n")
                json.dump({"roots": roots, "vgid": "V"}, open(os.path.join(t, name + ".json"), "w"))
            base = ["diskutil mount disk9s1", "os.chflags /Volumes/S/Finish Installation.app/Contents 0x0", "os.chflags /Volumes/S/Finish Installation.app 0x0", "m1n1.build"]
            sfl = ["diskutil mount disk9s1", "os.chflags /Volumes/S/SiliconForest Setup.app/Contents/MacOS 0x0", "os.chflags /Volumes/S/SiliconForest Setup.app 0x0", "m1n1.build"]
            w("a", base, {"System": "/Volumes/S"}); w("b", sfl, {"System": "/Volumes/S"})
            fx = os.path.join(t, "fx.txt")
            def run(fixture_lines):
                open(fx, "w").write("\n".join(fixture_lines) + "\n")
                with contextlib.redirect_stdout(io.StringIO()):
                    return stubtree.sf_ops(os.path.join(t, "a.ops"), os.path.join(t, "a.json"), os.path.join(t, "b.ops"), os.path.join(t, "b.json"), DELTA, fixture=fx)
            norm = stubtree.norm_ops(os.path.join(t, "b.ops"), os.path.join(t, "b.json"))
            self.assertEqual(run(norm), 0)
            self.assertEqual(run(norm[:-1]), 1)                      # differs from the fixture
            # an undeclared command on the SF side
            open(os.path.join(t, "b.ops"), "w").write("\n".join(sfl[:2] + ["diskutil eraseDisk x"] + sfl[2:]) + "\n")
            self.assertEqual(run(norm), 1)


if __name__ == "__main__":
    unittest.main()
