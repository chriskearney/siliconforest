<!-- SPDX-License-Identifier: MIT -->

# SAP in the SiliconForest image and on SFBOOT

How SAP gets onto an installed machine: the files the root image carries, the database seeded at
image build, what the installer writes to SFBOOT, and the two launchd jobs that make A/B boot work.
Design: sections 3.5 (power), 4.3 (bootstrap), 8.2 (trust anchor), 10 (A/B boot).

## Building the binaries (aarch64-apple-darwin)

    sap/tools/build_darwin.sh OUT

on the build host with the Darwin cross linker of the userland (chonkstep `link-inputs.nix`,
`darwin-linker-inputs.py`; `rustup target add aarch64-apple-darwin`). It builds `sap` and `sf`
(cargo, release profile, no `testing` feature) and the two C tools, `sf-bootslot`
(`m1-native-boot/install/abboot`) and `sf-mount-sfboot` (`sap/image`), with `-Werror`, and writes
`OUT/build.json` (sizes, SHA-256, toolchain). They link only libSystem (libc, libm, libiconv), which
the root has.

## What the root image carries

`installer/payload/image/prepare_root.py BASE OUT --sap-bin OUT_OF_build_darwin --sap-channel DIR`
adds (`sap/tools/sap_image.py`):

| Path | What |
|---|---|
| `/usr/bin/sap`, `/usr/bin/sf` | the client |
| `/usr/libexec/sf-bootslot` | the A/B record tool (BOOT-INTERFACE.md) |
| `/usr/libexec/sap/sf-mount-sfboot` | mounts SFBOOT read-write (below) |
| `/usr/libexec/sap/sap-boot`, `sap-mark-good` | the launchd jobs' scripts |
| `/System/Library/LaunchDaemons/org.siliconforest.sap-boot.plist`, `…sap-mark-good.plist` | RunAtLoad, LaunchOnlyOnce |
| `/etc/sap.conf` | `sap/image/sap.conf`; `--sap-manifest-url` sets `manifest_url` |
| `/usr/libexec/sap/kc-builder`, `LICENSE.kc-tools` | when OUT has them (`SAP_KC_BUILDER=1`): the relink tool (design Q5) |
| `/private/var/db/sap/…` | the installed database, seeded |

The base root already has `/usr/bin/curl` and `/etc/ssl/cert.pem` (the CA bundle SAP passes to curl
with `--cacert`), `/bin/launchctl` and `msdosfs.kext`. It has no `mount_msdos`, `pmset` or `ioreg`.

The SAP files are the package `sap` (base `sf-base`). After writing them, prepare_root reads the
image back (`debugfs rdump`), publishes the image's channel from it (root packages only: `sf-base`
and `sap`, release = the base's `image.json` version, `--sap-sequence`) and runs `seed-db` against
that channel, then writes the database into the image and lists it in `root.manifest.tsv`. On the
installed machine `sap verify` is clean from the first start and `sap upgrade` downloads only what a
later release changes. The channel is published `--unsigned` (signed offline on the M3: signing
does not change `manifest.json`) or, for a rehearsal only, with `--sap-key TEST-ONLY…`.

Kernel-collection and stage 2 packages are not in the image's channel: the first
`sap install --all --boot` adopts what SFBOOT holds (README.md, `--adopt`).

## SFBOOT: what the installer writes (S42)

| SFBOOT path | Release artifact (install.json `boot`) | When |
|---|---|---|
| `sf/boot.bin`, `sf/kernel.bin` | `stage2`, the personalised kernel | always |
| `sf/b/boot.bin` | `stage2_b` (`boot-b.bin`, role `boot-stage2-b`) | the boot directory has `boot-b.bin` |
| `sf/trust` | `trust` (`sf-trust.txt`, role `boot-trust`) | always (make_release.py) |
| `sf/bootstate.bin` | `bootstate` (role `boot-state`), written last | stage 1 v2 **and** `boot-b.bin` |

`make_release.py` makes `bootstate.bin` by running a host build of `sf-bootslot --running a
--generation SEQUENCE init` on a scratch SFBOOT holding the release's `boot.bin`: slot A as
installed, good; slot B empty (design 10.6: never with stage 1 v1, which never reads the record;
`--slots auto|yes|no`, `yes` with a placeholder stage 1 only in a rehearsal). Stage 1 v2 is
`m1-native-boot/install/abboot/build_stage1_v2.sh`, shipped as `sf-stage1.bin`; `build_stage1.sh`
still builds v1. The engine checks every one of these files by SHA-256 at S42's read-back.

