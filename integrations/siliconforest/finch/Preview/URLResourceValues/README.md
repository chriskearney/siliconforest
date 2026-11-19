# Scoped URL resource values and content types

This independent Preview dependency group supplies real URLResourceValues,
`URL.resourceValues(forKeys:)` and the Swift UTI `contentType` getter. It is
separate from the confirmed standalone AppIntents CGRectStandardize gate owned
by the CoreGraphics worker. No AppIntents or Preview execution occurs here.
P13 remains the earlier inert preparation artifact; no active prefix changes.

## Sources and composition

`URLResourceValuesReader.swift` mines the two actual value dictionaries,
requested-key storage, initializers, optional getters, setters and `allValues`
from swift-foundation `c20150400269a6afffe5b3a9f9fa8bbd51d69e1a`,
Sources/FoundationEssentials/URL/URL.swift. It preserves upstream copyright and
Apache-2.0 WITH Swift-exception. The retained NSNumber importer needs
`integerValue` for native Int width and the `bool:` initializer spelling.

`ContentType.swift` retains the getter from Finch
`2d9b1bb1af57e14462e4621d194929188a8845b0`,
userland/swift/overlays/UniformTypeIdentifiers/UTType.swift, under its
MIT OR Apache-2.0 notice. `UTType-base.swift` and `UTTypeBridge.h` are the existing
tested open adapter sources, preserving their MIT notices. Their recorded
artifact/source hashes are distinct from the pinned full Finch source; no
upstream revision is invented for the adapter.

`SFURLResourceReader.h` adds the public typed NSString resource-key declaration
to an owned compiler overlay. This produces the imported NSURLResourceKey ABI
used by the actual Preview import. `SFURLResourceReader.m` is an original
private C adapter; it installs no NSURL category and replaces no global class.
It calls retained NSURL's single-key resource method. Existing non-nil values
and actual NSError failures are preserved. Where type values are unavailable,
it calls the existing open Finch `_UTFinchTypeIdentifierForPath` and native
UTType factory, using actual URL metadata. The provider's extension/registry
classification is used; content sniffing or image/PDF decoding is not claimed.

The native retained NSURL has no bulk resourceValuesForKeys:error: selector.
Its single-key reader returns real names, file sizes and directory flags, but
nil type values. Those observations and the existing type-provider function
were tested before adding the adapter. Neither path manufactures type metadata.

Prepare a fresh source/overlay directory:

```sh
python3 integrations/siliconforest/finch/Preview/URLResourceValues/prepare.py \
  --foundation-source /path/to/pinned/swift-foundation \
  --finch-source /path/to/pinned/finch \
  --baseline-overlay /path/to/existing/foundation-overlay.json \
  --coregraphics-header /path/to/existing/CoreGraphics/CGGeometry.h \
  --output /path/to/new/owned/resource-sources
```

The helper verifies pinned Git-object digests, exact selected value declarations,
reviewed adapted file hashes and the unchanged Finch getter before writing.
It copies full Swift/Finch license texts and produces a separate additive VFS
header overlay. It never edits the baseline header, shared SDK, other worktree,
Data, name or NSError source. Existing output is rejected.

Compile the reader Swift file together with the exact coherent baseline's
sources in **one Foundation module**. Compile the C reader into that library,
with the owned header directory available. Preserve the baseline's error alias,
name-class link flags, C objects and actual Collections object. Use the new
Foundation module when compiling both the retained UTI adapter and the getter
as one UniformTypeIdentifiers module. Use the expanded UTTypeBridge declaration;
the older cross-intents module map renames that class and lacks constrained
lookup. The prepared `overlay/cross.modulemap` preserves the supplied geometry
header and selects the correct bridge declaration without changing CoreGraphics.

Do not combine independently laid-out Foundation value implementations. Private
build/source manifests and exact compiler/link commands are retained in
`runs/preview/app-private/url-resource-values/`.

## Measured M1 result

Baseline: exact tested `bed3c17185d4103f1b8737434506ab66c35c2fc6b561491ea00e712554f4a0c9`
Foundation, with 84 Swift inputs copied read-only from its handoff. Every old
source remains byte-identical. New paired private libraries:

| Library | SHA-256 | Export preservation |
| --- | --- | --- |
| Swift Foundation | `2de8e8fc00a7acd6b1633add2db6cf13c9a7f6892d0c34250665bdd69921f0d6` | 5,294 previous retained; 5,362 total |
| Swift UTI | `2781e7551b3013ebeadf1ef478229c455f752a61f496aedcb098036108a23a68` | 40 previous retained; 43 total |

Thin arm64 signatures verify with zero mismatched pages. Native dlsym probe
PID4430 resolves all 5,338 names with zero missing: both prior export sets and
the four required direct Preview bindings. It uses the observed dyld dlsym
spelling (one leading Mach-O underscore removed):

- `_$s10Foundation17URLResourceValuesVMa`
- `_$s10Foundation17URLResourceValuesVMn`
- `_$s10Foundation3URLV14resourceValues7forKeysAA011URLResourceD0VShySo16NSURLResourceKeyaG_tKF`
- `_$s10Foundation17URLResourceValuesV22UniformTypeIdentifiersE07contentE0AD6UTTypeVSgvg`

Separate-client PID4429 passes PDF, PNG and text content types from the actual
retained provider, retained object identity across the Swift bridge, names/sizes,
directory basic metadata, value copies/setters, `allValues` copy isolation,
unrequested-value absence, actual missing-file NSPOSIXErrorDomain2 propagation,
nonfile unavailable values and prior UTType operations. No network fetch is
attempted. PIDs4431–4441 pass unchanged description, URLError, name,
AttributedString, calendar, NSError, mapped Data, encoder, decoder, UUID and URL
clients. Receipt:
`url-resource-values/resource-values-regression-20261119T120323Z.json`.
Earlier standalone semantic PID4353 also exits0.

All 20 packet file hashes and source hashes match before/after. Protected QTP
Foundation remains 94a07b51…, compositor 125 and owner guards are unchanged under
gui.lock. Each run uses owned scratch/HOME/preferences, arm64 CLI only, bounded
processes and core dumps disabled. No shared install, GUI action or app launch.

REA portable header evidence
`ev_4d80c7684c9580521e486d9c3f1f2e284b6c8bbbf7b3b89cd69e363aedad7f31`
covers this exact UTI artifact's 11 load commands. Absolute external providers
remain undetermined to that analysis. The native receipt supplies M1 loaded
paths, PIDs, return codes and integrity observations. No native disassembler or
remote syscall trace is claimed; the artifact session is closed.

## Bounds and remaining work

Directory content-type lookup rejects unavailable package metadata with
NSCocoaErrorDomain 3328. Basic directory name/flag reads work. The first C probe
expected a folder type and failed at that boundary; its receipt is preserved.
The scoped Swift semantic test explicitly verifies this error. No generic folder
or package type is substituted for an unknown package flag.

The reader exposes the selected optional fields only. It adds no writer,
bookmark, security scope, promised-item, general volume or full package support.
Nonfile resource requests preserve the retained nil/unavailable behavior.
Unrequested and unavailable values are absent, per the resource-value contract.
No whole-URL or full Foundation compatibility claim is made.

Preview's separate CoreFoundation NSURL key globals remain a distinct static
closure issue in the existing audit. This Swift/C reader does not replace that
framework or claim to resolve its two-level bindings. The confirmed standalone
AppIntents CGRectStandardize stop is unchanged by this work and is not rerun.
The paired libraries are headlessly qualified; Preview UI remains unproven.
