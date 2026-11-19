# Pinned JSONDecoder port candidate

This is the real `FoundationEssentials` decoder/scanner implementation from
swift-foundation `swift-6.3.1-RELEASE`, revision
`c20150400269a6afffe5b3a9f9fa8bbd51d69e1a`. It calls the requested type's real
`Decodable.init(from:)`, with keyed/unkeyed/single-value containers, coding paths,
user info, null/missing/type/range failures and backing-buffer lifetime handling.
No placeholder Data type, substitute parser or success stub is included.

`sources.json` pins all 13 required open Swift files by SHA-256. They are seven
JSON decoder/scanner/buffer files, `CodableUtilities`, `CodableWithConfiguration`,
`LockedState` and three pure-Swift Decimal files. JSONEncoder, JSONWriter and the
Decimal Objective-C compatibility wrappers are excluded. Every selected source
was compared with the pinned Git revision. Copyright notices remain in the
prepared files; the full Apache license with Swift exception is copied from
the repository's `LICENSES/Swift-Foundation.txt`.

Prepare in a fresh owned directory:

```sh
python3 integrations/siliconforest/finch/Preview/JSONDecoder/prepare.py \
  --source /path/to/pinned/swift-foundation \
  --output /path/to/fresh/owned/json-sources
```

Preparation verifies every source before writing, rejects an existing output,
applies the exact patch without fuzz, and never edits the source checkout or Data.
`JSONSupport.swift` is original MIT code. Its CoreFoundation adapters supply
capitalization and UTF-16/32 conversion using existing open providers. Malformed
input retains the pin's NSError-backed `DecodingError.Context.underlyingError`
through the real open error bridge supplied by Data.
The Decimal patch selects the pin's own Swift storage/arithmetic branch and
keeps locale-independent parsing/formatting, without claiming an NSDecimal bridge.

The absent `Date.ISO8601FormatStyle` machinery remains an explicit limitation:
`.iso8601` throws `SFJSONDecoderUnavailable.iso8601DateStrategy`. It never returns
a fabricated date. Other date strategies use the pin's existing paths; runtime
qualification remains necessary. Swift 5 language mode is used, matching the
current coherent Foundation overlay. Swift 6 concurrency qualification is not
claimed.

## Data and compiler handoff

Grok owns Data and its sources/bridges. The real Data APIs required here include
`init(buffer:)`, `withUnsafeBytes`, `count`, base64 decoding and its Decodable
witness. The Data source response file and flags were handed off under
`runs/preview/retained/swift-foundation-cross/data-impl/`. Those files are inputs,
not files this candidate modifies. Use a private module cache. Compile the
prepared sources in the **same Foundation module** as Data and the current
URL/UUID/error/localization source set; do not link a second Foundation module.

JSON adds the pinned `_FoundationCShims/string_shims.c` to the link. Its real
`_stringshims_strtod_clocale`, `_stringshims_strtof_clocale` and
`_stringshims_strncasecmp_clocale` call libSystem's C-locale operations.
Data additionally requires its own `DataShims.m`, `platform_shims.c`, open
`_ForSwiftFoundation` declarations and the tested Swift `os` overlay. The
compiler SDK/NSRange view and experimental flags must match Data's handoff.

## Evidence and remaining gate

Private logs live under `runs/preview/app-private/jsondecoder/`:

- `typecheck-owned-primary.log`: all port-owned source bodies pass against real
  Data declarations, independently of Data implementation diagnostics.
- `typecheck-with-probe.log`: full current Data + decoder + semantic probe passes.
- `typecheck-current-base.log`: full Data + decoder with the coordinator's
  combined URL/UUID Foundation sources passes.
- `emit-decoder-primary.log`: an actual arm64 decoder object is emitted, defining
  all three exact native AppIntents imports:

```text
_$s10Foundation11JSONDecoderC6decode_4fromxxm_AA4DataVtKSeRzlFTj
_$s10Foundation11JSONDecoderCACycfc
_$s10Foundation11JSONDecoderCMa
```

The first combined emit exposed Data's missing Objective-C error bridge. After
Grok supplied that bridge and the C declaration fixes, a frozen exact-byte
snapshot of all Swift inputs successfully emitted the coherent Foundation
object and module (`emit-frozen.log`, `inputs-v1.json`). The real link then
stopped at exactly `_fgetattrlist`, called from Data's file-writing path. Grok
owns that syscall/error boundary. No undefined-symbol bypass was used. Object
and module emission do not establish a linked dylib or runtime compatibility.

`probe.swift` exercises actual synthesized/custom Decodable, retained decoder
lifetime, scalar/nested values, large integer boundaries, Unicode escapes,
UTF-16, base64, JSON5, detailed failure paths and the explicit ISO date error.
Its combined-source typecheck passed; it has not run yet. It must compile again
as a separate client after the coherent Foundation module is emitted, followed
by guarded standalone M1 proof with hashes and export preservation. No app
launch, shared install or Preview UI result is claimed.
