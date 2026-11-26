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

> **Superseded by preview6 (section 7). Do not use preview5 for a real install:** its engine stops at S42 on the shipped
> `bootargs.template` (comment lines and `@SF_PART_BLOCKS@` were not handled) and at S50 (format 3 ships no firmware
> file). Both were found by the preview6 app run on a disk image and are fixed there. Stopping at S42 leaves the new
> partitions written; `sfinstrun rollback` undoes them.

Chris waived the stub-only Air run on 25 November 2026 (the stage 1 file is the same byte-for-byte). Preview5 is a **real-disk** prerelease and has **not** been run on a real Mac. **Back up first.** Nothing in this section has been run on the Air.

The installer app UI is still a flow preview. The first real install is the lab tool `sfinstrun` (in the DMG, `Lab tools/sfinstrun`), built with `SF_REAL_DISK_WRITES`. It never writes the authorization file, never runs `bless` / `bputil` / `kmutil` / DFU, and refuses before any change without the compile key, root, a verified signed release, and Chris's authorization for this plan and disk.

**Preconditions** (same spirit as [STUB-ONLY-RUN-J313.md](STUB-ONLY-RUN-J313.md) §1): Omarchy / the Linux stub already removed by Chris if that is the plan, macOS grown back, `diskutil list internal` recorded off the repository, macOS 13.5 or newer, Time Machine or other backup **confirmed by Chris**, on power, battery above 50%, Wi-Fi on. A person at the Air.

1. Copy the signed payload (every file listed in `SHA256SUMS`, plus `SHA256SUMS` and `SHA256SUMS.sig`) to `~/sf-run/rel/` on the Air. In a directory that contains **only** those files, run `python3 verify_release.py ~/sf-run/rel --allowed-signers allowed_signers` (the `allowed_signers` file is also in the DMG). Confirm `sf-stage1.bin` is `c4be3087…` (stage 1 v2; preview6 and earlier shipped v1 `44c1ef0b…`).
2. Copy `sfinstrun`, `allowed_signers`, the signed `SFRecovery` (`SiliconForest Installer.app/Contents/Helpers/SFRecovery`) and `AppIcon.icns` off the DMG. Copy macOS's own `AdminUserRecoveryInfo.plist` from the Preboot volume group.
3. `DISK=` the internal disk's GPT disk GUID: `sudo sfinstrun startup-disk` (preview6 and later; read-only). `diskutil info -plist disk0` has no `DiskUUID` for a whole disk, so preview5's instruction here could not be followed.
   `R="--release-dir ~/sf-run/rel"`, `J="--journal /var/db/org.siliconforest.installer/journal --work /var/db/org.siliconforest.installer/work"`,
   `A="--icon <AppIcon.icns> --admin-users <AdminUserRecoveryInfo.plist> --recovery-binary <signed SFRecovery>"`.
