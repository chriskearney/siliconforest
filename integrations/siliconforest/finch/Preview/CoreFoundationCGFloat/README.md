# Swift CGFloat in libswiftCoreFoundation

Standalone AppIntents on the M1, PID 4763, clears CGRectStandardize and then
fails dyld on `_$s12CoreGraphics7CGFloatVMn`. The two-level expected image is
`/usr/lib/swift/libswiftCoreFoundation.dylib`. Receipt
`runs/preview/app-private/evidence/appintents-geometry-resource-20261119T142405Z.json`.

That import is the only AppIntents import whose library is this dylib
(`open-intents-imports.json`, weak false). The image dyld logged is UUID
`24560DFE-A6D3-3B95-B19B-FDB809705F24`. The build package with that UUID is
`/nix/store/1xx6zwsdr41ws0v28156nkmzkbh1y3h7-siliconforest-swift-runtime-6.3.3/usr/lib/swift/libswiftCoreFoundation.dylib`,
SHA-256 `5cc34db69a4d67170cf5ab4dee8f0ec857ec64c9ff365ee2d0b4c67d03813f1e`.
Its install name is the expected path, compatibility version is 1.0.0
(65536), and current version is 0.0.0. Its export trie is these eight names:

- `__swift_FORCE_LOAD_$_swiftCoreFoundation`
- `_$s14CoreFoundation9_CFObjectMp`
- `_$s14CoreFoundation9_CFObjectPAAE2eeoiySbx_xtFZ`
- `_$s14CoreFoundation9_CFObjectPAAE4hash4intoys6HasherVz_tF`
- `_$s14CoreFoundation9_CFObjectPAAE9hashValueSivg`
- `_$s14CoreFoundation9_CFObjectPAAE9hashValueSivpMV`
- `_$s14CoreFoundation9_CFObjectPSHTb`
- `_$s14CoreFoundation9_CFObjectTL`

`runs/preview/retained/swift-foundation-cross/cgfloat/CGFloat.o`, SHA-256
`8c55d9502164710e6192c3f720abb67869b2f3aa8bb4f49d86f00a96e7747ffb`, already
defines `_$s12CoreGraphics7CGFloatVMn`. `link.py` refuses any other object
or runtime bytes. It does not recompile the object.

The source of that object is Finch `2d9b1bb1af57e14462e4621d194929188a8845b0`
`userland/swift/overlays/CoreFoundation/CGFloat.swift`, SHA-256
`61d4b0b7bac4c0695b0a485a3d70bb18f5009920e0ebb740b9acb7c0ae47fe28`, copied
here unchanged. Apache-2.0 WITH Swift-exception. CGFloat stays mangled as
CoreGraphics through `@_originallyDefinedIn`.

`link.py` copies the runtime dylib and changes only its install name to
`/usr/lib/swift/libswiftCoreFoundationBase.dylib`. That string is 47 bytes
and fits the existing 48-byte id slot, including the trailing NUL. The UUID
stays `24560DFE-A6D3-3B95-B19B-FDB809705F24`. The public dylib's install name
and versions match the live image. Its export trie reexports the eight names
from the base and defines `CGFloatVMn` from the object. A leaf named
`libswiftCoreFoundation.dylib` for the base would make `DYLD_LIBRARY_PATH`
load the wrapper again.

`probe.c` binds `CGFloatVMn`, the eight live names, and the dylib multiply
and subtract (`fmul d0,d0,d1` and `fsub d0,d0,d1`) to the public install
name. The arithmetic is `7.5 - 0.25 * 2`. The earlier static probe object
constant-folded that expression and only printed the success line; this
client calls the dylib bodies.

`run_m1.py` runs that client and the previous URL-resource regression
clients under `runs/m1-coord/gui.lock`, with a fresh HOME. Receipt
`runs/preview/retained/cgfloat-corefoundation/evidence/cgfloat-20261119T144703Z.json`
SHA-256 `1d96a83e69ff40471de259c6c11cc582c77b6c8fe123bfcd044b438dc724a68c`.
Remote scratch `/private/var/db/sfpreview-cgfloat/cgfloat-20261119T144703Z`.
Dyld loaded wrapper UUID `089ACAD8-694E-3356-BD01-E0B11CFE20CD` and base UUID
`24560DFE-A6D3-3B95-B19B-FDB809705F24` from that scratch. CGFloat probe PID
4834 exited 0 and printed `Swift CGFloat metadata and arithmetic passed`.
The thirteen previous clients, PIDs 4835–4847, exited 0, including native
exports `found=5338 missing=0`. Uploaded bytes and QTP Foundation
`94a07b510d116a7cfb4f302708f1a3ee7286d4be9c94037b77db13dc48959c2f` were
unchanged. Compositor 125 before and after. Owner guard `active=0`. No
Preview, AppIntents, shared install, or active-prefix change. Handoff hashes
are in `handoff.json`. The coordinator combines the provider. AppIntents was
not relaunched.
