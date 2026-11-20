#!/usr/bin/env python3
"""Link the validated CGFloat object into libswiftCoreFoundation.

The public dylib keeps the live install name, compatibility version, and
current version. It reexports the exact runtime image under a different
leaf, and it links the exact CGFloat.o that defines CGFloatVMn.
"""
import hashlib
import json
import shutil
import struct
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
LAB = Path("/home/chrisk/src/darwin-lab")
OBJECT = LAB / "runs/preview/retained/swift-foundation-cross/cgfloat/CGFloat.o"
RUNTIME = Path("/nix/store/1xx6zwsdr41ws0v28156nkmzkbh1y3h7-siliconforest-swift-runtime-6.3.3/usr/lib/swift/libswiftCoreFoundation.dylib")
OUT = LAB / "runs/preview/retained/cgfloat-corefoundation/build"
CLANG = "/nix/store/p8x57y0mi788srcls95cpcf2nbjz6la8-darwin-cross-toolchain-nix/bin/arm64-apple-darwin20.4-clang"
LD = "/nix/store/ikix61c2brfm9cf9f4pwdh80mhy1f2xp-siliconforest-native-ld-0.1/bin/ld"
NM = "/nix/store/v0x4y2cjbasgmrqsbka2bp8allw8j9ph-darwin-cross-toolchain-nix/bin/arm64-apple-darwin20.4-nm"
INSTALL_NAME_TOOL = "/nix/store/v0x4y2cjbasgmrqsbka2bp8allw8j9ph-darwin-cross-toolchain-nix/bin/arm64-apple-darwin20.4-install_name_tool"
SDK = "/nix/store/72ya6fb76jqznykdp5f72zh6951j1xkn-siliconforest-preview-foundation-url-arm64/compiler-sdk"
LIBSYSTEM = "/nix/store/qxkrrfhc2anc1zl8qv9gkr0856ra4f42-siliconforest-libsystem-0.1"
SWIFT_LIB = "/nix/store/1xx6zwsdr41ws0v28156nkmzkbh1y3h7-siliconforest-swift-runtime-6.3.3/usr/lib/swift"
OBJECT_SHA = "8c55d9502164710e6192c3f720abb67869b2f3aa8bb4f49d86f00a96e7747ffb"
RUNTIME_SHA = "5cc34db69a4d67170cf5ab4dee8f0ec857ec64c9ff365ee2d0b4c67d03813f1e"
SOURCE_SHA = "61d4b0b7bac4c0695b0a485a3d70bb18f5009920e0ebb740b9acb7c0ae47fe28"
PUBLIC_ID = "/usr/lib/swift/libswiftCoreFoundation.dylib"
BASE_ID = "/usr/lib/swift/libswiftCoreFoundationBase.dylib"
RUNTIME_UUID = "24560dfea6d33b95b19bfdb809705f24"
OLD = [
    "__swift_FORCE_LOAD_$_swiftCoreFoundation",
    "_$s14CoreFoundation9_CFObjectMp",
    "_$s14CoreFoundation9_CFObjectPAAE2eeoiySbx_xtFZ",
    "_$s14CoreFoundation9_CFObjectPAAE4hash4intoys6HasherVz_tF",
    "_$s14CoreFoundation9_CFObjectPAAE9hashValueSivg",
    "_$s14CoreFoundation9_CFObjectPAAE9hashValueSivpMV",
    "_$s14CoreFoundation9_CFObjectPSHTb",
    "_$s14CoreFoundation9_CFObjectTL",
]
VMN = "_$s12CoreGraphics7CGFloatVMn"
MUL = "_$s12CoreGraphics7CGFloatV1moiyA2C_ACtFZ"
SUB = "_$s12CoreGraphics7CGFloatV1soiyA2C_ACtFZ"
PROBE_BINDS = OLD + [VMN, MUL, SUB]
LC_ID = 0xD
LC_LOAD = 0xC
LC_WEAK = 0x80000018
LC_REEXPORT = 0x8000001F
LC_UUID = 0x1B
LC_DYLD_INFO = 0x22
LC_DYLD_INFO_ONLY = 0x80000022
LC_DYLD_EXPORTS_TRIE = 0x80000033


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def uleb(data: bytes, index: int):
    result = 0
    shift = 0
    while True:
        byte = data[index]
        index += 1
        result |= (byte & 0x7F) << shift
        if byte < 0x80:
            return result, index
        shift += 7


