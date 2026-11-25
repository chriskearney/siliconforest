<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Chris Kearney and the SiliconForest contributors -->
# SAP: the SiliconForest system updater

SAP updates an installed SiliconForest machine from a signed, static update channel: only the
packages that changed are downloaded, every byte is checked against a signed hash before anything
is written, files are swapped in through a crash-safe journal, and the kernel collection and stage 2
on SFBOOT are updated through the same transaction. The design is the "SAP updater design" document
(design numbers below, like 3.5, refer to its sections).

| Part | Where |
|---|---|
| Client `sap` (also `sf sap`), Rust | `sap/client/` |
| Publisher and reference verifier, Python | `sap/tools/sap_build.py` |
| Trust anchor compiled into the client | `sap/trust/release-keys` (same keys as `installer/payload/release/allowed_signers`) |
| Tests (unit, end-to-end, fault injection) | `sap/client/src/*` `#[test]`, `sap/tests/`, CI `.github/workflows/sap.yml` |
| Operator guide (publishing, keys, rotation) | [OPERATOR.md](OPERATOR.md) |
| Formats (manifest, record, file list, payload, journal) | [FORMATS.md](FORMATS.md) |
| Boot partition: legacy and A/B slots | [BOOT-INTERFACE.md](BOOT-INTERFACE.md) |

**Status.** Built and tested on Linux and macOS hosts against fake roots and fake SFBOOT
directories only. Nothing has run on a SiliconForest machine yet; see "Before the first real
update" below.

## Using it

    sap check                      # exit 10 if updates are available
    sap list [--installed|--upgradable|--available]
    sap show vim
    sap upgrade [PKG…] [--dry-run] [--download-only] [--boot] [--adopt PATH]… [--ignore-power] [-y]
    sap install PKG… | --all [--boot]
    sap verify [PKG…] [--repair]
    sap history
    sap rollback [TXN]
    sap hold PKG… / sap unhold PKG…
    sap recover [--rollback]
    sap boot-status                # A/B boot record (stage 1 v2), or "legacy layout"
    sap mark-good [--wait S] [--no-health]   # after a clean start from an updated slot (IMAGE.md)

Global options: `--root DIR` (operate on an image, not the running system), `--sfboot DIR`,
`--manifest-url URL`, `--trust-anchor FILE` (images only, with `--root`), `--offline`, `--json`.

Kernel, kernel-collection and stage 2 updates (package kinds `kc-input`, `kc-recipe`,
`boot-stage2`) and trust-anchor rotation are only applied with `--boot`; without it `sap upgrade`
says what is waiting.

Exit codes: 0 ok · 10 updates available · 20 verification failure (nothing changed) · 21 manifest
expired or replayed · 30 conflict or dependency failure · 40 a transaction was interrupted (run
`sap recover`) · 50 done, reboot required · 1 anything else.

### /etc/sap.conf

    channel = stable
    manifest_url = https://updates.example/v1/stable/manifest.json
    sfboot = /Volumes/SFBOOT          # where SFBOOT is mounted (Q3: settled by the image recipe)
    boot_backend = auto               # auto | legacy | slots (BOOT-INTERFACE.md)
    bootslot_tool = /usr/libexec/sf-bootslot
    require_ac = yes                  # boot updates only on AC power (IMAGE.md, Power)
    health_services = LABEL …         # also wait for these before mark-good

Unknown keys are ignored. The image's own copy is `sap/image/sap.conf` (IMAGE.md).

### On-disk state (all under the root)

| Path | What |
|---|---|
| `/private/var/db/sap/state.json` | highest accepted sequence, holds, manifest hash, anchor version |
| `/private/var/db/sap/installed/<pkg>.json`, `.files.tsv` | installed packages and the files each owns |
| `/private/var/db/sap/journal/<txn>.jsonl` | one hash-chained journal per transaction |
| `/private/var/cache/sap/` | the last verified manifest and downloaded payloads (by SHA-256) |
| `/private/var/lib/sap/staging/`, `backup/` | staged files; backups of the last two transactions |

## How an upgrade runs (design 3.1)

1. Fetch `manifest.json` and `manifest.json.sig`; verify the Ed25519 SSHSIG (namespace
   `siliconforest-release`) against the trust anchor; parse strictly (no duplicate keys, integers
   only, 4 MiB cap, unknown `critical` names refused, other unknown fields ignored).
2. Freshness: reject an expired manifest, a lower sequence than the highest seen (replay), or a
   different manifest with the same sequence (fork).
3. Resolve: compare with the installed database; dependencies, conflicts, holds, `min_sap`; `sap`
   itself is updated first and re-executed.
4. Fetch each changed package's record and file list (pinned by SHA-256 in the manifest), check
   file ownership (no package takes another's file without `replaces`, protected installer files
   and SAP's own state are refused, no path may go through a symlink, unowned differing files need
   `--adopt`), then download only changed payloads and check every file's SHA-256.
5. Stage everything under `/private/var/lib/sap/staging/<txn>` (same filesystem as the targets),
   relink the kernel collection with kc-builder if any kernel input changed and check it against the
   recipe's `collection_sha256`.
6. Commit: write the intent (every operation) to the journal, then swap each file in by `rename`,
   backing up what it replaces by hard link; the database entries are operations of the same
   transaction. SFBOOT is written last (legacy: `.old` copies; slots: the inactive slot, armed last).
7. Record `done`, restart named services (`launchctl kickstart -k`), report "reboot required" for
   kernel and stage 2 changes.

A crash anywhere leaves either the old or the new system: `sap recover` (also run at the start of
every upgrade) finishes a transaction whose staged copies are all intact, and rolls back otherwise;
`sap recover --rollback` always rolls back. The end-to-end tests kill the client after every journal
record and every swap and check exactly that.

## Before the first real update

What a test on hardware still needs (design 11 questions; deltas in the final report):

* **Trust anchor.** The installer writes `sf/trust` on SFBOOT, and `sf_trust=` into the boot arguments
  when it fits (IMAGE.md); without either SAP warns and falls back to the compiled-in key list.
* **SFBOOT mount (Q3).** `org.siliconforest.sap-boot` mounts SFBOOT read-write at `/Volumes/SFBOOT`
  (`sf-mount-sfboot`, IMAGE.md). The msdosfs argument layout is PureDarwin's; it has to be seen to
  work on the machine.
* **Root filesystem atomicity (Q2).** The journal assumes `rename` is atomic and `fsync` durable on the
  root filesystem (ext4 through SiliconForest's ext4.kext); checked on the QEMU guest, not on NVMe.
* **kc-builder on SiliconForest (Q5).** The relink runs `/usr/libexec/sap/kc-builder` on the machine; the
  kernel-collection inputs live under `/System/Library/SiliconForest/KernelCollection` (proposal).
* **HTTPS.** `https://` URLs go through `/usr/bin/curl` with `--cacert /etc/ssl/cert.pem`; the root has both.
* **Boot fallback (Q4).** With stage 1 v2 and `sf/bootstate.bin` (written by the installer, IMAGE.md),
  SAP stages into the inactive slot (BOOT-INTERFACE.md); `early` and a health-gated `mark-good` run
  from launchd. Without them the legacy backend replaces SFBOOT files in place, with `.old` copies.
* **First channel.** prepare_root.py `--sap-bin` publishes the image's channel and seeds the database
  (IMAGE.md); the channel still needs a host (`manifest_url`) and the M3 signature.
