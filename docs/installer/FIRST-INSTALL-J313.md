<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Chris Kearney and the SiliconForest contributors -->

# First real install: the M1 MacBook Air (J313)

Decided 22 November 2026. There is no spare 13-inch M1 MacBook Pro, and the development Pro's hand-made layout must not be the
installer's first target, so the **13-inch M1 MacBook Air (J313)** is the first real install target.

> **Status.** SiliconForest first booted on J313 on 24 November 2026, as a console-only RAM boot (G2). G0 and G1 are done (section 5). The inventory below was
> read-only, and the board comparison used Apple's public 13.5 device trees, not a live boot.

## 1. The Air today

Read-only from its running Linux on 22 November 2026.

| Item | Observed |
|---|---|
| Model | MacBook Air (M1, 2020), `apple,j313`, `apple,t8103` |
| System firmware | 14.6 as reported by m1n1 (`iBoot-10151.140.19`) |
| Existing OS | Arch Linux ARM with `linux-aurora`, on a 13.5 stub. **It is the default boot volume** |
| macOS | "Macintosh HD" is present. Its version and used space cannot be read from Linux |
| Disk | 251 GB |
| Free disk space | **None** beyond alignment gaps (under 0.5 MB) |
| macOS container | 157 GB, directly before the Linux stub |
| Linux | 2.5 GB stub, 524 MB ESP, 85 GB btrfs root |
| Linux root free space | **About 1.3 MB. It is full** |
| Linux references to partitions | By UUID, none by partition number, so new partitions cannot break them through renumbering |

Consequences:

- All of SiliconForest's space comes out of the **macOS container**. The Linux partitions are not touched.
- With today's fixed 7.3 GB install, macOS must use **no more than about 110 GB** so it can keep its 38 GB margin. This must be read in macOS first.
- New partitions land between macOS and the Linux stub, so removal can give the space straight back to macOS.
- The default boot volume is Linux, so the installer must **restore the previous default**, not assume macOS.
- The firmware is the 14.x family, so a pass here says nothing about the **macOS 27 resize** (spike S11).

## 2. What differs from J293

Compared from `DeviceTree.j293ap.im4p` and `DeviceTree.j313ap.im4p` in Apple's 13.5 restore image, the Linux device trees at
`linux-aurora` `6a08a08e`, and our driver source.

| Area | J293 | J313 | What it means |
|---|---|---|---|
| **Sound** | Codec on `i2c2`, four amplifiers | Codec on `i2c3`, two amplifiers. **`i2c2` carries the USB-C retimers at 0x18 and 0x19** | `SFAppleSound` now refuses every board but J293 before touching hardware. J313 boots **must** still carry `sfsound=0` until J313 has its own configuration |
| **Touch Bar** | Present | Absent | `SFAppleTouchBar` refuses every board but J293, and J313 boots carry `sftouchbar=0` |
| **Keyboard, trackpad** | SPI3, HID product `0x0341` | Same controller and pins, HID product **`0x0281`** in Linux | The guard accepts J313 by its own identity and product. The trackpad attaches only if its descriptor equals J293's, otherwise the driver runs keyboard-only |
| **Display** | Panel maximum 525 | Panel maximum **420** | `dispdt.c` selects the panel by board and refuses unknown boards |
| **PCIe** | PERST 152, CLKREQ 150 | Same | No change expected |
| **Wi-Fi** | `apple,honshu` | `apple,shikoku` | The driver takes the board from the device tree. Firmware names are confirmed on the Air's Linux |
| **Fan** | Present | **None** (`hwmon-fan.dtsi` is included only by J293) | From source, `thermalFan` writes nothing when `F0Mn` and `F0Mx` cannot be read. The 92 °C cap and 102 °C critical limits were chosen on a machine with a fan and must be checked in G3 |
| **Storage** | ANS | ANS, tunables differ | No board gate found in the driver. The write fence stays unchanged, and a read-only boot comes first |
| **Boot chain** | m1n1 pack options | Same options assumed | Unverified until the first boot |

The J313 profile, [`installer/profiles/J313.json`](../../installer/profiles/J313.json), records all of this and stays at `development`.

## 3. Order of work

Each gate needs the previous one. Steps marked **Air** change or boot the Air and each need Chris's explicit go.

