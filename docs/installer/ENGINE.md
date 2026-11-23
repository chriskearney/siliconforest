<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Chris Kearney and the SiliconForest contributors -->

# SiliconForest Installer: the partition and install engine

Companion to [`DESIGN.md`](DESIGN.md). **Design only. Nothing here has run on a Mac.**

The engine has one job: move a Mac from "macOS only" to "macOS and SiliconForest" and back, so that
**at every instant the Mac can still start macOS and the installer knows what state it is in.**

## 1. Pipeline

```
 probe ──► classify ──► preflight ──► size ──► plan ──► approve
                                                          │
       ┌──────────────────────────────────────────────────┘
       ▼
 re-derive plan as root ──► verify artifacts ──► GATE ──► step ──► verify ──► checkpoint
                                                   ▲                              │
                                                   └──────────────────────────────┘
```

## 2. Preflight

All of it is read-only and runs before any password or approval.

| Check | Source | Result if it fails |
|---|---|---|
| Mac is in a supported profile | `sysctl hw.targettype`, `hw.model`, IODeviceTree `compatible` | **Block**, naming the Mac |
| Not under Rosetta | `sysctl.proc_translated` | Relaunch natively |
| macOS within the profile's range | `sw_vers`, the profile | **Block** with the reason |
| System firmware at least the stub's minimum | IODeviceTree `system-firmware-version`, profile `min_iboot` | **Block**: update macOS |
| SFR and SystemRecovery versions | `/System/Volumes/iSCPreboot/SFR/…` | **Warn** on mismatch (correlated with `bless` Code 112, by report only) |
| Booted from internal macOS, not recovery | `diskutil info /`, `bputil -d` | **Block** |
| Logged in at the console, administrator | `SCDynamicStoreCopyConsoleUser`, OpenDirectory | **Block** |
| Admin list in Preboot is current | `AdminUserRecoveryInfo.plist` | Plan one `updatePreboot` step |
| Volume owner exists | `diskutil apfs listUsers` | **Block**: no owner can approve recovery |
| FileVault not converting | `fdesetup status`, `diskutil apfs list` | **Block** until conversion finishes |
| All volumes in macOS's container unlocked | `diskutil apfs list -plist` | **Block**: resize requires it |
| AC power | IOKit power sources | **Block** the Install button until connected |
| GPT intact | `diskutil list -plist`, `gpt` read-only | **Block** |
| Standard Apple layout present | `Apple_APFS_ISC`, `Apple_APFS_Recovery` | **Block** |
| Pending macOS update | `softwareupdate` state, overhead heuristic | **Warn**: finish or dismiss it first |
| Time Machine local snapshots | `tmutil listlocalsnapshots /` | **Inform**, quantify on the disk bar |
| Backup recency | `tmutil latestbackup` (if readable) | **Inform** only; the user attests |
| APFS health | Last `diskutil verifyVolume` is **offered**, not forced | Failure: guided repair from recoveryOS |
| Another install of ours | Install marker, journal, layout | Route to Resume, Repair or Remove |
| Other operating systems | Volume groups, Linux and EFI partitions | Listed and **left alone** |
| Current default boot volume | `nvram`, `bless --getBoot` | **Record** it. The install restores it, whichever OS it is |
| Network reachable | HEAD on the channel file and Apple's CDN | **Block** before any change |

## 3. Layout classification

Every partition gets exactly one class. The classifier is pure, and golden-tested against real recordings.

| Class | Meaning | Allowed actions |
|---|---|---|
| `apple.isc`, `apple.recovery` | Apple's system containers | **None, ever** |
| `macos.primary` | The container we run from | Resize only |
| `macos.other` | Another macOS | None |
| `os.foreign` | Asahi, Omarchy, Linux, anything else | None |
| `sf.owned` | Ours, proved by marker **and** journal **and** expected layout | Update, Repair, Remove |
| `sf.partial` | Ours, from an unfinished job in our journal | Resume, Roll back |
| `sf.unproven` | Looks like SiliconForest, but we can't prove it. **The development M1's hand-made install is this** | **None**: explain and stop |
| `free` | Unallocated | Use for new partitions |
| `unknown` | Anything else | None |

## 4. Sizing

