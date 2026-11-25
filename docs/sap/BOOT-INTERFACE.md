<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Chris Kearney and the SiliconForest contributors -->
# SAP and the boot partition

SAP writes two things on SFBOOT: the kernel image (`kernel.bin`, PDSF records: CONFIG with the boot
arguments, the gzip'd kernel collection, END) and stage 2 (`boot.bin`). It never writes stage 1, the
boot policy, NVRAM, or anything outside SFBOOT, and only with `sap upgrade --boot`.

`boot_backend` in `/etc/sap.conf` picks how:

| `boot_backend` | When | Result |
|---|---|---|
| `auto` (default) | always | `slots` if SFBOOT has `sf/bootstate.bin`, else `legacy` |
| `legacy` | stage 1 v1 | in place with `.old` copies; refused if `sf/bootstate.bin` exists |
| `slots` | stage 1 v2 | A/B try-once through `sf-bootslot`; refused without `sf/bootstate.bin` |

Only `sf-bootslot init` creates `sf/bootstate.bin`, and it is only run where stage 1 v2 is installed,
so the record's presence is how SAP knows stage 1 can fall back (design 10.6 leaves the final signal
open; see the deltas in the report).

## Legacy (design 3.5)

1. Stage the new file under `sf/.sap-staging/<txn>/`, fsync, read back, compare SHA-256.
2. In the commit (after every root-side operation): copy the current file to `<file>.old` (one per
   file; a leftover from an earlier transaction is replaced), then `rename` the staged file over it.
3. Recovery and rollback restore from `.old`.

FAT32 has no atomic replace; a power cut during step 2 can leave a broken `boot.bin`/`kernel.bin`, and
nothing at boot falls back. That risk is why the A/B backend exists.

## A/B slots (design 10, `integrations/siliconforest/m1-native-boot/install/abboot`)

| Slot | Stage 2 | Kernel |
|---|---|---|
| A | `sf/boot.bin` | `sf/kernel.bin` (no `sf_slot`) |
| B | `sf/b/boot.bin` | `sf/b/kernel.bin` (`sf_slot=b` in CONFIG) |

What `sap upgrade --boot` does (design 10.5):

1. `sf-bootslot status`. Refuse while a trial is `armed` or `tried`; the target slot is the one that is
   not the default (and never the running one).
2. Build the target slot's kernel.bin from the **default** slot's kernel.bin: the machine's boot
   arguments, the trust token (rotated if the manifest says so), `sf_slot` for the target, and the
   collection (relinked if inputs changed, else the current one).
3. Take the target slot's stage 2 from the `sf-boot` package: `/sf/boot.bin` is the slot-A build,
   `/sf/b/boot.bin` the slot-B build (`sap_build.py publish --boot-bin A --boot-bin-b B`). A release
   without the slot-B build cannot be staged into B; SAP refuses (exit 30) and changes nothing.
   `sf-boot` joins every boot transaction so the slot always gets a complete pair.
4. `sf-bootslot begin-stage <slot>` (clears the slot's entry), write both files (temp file, fsync,
   rename, read back), all before the journal's commit point.
5. Commit the root side; the last journal operation is `arm`: `sf-bootslot --generation <sequence> arm
   <slot>`. Recovery re-runs it if the slot's stage 2 still matches; it is idempotent.
6. Report "reboot required". At the next start stage 1 v2 tries the slot once; `sf-bootslot early`
   (launchd) records the try; `sap mark-good` (`sf-bootslot mark-good`) after a clean start makes it
   the default. A start that never reports clean falls back to the old default by itself.

No file of the default slot is written at any point. In image mode (`--root`) SAP runs the tool named
by `SAP_BOOTSLOT_TOOL` (a host build) with `--running <default>`.

**Rollback.** A rollback before the restart (`sap rollback`, `sap recover --rollback`, or a failed
commit undoing itself) runs `sf-bootslot disarm b`: the ARMED trial is cancelled and slot B is left
unrecorded, as `begin-stage` left it, and B's files are put back. Stage 1 then starts the default with
no notice. Once the trial has been started (`early` made it TRIED), `disarm` is refused and SAP leaves
the slots alone: a start that never reports clean falls back by itself, and `sap boot-status` shows it.

**verify.** With slots, `sap verify` checks the stage 2 of the slot SAP last staged (the armed or tried
trial, else the default); with the legacy layout `/sf/b/*` is not installed and not checked.
