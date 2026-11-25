<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Chris Kearney and the SiliconForest contributors -->

# Supervised stub-only run on the Air (J313): checklist

Written 24 November 2026, made runnable 25 November 2026 for the first real stub. **Nothing here has been run on the Air.** It needs Chris's
explicit go for each stage, and **a person at the Air**. It follows [`ENGINE.md`](ENGINE.md) sections 6, 7 and 11 and [`FIRST-INSTALL-J313.md`](FIRST-INSTALL-J313.md)
(G5 and G6), and builds the stub that [`PAYLOAD.md`](PAYLOAD.md) section 9 describes (SFStub, the SiliconForest payload).

**What it proves:** the stub SFStub builds is accepted by the Air: the startup picker lists it, recoveryOS pairs with it,
SiliconForest Setup runs there, and stage 1 (m1n1 `121fcbf`) starts from the boot object it carries. **What it does not:**
kernel, root, firmware slot or SFBOOT. Those are G6.

## 0. What is ready, and the one thing that is not

| Needed | State (25 Nov 2026) |
|---|---|
| The engine builds the stub with SFStub (S10 members, S30 `addPartition`, S32 volumes as upstream `prepare_volume`, S35 files, S55 boot object, S60 `SFInstall`), journaled, resumable after a kill or power loss at any SFStub action, through the live backend | **Done.** `InstallEngine.stubSource`; image tests on the M5 kill or cut power inside S32 and S35 and after S55/S60 and resume (ENGINE S10–S60). `LiveMutation` allows SFStub's `apfs changeVolumeRole <vol> D`, `rename`, `apfs addVolume … -role B\|R\|D` and `-role S -groupWith <Data>` only on the container this job created; mounts are `mount nobrowse` (PAYLOAD 9.1, the one listed difference) |
| A stub-only plan: S00–S35, S55–S70, with no S17, S40–S52 (no SFBOOT, no root) | **Done.** `InstallRequest.stubOnly`: macOS gives up exactly the profile's stub size (2,499,805,184 B); stage 1's variables name a PARTUUID that is on no disk (`EnginePlan.absentBootPartUUID`, from the install ID), so stage 1 stops at "can't find stage 2"; removal deletes only the stub |
| The run as commands | **Done.** `sfstubrun` (installer/mac, a lab tool, never in the app): `plan`, `run` (resume with `--job`), `rollback`, `remove`, `status` |
| The release's `sf-stage1.bin` (Omacom m1n1 `121fcbf` plus our stage 1 patch) and its SHA-256 | **Done.** `installer/payload/boot/build_stage1.sh` rebuilds the installed machine's stage 1 byte-identical: 4,325,376 B, `44c1ef0bda96224f5fe8c6228cc12ec1966b7781f38844cea960b21b47654318`; `make_release.py`/`verify_release.py` check it (PAYLOAD 2) |
| Dress rehearsal on the M5: `sfstubrun` on a disk image with that stage 1 and Apple's 13.5 image read by range, through the live backend | **Done** (section 7) |
| A signed `SFRecovery` for the app tree (`--recovery-binary`) | From `scripts/make-app.sh` with the Developer ID; without it the app carries a placeholder and stage B cannot run |
| **The real-disk gate**: a build with the compile key `SF_REAL_DISK_WRITES`, root, the runtime authorization file for this plan's digest and the Air's disk UUID (ENGINE 12.1), and Chris's approval words | **Not open, by design.** Only Chris builds with the key and writes the file. Without them `sfstubrun run --target disk:…` refuses before any change |
| The stub passes the differential test with the SiliconForest payload on the M5 | Yes (PAYLOAD 9.1) |

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

