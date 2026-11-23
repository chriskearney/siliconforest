# SiliconForest Installer for macOS

A fullscreen installer that runs in macOS, sets up SiliconForest beside macOS on an Apple silicon
Mac, hands over to recoveryOS for the one step only recoveryOS can do, and can remove an install
again. The first supported Mac is the 13-inch MacBook Pro with M1 (J293, t8103).

**State (23 November 2026): milestone M3, the engine on disk images.** The app's flow is still a
dry run. The real engine (`SFEngine`) runs real `diskutil`, `newfs_msdos` and raw writes, but **only
on disk images it creates under `installer/mac/.build-images`**. One chokepoint refuses every other
device. Nothing in this package has written to a real disk, and nothing runs `sudo`, `bless`, `bputil`,
`kmutil`, `nvram` or `csrutil`. See [What is real](#what-is-real-and-what-is-simulated).

Screenshots: [`docs/installer/screenshots/`](../../docs/installer/screenshots/).

## Layout

Module names follow [`docs/installer/DESIGN.md`](../../docs/installer/DESIGN.md) §4; screens and copy follow
[`UX-FLOW.md`](../../docs/installer/UX-FLOW.md); the look follows [`VISUAL-DESIGN.md`](../../docs/installer/VISUAL-DESIGN.md)
("night to dawn"); sizing, classification and step states follow [`ENGINE.md`](../../docs/installer/ENGINE.md).

| Target | What it is |
|---|---|
| `SFIdentity` | The one place the Developer ID team (`Z642ZK8JK4`) and the frozen identifiers live, with the designated-requirement strings the app, helper and recovery binary pin each other with. |
| `SFInstallKit` | The read-only half: profile loading (canonical `installer/profiles/*.json`), disk model and classification, ENGINE §4 sizing, compatibility, the simulator's planner and runner, read-only disk backends. No UI. |
| `SFEngine` | **The acting half (M3).** `ImageGuard` + `ImageChokepoint` (the image-only door for every change), typed verbs and the `Gate` (ENGINE §6), the hash-chained journal (§9), plan and binding (§5), the step machine S00–S70 / U10–U40 with idempotent checks, resume and rollback (§7), the resize supervisor (§8), `DiskImageBackend`, J293/J313 image fixtures, a rehearsal release, diagnostics redaction. |
| `SFHelperKit` | The helper's verb-only NSXPC protocol (`SFHelperXPC`), `HelperService` (owns the journal, runs jobs, short-lived), connection trust (signing requirement + minimum client build), `SecureBytes`, the LaunchDaemon layout and the SMAppService registration path (not called in this build). |
| `SFHelper` | The launchd executable over SFHelperKit. Its Info.plist is linked in (`org.siliconforest.installer.helper`). This build has no live-disk backend, so its disk verbs answer `noTarget`. |
| `SFRecoveryKit` | recoveryOS logic, Foundation only: the fail-closed gate (R10), `bputil -nc` and `kmutil configure-boot` through `PTYDriver` with password redaction (R20, R30), markers (R40), next-start-only `bless` (R50). It shares state markers with `sf-step2.sh`. |
| `SFRecovery` | The recoveryOS app: AppKit and Core Graphics only, minimum macOS 13.0. It exits 0 when finished and 75 on Shut Down; any other exit makes `sf-launcher` open Terminal. `--snapshot` renders offscreen. |
| `Recovery/` | `sf-launcher` (DESIGN §7.1) and `sf-step2.sh` (the Terminal fallback). |
| `SFCopy`, `SFDesign`, `SFFlow`, `SFInstaller` | Strings, design system, screen state machine, the app (unchanged in M3 apart from layout fixes). |
| `sfinstallctl` | The engine from the command line, including `image-rehearse`. |
| `SFInstallKitTests` / `sfinstallkit-selftest` | Swift Testing suites: one `swift test` bundle, plus the same tests as an executable for Macs with only the Command Line Tools. |

```
Sources/SFInstallKit/Model      DeviceProfile + CanonicalProfile (schema decoder), DiskModel (+ classification), SystemFacts, Bytes
Sources/SFInstallKit/Engine     Compatibility, Sizing, Plan, DiskOperation, Journal, InstallRunner
Sources/SFInstallKit/Backends   DiskBackend, SimulatedDiskBackend, RealDiskBackend (read-only)
Sources/SFEngine/Safety         ImageGuard, ImageChokepoint, ForbiddenTools, Query (read-only shapes)
Sources/SFEngine/Disk           Topology (by partition UUID, layout digest), DiskImageBackend, ImageFixtures
Sources/SFEngine/Journal        ChainJournal (hash chain, fsync, torn tail), Diagnostics (redaction)
Sources/SFEngine/Plan           EnginePlan, EnginePlanner (install, removal, bind)
Sources/SFEngine/Engine         Gate, InstallEngine + Steps (S00–S70, U10–U40), ResizeSupervisor, RehearsalRelease, RecoveryPayload
Sources/SFHelperKit             HelperXPC, HelperService, Trust (policy, SecureBytes, lifecycle), HelperClient, HelperBundle
Sources/SFRecoveryKit           PTYDriver, RecoverySetup
Recovery/                       sf-launcher, sf-step2.sh
Fixtures/disks/*.json           fake Macs: j293-512, j293-512-installed, j293-512-devinstall (hand-made, sf.unproven), j293-256-full, j313-256 (the Air)
```

Device profiles are the canonical `installer/profiles/*.json` (J293 and J313 today); there is no
fixture profile. J313 loaded without engine changes, which is the point of the profile layer.

## Build, run, test

Runs on macOS 13.5 or later (D10); builds with Swift 6 (Command Line Tools are enough).
`scripts/fetch-fonts.sh` fetches Inter and Source Code Pro (OFL, pinned by SHA-256) into `build/fonts`.

```sh
cd installer/mac
scripts/test.sh                      # every suite, serially (about 20 minutes: the image suites run real diskutil)
SF_IMAGE_TESTS=0 scripts/test.sh     # without the disk-image suites (seconds)
SF_FULL_SWEEP=1 scripts/test.sh      # fork at every journal record, not a sample (about an hour)
swift run SFInstaller --windowed     # the app in a window (dry run)
swift run SFInstaller                # native full screen in its own Space; Esc leaves full screen, ⌘Q asks
scripts/make-app.sh                  # build/SiliconForest Installer.app (release, ad hoc signed)
```

Results on 23 November 2026, on the M5:
- All 66 tests in 15 suites passed, 0 failed: 57 non-image tests and 9 disk-image tests.
- `SF_FULL_SWEEP=1` forked at all 67 records of an install. 66 forked resumes reached the handoff, and
  65 forked rollbacks restored the original partition table (the end record has no rollback).
- The sweep also forked at all 40 records of a rollback. All 40 resumed rollbacks finished, restoring
  the table with the Linux partitions untouched.

`SF_KEEP=1` keeps the per-test images and journals. `SF_REBUILD_TEMPLATES=1` rebuilds the template images.

App options:

| Option | Effect |
|---|---|
| *(none)* | Dry run against the simulated J293 disk (`j293-512`) |
| `--fixture j293-512-installed` | A Mac with SiliconForest already installed (Remove SiliconForest…) |
| `--fixture j293-512-devinstall` | The development M1's hand-made layout: refused ("not from this installer") |
| `--fixture j293-256-full` | A Mac that fails the checks (full disk, on battery) |
| `--fail-step writeSystem` | Inject a failure in a step to see rollback (any `StepID`) |
| `--speed 0.3` | Faster dry run (1 is the default pace, about a minute and a half) |
| `--real` | Read-only analysis of this Mac (never writes) |
| `--appearance dark` / `light` | Force an appearance (default: follow macOS, VISUAL §9) |
| `--windowed` | Stay in a window instead of entering full screen |
| `--snapshot DIR [--sizes 1280x800@2,1512x982@2] [--only 04-disk] [--appearance dark]` | Render every screen offscreen to PNG; no window is opened |
| `--render-icon DIR` | Write the `.iconset` used by `make-app.sh` |

`sfinstallctl`:

```sh
swift run sfinstallctl check                         # compatibility, dry-run fixture
swift run sfinstallctl check --real                  # this Mac, read-only
swift run sfinstallctl plan --size 80G               # every command the install would run, with its undo
swift run sfinstallctl install --speed 0 --fail-step writeSystem   # dry run with rollback
swift run sfinstallctl uninstall --speed 0           # dry-run removal of j293-512-installed
swift run sfinstallctl rehearse --real --size 60G    # plan against this Mac's real layout; records, runs nothing
swift run sfinstallctl journal ~/Library/Application\ Support/SiliconForest\ Installer/Journals/<file>.jsonl
```

## The engine on disk images (M3)

```sh
swift run sfinstallctl image-rehearse --layout j313 --size 20G           # create an Air-like image, install, hand off
swift run sfinstallctl image-rehearse --kill-after S47 --then rollback   # kill after a step's command, then roll back
swift run sfinstallctl image-rehearse --remove                           # install, then remove: the table must match
swift run sfinstallctl image-journal .build-images/…/journal/<job>.jsonl  # verify a journal's hash chain and print it
swift run sfinstallctl image-clean                                       # detach and delete everything under .build-images
```

**The chokepoint.** Every mutating command (`diskutil addPartition | eraseVolume | partitionDisk |
mount | apfs resizeContainer | addVolume | deleteContainer …`, `newfs_msdos`, `hdiutil detach`) and every
raw-device open goes through `ImageChokepoint`. Each call proves two things for every device in its
argv. First, `hdiutil info -plist` lists the device as an entity of one attached image whose resolved
path is under `.build-images`. Second, `diskutil info -plist` reports a `Disk Image`, `Virtual`,
non-internal device whose parent whole disk (and, for APFS, whose physical stores) are in that same
image. The `hdiutil` check runs first, so a real disk is refused before `diskutil` is asked anything.
Tests prove this against fakes and against this Mac's real `disk0`–`disk3`. Raw writes to whole
disks are refused outright. `sudo`, `dd`, `gpt`, `bputil`, `kmutil`, `nvram`, `bless` and `csrutil` are
refused before a process exists.

**Image fixtures.** `ImageFixtures` builds sparse GPT images through the same chokepoint. The J293
layout is ISC, macOS (System and Data volumes) and Recovery. The J313 layout is ISC, macOS, a Linux
stub APFS container, an ESP, a 20 GB Linux root holding a sentinel block, and Recovery. Tests clone
the templates with `clonefile` and detach and delete them afterwards.

**Steps and what is simulated.** S00–S15 read, fetch and hash. S25 shrinks macOS through the resize
supervisor. S30 and S32 create the stub container and its System, Data, Preboot and Recovery
volumes, and S35 adds its files. S40 creates the EFI-type SFBOOT and formats it FAT32. S45 creates the
root. S46 erases the booter (see below). S47 streams the xz root image to the raw partition and reads
all of it back. S42 copies stage 2 and a kernel personalised with the root's UUID and LBA. S50 and S52
write the firmware and receipt slots. S55, S60 and S68 stage the boot object, `SiliconForest Setup.app`,
`plan.json` and the markers on the stub. Two steps need root and a real Mac, so they are journaled as
`simulated` and listed as needing approval: **S20** (`diskutil apfs updatePreboot`) and **S65**
(`bless --setBoot --nextonly`), with **U10** (restore the startup disk) in removal. Removal (U20–U40)
deletes exactly the UUIDs the install's journal proves, regrows macOS, and checks the table against
the one saved before the install.

**Found on images: diskutil's `Apple_Boot` booter.** `diskutil addPartition` with a Linux type GUID
and about 1.5 GB or more carves a 128 MiB `Apple_Boot` partition out of the requested span, directly
after the new partition. EFI types don't get one. The gate stopped on this "unexpected partition". S45
now records the booter as the job's own, and the new step **S46** erases it to free space. ENGINE's
numbering leaves gaps for exactly this. Whether the internal disk behaves the same needs checking on
the Air (G5, read-only dry run first).

**Found by the sweep: a descriptor leak.** Every tool run leaked its pipes, about ten descriptors a
second, until `posix_spawn` failed with `EBADF` near the end of a long run. A helper on a real Mac would
have died mid-install the same way. Every pipe end is now closed explicitly, and an install plus
removal holds steady at 10–12 descriptors.

**Fault injection** (`FaultInjectionTests`):
- **Every journal state.** One uninterrupted install forks the image and journal right after each
  journal record, which is the state a crash there leaves. On each fork a fresh engine must resume to
  the handoff, and a second fork must roll back to the original partition table.
- **Rollback.** The same fork-per-record check, applied to a rollback's own records (J313, with Linux
  checked untouched).
