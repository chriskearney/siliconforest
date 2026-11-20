#!/usr/bin/env python3
"""Build the scoped TipKit provider and its headless client.

The SwiftUI binding-subset source is compiled only as a module so Text and
Image stay the P13 SwiftUI types. That object is not linked into TipKit.
"""
import hashlib
import json
import struct
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
LAB = Path("/home/chrisk/src/darwin-lab")
OUT = LAB / "runs/preview/retained/tipkit/build"
CACHE = LAB / "runs/preview/retained/tipkit/module-cache"
SWIFTC = "/nix/store/bni7djh2akv2x23pk86bgqj95xhxlgja-swift-toolchain-6.3.3/bin/swiftc"
CLANG = "/nix/store/p8x57y0mi788srcls95cpcf2nbjz6la8-darwin-cross-toolchain-nix/bin/arm64-apple-darwin20.4-clang"
LD = "/nix/store/ikix61c2brfm9cf9f4pwdh80mhy1f2xp-siliconforest-native-ld-0.1/bin/ld"
NM = "/nix/store/v0x4y2cjbasgmrqsbka2bp8allw8j9ph-darwin-cross-toolchain-nix/bin/arm64-apple-darwin20.4-nm"
SDK = Path("/nix/store/72ya6fb76jqznykdp5f72zh6951j1xkn-siliconforest-preview-foundation-url-arm64/compiler-sdk")
DEV = Path("/nix/store/qd81f2xxrfrig8p3s1bijsyfjpc95r6k-siliconforest-swift-runtime-6.3.3-dev/usr/lib/swift")
RESOURCE = Path("/nix/store/sk8w4a68hamxyy3dac93qffkp68d2nrc-siliconforest-finch-swift-cross-sysroot/resource")
CG = Path("/nix/store/2p4xgkniqff2d87mnwxaq4d948g0gx5f-siliconforest-coregraphics-0.1/usr/include")
LIBSYSTEM = Path("/nix/store/qxkrrfhc2anc1zl8qv9gkr0856ra4f42-siliconforest-libsystem-0.1")
LIBOBJC = Path("/nix/store/w5092y706fszhrkwpcf4v2c62hrrc6y3-siliconforest-libobjc-1")
FOUNDATION_LIB = Path("/nix/store/f81yl12wpld3d9xh1qa4v2k87sfaj6pb-siliconforest-foundation-1")
SWIFT_LIB = Path("/nix/store/1xx6zwsdr41ws0v28156nkmzkbh1y3h7-siliconforest-swift-runtime-6.3.3/usr/lib/swift")
RETAINED = LAB / "runs/preview/retained"
SF = RETAINED / "swift-foundation-cross"
SCR = LAB / "runs/preview/app-private/url-resource-values"
SWIFTUI_SRC = LAB / "runs/qtp/closure/prefix/System/Library/Frameworks/SwiftUI.framework/Versions/A/Resources/Source/c0skbmlfgqf09kvj73iq8d5spfmrv1sb-SwiftUI.swift"
CGFLOAT_SRC = LAB / "runs/qtp/closure/prefix/System/Library/Frameworks/SwiftUI.framework/Versions/A/Resources/Source/CGFloat.swift"
SWIFTUI_DYLIB = LAB / "runs/qtp/closure/prefix/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI"
LIBSWIFT_FOUNDATION_P13 = SCR / "build/libswiftFoundation.dylib"
PREDICATE_BUILD = LAB / "runs/preview/predicate-wt/runs/predicate/build"
LIBSWIFT_FOUNDATION = PREDICATE_BUILD / "libswiftFoundation.dylib"
FOUNDATION_SWIFTMODULE = PREDICATE_BUILD / "Foundation.swiftmodule/arm64-apple-macos.swiftmodule"
AUDIT = LAB / "runs/preview/app-private/p13/projected-audit.json"
INSTALL = "/System/Library/Frameworks/TipKit.framework/Versions/A/TipKit"
OBSERVATION = Path("/nix/store/jj285a5nvzzk36bxc6spdx67km16l7p7-siliconforest-preview-observation-arm64/usr/lib/swift")
OBSERVATION_DYLIB = OBSERVATION / "libswiftObservation.dylib"
PLUGIN = Path("/nix/store/bni7djh2akv2x23pk86bgqj95xhxlgja-swift-toolchain-6.3.3/lib/swift/host/plugins/libObservationMacros.so")
PINS = {
    SWIFTUI_SRC: "022a0fb0537cf3133f7542efa2e7cbffa6f366b18c85e24d5d0c6094f47c04c6",
    CGFLOAT_SRC: "61d4b0b7bac4c0695b0a485a3d70bb18f5009920e0ebb740b9acb7c0ae47fe28",
    SWIFTUI_DYLIB: "366e2f883d17af3ac94fe8f37d3b53f24adad02c5fa49f95b0653ff0991d9e1a",
    LIBSWIFT_FOUNDATION_P13: "2de8e8fc00a7acd6b1633add2db6cf13c9a7f6892d0c34250665bdd69921f0d6",
    LIBSWIFT_FOUNDATION: "aa7de512b8f76a22d9f9484455b5fccd35af9b99f5d0e9c943b54bfaefd530c0",
    FOUNDATION_SWIFTMODULE: "8ad0dda8f4e565a44588e308cdf9f84c4e9c0eb3f6586d0768b95fc6072647e8",
}
PREDICATE_EXPORTS = [
    "_$s10Foundation20PredicateExpressionsO10ComparisonVy_xq_G6TipKit05EventB10ExpressionA2gHRzAgHR_rlMc",
    "_$s10Foundation20PredicateExpressionsO5ValueVy_xG6TipKit05EventB10ExpressionAGMc",
    "_$s10Foundation20PredicateExpressionsO7KeyPathVy_xq_G6TipKit05EventB10ExpressionA2gHRzrlMc",
    "_$s10Foundation20PredicateExpressionsO8VariableVy_xG6TipKit05EventB10ExpressionAGMc",
    "_$s6TipKit4TipsO4RuleVyAeC5EventVy_xG_AA0E19PredicateExpression_pSb6Output10Foundation0fG0PRts_XPAK0F11ExpressionsO8VariableVy_AHGXEtcSeRzSERzs8SendableRzlufC",
]
POPOVER_EXPORTS = [
    "_$s7SwiftUI4ViewP6TipKitE07popoverD0_11isPresented16attachmentAnchor9arrowEdge6actionQrAD0D0_pSg_AA7BindingVySbGSgAA017PopoverAttachmentJ0OAA0L0OSgyAD4TipsO6ActionVctF",
    "_$s7SwiftUI4ViewP6TipKitE07popoverD0_11isPresented16attachmentAnchor9arrowEdge6actionQrAD0D0_pSg_AA7BindingVySbGSgAA017PopoverAttachmentJ0OAA0L0OSgyAD4TipsO6ActionVctFQOMQ",
]
sys.path.insert(0, str(LAB / "runs/preview/tipkit-wt/integrations/siliconforest/homebrew"))
from hb_macho import load  # noqa: E402


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(cmd):
    completed = subprocess.run(cmd, text=True, capture_output=True)
    if completed.returncode != 0:
        sys.stderr.write(completed.stdout)
        sys.stderr.write(completed.stderr)
        raise SystemExit(completed.returncode)
    return completed