| Gate | Work | Touches the Air? | Status |
|---|---|---|---|
| **G0** | Board-aware keyboard and display changes. Sound and Touch Bar off on J313. Host tests | No | **Done on the host**, `ae9fe1c71` |
| **G1** | Build a J313 kernel collection | No | **Built, not booted**, from `ae9fe1c71` |
| **G2** | RAM boot through m1n1 with **read-only storage**, returning to Linux | **Air**, needs a USB-C link to the M5 | **Passed 24 Nov 2026**: `BOOT_OBSERVED_LINUX_RESTORED`. See [`G2-RUNBOOK-J313.md`](G2-RUNBOOK-J313.md) |
| **G3** | Display, keyboard, trackpad, Wi-Fi and thermal behaviour observed on the Air | **Air** | Log-only part done in G2 (no one at the Air). A person is still needed |
| **G4** | Installer M1 to M3: simulator, dry run, Swift engine on disk images | No | Not recorded here |
| **G5** | Boot macOS once. Read its version, used space and limits. Dry-run the real plan | **Air**, read-only | Not run |
| **G6** | Current backup confirmed, then the **first real install** and the full checklist in [`ENGINE.md`](ENGINE.md) section 11 | **Air** | Not run |
| **G7** | Decide whether to update the Air to macOS 27 and run spike S11 | **Air**, irreversible firmware update | Not run |

## 4. Rules for the Air

- Linux on the Air is an existing, working system. **Its stub, ESP and root are never modified**, and it is restored as the default after each test.
- Sound stays off on J313 until its speaker configuration exists. Do not reuse J293's speaker model.
- Physical addresses and board values come from J313's own device tree.
- No DFU, no `bputil -z`, no firmware flashing.
- Serial numbers, UUIDs, addresses and captures stay out of this repository.

## 5. G0 and G1 results

Everything here ran on the build host. **Neither collection has booted on any machine.**

### G0

- The current SPI HID build uses board-aware copies of the keyboard guard, transport check and metadata check, in
  `m1-trackpad-child/multitouch`. The originals in `m1-keyboard` are unchanged because frozen recipes pin their hashes.
- The new guard matches the frozen guard on the J293 test table under every dropped, shortened, lengthened and altered property. It
  accepts Apple's public 13.5 J293 and J313 device trees and a saved real J293 tree.
- For J293, the display tree still matches the saved Linux ground truth. The J293 and J313 trees differ only in the panel's
  `compatible` and `apple,max-brightness`.
- `python3 tools/check.py --sanitize --cross` passes with 301 Python tests and 77 C groups. It needs the ignored `artifacts` and
  `sources` directories. The other required repository checks also pass.
- Three checks fail identically without this change: one `test_firstboot.py` staging test, `verify_source.py` for the trackpad child,
  and `tools/sf_rename.py check` (246 names in 13 files, none of them changed here).

### G1

Both collections are built from `ae9fe1c71` on the builder, with `SF_PD` unset. The board is chosen at run time, so the J313 difference
is in the sources above and the boot arguments.

```sh
nix-build --extra-experimental-features 'nix-command flakes' integrations/siliconforest/rebase/build-kc.nix \
  --out-link artifacts/j313-g1/kc-default-ram
nix-build --extra-experimental-features 'nix-command flakes' integrations/siliconforest/m1-storage/build-kc-native-rw-halt.nix \
  --out-link artifacts/j313-g1/kc
```

| Use | Path (ignored by Git) | Bytes | SHA-256 |
|---|---|---|---|
| **G2 RAM boot.** No NVMe driver | `artifacts/j313-g1/kc-default-ram/kernel` | 34,637,870 | `ff0238cc345bbf33e90c39e7a909eef002c85113394b67fb5137d4857499812c` |
| **Installed system only (G6).** Contains `SFAppleNVMeRW`. Never use it for G2 | `artifacts/j313-g1/kc/kernel` | 33,842,862 | `b3115d93b1932c3ef86d2ca39bf638ddddb29872421c297ced960f7f653a6a99` |

Both builds passed the collection overlap check (19 segments, no overlaps).

### Only a real boot can confirm

- **Keyboard product ID.** `0x0281` comes from Linux. If the Air reports another value, the driver stops at `device-metadata` and there
  is no built-in keyboard.
