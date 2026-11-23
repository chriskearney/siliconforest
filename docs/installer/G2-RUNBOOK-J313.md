<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Chris Kearney and the SiliconForest contributors -->

# G2 runbook: first RAM boot on the M1 MacBook Air (J313)

Written 22 November 2026 for CHL-27, gate G2 of [`FIRST-INSTALL-J313.md`](FIRST-INSTALL-J313.md).

> **Status: stopped at the approval below. Nothing in this runbook has run.** The research was read-only. The Air was not rebooted
> or written to. SiliconForest has still never booted on J313.
>
> **The Air cannot reach an m1n1 USB proxy under the approved G2 constraints.** Every route either needs a write to its boot chain
> or NVRAM, or does not work. The smallest route is one temporary, reversible replacement of `m1n1/boot.bin` on the Air's ESP.
> That is a boot-chain change, so it needs Chris's explicit go (section 3).

## 1. What is on the Air

Sources: the read-only ESP backup of 22 November, and the running Linux's device tree.

### Stage 1

- Live device tree: `asahi,m1n1-stage1-version = v1.5.2`. It lives in the stub, not on the ESP, and its bytes were not read.
- `asahi/stub_info.json` only describes the stub: macOS 13.5 (22G74), `j313ap`, board `0x26`, chip `0x8103`, and its admin users.
  It records nothing about m1n1.
- Upstream v1.5.2 in a `RELEASE=1 CHAINLOADING=1` build chainloads the file on the ESP and falls back to the USB proxy if it cannot.
  It has a 5-second early proxy window only when **no display is present and `lp-sip0 == 127`** (`src/main.c`, `config.h` at the
  `v1.5.2` tag). It has no `m1n1-proxy` option and no keyboard check.

### Stage 2: `m1n1/boot.bin`

| Property | Observed |
|---|---|
| Size | 10,107,602 bytes |
| SHA-256 | `54fa07e4f5cbeecd90e67e335657c40b33c25aede7015a84afb1427333b4f923` |
| Version tag | `f5a82fdb-dirty`, matching the live `asahi,m1n1-stage2-version` |
| Same bytes as | The Pro's original loader recorded in [`M1_RECOVERY.md`](../M1_RECOVERY.md) |
| Payloads | 115 device trees from offset `0x400000` (J313 included), then gzip U-Boot 2026.07, ending at end of file |
| Appended configuration | **None.** No `chainload=`, `display=` or other variable lines sit between or after the payloads |
| Proxy window | **None.** No stage 1 configuration block (`AURORA-S1-CFG01`) and no early-proxy strings |

The `f5a82fdb` source is not in this lab. The closest source is `121fcbf`, so conclusions about this binary come from its bytes and
strings plus that related source. In `121fcbf`, `m1n1-proxy` works only in stage 1 and an `ESP_STAGE2` build ignores it.

### `siliconforest-recovery/` and the other SiliconForest names on the ESP

These belong to **SiliconForest Linux, a separate project with the same name**, not to this Darwin project. The Air has its
`siliconforest-branding` package and its rollback records under `/var/lib/siliconforest/transactions`.

- The 14 directories date from 18 to 22 October. Each saves the previous stage 2, the previous Limine menu (`boot-menu.cfg`) and
  a README describing a manual Linux rollback. Their saved stage 2 builds are `v1.6.1-omarchy.aurora17` and `v2.0.0-siliconforest.dev`.
- `EFI/Linux/siliconforest-normal-*.efi` is an Arch Linux ARM kernel (`7.2.11-lab182-…`).
- So "SiliconForest has never booted on J313" in `FIRST-INSTALL-J313.md` stands. It means this Darwin system.
- The transaction directories are root-only and were not opened, so the exact tool and operator are not established.

## 2. Every route to a proxy session

| Route | Writes anything persistent? | Needs a person? | Result |
|---|---|---|---|
| `kexec` m1n1 from Linux | No | No | **Blocked.** All CPUs use `spin-table`, there is no `cpu1/online`, and the kernel contains the refusal `Can't kexec: CPUs are stuck in the kernel`. Only `kexec_file_load` is built, m1n1 has no arm64 `Image` magic, and it needs iBoot's boot arguments |
| A custom kernel module that jumps to m1n1 | No | No, until it fails | **Rejected.** New privileged code, already-started CPUs cannot be restarted through iBoot's path, and a failure would hard-stop a read-write Linux root |
| `m1n1-proxy` boot argument | **NVRAM** | No | **Not allowed and ineffective.** Stage 1 v1.5.2 has no such option, and stage 2 ignores it |
| Stage 1 early proxy window | Possibly **boot policy** | Yes | **Not usable.** Needs `lp-sip0 == 127`, which Linux cannot read here, and no display. Whether a closed lid counts is unknown. Changing SIP is a boot-policy change |
| Keypress in m1n1 | No | Yes | **Does not exist** in stage 1 v1.5.2 or in the stage 2 strings |
| Limine menu or U-Boot prompt | No | Yes | **No route.** Nothing on the ESP starts a proxy, and U-Boot has no tested way to re-enter m1n1 with iBoot's boot arguments |
| Startup picker or recoveryOS | Only if used to change policy | Yes | **No route** without a change that is not authorized |
| `macvdmtool reboot` from the M5 | No | No | **Reset only.** The Air boots its normal chain back to Linux |
| DFU | Forbidden | Yes | **Not allowed** |
| Temporary J313 window build as `m1n1/boot.bin` | **One ESP file** | No, unless recovery is needed | **Works in principle. Recommended, needs approval** |