On the i9: `installer/payload/boot/build_stage1.sh OUT` (prints `44c1ef0b…  (the installed stage 1)`), copy `OUT/sf-stage1.bin` to the Air
(`~/sf-run/rel/`). On the Air, in macOS, with the gated build of `sfstubrun` (`swift build -c release --product sfstubrun -Xswiftc -DSF_REAL_DISK_WRITES`,
built by Chris; never committed, never shipped) and `DISK=` the internal disk's `DiskUUID` from `diskutil info -plist disk0`. Common options:
`R="--release-dir ~/sf-run/rel --stage1-sha256 44c1ef0bda96224f5fe8c6228cc12ec1966b7781f38844cea960b21b47654318"`,
`J="--journal /var/db/org.siliconforest.installer/journal --work /var/db/org.siliconforest.installer/work"`,
`A="--icon <SiliconForest .icns> --admin-users <AdminUserRecoveryInfo.plist> --recovery-binary <signed SFRecovery>"`, where the admin-users
file is a copy of the one in macOS's own Preboot volume group, `<Preboot>/<macOS group UUID>/var/db/AdminUserRecoveryInfo.plist` (upstream
`copy_admin_users`); the run copies it into the stub's Preboot and marks it `schg`.

| # | Step (ENGINE code) | Command | Check |
|---|---|---|---|
| A0 | Plan (read-only) | `sfstubrun plan --target disk:$DISK $R --out ~/sf-run/plan.json` | Prints the plan digest, macOS shrink by 2,499,805,184 B, one new `stub`, stage 1's hash, the absent PARTUUID, steps S00…S70 without S17/S40–S52, and the authorization JSON. `diskutil list -plist` unchanged |
| A0b | Chris checks the plan and writes the authorization (root-owned, 0600, `RealDiskGate.authorizationPath`, at most 2 h) and says the stage A words | by hand | `sudo ls -l` shows root, `-rw-------` |
| A1 | Dry check of the gate: run without the file, or with another digest | `sudo sfstubrun run --target disk:$DISK $R $J $A --plan ~/sf-run/plan.json` | Refused (`the real-disk gate is closed`), journal shows no changes |
| A2–A5 | S00–S60: preflight, the 13.5 members by range (CRC-checked before any write), S25 shrink, S30 container, S32 volumes, S35 files, S55 boot object, S60 `SFInstall` | the same command with the file in place | Prints each step and SFStub action. On a stop: fix the cause, then the same command with `--job <id>` resumes; `sfstubrun rollback … --job <id>` undoes everything |
| A2 check | S25 | | Container smaller by 2,499,805,184 B, macOS volume mounts, nothing else moved |
| A3 check | S30–S32 | | `diskutil apfs list`: one new container of exactly 2,499,805,184 B; volumes `SiliconForest` (System), `SiliconForest - Data` (Data), `Preboot`, `Recovery`, one volume group |
| A4 check | S35 | | The tree matches the M5 differential run's SiliconForest delta (PAYLOAD 9.1): `SiliconForest Setup.app`, `SFInstall/plan.json`, no `Finish Installation.app`; Recovery has `<group>/usr/standalone/firmware/arm64eBaseSystem.dmg` (compressed) |
| A5 check | S55, S60, S68 | | `SiliconForest Setup.app/Contents/Resources/boot.bin` = stage 1 (`44c1ef0b…`, 4,325,376 B) + `chosen.asahi,efi-system-partition=<absent PARTUUID>\nchainload=<absent PARTUUID>;sf/boot.bin\n` + four NULs; `SFInstall/plan.json` has that `boot` and `root: none` |
| A6 | S65: `bless` the stub | The engine journals it as **simulated, needs Chris's approval** (it never runs bless). Chris runs the printed `bless` command himself (the macOS owner's password) | The startup picker (hold the power button on a restart) lists **SiliconForest**. The previous default is recorded |
| A7 | Choose SiliconForest in the picker | | recoveryOS starts, then **SiliconForest Setup** (or its Terminal fallback). It stops at its gate with a clear message if this is not the paired recovery |

`sfstubrun status --journal … --job <id>` prints the job's state and every simulated command waiting for Chris.

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

