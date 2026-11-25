#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Dumps and compares stub volume trees for SFStub's differential test (ENGINE.md section 10).

  stubtree.py dump --info build.json --store diskNsM --out tree.json
  stubtree.py compare A.json B.json [--report report.md]
  stubtree.py ops A.ops A-build.json B.ops B-build.json [--fixture asahi-v0.9.2-commands.txt]

The dump records, for every entry of the four volumes (System, Data, Preboot, Recovery): its path, type,
permission bits, owner, group, BSD flags, every extended attribute (read with XATTR_SHOWCOMPRESSION, so the
decmpfs header and the compressed resource fork are compared byte for byte), its size and the SHA-256 of
its contents as read (the decompressed bytes), or a symlink's target. Plus each volume's name, roles and
APFS bootable flag.

NORMALISATIONS, the complete list (anything else that differs is a failure):
  N1 The volume group UUID (VGID), a fresh random UUID per container: replaced by <VGID> in paths, symlink
     targets and file contents.
  N2 The Preboot volume's own UUID (upstream's ##PREBOOT## substitution in step2.sh): <PREBOOT_UUID> in
     file contents.
  N3 Mount points (/Volumes/... as macOS chose them): <System>, <Data>, <Preboot>, <Recovery> in symlink
     targets and in the command sequence.
  N4 Timestamps (access, modification, change, birth) and inode numbers are not compared.
  N5 Entries macOS itself creates on a mounted volume, at a volume's root only: .fseventsd,
     .Spotlight-V100, .Trashes, .TemporaryItems, .DocumentRevisions-V100. They are listed in the dump but
     excluded from the comparison.
  N6 Disk identifiers in the command sequence: replaced by the volume's role (<CONTAINER>, <DATA>, ...).
