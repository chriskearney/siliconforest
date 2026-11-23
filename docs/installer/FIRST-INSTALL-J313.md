<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Chris Kearney and the SiliconForest contributors -->

# First real install: the M1 MacBook Air (J313)

Decided 22 November 2026. There is no spare 13-inch M1 MacBook Pro, and the development Pro's hand-made layout must not be the
installer's first target, so the **13-inch M1 MacBook Air (J313)** is the first real install target.

> **Status.** SiliconForest has never booted on J313. G0 and G1 are done on the build host only (section 5). The inventory below was
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
| **G2** | RAM boot through m1n1 with **read-only storage**, returning to Linux | **Air**, needs a USB-C link to the M5 | Not run. See [`G2-RUNBOOK-J313.md`](G2-RUNBOOK-J313.md) |
| **G3** | Display, keyboard, trackpad, Wi-Fi and thermal behaviour observed on the Air | **Air** | Not run |
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
| **G2 RAM boot.** No NVMe driver | `artifacts/j313-g1/kc-default-ram/kernel` | 34,637,870 | `ef49aa0a376ed1b25054247e708467c020d5c8c95855186a166a5c8f616018c8` |
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
