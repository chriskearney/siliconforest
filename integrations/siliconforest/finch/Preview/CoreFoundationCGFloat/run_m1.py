#!/usr/bin/env python3
"""Guarded headless arm64 clients for the Swift CGFloat provider.

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
EVIDENCE = LAB / "runs/preview/retained/cgfloat-corefoundation/evidence"
BUILD = LAB / "runs/preview/retained/cgfloat-corefoundation/build"
Q = "/private/var/db/sfqtp/load-20261118T091237Z"
PROTECTED = "94a07b510d116a7cfb4f302708f1a3ee7286d4be9c94037b77db13dc48959c2f"
FILES = {
    "bin/cgfloat-probe": BUILD / "cgfloat-probe",
    "lib/libswiftCoreFoundation.dylib": BUILD / "libswiftCoreFoundation.dylib",
    "lib/libswiftCoreFoundationBase.dylib": BUILD / "libswiftCoreFoundationBase.dylib",
    "fixtures/document.pdf": LAB / "runs/preview/reading.pdf",
    "fixtures/pixel.png": LAB / "runs/preview/reading-reference-1.png",
    "bin/resource-values-probe": LAB / "runs/preview/app-private/url-resource-values/build/resource-values-probe",
    "lib/libswiftFoundation.dylib": LAB / "runs/preview/app-private/url-resource-values/build/libswiftFoundation.dylib",
    "lib/libswiftUniformTypeIdentifiers.dylib": LAB / "runs/preview/app-private/url-resource-values/build/libswiftUniformTypeIdentifiers.dylib",
    "lib/libswiftos.dylib": LAB / "runs/preview/retained/swift-foundation-cross/os-overlay/packet/lib/libswiftos.dylib",
    "bin/exports-probe": LAB / "runs/preview/app-private/url-resource-values/build/exports-probe",
    "bin/description-probe": LAB / "runs/preview/url-error-wt/runs/error-description/build/probe/description-probe",
    "bin/url-error-probe": LAB / "runs/preview/url-error-wt/runs/url-error/build/probe/url-error-probe",
    "bin/name-probe": LAB / "runs/preview/retained/person-name-components/build/person-name-components-probe",
    "bin/attributed-string-probe": LAB / "runs/preview/app-private/attributed-string/build/attributed-string-probe",
    "bin/calendar-values-probe": LAB / "runs/preview/app-private/calendar-values/build/calendar-values-probe",
    "bin/error-probe": LAB / "runs/preview/app-private/foundation-error-bridge/build/error-probe",
    "bin/data-probe": LAB / "runs/preview/app-private/attributed-string/mapped-data-probe",
    "bin/jsonencoder-probe": LAB / "runs/preview/app-private/jsonencoder/build/jsonencoder-probe",
    "bin/jsondecoder-probe": LAB / "runs/preview/app-private/jsondecoder/build/jsondecoder-probe",
    "bin/uuid-probe": Path("/nix/store/q025lv5j3ddz120rvjrgl4s4vyvaywkq-siliconforest-preview-foundation-uuid-arm64/bin/uuid-probe"),
    "bin/legacy-url-probe": Path("/nix/store/q025lv5j3ddz120rvjrgl4s4vyvaywkq-siliconforest-preview-foundation-uuid-arm64/bin/legacy-url-probe"),
    "prior-exports.tsv": LAB / "runs/preview/app-private/url-resource-values/prior-exports.tsv",
    "lib/libUUIDInteropClient.dylib": Path("/nix/store/q025lv5j3ddz120rvjrgl4s4vyvaywkq-siliconforest-preview-foundation-uuid-arm64/lib/libUUIDInteropClient.dylib"),
}
PROBES = [
    {"name": "cgfloat-probe", "arguments": []},
    {"name": "resource-values-probe", "arguments": ["{root}/fixtures"]},
    {"name": "exports-probe", "arguments": ["{root}/prior-exports.tsv"]},
    {"name": "description-probe", "arguments": []},
    {"name": "url-error-probe", "arguments": []},
    {"name": "name-probe", "arguments": []},
    {"name": "attributed-string-probe", "arguments": []},
    {"name": "calendar-values-probe", "arguments": []},
    {"name": "error-probe", "arguments": []},
    {"name": "data-probe", "arguments": []},
    {"name": "jsonencoder-probe", "arguments": []},
    {"name": "jsondecoder-probe", "arguments": []},
    {"name": "uuid-probe", "arguments": []},
    {"name": "legacy-url-probe", "arguments": []},
]
SSH = [
    "ssh", "-i", "/home/chrisk/.ssh/id_rsa",
    "-o", "IdentitiesOnly=yes",
    "-o", "StrictHostKeyChecking=yes",
    "-o", "UserKnownHostsFile=/home/chrisk/.ssh/known_hosts_m1_siliconforest",
    "-o", "HostKeyAlias=m1-siliconforest",
    "-o", "BatchMode=yes",
    "root@10.1.1.211",
]


def remote(code: str, timeout: int) -> bytes:
    completed = subprocess.run(SSH + ["/opt/homebrew/bin/python3 -"], input=code.encode(), capture_output=True, timeout=timeout)
    if completed.returncode != 0:
        raise SystemExit(completed.stderr.decode())
    return completed.stdout


def main():
    import fcntl
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    remote_root = "/private/var/db/sfpreview-cgfloat/cgfloat-" + stamp
    expected = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in FILES.items()}
    for name, path in FILES.items():
        if name.startswith("bin/") or name.endswith(".dylib"):
            magic, cputype, subtype = struct.unpack_from("<Iii", path.read_bytes())
            if (magic, cputype, subtype) != (0xFEEDFACF, 16777228, 0):
                raise SystemExit("not thin arm64: " + name)
        if name.startswith("bin/") and not (name.endswith("probe") and path.stat().st_mode & 0o111):
            raise SystemExit("probe is not executable: " + name)
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.PAX_FORMAT) as tar:
        for name, path in FILES.items():
            tar.add(path, arcname=name, recursive=False)
    code = r'''from pathlib import Path
import sys,hashlib,json,resource,subprocess,time
r=Path(REMOTE);expected=EXPECTED;config=CONFIG;assert sys.platform=='darwin'
for d in ['home/Library/Preferences','tmp','core','logs','fixtures/folder']: (r/d).mkdir(parents=True,mode=0o700,exist_ok=True)
(r/'fixtures/note.txt').write_text('Owned CGFloat fixture.\n')
base=Path('/private/var/db/sfqtp/load-20261118T091237Z/core/libFoundation.dylib'); (r/'core/libFoundation.dylib').symlink_to(base)
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
probes=[]
for item in config:
 command=[str(r/'bin'/item['name'])]+[v.replace('{root}',str(r)) for v in item.get('arguments',[])]
 start=time.monotonic(); p=subprocess.Popen(command,cwd=r/'home',env=env,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True); signals=[]
 try: o,e=p.communicate(timeout=15)
 except subprocess.TimeoutExpired:
  p.terminate(); signals.append('TERM')
  try: o,e=p.communicate(timeout=3)
  except subprocess.TimeoutExpired: p.kill(); signals.append('KILL'); o,e=p.communicate(timeout=3)
 probes.append({'name':item['name'],'pid':p.pid,'returncode':p.returncode,'signals':signals,'seconds':time.monotonic()-start,'stdout':o.decode(errors='replace'),'stderr':e.decode(errors='replace')})
after=hashes(); protected_after=sha(base)
result={'scope':'Owned headless arm64 CGFloat client and previous Foundation consumers only; no app/window/input/active prefix/shared install','root':str(r),'probes':probes,'before':before,'after':after,'bytes_unchanged':before==after,'protected_before':protected_before,'protected_after':protected_after,'protected_unchanged':protected_before==protected_after,'compositor_before':comp_before,'compositor_after':compositor(),'environment':env}
(r/'logs/result.json').write_text(json.dumps(result,indent=2)); print(json.dumps(result))
'''.replace("REMOTE", repr(remote_root)).replace("EXPECTED", repr(expected)).replace("CONFIG", repr(PROBES)).replace("PROTECTED", repr(PROTECTED))
    guard = "import subprocess;p=subprocess.run(['/opt/homebrew/bin/python3',%r,'guard','60'],env={'PATH':'/usr/bin:/bin','QTP_BUNDLE':%r},capture_output=True,text=True);print(p.stdout,end='');print(p.stderr,end='');assert p.returncode==0" % (Q + "/qtp_m1.py", Q)
    with (LAB / "runs/m1-coord/gui.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        guard_before = remote(guard, 60).decode()
        if "active=0" not in guard_before:
            raise SystemExit(guard_before)
        remote("from pathlib import Path; Path(%r).mkdir(parents=True, mode=0o700)" % str(Path(remote_root).parent), 30)
        transport = "import sys,tarfile,pathlib; root=pathlib.Path(%r); t=tarfile.open(fileobj=sys.stdin.buffer,mode='r|')\nfor m in t:\n assert m.isfile() and not pathlib.PurePosixPath(m.name).is_absolute() and '..' not in pathlib.PurePosixPath(m.name).parts\n p=root/m.name; p.parent.mkdir(parents=True, exist_ok=True); p.write_bytes(t.extractfile(m).read()); p.chmod(m.mode & 0o777)" % remote_root
        uploaded = subprocess.run(SSH + ["/opt/homebrew/bin/python3 -c " + shlex.quote(transport)], input=buf.getvalue(), capture_output=True, timeout=90)
        if uploaded.returncode != 0:
            raise SystemExit(uploaded.stderr.decode())
        result = json.loads(remote(code, 180))
        guard_after = remote(guard, 60).decode()
    if "active=0" not in guard_after:
        raise SystemExit(guard_after)
    source_after = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in FILES.items()}
    result["owner_guard_before"] = guard_before
    result["owner_guard_after"] = guard_after
    result["source_before"] = expected
    result["source_after"] = source_after
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    receipt = EVIDENCE / ("cgfloat-" + stamp + ".json")
    receipt.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({
        "receipt": str(receipt),
        "root": result["root"],
        "probes": [{k: item[k] for k in ("name", "pid", "returncode", "signals")} | {"stdout": item["stdout"].strip().splitlines()[-1:] } for item in result["probes"]],
        "bytes_unchanged": result["bytes_unchanged"],
        "protected": result["protected_unchanged"],
        "compositor": [result["compositor_before"], result["compositor_after"]],
    }, indent=2))
    if not (result["bytes_unchanged"] and result["protected_unchanged"] and result["compositor_before"] == result["compositor_after"] == "125"):
        raise SystemExit("integrity failed")
    if source_after != expected:
        raise SystemExit("local inputs changed")
    for item in result["probes"]:
        if item["returncode"] != 0 or item["signals"]:
            raise SystemExit(item["name"] + " failed")
        if "Symbol not found" in item["stderr"]:
            raise SystemExit(item["name"] + " missing symbol")
    cg = result["probes"][0]
    if "Swift CGFloat metadata and arithmetic passed" not in cg["stdout"]:
        raise SystemExit(cg["stdout"])
    if remote_root + "/lib/libswiftCoreFoundation.dylib" not in cg["stderr"] or remote_root + "/lib/libswiftCoreFoundationBase.dylib" not in cg["stderr"]:
        raise SystemExit("dyld did not log the scratch provider chain")


if __name__ == "__main__":
    main()