4. **Plan (read-only):** `sfinstrun plan --target disk:$DISK $R --out ~/sf-run/plan.json` (add `--size 80G` or similar; the default is the profile's recommended footprint). It verifies the signed release, prints the plan digest, the macOS shrink, the new stub / boot / root partitions, and the authorization JSON. `diskutil list` is unchanged.
5. Chris checks the plan, writes the authorization (root-owned, 0600, `RealDiskGate.authorizationPath`, at most 2 hours, this digest and this disk UUID) and records his approval words.
6. **Dry check of the gate:** the same `sudo sfinstrun run --target disk:$DISK $R $J $A --plan ~/sf-run/plan.json` **without** the file, or with another digest, must be refused (`the real-disk gate is closed`); the journal shows no changes.
7. **Install:** the same command with the file in place. On a stop: fix the cause, then the same command with `--job <id>` resumes; `sfinstrun rollback … --job <id>` undoes everything it can. S65's `bless` is simulated; Chris runs the printed `bless` himself.
8. **Remove:** `sudo sfinstrun remove --target disk:$DISK $J --job <id>` prints a new plan and a new authorization JSON; Chris writes a new file for that digest, then the same command runs U10–U40.

The 13.5 restore-image members and the Wi-Fi firmware the installer extracts are read at run time from Apple's CDN / this Mac, never from the release.

## 7. Preview6/7: the app does the install, sets the one-time boot, and can remove it

**What preview7's payload adds for the SAP hardware test** (docs/sap/IMAGE.md): the root is built with SAP baked in
(`build_darwin.sh` with `SAP_KC_BUILDER=1`, then `prepare_root.py --sap-bin … --sap-channel … --sap-manifest-url …`: `sap`, `sf`,
`sf-bootslot`, `sf-mount-sfboot`, `kc-builder`, the two launchd jobs, `/etc/sap.conf`, and the database seeded from the image's own
channel); **stage 1 is v2** (`abboot/build_stage1_v2.sh`, A/B try-once slots, `c4be3087…`); the release carries `boot-b.bin` (slot B's
stage 2, written to `sf/b/boot.bin`; built by `installer/payload/boot/build_stage2.sh`), `bootstate.bin` (slot A as installed, good)
and `sf-trust.txt` (the release key as SAP's trust anchor, written to `sf/trust` and, when it fits, into the boot arguments).
The channel's `manifest.json` is signed on the M3 with `SHA256SUMS`. Installing a new stage 1 is the same recovery-mode step as
before (SiliconForest Setup writes the stub's boot object).

Preview6's app performs the real install itself (preview7 adds the steps marked below), through its privileged helper (an `SMAppService` daemon). Built with
`SF_REAL_DISK_WRITES`. **Back up first. Not yet run on a real Mac.** The preconditions of section 6 still apply.

1. Open the DMG, drag **SiliconForest Installer** to `/Applications`, open it from there. Approve its helper when macOS asks
   (System Settings › General › Login Items › Allow in the Background: "SiliconForest Installer").
2. **Checks** (read-only): model J313, macOS, FileVault **off**, power and battery, free space. Any failure stops here.
3. **Size and Review**: choose the size; Review shows what macOS gives up and what is created. "Continue".
4. **Fetching the release**: the app downloads this version's signed payload from the GitHub release (or "Use a Folder…"
   with a local copy) into `~/Library/Caches/org.siliconforest.installer/releases`, checks every file against
   `SHA256SUMS`, and `SHA256SUMS.sig` against the bundled `allowed_signers`. The helper copies it into its root-only store
   (`/var/db/org.siliconforest.installer/releases`) and verifies it again there, and refuses any stage 1 but v2 `c4be3087…` (preview7; v1 `44c1ef0b…` of previews 1–6 is refused).
5. **Confirm**: the helper reads the disk and makes the plan. The screen shows the exact plan and asks you to type
   the macOS volume's name (for example `Macintosh HD`) and the erase phrase (`ERASE <N> GB`, N = what macOS gives up,
   rounded up). "Install" is enabled only when both match exactly. Then macOS asks for an administrator's password.
6. The helper checks that approval, that the plan's disk is this Mac's startup disk, and writes
   `/var/db/org.siliconforest.installer/real-disk-authorization.json` (root, 0600) for this plan digest and disk UUID,
   valid for 2 hours at most. Then the install runs: **Installing** shows elapsed time, overall percentage, each step with
   its time, the macOS resize's live `diskutil` status (S25), bytes written and read back for the root (S47), and the journal.
7. If the app is quit, the helper continues. If the Mac or the helper stops, open the app again: it finds the unfinished job
   and offers **Continue** (asking you to confirm again if the 2 hours have passed) or **Undo Everything**.
8. **Size** (Space screen): SiliconForest's size is what macOS gives up, in whole GB. The minimum is the stub (2.5 GB) +
   boot (0.5 GB) + the root the release needs; the maximum is what macOS can give while keeping what it uses plus the
   profile's free-space reserve, the downloads and a drift margin (and never more than the root's 2,080 GiB growth cap);
   the default is the profile's recommended root (or a fraction of the disk), clamped into that range. The helper plans
   from its own read of the disk and refuses any size outside the range, so the screen cannot ask for more than fits.
   macOS is shrunk to exactly what is left (S25); nothing is formatted or moved.
