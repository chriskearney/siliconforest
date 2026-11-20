# Error.localizedDescription

AppIntents imports this Foundation getter:

- `_$ss5ErrorP10FoundationE20localizedDescriptionSSvg`

Library evolution also emits the property descriptor
`_$ss5ErrorP10FoundationE20localizedDescriptionSSvpMV`. That descriptor is
the companion of the public property. The AppIntents binding is the getter.
Leave the descriptor in the export trie.

Pinned swift-foundation `c20150400269a6afffe5b3a9f9fa8bbd51d69e1a` keeps a
one-line `localizedDescription` inside `CocoaError.swift`. Leave that file
out of this compile. `sources.json` pins this implementation. The default
`_userInfo` hook in this module is unset, and the default
`_getEmbeddedNSError` returns nil, so a plain Swift error would otherwise
bridge with an empty dictionary.

The getter opens `self` as `any Error` before it calls
`_getEmbeddedNSError`. A generic witness call from inside the extension does
not match the client existential ABI. When that call returns an `NSError`,
the getter invokes the Objective-C `localizedDescription` method on that
object with `perform`. Using the Swift property would call this extension
again. The `NSError` specialization dynamic-casts and branches to itself.

Otherwise the getter copies `CustomNSError.errorUserInfo`, then writes
non-nil `LocalizedError.errorDescription`, `failureReason`, and
`recoverySuggestion` onto `NSLocalizedDescriptionKey`,
`NSLocalizedFailureReasonErrorKey`, and
`NSLocalizedRecoverySuggestionErrorKey`. `errorDescription` replaces a
description already copied from `errorUserInfo`. `helpAnchor` has no Finch
key here. An empty dictionary is passed as nil userInfo. The failable
`NSError(domain:code:userInfo:)` result is required. The returned string is
that object's Objective-C method. For a simple domain and a nil userInfo
dictionary, the loaded method formats `"%@ error %ld"` from the domain and
code.

Prepare a fresh directory. The helper checks the pin license, checks the
recorded digests, and copies this slice. It names every `CocoaError.swift`
in the pin and does not copy those files:

```sh
python3 integrations/siliconforest/finch/Preview/ErrorDescription/prepare.py \
  --source /path/to/pinned/swift-foundation \
  --output /path/to/fresh/owned/error-description-sources
```

Compile `LocalizedDescription.swift` into the read-only combined Foundation
`e49ea43b71d3bcbb0c63c7b69df8fda74fdafb979e52d2376a2b99a34303b649` (5,292
exports: the URLError bridge plus PersonNameComponents). Append this source
to that module's file list. Keep `-D FOUNDATION_FRAMEWORK`. Use that
module's emit: whole-module optimization, library evolution, the
FoundationPreview availability macros, and the calendar, collections,
attributed-string, shim, API-notes, and NSRange overlay include paths. Link
with that baseline's C objects. Do not link `-lswiftFoundation` into this
dylib. Keep the install name `/usr/lib/swift/libswiftFoundation.dylib`, dead
stripping, and the alias from `_$sSo7NSErrorCs5Error10FoundationMc` to
`_$sSo10CFErrorRefas5Error10FoundationMc`. Keep the undefined
`_OBJC_CLASS_$_NSPersonNameComponents` class and its metaclass.

The separate client is `DescriptionProbe.swift` plus `symbols.c`. This dyld
prepends one underscore in `dlsym`, so the probe looks up
`$ss5ErrorP10FoundationE20localizedDescriptionSSvg`. Put the new Foundation
module first on the compiler search path. Link the client with
`-lswiftFoundation` and the same person-name undefined symbols.

The tested library is
`bed3c17185d4103f1b8737434506ab66c35c2fc6b561491ea00e712554f4a0c9`.
Against combined `e49ea43b71d3bcbb0c63c7b69df8fda74fdafb979e52d2376a2b99a34303b649`
the export trie is prior 5,292, new 5,294, lost 0, gained the getter at
`00000000000bf57c T` and the descriptor at `00000000001b92c0 S`. Frozen
`1fff856bea529b0a22d98b89de5a03c31ad0be3499595b445f6e51c2e64c64cc` and live
`d02a85edbe5ef478d32ab2f13e1c859524d9fbbf0fa630fbb089101a2093b66e` stayed
unchanged, as did `URLError.swift`
`d5d362a99af119f4329e70f281e79454cb59858d9c4d39d29a6b973cb67535e9`. Headless
receipt
`runs/preview/url-error-wt/runs/error-description/evidence/error-description-20261119T084327Z.json`
exited 0. The symbol resolved. An `NSError` in domain `SFNative` with the
description key compared identical to its embedded object and to the
Objective-C method (`sf-native-text`). Domain `SFNative` code 5 with nil
userInfo matched the method and `SFNative error 5`. A `LocalizedError`
matched `sf-custom-desc` and an `NSError` built from that error's domain,
code, and key. `LocalizedError.errorDescription` (`sf-both-desc`) replaced
the `CustomNSError` userInfo text on domain `SFDescDomain` code 9. A stored
`URLError` with `sf-url-desc` compared identical to `URLError._nsError` and
to that object's method. A `CustomNSError` with domain `SFPlain` code 3 and
no `LocalizedError` matched `SFPlain error 3`. Probe sha256
`240666f8962cd7765fd2ef9629e585b04902309d6c8f90b1420c5ee6d0263322`. Uploaded
bytes, QTP Foundation
`94a07b510d116a7cfb4f302708f1a3ee7286d4be9c94037b77db13dc48959c2f`, and
compositor PID 125 stayed unchanged. No AppIntents or Preview launch.

The loaded QTP `-[NSError localizedDescription]` raises SIGTRAP for an
`NSError` whose domain is the compiler type name
`DescriptionProbe.(unknown context at $…).Undescribed`. Receipts
`error-description-20261119T083855Z.json`,
`error-description-20261119T083920Z.json`,
`error-description-20261119T084048Z.json`, and
`error-description-20261119T084144Z.json` exited -5 on that domain. The
constructor itself succeeds. A description key on a type-name domain does
not trap. The passing probe therefore uses the `SFPlain` domain for the
no-key fallback. A bare Swift error whose only domain is that type name is
not a proven path. Receipts `error-description-20261119T082706Z.json` and
`error-description-20261119T083007Z.json` exited -11 when the getter called
the Swift property on the embedded `NSError`.

Machine-specific emit, link, and runner scripts stay in the ignored `runs/`
scratch. This slice does not replace the combined baseline.
