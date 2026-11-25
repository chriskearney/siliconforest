<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Chris Kearney and the SiliconForest contributors -->

# Supervised stub-only run on the Air (J313): checklist

Written 24 November 2026 for the first real stub. **Nothing here has been run.** It needs Chris's explicit go for each stage,
and **a person at the Air**. It follows [`ENGINE.md`](ENGINE.md) sections 6, 7 and 11 and [`FIRST-INSTALL-J313.md`](FIRST-INSTALL-J313.md)
(G5 and G6), and builds the stub that [`PAYLOAD.md`](PAYLOAD.md) section 9 describes (SFStub, the SiliconForest payload).

**What it proves:** the stub SFStub builds is accepted by the Air: the startup picker lists it, recoveryOS pairs with it,
SiliconForest Setup runs there, and stage 1 (m1n1 `121fcbf`) starts from the boot object it carries. **What it does not:**
kernel, root, firmware slot or SFBOOT. Those are G6.

## 0. Not runnable yet (what must be true first)

| Needed | Today |
|---|---|
| The engine builds the stub with SFStub (S30 `addPartition`, S32 volumes, S35 files, S55, S60), through the live backend | **Not wired.** SFStub runs only through `sfstubctl`, which refuses anything but disk images. `LiveMutation` now parses SFStub's `apfs changeVolumeRole <vol> D`, `rename <vol> <name>` and `apfs addVolume … -role B|R|D` / `-role S -groupWith <Data>` shapes, allowed only on the container this job created; S55 is aligned (section 8) |
| A build with the compile key (`SF_REAL_DISK_WRITES`) and a runtime authorization file for the Air's disk, bound to the plan digest (ENGINE 12.1), both made by Chris | Both off. Never in a shipped, CI or test build |
| A stub-only plan: S00–S35, S55–S70, then R10–R50, with no S40–S52 (no SFBOOT, no root) | Not defined in the engine |
| A signed `SFRecovery` and the release's `sf-stage1.bin` (Omacom m1n1 `121fcbf` plus our patches), its SHA-256 from the signed `install.json` (`siliconforest-install/3`) | The stage 1 binary has not been built into a release; PAYLOAD 12 lists it |
| The stub passes the differential test with the SiliconForest payload on the M5 | Yes, section 7 of this file and PAYLOAD 9 |

## 1. Preconditions on the Air

1. **Omarchy removed**, so the installer sees no foreign OS (`os.foreign` refuses Asahi, Omarchy and any Linux, D12). The Linux stub, ESP and
   root are gone by Chris's own hand, not by this installer. Their old default boot entry no longer exists.
2. **macOS at full size**, grown back over the space Omarchy used (`diskutil apfs resizeContainer <macOS container> 0`, from macOS). No free space left over.
3. `diskutil list internal` shows **exactly three partitions** of the internal disk: `Apple_APFS_ISC` (about 524 MB), the macOS `Apple_APFS`
   container (all the rest but about 5 GB), and `Apple_APFS_Recovery` (about 5 GB). No `EFI`, no `Linux`, no `Apple_Boot`, no `(free space)` line.
   Save the full `diskutil list -plist` and `diskutil apfs list -plist` **off the repository** (they hold UUIDs).