```text
ALIGN        = 1 MiB
STUB         = 2,499,805,184 B          (profile)
BOOT         =   524,288,000 B          (profile)
ROOT_MIN     = release.root.min_bytes
ROOT_DEFAULT = max(ROOT_MIN, profile default)

used         = CapacityCeiling - CapacityFree
reserve      = 38 GB                    (1 GB on disks under 150 GiB, with a warning)
downloads    = bytes still to fetch into macOS's container
drift        = min(8 GiB, 5% of the resizable span)

macos_floor  = align_up(used + reserve + downloads + drift, ALIGN)
macos_min    = max(macos_floor, limits.MinimumSizePreferred)
sf_max       = container_size + adjacent_free - macos_min
sf_min       = STUB + BOOT + ROOT_MIN
```

If `sf_max < sf_min`, the disk screen explains what would have to be freed and by how much. It separates the causes:

```text
overhead = limits.MinimumSizePreferred - align_up(used + reserve)
```

An `overhead` above 16 GB is attributed to Time Machine snapshots if they exist, otherwise to a pending macOS update or
APFS metadata. **We never delete snapshots without the user asking**. When they ask, we use `tmutil deletelocalsnapshots <date>` per
snapshot and re-read the limits.

The default size is the larger of the profile's default and 25% of the disk, capped by `sf_max`. It is never the minimum.

If the release declares `root.sizing = "fixed"`, the root partition equals the image size, and the handle is locked with an explanation.

## 5. The plan

The plan is an immutable value. Its digest is what the user approves.

```json
{
  "format": "siliconforest-plan/1",
  "operation": "install",
  "profile": {"id": "J293", "sha256": "…"},
  "release": {"version": "…", "sums_sha256": "…", "install_json_sha256": "…"},
  "layout_digest": "sha256 of every partition: type, uuid, first LBA, length, plus the live limits",
  "steps": [
    {"id": "resize", "container": "<part-uuid>", "from": 494384795648, "to": 390000000000},
    {"id": "add-stub", "after": "<part-uuid>", "bytes": 2499805184},
    {"id": "add-boot", "after": "@stub", "bytes": 524288000, "label": "SFBOOT"},
    {"id": "add-root", "after": "@boot", "bytes": 101000000000}
  ],
  "human_steps": ["enterOneTrueRecovery", "authenticateMachineOwner"],
  "digest": "sha256 of the canonical form of everything above"
}
```

At `begin`, the helper reads the disk itself, rebuilds the plan with the same inputs, and refuses unless the digests match. A small drift inside the
margin (ordinary macOS writes) changes `CapacityFree` but not the partition layout, so the digest covers the **bounds** the step needs, rather than
the exact free byte count. The helper separately rechecks that `to >= macos_min`.

## 6. The gate

Ported from SF-AJ's `sf_gate.py`, every disk-changing call goes through it.

- **Allow-listed:** the planned resize, once, to the planned size; new partitions after the planned one, inside the planned span; format, raw write, volume changes and bless **only on objects this job created**; in a removal, only the planned deletes and the grow.
- **Refused:** `dd`, `gpt`, `bputil` beyond `-d`, NVRAM writes, anything not named in the plan.
- **After each change:** re-read the partition table and stop everything if any pre-existing partition moved, vanished or changed size, apart from the planned resize.
- **Every call** records intent before and evidence after.

## 7. State machine

Numbering leaves gaps for later insertions. **Recorded in the journal; the journal decides the state.**