def common():
    return [
        SWIFTC, "-target", "arm64-apple-macosx26.5", "-sdk", str(SDK),
        "-resource-dir", str(RESOURCE),
        "-I", str(OUT), "-I", str(PREDICATE_BUILD), "-I", str(SCR / "build"),
        "-I", str(SDK.parent / "usr/lib/swift"), "-I", str(DEV),
        "-Xcc", f"-fmodule-map-file={DEV}/shims/module.modulemap",
        "-Xcc", f"-fmodule-map-file={SCR}/overlay/cross.modulemap",
        "-Xcc", f"-I{CG}", "-Xcc", "-DXNU_PLATFORM_MacOSX=1", "-Xcc", "-U__OPTIMIZE__",
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
        "-I", str(RETAINED / "foundation-source/Sources/_FoundationCShims/include"),
        "-module-cache-path", str(CACHE),
        "-I", str(OBSERVATION),
        "-load-plugin-library", str(PLUGIN),
    ]


def link(output, objects, extra):
    cmd = [
        CLANG, "-o", str(output), *map(str, objects),
        "--ld-path=" + LD, "-nostdlib", "-isysroot", str(SDK),
        "-L" + str(LIBSYSTEM / "usr/lib"),
        "-L" + str(LIBOBJC / "usr/lib"),
        "-L" + str(FOUNDATION_LIB / "usr/lib"),
        "-L" + str(SWIFT_LIB),
        *map(str, extra),
        "-lFoundation", "-lobjc", "-lSystem",
        "-lswiftCoreFoundation", "-lswiftObjectiveC", "-lswiftDarwin",
        "-lswiftCore", "-lswiftDispatch", "-lswift_Concurrency",
        "-Wl,-dylib_file,/usr/lib/system/libdyld.dylib:" + str(LIBSYSTEM / "usr/lib/system/libdyld.dylib"),
        "-Wl,-platform_version,macos,26.5,26.5",
    ]
    run(cmd)


def names(path):
    image = load(str(path))
    own, re = image.exported()
    out = set()
    for name in list(own) + list(re):
        out.add(name if name.startswith("_") else "_" + name)
    return out, image


def audit_symbols():
    data = json.loads(AUDIT.read_text())
    found = None

    def walk(node):
        nonlocal found
        if isinstance(node, dict):
            library = node.get("library")
            if isinstance(library, str) and library.endswith("/TipKit") and "symbols" in node:
                found = node["symbols"]
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(data)
    if found is None or len(found) != 42:
        raise SystemExit("projected audit did not contain 42 TipKit imports")
    return found


def thin_arm64(path: Path):
    magic, cpu, subtype = struct.unpack_from("<Iii", path.read_bytes())
    if (magic, cpu, subtype) != (0xFEEDFACF, 16777228, 0):
        raise SystemExit(f"not thin arm64: {path}")