def parse_trie(data: bytes, start: int = 0, prefix: bytes = b""):
    index = start
    term_size, index = uleb(data, index)
    term = index
    index += term_size
    nedges, index = uleb(data, index)
    edges = []
    for _ in range(nedges):
        end = data.index(b"\0", index)
        label = data[index:end]
        index = end + 1
        child, index = uleb(data, index)
        edges.append((label, child))
    found = []
    if term_size:
        flags, cursor = uleb(data, term)
        info = {"flags": flags}
        if flags & 0x08:
            library, cursor = uleb(data, cursor)
            end = data.index(b"\0", cursor)
            info["import"] = data[cursor:end].decode()
            info["lib"] = library
        else:
            addr, cursor = uleb(data, cursor)
            info["addr"] = addr
        found.append((prefix.decode(), info))
    for label, child in edges:
        found.extend(parse_trie(data, child, prefix + label))
    return found


def load_commands(blob: bytes):
    magic, _, _, _, ncmds, _, _ = struct.unpack_from("<IiiIIII", blob, 0)
    if magic != 0xFEEDFACF:
        raise SystemExit(f"not a 64-bit Mach-O: {magic:#x}")
    offset = 32
    commands = []
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", blob, offset)
        commands.append((cmd, cmdsize, offset, blob[offset : offset + cmdsize]))
        offset += cmdsize
    return commands


def dylib_name(raw: bytes) -> str:
    nameoff = struct.unpack_from("<I", raw, 8)[0]
    return raw[nameoff:].split(b"\0", 1)[0].decode()


def versions(raw: bytes):
    return struct.unpack_from("<III", raw, 12)


def export_trie(blob: bytes) -> dict:
    for cmd, _, offset, _ in load_commands(blob):
        if cmd in (LC_DYLD_INFO, LC_DYLD_INFO_ONLY):
            export_off, export_size = struct.unpack_from("<II", blob, offset + 40)
            data = blob[export_off : export_off + export_size]
            return {name: info for name, info in parse_trie(data)}
        if cmd == LC_DYLD_EXPORTS_TRIE:
            export_off, export_size = struct.unpack_from("<II", blob, offset + 8)
            data = blob[export_off : export_off + export_size]
            return {name: info for name, info in parse_trie(data)}
    raise SystemExit("no export trie")


def uuid_of(blob: bytes) -> str:
    for cmd, _, _, raw in load_commands(blob):
        if cmd == LC_UUID:
            return raw[8:24].hex()
    raise SystemExit("no uuid")


def id_command(blob: bytes):
    for cmd, cmdsize, offset, raw in load_commands(blob):
        if cmd == LC_ID:
            return cmdsize, offset, raw
    raise SystemExit("no install name")


def require(condition: bool, message: str):
    if not condition:
        raise SystemExit(message)


def check_pins():
    recorded = json.loads((HERE / "sources.json").read_text())
    require(recorded["object"]["sha256"] == OBJECT_SHA, "sources.json object hash drifted")
    require(recorded["runtime"]["sha256"] == RUNTIME_SHA, "sources.json runtime hash drifted")
    require(recorded["source"]["sha256"] == SOURCE_SHA, "sources.json source hash drifted")
    require(recorded["base_install_name"] == BASE_ID, "sources.json base id drifted")
    require(sha256(OBJECT) == OBJECT_SHA, f"CGFloat.o is not {OBJECT_SHA}")
    require(sha256(RUNTIME) == RUNTIME_SHA, f"runtime dylib is not {RUNTIME_SHA}")
    require(sha256(HERE / "CGFloat.swift") == SOURCE_SHA, "tree CGFloat.swift is not the Finch overlay")
    require(len(BASE_ID) == 47, "base install name no longer fits the 48-byte id slot")
    require(len(recorded["same_provider_imports"]) == 1, "import audit is no longer one symbol")
    require(recorded["same_provider_imports"][0]["name"] == VMN, "import audit symbol changed")