| State | Action | Evidence that it is done | Idempotent check | Rollback |
|---|---|---|---|---|
| `S00 preflight` | Read only | Report | Rerun | Nothing to do |
| `S05 approved` | User approved | Plan digest | | Nothing to do |
| `S08 helper` | Register daemon | Status `.enabled` | Status | Unregister |
| `S10 fetched` | Download to work directory | Sizes | Resume by range | Delete work files |
| `S15 verified` | Hash everything | SHA-256 match | Rehash | Delete work files |
| — | **First disk write below this line** | | | |
| `S20 preboot` | `updatePreboot` if planned | Admin list current | Compare | Harmless; left alone |
| `S25 resized` | Shrink container | Topology shows the planned size | Size already right | Grow back |
| `S30 stub-part` | `addPartition` APFS | Partition with expected span | Find by span + marker | Delete it |
| `S32 stub-vols` | System, Data, Preboot, Recovery | Volume roles | List roles | Delete container |
| `S35 stub-files` | IPSW files, Preboot, Recovery image | Hashes, manifest | Per-file hash | Delete container |
| `S40 boot-part` | `addPartition`, `newfs_msdos` | FAT with label | Probe | Erase to free |
| `S42 boot-files` | Personalised `sf/boot.bin`, `sf/kernel.bin` | Read-back hash | Hash | Erase to free |
| `S45 root-part` | `addPartition` raw | Span | Probe | Erase to free |
| `S47 root-image` | Stream xz to `/dev/rdisk` | **Full read-back** against `image_sha256` | Hash | Erase to free |
| `S50 firmware` | Extract, write the firmware slot | Slot header + digest | Compare | Covered by root erase |
| `S52 receipt-slot` | Write header and install ID | Read back | Compare | Covered by root erase |
| `S55 boot-object` | Stage 1 + variables into the app | Hash, size limit | Hash | Covered by stub delete |
| `S60 recovery-stage` | Copy app, plan, marker | Hashes | Hash | Covered by stub delete |
| `S65 blessed` | `bless --setBoot` on stub (needs password) | **Read back** default volume | Read | Restore previous default, verify |
| `S68 handoff` | Hide `SystemVersion.plist`, enable marker | Files | Check | Restore |
| `S70 awaiting-recovery` | The Mac shuts down | | | Restore previous default, then full rollback |
| `R10 gate` | Recovery checks | Paired + 1TR | Rerun | Explain, shut down |
| `R20 policy` | `bputil -nc` | `bputil -d` shows Permissive | Read policy | **None.** See below |
| `R30 boot-object` | `kmutil configure-boot` | Custom object present | Read policy | **None.** Forward only |
| `R40 markers` | Disable marker, restore version file | Files | Check | |
| `R50 boot-select` | Previous default restored, SiliconForest next (S5, S12) | Read back | Read | |
| `S80 first-boot` | SiliconForest starts | Receipt | Read slot | Use Remove |
| `S90 installed` | Verified in macOS | `desktop-ready` | Terminal state | Use Remove |

**After recovery there is no "undo", only Remove.** A LocalPolicy cannot be rolled back. It applies only to this volume group, and removing the stub
retires it from use.

### Interruptions

