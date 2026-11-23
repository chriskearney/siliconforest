<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Chris Kearney and the SiliconForest contributors -->

# G2 runbook: first RAM boot on the M1 MacBook Air (J313)

Written 22 November 2026 and updated 23 November for CHL-27, gate G2 of [`FIRST-INSTALL-J313.md`](FIRST-INSTALL-J313.md).

> **Status: all offline preparation is done, and G2 is waiting for Chris's approval (section 3).** Nothing in this runbook has run on
> the Air. It has not been rebooted or written to. SiliconForest has still never booted on J313.
>
> **The Air cannot reach an m1n1 USB proxy without a boot-chain write.** Every other route needs NVRAM or does not work. The smallest
> route is one temporary, reversible replacement of `m1n1/boot.bin` on the Air's ESP. With approval, it is one command (section 6).
>
> **Re-checked read-only on 23 November at 02:40 PST.** The Air is up on its normal Linux, with no restart since before the
> 22 November backup. Stage 2 is still `f5a82fdb-dirty`, `m1n1/boot.bin` still matches the pinned hash, no one-shot boot is pending,
> the default boot entry and partition table are unchanged, and no `boot.bin.pre-g2` exists. Of the 76 ESP files, only `limine.conf`
> and `limine_history/snapshots.json` differ, and both were rewritten by the Air's own hourly snapshot timer. The Linux root is
> still full (about 1.3 MB free). `g2.py plan` at `8341c4eab` passes 16 of 16 input checks.

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

**Nothing below may run until Chris gives this exact approval:**

> Chris approves the temporary J313 G2 ESP swap and RAM boot

`g2.py` refuses `go` and `rollback` without those exact words. The approval covers only this:

- **One temporary ESP change.** `m1n1/boot.bin` becomes the J313 window build, the original is kept beside it as
  `m1n1/boot.bin.pre-g2`, and afterwards the original is restored, verified and the copy deleted.
- **Up to three Air restarts:** one orderly reboot into the window, one M5 reset out of the RAM boot, and one orderly reboot to verify
  the restored stage 2.
- **One RAM boot** of the G1 collection, console only, for at most 420 seconds of capture.

It does not cover stage 1, the stub, NVRAM, boot policy, partitions, the Linux root, DFU, firmware flashing, or a change of default.

**What could go wrong:**

- **Linux might not boot through the window build.** It uses m1n1 `121fcbf`, not the `f5a82fdb` the Air runs today. The same code with
  J293's identity booted Linux on the Pro, but under the Pro's stage 1 v1.6.1. The Air's stage 1 is v1.5.2, and this pairing is
  untested. If it fails, **a person must restore the file from recoveryOS** (section 8).
- **The launcher path is new.** No renamed collection has been booted through the hypervisor launcher before. A failure here should
  end in the one M5 reset and a normal return to Linux.
- **Power loss during the rename** could leave the FAT directory needing repair. The kept copy stays on the ESP until the end.

## 4. What is ready (all offline)

Nothing here contacted the Air, the Pro, `macvdmtool` or the M3. Binaries, firmware and the packet are outside Git, in the builder's
private directory `~/chl27-g2`. Sources are in [`integrations/siliconforest/m1-j313-g2`](../../integrations/siliconforest/m1-j313-g2).

