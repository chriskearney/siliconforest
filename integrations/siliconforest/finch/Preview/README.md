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
failure behavior, not Apple's complete private ABI or Preview UI. Preview
execution remains paused while its backing-page PAC mutation is addressed.

## Taken from Finch

| Pinned source | Use and SiliconForest changes |
|---|---|
| `2d9b1bb1af57e14462e4621d194929188a8845b0:userland/RecapPerformanceTesting/RecapPerformanceTesting.m` | Runner properties and method shapes; parameter storage pattern. Replaced successful no-op execution with explicit unsupported errors/exceptions; added the imported activation parameter class. MIT OR Apache-2.0, notices and both license texts retained. |

Do not deploy by overwriting the existing private app bundle, shared libraries,
or QTP's runtime. App bytes and extracted interface evidence stay in ignored
private staging; this directory contains only open source and observed names.

The next narrow provider and its measured Swift build prerequisites are
documented in [VISIONKIT.md](VISIONKIT.md). It is a separate static candidate;
Recap's successful runtime proof does not qualify VisionKitCore.

[PAPERKIT.md](PAPERKIT.md) describes the next view adapter, private URL overlay,
measured M1 results and remaining limits. Preview's latest observed loader stop
is ModelIO; its application bytes remain unchanged and no UI is claimed yet.