9. **Finish** (preview7; **changed in preview13**, see "Preview13: persistent startup disk" below): after S60/S68 hand off, S65
   runs, inside the same confirmed job and the same administrator approval,
   `/usr/sbin/bless --mount "/Volumes/<name>" --setBoot [--user <owner> --stdinpass]`: a **persistent** selection of the stub
   (no `--nextonly`). The helper runs it (as root, no shell) only if the mount point is the System volume of the stub container
   **this plan created** on this Mac's startup disk. It checks the exit code and then reads `bless --getBoot`. The finish screen
   shows **Shut Down** (the helper runs `shutdown -h now`, only for a finished, not-removed install, for a day after it
   finished) and the steps: hold the power button until "Loading startup options", choose SiliconForest, **not Options**.
   SiliconForest Setup then finishes in the stub's own recoveryOS (it asks for your password; `bputil`, `kmutil configure-boot`)
   and starts SiliconForest. If `bless` fails, the install is **not** failed: the screen shows the manual command
   (`sudo /usr/sbin/bless --mount "/Volumes/<name>" --setBoot`, with "Copy the bless command") and the startup-menu steps.
10. **Remove SiliconForest** (preview7; Welcome, or the "already installed" Check screen, then "Remove SiliconForest…"):
    the app lists the installs the helper's own journals prove (finished, not already removed), shows what will be deleted
    (the stub, its boot partition and the root partition, and the recovery setup the install added with the stub), and
    asks for the same confirmation: type the macOS volume's name and `REMOVE SILICONFOREST`, then the macOS administrator
    prompt. The helper acts only on partitions whose UUIDs the install journal recorded, that are still on this Mac's startup
    disk, right after the macOS container in the installer's order. Steps: **U10** reads the startup selection and, only if
    it names SiliconForest, sets macOS back (`bless --mount <macOS System volume> --setBoot`; a selection that points elsewhere
    is left alone); **U20** deletes the partitions; **U30** grows macOS back into the freed space; **U40** checks the partition
    table against the one saved before the install. Same progress screen and resume (a stopped removal continues from its journal).
    `sfinstrun remove` does the same from Terminal (with `bless` simulated, as in every lab tool). The GPL resize tool is not involved.

No Wi-Fi firmware is extracted yet: the firmware slot is written empty, so Wi-Fi stays off in SiliconForest. The lab tool
`sfinstrun` (section 6) still works with a hand-written authorization file.

Tested before the cut on the M5, against a **disk image** only, through the app's own code path (`sfappimage`: the
helper's verbs over XPC, the app's `LiveInstallController`, the live backend): typed-confirmation and begin refusals; a
full install from the published preview5 payload; a `kill -9` of helper and controller in the middle of S47's root write
and again in S60, each resumed to "handed-off". Preview7 adds, on a disk image
with `bless` and the restart replaced by recorders (the lab tool `sfappimage` never runs either): the one-time bless arguments
and the `--getBoot` read-back, the bless-failure fallback, the restart verb, and a full install then Remove SiliconForest
(layout digest and macOS size identical to before the install). Not tested: the real administrator prompt, `SMAppService`
registration, the startup-disk lookup and the Preboot admin list on real hardware, what `bless --nextonly` does on Apple
silicon with this stub (whether `--getBoot` reports it, whether the restart lands in SiliconForest Setup), the real restart,
and any real disk.

## Preview8: the same install, easier to read and use (UI only)

Chris tried preview7 on the Air and it stopped at the preflight screen "Not enough free space" (correct: the install needs 19 GB and macOS keeps 38 GB).
Preview8 changes the app's look and its buttons, not the engine, the payload or the free-space rule:

- The **"REAL INSTALL · Writes to this Mac's disk · back up first" pill is gone** from the top bar. The back-up warning stays in the flow text (Before you begin, Confirm the change, Remove SiliconForest).
- A **reading panel** (a soft translucent card under the content column, on every screen) and lighter secondary text and stronger hairlines in the dark theme (darker in the light theme) keep the text readable over the forest. The forest still shows around and faintly through the panel.
- **Every control that does something looks like a button**: filled primary, bordered secondary, a smaller bordered "quiet" button for Details and What is SiliconForest?, a destructive button, and bordered disclosure buttons ("About security", "Show partition details"). All have hover and pressed states and a dimmed disabled look.
- **"Open Storage Settings" works** (`SystemLinks`): it opens `x-apple.systempreferences:com.apple.settings.Storage`, then the General pane, then the System Settings app. "Open Software Update", "Open Disk Utility" and "See Supported Macs" / "Learn More" open their places too. A check-screen button with nothing behind it is not shown in the real install (it was an empty button in preview7).

