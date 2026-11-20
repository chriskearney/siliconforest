# Additive Swift Foundation UUID

The observed native AppIntents imports require `UUID.init()`,
`init(uuidString:)`, `uuidString`, and the genuine Swift metadata accessor and
descriptor. `FoundationUUID.swift` compiles those as one real value type in the
existing Foundation module. Its five exact mangled exports are checked by
`check-uuid.py`; no symbol aliases or fabricated metadata are used.

The source is scoped from open swift-foundation `swift-6.3.1-RELEASE`, revision
`c20150400269a6afffe5b3a9f9fa8bbd51d69e1a`. See NOTICE for source hashes and
changes and the full Apache license with Swift exception in
`LICENSES/Swift-Foundation.txt`. The C module `SFUUIDRuntime` includes the
existing open libSystem `uuid/uuid.h`. Generation, parsing and uppercase
formatting use `uuid_generate_random`, `uuid_parse`, and `uuid_unparse_upper`.
Parsing validates the entire Swift string (36 ASCII bytes, no embedded NUL)
before libSystem validates hexadecimal groups and separators. The type retains
16-byte tuple/value storage, equality and hashing. NSUUID bridging, Codable,
Comparable and generic random-generator extensions are outside this slice.

Build on the cross-build host, without target access or installation:

```sh
nix-build --extra-experimental-features 'nix-command flakes' --no-out-link \
  --expr '(import ./integrations/siliconforest/finch/Preview/foundation-uuid.nix) {}'
python3 integrations/siliconforest/finch/Preview/check-uuid.py \
  --candidate "$candidate" --baseline "$baseline/usr/lib/swift/libswiftFoundation.dylib" \
  --macho integrations/siliconforest/homebrew
```

The derivation accepts `baseFoundation` and copies its coherent source set;
the default is the earlier URL overlay. It adds one UUID source and the C module,
preserving the baseline string bridge and SDK. New module and library search
paths precede the old runtime so consumers compile against the added type.
The separate `UUIDInteropClient` library exercises value calls across an actual
Swift library boundary. The unchanged baseline URL executable tests old consumer
ABI against the replacement, without recompiling that consumer.

## Measured standalone M1 result

Tested output:
`/nix/store/iiklpq25h5l3h07adlmfw3zjhh0ha6ri-siliconforest-preview-foundation-uuid-arm64`.
Swift Foundation SHA-256:
`a4a8b9d524f6d0874469043a4916199083bf40182dbfe75a6e6c81fc9391d295`.
Static checks preserve all 258 default-baseline exports (279 total), match all
five native UUID imports, verify thin arm64 and all four Mach-O page signatures,
and confirm the three libSystem imports.

On M1, the privately staged UUID probe (PID 2347) exited 0: lowercase parsing,
uppercase formatting, exact tuple bytes, nine invalid inputs, nil UUID, 1,000
unique generated version-4/variant UUIDs, round trips, hashing, 10,000 value
copies, metadata/type reflection and separate-library calls. The unchanged URL
probe (PID 2348) exited 0 for URL bridging/copies/hash and legacy Swift
string/dictionary/date behavior. Both loader receipts select the exact private
Swift Foundation. This is a sample generation/value test, not an entropy audit
or full native Apple Foundation ABI qualification.

Execution used the existing strict SSH identity/host pin, an owned scratch
prefix and HOME, bounded CLI processes, no core dumps, `gui.lock`, and the
documented 60-second owner-idle guard before/after. All four staged file hashes
and baseline QTP Objective-C Foundation remained unchanged. Compositor PID 125
was unchanged. No app/window/input action, shared install, reboot, app-prefix
change or Preview launch occurred. Private receipts:
`runs/preview/app-private/evidence/foundation-uuid-20261119T054149Z.json` and
`foundation-uuid-final-static.json`.

The coordinator's newer Foundation has additional URL/error/localization APIs.
Integrate this additive source and C module into that coherent build and check
all of its exports; do not substitute this earlier-baseline proof artifact.
URL additions and Data remain separately owned. AppIntents and Preview runtime
support are not established by these standalone tests.
