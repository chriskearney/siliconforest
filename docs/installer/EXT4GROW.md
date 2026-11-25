<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Chris Kearney and the SiliconForest contributors -->

# SiliconForest Installer: sf-ext4grow, the Swift root grower (S48)

Companion to [`PAYLOAD.md`](PAYLOAD.md) section 6. Code: [`installer/mac/SFExt4Grow/`](../../installer/mac/SFExt4Grow/).
CI: `.github/workflows/installer-ext4grow.yml`. Started 24 November 2026 with Chris's go (voice, 3:25 PM PT): a Swift grower
with no GPL dependency instead of shipping a macOS build of `resize2fs` in the dmg. **The real-disk write switch stays off.**
The `resize2fs` path in PAYLOAD.md and `grow_check.py` is left as it was; it stays the reference.

> **Status, milestone M1.** Library + CLI + tests. Everything ran on plain files and disk images on the M5. Nothing has
> written to a real disk, touched the Air or the Pro, or booted. Not yet wired into the engine's S48 step.

## 1. What is grown (not APFS)

The target is the SiliconForest **ext4** root: the installer root image written to its raw root partition at S45 to S47,
grown **offline** (unmounted, before the first start) from about 2.17 GB to the partition's size, for example 96 GiB. It is not
an APFS volume. APFS volumes do not need growing (the macOS container resize is the resize supervisor's job, before S45).
DiskArbitration is used only to refuse a mounted or busy target, to unmount on request, and to claim the disk for the
length of the grow.

## 2. Clean room

Written from the published ext4 on-disk format description (the kernel's `Documentation/filesystems/ext4` pages: superblock,
group descriptors, flex_bg, sparse_super, the resize inode, metadata checksums, jbd2 superblock). No e2fsprogs or kernel code
was read, copied or translated. e2fsprogs (`mke2fs`, `e2fsck`, `dumpe2fs`, `debugfs`, `resize2fs`) is used only as an external
test oracle on test machines (a user-local build on the M5, `brew install` on the CI runner). It is never linked or shipped;
CI checks the binary's `otool -L`. Facts not spelled out in the description were read off real images with `debugfs` and
`dumpe2fs` and are marked in the code (the resize inode's index rule; the last-group rule in section 5).

## 3. Supported input, and refusals

Exactly the features the 0.1.0 root uses (`dumpe2fs`, 24 November): `has_journal ext_attr resize_inode dir_index filetype extent
64bit flex_bg metadata_csum_seed sparse_super large_file huge_file dir_nlink extra_isize metadata_csum`, 4 KiB blocks, 64-byte
group descriptors. Grow only. Each refusal happens before the first write and leaves the target byte-for-byte unchanged
(tested for each):

| Code | When |
|---|---|
| `unsupported-feature` | any feature outside that set (meta_bg, bigalloc, quota, large_dir, orphan_file, …), or one it needs is missing |
| `shrink` | target smaller than the filesystem |
| `journal-dirty` | `needs_recovery`, a journal holding transactions (`s_start` ≠ 0) or recording an error |
| `not-clean` | state not clean, errors recorded, orphan list not empty |
| `checksum` | any superblock, group descriptor, block or inode bitmap, resize or journal inode checksum mismatch |
| `inconsistent`, `resize-inode` | free counts disagree with the bitmaps; resize inode not exactly the layout the geometry implies |
| `beyond-limit` | more groups than the reserved GDT blocks can describe: 2,233,382,993,920 bytes for the 0.1.0 root |
| `mounted`, `busy` | the device has a mounted slice (unless `--unmount` and the unmount succeeds), cannot be claimed, or a file target is attached as an image |
| `not-disk-image` | a `/dev` node that `hdiutil info` does not list as an attached disk image: real disks are refused |
| `protected-range` | a write would touch a protected range (`--root-json` protects the CHL-40 firmware and receipt slots) |
| `interrupted` | an undo log from an unfinished grow exists |

## 4. Method

All in memory first (`GrowPlanner`), then written in order (`Grower`):

1. New groups are appended. Their descriptors go into the next GDT blocks, which were the first reserved GDT blocks, so
   **no existing block moves**; the slots' offsets in install.json stay valid.
2. Each new group's block bitmap, inode bitmap and inode table go into its flex group's metadata area: an existing flex group
   keeps its spacing, a new one is packed for the groups it holds. A taken block falls back to the first free run (not yet
   exercised by a test image, section 8).
3. New sparse_super backup groups get a superblock copy, a GDT copy and a zeroed reserved area.
4. The resize inode is rebuilt for the new geometry: the double-indirect block lists each remaining reserved GDT block P at
   index P − 1 (its place in the GDT area), and block P lists P's copy in every backup group, the new ones included.
5. The old last group's bitmap is widened; superblock counts (blocks, free blocks, inodes, reserved blocks scaled down,
   reserved GDT, `s_overhead_clusters` = 0) and every changed checksum are updated.

New groups are `INODE_UNINIT`, and `BLOCK_UNINIT` when nothing is in them (never the last group). **By default their inode
tables are zeroed and marked `ITABLE_ZEROED`**, like every group of the 0.1.0 root, because the partition's old bytes are
arbitrary and the Darwin driver is not known to zero tables lazily. About 1.2 GiB is written for 96 GiB. `--lazy-itables`
skips that and gives Linux `resize2fs`'s layout.

## 5. Write order and recovery

| Phase | Blocks | Crash here |
|---|---|---|
| 0 | Preflight and plan, read-only | Nothing written |
| 1 | Undo log: old contents of every existing block to be rewritten, SHA-256 sealed, `F_FULLFSYNC`ed with its directory. Kept on the Mac, never on the target | Filesystem unchanged |
| 2 | "fresh": new bitmaps, zeroed inode tables, new backup groups. All free in the old filesystem or past its end; checked for each block | Old filesystem unchanged |
| 3 | "commit": GDT (incl. reserved blocks turned into GDT), old backup groups' GDT and superblock, resize inode, old last group's bitmap | `undo` |
| 4 | Primary superblock, last | `undo` |
| 5 | Re-read: full preflight on the result, descriptors equal to the plan, protected ranges re-hashed; then the log is removed | `undo` |

`sf-ext4grow undo TARGET --undo-log FILE` writes the saved blocks back (superblock last), checks the UUID first and runs the
preflight after: the result is the old filesystem in every block it uses. It is idempotent. `grow` refuses to start while a log
exists. A finished grow is detected by "block count already fills the target", so running S48 twice is a no-op.

Differences from `resize2fs`, on purpose: no rounding of a device's size down to the page size (`resize2fs` drops up to 3
blocks on arm64 macOS); the last group is dropped when it is smaller than its backup area + inode table + 2 + 50 blocks (the
rule observed from `resize2fs`).