## Preview10: permissions first, and no silent failures

Preview9 on Connor's Air (macOS 27.2.1) went wrong in two ways. The app reopened System Settings → Login Items about every 2 s while the helper waited for approval, which pulled it out of full screen. Then the helper's plan read the GPT header from `/dev/rdisk0` (a whole disk has no DiskUUID in `diskutil`, and IOMedia doesn't publish one either, as the M5 shows). macOS denied that read: tccd refused kTCCServiceSystemPolicyAllFiles to `org.siliconforest.installer.helper`, because even root needs Full Disk Access for a raw device. Nothing was logged and nothing was shown. The disk was untouched.

Preview10 changes the following:

- **A Privileges screen comes before anything else.** Get Started (and Remove SiliconForest…) leads to "Permissions first", before the checks, any download or any disk work. `PrivilegeGate` (SFAppEngine) checks two things:
  - **The helper's approval** (SMAppService). It registers the helper once, on the person's click. If macOS wants approval, the screen shows "Waiting for approval…".
  - **The helper's Full Disk Access**, through a new verb, `checkPrivileges`. The helper opens the startup disk's raw device read-only and closes it at once. If it can't name the startup disk, it opens `/Library/Application Support/com.apple.TCC/TCC.db` read-only instead. It never reads or writes.
- **System Settings opens only on a click, once per click.** "Open Login Items" calls `SMAppService.openSystemSettingsLoginItems()`. "Open Full Disk Access Settings" opens `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`. Between clicks the screen checks quietly every 2 s: it reads `SMAppService.status` and runs the helper's probe. It never registers again and never opens anything. It continues by itself once everything is in place. A Check Again button is there as well. The app no longer registers the helper at launch; it only reads the status.
- **The Full Disk Access instructions**: turn on SFHelper. If SFHelper isn't in the list, click +, press ⌘⇧G and paste `/Applications/SiliconForest Installer.app/Contents/MacOS/SFHelper`.
- **Raw-device access is typed.** Every raw open in the helper goes through `RawAccess.open`. EPERM or EACCES as root becomes `FullDiskAccessDenied`, which the helper returns as `HelperErrorCode.needsFullDiskAccess`. Three places do raw I/O:
  - `GPTHeader.diskGUID`: a two-block read for the disk identity.
  - `LiveChokepoint.openRaw`: partition reads and writes inside the protection receipt.
  - `newfs_msdos` on `/dev/r<partition>`: a child of the helper, covered by the same grant.

  Each runs only after `requireFullDiskAccess()`, which `readTarget` and `backend` call on the internal disk. If a denial still happens, the app goes back to the Privileges screen. The whole-disk GPT read stays: no non-raw source of the whole disk's GUID exists, and the install writes raw partitions anyway.
- **Logs:**
  - The app logs to `~/Library/Logs/SiliconForest Installer/installer.log`.
  - The helper logs to `/Library/Logs/SiliconForest/helper.log`.
  - Both also go to the unified log under subsystem `org.siliconforest.installer` (`log show --predicate 'subsystem == "org.siliconforest.installer"' --last 1h`).
  - What's logged: privilege states, each helper verb's result, job steps and ends, and every error with its underlying cause. Passwords, authorizations and tokens are never logged; values after such keys are redacted.
  - Every live error box shows the error, both log paths, Show Log and Show Helper Log.
- **Unchanged from preview9:** macOS 27 passes (a note in Details), and the battery blocks only when the Mac is unplugged at 50% or lower.

Not verified on hardware yet: the TCC prompts and Full Disk Access list on macOS 27, and whether a helper that is already running sees a new grant without restarting. The helper exits when idle, and launchd starts a fresh one for the next check.

## Preview11: plainer copy (text only)

Preview11 makes no change to behaviour from preview10. It rewrites user-visible text that read like a brochure: short, plain, standard installer wording. For example, the Welcome lead "A new operating system for your Mac, right beside macOS." becomes "A Darwin-based system that boots next to macOS.". The back-up warning, the "not yet run on a real Mac" warning and the macOS 27 note in Details all stay. No identifiers, log lines or URLs changed. The changed strings are in `SFCopy/Copy.swift`, `SFInstaller/LiveScreens.swift` and `SFInstaller/PrivilegeScreens.swift`.

## Preview12: Welcome lead, and a leftover helper is restarted

The Welcome lead is now "Built on Darwin and XNU. Runs Mac apps." (it was "A Darwin-based system that boots next to macOS.").

Preview11 on Connor's Air talked to a preview9 helper that was still running, from the previous app in the Trash. That helper does not know the `checkPrivileges` verb added in preview10, so it dropped the call and the app showed "The installer's helper didn't answer: Couldn't communicate with a helper application." The Permissions row with the X was not a button, and the failed footer had only Check Again, which tried the same leftover helper again.

Preview12 changes the following:

- **The failed Permissions footer keeps Open Login Items**, and also shows Open Full Disk Access Settings when the failure is about Full Disk Access.
- **The helper and Full Disk Access rows are buttons** (a chevron and a pointer cursor) that open the matching System Settings pane. The "Waiting for approval…" help is shown for a failed helper check too. The helper row shows a spinner while it waits for approval, not an X.
- **If this app version or build is not the one that last registered the helper**, and the helper is already enabled, the app unregisters, registers and reconnects. The registered build is stored in UserDefaults (`org.siliconforest.installer.registeredHelperBuild`).
- **If a privilege probe fails** because the connection was invalidated or the helper does not know the verb, and the helper is enabled, the app does that re-register once and retries, and shows "Restarting the installer's helper…".
- **SFHelper reports its real `CFBundleVersion` as `helperBuild`**, and requires the same minimum client build, so a leftover helper is detectable.
- Unchanged from preview11: macOS 27 passes (a note in Details), the battery blocks only when the Mac is unplugged at 50% or lower, and System Settings still opens only on a click.

## Preview13 (on main, not yet released)

- **Every permission row opens its System Settings pane.** The helper row opens General → Login Items & Extensions (`SMAppService.openSystemSettingsLoginItems()`; "Allow in the Background" is the section below "Open at Login"). The Full Disk Access row is a button whenever it is not passing, and opens Privacy & Security → Full Disk Access with `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles`, then the older `com.apple.preference.security?Privacy_AllFiles`, then the System Settings app. **Limit:** macOS has no URL that adds, selects or switches on an app in that list. So the click also shows SFHelper in a Finder window (drag it into the list), and the screen has "Show SFHelper in Finder" and "Copy SFHelper path" (for + then ⌘⇧G).
- **The download row no longer flickers.** The file total is the length of SHA256SUMS and never changes; the count never goes back. Until the total is known the row says "Downloading…" with the bytes received (a spinner, no counts); after that it says "N of M files" with a bar, and "Verifying…" at the end. Updates are limited to about four a second, and bytes are reported while the large root image downloads.
- **The Confirm screens are short.** "What will change", then one block per partition (macOS: "Shrinks from 245 GB to 196 GB. Your files stay."; SiliconForest boot: "New, 2.5 GB."; removal: "Grows back from … to …" and "Deleted."), then "Back up your Mac first. This changes your disk.", then the release, signature and plan as a quiet footnote.
- **One typed confirmation.** The person types the name of the macOS volume (case and extra spaces do not matter). A green check appears when it matches and the button reads "Erase N GB and Install" (removal: "Remove SiliconForest"). The administrator dialog is still the second step. The erase phrase is gone from the app and from `TypedConfirmation`; the helper still derives the volume name from its own plan and disk read and refuses anything else. A preview12 app that still sends a phrase is accepted (the phrase is ignored). The build number is stamped by CI, and the helper requires a client build at least its own, so an older app cannot talk to a newer helper.
- **The Install button follows what you type.** `Session.live` is not `@Published`, so the footer didn't redraw on each keystroke and the button stayed dead. `Session` now forwards `LiveRun.objectWillChange` to its own, so every change redraws the footer.
- **The "macOS is still working on this…" notice sits under the progress.** Same words, caption size, secondary colour, a small info icon, no box. It only shows for the shrink step (S25, `diskutil`) and sits in a fixed-height block that fades, so nothing moves. It never shows during the release download.
- **The step list follows the step in progress.** Auto-follow rule (`ScrollFollow`): scroll to the active row (animated, at most four times a second) only when the active row changes. If the person scrolls so that the active row leaves the screen (and it isn't our own scroll settling), following pauses. It resumes when the active row is on screen again or when a new step starts.

### Preview13: setting the startup disk on Apple Silicon (owner authentication)

`bless --mount <stub> --setBoot --nextonly` run by the root helper failed with "owner authentication required" (S65). The same command with `sudo` from a logged-in volume owner works. Preview13 gives the helper that owner's login:

- **Which account.** The helper reads who can unlock macOS's System volume, read-only: `diskutil apfs listUsers / -plist` (users with `VolumeOwner`, local accounts only) mapped to short names with `dscl . -list /Users GeneratedUID`. The person at the keyboard is the default when they are an owner. The helper refuses a login for any other name.
- **Where it is typed.** Optional, on the Confirm screen ("Start SiliconForest next time": "To set your Mac to start SiliconForest, macOS needs the login password of a user who can unlock Macintosh HD. This is your Mac login password."), or on the finish screen with the **Set Startup Disk** button if the first try didn't work or no password was given. The words are "your Mac login password", never "root".
- **How it is used.** `authorizeBless(job:owner:password:)` (before the job starts) puts the password in locked memory (`SecureBytes`). S65 takes it once and runs `bless --mount /Volumes/<stub> --setBoot --nextonly --user <owner> --stdinpass`, sending the password only on bless's stdin (`StdinFeed`), then wipes it. `BlessGuard.isAllowed` accepts the two new flags only in exactly that shape. The password is never an argument, never in installer.log, helper.log or the journal; bless's output is scrubbed of it before it is journaled. If the helper exits before S65 (it idles out), the password is gone and the finish screen's button asks again. A login held for more than three hours is dropped.
- **If it fails.** The install stays successful. The journal's S65 evidence and helper.log carry bless's full output (up to 1.5 KB), the exit status and the account name. The app logs the error domain and code. **Set Startup Disk** (`retryStartupSelection`) runs only the bless again with a fresh login. The manual `sudo /usr/sbin/bless …` command and the Copy button stay.
- **Fallback if owner authentication still fails from the daemon.** Run bless in the person's own session instead of in the root daemon: the app, which already holds the administrator authorization (`AdminAuthorization`), would run `/usr/sbin/bless --mount "/Volumes/<stub>" --setBoot --nextonly` through that authorization (an `osascript … with administrator privileges` or `AuthorizationExecuteWithPrivileges` call from the user session). That is the same security context as the `sudo` that worked by hand. It is not built in preview13; it needs a new, narrowly guarded app-side runner.
- **Versions.** The new verbs (`authorizeBless` with an owner, `startupOwners`, `retryStartupSelection`) are unknown to an older helper, which drops them; the app treats that as a stale helper and the login step as non-fatal. The CI build number is `CFBundleVersion`, which is the helper's `helperBuild` and its `minimumClientBuild`, so it rises with each release build.

### Preview13: persistent startup disk, macOS Recovery vs SiliconForest's, owners, and the helper registration bug

**Why S65 changed.** On the Air the person ended up in macOS's own paired 1TR (the **Options** entry). There the stub is only
mounted at `/Volumes/SiliconForest`, and `.IAPhysicalMedia` is never read, so SiliconForest Setup never launched. And
`bless --setBoot --nextonly` on the stub's System volume is a one-shot *OS* boot of the stub, whose `SystemVersion.plist` is hidden
at S68, so the Mac falls back to macOS and never reaches the stub's recoveryOS. Asahi's way (RESEARCH.md, `bless --setBoot
--device <sys> --user <admin> --stdinpass`, no `--nextonly`, then hide SystemVersion, write the marker, shut down; the person holds
power and picks the new OS) makes the stub's boot the one true recoveryOS.

- **S65 is a persistent bless of the stub**: `bless --mount <stub System volume> --setBoot` and, with the owner's login,
  `--user <owner> --stdinpass` (password on stdin only). `BlessGuard.isAllowed` accepts exactly: `--getBoot`;
  `--mount <"/" or /Volumes/x> --setBoot` (4 elements); and the same plus `--user <owner> --stdinpass` (7 elements). `--nextonly`
  is **not** accepted by the helper at all. It remains only in SFRecoveryKit's R50 (`bless --mount <stub> --setBoot --nextonly`),
  run in recoveryOS after `kmutil configure-boot`.
- **What a normal power-on does before Setup has run.** The default points at the stub, whose SystemVersion is hidden, so the
  Mac falls back to macOS. This is expected, and the finish screen says so: "Until Setup has run, a normal start opens macOS. That
  is expected." The installer never says "Restart" any more; the button is **Shut Down** and the steps are: shut down, hold the
  power button until you see "Loading startup options", choose SiliconForest, not Options.
- **R50's role.** Redundant when S65's persistent bless worked; it makes the restart after Setup come back to SiliconForest (one
  time) even if the startup disk was changed in between, and covers an S65 that failed (manual path). It does not change the
  persistent default.
- **Flagged design question: the persistent default stays on SiliconForest after Setup** until **Remove** (U10) or the person
  chooses macOS in Startup Disk. A failed SiliconForest start would then not fall back to macOS by itself (D5 is relaxed). Putting
  macOS back as the default from R50 needs the owner's login and a mount of macOS's System volume in recoveryOS; it is not built.
- **Remove (U10)** resets the startup disk to macOS when `bless --getBoot` names SiliconForest (always the case now). It takes the
  owner's login through the same `--user/--stdinpass` shape (the removal confirm screen has the optional field: "Set macOS as the
  startup disk again"). If bless fails the removal is **not** failed: U10's evidence says `reset: no` with the reason and the
  manual command.
- **Copy, everywhere** (`StartupOptionsCopy`, `Copy.Recovery.steps`, `AfterHandoff.manualSteps/fallback`, `Copy.StartupFinish`):
  "Hold the power button until you see “Loading startup options”." and "Choose SiliconForest, not Options. Options opens macOS
  Recovery, which can't finish the setup."
- **SFRecovery knows which recovery it is in.** Its gate runs `bputil -d` (no `-v`: the recovery that is running). Not "one true
  recoveryOS", or "Not Paired", or no "one true recoveryOS" for the stub's group (`-d -v <VGID>`), or (when bputil prints nothing) the stub
  mounted under `/Volumes/`, means macOS's Recovery. Nothing is changed; the screen is titled **This is macOS Recovery, not
  SiliconForest's.**, with steps (shut down; hold power until Loading startup options; choose SiliconForest, not Options) and a
  **Shut Down** button. The same check is in `sf-step2.sh`. Not yet exercised on real hardware.
- **Owners instead of "Chris".** S60 writes `owners` (short and full names, from `StartupOwners`, which now also reads `RealName`)
  and `owner` (the one whose login was given for bless) into `plan.json`. SFRecovery shows the full name ("Password for Chris
  Kearney"), a picker when there are several, and "Your Mac login password" when none are known. If the plan has none it parses the
  stub's Preboot `AdminUserRecoveryInfo.plist` tolerantly (layout undocumented: **unverified on a real Mac**).
- **Username prompts.** The PTY rules for `bputil -nc` and `kmutil configure-boot` answer a prompt containing "username", "user
  name", "name of an administrator" or "name of an admin" with the owner's short name, unless the same output also asks for the
  password. The real wording isn't recorded in the repo (Asahi's docs only say "Enter the username… / enter the password…"), so
  this is **unverified on hardware**. Password redaction is unchanged.
- **The helper registration bug (preview12's "Job is not allowed to bootstrap").** `PrivilegeGate.refreshIfBuildChanged` /
  `restartHelper` unregistered an already-approved helper; macOS then disabled it, and `.failed` was never polled again. Now: an
  approved, enabled helper is **never unregistered**. A stale helper is replaced by the new `retire` XPC verb (it exits itself;
  launchd starts the current binary at the next connection; older helpers idle out). The gate registers **only for `.notRegistered`**
  (by a person's click), and a register error 1 / "Operation not permitted" / "not allowed to bootstrap" maps to the approval screen
  (not `.failed`) and doesn't retry until the status changes. `.failed` is polled too, so the X clears. The NSError domain and code
  are logged. The copy names the toggle: "Allow in the Background → SiliconForest Installer".