- **Power loss.** The image is force-detached right after the command of each of 14 disk steps. A
  spacer image makes it come back under a different `diskN`. The engine resumes by partition UUID.
- **Failing diskutil.** A `-69850` failure on the root partition stops the step with the real error.
  Roll Back restores the table, and Try Again finishes.
- **Resize.** A `-69606` failure is classified as First Aid with nothing changed. A hang reports a
  stall and is never killed. If the helper dies mid-resize, the process keeps running and the next
  engine reattaches and waits. If the topology shows the target before the tool exits, the resize
  counts as done (#391).
- **Plan binding.** A tampered plan, a resealed plan that doesn't match the disk, a size below the
  live APFS minimum, and a disk changed after approval are all refused before anything is written.

**The helper over XPC** (`HelperXPCTests`). The tests run `HelperService` on an anonymous
`NSXPCListener` in-process and drive a whole install, status, events, diagnostics and removal over a
real `NSXPCConnection`. Those tests also check the following:
- The interface has only the verbs in DESIGN §6.3, with no command, path or device.
- A client that doesn't meet the pinned requirement is refused, in both directions.
- A client below the minimum build is refused.
- The owner's password is held in `mlock`ed memory and zeroed unused, since on an image there is no
  `bless`.
- The helper goes away when idle.

**Recovery** (`RecoveryTests`, fake `bputil`, `kmutil`, `bless`, `diskutil` and `reboot` scripts only):
- The PTY driver types the password only once echo is off. With echo on it refuses, kills the tool and
  never sends the password.
- It answers the `(y/n)` prompt, times out on a silent tool, and keeps the password out of argv, logs
  and the transcript.
- R10–R50 run in order and resume without repeating a step, and the gate fails closed.
- `sf-launcher` falls back to Terminal for exits 1, 70 and 134, and for a missing or non-executable
  app. It does not fall back for 0 or 75.
- `sf-step2.sh` runs the same steps and shares state markers with the app.
- `scripts/check-recovery-links.sh` enforces DESIGN §7.3 on the binary.

## Needs Chris's approval or a real Mac

Nothing below has been attempted. Each item is recorded instead of being worked around.

| Item | Why it can't run here | What it unblocks |
|---|---|---|
| `diskutil apfs updatePreboot` (S20) | Needs root and a live macOS volume group. Simulated on images | Stale admin lists before recovery |
| `bless --setBoot --nextonly` (S65) and restoring the startup disk (U10, rollback of S65) | Needs root and the owner's password, and changes the Mac's startup disk. Simulated on images. `bless` is on the never-run list | One-shot first start (D5, spikes S5, S12) |
| Developer ID signing (team `Z642ZK8JK4`) and notarization | Pending Chris's go. Ad hoc only | `SMAppService` registration (S1, S2, S7) and the pinned XPC trust for real |
| Registering `SFHelper` with SMAppService | Would prompt at the console. Needs a signed app | The helper as a real LaunchDaemon |
| SFRecovery in recoveryOS | Needs the Air, the power-button step and Chris's go. `bputil` and `kmutil` are never run here | Spikes S3 (AppKit launch via `.IAPhysicalMedia`, full screen), S6 (PTY `bputil`/`kmutil`) |
| The Apple_Boot booter on the internal disk | Seen on images only | Confirm S45/S46 at G5 with a read-only dry run on the Air |
| A `LiveDiskBackend` for the internal disk | Deliberately not built. Release builds only, after review | M5, the first real install |
| SFStub, the differential test against Asahi v0.9.2, firmware extraction, downloads | Not built in M3. The rehearsal release stands in | M3's remaining half (DESIGN §6.4 fallback if it slips) |

## How an install works (dry run)

Welcome → Check (live checklist; blocked variants and entry states such as "already here, but not
from this installer") → Before you begin (backup attestation) → Choose your space (disk bar: drag, type,
−/+, arrows, presets; hard stops explain the limit) → A few choices → Review ("Install SiliconForest",
no default key) → Allow the installer (helper approval; simulated) → Getting everything ready
(downloads and verification **before any disk write**, D6; cancellable) → Installing (six named
phases; the Grove brightens with real progress; no Cancel during the resize or the startup change) →
One last step (the Touch ID hold, from the profile) → simulated recoveryOS (R1–R3) → Installed, shown
only after the (simulated) first-start receipt. Remove: what will be removed → type SiliconForest →
removing (macOS made the startup disk **first**, DESIGN §8.4) → removed. A failure stops without
touching anything else: E1 when the journal proves nothing changed, otherwise E2 with **Undo Changes**
→ E3 → E4, or E5 when an undo can't finish.

Sizing (ENGINE §4): macOS keeps `used + 38 GB (1 GB under 150 GiB) + downloads + drift (min 8 GiB,
5%)`; SiliconForest's default is the larger of the profile default (48 GiB) and 25% of the disk.
`ROOT_MIN` belongs to the release manifest, which doesn't exist yet (`ReleaseInfo.placeholder`).

## What is real and what is simulated

| Part | State |
|---|---|
| UI, flow, copy, keyboard, VoiceOver labels, Reduce Motion, light/dark, night-to-dawn | Real |
| Canonical profile loading, classification (`sf.owned` / `sf.unproven` …), sizing, compatibility, plan, journal, undo, resume | Real (tested) |
| Reading this Mac (`--real`): `diskutil list/apfs list/info -plist`, `fdesetup status`, `csrutil status`, `sysctl`, `sw_vers`, `pmset -g batt`, IODeviceTree `system-firmware-version`, admin group | Real, read-only (allow-listed processes; in-process IOKit/getgrouplist reads) |
| Disk changes in the app's flow | **Simulated** (`SimulatedDiskBackend`: diskutil's refusals, realistic timing, failure injection). `--real` records them as *not executed*. The app is not yet wired to `SFEngine` |
| The engine (`SFEngine`): chokepoint, gate, hash-chained journal, plan binding, S00–S70 and U10–U40, resume, rollback, resize supervisor | **Real, on disk images only** (real `diskutil`, `newfs_msdos`, raw writes and read-back), with fault-injection tests |
| `updatePreboot` (S20), `bless` (S65, U10) | **Simulated on images** and journaled as needing approval: they need root and a real Mac |
| Writing to a real disk | **Not built.** There is no `LiveDiskBackend`; the chokepoint refuses every non-image device |
| Privileged helper (`SFHelper`, `SFHelperKit`) | **Real code, tested in-process** over an anonymous XPC listener against images. The launchd daemon is laid out in the app but never registered: that needs a Developer ID-signed app |
| recoveryOS app (`SFRecovery`, `sf-launcher`, `sf-step2.sh`) | **Real code, tested only with fake tools.** It has never run in recoveryOS (spikes S3, S5, S6) |
| Downloads, the stub builder (SFStub), firmware extraction, the boot receipt reader | Not built. The rehearsal release stands in, made of placeholder bytes with real hashes and offsets |
| The Grove | SwiftUI Canvas rather than the MTKView VISUAL §6 names: Metal needs the Xcode toolchain here, and `ImageRenderer` can't draw an MTKView, so snapshots wouldn't match the app. Same look, 30 fps |

