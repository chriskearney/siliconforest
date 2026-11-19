#!/usr/bin/env python3
"""Guarded headless arm64 client for the scoped TipKit provider.

No Preview, AppIntents, window, input, active prefix, or shared install.
"""
import hashlib
import io
import json
import shlex
import struct
import subprocess
import tarfile
from datetime import datetime, timezone
from pathlib import Path

LAB = Path("/home/chrisk/src/darwin-lab")
EVIDENCE = LAB / "runs/preview/retained/tipkit/evidence"
BUILD = LAB / "runs/preview/retained/tipkit/build"
Q = "/private/var/db/sfqtp/load-20261118T091237Z"
PROTECTED = "94a07b510d116a7cfb4f302708f1a3ee7286d4be9c94037b77db13dc48959c2f"
FILES = {
    "bin/tipkit-probe": BUILD / "tipkit-probe",
    "prefix/System/Library/Frameworks/TipKit.framework/Versions/A/TipKit": BUILD / "TipKit",
    "lib/libswiftFoundation.dylib": LAB / "runs/preview/predicate-wt/runs/predicate/build/libswiftFoundation.dylib",
    "lib/libswiftCoreFoundation.dylib": LAB / "runs/preview/retained/cgfloat-corefoundation/build/libswiftCoreFoundation.dylib",
    "lib/libswiftCoreFoundationBase.dylib": LAB / "runs/preview/retained/cgfloat-corefoundation/build/libswiftCoreFoundationBase.dylib",
    "lib/libswiftSwiftOnoneSupport.dylib": Path("/nix/store/1xx6zwsdr41ws0v28156nkmzkbh1y3h7-siliconforest-swift-runtime-6.3.3/usr/lib/swift/libswiftSwiftOnoneSupport.dylib"),
    "lib/libswiftos.dylib": LAB / "runs/preview/retained/swift-foundation-cross/os-overlay/packet/lib/libswiftos.dylib",
    "lib/libswiftObservation.dylib": Path("/nix/store/jj285a5nvzzk36bxc6spdx67km16l7p7-siliconforest-preview-observation-arm64/usr/lib/swift/libswiftObservation.dylib"),
}
PROBE = {"name": "tipkit-probe", "arguments": ["{root}/data"]}
SSH = [
    "ssh", "-i", "/home/chrisk/.ssh/id_rsa",
    "-o", "IdentitiesOnly=yes",
    "-o", "StrictHostKeyChecking=yes",
    "-o", "UserKnownHostsFile=/home/chrisk/.ssh/known_hosts_m1_siliconforest",
    "-o", "HostKeyAlias=m1-siliconforest",
    "-o", "BatchMode=yes",
    "root@10.1.1.211",
]
REQUIRED = [
    "configured-twice ok",
    "donations 2",
    "pro available",
    "closed invalidated",
    "cap invalidated",
    "actions 1",
    "group ordered",
    "predicate comparison true",
    "predicate comparison false",
    "tipkit-scoped-behavior-passed",
]


def remote(code: str, timeout: int) -> bytes:
    completed = subprocess.run(SSH + ["/opt/homebrew/bin/python3 -"], input=code.encode(), capture_output=True, timeout=timeout)
    if completed.returncode != 0:
        raise SystemExit(completed.stderr.decode())
    return completed.stdout