Every file whose contents N1 or N2 changed is named in the report.
"""
import ctypes, hashlib, json, os, plistlib, stat, subprocess, sys

OS_ARTIFACTS = {".fseventsd", ".Spotlight-V100", ".Trashes", ".TemporaryItems", ".DocumentRevisions-V100"}
XATTR_NOFOLLOW, XATTR_SHOWCOMPRESSION = 0x0001, 0x0020
libc = ctypes.CDLL("libSystem.B.dylib", use_errno=True)
libc.listxattr.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_int]
libc.listxattr.restype = ctypes.c_ssize_t
libc.getxattr.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint32, ctypes.c_int]
libc.getxattr.restype = ctypes.c_ssize_t
libc.fsctl.argtypes = [ctypes.c_char_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_int), ctypes.c_uint]
libc.fsctl.restype = ctypes.c_int


def xattrs(path):
    p = path.encode()
    opts = XATTR_NOFOLLOW | XATTR_SHOWCOMPRESSION
    n = libc.listxattr(p, None, 0, opts)
    if n <= 0:
        return {}
    buf = ctypes.create_string_buffer(n)
    n = libc.listxattr(p, buf, n, opts)
    out = {}
    for name in buf.raw[:n].split(b"\0"):
        if not name:
            continue
        sz = libc.getxattr(p, name, None, 0, 0, opts)
        if sz < 0:
            raise OSError(ctypes.get_errno(), f"getxattr {name} {path}")
        vb = ctypes.create_string_buffer(max(sz, 1))
        sz = libc.getxattr(p, name, vb, sz, 0, opts)
        v = vb.raw[:sz]
        out[name.decode()] = v.hex() if len(v) <= 64 else "sha256:" + hashlib.sha256(v).hexdigest() + f":{len(v)}"
    return out


def bootable(root):
    c = ctypes.c_int(0)
    if libc.fsctl(root.encode(), 0xC0044A57, ctypes.byref(c), 0) != 0:
        return None
    return c.value == 1


def dump(info_path, store, out):
    info = json.load(open(info_path))
    vgid, pb = info["vgid"], info["preboot_uuid"]
    roots = info["roots"]
    norm = [(vgid, "<VGID>"), (vgid.lower(), "<VGID>"), (pb, "<PREBOOT_UUID>"), (pb.lower(), "<PREBOOT_UUID>")]
    mounts = sorted(((r, f"<{v}>") for v, r in roots.items()), key=lambda x: -len(x[0]))

    def n_text(s):
        for a, b in norm:
            s = s.replace(a, b)
        return s

    def n_link(s):
        for a, b in mounts:
            if s == a or s.startswith(a + "/"):
                s = b + s[len(a):]
        return n_text(s)

    tree = {"volumes": {}, "entries": {}, "artifacts": [], "normalised_contents": []}
    cinfo = plistlib.loads(subprocess.run(["/usr/sbin/diskutil", "info", "-plist", store], stdout=subprocess.PIPE, check=True).stdout)
    clist = plistlib.loads(subprocess.run(["/usr/sbin/diskutil", "apfs", "list", "-plist", cinfo["APFSContainerReference"]],
                                          stdout=subprocess.PIPE, check=True).stdout)["Containers"][0]
    tree["container_bytes"] = clist.get("CapacityCeiling")
    vgs = plistlib.loads(subprocess.run(["/usr/sbin/diskutil", "apfs", "listVolumeGroups", cinfo["APFSContainerReference"], "-plist"],
                                        stdout=subprocess.PIPE, check=True).stdout)["Containers"][0].get("VolumeGroups", [])
    group_of = {}
    for g in vgs:
        for gv in g.get("Volumes", []):
            group_of[gv["DeviceIdentifier"]] = "<VGID>" if g["APFSVolumeGroupUUID"] == vgid else g["APFSVolumeGroupUUID"]
    for v in clist["Volumes"]:
        role = v["Roles"][0] if len(v["Roles"]) == 1 else ",".join(v["Roles"]) or "-"
        tree["volumes"][role] = {"name": v["Name"], "roles": v["Roles"], "group": group_of.get(v["DeviceIdentifier"]),
                                 "filevault": v.get("FileVault"), "encryption": v.get("Encryption")}
    for vol, root in sorted(roots.items()):
        tree["volumes"].setdefault(vol, {})["bootable"] = bootable(root)
        for dirpath, dirnames, filenames in os.walk(root):
            rel_dir = os.path.relpath(dirpath, root)
            if rel_dir == ".":
                for a in sorted(set(dirnames + filenames) & OS_ARTIFACTS):
                    tree["artifacts"].append(f"{vol}:/{a}")
                dirnames[:] = [d for d in dirnames if d not in OS_ARTIFACTS]
                filenames = [f for f in filenames if f not in OS_ARTIFACTS]
                names = [""]
            else:
                names = []
            names += sorted(dirnames) + sorted(filenames)
            for name in names:
                full = os.path.join(dirpath, name) if name else dirpath
                st = os.lstat(full)
                rel = os.path.normpath(os.path.join(rel_dir, name)) if name else rel_dir
                key = f"{vol}:/{n_text(rel) if rel != '.' else ''}"
                e = {"mode": oct(stat.S_IMODE(st.st_mode)), "uid": st.st_uid, "gid": st.st_gid,
                     "flags": hex(st.st_flags), "xattrs": xattrs(full)}
                if stat.S_ISLNK(st.st_mode):
                    e["type"] = "link"
                    e["target"] = n_link(os.readlink(full))
                elif stat.S_ISDIR(st.st_mode):
                    e["type"] = "dir"
                else:
                    e["type"] = "file"
                    h = hashlib.sha256()
                    size = 0
                    data_small = None
                    with open(full, "rb") as f:
                        while True:
                            b = f.read(8 << 20)
                            if not b:
                                break
                            if size == 0 and len(b) < (1 << 20):
                                data_small = b
                            size += len(b)
                            h.update(b)
                    e["size"] = size
                    e["sha256"] = h.hexdigest()
                    if data_small is not None and size == len(data_small):
                        try:
                            t = data_small.decode("utf-8")
                            nt = n_text(t)
                            if nt != t:
                                e["sha256"] = "normalised:" + hashlib.sha256(nt.encode()).hexdigest()
                                tree["normalised_contents"].append(key)
                        except UnicodeDecodeError:
                            pass
                tree["entries"][key] = e
    json.dump(tree, open(out, "w"), indent=1, sort_keys=True)
    print(f"dumped {len(tree['entries'])} entries to {out}")


def compare(a_path, b_path, report=None):
    a, b = json.load(open(a_path)), json.load(open(b_path))
    diffs = []
    for k in sorted(set(a["volumes"]) | set(b["volumes"])):
        if a["volumes"].get(k) != b["volumes"].get(k):
            diffs.append(f"volume {k}: {a['volumes'].get(k)} != {b['volumes'].get(k)}")
    if a.get("container_bytes") != b.get("container_bytes"):
        diffs.append(f"container size {a.get('container_bytes')} != {b.get('container_bytes')}")
    ka, kb = set(a["entries"]), set(b["entries"])
    for k in sorted(ka - kb):
        diffs.append(f"only in A: {k}")
    for k in sorted(kb - ka):
        diffs.append(f"only in B: {k}")
    for k in sorted(ka & kb):
        ea, eb = a["entries"][k], b["entries"][k]
        for f in sorted(set(ea) | set(eb)):
            if ea.get(f) != eb.get(f):
                diffs.append(f"{k}: {f}: {ea.get(f)} != {eb.get(f)}")
    if a["normalised_contents"] != b["normalised_contents"]:
        diffs.append(f"normalised files differ: {a['normalised_contents']} != {b['normalised_contents']}")
    files = [e for e in a["entries"].values() if e["type"] == "file"]
    lines = [f"A: {a_path}", f"B: {b_path}",
             f"entries: {len(ka)} vs {len(kb)}; files {len(files)}, {sum(e['size'] for e in files)} bytes (as read)",
             f"volumes: {json.dumps(a['volumes'], sort_keys=True)}",
             f"OS-created root entries excluded (N5): A {a['artifacts']} B {b['artifacts']}",
             f"contents normalised (N1/N2): {a['normalised_contents']}",
             f"differences: {len(diffs)}"] + [f"  {d}" for d in diffs[:200]]
    text = "\n".join(lines) + "\n"
    print(text)
    if report:
        open(report, "w").write(text)
    return 0 if not diffs else 1


def norm_ops(ops_path, info_path):
    info = json.load(open(info_path))
    subs = sorted(((r, f"<{v}>") for v, r in info["roots"].items()), key=lambda x: -len(x[0]))
    out = []
    for line in open(ops_path).read().splitlines():
        for a_, b_ in subs:
            line = line.replace(a_ + "/", b_ + "/")
            if line.endswith(" " + a_) or (" " + a_ + " ") in line:
                line = line.replace(" " + a_, " " + b_)
        line = line.replace(info["vgid"], "<VGID>")
        out.append(line)
    return out


def ops(a_ops, a_info, b_ops, b_info, fixture=None):
    A, B = norm_ops(a_ops, a_info), norm_ops(b_ops, b_info)
    rc = 0
    if A != B:
        rc = 1
        import difflib
        print("\n".join(difflib.unified_diff(A, B, "oracle", "sfstub", lineterm="")))
    else:
        print(f"command sequences equal ({len(A)} commands)")
    if fixture:
        if os.path.exists(fixture):
            F = open(fixture).read().splitlines()
            F = [l for l in F if l and not l.startswith("#")]
            if F != A:
                rc = 1
                print("oracle sequence differs from the committed fixture")
            else:
                print("matches fixture", fixture)
        else:
            print("fixture missing:", fixture)
            rc = 1
    return rc


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "dump":
        a = dict(zip(sys.argv[2::2], sys.argv[3::2]))
        dump(a["--info"], a["--store"], a["--out"])
    elif cmd == "compare":
        rep = sys.argv[sys.argv.index("--report") + 1] if "--report" in sys.argv else None
        sys.exit(compare(sys.argv[2], sys.argv[3], rep))
    elif cmd == "ops":
        fx = sys.argv[sys.argv.index("--fixture") + 1] if "--fixture" in sys.argv else None
        sys.exit(ops(*sys.argv[2:6], fixture=fx))
    else:
        sys.exit("unknown command")
