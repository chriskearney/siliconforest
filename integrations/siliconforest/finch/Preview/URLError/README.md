# URLError and _BridgedStoredNSError

AppIntents imports these six Foundation symbols:

- `_$s10Foundation21_BridgedStoredNSErrorPAAE_8userInfox4CodeQz_SDySSypGtcfC`
- `_$s10Foundation8URLErrorV4CodeV14unsupportedURLAEvgZ`
- `_$s10Foundation8URLErrorV4CodeVMa`
- `_$s10Foundation8URLErrorV8_nsErrorSo7NSErrorCvg`
- `_$s10Foundation8URLErrorVAA21_BridgedStoredNSErrorAAMc`
- `_$s10Foundation8URLErrorVMa`

`URLError.Code` is a struct, so its metadata spelling is `V`. `unsupportedURL`
is a static getter. Its raw value is the retained `NSURLErrorUnsupportedURL`
(-1002). Pinned swift-foundation `c20150400269a6afffe5b3a9f9fa8bbd51d69e1a`
has no `URLError.swift`. `sources.json` pins this original implementation.

`_BridgedStoredNSError` stores the object returned by the failable
`NSError(domain:code:userInfo:)`. A nil result traps. `URLError(_nsError:)`
requires `NSURLErrorDomain`. Value equality compares domain, code, and the
user-info dictionaries. Object identity is a separate `===` check. `Code`
getters are the retained `NSURLSession.h` values: unknown, cancelled, badURL,
timedOut, unsupportedURL, cannotFindHost, cannotConnectToHost,
networkConnectionLost, httpTooManyRedirects, notConnectedToInternet,
zeroByteResource, fileDoesNotExist, fileIsDirectory, noPermissionsToReadFile,
secureConnectionFailed, and serverCertificateUntrusted. An empty Swift
dictionary passed as userInfo stays a dictionary.

Prepare a fresh directory. The helper rejects a pin that already contains
`URLError.swift`, checks the recorded digests, and copies the Apache license
with the Swift exception from that pin:

```sh
python3 integrations/siliconforest/finch/Preview/URLError/prepare.py \
  --source /path/to/pinned/swift-foundation \
  --output /path/to/fresh/owned/url-error-sources
```

Compile `URLError.swift` into the coherent Foundation that already contains
CustomNSError, the Data munmap handoff, JSON, DateComponents, and
AttributedString. Do not compile the pin's `CocoaError.swift` or
`ErrorCodes+POSIX.swift`; those protocols and the stored-code POSIX and Cocoa
errors are already in that module. Keep `-D FOUNDATION_FRAMEWORK`. Use the
attributed-string emit: whole-module optimization, library evolution, the
FoundationPreview availability macros, and the calendar, collections,
attributed-string, shim, API-notes, and NSRange overlay include paths. Link
the new object with that baseline's C objects (`StringBridge`, `DataShims`,
`PlatformShims`, `StringShims`, `FGetAttrList`) and `CollectionsInternal.o`.
Do not link `-lswiftFoundation` into this dylib. Keep the install name
`/usr/lib/swift/libswiftFoundation.dylib`, dead stripping, and the alias from
`_$sSo7NSErrorCs5Error10FoundationMc` to
`_$sSo10CFErrorRefas5Error10FoundationMc`.

The separate client is `URLErrorProbe.swift` plus `symbols.c`. This dyld
prepends one underscore in `dlsym`, so the probe looks up the `$s…` spelling
of each `_$s…` export. Put the new Foundation module first on the compiler
search path, and pass the calendar and attributed-string includes to both
Swift and Clang. The client calls the protocol-extension initializer through a
generic.

The tested library is
`73e3f94b67eae0d46ac73600a26e68fdf9c31f566091ca85d5d98f43b1f3fea1`.
Against frozen `1fff856bea529b0a22d98b89de5a03c31ad0be3499595b445f6e51c2e64c64cc`
and live `d02a85edbe5ef478d32ab2f13e1c859524d9fbbf0fa630fbb089101a2093b66e`
the export trie is prior 5,141, new 5,231, lost 0, gained 90. Every gained
name contains `URLError` or `BridgedStored`. Headless receipt
`runs/preview/url-error-wt/runs/url-error/evidence/url-error-20261119T080050Z.json`
exited 0: symbols 6/6, domain `NSURLErrorDomain`, code -1002, the failing URL
round-trip, identical stored and embedded objects, and value equality of a
distinct twin. An earlier receipt, `url-error-20261119T075706Z.json`, exited 1
only because `dlsym` was given the export-trie spelling. The value checks in
that run passed. Uploaded bytes, QTP Foundation
`94a07b510d116a7cfb4f302708f1a3ee7286d4be9c94037b77db13dc48959c2f`, and
compositor PID 125 stayed unchanged. No AppIntents or Preview launch.

The PersonNameComponents provider's 61 added names are disjoint from these
90. This slice does not contain that bridge. Machine-specific emit, link, and
runner scripts stay in the ignored `runs/` scratch.