4. macOS is **13.5 or newer** and the macOS volume group is not FileVault-locked in a way that blocks the resize (ENGINE 4 preflight). Time Machine or other
   current backup **confirmed by Chris**. On power, battery above 50%. Wi-Fi on (about 710 MB is read from Apple's CDN by range).
5. At least **2.5 GB (2,499,805,184 B plus alignment) free in the macOS container**, and macOS using no more than about 110 GB of its 245 GB so the 38 GB margin holds.
6. A USB-C cable and the M5 at hand to read stage 1's console (optional, section 5). Do **not** use DFU, `bputil -z`, or a firmware flash. Nothing on the Pro.
7. Chris's approval words recorded in the run log: "Chris approves the stub-only run on the Air, stage A" (and again for stage B).

## 2. Stage A: the stub, up to the picker (everything is deletable)

| # | Step (ENGINE code) | Check |
|---|---|---|
| A1 | Dry run (**Show What Would Happen**). Quit | Disk unchanged: `diskutil list -plist` equals the saved one |
| A2 | S25: macOS container shrinks by 2,499,805,184 B plus alignment | Container smaller by that, macOS volume mounts, nothing else moved |
| A3 | S30–S32: one new APFS container of exactly 2,499,805,184 B, named `SiliconForest`, with System, Data, Preboot, Recovery | `diskutil apfs list`: roles System, Data (`SiliconForest - Data`), Preboot, Recovery, one volume group |
| A4 | S35: SFStub writes the stub content from the 13.5 image | The tree matches the M5 differential run's SiliconForest delta (section 7): `SiliconForest Setup.app`, `SFInstall/plan.json`, no `Finish Installation.app`; Recovery has `arm64eBaseSystem.dmg` |
| A5 | S55, S60, S68: boot object, Setup app staged, `SystemVersion.plist` hidden, `.IAPhysicalMedia` present | `boot.bin` ends with `chosen.asahi,efi-system-partition=<uuid>`, `chainload=<uuid>;sf/boot.bin`, four NULs; its stage 1 part has the release's SHA-256 |
| A6 | S65: `bless` the stub (needs the macOS owner's password) | The startup picker (hold the power button on a restart) lists **SiliconForest**. The previous default is recorded |
| A7 | Choose SiliconForest in the picker | recoveryOS starts, then **SiliconForest Setup** (or its Terminal fallback). It stops at its gate with a clear message if this is not the paired recovery |

Stop at any unexpected output. **Rollback of stage A is complete** (section 4): no LocalPolicy has been changed yet.

## 3. Stage B: the boot object (one-way for this volume group)

Only after Chris says "approves stage B". It runs R10–R50 in SiliconForest Setup. **R20 `bputil -nc` and R30 `kmutil configure-boot` change the stub's
volume group's LocalPolicy and cannot be undone**; removing the stub retires them. The macOS volume group is not touched. The owner's password
is typed at the person's keyboard only.

| # | Step | Check |
|---|---|---|
| B1 | R10 gate: `/System/Installation/CDIS`, root, volume and group UUIDs match `plan.json`, `bputil -d` says `Paired` and `one true recoveryOS` | Passes. Try the wrong ways first (power-button release early, the macOS recovery instead): a clear refusal, nothing changed |
| B2 | R20 `bputil -nc`, R30 `kmutil configure-boot -c boot.bin --raw --entry-point 2048 --lowest-virtual-address 0` | Read back: policy Permissive, custom boot object present |
| B3 | R40 markers cleared; R50 previous default restored, SiliconForest chosen **for the next boot only** | Default boot volume is still the previous one |
| B4 | Restart | Stage 1 runs (below) |

**What to check at B4, "reaching our loader":** the picker still shows SiliconForest, and choosing it starts stage 1 (m1n1 `121fcbf`): its version line
on the console (M5, section 5) or the display, and a `chainload` attempt for the SFBOOT PARTUUID in `boot.bin`. **There is no SFBOOT partition in a
stub-only run, so the expected end is stage 1 reporting that it cannot find stage 2** (upstream v1.5.2 then falls back to the USB proxy; whether
`121fcbf` does the same is **unverified**, and observing it is the point). Any of these is a pass for the stub: stage 1 starts, names the right
PARTUUID, and returns control without a hang that needs more than a power-button restart. A silent black screen with no console is a **fail to
investigate**, not a pass. After it, the Air restarts into the previous default (power button, then pick it) and boots macOS normally.

## 4. Rollback

Do these in macOS, in this order. They are the engine's own removal (U10–U40) done by hand if the app cannot:

1. **Restore the previous default boot volume** (System Settings, Startup Disk, or the startup picker: choose it with Option held to make it the default). Check it.
2. **Delete the stub container:** `diskutil apfs list`, find the container whose Physical Store is the 2,499,805,184 B partition and whose volumes are
   `SiliconForest`, `SiliconForest - Data`, `Preboot`, `Recovery`, then `diskutil apfs deleteContainer <container disk>`. Name it by its identifier from `diskutil list`; check twice that it is
   not the macOS container.
3. **Erase the freed partition and grow macOS:** `diskutil eraseVolume free free <stub disk>`, then `diskutil apfs resizeContainer <macOS container> 0`.
4. `diskutil list -plist` equals the saved one in layout and sizes (UUIDs of the macOS partitions unchanged); `diskutil verifyVolume /` is clean; macOS boots from the picker and the Startup Disk.
5. If stage B ran: the stub's LocalPolicy stays on the Mac, unused. If a clean policy is wanted, that is a separate decision (recovery, Startup Security Utility), not part of this rollback. **Do not use DFU or `bputil -z`.**
6. Save the run log without UUIDs or serial numbers.

## 5. Reading stage 1 (optional)

USB-C from the Air's port to the M5 with the proxy client; stage 1's console shows the m1n1 version and the `chainload` line. Whether `121fcbf` stage 1 opens the proxy
window with a display present is not known (G2-RUNBOOK 1). If the console cannot be read, the display and the picker are the only evidence, and the run says so.

## 6. Stop conditions

Any pre-existing partition moves, vanishes or changes size other than the planned shrink; a command not in the plan; a refused gate; `bless` Code 112/103/302;
resize `-69606` or `-69850`; recovery pairing error 17; no picker entry after A6. Stop, do not retry blind, roll back, export diagnostics.

## 7. Evidence from the M5 (not the Air)

The stub this builds equals Asahi v0.9.2's, except the declared SiliconForest payload, on a disk image: PAYLOAD 9, `installer/mac/scripts/stub-differential.sh`
(`SF_PAYLOAD=sf`), delta in `Tests/StubDifferential/fixtures/sf-payload-delta.json`. Boot personalisation and recovery pairing are not comparable on images; this run is where they are first tried.

## 8. Decisions (Chris, 25 Nov 2026 12:21 AM PT)

1. The first stub-only run **ends at stage 1 reporting it can't find stage 2**. No SFBOOT in that run; a minimal SFBOOT comes in a later run.
2. **Stage B (R20/R30, the LocalPolicy change for the stub's own volume group) is part of the first real run.**
3. S55 writes `.sf/boot.bin` in `m1n1.build`'s format, the same bytes SFStub stages: stage 1, each variable and a newline, four NULs (done: `InstallEngine.bootObject`, test `theEngineWritesTheSameBootObjectAsTheStub`).