def assert_base_is_runtime_with_new_leaf(runtime: bytes, copied: bytes):
    require(len(runtime) == len(copied), "base size changed")
    require(uuid_of(runtime) == uuid_of(copied) == RUNTIME_UUID, "base uuid changed")
    _, offset, raw = id_command(runtime)
    nameoff = struct.unpack_from("<I", raw, 8)[0]
    slot_start = offset + nameoff
    slot_end = offset + len(raw)
    diffs = [index for index, (left, right) in enumerate(zip(runtime, copied)) if left != right]
    require(diffs, "install name was not rewritten")
    require(min(diffs) >= slot_start and max(diffs) < slot_end, f"base differs outside the install-name slot: {diffs[:8]}")
    require(dylib_name(id_command(copied)[2]) == BASE_ID, "base install name mismatch")
    require(versions(id_command(runtime)[2]) == versions(id_command(copied)[2]), "base versions changed")


def link_wrapper(base: Path, wrapper: Path):
    names = wrapper.parent / "reexports.txt"
    names.write_text("".join(name + "\n" for name in OLD))
    if wrapper.exists():
        wrapper.unlink()
    command = [
        CLANG, "-dynamiclib", str(OBJECT),
        f"--ld-path={LD}", "-nostdlib", "-isysroot", SDK,
        "-L", f"{LIBSYSTEM}/usr/lib", "-L", SWIFT_LIB,
        "-Wl,-reexport_library," + str(base),
        "-Wl,-reexported_symbols_list," + str(names),
        "-lswiftDarwin", "-lswiftDispatch", "-lswiftObjectiveC", "-lswiftCore", "-lSystem",
        f"-Wl,-dylib_file,/usr/lib/system/libdyld.dylib:{LIBSYSTEM}/usr/lib/system/libdyld.dylib",
        "-Wl,-platform_version,macos,26.5,26.5",
        "-Wl,-install_name," + PUBLIC_ID,
        "-Wl,-compatibility_version,1.0.0",
        "-Wl,-current_version,0.0.0",
        "-o", str(wrapper),
    ]
    proc = subprocess.run(command, text=True, capture_output=True)
    sys.stderr.write(proc.stderr)
    require(proc.returncode == 0, "link failed")


def check_wrapper(blob: bytes, runtime: bytes):
    kind = {}
    for cmd, _, _, raw in load_commands(blob):
        if cmd in (LC_ID, LC_LOAD, LC_WEAK, LC_REEXPORT):
            kind.setdefault(cmd, []).append(dylib_name(raw))
    require(kind[LC_ID] == [PUBLIC_ID], f"public id {kind.get(LC_ID)}")
    require(kind[LC_REEXPORT] == [BASE_ID], f"reexport {kind.get(LC_REEXPORT)}")
    require(versions(id_command(blob)[2]) == versions(id_command(runtime)[2]) == (1, 0, 65536), "version mismatch")
    trie = export_trie(blob)
    missing = [name for name in OLD if name not in trie]
    require(not missing, f"lost exports {missing}")
    for name in OLD:
        info = trie[name]
        require(info.get("flags", 0) & 0x08, f"{name} is not a reexport")
        require(info.get("lib") == 1, f"{name} reexport ordinal {info.get('lib')}")
    require(VMN in trie and trie[VMN].get("flags", 0) & 0x08 == 0, "CGFloatVMn is not defined here")
    runtime_trie = export_trie(runtime)
    require(set(runtime_trie) == set(OLD), "runtime export set is no longer the live eight")
    return trie


