#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Runs the pinned Asahi Linux installer v0.9.2 stub code as the REFERENCE ORACLE for SFStub's
differential test (ENGINE.md section 10). Test machines only (the M5 or the i9). Nothing here ships, and
the Asahi code is imported from a pinned checkout, never copied into this repository.

It calls upstream's own StubInstaller.load_ipsw / prepare_volume / check_volume / install_files, then
m1n1.build exactly as osinstall.py does, on an APFS container inside a disk image. Upstream's DiskUtil is
used through a subclass whose action() first proves, with `hdiutil info` and `diskutil info`, that every
device it names belongs to a disk image under --images-root. bputil, bless, kmutil, nvram and asr are
refused outright (osenum's bputil read is replaced by a refusal, which upstream already tolerates).
"""
import argparse, json, logging, os, plistlib, re, shutil, subprocess, sys, tempfile, types

PINNED = "dffbb38ef0c00c0431c609ecd8a00f42deb5b24c"
FORBIDDEN = {"bputil", "bless", "kmutil", "nvram", "asr", "csrutil", "dd", "gpt", "fdisk"}
DEV_RX = re.compile(r"^(/dev/)?r?disk[0-9]+(s[0-9]+)*$")

ap = argparse.ArgumentParser()
ap.add_argument("--asahi", required=True)
ap.add_argument("--profile", required=True)
ap.add_argument("--store", required=True)
ap.add_argument("--label", default="SiliconForest")
ap.add_argument("--images-root", required=True)
ap.add_argument("--admin-users", required=True)
ap.add_argument("--icon", required=True)
ap.add_argument("--stage1", required=True)
ap.add_argument("--var", action="append", default=[])
ap.add_argument("--distro", default="Asahi Linux")
ap.add_argument("--ipsw", default=None)
ap.add_argument("--ops", required=True)
ap.add_argument("--out", required=True)
args = ap.parse_args()

os.umask(0o022)
asahi = os.path.realpath(args.asahi)
head = subprocess.run(["git", "-C", asahi, "rev-parse", "HEAD"], stdout=subprocess.PIPE, check=True).stdout.decode().strip()
if head != PINNED:
    sys.exit(f"Asahi reference checkout is at {head}, expected v0.9.2 {PINNED}")
dirty = subprocess.run(["git", "-C", asahi, "status", "--porcelain", "--untracked-files=no"], stdout=subprocess.PIPE, check=True).stdout.decode().strip()
if dirty:
    sys.exit("Asahi reference checkout has local modifications")

images_root = os.path.realpath(args.images_root)
real_run = subprocess.run
ops = []
names = {}


def attached_images():
    info = plistlib.loads(real_run(["/usr/bin/hdiutil", "info", "-plist"], stdout=subprocess.PIPE, check=True).stdout)
    for img in info.get("images", []):
        ents = {e["dev-entry"][5:] for e in img.get("system-entities", []) if "dev-entry" in e}
        yield os.path.realpath(img.get("image-path", "")), ents


def prove_image(dev):
    """hdiutil info first, then diskutil: the device is part of an image under images_root."""
    d = dev[5:] if dev.startswith("/dev/") else dev
    d = d[1:] if d.startswith("rdisk") else d
    whole = "disk" + re.match(r"disk([0-9]+)", d).group(1)
    for path, ents in attached_images():
        if d in ents:
            if not path.startswith(images_root + "/"):
                raise SystemExit(f"REFUSED: {d} is backed by {path}, outside {images_root}")
            break
    else:
        # a synthesised APFS disk: its physical store must be in an image
        info = plistlib.loads(real_run(["/usr/sbin/diskutil", "info", "-plist", d], stdout=subprocess.PIPE, check=True).stdout)
        stores = [s["APFSPhysicalStore"] for s in info.get("APFSPhysicalStores", [])]
        if not stores:
            raise SystemExit(f"REFUSED: {d} is not attached from a disk image")
        for s in stores:
            prove_image(s)
        if info.get("BusProtocol") != "Disk Image" or info.get("Internal") is not False:
            raise SystemExit(f"REFUSED: diskutil does not call {d} an external disk image")
        return
    info = plistlib.loads(real_run(["/usr/sbin/diskutil", "info", "-plist", d], stdout=subprocess.PIPE, check=True).stdout)
    if info.get("BusProtocol") != "Disk Image" or info.get("Internal") is not False:
        raise SystemExit(f"REFUSED: diskutil does not call {d} an external disk image")


def label(a):
    return f"<{names[a]}>" if a in names else a


def guarded_run(argv, *a, **kw):
    argv = list(argv)
    base = os.path.basename(str(argv[0]))
    if base in FORBIDDEN or any(os.path.basename(str(x)) in FORBIDDEN for x in argv):
        raise SystemExit(f"REFUSED: {base} is never run by the oracle")
    if base == "diskutil":
        mutating = argv[1] not in ("info", "list") and not (argv[1] == "apfs" and argv[2] in ("list", "listVolumeGroups"))
        if mutating:
            devs = [x for x in argv[1:] if DEV_RX.match(str(x))]
            if not devs:
                raise SystemExit(f"REFUSED: diskutil {argv[1:]} names no device")
            for d in devs:
                prove_image(d)
            ops.append(" ".join(["diskutil"] + [label(str(x)) for x in argv[1:]]))
    elif base in ("xattr", "chflags"):
        ops.append(" ".join([base] + [str(x) for x in argv[1:]]))
    elif base not in ("hdiutil", "tar", "git"):
        raise SystemExit(f"REFUSED: the oracle does not run {base}")
    return real_run(argv, *a, **kw)


subprocess.run = guarded_run
logging.basicConfig(level=logging.INFO, stream=sys.stderr, format="%(message)s")

# upstream reads step2/ and logo.icns from its working directory
work = tempfile.mkdtemp(prefix="asahi-oracle-")
shutil.copytree(os.path.join(asahi, "src", "step2"), os.path.join(work, "step2"))
shutil.copy(args.icon, os.path.join(work, "logo.icns"))
os.chdir(work)
os.environ["DISTRO"] = args.distro
sys.path.insert(0, os.path.join(asahi, "src"))
sys.argv = [sys.argv[0]]      # upstream reads -v from argv

import util, stub, diskutil, osenum, m1n1   # noqa: E402

real_fsctl = util.fsctl_set_bootable
real_chflags = os.chflags


def rec_fsctl(path, val):
    ops.append(f"fsctl APFSIOC_VOL_BOOTABLE {path} {1 if val else -1}")
    return real_fsctl(path, val)


def rec_chflags(path, flags, *a, **kw):
    ops.append(f"os.chflags {path} 0x{flags:x}")
    return real_chflags(path, flags, *a, **kw)


stub.fsctl_set_bootable = rec_fsctl
util.fsctl_set_bootable = rec_fsctl
os.chflags = rec_chflags


class ImageOnlyDiskUtil(diskutil.DiskUtil):
    def __init__(self):
        super().__init__()
        self.ctnr_by_ref = {}
        self.ctnr_by_store = {}


class NoBputilOSEnum(osenum.OSEnum):
    def bputil(self, *a):
        raise subprocess.CalledProcessError(1, "bputil (refused by the oracle)")


profile = json.load(open(args.profile))["stub"]
ident = profile["identity"]
sysinfo = types.SimpleNamespace(board_id=int(ident["ap_board_id"], 16), chip_id=int(ident["ap_chip_id"], 16),
                                device_class=ident["device_class"], boot_uuid="not-this-container")
prove_image(args.store)
dutil = ImageOnlyDiskUtil()
dutil.get_list()
part = dutil.get_partition_info(args.store, refresh_apfs=True)
names[part.container["ContainerReference"]] = "CONTAINER"
for v in part.container["Volumes"]:
    if v["Roles"] == []:
        names[v["DeviceIdentifier"]] = "DATA"
osinfo = NoBputilOSEnum(sysinfo, dutil, None)
ins = stub.StubInstaller(sysinfo, dutil, osinfo)
ins.load_ipsw(types.SimpleNamespace(version=f'{profile["version"]} ({profile["build"]})', url=args.ipsw or profile["restore_image"]["url"]))
ins.prepare_volume(part)
dutil.get_list()
for v in part.container["Volumes"]:
    r = v["Roles"]
    if len(r) == 1:
        names[v["DeviceIdentifier"]] = r[0].upper()
ins.check_volume()

# copy_admin_users reads the running macOS's Preboot; the oracle gets a fixture in its place
cur_pb = tempfile.mkdtemp(prefix="asahi-oracle-curos-")
os.makedirs(os.path.join(cur_pb, "CUROS", "var/db"))
shutil.copy(args.admin_users, os.path.join(cur_pb, "CUROS", "var/db/AdminUserRecoveryInfo.plist"))
cur_os = types.SimpleNamespace(preboot=cur_pb, vgid="CUROS")
ins.install_files(cur_os)
m1n1.build(args.stage1, ins.boot_obj_path, args.var)   # osinstall.py OSInstaller.install
ops.append("m1n1.build")

osi = ins.osi
with open(args.ops, "w") as f:
    f.write("\n".join(ops) + "\n")
json.dump({"vgid": osi.vgid, "preboot_uuid": osi.preboot_vgid,
           "roots": {"System": osi.system, "Data": osi.data, "Preboot": osi.preboot, "Recovery": osi.recovery},
           "devices": {"System": osi.sys_volume, "Data": osi.data_volume}}, open(args.out, "w"), indent=2, sort_keys=True)
print("oracle done", file=sys.stderr)
