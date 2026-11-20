# Staged QuickTime private dependencies

**Parked 2026-11-15 by owner direction:** Firefox media is the priority.
Keep all existing stages, evidence and installed providers. The last load
attempt still stops at missing Quartz.framework; no QuickTime startup or
playback is claimed and no additional launch is queued.

This builds eight minimal private frameworks from Linux/Nix and our own/PD
OSS declarations. No Apple SDK or native implementation bytes are inputs.
These providers do not supply Apple's private services:

| Framework | QuickTime imports supplied | Unavailable behavior |
|---|---|---|
| TCC | TCCAccessPreflight, TCCAccessRequest, kTCCServiceScreenCapture | Denied; asynchronous false once; no prompt/grant |
| PhotosFormats | PFSlowMotionUtilities, PFVideoAVObjectBuilder, PFVideoAdjustments | Mapper/asset factories and builder/adjustment initializers return nil |
| MediaRemote | MRMediaRemoteGetLocalOrigin, MRMediaRemoteSetNowPlayingTintColor | No origin; void setter reports no service |
| GeoKit | GEOManagedObjectContext, GEOCity, GeoKitPlace | No managed context/place store; initialization returns nil |
| MobileAsset | ASAttributeContentVersion, MAAsset, MAAssetQuery, MADownloadOptions | Queries/downloads return nonzero unavailable status; no local assets; empty results |
| MonitorPanel | MPDisplayMgr | No private manager; sharedMgr returns nil |
| PerformanceAnalysis | PAMarkOperationStart, PAMarkOperationEnd | No recording token; no telemetry |
| FeatureFlags | FeatureFlagsKey protocol and both property requirement descriptors | Actual compiler-emitted Swift metadata; feature queries false |

FeatureFlags is a genuine Swift protocol/library, not three guessed exports.
Its protocol shape comes from Finch (MIT/Apache-2.0); the Swift compiler and
runtime are SiliconForest's source builds. A separate Swift conformance probe
checks existential/witness behavior. This is not a complete FeatureFlags API.

Our Linux-built native metadata probe loads the named frameworks and prints
class/method encodings and the MobileAsset version key. It does not invoke
services, permission requests, downloads or native implementation bytes.
M5 reference evidence: runs/sffinch/m5-quicktime-private-metadata-v1-results.json
(296lines; successful SHA check,30s bound, fresh deleted /tmp directory, no
DYLD overrides). Observed MobileAsset key is _ContentVersion. PhotosFormats'
source-duration argument is double and rate is float; its CMTimeRange layout
matches our declarations. Only selected required method layouts are declared.

REA opened the already-held QuickTime26.5.2 artifact9fff9ad…; Ghidra/Hopper/IDA
remain unavailable. Local LLVM call-site observations are ordinary offline
inspection, not REA decompilation. TCC takes service/options and a completion
block; preflight compares a32-bit result0/1/2. MediaRemote origin is an object;
tint receives that object and four floats. GEOManagedObjectContext receives
a Boolean. PerformanceAnalysis' caller supplies two pointer-sized arguments.