def bind_records(blob: bytes):
    dylibs = []
    info = None
    for cmd, _, offset, raw in load_commands(blob):
        if cmd in (LC_DYLD_INFO, LC_DYLD_INFO_ONLY):
            info = struct.unpack_from("<IIIIIIIIII", blob, offset + 8)
        if cmd in (LC_LOAD, LC_WEAK, LC_REEXPORT):
            dylibs.append(dylib_name(raw))
    require(info is not None, "probe has no bind info")
    _, _, bind_off, bind_size, weak_off, weak_size, lazy_off, lazy_size, _, _ = info

    def parse(chunk: bytes):
        index = 0
        ordinal = 0
        symbol = None
        found = []
        while index < len(chunk):
            op = chunk[index]
            index += 1
            imm = op & 0x0F
            opcode = op & 0xF0
            if op == 0:
                continue
            if opcode == 0x10:
                ordinal = imm
            elif opcode == 0x20:
                ordinal, index = uleb(chunk, index)
            elif opcode == 0x30:
                ordinal = imm
            elif opcode == 0x40:
                end = chunk.index(0, index)
                symbol = chunk[index:end].decode()
                index = end + 1
            elif opcode == 0x60:
                while True:
                    byte = chunk[index]
                    index += 1
                    if byte < 0x80:
                        break
            elif opcode == 0x70 or opcode == 0x80:
                _, index = uleb(chunk, index)
            elif opcode == 0x90:
                found.append((ordinal, symbol))
            elif opcode == 0xA0:
                found.append((ordinal, symbol))
                _, index = uleb(chunk, index)
            elif opcode == 0xB0:
                found.append((ordinal, symbol))
            elif opcode == 0xC0:
                count, index = uleb(chunk, index)
                _, index = uleb(chunk, index)
                found.extend([(ordinal, symbol)] * count)
            elif opcode in (0x50,):
                continue
            else:
                raise SystemExit(f"unknown bind opcode {op:#x}")
        return found

    binds = parse(blob[bind_off:bind_off + bind_size])
    binds += parse(blob[lazy_off:lazy_off + lazy_size])
    binds += parse(blob[weak_off:weak_off + weak_size])
    return dylibs, binds


def link_probe(wrapper: Path):
    probe_o = wrapper.parent / "cgfloat-probe.o"
    probe = wrapper.parent / "cgfloat-probe"
    subprocess.run(
        [CLANG, "-c", "-target", "arm64-apple-macosx26.5", "-isysroot", SDK, "-O2",
         "-o", str(probe_o), str(HERE / "probe.c")],
        check=True,
    )
    if probe.exists():
        probe.unlink()
    proc = subprocess.run(
        [CLANG, str(probe_o), f"--ld-path={LD}", "-nostdlib", "-isysroot", SDK,
         "-L", str(wrapper.parent), "-L", f"{LIBSYSTEM}/usr/lib", "-L", SWIFT_LIB,
         "-lswiftCoreFoundation", "-lSystem",
         f"-Wl,-dylib_file,/usr/lib/system/libdyld.dylib:{LIBSYSTEM}/usr/lib/system/libdyld.dylib",
         "-Wl,-platform_version,macos,26.5,26.5", "-o", str(probe)],
        text=True, capture_output=True,
    )
    sys.stderr.write(proc.stderr)
    require(proc.returncode == 0, "probe link failed")
    dylibs, binds = bind_records(probe.read_bytes())
    require(dylibs[0] == PUBLIC_ID, f"probe first dependency is {dylibs[:2]}")
    bound = {symbol: ordinal for ordinal, symbol in binds}
    missing = [name for name in PROBE_BINDS if bound.get(name) != 1]
    require(not missing, f"probe symbols not bound to the public dylib: {missing}")
    magic, cputype, cpusubtype = struct.unpack_from("<Iii", probe.read_bytes())
    require((magic, cputype, cpusubtype) == (0xFEEDFACF, 16777228, 0), "probe is not thin arm64")


def main():
    check_pins()
    OUT.mkdir(parents=True, exist_ok=True)
    runtime = RUNTIME.read_bytes()
    base = OUT / "libswiftCoreFoundationBase.dylib"
    if base.exists():
        base.unlink()
    shutil.copyfile(RUNTIME, base)
    base.chmod(0o755)
    subprocess.run([INSTALL_NAME_TOOL, "-id", BASE_ID, str(base)], check=True)
    assert_base_is_runtime_with_new_leaf(runtime, base.read_bytes())
    require(sha256(RUNTIME) == RUNTIME_SHA, "runtime file changed while rewriting the base copy")
    wrapper = OUT / "libswiftCoreFoundation.dylib"
    link_wrapper(base, wrapper)
    trie = check_wrapper(wrapper.read_bytes(), runtime)
    link_probe(wrapper)
    print(json.dumps({
        "wrapper": sha256(wrapper),
        "wrapper_size": wrapper.stat().st_size,
        "base": sha256(base),
        "base_size": base.stat().st_size,
        "probe": sha256(OUT / "cgfloat-probe"),
        "exports": len(trie),
        "old": len(OLD),
        "vmn": VMN in trie,
        "install_name": PUBLIC_ID,
        "base_install_name": BASE_ID,
        "versions": [1, 0, 65536],
    }, indent=2))


if __name__ == "__main__":
    main()
