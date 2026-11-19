# Private Preview provider candidate

`recap.nix` cross-builds RecapPerformanceTesting and `bin/recap-probe` on Linux.
It exports the two classes named by the owner-provided Preview executable:
`RPTTestRunner` and `RPTActivationTestParameters`. `NOTICE` records the pinned
Finch provenance, interface evidence and unsupported recording behavior.

```sh
nix-build --extra-experimental-features 'nix-command flakes' --no-out-link \
  integrations/siliconforest/finch/Preview/recap.nix
nix-build --extra-experimental-features 'nix-command flakes' --no-out-link \
  integrations/siliconforest/finch/Preview/recap-check.nix
```

The output has the exact framework install name and versions Preview requests;
it can be added to an individually owned private framework search directory.
Neither recipe installs anything or contacts the M1. The static check validates
class/metaclass exports and each output's direct undefined imports against the
open build providers. It does not validate Preview's entire load closure.

The probe checks that recording is unavailable, readiness returns an error,
error callbacks receive an NSError exactly once, void-only operations throw
an explicit unsupported exception, and success completion blocks never run.
The standalone thin arm64 probe passed on the M1 on 19 November 2026: exit 0,
four error callbacks and zero success completions. Probe and provider SHA256
digests were unchanged before/after execution. This used an individually owned
scratch prefix and HOME with the existing private Foundation provider. There
was no GUI/session access or global install. This validates the recorded
failure behavior, not Apple's complete private ABI or Preview UI. The coordinator subsequently fixed the backing-page PAC mutation and
verified the original arm64e integrity probe; fresh P1–P4 app launches retained
all bundle bytes and stopped before UI at successive missing providers.

## Taken from Finch

| Pinned source | Use and SiliconForest changes |
|---|---|
| `2d9b1bb1af57e14462e4621d194929188a8845b0:userland/RecapPerformanceTesting/RecapPerformanceTesting.m` | Runner properties and method shapes; parameter storage pattern. Replaced successful no-op execution with explicit unsupported errors/exceptions; added the imported activation parameter class. MIT OR Apache-2.0, notices and both license texts retained. |
| `2d9b1bb1af57e14462e4621d194929188a8845b0:userland/CoreSpotlight/CSSearchableItem.m` | Attribute dictionaries, bounded field names/KVC and copy, custom-key validation/storage. Scoped to two model classes; typed common fields replace forwarding, unavailable archive operations reject explicitly. No index/query adoption. MIT OR Apache-2.0, notices and both license texts retained. |
| `2d9b1bb1af57e14462e4621d194929188a8845b0:userland/QuickLook/{QuickLook.m,QuickLookUI.m}` | Three data keys and scoped item/model/view lifetime; actual image/PDF loaded state, draw and bounds. No panel/generator or fake loaded/page success. Existing QTP absence API retained. MIT OR Apache-2.0, both Finch licenses and original QTP MIT notice retained. |

Do not deploy by overwriting the existing private app bundle, shared libraries,
or QTP's runtime. App bytes and extracted interface evidence stay in ignored
private staging; this directory contains only open source and observed names.

The next narrow provider and its measured Swift build prerequisites are
documented in [VISIONKIT.md](VISIONKIT.md). It is a separate static candidate;
Recap's successful runtime proof does not qualify VisionKitCore.

[PAPERKIT.md](PAPERKIT.md) describes the next view adapter, private URL overlay,
measured M1 results and remaining limits. Preview's latest observed loader stop
was ModelIO at that checkpoint. A subsequent zero-API load-contract carrier
([MODELIO.md](MODELIO.md)) advanced the actual stop to AnnotationKit. Application
bytes remain unchanged; no Preview UI is claimed yet.

[ANNOTATIONKIT.md](ANNOTATIONKIT.md) describes the next original reader model
and overlay candidate, its semantic probe and explicit capability limits.

The AnnotationKit standalone reader probe subsequently passed on M1, including
actual rectangle pixels and NSError payloads. Unchanged Preview loaded it in P5;
P6, with tested ImageCaptureCore, now stops at CorePDF before UI. See the
AnnotationKit document for exact scope; no general annotation editor is claimed.

[CORESPOTLIGHT.md](CORESPOTLIGHT.md) describes the scoped Finch attribute model
and typed Swift initializer for the AppIntents build, with explicit UTType input.

[TRANSPORT.md](TRANSPORT.md) records the native PAX long-link failure, exact
PerformanceAnalysis check and fresh-only extraction with literal link readback.

