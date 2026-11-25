<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Chris Kearney and the SiliconForest contributors -->
# A/B try-once boot (stage 1 v2)

Two copies ("slots") of the files stage 1 starts, a small state record on SFBOOT, and a rule:
an updated slot is started **once**; unless the system that runs from it says the start was
clean, the next start uses the previous slot and says why on the screen. The design is section
"A/B try-once boot" of the SAP updater design document; this file is the implementation's view.

**Status.** Built and tested on the host only. Nothing here has run on hardware. The installer
still ships stage 1 **v1** (`installer/payload/boot/build_stage1.sh`, SHA-256 `44c1ef0b…`),
and nothing in this directory changes v1 or the installer.

## Layout on SFBOOT

| Slot | Stage 2 | Kernel image | Written by |
|---|---|---|---|
| A | `sf/boot.bin` | `sf/kernel.bin` | the installer (unchanged), later SAP |
| B | `sf/b/boot.bin` | `sf/b/kernel.bin` | SAP |
| — | `sf/bootstate.bin` (8192 bytes) | | `sf-bootslot init`, then every transition |

Each slot's stage 2 reads its own kernel image (a slot-B stage 2 is built with
`PDSF_KERNEL_FILE="sf/b/kernel.bin"`; not built yet). Slot B's kernel CONFIG carries
`sf_slot=b`, so the running system knows its slot; no `sf_slot` means a.

## The record

`sf/bootstate.bin` holds two 64-byte copies, at offsets 0 and 4096. A reader takes the valid
copy with the higher sequence number; a writer overwrites the other (older or damaged) copy in
place and fsyncs, so a torn write leaves the previous state. The file never changes size, so the
FAT is not written after `init`. All fields little-endian:

| Offset | Field |
|---|---|
| 0 | magic `SFBOOTAB` |
| 8 | u16 format = 1, u16 record bytes = 64 |
| 12 | u32 seq (serial arithmetic) |
| 16 | u8 default slot (0 = A, 1 = B), u8 trial slot (0xff = none), u8 trial state (NONE 0, ARMED 1, TRIED 2, FAILED 3), u8 flags = 0 |
| 20 | u32 reason of the last fallback |
| 24, 40 | per slot: u32 stage 2 bytes, u32 stage 2 CRC-32, u32 generation, u8 good, 3 bytes 0 |
| 56 | u32 0 |
| 60 | u32 CRC-32 (IEEE) of bytes 0..59 |

The CRC finds damage, not tampering: whoever can write SFBOOT can write the record too, so stage
1 is not a security boundary here (see the design's threat model).

## Who does what

| Step | Who | Change |
|---|---|---|
| `sf-bootslot init` | installer or first start | record for slot A as installed, A good |
| `sf-bootslot begin-stage b` | SAP, before writing B's files | B unrecorded (not good) |
| write `sf/b/*`, sync, read back | SAP | |
| `sf-bootslot arm b` | SAP | B's size and CRC recorded, trial B ARMED |
| start | stage 1 v2 | starts B, checked against the record |
| `sf-bootslot early` | first launchd job | ARMED → TRIED; or, started from the default, FAILED (shown) |
| `sf-bootslot mark-good` | after a clean start | trial B becomes the default and good |
| a start after TRIED | stage 1 v2 | starts the default, shows "never reported a clean start" |

Stage 1 v2's choice, from `sf_ab_decide()` (every candidate is tried in order until one starts;
"checked" means the file must have the recorded size and CRC-32):

| Record | Candidates |
|---|---|
| absent | A, B (unchecked): v1, plus B if A cannot start |
| both copies damaged | A, B (unchecked), the reason shown |
| ARMED | trial (checked), default (checked), default (unchecked) |
| TRIED | default (checked, "not confirmed" shown), trial (checked), default (unchecked) |
| NONE / FAILED | default (checked), the other slot if good, default (unchecked) |

It never does worse than v1: when every check fails it still starts the default slot unchecked.
Only the installer's chainload target `<uuid>;sf/boot.bin` takes this path; any other target is
chainloaded exactly as v1 does.

## The gap, and v3

m1n1 reads storage only (its FAT reader cannot write, and it has no NVMe write path), so v2
writes nothing: the one try is used up by the system itself, in `sf-bootslot early`. A trial slot
that dies **before** `early` runs (stage 2, kernel or early boot) is started again at the next
start, as long as its files pass the check. The way out then is from another system: delete or
rename `sf/b/boot.bin`, or run `sf-bootslot` there. A v3 stage 1 that writes TRIED itself (one
sector, raw, into the preallocated record) closes the gap; `sf_ab_decide()` already computes that
write (`plan.writeback`), and `sf-ab-stage1 --stage1-writes` simulates it.

## Files

| File | What |
|---|---|
| `sf_ab.h`, `sf_ab.c` | the record, the decision and the transitions; freestanding C (no libc), shared by stage 1 and the tools |
| `sf_ab_stage1.c` | stage 1's glue (m1n1, `SF_AB_BOOT`) |
| `../patches/stage1-v2/0002-…patch` | the m1n1 hooks: `SF_AB_BOOT=1` in the Makefile, `chainload_read_file`, `chainload_load_slot`, the call in `payload.c` (applied after `0001`; not matched by the `patches/*.patch` globs of v1 and stage 2) |
| `build_stage1_v2.sh OUT` | builds `sf-stage1-v2.bin` like v1, tag `<pin>-siliconforest-stage1-v2` |
| `sf-bootslot.c` | the userland tool (host and Darwin; a stub until SAP calls it) |
| `sf_ab_sim.c` | `sf-ab-stage1 DIR`: stage 1 v2's decision over a directory, for tests |
| `test_sf_ab.c`, `test_sf_ab_stage1.c`, `hostmock/` | C unit tests; the glue is tested against host stand-ins for m1n1 |
| `../../../../../tests/test_boot_ab.py` | builds and runs all of it, plus whole update cycles |

## Stage 1 v2 build

    PATH=$HOME/.cargo/bin:$PATH SF_M1N1_SRC=/path/to/m1n1-at-pin ./build_stage1_v2.sh OUT

With the v1 toolchain (clang/ld.lld 22.1.8, rustc 1.98.1) it is reproducible:

    STAGE1_V2_SHA256=c4be30876d39f7416145e56f56b021bc96e54c3b35899be12658a4406421994d

4,325,376 bytes, within the profile's footprint (`sfrelease.py check-stage1` passes).

## Before the installer can ship v2

1. Test on hardware: v2 from a fresh install (no record = v1), then a staged B.
2. Build a slot-B stage 2 (`PDSF_KERNEL_FILE="sf/b/kernel.bin"`) and add it to the payload.
3. Switch `build_stage1.sh` (and its test) to v2's patches, tag and hash, and give the installer
   app a v2 stub; installing a new stage 1 is a recovery-mode step, as any new stage 1 is.
4. Run `sf-bootslot init` at install time or first start, `early`/`mark-good` from launchd, and
   have SAP use `begin-stage`/`arm`. Anything that replaces slot files outside this protocol must
   rewrite or delete `sf/bootstate.bin`.