| Artifact | Bytes | SHA-256 |
|---|---|---|
| Window stage 2, code only | 4,325,376 | `a5bbd1430acc0fa0c44f9ff1ebed79f3ca5af12c0af7fee117d79f5df8b7c5e9` |
| **Window `boot.bin`** (code + the Air's payloads) | 10,238,674 | `c688793a85af45b1a71254798da10f56c4f861584b1dc1e606b559f964f5664c` |
| Original `boot.bin` (restored afterwards) | 10,107,602 | `54fa07e4f5cbeecd90e67e335657c40b33c25aede7015a84afb1427333b4f923` |
| G1 RAM-boot collection | 34,637,870 | `ef49aa0a376ed1b25054247e708467c020d5c8c95855186a166a5c8f616018c8` |
| RAM root (holds the Air's Wi-Fi firmware) | 402,653,184 | `41abdbdf18a411a6fd9e905d9e6171e1790347e2ffaecbe4487a8fb020a1f762` |
| Packet manifest | | `1804a1c447bd305bdef52a61fbdfd36147021ccaae648dc9dea7398a058eff21` |
| Generated launcher tree | 26 files | `c8fb1bea55748bca6418871d405979b416997d190db9dabdfb5a852f4bd8fcbf` |

[`g2-pins.json`](../../integrations/siliconforest/m1-j313-g2/g2-pins.json) holds these pins. The RAM root is not byte-reproducible, so
its pin binds this copy. If the packet is rebuilt, the pins must be reviewed again.

### The window build and how it differs

The build first rebuilds the Pro's J293 window as a control, which **reproduces it byte for byte** (`ba5bf4b3…`). It then applies
[`j313-window.patch`](../../integrations/siliconforest/m1-j313-g2/window/j313-window.patch). The receipt is
[`window-build-001.json`](../../integrations/siliconforest/m1-j313-g2/receipts/window-build-001.json).

| Compared with | Result |
|---|---|
| **The Air's current payloads** | **Byte-identical:** all 5,913,298 bytes (115 device trees and U-Boot) |
| **The Pro's J293 window** | Same layout and function addresses. The only logic change is two board-identity compares (J293 to J313). The version tag and one log line also change, which moves strings. The checker followed all 3,561 changed code references and 1,078 relocations to the same strings. Five deliberately altered images were all refused |
| **The Air's current stage 2 code** | **Not comparable.** The `f5a82fdb` source is not in this lab. It differs in size (4,194,304 and 4,325,376 bytes) and in 85 and 131 unique strings. This is the main reason a Linux boot through it is unproven on J313 |

Its window opens only for chip `0x8103` with board `J313`. On any other board it behaves as a plain loader. With no valid request in
10 seconds it continues to the same payloads.

### Install and restore

[`esp/j313_esp.py`](../../integrations/siliconforest/m1-j313-g2/esp/j313_esp.py) is a dry run by default and writes only `boot.bin`,
`boot.bin.pre-g2` and one temporary name in `m1n1/`.

- It refuses unless the machine is J313, the path is the FAT ESP this machine booted from, the current `boot.bin` is the original
  hash, and the candidate is the reviewed hash.
- Each write goes to a temporary file, is flushed and re-read from disk, then renamed over the target and verified again.
- `restore` verifies the kept copy first. `finalize` deletes the copy only after a reboot has really run on the original.

### The RAM boot

- The launcher is generated from the frozen J293 tree by exact replacements, which stop if the base changes. The base is not modified.
  The board checks remain and now require J313.
- **Boot arguments:**
  `-v -s debug=0x14e keepsyms=1 serial=3 serial-device-name=uart0 disable-uart-irq=1 cpus=1 rd=md0 serial_video_mirror=1 sftextboot=1
  sfm1kbd=1 sfm1trackpadenum=1 sfm1trackpadchild=1 sfsound=0 sftouchbar=0 sfm1tpmt=0 sfapciebridge=1`
- **Storage stays read-only because no driver can reach it.** The collection has no Apple NVMe driver. Its one NVMe family matches PCI
  storage only, which the Air's internal disk is not. `sfnvme*` arguments are refused, and the guest ends the session if anything
  attaches to the NVMe controller.
- **The first boot is console only:** one CPU, no GPU, display driver, compositor, sound or Touch Bar. The compositor that
  `tools/staged.sh` selects predates the rename and cannot use the renamed kernel's input path, so a desktop needs a separate packet.

### Offline results

| Check | Result |
|---|---|
| J313 window policy, under ASan and UBSan | Pass |
| ESP tool on a loopback FAT image of the backed-up ESP | **50 of 50**, including every refusal, `fsck`, and a final byte-identical ESP. The backup's `boot.bin` was unchanged |
| Sequence with a fake Air and M5 | **19 of 19**, including every failure path and "never a second reset" |
| Launcher input verification against the real packet | Pass, no device contact |
| `g2.py plan` | 16 of 16 input checks |

### Only a real boot can show

- Whether Linux boots through the window build under stage 1 v1.5.2.
- Whether this Thunderbolt cable and the Left-back port enumerate as USB CDC, and at the USB location the launcher accepts. If not, the
  M5 sees no proxy and the Air continues to Linux after 10 seconds.
- Everything listed under "Only a real boot can confirm" in [`FIRST-INSTALL-J313.md`](FIRST-INSTALL-J313.md).

The Air rewrites `limine.conf` by itself (it changed at 23:00 and 00:00 on 22 and 23 November), so `go` compares the **default boot
entry**, not the whole file. Nothing in `go` writes that file.

### M5 tooling

No installs are needed. On 22 November the M5 had `macvdmtool` with the pinned hash, `pyserial` 3.5, `construct` 2.10.70 and working
`sudo -n`. `g2.py` checks these again before it changes anything. The Air's cable stays in **USB-C Left-back** and M5 receptacle 1.

## 5. Bench hazard while the Air is connected

`macvdmtool` always uses the HPM with `RID=0`, and on this M5 that is **receptacle 1, now the Air**. Any Pro bench tool that issues its
recovery reset, including `tools/pcie_iterate.sh` and `tools/m1_return_linux.sh`, **would reset the Air instead of the Pro**.

Do not run Pro bench cycles while the Air is on receptacle 1. The go command holds `tools/bench.sh` for the whole session.

## 6. The go sequence

Run only after the approval in section 3, on the builder:

```sh
cd /home/chrisk/src/darwin-lab
git fetch origin main
G2_COMMIT=$(git log -1 --format=%H origin/main -- integrations/siliconforest/m1-j313-g2)
git worktree add --detach /tmp/chl27-g2-go "$G2_COMMIT"

# Offline. Read the plan; every check must pass.
python3 /tmp/chl27-g2-go/integrations/siliconforest/m1-j313-g2/g2.py plan

# The one command. Someone must be at the Air for G3 (section 7).
BENCH_WHO=CHL-27-G2 tools/bench.sh run python3 \
  /tmp/chl27-g2-go/integrations/siliconforest/m1-j313-g2/g2.py go \
  --approval "Chris approves the temporary J313 G2 ESP swap and RAM boot"

git worktree remove /tmp/chl27-g2-go
```

`go` performs these steps, and stops at the first failure:

1. Verifies every local hash.
2. Checks the Air read-only: J313, original stage 2, no one-shot boot pending.
3. Checks the M5 read-only: receptacle 1 is the Air, the `macvdmtool` pin, no latch, handoff or existing proxy.
4. Delivers the launcher and packet to the M5 and verifies them there. **Nothing on the Air has changed up to this point.**
5. Puts the window build in the Air's `/dev/shm` and installs it on the ESP, keeping the original.
6. Starts the M5 cycle, then reboots the Air.
7. The M5 claims the window, starts the RAM boot, captures the console, and issues at most one reset.
8. Waits for a new Linux boot on the window build, restores the original, and reboots once.
9. Verifies `f5a82fdb-dirty`, deletes the kept copy, confirms the default boot entry is unchanged, and clears the M5 latch.

The final status is `BOOT_OBSERVED_LINUX_RESTORED` or `NO_SHELL_LINUX_RESTORED`. The serial capture is private, in
`j313-g2-cycles` on the M5. A log of every command is in `~/chl27-g2/runs`.

## 7. What a person at the Air does (G3)

Sit at the Air before starting `go`, with the lid open and on power. Do not touch it during the first minutes. A host log cannot prove
the screen or physical input, so record what you see.

| When | What you see or do | Pass |
|---|---|---|
| After the first reboot | The screen may stay dark or show m1n1 for about 10 seconds, then scrolling kernel text | Text is readable and correctly placed on the **built-in panel** |
| `>>> TRACKPAD` appears | **Move a finger on the trackpad for 30 seconds.** No pointer appears in this console boot | The log line `G2_TRACKPAD bytes=` is above zero |
| `>>> KEYBOARD` appears | **Type `uname -a` and press Return** on the built-in keyboard | Your characters appear and it prints `Darwin … arm64` |
| Throughout | **Feel the keyboard deck and underside.** The Air has no fan | Warm is fine. If uncomfortably hot, hold the power button |
| Automatic | Wi-Fi scan, reported as a count only. It never joins | `G2_WIFI interface=en0` with `scan_lines` above 1 |
| About 7 minutes in | The Air restarts into Linux, and restarts once more | The normal Linux login returns |

This boot cannot judge brightness, the GPU, multitouch or sound. Those need later packets. Do not unplug the cable or power until `go`
has finished.

## 8. Abort and rollback

| Situation | Action |
|---|---|
| `go` stops before step 5 | Nothing on the Air changed. Fix the cause |
| `go` stops after step 5 and Linux is up | `go` restores the original itself. If it reports that it did not, run the rollback below |
| The Air is uncomfortably hot, or a person must stop the test | Hold the power button until it is off, press it to start Linux, then run the rollback |
| `go` says a worker may still own the proxy | **Do not reset the Air.** Review the cycle on the M5 |
| `go` prints `STOP. Linux did not come back` | **Do not reset again.** Use the recovery below |

**Rollback from Linux:**

```sh
python3 /tmp/chl27-g2-go/integrations/siliconforest/m1-j313-g2/g2.py rollback \
  --approval "Chris approves the temporary J313 G2 ESP swap and RAM boot"
```

It restores and verifies the original, reboots once, confirms `f5a82fdb-dirty`, and deletes the kept copy.

**Recovery if Linux does not boot (needs a person at the Air):**

1. Hold the power button until the Air is off.
2. Hold it again until "Loading startup options" appears. Choose **Options**, then **Utilities > Terminal**.
3. Run `diskutil list` and identify the Linux ESP (about 500 MB, FAT). **Do not assume its partition number.**
4. Mount it, copy `m1n1/boot.bin.pre-g2` over `m1n1/boot.bin`, and run `shasum -a 256` on it. It must begin `54fa07e4f5cbeecd`.
5. Restart. Do not run `bputil`, `csrutil` or any other policy command.

Then run the rollback above so the kept copy is verified and removed. An M5 latch may remain after a failed run: review that cycle
before any other bench work.

## 9. What a person must do

| When | Action |
|---|---|
| Before anything | **Chris gives the exact approval in section 3** |
| During `go` | **Be at the Air** for G3 (section 7) |
| Failure only | Force power-off and the recoveryOS restore in section 8 |

### Rebuilding the inputs

Only needed if a source changes. Each command refuses to overwrite its output, and any rebuilt hash needs a new review of `g2-pins.json`.

```sh
D=integrations/siliconforest/m1-j313-g2
python3 $D/window/build_window.py --source sources/m1n1-boot-window \
  --original <backup>/boot-efi/m1n1/boot.bin --out ~/chl27-g2/window-NNN
python3 $D/launcher/make_packet.py --kernel artifacts/j313-g1/kc-default-ram/kernel \
  --base-image artifacts/rebase/ramdisk-tip.img --base-packet artifacts/m1-desktop-010/apcie-port-candidate-003 \
  --firmware-tar <backup>/boot-efi/vendorfw/firmware.tar --ioreg <ioreg store path> \
  --stager integrations/siliconforest/m1-boot-speed/tools/stage_ramdisk_slim.py --out ~/chl27-g2/packet-NNN
python3 $D/launcher/make_lab.py --base runs/m1-desktop-010/pcie-m2-host-001/lab --out ~/chl27-g2/lab-NNN \
  --extra-bootargs "sfsound=0 sftouchbar=0 sfm1tpmt=0"
```