- **Trackpad.** J313's descriptor has not been captured. If it differs from J293's, the driver runs keyboard-only. Multitouch is on by
  default, so G2 must pass `sfm1tpmt=0`.
- **Display.** The carve-outs are filled in by iBoot and are absent from the public trees. The brightness range needs a real panel.
- **Wi-Fi.** The `apple,shikoku` firmware has not been loaded by the Darwin driver.
- **Thermal.** Sustained temperatures with no fan, against the 92 °C and 102 °C limits.
- **Names.** Some J313 logs and the HID product strings still say "J293". This is cosmetic.

## 6. Preview5: running the first real install (`sfinstrun`)

Chris waived the stub-only Air run on 25 November 2026 (the stage 1 file is the same byte-for-byte). Preview5 is a **real-disk** prerelease and has **not** been run on a real Mac. **Back up first.** Nothing in this section has been run on the Air.

The installer app UI is still a flow preview. The first real install is the lab tool `sfinstrun` (in the DMG, `Lab tools/sfinstrun`), built with `SF_REAL_DISK_WRITES`. It never writes the authorization file, never runs `bless` / `bputil` / `kmutil` / DFU, and refuses before any change without the compile key, root, a verified signed release, and Chris's authorization for this plan and disk.

**Preconditions** (same spirit as [STUB-ONLY-RUN-J313.md](STUB-ONLY-RUN-J313.md) §1): Omarchy / the Linux stub already removed by Chris if that is the plan, macOS grown back, `diskutil list internal` recorded off the repository, macOS 13.5 or newer, Time Machine or other backup **confirmed by Chris**, on power, battery above 50%, Wi-Fi on. A person at the Air.

1. Copy the signed payload (every file listed in `SHA256SUMS`, plus `SHA256SUMS` and `SHA256SUMS.sig`) to `~/sf-run/rel/` on the Air. In a directory that contains **only** those files, run `python3 verify_release.py ~/sf-run/rel --allowed-signers allowed_signers` (the `allowed_signers` file is also in the DMG). Confirm `sf-stage1.bin` is `44c1ef0b…`.
2. Copy `sfinstrun`, `allowed_signers`, the signed `SFRecovery` (`SiliconForest Installer.app/Contents/Helpers/SFRecovery`) and `AppIcon.icns` off the DMG. Copy macOS's own `AdminUserRecoveryInfo.plist` from the Preboot volume group.
3. `DISK=` the internal disk's `DiskUUID` from `diskutil info -plist disk0`.
   `R="--release-dir ~/sf-run/rel"`, `J="--journal /var/db/org.siliconforest.installer/journal --work /var/db/org.siliconforest.installer/work"`,
   `A="--icon <AppIcon.icns> --admin-users <AdminUserRecoveryInfo.plist> --recovery-binary <signed SFRecovery>"`.
4. **Plan (read-only):** `sfinstrun plan --target disk:$DISK $R --out ~/sf-run/plan.json` (add `--size 80G` or similar; the default is the profile's recommended footprint). It verifies the signed release, prints the plan digest, the macOS shrink, the new stub / boot / root partitions, and the authorization JSON. `diskutil list` is unchanged.
5. Chris checks the plan, writes the authorization (root-owned, 0600, `RealDiskGate.authorizationPath`, at most 2 hours, this digest and this disk UUID) and records his approval words.
6. **Dry check of the gate:** the same `sudo sfinstrun run --target disk:$DISK $R $J $A --plan ~/sf-run/plan.json` **without** the file, or with another digest, must be refused (`the real-disk gate is closed`); the journal shows no changes.
7. **Install:** the same command with the file in place. On a stop: fix the cause, then the same command with `--job <id>` resumes; `sfinstrun rollback … --job <id>` undoes everything it can. S65's `bless` is simulated; Chris runs the printed `bless` himself.
8. **Remove:** `sudo sfinstrun remove --target disk:$DISK $J --job <id>` prints a new plan and a new authorization JSON; Chris writes a new file for that digest, then the same command runs U10–U40.

The 13.5 restore-image members and the Wi-Fi firmware the installer extracts are read at run time from Apple's CDN / this Mac, never from the release.