**What to check at B4, "reaching our loader":** the picker still shows SiliconForest, and choosing it starts stage 1 (m1n1 `121fcbf`, version tag
`121fcbf…-siliconforest-stage1-v1`, our boot logo): its version line on the console (M5, section 5) or the display, and a `chainload` attempt for
the absent PARTUUID in `boot.bin` (the one `sfstubrun plan` printed). **There is no SFBOOT partition in a stub-only run, so the expected end is
stage 1 reporting that it cannot find stage 2.** Our stage 1 is the installed variant (`SF_INSTALLED`): instead of falling back to the USB proxy
(upstream v1.5.2) or restarting, it stops with "nothing could be started" on the screen (`sf_stop`). The same binary with a PARTUUID that does
not exist did exactly that on the bench (SF-R-storage step 6, the kit's `sf-stage1-test.bin`, which is byte-for-byte this run's boot object
format). A pass: stage 1 starts, names the right PARTUUID, and stops with that message; a power-button restart gets out. A silent black screen
with no console is a **fail to investigate**, not a pass. After it, the Air restarts into the previous default (power button, then pick it) and
boots macOS normally.

## 4. Rollback

**With the tool:** `sudo sfstubrun remove --target disk:$DISK $J --job <the run's job id>` prints the removal plan (delete the stub, grow macOS
back) and its authorization JSON; it is a new plan, so Chris writes a new authorization for its digest and the same command runs it (U10–U40),
ending with the original partition table (the M5 dress rehearsal checks exactly that). Before that, restore the default boot volume (step 1 below).
A job stopped part-way is undone with `sfstubrun rollback … --job <id>` instead.

**By hand**, in macOS, in this order, if the tool cannot:

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

- The stub this builds equals Asahi v0.9.2's, except the declared SiliconForest payload, on a disk image: PAYLOAD 9, `installer/mac/scripts/stub-differential.sh`
  (`SF_PAYLOAD=sf`), delta in `Tests/StubDifferential/fixtures/sf-payload-delta.json`.
- The stub-only run on images (`StubOnlyImageTests`, `StubOnlyRunImageTests`, M5 long lane): power loss after S30, S32 and S55, kills inside S32 and S35,
  resume to hand-off; only the stub added; `boot.bin` chainloads the absent PARTUUID; removal and rollback restore the original table; the same through the
  live backend with `StubOnlyRun`'s plan and authority.
- **Dress rehearsal, 25 Nov 2026 ~2:30 AM PT (M5, macOS 26.5, not root):** `sfstubrun plan` then `run` on a j293-layout disk image (ISC, macOS,
  Recovery: the Air after Omarchy), J313 profile, the real `sf-stage1.bin` (`44c1ef0b…`, from `build_stage1.sh` on the i9) and Apple's 13.5 j313
  image read by range from the CDN, through the live backend. Plan `667993ae…`: macOS 62,826,479,616 → 60,326,674,432 B, one stub of 2,499,805,184 B,
  steps S00 S05 S08 S10 S15 S20 S25 S30 S32 S35 S55 S60 S65 S68 S70. End **handed-off**, 53 journal records, 112 SFStub actions in S35 (BaseSystem
  lzfse-compressed onto Recovery). Read back: `boot.bin` 4,325,510 B = stage 1 (`44c1ef0b…`) + `chosen.asahi,efi-system-partition=<absent>` +
  `chainload=<absent>;sf/boot.bin` + four NULs; `SFInstall/plan.json` `boot` = the absent PARTUUID, `root` = `none`. Simulated for Chris: S20
  `updatePreboot`, S65 `bless`; without root, `schg` and `bootable` are simulated too. `sfstubrun remove`: removal plan `7f78b64a…` **committed**,
  the image back to ISC, macOS at 62,826,479,616 B, Recovery. Image detached and deleted.
- Boot personalisation, recovery pairing and `bless` are not comparable on images; this run is where they are first tried.

## 8. Decisions (Chris, 25 Nov 2026 12:21 AM PT)

1. The first stub-only run **ends at stage 1 reporting it can't find stage 2**. No SFBOOT in that run; a minimal SFBOOT comes in a later run.
2. **Stage B (R20/R30, the LocalPolicy change for the stub's own volume group) is part of the first real run.**
3. S55 writes the boot object in `m1n1.build`'s format, the same bytes SFStub stages: stage 1, each variable and a newline, four NULs (done: `InstallEngine.bootObject`, test `theEngineWritesTheSameBootObjectAsTheStub`).
4. Live mounts are `mount nobrowse` (plain `mount` stays refused), recorded as the one listed difference (PAYLOAD 9.1).