## 3. Decision needed from Chris

**Approve or decline one temporary change:** replace `m1n1/boot.bin` on the Air's ESP with a J313 build that waits 10 seconds for a
USB proxy request, then boots the same device trees and U-Boot as today. Afterwards the original file is restored and verified.

- Unchanged: stage 1, the stub, NVRAM, boot policy, the Linux root, partitions, and Linux as the default.
- Without a host request the Air boots Linux about 10 seconds later than normal.
- **The risk is a failed Linux boot.** The window build uses m1n1 `121fcbf`, not the `f5a82fdb` the Air runs today. The Pro has run
  that source with this same payload, but J313 has not. The new file is also larger, and stage 1 can refuse an image that does not fit
  its heap, as happened on the Pro's first install.
- **If it fails, a person may have to restore the file from recoveryOS** (section 7).

If declined, G2 stays stopped. No other route in section 2 works within the constraints.

## 4. What must exist before the first boot

None of these touch the Air.

1. **G0 and G1 are done on the host, unbooted.** Use the **G2 RAM boot** collection recorded in
   [`FIRST-INSTALL-J313.md`](FIRST-INSTALL-J313.md) section 5. The other collection there contains the write-capable NVMe driver.
2. **A J313 window build.** Candidate004 enters its window only for `J293`, so on the Air it would act as a plain loader. Build a
   distinct J313-only variant with its own version tag, keeping the 10-second limit and the complete-NOP claim rule. Append the Air's
   exact bytes from offset `0x400000`.
3. **A J313 install and restore script, reviewed before use.** `tools/m1_boot_install.py` is J293-only and keeps state under
   `/var/lib`. The Air's root has about 1.3 MB free and must not be written, so the new script may touch only the ESP.
4. **J313 launcher support.** `host_progress.py`, `bootstrap.py` and the bring-up controller require `J293` and `MacBookPro17,1`.
   Add an explicit J313 path. Do not remove the board checks.
5. **A J313 RAM-boot argument list**, derived from `installer/profiles/J313.json` with these rules:
   - **Remove** `rd=uuid`, `boot-uuid=` and every `sfnvme*` argument. The profile's list includes `sfnvme=3` and `sfnvme_write=1`,
     which are for an installed system and must never reach this boot.
   - **Keep** `sfsound=0` and `sftouchbar=0`. `sfsound=0` is a safety requirement on J313.
   - **Add** `sfm1tpmt=0`. Multitouch mode is on by default, and this boot must not enable it.
   - Use a RAM root and the **default** collection, which has no NVMe driver. Never use the `storage` collection.
   - Start the guest script with `rebase/guest/rb-prologue.sh`, which ends the session if anything attaches to the NVMe controller.

With no NVMe driver in the collection, the running system has no path to write to the disk. That is stronger than the driver's write
fence, which only matters if a later, separately approved boot loads the driver.

### M5 tooling

No installs are needed. Read-only checks on the M5 found:

- `macvdmtool` **is present** in the lab's `native-control-src` directory, with the pinned SHA-256 (`db6da3ff…`). It is not on `PATH`.
- The lab virtual environment has `pyserial` 3.5 and `construct` 2.10.70, and `sudo -n` works.
- The Air is on **M5 receptacle 1** as a 40 Gb/s Thunderbolt peer. No `/dev/cu.usbmodem*` exists yet, which is expected.

**Port on the Air:** the cable is in **USB-C Left-back** (`typec0`, `usb-pd@38`), the first port m1n1 brings up. Leave it there.
This cable and port have not yet been seen enumerating as CDC, so the first window is also that test.

## 5. Bench hazard while the Air is connected

`macvdmtool` always uses the HPM with `RID=0`, and on this M5 that is **receptacle 1, now the Air**. Any Pro bench tool that issues
its recovery reset, including `tools/pcie_iterate.sh` and `tools/m1_return_linux.sh`, **would reset the Air instead of the Pro**.

Do not run Pro bench cycles while the Air is on receptacle 1. Take `tools/bench.sh` for the whole G2 session.

## 6. Runbook

Run only after section 3 is approved and section 4 is complete.

### P0. Preflight (read-only)