def main():
    for path, digest in PINS.items():
        actual = sha256(path)
        if actual != digest:
            raise SystemExit(f"pin changed: {path} {actual}")
    import os
    OUT.mkdir(parents=True, exist_ok=True)
    CACHE.mkdir(parents=True, exist_ok=True)
    (OUT / "SwiftUI.swiftmodule").mkdir(exist_ok=True)
    (OUT / "TipKit.swiftmodule").mkdir(exist_ok=True)
    base_env = dict(os.environ)
    base_env["DARWIN_SDK_ROOT"] = str(SDK)
    completed = subprocess.run(common() + [
        "-wmo", "-enable-library-evolution",
        "-emit-module", "-emit-module-path", str(OUT / "SwiftUI.swiftmodule/arm64-apple-macos.swiftmodule"),
        "-emit-object", "-o", str(OUT / "SwiftUI-module-only.o"),
        "-module-name", "SwiftUI",
        str(SWIFTUI_SRC), str(CGFLOAT_SRC),
    ], env=base_env, text=True, capture_output=True)
    if completed.returncode != 0:
        sys.stderr.write(completed.stderr)
        raise SystemExit(completed.returncode)
    completed = subprocess.run(common() + [
        "-wmo", "-enable-library-evolution",
        "-emit-module", "-emit-module-path", str(OUT / "TipKit.swiftmodule/arm64-apple-macos.swiftmodule"),
        "-emit-object", "-o", str(OUT / "TipKit.o"),
        "-module-name", "TipKit",
        str(HERE / "TipKit.swift"),
    ], env=base_env, text=True, capture_output=True)
    if completed.returncode != 0:
        sys.stderr.write(completed.stderr)
        raise SystemExit(completed.returncode)
    link(OUT / "TipKit", [OUT / "TipKit.o"], [
        "-dynamiclib", str(LIBSWIFT_FOUNDATION), str(OBSERVATION_DYLIB),
        "-Wl,-install_name," + INSTALL,
        "-Wl,-compatibility_version,1", "-Wl,-current_version,1",
    ])
    completed = subprocess.run(common() + [
        "-emit-object", "-o", str(OUT / "probe.o"),
        "-module-name", "TipKitProbe",
        str(HERE / "probe.swift"),
    ], env=base_env, text=True, capture_output=True)
    if completed.returncode != 0:
        sys.stderr.write(completed.stderr)
        raise SystemExit(completed.returncode)
    link(OUT / "tipkit-probe", [OUT / "probe.o"], [
        str(OUT / "TipKit"), str(SWIFTUI_DYLIB), str(LIBSWIFT_FOUNDATION),
    ])
    thin_arm64(OUT / "TipKit")
    thin_arm64(OUT / "tipkit-probe")
    (OUT / "SwiftUI-module-only.o").unlink()
    expected = audit_symbols()
    exported, image = names(OUT / "TipKit")
    present = [name for name in expected if name in exported]
    absent = [name for name in expected if name not in exported]
    if set(absent) != set(POPOVER_EXPORTS):
        raise SystemExit(
            f"export coverage {len(present)} present {len(absent)} absent: " + " ".join(absent)
        )
    for name in PREDICATE_EXPORTS:
        if name not in exported:
            raise SystemExit("missing predicate symbol " + name)
    for name in exported:
        if "popoverD" in name:
            raise SystemExit("fabricated popover " + name)
    if image.dylibs[0]["name"] != "/usr/lib/swift/libswiftFoundation.dylib":
        raise SystemExit("TipKit load list changed")
    loads = [item["name"] for item in image.dylibs]
    if INSTALL not in subprocess.check_output(
        ["/nix/store/v0x4y2cjbasgmrqsbka2bp8allw8j9ph-darwin-cross-toolchain-nix/bin/arm64-apple-darwin20.4-otool", "-D", str(OUT / "TipKit")],
        text=True,
    ):
        raise SystemExit("install name mismatch")
    undefined = subprocess.check_output([NM, "-u", str(OUT / "probe.o")], text=True)
    tip_names, _ = names(OUT / "TipKit")
    ui_names, _ = names(SWIFTUI_DYLIB)
    for line in undefined.splitlines():
        symbol = line.split()[-1]
        if symbol.startswith("_$s6TipKit") and symbol not in tip_names:
            raise SystemExit("probe TipKit symbol missing " + symbol)
        if symbol.startswith("_$s7SwiftUI") and symbol not in ui_names:
            raise SystemExit("probe SwiftUI symbol missing " + symbol)
    if "/usr/lib/swift/libswiftObservation.dylib" not in loads:
        raise SystemExit("TipGroup did not link libswiftObservation")
    print(json.dumps({
        "tipkit": sha256(OUT / "TipKit"),
        "probe": sha256(OUT / "tipkit-probe"),
        "present": len(present),
        "absent": absent,
        "loads": loads,
    }, indent=2))


if __name__ == "__main__":
    main()