## 6. Command line

```
sf-ext4grow inspect TARGET
sf-ext4grow plan    TARGET [--size BYTES | --blocks N] [--lazy-itables] [--root-json root.json] [--verbose]
sf-ext4grow grow    TARGET [...] [--undo-log FILE] [--keep-undo-log] [--unmount] [--write-map FILE] [--json]
sf-ext4grow undo    TARGET --undo-log FILE
```

TARGET is a plain file or an attached image's `/dev/diskN[sM]` (I/O goes through `/dev/rdisk…`, whole aligned 4 KiB blocks).

## 7. M1 results (24 November 2026, M5, macOS 26.5.2)

All with e2fsprogs 1.47.3 as the oracle (a user-local build on the M5).

| Claim | Evidence |
|---|---|
| The real 0.1.0 installer root (`ce208533…`) grows to 96 GiB through an attached raw disk image (`/dev/disk12`, checked against `hdiutil info`) | 530,524 → 25,165,824 blocks, 17 → 768 groups; 502 metadata blocks written, 313,897 inode-table blocks zeroed. `e2fsck -fn` clean: 72,474/5,099,520 files, 746,312/25,165,824 blocks |
| Same on a plain 96 GiB file, in both modes | Same counts, `e2fsck -fn` clean |
| Files unchanged | `debugfs rdump` of the root before and after: 71,171 entries, 38,609 files, same SHA-256, mode and link targets |
| Nothing else changed | In the old 530,524 blocks only 331 differ, and every one is in the tool's own write map: 328 metadata, the primary superblock, and 2 new bitmaps in blocks that were free |
| CHL-40 slots unmoved | Firmware slot (offset 1,729,200,128, 32 MiB) and receipt slot (1,762,754,560, 64 KiB): byte-identical, no write inside |
| Same result as `resize2fs` | `dumpe2fs` identical apart from times, lifetime writes and the superblock checksum: same block, inode and reserved counts (reserved 1,258,281), same 768-group layout, flags and checksums. Block for block, 16 blocks differ: the primary and 15 backup superblocks (write time, kbytes written) and the inode-table block holding the resize inode (its times). `--lazy-itables` matches Linux `resize2fs` 1.47.4 on the i9 the same way |
| A synthetic test root (2,100 MiB, same features) grows to 96 GiB through an attached image | `e2fsck -fn` clean, no unlisted change |
| `scripts/oracle-test.sh` | **349 checks, 0 failures** (about 8 minutes): 3 synthetic bases (64, 300, 2,100 MiB) × 13 targets × 2 modes (fsck, files, write map, `dumpe2fs` equal to `resize2fs`, second run a no-op); 11 refusals, each leaving the image untouched; a stop after the fresh and after the commit phase, then undo (old filesystem back, fsck clean) and a clean regrow; a grow through an attached image; a mounted image and an attached image file refused; the real-root run |

## 8. Risks

- **flex_bg.** Placement follows the layout mke2fs and resize2fs use, and matches resize2fs on every tested size. The fallback
  (first free run, when a flex slot is taken) is valid ext4 but has no test image yet.
- **resize_inode / meta_bg.** Growth is limited to what the reserved GDT blocks describe: 16,640 groups, **2.03 TiB** for the
  0.1.0 root. A bigger root partition is refused (`beyond-limit`). meta_bg is refused, not supported.
- **metadata_csum.** Every checksum is verified before planning and after writing; the CRC32C seed comes from
  `metadata_csum_seed`. Verified against the real root and by e2fsck on every result.
- **Journal.** Only checked (clean, no errors), never written. A fresh root from the image is always clean; a root that has been
  booted and not cleanly shut down is refused, and S48 would need an fsck path for it (not planned).
- **Darwin's ext4 driver** has not mounted a grown root yet. The new groups use only flags the 0.1.0 root already carries
  (`INODE_UNINIT`, `BLOCK_UNINIT`, `ITABLE_ZEROED`). Needs the QEMU boot (PAYLOAD.md section 12) or G6.
- **Real partitions** are refused by design. Raw I/O is proven on attached images; the helper's real-disk path stays behind its gate.

## 9. What is left

| Item | Estimate |
|---|---|
| M2: S48 in SFEngine through the helper's chokepoint (image backend first), undo log under the helper's state directory, journal entries, idempotence, engine tests | 2–3 days |
| M3: wider proof: a few hundred random sizes against resize2fs, a stop after every single write (not only per phase) with undo, an image that forces the flex fallback, the next release root from the builder | 2 days |
| M4: boot a grown root in QEMU (with the PAYLOAD QEMU item), fsck after | 1 day on top of that item |
| Review and hardening | 1–2 days |
