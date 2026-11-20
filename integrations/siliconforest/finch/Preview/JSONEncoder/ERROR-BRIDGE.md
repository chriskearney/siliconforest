# NSError runtime conformance lookup

The standalone Data probe found a real error-boxing abort in the earlier
`d023b891...` decoder and `98a10e05...` encoder libraries. The real NSError
conformance existed, but Swift's runtime dynamically looks up
`$sSo10CFErrorRefas5Error10FoundationMc`.

The open Swift runtime `stdlib/public/runtime/ErrorObject.mm`,
`getNSErrorConformanceToError`, explicitly permits the NSError and CFError
witness tables interchangeably because those error references are toll-free
bridged. Grok proved the alias on the decoder library. The combined encoder
was relinked from the **same exact objects**, adding only:

```text
-Wl,-alias,_$sSo7NSErrorCs5Error10FoundationMc,_$sSo10CFErrorRefas5Error10FoundationMc
```

The new name points at the real existing NSError conformance descriptor. No
new conformance body, fake Error value or guessed metadata is added. The source
and new alias have the same address, the `__TEXT,__text` bytes are identical,
and every one of the prior 1,805 exports is preserved (1,806 total).

Private relink: `runs/preview/app-private/foundation-error-bridge/build/libswiftFoundation.dylib`.
SHA-256:
`f7978f22b3ea665a5bfa013723ffcfab765a1b44f9ddf9ee895125dfae382653`.
Static receipt: `foundation-error-bridge/linked-static.json` under app-private.

`error-probe.swift` is a separate client of the proven encoder Foundation module.
On M1 (PID 2791, exit 0), it boxes actual NSError objects, checks domain/code,
user info/nullability and original identity, propagates the NSError through
custom encode/decode calls, examines the malformed JSON parser's actual
underlying Cocoa error (3840), and reuses both codecs after failures. The
unchanged Data probe (2792), encoder (2793), decoder (2794), UUID (2795) and
URL/localization (2796) also exit 0 against the relink. The Data probe checks
actual file/atomic replacement and mode 0640, without claiming mapped reads.

Receipt: `runs/preview/app-private/evidence/foundation-error-bridge-20261119T070105Z.json`.
All nine packet files and protected QTP Foundation bytes remain unchanged;
gui.lock, owner-idle guards and compositor PID 125 are preserved. No Data source
edits, shared installs or app-prefix changes occurred. The original tested
decoder and encoder artifacts remain in place.

## Next observed standalone gate

A single private standalone open AppIntents `dlopen` (PID 2825) with this
candidate clears JSONEncoder and first stops at
`_$s10Foundation14DateComponentsVMa`. It exits 1 before successful loading.
All six packet files and QTP Foundation hashes remain unchanged. No Apple
Preview executable was run.

M1 receipt: `runs/preview/app-private/evidence/appintents-errorbridge-20261119T070326Z.json`.
REA's bounded host-wrapper capture is
`ev_9e889af8474773431454398e9a908fcdd40ed7710c74212a4a94cd80a42e07e8`;
the complete private bundle is `foundation-error-bridge/rea-process-evidence.json`.
REA captures the Linux wrapper, not a direct remote-inferior trace; the native
PID, exact dyld stop and M1 byte checks come from the remote receipt.
No syscall/filesystem completeness is implied by that capture.

The mapped-read deallocator bug found by the independent Data work remains
unfixed in this candidate. ISO8601 date formatting remains explicitly unavailable.