def main():
    import fcntl
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    remote_root = "/private/var/db/sfpreview-tipkit/tipkit-" + stamp
    expected = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in FILES.items()}
    for name, path in FILES.items():
        if name.startswith("bin/") or name.endswith(".dylib") or name.endswith("/TipKit"):
            magic, cputype, subtype = struct.unpack_from("<Iii", path.read_bytes())
            if (magic, cputype, subtype) != (0xFEEDFACF, 16777228, 0):
                raise SystemExit("not thin arm64: " + name)
        if name.startswith("bin/") and not (path.stat().st_mode & 0o111):
            raise SystemExit("probe is not executable: " + name)
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.PAX_FORMAT) as tar:
        for name, path in FILES.items():
            tar.add(path, arcname=name, recursive=False)
    code = r'''from pathlib import Path
import sys,hashlib,json,resource,subprocess,time
r=Path(REMOTE);expected=EXPECTED;config=CONFIG;assert sys.platform=='darwin'
for d in ['home/Library/Preferences','tmp','data','core','logs']: (r/d).mkdir(parents=True,mode=0o700,exist_ok=True)
base=Path('/private/var/db/sfqtp/load-20261118T091237Z/core/libFoundation.dylib')
assert Path('/private/var/run/gpu-desktop/inject').is_dir()
def compositor():
 x=subprocess.run(['pgrep','-x','chonkstep-darwin-desktop.next'],capture_output=True,text=True); assert x.returncode==0; return x.stdout.strip()
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def hashes(): return {n:sha(r/n) for n in expected}
before=hashes(); assert before==expected
protected_before=sha(base); assert protected_before==PROTECTED
comp_before=compositor(); assert comp_before=='125'
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
env={'PATH':'/usr/bin:/bin','HOME':str(r/'home'),'CFFIXED_USER_HOME':str(r/'home'),'TMPDIR':str(r/'tmp')+'/','DYLD_FRAMEWORK_PATH':str(r/'prefix/System/Library/Frameworks')+':/private/var/db/sfqtp/load-20261118T091237Z/prefix/System/Library/Frameworks','DYLD_LIBRARY_PATH':str(r/'lib')+':'+str(r/'core'),'DYLD_PRINT_LIBRARIES':'1'}
item=config
command=[str(r/'bin'/item['name'])]+[v.replace('{root}',str(r)) for v in item.get('arguments',[])]
start=time.monotonic(); p=subprocess.Popen(command,cwd=r/'home',env=env,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True); signals=[]
try: o,e=p.communicate(timeout=15)
except subprocess.TimeoutExpired:
 p.terminate(); signals.append('TERM')
 try: o,e=p.communicate(timeout=3)
 except subprocess.TimeoutExpired: p.kill(); signals.append('KILL'); o,e=p.communicate(timeout=3)
probe={'name':item['name'],'pid':p.pid,'returncode':p.returncode,'signals':signals,'seconds':time.monotonic()-start,'stdout':o.decode(errors='replace'),'stderr':e.decode(errors='replace')}
after=hashes(); protected_after=sha(base)
result={'scope':'Owned headless arm64 TipKit client only; no app/window/input/active prefix/shared install','root':str(r),'probe':probe,'before':before,'after':after,'bytes_unchanged':before==after,'protected_before':protected_before,'protected_after':protected_after,'protected_unchanged':protected_before==protected_after,'compositor_before':comp_before,'compositor_after':compositor(),'environment':env}
(r/'logs/result.json').write_text(json.dumps(result,indent=2)); print(json.dumps(result))
'''.replace("REMOTE", repr(remote_root)).replace("EXPECTED", repr(expected)).replace("CONFIG", repr(PROBE)).replace("PROTECTED", repr(PROTECTED))
    guard = "import subprocess;p=subprocess.run(['/opt/homebrew/bin/python3',%r,'guard','60'],env={'PATH':'/usr/bin:/bin','QTP_BUNDLE':%r},capture_output=True,text=True);print(p.stdout,end='');print(p.stderr,end='');assert p.returncode==0" % (Q + "/qtp_m1.py", Q)
    with (LAB / "runs/m1-coord/gui.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        guard_before = remote(guard, 90).decode()
        if "active=0" not in guard_before:
            raise SystemExit(guard_before)
        remote("from pathlib import Path; Path(%r).mkdir(parents=True, mode=0o700, exist_ok=True)" % str(Path(remote_root).parent), 30)
        transport = "import sys,tarfile,pathlib; root=pathlib.Path(%r); t=tarfile.open(fileobj=sys.stdin.buffer,mode='r|')\nfor m in t:\n assert m.isfile() and not pathlib.PurePosixPath(m.name).is_absolute() and '..' not in pathlib.PurePosixPath(m.name).parts\n p=root/m.name; p.parent.mkdir(parents=True, exist_ok=True); p.write_bytes(t.extractfile(m).read()); p.chmod(m.mode & 0o777)" % remote_root
        uploaded = subprocess.run(SSH + ["/opt/homebrew/bin/python3 -c " + shlex.quote(transport)], input=buf.getvalue(), capture_output=True, timeout=90)
        if uploaded.returncode != 0:
            raise SystemExit(uploaded.stderr.decode())
        result = json.loads(remote(code, 180))
        guard_after = remote(guard, 90).decode()
    if "active=0" not in guard_after:
        raise SystemExit(guard_after)
    source_after = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in FILES.items()}
    result["owner_guard_before"] = guard_before
    result["owner_guard_after"] = guard_after
    result["source_before"] = expected
    result["source_after"] = source_after
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    receipt = EVIDENCE / ("tipkit-" + stamp + ".json")
    receipt.write_text(json.dumps(result, indent=2) + "\n")
    probe = result["probe"]
    print(json.dumps({
        "receipt": str(receipt),
        "root": result["root"],
        "pid": probe["pid"],
        "returncode": probe["returncode"],
        "signals": probe["signals"],
        "stdout": probe["stdout"].strip().splitlines(),
        "bytes_unchanged": result["bytes_unchanged"],
        "protected": result["protected_unchanged"],
        "compositor": [result["compositor_before"], result["compositor_after"]],
    }, indent=2))
    if not (result["bytes_unchanged"] and result["protected_unchanged"] and result["compositor_before"] == result["compositor_after"] == "125"):
        raise SystemExit("integrity failed")
    if source_after != expected:
        raise SystemExit("local inputs changed")
    if probe["returncode"] != 0 or probe["signals"]:
        sys_err = probe["stderr"]
        raise SystemExit(probe["name"] + " failed\n" + probe["stdout"] + "\n" + sys_err[-4000:])
    if "Symbol not found" in probe["stderr"] or "Library not loaded" in probe["stderr"]:
        raise SystemExit(probe["stderr"][-4000:])
    for line in REQUIRED:
        if line not in probe["stdout"]:
            raise SystemExit("missing stdout line " + line + "\n" + probe["stdout"])
    scratch = remote_root + "/prefix/System/Library/Frameworks/TipKit.framework/Versions/A/TipKit"
    if scratch not in probe["stderr"]:
        raise SystemExit("dyld did not log the scratch TipKit image")


if __name__ == "__main__":
    main()
