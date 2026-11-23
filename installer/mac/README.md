# SiliconForest Installer for macOS

A fullscreen installer that runs in macOS, sets up SiliconForest beside macOS on an Apple silicon
Mac, hands over to recoveryOS for the one step only recoveryOS can do, and can remove an install
again. The first supported Mac is the 13-inch MacBook Pro with M1 (J293, t8103).

**State (22 November 2026): dry run and read-only analysis only.** Nothing in this package writes
to a real disk. See [What is real](#what-is-real-and-what-is-simulated).

Screenshots: [`docs/installer/screenshots/`](../../docs/installer/screenshots/).

## Layout

Module names follow [`docs/installer/DESIGN.md`](../../docs/installer/DESIGN.md) §4; screens and copy follow
[`UX-FLOW.md`](../../docs/installer/UX-FLOW.md); the look follows [`VISUAL-DESIGN.md`](../../docs/installer/VISUAL-DESIGN.md)
("night to dawn"); sizing, classification and step states follow [`ENGINE.md`](../../docs/installer/ENGINE.md).

| Target | What it is |
|---|---|
| `SFInstallKit` | Engine: profile loading (canonical `installer/profiles/*.json`), disk model and partition classification, ENGINE §4 sizing, compatibility, planner (S10…S68 install, U10…U40 removal), checkpointed runner with JSON Lines journal, undo, disk backends, the helper's verb protocol. No UI. |
| `SFCopy` | Every user-facing string (UX-FLOW copy), Foundation-only so the CLI uses it too. |
| `SFDesign` | Tokens (Canopy/Clearing, VISUAL §3), Inter/Source Code Pro type, motion, **The Grove** (night → dawn background tied to progress), the disk bar, vias, rows, buttons, panels. |
| `SFFlow` | The screen state machine: one observable `Session`; screens are pure functions of it. |
| `SFInstaller` | The app: AppKit shell (native full screen), every screen, `--snapshot` renderer. |
| `SFHelper` | Placeholder for the privileged helper (DESIGN §6). Exits; no disk access. |
| `SFRecovery` | Placeholder for the recoveryOS app (DESIGN §7), AppKit only. Exits; changes nothing. |
| `sfinstallctl` | The engine from the command line. |
| `SFInstallKitTests` / `sfinstallkit-selftest` | 26 Swift Testing tests, as a `swift test` bundle and as an executable for Command Line Tools-only Macs. |

```
Sources/SFInstallKit/Model      DeviceProfile + CanonicalProfile (schema decoder), DiskModel (+ classification), SystemFacts, Bytes
Sources/SFInstallKit/Engine     Compatibility, Sizing, Plan, DiskOperation, Journal, InstallRunner
Sources/SFInstallKit/Backends   DiskBackend, SimulatedDiskBackend, RealDiskBackend (read-only)
Sources/SFInstallKit/Helper     SFHelperProtocol (verbs, DESIGN §6.3)
Fixtures/disks/*.json           fake Macs: j293-512, j293-512-installed, j293-512-devinstall (hand-made, sf.unproven), j293-256-full, j313-256 (the Air)
```

Device profiles are the canonical `installer/profiles/*.json` (J293 and J313 today); there is no
fixture profile. J313 loaded without engine changes, which is the point of the profile layer.

## Build, run, test

Runs on macOS 13.5 or later (D10); builds with Swift 6 (Command Line Tools are enough).
`scripts/fetch-fonts.sh` fetches Inter and Source Code Pro (OFL, pinned by SHA-256) into `build/fonts`.

```sh
cd installer/mac
scripts/test.sh                      # the test suite
swift run SFInstaller --windowed     # the app in a window (dry run)
swift run SFInstaller                # native full screen in its own Space; Esc leaves full screen, ⌘Q asks
scripts/make-app.sh                  # build/SiliconForest Installer.app (release, ad hoc signed)
```

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
| Disk changes | **Simulated** (`SimulatedDiskBackend`: diskutil's refusals, realistic timing, failure injection). `--real` records them as *not executed* |
| Executing disk changes | **Not built.** Compile flag off, runtime gate, refusing executor; the real path is `SFHelper` (placeholder) |
| Helper approval, downloads, stub builder, firmware extraction, boot receipt, recoveryOS app | Simulated in the dry run / placeholders (`SFHelper`, `SFRecovery`) |
| The Grove | SwiftUI Canvas rather than the MTKView VISUAL §6 names: Metal needs the Xcode toolchain here, and `ImageRenderer` can't draw an MTKView, so snapshots wouldn't match the app. Same look, 30 fps |

## Device profiles

One JSON per Mac. Search order: `--profiles`/`SF_PROFILES_DIR`, `installer/profiles/` (canonical,
documented in `docs/installer/ADDING-A-MAC.md` with its schema), the app bundle's
`Resources/Profiles`, then `Fixtures/profiles` (test fixture). Unknown keys are ignored and most
sections are optional, so the format can grow.

## Signing, notarization and the privileged helper (needs the Developer ID Mac)

This Mac has no signing identity; `make-app.sh` signs ad hoc. To ship:

1. **Developer ID Application certificate** in the keychain of the signing Mac, and a
   **notarytool profile** (`xcrun notarytool store-credentials sf-notary --apple-id … --team-id …`
   with an app-specific password, or an App Store Connect API key).
2. `SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" scripts/make-app.sh` signs with the
   hardened runtime and a secure timestamp.
3. Notarize and staple:
   `ditto -c -k --keepParent "build/SiliconForest Installer.app" build/sfi.zip && xcrun notarytool submit build/sfi.zip --keychain-profile sf-notary --wait && xcrun stapler staple "build/SiliconForest Installer.app"`.
   Distribute as a notarized `.dmg` or `.zip`.
4. **Privileged helper** (for the real disk writes: `diskutil` resize/add/erase, the raw image write
   to `/dev/rdiskNsM`): a launchd daemon registered with `SMAppService.daemon(plistName:)`, shipped
   in `Contents/Library/LaunchDaemons/` with its binary in `Contents/MacOS/` or `Contents/Library/`.
   `SMAppService` only registers daemons from a **properly signed app** (Developer ID, same team as
   the helper; the user approves it in System Settings → General → Login Items). The helper should
   check the caller's code signature (team ID + bundle ID) on every XPC connection, accept only the
   `DiskOperation` vocabulary (never shell strings), and refuse anything that touches the macOS
   container except `resizeContainer`. It becomes the `PrivilegedExecutor`; the compile flag and the
   runtime gate stay until the write path has been reviewed and tested on a spare Mac.
5. Xcode is not required for any of this; `codesign`, `notarytool` and `stapler` come with Xcode or
   with the full Command Line Tools on the signing Mac.

## Snapshots

`swift run SFInstaller --snapshot /tmp/sf-shots --sizes 1280x800@2,1512x982@1` renders every screen
from the real views with the Grove frozen at a fixed time. Committed in `docs/installer/screenshots/`:
2560×1600 (1280×800 pt @2x, the 13-inch M1's panel) for the key screens, 1512×982 for all 34 states. Controls that AppKit draws (the name field, the log's scroll view) are
swapped for SwiftUI equivalents that look the same in snapshots only.