[QUICKLOOK.md](QUICKLOOK.md) describes the scoped, M1-tested QuickLook
reader and the exact existing API it preserves. Preview remains before UI.

[UUID.md](UUID.md) describes the additive open Swift Foundation UUID slice,
exact native import coverage and guarded standalone M1 proof. This candidate
does not replace the coordinator's newer Foundation overlay or launch Preview.

[JSONDecoder/README.md](JSONDecoder/README.md) records the real pinned decoder
port preparation, passing cross-typechecks and exact native arm64 object exports.
The coherent module links with Grok's Data/syscall handoff. Its standalone M1
decoder, unchanged UUID and URL/localization consumers pass with every prior
export and artifact hash preserved. ISO8601 dates remain explicitly unavailable.

[JSONEncoder/README.md](JSONEncoder/README.md) adds the real pinned encoder and
writer to the same coherent Foundation. Separate-client encode/re-decode and
unchanged decoder/UUID/URL M1 probes pass, preserving all 1,691 prior exports.

[DateComponents/README.md](DateComponents/README.md) adds the pinned real date
component value with bounded CoreFoundation calendar conversion. Its M1 proof
passes; the standalone AppIntents loader next reaches AttributedString metadata.

The [AttributedString reader slice](AttributedString/README.md) prepares real open
text/runs/attribute/Codable values over retained Swift Collections. Its native
proof advances the standalone AppIntents loader to PersonNameComponents; it
does not establish an Apple Preview launch.

[PersonNameComponents/README.md](PersonNameComponents/README.md) adds the Swift
5.4 name-component overlay and its bridge to the retained NSPersonNameComponents
class. The observed AppIntents stop after AttributedString is that bridge.

The [P13 preparer](P13/README.md) builds a deterministic private packet and guard
manifest locally, with execution explicitly disabled. Its audit separates
observed loader/file evidence from predicted future dependency gaps.

[URLError/README.md](URLError/README.md) adds the stored NSError bridge and
URLError codes required by the AppIntents audit. The separate-client M1 probe
passes with all 5,141 prior Foundation exports retained.

[ErrorDescription/README.md](ErrorDescription/README.md) adds the
`Error.localizedDescription` getter on the combined URLError and
PersonNameComponents Foundation. The separate-client M1 probe passes with
all 5,292 combined exports retained. The getter is the new AppIntents
binding. Library evolution also emits the property descriptor.

The [URL resource reader](URLResourceValues/README.md) adds pinned value storage
and a real retained-NSURL/content-type adapter, with the exact Swift getter and
prior exports verified natively. Directory package metadata remains explicitly
unsupported; this is independent of the AppIntents CoreGraphics loader gate.

[CoreFoundation CGFloat](CoreFoundationCGFloat/README.md) puts the validated
CGFloat object on `libswiftCoreFoundation`. The public install name and the
eight live exports stay, and the separate-client M1 probe calls the dylib
arithmetic. It does not launch AppIntents.

[TipKit](TipKit/README.md) is a scoped Finch store for the missing Preview
image `/System/Library/Frameworks/TipKit.framework/Versions/A/TipKit`.
Forty of Preview's forty-two TipKit imports are real exports. The predicate
conformances and the event `Rule` initializer are in the trie. The linked
Foundation is the tested p9 image. M1 PID 7552 ran the predicate comparison
rules against that image. `SwiftUI.View.popoverTip` stays absent. `TipGroup.currentTip`
uses the real `@Observable` macro. The headless client calls configure,
donate, a closure rule, a `Comparison` of two `Value`s, invalidation,
`MaxDisplayCount`, and both group priorities.

[MapKit](MapKit/README.md) is the full renderer-dependent `_MapKit_SwiftUI`
source: Web Mercator land and markers, `Marker<Label: View>`, and an
`NSViewRepresentable` body. The Linux compile did not emit the framework.
The P13 SwiftUI subset has no `Namespace` or `NSViewRepresentable`.

### Linux SwiftUI graph/source lane

`SwiftUI/README.md` records the pinned OpenSwiftUI/Finch source preparation,
scoped observation and Accessibility corrections, and the Linux Swift 6.3.3
Compute/OAG graph proof on M1. Graph updates, metadata and body destruction,
canonical Observation collection and real Edge values are verified separately.
Full SwiftUI layout/popover and the unmodified Preview UI remain unproven by
this lane. Temporary diagnostic headers are explicitly excluded from provider
qualification. No app launch, shared install or active-prefix change is added.
