# Scoped PaperKit view adapter

Preview imports three Swift entries from PaperKit: PaperViewController's
metadata/accessor and `display(_:readOnly:)` dispatch thunk. This original
adapter subclasses the open AppKit NSViewController. Local images are decoded
by NSImage and placed in NSImageView; PDFs are passed to the coordinator's
PDFDocument/PDFView implementation when those classes are loaded. Read/decode
errors and an unavailable PDF provider raise an exception with an underlying
NSError. No successful no-op display, fabricated document or metadata cast is
used. The adapter offers no editing or saving operation.

The private API's class was not exposed by the reference Mac's public SDK.
Observed Preview calls establish Swift metadata -> Objective-C class ->
alloc/init and the exact display entry type. Only names and observed call
behavior informed this code; no Apple framework implementation or assets were
copied. This is not a complete PaperKit implementation.

## Private Foundation prerequisite

The installed Swift Foundation overlay lacked URL. `foundation-url.nix`
rebuilds the existing open overlay sources, including the existing dictionary
and NSNumber bridges, with a scoped NSURL-backed URL value/bridge. It keeps
all 227 measured installed exports and adds 31 URL symbols. It uses its own
compiler SDK; the NSDate NSCopying declaration comes from the existing
runtime recipe, and implemented NSObject description getters have the
nonoptional contract needed by the Swift conformances. Shared headers and
installed libraries are untouched. An explicit modular Foundation import in
PaperBridge.h preserves imported class identity across the Swift/Clang bridge.

This URL subset does not supply URLResourceValues, bookmark handling, or
security-scope grants. The grant query returns false. Its implementation must
not be described as general Foundation or AppIntents support.

| Open upstream input | Use and provenance |
|---|---|
| Swift `swift-5.4.3-RELEASE`, `stdlib/public/Darwin/Foundation/URL.swift` | Scoped value storage, constructors and Objective-C bridge patterns; copyright and Apache-2.0 WITH Swift-exception notice retained in FoundationURL.swift. |
| Existing PureDarwin/SiliconForest Swift overlay recipe | Same Foundation/String/Date/collection source subset and patches, NSString helper and SFBridging. Recompiled coherently rather than registering duplicate conformances beside the old image. Original source notices and Swift license accompany the output. |
| Original SiliconForest code | PaperViewController, native image/PDF bridge, probes, recipes and static checks; MIT. |

## Validation and limits

The M1 URL probe passed Objective-C identity bridging, 10,000 retained copies,
hashing, and the existing string/dictionary/date bridges. The PaperKit probe
passed exact symbol resolution, real NSViewController initialization and the
Swift URL -> explicit nonlocal-input error path. A real coordinator PNG with
spaces in its copied filename decoded to a 240x180 image and installed an
NSImageView. No window was requested; this is not an on-screen rendering proof.
Probe, provider, private Foundation and fixture hashes stayed unchanged.

The next bounded unmodified Preview launch loaded this provider and the
coordinator's MediaAccessibility/Synapse candidates, then stopped at missing
ModelIO. All 174 application files remained identical to the owner source.
No Preview UI or general PDF-view acceptance is claimed. PDF behavior still
requires the coordinated provider and separate tests. All execution used
owned prefixes/HOME; AppKit tests held gui.lock with owner-idle guards. The
existing private AppKit wrapper's duplicate-class warning remains in evidence.

```sh
nix-build --extra-experimental-features 'nix-command flakes' --no-out-link \
  integrations/siliconforest/finch/Preview/paperkit-check.nix
```

The private output can override libswiftFoundation only for its own process.
Do not install it globally, overwrite QTP's runtime or replace the preserved
p0 app. Private receipts and raw loader output remain outside tracked code.
