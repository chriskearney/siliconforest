<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Chris Kearney and the SiliconForest contributors -->

# First real install: the M1 MacBook Air (J313)

Decided 22 November 2026. There is no spare 13-inch M1 MacBook Pro, and the development Pro's hand-made layout must not be the
installer's first target, so the **13-inch M1 MacBook Air (J313)** is the first real install target.

> **Status.** SiliconForest has never booted on J313. Nothing in this plan has run. The inventory below was read-only, and the board
> comparison used Apple's public 13.5 device trees, not a live boot.

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
| **Sound** | Codec on `i2c2`, four amplifiers | Codec on `i2c3`, two amplifiers. **`i2c2` carries the USB-C retimers at 0x18 and 0x19** | **Unsafe as it stands.** `SFAppleSound` checks only for T8103, so it would start on the Air and use J293's buses, amplifier list and speaker model. J313 boots **must** carry `sfsound=0` until it has its own configuration |
| **Touch Bar** | Present | Absent | `sftouchbar=0` |
| **Keyboard, trackpad** | SPI3 | Same controller and pins | `m1kbd_board.c` refuses by identity. With only the two identity strings substituted, the existing validator accepts every other J313 value. A small, reviewed change |
| **Display** | Panel maximum 525 | Panel maximum **420** | `dispdt.c` hard-codes J293's panel. It only warns on another board, so it would use the wrong brightness range. Must become per-board |
| **PCIe** | PERST 152, CLKREQ 150 | Same | No change expected |
| **Wi-Fi** | `apple,honshu` | `apple,shikoku` | The driver takes the board from the device tree. Firmware names are confirmed on the Air's Linux |
| **Fan** | Present | **None** | From source, the fan code writes nothing when the fan limits are unavailable. The temperature limits were chosen on a machine with a fan and need checking |
| **Storage** | ANS | ANS, tunables differ | No board gate found in the driver. The write fence stays unchanged, and a read-only boot comes first |
| **Boot chain** | m1n1 pack options | Same options assumed | Unverified until the first boot |

The J313 profile, [`installer/profiles/J313.json`](../../installer/profiles/J313.json), records all of this and stays at `development`.

## 3. Order of work

Each gate needs the previous one. Steps marked **Air** change or boot the Air and each need Chris's explicit go.

| Gate | Work | Touches the Air? |
|---|---|---|
| **G0** | Board-aware keyboard and display changes. Sound and Touch Bar off on J313. Host tests | No |
| **G1** | Build a J313 kernel collection | No |
| **G2** | RAM boot through m1n1 with **read-only storage**, returning to Linux | **Air**, needs a USB-C link to the M5 |
| **G3** | Display, keyboard, trackpad, Wi-Fi and thermal behaviour observed on the Air | **Air** |
| **G4** | Installer M1 to M3: simulator, dry run, Swift engine on disk images | No |
| **G5** | Boot macOS once. Read its version, used space and limits. Dry-run the real plan | **Air**, read-only |
| **G6** | Current backup confirmed, then the **first real install** and the full checklist in [`ENGINE.md`](ENGINE.md) section 11 | **Air** |
| **G7** | Decide whether to update the Air to macOS 27 and run spike S11 | **Air**, irreversible firmware update |

## 4. Rules for the Air

- Linux on the Air is an existing, working system. **Its stub, ESP and root are never modified**, and it is restored as the default after each test.
- Sound stays off on J313 until its speaker configuration exists. Do not reuse J293's speaker model.
- Physical addresses and board values come from J313's own device tree.
- No DFU, no `bputil -z`, no firmware flashing.
- Serial numbers, UUIDs, addresses and captures stay out of this repository.
