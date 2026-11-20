# Pinned JSONEncoder and writer

This adds the real open FoundationEssentials `JSONEncoder.swift` and
`JSONWriter.swift` from swift-foundation `swift-6.3.1-RELEASE`, revision
`c20150400269a6afffe5b3a9f9fa8bbd51d69e1a`. `sources.json` pins both complete
files and records the provenance of the small `_specializingCast` helper mined
from the same pin's `AttributedString/Collection Stdlib Defaults.swift`.
Copyright notices remain intact; the full Apache license with Swift exception
is copied from `LICENSES/Swift-Foundation.txt` beside prepared sources.

The new encoder calls actual `Encodable.encode(to:)`, including keyed, unkeyed,
single-value, nested and super encoders. The original writer serializes the
result to real Data. It shares one Foundation module with the proven Data,
JSONDecoder, URL, UUID and error/localization source set. No Data or decoder
source changes, second Foundation module or undefined-symbol bypass is used.

Prepare only the two new sources in a fresh owned output:

```sh
python3 integrations/siliconforest/finch/Preview/JSONEncoder/prepare.py \
  --source /path/to/pinned/swift-foundation \
  --output /path/to/fresh/owned/encoder-sources
```

The helper verifies source hashes before writing, rejects an existing output
and applies the exact compatibility patch without fuzz. Add the resulting three
Swift files to the coherent decoder/Data Foundation build. The prior build's
inputs and C objects remain byte-identical; the new encoder adds no C shim.
The same Data compiler SDK/flags/module maps and private os dependency apply.

## Scoped adaptations

- Snake-case conversion uses the real public CoreFoundation uppercase/lowercase
  character sets and Unicode scalar ranges. It retains the pin's key algorithm.
- The pin's array fast path refers to `array` before declaration. Cast the actual
  `value` argument, using metatype equality followed by a checked standard cast.
  The original direct-array writer and general Encodable fallback remain intact.
- Sorted output uses the pin's current UTF-8 lexicographic branch. The historical
  NSString sorting branch depends on an unavailable compatibility feature flag
  and is excluded explicitly.
- A nil result from the retained DateFormatter throws `EncodingError.invalidValue`.
  ISO8601 formatting remains unavailable and throws
  `SFJSONEncoderUnavailable.iso8601DateStrategy`, matching the decoder's explicit
  limitation. No fabricated date string or successful formatting is returned.

Swift 5 language mode matches the proven coherent module. Full Swift 6 concurrency
qualification, complete JSON API coverage and legacy sort compatibility are not
claimed.

## Exact M1 proof

Private library: `runs/preview/app-private/jsonencoder/build/libswiftFoundation.dylib`.
SHA-256:
`98a10e050e7302e920a5de9cecd89607fd4ad35dd2e41430a9e23354ff6f27d8`.
All **1,691** preceding `d023b891...` exports remain (1,805 total), including the
entire decoder/Data/URL/UUID surface. The observed native AppIntents import
`_$s10Foundation11JSONEncoderC6encodeyAA4DataVxKSERzlFTj`, allocating initializer
and real metadata are exported. Both new binaries have valid thin arm64 signatures.
Static receipt: `app-private/jsonencoder/linked-static-final.json`.

`probe.swift` compiled and linked as a separate client of the emitted Foundation
module. On M1 it exited 0 (final PID 2655), testing encode/re-decode of real Codable
values, custom/nested/super containers and user info, Unicode/control characters,
slash escaping, sorted/pretty/direct-array output, signed/unsigned integer limits,
negative zero, key strategies, Decimal/date/Data, nonfinite float errors and
configured conversion, user errors, empty-value errors and reuse after failures.
It also checks BMP and astral Unicode key conversion, and verifies that
ISO8601 dates throw the explicit unavailable error.

Unchanged decoder (PID 2656), UUID (2657) and URL/localization/CharacterSet (2658)
probes also exited 0. Every loader receipt uses the exact new private Foundation.
All seven staged files and the protected QTP Objective-C Foundation hash remained
unchanged. Execution used strict existing SSH identity/host pin, an owned prefix
and HOME, bounded CLI processes, `gui.lock` and the documented owner-idle guard
before and after; compositor PID 125 was unchanged.

Receipt: `runs/preview/app-private/evidence/jsonencoder-20261119T063531Z.json`.
Private build scripts, exact input hashes and outputs are under
`runs/preview/app-private/jsonencoder/`. No Preview/AppIntents launch, window/input
action, shared install or active app-prefix change occurred. These tests qualify
the observed cases and prior consumers; they do not establish Preview UI.

A separate arm64 CLI probe loaded this exact private library with `RTLD_NOW`
and resolved every preceding d023 export with `dlsym`: **1,691 resolved, zero
missing**, PID 2627 exit 0. Its eight packet hashes, QTP Foundation, owner guard
and compositor remained unchanged. Receipt:
`runs/preview/app-private/evidence/jsonencoder-exports-20261119T063412Z.json`.
This checks actual M1 symbol resolution; it does not call every exported API.
The export probe keeps Swift/Objective-C metadata mapped until its process exits.

[ERROR-BRIDGE.md](ERROR-BRIDGE.md) records the subsequent real NSError runtime
lookup fix, its six passing M1 probes and the next observed DateComponents gate.
The original encoder artifact above is preserved; the relink has a separate digest.