### The trust anchor

`sf_trust=1:<base64 key>` is 54 characters. m1n1 passes at most 607 characters of boot arguments;
J313's personalised arguments are about 587 already, so the token does not fit there. make_release
appends it to `bootargs.template` only when the worst-case personalised length (UUIDs 36, LBA and
block counts 10 digits, plus ` sf_slot=b`) stays under 608 (`boot.trust_in_bootargs`), and always
ships `sf-trust.txt`. SAP looks, in order, at the boot arguments' token, then `<sfboot>/sf/trust`
("boot partition (sf/trust)"), then the compiled-in keys (with a warning). `sf/trust` is on the same
partition as `kernel.bin`, so it is as trustworthy as the boot arguments themselves.

The template's format: lines starting with `#` are comments, the others are joined with spaces;
the installer fills `@SF_FSUUID@`, `@SF_PARTUUID@`, `@SF_PART_LBA@` and `@SF_PART_BLOCKS@`.

## At every start

`org.siliconforest.sap-boot` (`sap/image/sap-boot`, log `/var/log/sap-boot.log`):

1. `sf-mount-sfboot /Volumes/SFBOOT`: finds the one `rdiskNsM` whose boot sector is FAT32 with the
   label `SFBOOT` (none or two: nothing is mounted) and mounts the block device with
   `mount("msdos", …)`, root-owned, read-write, `noatime`. Already mounted there: nothing to do.
2. With `sf/bootstate.bin` present: `sf-bootslot early` (an armed trial that is running becomes
   TRIED; a trial stage 1 skipped becomes FAILED), then `status` into the log.
3. `/var/run/sap-boot.done` holds the outcome (`early-ok`, `early-refused`, `no-record`, `no-sfboot`).
   The job never fails the start.

`org.siliconforest.sap-mark-good` (`sap/image/sap-mark-good`) waits for that file and, after
`early-ok` only, runs `sap mark-good --wait 600`. When the running slot is the one being tried, SAP
waits until every launchd service the installed packages name (`services` in their records) and
every `health_services` label in `/etc/sap.conf` is running (`launchctl list LABEL`: a PID, or last
exit status 0), and only then runs `sf-bootslot mark-good`. If they are not all up in time it marks
nothing and says so: the next start goes back to the default slot by itself. `--no-health` skips the
wait (by hand only).

## Power

Boot and kernel updates (`sap upgrade --boot` with boot work to do) need AC power (design 3.5):
on battery SAP stops with exit 30 before staging anything (`--ignore-power` overrides). SAP reads
`pmset -g batt`; SiliconForest has no `pmset` and does not expose the battery yet (SF-K K4), so on
SiliconForest power is "unknown": SAP warns and continues. `require_ac = no` turns the check off.
Image mode (`--root`) never checks.

## Checked without hardware (sap/tests/guest)

`sap/tests/guest/cases.py` (on the build host; QEMU arm64 `virt`, SiliconForest's release kernel,
ext4.kext root, disks are files under `runs/sap-guest`) checks what SAP assumes of the machine:

* **durable**: write + fsync + rename + fsync(dir) in a loop on the ext4 root; QEMU is killed
  (SIGKILL, a power cut) at several acknowledged steps. After a host e2fsck and when the guest boots
  the cut disk itself, the file is always one whole record, never older than the last acknowledgement.
* **sap-cut**: the Darwin build of sap installs 0.1.0 into a root directory, upgrades to 0.1.1 and is
  stopped for good at a journal record or a file operation (`SAP_FAULT=halt:rec:N|op:N`, testing
  builds only), then the power is cut. On the next boot `sap recover` and `sap verify` both succeed.
* **sfboot**: a second disk (GPT, FAT32 `SFBOOT`) with the installer's record. sf-mount-sfboot mounts
  it read-write through msdosfs.kext, sf-bootslot stages and arms slot B, the record reads back on
  the host; booted with `sf_slot=b`, the two launchd jobs run `early` and, once the health service
  runs, `mark-good`: the record ends with default=b.
* **kc**: kc-builder built for SiliconForest links the release's kernel-collection inputs in the
  guest; the collection is byte-identical to the host kc-builder's.

Only the machine can show: stage 1 v2 choosing slot B and falling back to A (m1n1, iBoot), Apple's
NVMe and ext4 on it, msdosfs on the real SFBOOT, the real services' health, and power (no battery
reading on SiliconForest yet).
