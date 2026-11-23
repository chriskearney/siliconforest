<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Chris Kearney and the SiliconForest contributors -->

# Adding a Mac to the SiliconForest Installer

Each Mac is one declarative profile plus evidence that it works. **No Mac becomes `supported` because a table entry was added.**

Status ladder, in the profile's `status` field:

| Status | Meaning | Who sees it |
|---|---|---|
| `refused` | Known, not installable, with a reason | Everyone: a clear refusal |
| `development` | Being brought up | Developer builds only |
| `preview` | Install and uninstall passed on real hardware | Users who opt in to the preview channel |
| `supported` | Every gate below passed | Everyone |

## 1. Identify the Mac

Read only, in macOS:

```sh
sysctl -n hw.targettype hw.model
ioreg -d2 -c IOPlatformExpertDevice -a     # compatible, board-id, chip-id
sw_vers
```

- [ ] Target type, model identifier, device class and SoC recorded
- [ ] Chip ID and board ID confirmed from Apple's `BuildManifest.plist`
- [ ] **No serial number, ECID, MAC address or user name written anywhere**

## 2. Choose the firmware

- [ ] Find the stub version: an entry in the Asahi installer's `IPSW_VERSIONS` that lists this device, or a new one
- [ ] Record restore image URL, size, build, `min_iboot`, `min_sfr` and identity (`ApBoardID`, `ApChipID`, `DeviceClass`)
- [ ] Decide the supported macOS range. The upper bound is the newest major **actually tested**
- [ ] Check open Asahi and Omacom issues for this model and add `quirks`

## 3. Bring the OS up on this board

This is the real work and lies outside the installer.

- [ ] Kernel collection builds for this SoC and board
- [ ] Device tree handling for this board
- [ ] Stage 1 and stage 2 built for it, and stage 2 within stage 1's size budget
- [ ] Native boot to a shell on real hardware
- [ ] **NVMe write fence proved** on this controller. It is the safety-gated code and changes only with the maintainer's agreement
- [ ] Display, keyboard, trackpad, Wi-Fi, and whatever else the profile lists, each observed on the machine
- [ ] Physical addresses taken from **this** board's device tree, never copied from a sibling
- [ ] Clean restart and halt

## 4. Write the profile

```sh
cp installer/profiles/J293.json installer/profiles/<BOARD>.json
```

- [ ] `identity`: all fields
- [ ] `host_macos`: allowed range and gated majors, each with its spike and reason
- [ ] `stub`: from step 2
- [ ] `boot`: stage limits, entry point, pack options
- [ ] `kernel`: collection recipe and boot-argument template
- [ ] `layout`: sizes and alignment
- [ ] `hardware`: panel, input, drivers
- [ ] `firmware`: every file the drivers load. **Names and sources only, never bytes**
- [ ] `quirks`: each with an ID, effect and source
- [ ] `support.evidence`: paths to reports in this repository
- [ ] `status`: start at `development`
- [ ] It validates against `device-profile.schema.json`

## 5. Firmware

- [ ] Every firmware file the kernel requests is listed. Compare against the driver source, not memory
- [ ] Extraction tested from Apple's image for this board
- [ ] The extracted set fits the firmware slot
- [ ] Machine-specific calibration, if any, comes only from the live Mac and stays on the Mac
- [ ] No firmware committed

## 6. Installer tests

No hardware needed:

- [ ] Record `diskutil` plists on this Mac, **scrub them**, add them as fixtures
- [ ] Classifier and sizing pass on the fixtures
- [ ] Add a scenario to the simulator
- [ ] Add this model's power-button instructions
- [ ] UI copy uses its marketing name

## 7. Real-hardware acceptance

**On a Mac whose owner has a current backup and can recover it. Never by DFU.**

Run the full checklist in [`ENGINE.md`](ENGINE.md) section 11:

- [ ] Install, recovery step, first start, **boot receipt read in macOS**
- [ ] Update
- [ ] Interrupted install recovered
- [ ] Forced failed first boot returns to macOS
- [ ] Remove restores the original partition table
- [ ] macOS verifies clean after each step
- [ ] Repeated on the **lowest and highest** macOS in the profile's range

Record the results in a report under `reports/`, with raw logs kept private. Set `status` to `preview`.

## 8. Promotion to supported

- [ ] One further install by **someone other than the person who did the bring-up**
- [ ] No open critical issue for this model
- [ ] `support.evidence` complete
- [ ] A signed release lists this board in `install.json`
- [ ] Status set to `supported` in a reviewed commit

## Sibling Macs

A shared SoC reduces the work but removes none of the gates. For example, the 13-inch MacBook Air (J313) shares T8103 with J293 but has a
different display, audio, power and thermal design, and no Touch Bar. [`FIRST-INSTALL-J313.md`](FIRST-INSTALL-J313.md) is the worked example: its sound hardware makes J293's driver unsafe there, even though both are T8103.
