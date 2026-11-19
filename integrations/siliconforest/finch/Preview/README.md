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