| Interrupted during | On next launch |
|---|---|
| Before `S20` | Nothing changed, **proved by the journal**. Start over |
| A step with intent but no evidence | Run that step's idempotent check. The answer is **done**, **not done** or **cannot tell**. Done or not done continue automatically. "Cannot tell" offers Roll Back and Export Diagnostics; **it is never a dead end** |
| `S25` (resize) | The resize supervisor runs (section 8) |
| `S47` (root image) | Restart the image write. No partial is trusted |
| `S70` onward | "Finish in Recovery" with the same instructions |
| macOS updated between stages | The System volume UUID changes (Omacom #183). The owner is re-resolved and `AdminUserRecoveryInfo.plist` refreshed, with its own message |

## 8. The resize supervisor

Resize is where other installers fail most, so it gets its own component.

1. **Before:** record the container size, the partition size and the limits. Hold a power assertion.
2. **Run:** spawn `diskutil apfs resizeContainer <part> <bytes>` **from the helper**, in its own process group, streaming output to the log.
3. **Watch:** parse the phase and percentage for display. Sample the real topology every 15 seconds.
4. **If output stalls** for 10 minutes, say so ("macOS is still working; this step can take a long time"). **Do not kill it.** Keep watching topology.
5. **If the topology shows the target size,** treat the resize as complete even if the tool has not exited (#391). Keep waiting for a clean exit, then continue.
6. **If the app dies,** the helper continues. On relaunch, the app reattaches and shows the true state.
7. **If the helper dies mid-resize,** on restart it checks for a surviving `diskutil` process and reattaches by watching it.
8. **On tool failure,** re-read the topology and classify:

| Outcome | State | Action offered |
|---|---|---|
| Nothing changed | Clean | Show the real error and specific fix. Try Again |
| `-69606`, `49153`, "Storage system verify or repair failed" | Unchanged | Guided First Aid from recoveryOS |
| Container smaller, partition unchanged (Omacom #210) | Inconsistent | **Reconcile**: finish with Apple's tool, or grow back. Never refuse |
| Unknown | Unknown | Stop, keep the Mac on, Export Diagnostics |

There is **no Cancel during a resize**. The UI says why.

## 9. The journal

Append-only JSON lines in `/var/db/org.siliconforest.installer/journal/<job>.jsonl`, root-only, `fsync` per record. Each record chains the hash of the previous one.

```json
{"seq":41,"prev":"9f2c…","t":"2026-12-01T18:22:04Z","kind":"intent","step":"S30","args":{"after":"uuid-3","bytes":2499805184}}
{"seq":42,"prev":"71aa…","t":"2026-12-01T18:22:06Z","kind":"evidence","step":"S30","result":{"part":"uuid-7","first":…,"len":…}}
{"seq":43,"prev":"c04e…","t":"2026-12-01T18:22:06Z","kind":"checkpoint","step":"S30"}
```

- The record **before** a write states what is about to happen. The record **after** states what is proved.
- "No changes were made" is derived: the journal contains no `intent` at or past `S20`.
- A copy moves to SFBOOT once that partition exists, and to the stub for the recovery step.
- Before the first write, the helper saves the **original GPT** and the classified layout, so Uninstall can prove it restored the table.
- A job ends in `committed`, `rolled-back` or `abandoned`. An unfinished job routes the next launch to Resume.

## 10. Stub builder and the differential test

`SFStub` is a Swift port of Asahi v0.9.2's `stub.py`, `urlcache.py` and the relevant parts of `osinstall.py`, keeping their MIT notice.

Changes from upstream, all deliberate:

- Requires HTTP `206` and a matching `Content-Range`.
- A bounded block cache.
- Files downloaded and checked before the first disk write.
- No password in argv.
- Fixes the suffix-strip and "Multiple volumes" bugs.
- Uses Apple's Compression framework for deflate and LZFSE.

**Done means proved:** run the real Asahi v0.9.2 code and `SFStub` on two identical image-backed disks from the same IPSW, then compare:

1. The command sequence (against the `asahi-v0.9.2-commands.txt` fixture).
2. The file tree of all four volumes, with modes, flags, xattrs and contents.
3. The decompressed BaseSystem bytes.
4. The `bootable` flag and the volume roles.

Differences must be listed and justified one by one. Boot personalisation is not comparable on an image and is covered in real-hardware testing.

## 11. Real-hardware acceptance

From SF-AJ's checklist, extended. **Runs first on the M1 Air (J313), with Chris's go. Stop at any unexpected output. Never use DFU.**

1. Launch, compatibility, every refusal worded correctly.
2. Dry run prints the plan. Quit: disk unchanged.
3. Install with defaults. Time each phase.
4. Before recovery, verify partitions, hashes, firmware slot, receipt header.
5. Recovery: wrong ways first (release early, double-press), then right.
6. First start: mark, desktop, Wi-Fi, keyboard, trackpad, Touch Bar, restart.
7. Back in macOS (start it from the picker if another OS is the default): **receipt read**, Verified screen. `diskutil verifyVolume /` clean.
8. Picker → SiliconForest three times.
9. Update kernel and stage 2 with a second release.
10. Force-quit the app during each long phase. Reattach.
11. Kill power during the root image write. Recover.
12. Update macOS between the stages. Recover.
13. Force a failed first boot (a deliberately bad kernel). Confirm the Mac returns to its previous default and the app offers recovery.
14. Remove. The partition table matches the original. macOS has its size back. Reinstall works.

## 12. Dry run

`SFInstallKit` depends on a `DiskBackend` protocol with three implementations:

| Backend | Use | Writes |
|---|---|---|
| `FakeDiskBackend` | Loads a plist-described disk, applies commands to the model. Port of `fakemac.py` | Memory |
| `ImageDiskBackend` | Real `diskutil` and `hdiutil` on an attached sparse image | The image only |
| `LiveDiskBackend` | Real disk | The real disk, **release builds only** |

```sh
sfinstallctl plan     --fake fixtures/m1-stock --size 80G
sfinstallctl run      --fake fixtures/m1-stock --fail-at S35 --then rollback
sfinstallctl rehearse --image /tmp/sf-test.sparseimage --size 256G
```

`ImageDiskBackend` checks **on every call** that the device's `diskutil info -plist` reports a disk image, and aborts otherwise.
`LiveDiskBackend` is not linked into test or simulator builds.

In the app, **Show What Would Happen** on the Review screen is a dry run against the real, read-only topology.

## 13. Error taxonomy

Every failure maps to one of these, and each has a screen in [`UX-FLOW.md`](UX-FLOW.md).

| Class | Meaning | User's way out |
|---|---|---|
| `blocked` | Preflight said no; nothing changed | Fix it, Check Again |
| `transient` | Network, sleep, a busy volume | Try Again |
| `user-fixable` | Wrong password, not enough space | Guidance, Try Again |
| `apple-tool` | `diskutil`, `bless`, `bputil`, `kmutil` failed | Real error, known fix if there is one, Try Again or Roll Back |
| `inconsistent` | The disk differs from what the journal expects | Stop, Roll Back if safe, Export Diagnostics |
| `boot-failed` | No receipt | Try Again, Export Diagnostics, Remove |
| `internal` | A bug | Roll Back, Export Diagnostics |

Known Apple errors have specific entries: `bless` Code 112, 103 and 302; resize `-69606` and `-69850`; `bputil` "User not found"; recovery pairing error 17.