## Device profiles

One JSON per Mac. Search order: `--profiles`/`SF_PROFILES_DIR`, `installer/profiles/` (canonical,
documented in `docs/installer/ADDING-A-MAC.md` with its schema), the app bundle's
`Resources/Profiles`, then `Fixtures/profiles` (test fixture). Unknown keys are ignored and most
sections are optional, so the format can grow.

## Signing and the privileged helper

**Developer ID signing is pending Chris's go.** Every build so far is ad hoc (`codesign -s -`). The
team is `Z642ZK8JK4`, recorded once in `SFIdentity.SigningIdentity`, and these requirement strings
derive from it:

```text
anchor apple generic and identifier "org.siliconforest.installer" and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */
and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = "Z642ZK8JK4"
```

The same applies to `org.siliconforest.installer.helper` and `org.siliconforest.recovery`. The helper
sets the app's requirement on every connection, and the app pins the helper's. Tests prove an ad hoc
peer is refused in both directions. The helper also enforces a minimum client `CFBundleVersion`.

`make-app.sh` lays out the bundle as DESIGN §6.1 and §7.1 describe, each part signed ad hoc with its
frozen identifier:
- `Contents/MacOS/SFHelper` (Info.plist linked into `__TEXT,__info_plist`)
- `Contents/Library/LaunchDaemons/org.siliconforest.installer.helper.plist` (`BundleProgram`, one Mach
  service, `AssociatedBundleIdentifiers`)