FigAssetCreateWithURL remains unimplemented: this binary only takes its address
for a registry; neither its callable ABI nor ownership is established. No
unsafe return-value stub is added merely to satisfy dyld. MediaToolbox's public
void professional-reader opt-in now emits an explicit unavailable diagnostic
once, since no MediaExtension registry exists. It registers no reader or asset.
The public declaration is documented by
[Apple](https://developer.apple.com/documentation/MediaToolbox/MTRegisterProfessionalVideoWorkflowFormatReaders()?language=objc).

Build build.nix, tests.nix, swift-test.nix and ../MediaToolbox/build.nix. The
failure-contract probe is M1-only (SF_QT_PD_ONLY plus /dev/sfavd); never use it
against Apple's services on the M5. Native-probe.nix is the metadata-only
reference. Providers remain staged; no installed framework is replaced.

Current source build/export audit: all 21 imported symbols across these eight
frameworks resolve, including all three Swift protocol imports. The complete
v4 scan has 965 imports, 158 strong gaps, 40 missing classes and 466 selectors
implemented by no image of its closure. Its root is the cached player-root-v3,
overlaid with our coherent AVFoundation/AVKit player package v2, these private
providers, MediaToolbox, the previously qualified WebKit absence provider and
the CoreMediaIO absence provider. This inventory is not runtime evidence or a
fresh installed-system snapshot. See runs/sffinch/quicktime-private-scan-v4.
The v5 offline audit incorporates the final, independently qualified coherent
player artifact and retains those same counts; remaining imports are grouped
in runs/sffinch/quicktime-private-scan-v5/remaining-grouped.json. A corresponding
fresh quicktime-load-v5 is prepared but has not executed; v4 remains the latest
actual QuickTime load result.

M1 failure-contract stage-v2 now passes both programs:8 frameworks/9 classes,
exactly one denied TCC callback, one failed catalog and one failed query callback,
plus a real Swift existential/witness call. All prefix bytes were cold-verified
before loading. These are unavailable-service and ABI fixtures, not native
service parity. Photo/GEO absence classes have NSObject-based shells; they do
not provide the native private adjustment/CoreData storage hierarchy, and their
initializers return nil.

Actual unchanged staged QuickTime loads: v2 aborts in dyld at absent WebKit in
0.052 s; v3 adds our already-qualified unavailable WebKit facade and reaches
absent CoreMediaIO in 0.028 s; v4 adds CoreMediaIO and reaches absent
Quartz.framework in 0.028 s. All return -6 before application startup, with no
timeout or controller signal. Raw failures and cold-file verification receipts
remain in runs/sffinch/quicktime-load-v{2,3,4}. No window or playback is claimed.
The small CoreMediaIO absence provider is built separately from the public
[seven-argument getter contract](https://developer.apple.com/documentation/coremediaio/cmioobjectgetpropertydata(_:_:_:_:_:_:_:)?language=objc):
nonzero unimplemented status, dataUsed=0, output unchanged, no capture objects.
Its M1 negative fixture passes in
runs/sffinch/coremediaio-unavailable-stage-v1/candidate.json. These are stages
only, not camera or private-service implementations; nothing was installed.

`vt-queries.nix {}` stages two additive VideoToolbox queries above an exact
retained decoder/encoder child. All172 child exports and its entire text
section remain unchanged; the wrapper's effective exports total174. Public
[extension-property query contract](https://developer.apple.com/documentation/videotoolbox/vtcopyvideodecoderextensionproperties?language=objc)
and [stereo capability contract](https://developer.apple.com/documentation/videotoolbox/vtisstereomvhevcdecodesupported()?language=objc)
are implemented truthfully: the retained H264/HEVC/VP9 codec family is built in,
no MediaExtension dictionary exists, and multiview output is unsupported.
The native Linux-built query observes-19510 for H264/HEVC and-12906 for an
unknown codec, leaving the output slot untouched on failure. The source uses
those same error/ownership facts; the output is never a fabricated extension.
Native M5 stereo support is true; this platform must report false. That is a
capability difference, not a reason to fabricate multi-image decoding.
The M1 `media-private-controls-v3` query completed at19:39Z with exit0: the
three extension statuses and unchanged output slots match the same-byte M5
reference; stereo reports false as required here. They cover the final two
missing reviewed VT imports. This is a public query fixture, not a decoder
execution or canonical replacement. Actual QuickTime remains the v4 Quartz
loader failure, despite this later export/query evidence.

## Loader libraries (17 November 2026, SF-AI)

`loader.nix` builds the six libraries QuickTime Player's load commands name that no
earlier stage had: SwiftUI, DeveloperToolsSupport, the Swift `os` module
(`libswiftos.dylib`), QuickLook, QuickLookUI and the Quartz umbrella. The last real
load (v4, above) stopped at the first of them.

| Library | Symbols bound by QuickTime Player | What it is |
|---|---|---|
| SwiftUI | 34 | A binding subset written here (`loader/SwiftUI.swift`): the `View` protocol with its hidden requirements, `Text`, `Image`, `Button`, the frame modifier, conditional content. Compiler-emitted Swift metadata with library evolution; no renderer. Anything that would draw stops with a message |
| DeveloperToolsSupport | 2 | `ImageResource` and `ColorResource` as a name and a bundle |
| libswiftos | 2 | `os.Logger` creation over libSystem's `os_log_create` |
| QuickLook | 3 | No thumbnail generators: `QLThumbnailImageCreate` returns NULL, as documented when none can be made |
| QuickLookUI | 1 | No preview panel: there is never a preview to open a document from |
| Quartz | 0 | Umbrella that re-exports QuickLookUI |

The application contains one SwiftUI view and imports no hosting class, so the
subset is expected to be needed for binding only. That is an inference from the
import table, not an observation.

CGFloat: SwiftUI's frame modifier is mangled with `CoreGraphics.CGFloat`, which our
Swift CoreFoundation overlay does not define. The recipe compiles Finch's
`userland/swift/overlays/CoreFoundation/CGFloat.swift` (Apache-2.0 with the Swift
Runtime Library Exception; from the Swift project's historical overlay) into the
subset from the pinned Finch source and ships its licence beside it. Its proper home
is `libswiftCoreFoundation`; when the Swift runtime build gains it, drop it here.

`loader-check.nix` runs `loader/check_exports.py`: every name in
`loader/imports.json` must be exported by the library with that install name. It
passes, 42 of 42. This is a static prediction of dyld's verdict on these six
libraries; nothing has been loaded on SiliconForest. With these libraries laid over
the 15 November copy of the system and the stages above, `sf_gapscan.py` reports no
required library missing and 112 symbols unbound (153 without them).
`docs/roadmap/issues/SF-AI-quicktime.md` has the table and the plan.

`../Network/toolchain.nix` needed one correction for any Swift source that imports
Foundation: the kernel-private `sf_pthread_sched.h` is kept out of the generated
Darwin module, as `../../rebase/swift-darwin-module.nix` already does for the Swift
runtime build.

## Additions and the private prefix (18 November 2026, SF-AI)

The loader libraries above, and everything below, are for one private prefix that only
QuickTime Player's launcher names through `DYLD_FRAMEWORK_PATH` and `DYLD_LIBRARY_PATH`.
None of it is to be installed at a system path: the SwiftUI is a binding subset, and a
real SwiftUI program must never find it.

`additions.nix` builds, for each of 17 system frameworks from which QuickTime Player
binds names SiliconForest lacks, a small library that is placed at that framework's path
in the prefix. It defines the missing names (`additions/*.m`, `plain.c`) and re-exports
`@loader_path/<Name>.sf-under`, which `qt_prefix.py` makes a symbolic link to the
system's own image of the framework (or, for AVFoundation, MediaToolbox and WebKit, the
staged provider). The process loads the system's file once; no system file changes.
`additions/standin.m` exists only so that the linker has something with that name.

Its install name is `<framework path>.sf-additions`, never the framework's own: dyld
folds a library onto any loaded image with the same install name (`checkandAddImage`),
and with equal names the system image was folded onto ours. That broke the first run on
the M1 (load failures, and a stack overflow in dyld's symbol search through a re-export
cycle); `docs/roadmap/issues/SF-AI-quicktime.md` has the details. `qt_prefix.py` refuses
a prefix with an install name twice on a re-export chain, and a class that both our
libraries and a loadable system image define. `NSFileWrapper` is AppKit's class on this
system, so Foundation's additions re-export it (`additions/foundation-reexports.txt`).

`additions/symbols.json` lists all 112 names with what each is: real, constant, model or
absence. An absence binds, and when used fails as its interface documents and says so
once on stderr. `additions-check.nix` verifies 112 of 112 are exported from the right
library; the kind of each (code or data) matches how the application binds it.
`../AVKit/SFQuickTimeControls.m` holds the AVKit ones.

`qt_prefix.py --out PREFIX --root / --additions ... --stage ...` assembles the prefix and
reports names that the system image now exports itself; pass those to
`additions.nix { omit = [ ... ]; }` (the `SF_OMIT_` guards in `additions/AppKit.m` show
the pattern; add a guard where one is needed). `additions-probe.m` is our own check of an
assembled prefix on SiliconForest: symbol lookups through the real dyld, then behaviour.

Offline, against the 15 November copy of the system: 965 imports, none unbound. On the
M1 (18 November, probe only, no window): all 154 names found by the real dyld through the
prefix, every behaviour check passes, each system image loaded once. QuickTime Player
itself has not been loaded yet.

## Names moved into the frameworks (18 November 2026, SF-AI)

28 of the 112 names were general, not QuickTime Player's alone, and now live in the
frameworks: Cocoa patches 0340-0347 (`../../cocoa/patches`: AppKit, CoreGraphics,
QuartzCore, CoreAudio, libFoundation) and the framework wrappers of
`../../terminal-app/compat` (the URL key names, `NSFileCoordinator`). `additions.nix`
leaves them out by default (`-DSF_MOVED`), and then builds no additions for CoreFoundation
or CoreAudio at all; `additions.nix { movedInFrameworks = false; }` still builds the full
set, for a system without those frameworks (the M1 as installed on 18 November; the load
test uses it). `additions/symbols.json` says for each name what provides it
(`provided_by`); `additions-check.nix` checks the full set, the shrunk set and the
frameworks separately.

