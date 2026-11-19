#!/usr/bin/env python3
"""Compile the Map source and keep the log when swiftc stops.

Attempt A uses the P13 SwiftUI subset module and the local Cocotron AppKit
headers. Attempt B points -F at the M6 SwiftUI dylibs, which have no
swiftmodule on this host. Nothing is installed on the Preview framework path.
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
LAB = Path("/home/chrisk/src/darwin-lab")
RETAINED = LAB / "runs/preview/retained/mapkit"
OUT = RETAINED / "build"
CACHE = RETAINED / "module-cache"
LOG = RETAINED / "compile-001.log"
GEOJSON = RETAINED / "ne_110m_land.geojson"
GEOJSON_SHA = "9e0729ee253ca7d7a5c4ae9395fb1902264c5377c52e224d13dd85010e2835d9"
SWIFTC = "/nix/store/bni7djh2akv2x23pk86bgqj95xhxlgja-swift-toolchain-6.3.3/bin/swiftc"
CLANG = "/nix/store/p8x57y0mi788srcls95cpcf2nbjz6la8-darwin-cross-toolchain-nix/bin/arm64-apple-darwin20.4-clang"
LD = "/nix/store/ikix61c2brfm9cf9f4pwdh80mhy1f2xp-siliconforest-native-ld-0.1/bin/ld"
NM = "/nix/store/v0x4y2cjbasgmrqsbka2bp8allw8j9ph-darwin-cross-toolchain-nix/bin/arm64-apple-darwin20.4-nm"
LIBSYSTEM = Path("/nix/store/qxkrrfhc2anc1zl8qv9gkr0856ra4f42-siliconforest-libsystem-0.1")
LIBOBJC = Path("/nix/store/w5092y706fszhrkwpcf4v2c62hrrc6y3-siliconforest-libobjc-1")
FOUNDATION_LIB = Path("/nix/store/f81yl12wpld3d9xh1qa4v2k87sfaj6pb-siliconforest-foundation-1")
SWIFT_LIB = Path("/nix/store/1xx6zwsdr41ws0v28156nkmzkbh1y3h7-siliconforest-swift-runtime-6.3.3/usr/lib/swift")
AUDIT = LAB / "runs/preview/app-private/p13/projected-audit.json"
EXPECTED = [
    "_$s15_MapKit_SwiftUI0A0V6bounds16interactionModes5scope7contentACyAA0A11ContentViewVys5NeverOqd__GGAA0A12CameraBoundsVSg_AA0a11InteractionG0V0cD09NamespaceV2IDVSgqd__yXEtcALRszAA0aJ0Rd__lufC",
    "_$s15_MapKit_SwiftUI0A12CameraBoundsVMa",
    "_$s15_MapKit_SwiftUI0A16InteractionModesV3allACvgZ",
    "_$s15_MapKit_SwiftUI0A16InteractionModesVMa",
    "_$s15_MapKit_SwiftUI6MarkerV_10coordinateACy0cD04TextVGAE18LocalizedStringKeyV_So22CLLocationCoordinate2DVtcAGRszrlufC",
    "_$s15_MapKit_SwiftUI6MarkerVyxGAA0A7ContentAAMc",
    "_$s15_MapKit_SwiftUI0A0VMn",
    "_$s15_MapKit_SwiftUI0A11ContentViewVMn",
    "_$s15_MapKit_SwiftUI6MarkerVMn",
    "_$s15_MapKit_SwiftUI0A12CameraBoundsVMn",
]
SDK = Path("/nix/store/72ya6fb76jqznykdp5f72zh6951j1xkn-siliconforest-preview-foundation-url-arm64/compiler-sdk")
DEV = Path("/nix/store/qd81f2xxrfrig8p3s1bijsyfjpc95r6k-siliconforest-swift-runtime-6.3.3-dev/usr/lib/swift")
RESOURCE = Path("/nix/store/sk8w4a68hamxyy3dac93qffkp68d2nrc-siliconforest-finch-swift-cross-sysroot/resource")
CG_INCLUDE = Path("/nix/store/2p4xgkniqff2d87mnwxaq4d948g0gx5f-siliconforest-coregraphics-0.1/usr/include/CoreGraphics")
CG_UMBRELLA = Path("/nix/store/2p4xgkniqff2d87mnwxaq4d948g0gx5f-siliconforest-coregraphics-0.1/System/Library/Frameworks/CoreGraphics.framework/Versions/A/Headers/CoreGraphics.h")
APPKIT = Path("/nix/store/zn9fyhvg09d9dpzy803nm026d0jgyz4c-AppKit")
APP_SERVICES = Path("/nix/store/v52809lhqzinnyck597vqigswi274m87-ApplicationServices/ApplicationServices.h")
CORETEXT = Path("/nix/store/24lfg30rvacrgmr9pakls7c6ya1hj828-CoreText")
SF = LAB / "runs/preview/retained/swift-foundation-cross"
SCR = LAB / "runs/preview/app-private/url-resource-values"
SWIFTUI_SRC = LAB / "runs/qtp/closure/prefix/System/Library/Frameworks/SwiftUI.framework/Versions/A/Resources/Source/c0skbmlfgqf09kvj73iq8d5spfmrv1sb-SwiftUI.swift"
CGFLOAT_SRC = LAB / "runs/qtp/closure/prefix/System/Library/Frameworks/SwiftUI.framework/Versions/A/Resources/Source/CGFloat.swift"
M6 = LAB / "runs/preview/retained/swiftui-m6/output"
MODULES = OUT / "modules"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def common(module_maps):
    flags = [
        SWIFTC, "-target", "arm64-apple-macosx26.5", "-sdk", str(SDK),
        "-resource-dir", str(RESOURCE),
        "-I", str(OUT), "-I", str(SCR / "build"),
        "-I", str(SDK.parent / "usr/lib/swift"), "-I", str(DEV),
        "-Xcc", f"-fmodule-map-file={DEV}/shims/module.modulemap",
        "-Xcc", f"-fmodule-map-file={SCR}/overlay/cross.modulemap",
        "-Xcc", f"-I{CG_INCLUDE.parent}", "-Xcc", "-DXNU_PLATFORM_MacOSX=1", "-Xcc", "-U__OPTIMIZE__",
        "-Xfrontend", "-disable-objc-attr-requires-foundation-module",
        "-parse-as-library", "-swift-version", "5", "-Onone",
        "-runtime-compatibility-version", "none",
        "-I", str(LAB / "runs/preview/app-private/calendar-values/include"),
        "-I", str(SF / "collections"),
        "-I", str(LAB / "runs/preview/app-private/attributed-string/include"),
        "-I", "/nix/store/q025lv5j3ddz120rvjrgl4s4vyvaywkq-siliconforest-preview-foundation-uuid-arm64/include",
        "-I", str(SF / "shims"), "-Xcc", f"-I{SF}/shims", "-Xcc", f"-I{SF}/c-fixes",
        "-Xcc", "-fapinotes", "-Xcc", "-iapinotes-modules", "-Xcc", str(SF / "data-impl"),
        "-vfsoverlay", str(SF / "data-impl/nsrange-overlay.json"),
        "-Xcc", "-ivfsoverlay", "-Xcc", str(SF / "data-impl/nsrange-overlay.json"),
        "-vfsoverlay", str(SCR / "overlay/foundation-overlay.json"),
        "-Xcc", "-ivfsoverlay", "-Xcc", str(SCR / "overlay/foundation-overlay.json"),
        "-I", str(SF / "os-overlay"), "-I", str(SF / "os-headers"),
        "-I", str(LAB / "runs/preview/retained/foundation-source/Sources/_FoundationCShims/include"),
        "-module-cache-path", str(CACHE),
        "-Xcc", f"-I{OUT / 'include'}",
    ]
    for module_map in module_maps:
        flags.extend(["-Xcc", f"-fmodule-map-file={module_map}"])
    return flags


def run(cmd, env):
    completed = subprocess.run(cmd, text=True, capture_output=True, env=env)
    return completed.returncode, completed.stdout, completed.stderr


def link_headers():
    include = OUT / "include"
    if include.exists():
        shutil.rmtree(include)
    appkit = include / "AppKit"
    appkit.mkdir(parents=True)
    for header in APPKIT.rglob("*.h"):
        dest = appkit / header.name
        if not dest.exists():
            dest.symlink_to(header)
    services = include / "ApplicationServices"
    services.mkdir()
    (services / "ApplicationServices.h").symlink_to(APP_SERVICES)
    coretext = include / "CoreText"
    coretext.mkdir()
    for header in CORETEXT.glob("*.h"):
        (coretext / header.name).symlink_to(header)
    coregraphics = include / "CoreGraphics"
    coregraphics.mkdir()
    for header in CG_INCLUDE.glob("*.h"):
        (coregraphics / header.name).symlink_to(header)
    if not (coregraphics / "CoreGraphics.h").exists():
        (coregraphics / "CoreGraphics.h").symlink_to(CG_UMBRELLA)


def write_modules():
    MODULES.mkdir(parents=True, exist_ok=True)
    (MODULES / "AppKitMapUmbrella.h").write_text(
        "#import <AppKit/NSView.h>\n"
        "#import <AppKit/NSBezierPath.h>\n"
        "#import <AppKit/NSGraphicsContext.h>\n"
        "#import <AppKit/NSColor.h>\n"
    )
    (MODULES / "CLCoordinate.h").write_text(
        "typedef double CLLocationDegrees;\n"
        "typedef double CLLocationDistance;\n"
        "typedef struct {\n"
        "    CLLocationDegrees latitude;\n"
        "    CLLocationDegrees longitude;\n"
        "} CLLocationCoordinate2D;\n"
    )
    (MODULES / "module.modulemap").write_text(
        "module AppKit {\n"
        "  header \"AppKitMapUmbrella.h\"\n"
        "  export *\n"
        "}\n"
        "module CoreLocation {\n"
        "  header \"CLCoordinate.h\"\n"
        "  export *\n"
        "}\n"
        "module ApplicationServices {\n"
        "  header \"ApplicationServices.h\"\n"
        "  export *\n"
        "}\n"
        "module CoreText {\n"
        "  umbrella \"CoreText\"\n"
        "  export *\n"
        "}\n"
    )
    (MODULES / "ApplicationServices.h").symlink_to(APP_SERVICES) if not (MODULES / "ApplicationServices.h").exists() else None
    coretext = MODULES / "CoreText"
    if coretext.exists():
        shutil.rmtree(coretext)
    coretext.mkdir()
    for header in CORETEXT.glob("*.h"):
        (coretext / header.name).symlink_to(header)
    (MODULES / "CoreGraphics.modulemap").write_text(
        "module CoreGraphics [system] {\n"
        f"  umbrella \"{OUT / 'include' / 'CoreGraphics'}\"\n"
        "  export *\n"
        "}\n"
    )


def write_embed():
    digest = sha256(GEOJSON)
    if digest != GEOJSON_SHA:
        raise SystemExit(f"geojson pin changed: {digest}")
    text = GEOJSON.read_text()
    if '#"""' in text or '"""#' in text:
        raise SystemExit("geojson contains a raw-string terminator")
    generated = OUT / "EmbeddedLand.swift"
    generated.write_text(
        "// Generated by build.py from ne_110m_land.geojson\n"
        f"// SHA-256 {digest}\n"
        "func embeddedNaturalEarthLandGeoJSON() -> String {\n"
        "    #\"\"\"\n"
        f"{text}\n"
        "    \"\"\"#\n"
        "}\n"
    )
    return generated


def section(title, code, stdout, stderr, command):
    return (
        f"\n===== {title} exit {code} =====\n"
        f"$ {' '.join(command)}\n\n"
        "--- stdout ---\n"
        f"{stdout}\n"
        "--- stderr ---\n"
        f"{stderr}\n"
    )


def link_probe(obj, output):
    cmd = [
        CLANG, "-o", str(output), str(obj),
        "--ld-path=" + LD, "-nostdlib", "-isysroot", str(SDK),
        "-L" + str(LIBSYSTEM / "usr/lib"),
        "-L" + str(LIBOBJC / "usr/lib"),
        "-L" + str(FOUNDATION_LIB / "usr/lib"),
        "-L" + str(SWIFT_LIB),
        "-lFoundation", "-lobjc", "-lSystem",
        "-lswiftCoreFoundation", "-lswiftObjectiveC", "-lswiftDarwin",
        "-lswiftCore", "-lswiftDispatch", "-lswift_Concurrency",
        "-Wl,-dylib_file,/usr/lib/system/libdyld.dylib:" + str(LIBSYSTEM / "usr/lib/system/libdyld.dylib"),
        "-Wl,-platform_version,macos,26.5,26.5",
    ]
    return cmd


def defined_symbols(path: Path):
    code, stdout, stderr = run([NM, "-g", str(path)], dict(os.environ))
    names = set()
    for line in stdout.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[-2] in {"T", "S", "D", "B"}:
            name = parts[-1]
            names.add(name if name.startswith("_") else "_" + name)
    return code, names, stderr


def abi_report(obj: Path):
    found = []
    def walk(node):
        if isinstance(node, dict):
            library = node.get("library")
            symbols = node.get("symbols")
            if isinstance(library, str) and library.endswith("/_MapKit_SwiftUI") and isinstance(symbols, list):
                found.append(symbols)
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)
    walk(json.loads(AUDIT.read_text()))
    audit = found[0] if len(found) == 1 else None
    lines = ["\n===== ABI =====\n"]
    if audit is None:
        lines.append("audit did not contain one _MapKit_SwiftUI symbol list\n")
    else:
        lines.append(f"audit count {len(audit)} matches expected {audit == EXPECTED}\n")
    if not obj.exists():
        lines.append(f"{obj.name} absent; none of the 10 binds were emitted\n")
        for name in EXPECTED:
            lines.append(f"absent {name}\n")
        return "".join(lines)
    code, names, stderr = defined_symbols(obj)
    lines.append(f"nm exit {code}\n{stderr}\n")
    for name in EXPECTED:
        lines.append(("present " if name in names else "absent ") + name + "\n")
    extra = sorted(name for name in names if "_MapKit_SwiftUI" in name and name not in EXPECTED)
    lines.append(f"other _MapKit_SwiftUI symbols {len(extra)}\n")
    for name in extra:
        lines.append(f"extra {name}\n")
    return "".join(lines)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    CACHE.mkdir(parents=True, exist_ok=True)
    link_headers()
    write_modules()
    embed = write_embed()
    env = dict(os.environ)
    env["DARWIN_SDK_ROOT"] = str(SDK)
    parts = [
        "compile-001\n",
        "Host swiftc is the Linux cross compiler. It has no M6 SwiftUI swiftmodule.\n",
        "Attempt A compiles against the P13 SwiftUI subset module.\n",
        "Attempt B uses -F on the M6 dylib directory and does not see that subset.\n",
        "No framework is installed at /System/Library/Frameworks/_MapKit_SwiftUI.framework.\n",
        f"GeoJSON SHA-256 {sha256(GEOJSON)}\n",
    ]
    (OUT / "SwiftUI.swiftmodule").mkdir(exist_ok=True)
    geo = common([MODULES / "module.modulemap"]) + [
        "-wmo", "-O",
        "-c", "-emit-object", "-o", str(OUT / "mapkit-geo-probe.o"),
        "-module-name", "MapKitGeoProbe",
        str(HERE / "Geo.swift"), str(HERE / "probe.swift"), str(embed),
    ]
    geo_code, geo_out, geo_err = run(geo, env)
    parts.append(section("G Geo semantic probe object", geo_code, geo_out, geo_err, geo))
    LOG.write_text("".join(parts))
    if geo_code == 0:
        probe_link = link_probe(OUT / "mapkit-geo-probe.o", OUT / "mapkit-geo-probe")
        link_code, link_out, link_err = run(probe_link, env)
        parts.append(section("G link private mapkit-geo-probe", link_code, link_out, link_err, probe_link))
        LOG.write_text("".join(parts))
    subset = common([MODULES / "module.modulemap"]) + [
        "-wmo", "-enable-library-evolution",
        "-emit-module", "-emit-module-path", str(OUT / "SwiftUI.swiftmodule/arm64-apple-macos.swiftmodule"),
        "-emit-object", "-o", str(OUT / "SwiftUI-module-only.o"),
        "-module-name", "SwiftUI",
        str(SWIFTUI_SRC), str(CGFLOAT_SRC),
    ]
    code, stdout, stderr = run(subset, env)
    parts.append(section("A0 P13 SwiftUI subset module", code, stdout, stderr, subset))
    LOG.write_text("".join(parts))
    if code != 0:
        parts.append(abi_report(OUT / "MapKit-a.o"))
        LOG.write_text("".join(parts))
        print(f"subset module failed; geo exit {geo_code}; log {LOG}")
        return code
    (OUT / "SwiftUI-module-only.o").unlink()
    attempt = common([MODULES / "module.modulemap"]) + [
        "-wmo", "-enable-library-evolution",
        "-c", "-emit-object", "-o", str(OUT / "MapKit-a.o"),
        "-module-name", "_MapKit_SwiftUI",
        str(HERE / "Geo.swift"), str(HERE / "MapKit.swift"), str(embed),
    ]
    code, stdout, stderr = run(attempt, env)
    parts.append(section("A P13 SwiftUI plus Cocotron AppKit", code, stdout, stderr, attempt))
    LOG.write_text("".join(parts))
    source = common([MODULES / "module.modulemap"])
    m6_flags = []
    index = 0
    while index < len(source):
        if source[index] == "-I" and index + 1 < len(source) and source[index + 1] == str(OUT):
            index += 2
            continue
        m6_flags.append(source[index])
        index += 1
    m6 = m6_flags + [
        "-F", str(M6),
        "-wmo", "-enable-library-evolution",
        "-c", "-emit-object", "-o", str(OUT / "MapKit-b.o"),
        "-module-name", "_MapKit_SwiftUI",
        str(HERE / "Geo.swift"), str(HERE / "MapKit.swift"), str(embed),
    ]
    code_b, stdout_b, stderr_b = run(m6, env)
    parts.append(section("B M6 -F without a swiftmodule", code_b, stdout_b, stderr_b, m6))
    parts.append(abi_report(OUT / "MapKit-a.o"))
    LOG.write_text("".join(parts))
    print(f"geo exit {geo_code}; attempt A exit {code}; attempt B exit {code_b}; log {LOG}")
    return code if code != 0 else geo_code


if __name__ == "__main__":
    sys.exit(main())
