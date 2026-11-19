# Scoped Swift AttributedString reader values

This slice prepares the real open Swift Foundation AttributedString text,
attribute storage, runs, views, value operations and Codable implementation.
It addresses the native AppIntents metadata gate observed after DateComponents.
It does not establish Preview launch or UI support.

Sources are pinned to swift-foundation swift-6.3.1-RELEASE,
`c20150400269a6afffe5b3a9f9fa8bbd51d69e1a`. `sources.json` records all 29
upstream file digests. The source preparer reads that exact Git revision,
verifies every digest before writing, rejects an existing output and applies
the decoded `compatibility.json` patch without fuzz. Upstream notices and full licenses remain.
No Apple implementation, extracted assets or private app bytes are included.

```sh
python3 integrations/siliconforest/finch/Preview/AttributedString/prepare.py \
  --source /path/to/local/swift-foundation \
  --output /path/to/fresh/owned/attributed-sources
```

Compile all prepared Swift files in the existing coherent Foundation module,
with the retained Data/JSON/UUID/URL/calendar sources, library evolution and
`FOUNDATION_FRAMEWORK`. Add this slice's `include` directory and the actual
CollectionsInternal module to search paths. Link its real arm64 Collections
object into the same library, retain all preceding exports and the NSError to
CFError conformance alias documented in `../JSONEncoder/ERROR-BRIDGE.md`.
Do not combine independently laid-out Swift Foundation value implementations.

`collections.json` records 171 open Swift Collections source digests at revision
`c11818f3cae0780656baa430b49e7f163f08dffd`, plus the exact retained object/module
hashes used here. This port reuses that existing arm64 object; it does not claim
to have reproduced its compilation. Its license is in
`LICENSES/Swift-Collections.txt` and copied into prepared output. A portable
package still needs to build that dependency from the recorded source set.

## Adaptations and bounds

- Preserve the pinned BigString/Rope storage and actual run mutation,
  Unicode views, value copying, equality, hashing and Codable operations.
- Replace the unavailable ReflectionInternal import with the existing Finch
  field-reflection adapter. Its field record layout and Swift calling convention
  were checked against open Swift runtime ReflectionMirror.cpp and Reflection.h.
  The custom-scope Codable probe exercises real field discovery.
- Expose the actual dyld image inventory through a small C module. Keep the
  original default-scope discovery; only already-loaded scope metadata is queried.
- Default Foundation scope contains the genuine URL link and language identifier
  attributes. Formatter, grammar, Markdown presentation and UI-specific scopes
  are omitted; this is not the full Foundation attribute catalog.
- Retain the ObjectiveCConvertibleAttributedStringKey protocol, but omit newer
  NSAttributedString conversion implementations that the retained Objective-C
  class/provider cannot supply. `NSAttributedString.Key` is an actual string key.
- Generic attribute Codable remains upstream behavior. The secure-object default
  bridge uses real Data/NSData and the retained keyed archiver/unarchiver APIs;
  it propagates their failures and rejects a missing decoded object. The native
  probe covers Swift Codable attributes, not arbitrary secure object archives.
- Attribute text search uses existing CoreFoundation Unicode and ICU regex
  operations, with actual UTF-16 to String index conversion. The older protected
  QTP NSString lacks the newer regex wrapper, so it is not used for this path.
  Invalid regex patterns produce nil, matching the pinned nonthrowing API.
- ASCII CR/LF constants support the unchanged pinned paragraph-boundary helper.

No Data source is authored by this slice. The final coherent build additionally
uses PREVIEW-CGPDF's tested Darwin munmap disposal handoff, Data.swift digest
`5157a44dafcbe324e77e60fd7cfd08068de4a7de8fd26994a80656a4d704ff2a`.
The remaining 50 preceding Swift inputs are unchanged. Exact source/object
manifests, compiler drivers, linker commands and receipts are retained in the
private `runs/preview/app-private/attributed-string` directory.

## Native proof

The first corrected library, SHA-256
`1fff856bea529b0a22d98b89de5a03c31ad0be3499595b445f6e51c2e64c64cc`,
retains all 2,018 previous exports (5,141 total), both imported metadata symbols
and valid arm64 code signatures. Its eight separate clients exit 0: Unicode,
character/UTF-8/UTF-16 views, attributes/runs, independent copies, equality/hash,
localized/backwards/regex search, mutation, default and custom-scope Codable,
24-run attribute-table representation and malformed-input rejection; plus
unchanged calendar/error/Data/encoder/decoder/UUID/URL probes. Receipt:
`app-private/evidence/attributed-string-20261119T074023Z.json`.
A separate current Data probe also passes mapped-read disposal and atomic mode
preservation with the same library:
`app-private/evidence/attributed-mapped-20261119T074126Z.json`.

One bounded standalone native open AppIntents load (PID 3204, exit 1) clears
AttributedString and next stops at
`_$s10Foundation20PersonNameComponentsV19_bridgeToObjectiveCSo08NSPersoncD0CyF`.
Receipt: `app-private/evidence/appintents-attributed-20261119T074148Z.json`.
REA host-wrapper evidence:
`ev_5e75893fb5ddaaceb41a5f0f2b3b1357016278a10723be87601f2af92a256540`.
The remote receipt supplies actual M1 PID, dyld and hash observations; REA does
not directly trace the remote inferior or its filesystem/syscalls.

All probes use owned fresh prefixes/HOME with gui.lock and the owner-input guard.
Packet bytes, protected QTP Foundation and compositor PID 125 remain unchanged.
No Preview execution, GUI action, shared install or active-prefix modification
occurs. Earlier regex and mismatched mapped-probe failures remain preserved.

Final empty/invalid/backwards/anchored regex edge checks also pass (PID 3242),
with all seven prior clients still passing. Exact final library SHA-256
`d02a85edbe5ef478d32ab2f13e1c859524d9fbbf0fa630fbb089101a2093b66e`, same 5,141 exports / all 2,018 retained.
Receipts: `app-private/evidence/attributed-string-20261119T074410Z.json`
and final mapped-read probe `app-private/evidence/attributed-mapped-20261119T074443Z.json`.
The only further source change permits empty-input regex matches; no AppIntents
load is repeated while its observed name-provider gate remains unchanged.
The earlier exact tested loader library is preserved as `build-1fff856b`.
All six required host checks pass (295 Python, 77 C groups, 6/6 mutations,
validation/plans/dry runs); no push. `attributed-string/handoff.json` records
all exact inputs, artifacts, receipts and private build/replay commands.