- `Contents/Helpers/SFRecovery`, after the §7.3 link check
- `Contents/Resources/RecoveryPayload/`

**Registration path** (`HelperRegistration`; never called in this build, because it would prompt at
the console):
1. After Review, the app calls `SMAppService.daemon(plistName: "org.siliconforest.installer.helper.plist").register()`.
2. If the status is `.requiresApproval`, the app calls `SMAppService.openSystemSettingsLoginItems()`
   and explains the approval.
3. Once enabled, the app connects with `HelperClient()`: a privileged Mach connection with the helper's
   requirement set.
4. When the job ends, the app calls `unregister()`. The journal stays in `/var/db/org.siliconforest.installer/journal/`.

`HelperRegistration.preflight()` refuses unless the app runs from `/Applications` and satisfies its
own Developer ID requirement. Notarization (`notarytool`, `stapler`) waits on Developer ID signing
too. Xcode is not required.

## Snapshots

`swift run SFInstaller --snapshot /tmp/sf-shots --sizes 1280x800@2,1512x982@1` renders every screen
from the real views with the Grove frozen at a fixed time. Committed in `docs/installer/screenshots/`:
2560×1600 (1280×800 pt @2x, the 13-inch M1's panel) for the key screens, 1512×982 for all 36 states, plus
`19-recovery-*` from `SFRecovery --snapshot OUT.png --size 1512x982@1 --stage password|working|failed` (AppKit, offscreen).
The content column is centred and at most 880 pt wide on every display; checked at 1280×800, 1512×982 and 2560×1600 pt. Controls that AppKit draws (the name field, the log's scroll view) are
swapped for SwiftUI equivalents that look the same in snapshots only.
