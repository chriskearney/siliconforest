# Open SwiftUI source and Linux graph work

This is an isolated source port for the unmodified Preview dependency closure.
P13's observed app stop is missing TipKit. This directory does not launch an
Apple app, install libraries, or authorize a later launch.

Finch `2d9b1bb1af57e14462e4621d194929188a8845b0` builds OpenSwiftUI at
`aefa4e6edc9c37a992a0cf9c6cf317fb670ed305`. Its adaptation gives SwiftUICore
SwiftUI's ABI module name and makes SwiftUI reexport it. The graph backend is
Compute 0.6.0 through OpenAttributeGraph. Exact source revisions and per-file
Finch hashes are in `sources.json`; no moving dependency update is required.

## Verified scopes

The original live P13 SwiftUI image has 384 exports. It supplies 42 of Preview's
362 strong direct SwiftUI imports; 320 are absent. The independently built Edge
candidate preserves every one of those 384 exports, supplies 501 total, and
adds six direct Preview imports. A native M1 client checked enum cases, raw
values, invalid values, one-byte frozen storage and set algebra. A client
compiled against the original subset module passed against both images.
This candidate still uses the original binding subset; it supplies neither a
renderer nor Binding/popover support.

The Linux Swift 6.3.3 Compute/OAG build linked and passed native M1 PID 5796.
Its separate client checks a real Rule, cached reads, dependency changes,
invalidation/recomputation, actual Swift field names and offsets, observer
removal, and exactly-once destruction of the rule's retained object on subgraph
invalidation. The build includes all 54 graph C/C++/Objective-C++ translation
units, the Swift facade/support, and the real OAG adapter. This establishes that
bounded graph behavior against P13's retained runtime. It does not establish
full SwiftUI layout, popovers, archive/debug tracing, or Apple arm64e client ABI.

The actual patched graph-independent observation collection helper and a real
`@Observable` macro client passed native M1 PID 5278. The test covers canonical
collection/merge, both models, pre-change key paths, cancellation, nested scopes
and restoration after throwing. It uses the coordinator's real Observation
module and the installed Linux Swift 6.3.3 ObservationMacros plugin.

## Changes

* `observation-collection.patch` delegates collection and merging to the real
  `ObservationTracking._collectAccesses` and `_mergeAccessLists` SPI. It removes
  fixed pthread slot 106 and every private access-list layout reinterpretation.
* `accessibility-failable.patch` keeps the open Accessibility provider's nullable
  archive initializer authoritative and propagates the existing unarchive error.
* `compute-cross.patch` explicitly opens metatypes, uses real CF string/data
  creation and retained Foundation dictionary APIs, includes the actual Mach
  declaration, and writes compressed graph archives through zlib with checked
  errors. It supplies the callback authentication helper referenced but omitted
  by Finch's patch, using the operation already present in that patch. Graph
  behavior is tested; archive output and the authenticated arm64e branch remain
  separate validation work.
* `oag-cross.patch` adapts real CF description bridges and hexadecimal formatting,
  omits Finch's unused Network debug client, and replaces the profile-reset
  placeholder with the actual Compute operation.
* `orb-cross.patch` corrects `ORB_TRRET_OS_DARWIN` so Darwin uses its actual
  CoreGraphics types rather than redeclaring fallback geometry types.
* `backtrace_image_offsets.c` extracts the existing open libc implementation,
  retaining its APSL notice. It calls the real dyld image/UUID query and is hidden
  at the private graph link. It is not a global libSystem replacement.

The two files in `diagnostics/` are **compile diagnostics only**. Their temporary
annotation/protocol declarations are not a provider or runtime implementation.
A complete header/module package must replace them before renderer qualification.

## Reproduce source preparation

Check out the exact revisions in `sources.json` under a private source directory
using the named subdirectories. Initialize Compute's pinned runtime-header
submodule. Then run:

```sh
python3 prepare.py --finch /path/to/pinned/finch \
  --sources /path/to/private/checkouts --output /path/to/new/output
```

Preparation checks revisions, tracked working bytes and Finch file hashes,
applies the retained and scoped patches, and records every regular output file.
It refuses an existing output. `--diagnostic-headers` explicitly selects the
compile-only declarations and marks the receipt accordingly. Neither mode
builds, executes target code or grants provider staging authority.

A fresh preparation was compared with the tested Compute/OAG sources with zero
source differences. This is source reproduction, not a claim of identical
binaries across different compiler paths. The current cross-build commands,
all toolchain/header inputs, native receipts and exact artifacts remain in the
ignored private `runs/swiftui/` handoff. No owner app bytes or device logs are
tracked here.

## Remaining renderer work

The Linux host OpenSwiftUIMacros executable and target graph/graphics/render
shim modules build. Full SwiftUICore remains under compilation. It needs a
coherent full CoreGraphics/QuartzCore module surface, real Observation and
Synchronization, the tested open Combine and Accessibility providers, and the
remaining actual imported framework interfaces. Module emission alone is not
runtime behavior. The QTP fallback, P13 and all shared providers remain intact.

## CoreGraphics geometry slice

Source preparation also extracts the complete unchanged `CGPoint: Equatable`
conformance from pinned Finch CoreGraphics, retaining its Swift project license
header. Compile it as `CoreGraphics` with the real underlying geometry module,
`-module-link-name swiftCoreGraphics`, and library evolution. It does not define
new C types or replace their layout. The test client exercises generic witness
dispatch, synthesized enum equality, signed zero, NaN/infinity, and size/alignment.
A private native M1 client passed. This is a narrow geometry conformance, not a
complete CoreGraphics overlay or renderer qualification. Exact commands, hashes
and native receipt remain in the ignored `runs/swiftui/cg-primitives` handoff.

The renderer accepts the coordinator's real Foundation `FormatStyle` and
`DiscreteFormatStyle` module. Further confirmed source/client requirements
include `Locale.language`, locale-aware capitalization, Date format styles and
Duration time/units format styles. They remain separate provider work; the
full renderer does not compile yet.