1. Hold the bench with `tools/bench.sh`. Confirm no other actor is running.
2. On the Air, confirm: J313, stage 2 hash `54fa07e4…`, Linux as the running default, ESP free space, and no pending one-shot entry.
3. Confirm the i9 backup of the ESP has finished, and its `m1n1/boot.bin` has the same hash.
4. On the M5, confirm receptacle 1 is the Air and `macvdmtool` has the pinned hash.
5. Confirm someone can reach the Air if recovery is needed.

### P1. Install the window build (the only boot-chain write)

1. Copy the original to `m1n1/boot.bin.pre-g2` on the ESP and verify its hash. Do not reuse `boot.bin.old` or
   `boot.bin.pre-omacom-50fb`, which are different builds.
2. Write the candidate to a temporary name on the ESP, `fsync`, and verify its hash.
3. Rename it over `m1n1/boot.bin`, sync, and verify again.

### P2. Enter the proxy

1. Stop Linux services cleanly and run `systemctl reboot` on the Air.
2. On the M5, open the new `/dev/cu.usbmodem*` and send one complete proxy NOP inside the 10-second window.
3. Require the J313 window tag, board `J313`, chip `0x8103`, and the expected USB interfaces. On any mismatch, go to P5.

### P3. Load SiliconForest into RAM

1. Build the packet on the i9 and deliver it to a new private directory on the M5.
2. Use the J313 launcher to load the collection and RAM root over USB, under the m1n1 hypervisor, with the section 4 arguments.
3. Save the serial log privately. Hold the first session to **180 seconds**.
4. Require the `RB_NVME_OK` line. If it is missing, end the session.

### P4. Observe (G3)

A person must watch the Air. Host logs cannot prove the screen or physical input.

| Item | Pass needs | Notes |
|---|---|---|
| Screen | The desktop or console is visibly correct on the panel | Check brightness behaviour. J313's panel maximum is 420 |
| Keyboard | A person types and sees the characters | Host-injected input does not count |
| Trackpad | A person moves the pointer | Do not enable multitouch mode |
| Wi-Fi | `en0` appears, scans, and joins | Board `apple,shikoku`. Keep credentials and firmware out of the repository |
| Heat | No sustained hot chassis | J313 has **no fan** and the limits were set on a machine with one. Keep the first session idle |

Record what was seen as a separate human witness, not as a boot result.

### P5. Return to Linux

1. From the M5, run the pinned `macvdmtool reboot` **once**, after confirming receptacle 1 is still the Air.
2. The Air restarts through stage 1 and the window build. With no host request it continues to U-Boot, Limine and the default Linux.
3. Require a new boot ID, the same Linux kernel, the root mounted read-write, and no failed boot entry.

### P6. Restore the original stage 2

1. From Linux, copy `m1n1/boot.bin.pre-g2` to a temporary name on the ESP, `fsync`, and verify `54fa07e4…`.
2. Rename it over `m1n1/boot.bin`, sync, and verify again.
3. Reboot once and confirm `asahi,m1n1-stage2-version` is `f5a82fdb-dirty`.
4. Only then delete `boot.bin.pre-g2`, and confirm the default boot entry is unchanged.

**Keep the window build installed between sessions only if Chris approves that separately.**

## 7. Abort conditions and recovery

Stop the session, and do not retry, on any of these:

| Condition | Action |
|---|---|
| Any preflight check differs | Stop. Nothing has been written |
| The M5 sees no USB device during the window, and Linux returns | Run P6. Record it. Do not retry until the cause is understood |
| The wrong board or tag answers | Do not load anything. Go to P5, then P6 |
| A launcher or hash check refuses | Go to P5, then P6 |
| Any NVMe driver appears, `RB_NVME_OK` is missing, or a kernel panic occurs | End the session. Go to P5, then P6 |
| The chassis gets hot | End the session at once. Go to P5, then P6 |
| Linux does not return after the one reset | **Do not reset again.** Use the recovery below |

**Recovery if Linux does not boot (needs a person at the Air):**

1. Hold the power button until the Air is off.
2. Hold it again until "Loading startup options" appears. Choose **Options**, then **Utilities > Terminal**.
3. Run `diskutil list` and identify the Linux ESP (about 500 MB, FAT). **Do not assume its partition number.**
4. Mount it, copy `m1n1/boot.bin.pre-g2` over `m1n1/boot.bin`, and check it with `shasum -a 256`.
5. Restart. Do not run `bputil`, `csrutil` or any other policy command.

## 8. What a person must do

| When | Action |
|---|---|
| Before anything | **Chris approves or declines section 3** |
| P0 to P3 | Nothing physical if all goes well. Someone should be able to reach the Air |
| P4 (G3) | **Be at the Air** to watch the screen, type, use the trackpad and feel for heat |
| Failure only | Force power-off and the recoveryOS restore in section 7 |
