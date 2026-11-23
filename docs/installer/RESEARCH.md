<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Chris Kearney and the SiliconForest contributors -->

# SiliconForest installer: research record

CHL-27 phase 1, 22 November 2026. This is the evidence behind [`DESIGN.md`](DESIGN.md).

**What this is.** A reading of source code, documentation, public issue trackers and one Apple
restore image. Nothing here was run on a Mac. No disk was touched, no upstream code was built or
executed, and neither the M1 nor the M3 was contacted.

Marks used below:

| Mark | Meaning |
|---|---|
| **read** | Read in source at the stated revision |
| **data** | Read from a real artifact (Apple's 13.5 restore image for J293) |
| **Apple** | Stated in an Apple primary source |
| **report** | A user report in a tracker. Real, but not confirmed |
| **inferred** | Our conclusion from the above |
| **unknown** | Not established. Listed as a spike in `DESIGN.md` section 15 |

## 1. Revisions read

| Project | Revision | URL |
|---|---|---|
| Omacom installer | `e0aa53fdf4fc` (main, 22 Nov 2026) | <https://github.com/omacom/omarchy-mac-installer> |
| Omacom script route | `71174e8b7a0e` (frozen, points to the installer) | <https://github.com/omacom/omarchy-mac> |
| Asahi installer | v0.9.2 `dffbb38ef0c0`, main `e93743d52178` (same `src/`) | <https://github.com/AsahiLinux/asahi-installer> |
| m1n1 | v2.0.1 `5e3a756398bf`; our stage 1 is Omacom's `121fcbf35d45` | <https://github.com/AsahiLinux/m1n1> |
| asahi-bless | 0.4.4, `3df52c939fbc` | <https://github.com/WhatAmISupposedToPutHere/asahi-nvram> |
| Asahi docs | `e8bcfeab975a` | <https://github.com/AsahiLinux/docs> |
| Asahi installer data | `06543833b81f` | <https://github.com/AsahiLinux/asahi-installer-data> |
| Apple restore image | `UniversalMac_13.5_22G74_Restore.ipsw`, J293 identity and BaseSystem only | Apple CDN, URL in [`J293.json`](../../installer/profiles/J293.json) |
| Apple documentation | HIG, Platform Security, ServiceManagement, man pages (Xcode 27.3 beta 2 mirror) | Cited inline |

## 2. Omacom's Mac installer

**What it is.** A SwiftUI macOS app (`Omarchy Installer.app`, macOS 15+) distributed as a dmg and a
Homebrew cask. It installs Omarchy beside macOS by driving a pinned Asahi v0.9.2 engine with a
Python overlay. A separate AppKit app runs in recoveryOS. Every release is a GitHub pre-release.

```
Omarchy Installer.app (SwiftUI)
  ├─ root helper via SMJobBless, XPC pinned in both directions
  ├─ Engine: Asahi v0.9.2 + Python overlay + bundled Python 3.13
  ├─ RecoveryTemplate/Omarchy Installer.app (AppKit, macOS 13 target)
  └─ signed-catalog trust root (Ed25519)
Catalog → engine + OS zip (digests) → unprivileged plan → password → helper → engine as root
  → shut down → user holds power → Recovery app auto-launches → bputil + kmutil → restart
```

### What it does well (read)

| Idea | Where |
|---|---|
| The Recovery step is a real branded app, launched by pointing `.IAPhysicalMedia` at it | `Engine/overlay/src/omarchy_recovery.py:372-502` |
| Before any write, Recovery checks root, the volume identity, and `bputil` reporting both `one true recoveryOS` and `Paired` | `Recovery/Sources/RecoveryActions.swift:51-67`, `EnrollmentGate.swift:44-74` |
| Plans bind the live layout, the exact artifacts and the required human steps through nested digests | `omarchy_execution.py:124-132,286-300,410-434` |
| An append-only, fsynced intent and checkpoint journal | `omarchy_contract.py:13,491-519` |
| "No disk changes were made" appears only when the root-owned journal proves it | `PlainLanguage.swift:498-508` |
| All copy lives in one file. A debug-only simulator covers 31 scenarios, including failure screens | `PlainLanguage.swift`, `InstallerSimulation.swift:6-14` |
| A helper-owned, five-minute, single-use removal ticket, with the layout rechecked around every step | `ClosedEngineHelperServer.swift:265-283`, `OmarchyRemoval.swift:328-352` |
| A build gate rejects any framework the 13.5 Recovery lacks | `Recovery/build-app.sh:23-46` |
| Ed25519-signed catalog with per-channel sequence. All three live signatures verified against the repository's trust root | `SignedSupportCatalog.swift:132-183` |
| `bless` exit status is not trusted: the boot volume is read back | `omarchy_asahi.py:63-80,229-236,1889-1911` |

### What it does badly or leaves open

| Problem | Evidence |
|---|---|
| **Boot loop on our exact model.** J293 on macOS 26.6.1: both stages complete, `nsih` matches, then Apple logo, Omarchy logo, reboot, forever. Open, no comments, cause unknown | **report**, [#218](https://github.com/omacom/omarchy-mac-installer/issues/218) |
| It says "Installation complete!" before anyone has booted the OS | read, #218, #198, #200 |
| Resize is its worst stage: stalls over an hour, survives force-quit, and can end in a state the planner refuses | **report**, #196, #199, #210, #211, #146 |
| Dead ends: an intent with no checkpoint blocks resume | read, `omarchy_stage1.py:178-181`; #180 |
| A macOS update between the stages breaks owner lookup with a misleading error | **report**, #183 |
| Software Update treats the stub as an OS to update | **report**, #231 |
| The progress bar is mostly a timer, capped at 95% | read, `InstallationProgressEstimate.swift:14-21` |
| The bundled root-run Python carries `disable-library-validation`, `allow-unsigned-executable-memory` and `allow-dyld-environment-variables` | read, `Engine/python-executable.entitlements.plist` (exploitability not audited) |
| Neither app is fullscreen (780×600 and 780×440). The flow is a stack of windows and sheets | read; its own tracker says the design "does not spark joy" (#192) |
| Debug and USB-proxy switches sit on the ordinary repair screen | read, `InstallerView.swift:422-429` |
| README drift: it still describes a typed removal phrase and reinstall-over-existing | read, section 1 of our notes |

**Provenance caution.** Omacom's repository is MIT, but several Recovery files credit
`aurora-silicon/aurora-installer` at `7be5339` as MIT. GitHub detects no licence on that
repository's current head. We therefore **do not copy** Omacom's Recovery PTY code
(`Recovery/Native/Authorization.c`). We reimplement the behaviour from Apple's tools and our own
tests, or copy only after the provenance is checked file by file.

## 3. The Asahi installer

### Step 1, in macOS (read, `src/main.py`, `stub.py`, `osinstall.py`, `diskutil.py`)

1. **Read the machine:** `ioreg`, `nvram -p`, `bputil -d`, `scutil` (console user), `diskutil list/apfs list/info -plist`.
   This is not strictly read-only. It mounts Preboot, Recovery, System and Data of every OS, and runs
   `diskutil apfs updatePreboot` if macOS's admin list is stale.
2. **Size the resize:**

   ```python
   limits = diskutil apfs resizeContainer <part> limits -plist
   min_raw  = align_up(CapacityCeiling - CapacityFree + 38 GB, 1 MiB)
   min_size = max(min_raw, limits["MinimumSizePreferred"])
   ```

   The 38 GB margin drops to 1 GB on disks under 150 GiB. An overhead above 16 GB triggers a warning
   about Time Machine snapshots or a pending macOS update.
3. **Resize:** `diskutil apfs resizeContainer <part> <bytes>`.
4. **Stub container and volumes:** `diskutil addPartition <prev> apfs "<name>" 2499805184`, then `changeVolumeRole`,
   `addVolume` for System (`-groupWith` Data), Preboot and Recovery.
5. **Build the stub from Apple's IPSW** over HTTP range reads. For J293 13.5 it needs at most **about 0.72 GB of the 12.9 GB image** (**data**).
6. **OS partitions:** `diskutil addPartition <prev> %EFI% %noformat% <bytes>`, `newfs_msdos -F 32`, then the package contents.
7. **Boot object:** `m1n1 + "chosen.asahi,efi-system-partition=<partuuid>\n" + "chainload=<partuuid>;<next>\n" + 4 NUL`.
8. **Bless and hand off:** `bless --setBoot --device <sys> --user <admin> --stdinpass`, hide `SystemVersion.plist`, enable `.IAPhysicalMedia`, shut down.

### Step 2, in recoveryOS (read, `src/step2/step2.sh`)

```sh
bputil -d -v "$VGID"              # must contain ": Paired" and "one true recoveryOS"
bputil -nc -v "$VGID"             # Permissive Security, kernel CTRR off, for this OS only
kmutil configure-boot -c boot.bin --raw --entry-point 2048 \
       --lowest-virtual-address 0 -v "$system_dir"
mount -u -w "$system_dir"         # then disable .IAPhysicalMedia, restore SystemVersion.plist
reboot
```

The picker launches the `AppName` bundle named by `.IAPhysicalMedia`. In Asahi that is a shell script that
execs Recovery's Terminal with `step2.sh`.

### Safety checks it has and lacks (read)

| Has | Lacks |
|---|---|
| Console user, admin list, GPT, device allow-list, firmware minimums, Rosetta, the ProMotion firmware bug (J293 not affected) | FileVault state, SIP, AC power, macOS upper bound, any snapshot listing, journal, rollback |

Known code hazards we must not port: `label.rstrip(" - Data")` strips characters rather than a suffix
(`stub.py:80`); the "Multiple volumes" guard never fires (`stub.py:66-69`); the URL cache never evicts and does not
check for HTTP 206 (`urlcache.py:15,103-108,166`); a password is passed in argv in one path (`main.py:643-644`).

### Uninstall (read)

**No uninstaller is merged** (issue #83, PR #128 open since 2022). The documented procedure is: make macOS the default,
`diskutil apfs deleteContainer <stub>`, `diskutil eraseVolume free free <ESP>` and `<root>`, then
`diskutil apfs resizeContainer <macOS> 0`. Never delete `Apple_APFS_Recovery`.

The boot policy stays behind in `/System/Volumes/iSCPreboot/<VGID>/`. `bputil -d` only displays. Apple's current man page lists
`-r` (remove by VGID) and `-z` (clean up all absent VGIDs), but **the 13.5 `bputil` has neither** (**data**, getopt string).
`-z` would also destroy the policy of an unplugged external macOS, so we never use it.

### Field failures to design for

| Failure | Evidence |
|---|---|
| `bless` Code 112, "Preserved restore bundle in preboot is missing", M1/M2 on macOS 26.x. Cause not established | **report**, [#404](https://github.com/AsahiLinux/asahi-installer/issues/404), open, 19 comments |
| Resize error `-69606` on macOS 27. The reporter's fix was rolling back to 26. Closed without a recorded code fix | **report**, [#448](https://github.com/AsahiLinux/asahi-installer/issues/448) |
| Resize stuck at "Shrinking APFS data structures", sometimes after the container had already resized | **report**, [#391](https://github.com/AsahiLinux/asahi-installer/issues/391) |
| `.IAPhysicalMedia` ignored on an M4 with 26.5.1. Not tested on J293 | **report**, [#441](https://github.com/AsahiLinux/asahi-installer/issues/441) |
| APFS corruption blocks resize; the fix is `diskutil repairVolume` from recoveryOS | **report**, #88, #80, #54 |
| Stale owner after a macOS reinstall (`bputil` "User not found") | **report**, #401 |

### Upstream's own GUI direction

Unmerged PRs [#454](https://github.com/AsahiLinux/asahi-installer/pull/454) and
[#455](https://github.com/AsahiLinux/asahi-installer/pull/455) add a localhost WebSocket backend with a placeholder page, for step 1 only.
#454 also relicenses the refactored core to GPL. **Our port therefore pins v0.9.2, which is MIT.**

## 4. What recoveryOS really contains

Read from the actual J293 13.5 BaseSystem (**data**, 57,025 paths). This is the environment a correct step 2 runs in,
because J293 gets the 13.5 stub and pairing requires the stub's own recoveryOS.

| Present | Absent |
|---|---|
| AppKit, Foundation, CoreGraphics, QuartzCore, Metal, CoreText, WebKit, Security, IOKit, DiskArbitration | **SwiftUI**, Python |
| Swift core libraries in the dyld cache | The Swift AppKit overlay in practice (Omacom: `NSSound.beep()` stops launch) |
| `bputil`, `kmutil`, `bless`, `diskutil`, `nvram`, `hdiutil`, `codesign`, `curl`, `tar`, `caffeinate` | `open`, `osascript`, `sudo`, zsh, `tmutil`, `fdesetup` |
| `bash`, `perl`, Terminal, Disk Utility, Startup Disk, WindowServer | `syspolicyd` (the Gatekeeper daemon) |

- **Shipping elsewhere:** an unsigned script `.app` launches through `.IAPhysicalMedia` (Asahi). Omacom ships a Developer ID signed AppKit app there. We read both, and ran neither.
- **Unknown on J293:** ad-hoc signed Mach-O, borderless fullscreen, whether the launch path still works with the newest system firmware.

## 5. asahi-bless and m1n1

- **asahi-bless** is Linux-only and writes NVRAM only (`boot-volume`, or `alt-boot-volume` with `--next`). It cannot create a LocalPolicy. The app cannot use it, and SiliconForest has no NVRAM driver. Our lab's `asahi-bless --next` proves that a **one-shot next boot works on this J293** from Linux.
- **`bless --nextonly`** is listed under Apple-silicon Mount Mode in the current man page, while the general option text calls it EFI-only (**Apple**, [bless(8)](https://keith.github.io/xcode-man-pages/bless.8.html)). Whether the 13.5 recovery `bless` honours it is **unknown** (spike S5).
- **m1n1 appended variables** are `name=value\n`, ending in 4 NUL bytes. Only `chosen.*` is forwarded. PARTUUIDs must be lower case.
- **Our stage 1 is Omacom's m1n1 `121fcbf`** plus our patches. It refuses an oversized stage 2 (`image span overlaps the live heap`), so the size budget in `m1-native-boot/install/build.sh` stays a hard check.

## 6. Apple platform facts

| Fact | Mark | Source |
|---|---|---|
| Permissive Security needs a physical power-button hold into the paired recoveryOS plus owner credentials. It cannot be automated | Apple | [Boot process](https://support.apple.com/guide/security/boot-process-secac71d5623/web), [LocalPolicy](https://support.apple.com/guide/security/contents-a-localpolicy-file-mac-apple-silicon-secc745a0845/web) |
| Security policy is per installed OS, so macOS's own policy is unchanged | Apple | [Startup Disk policy](https://support.apple.com/guide/security/startup-disk-security-policy-control-sec7d92dc49f/web) |
| "Apple doesn't provide or support custom XNU kernels" | Apple | Boot process, above |
| `SMAppService.daemon` is macOS 13+; the plist is in `Contents/Library/LaunchDaemons` and uses `BundleProgram` | Apple | [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) |
| `SMAuthorizedClients` does not apply to SMAppService, so the daemon must pin its clients itself | Apple DTS | [thread 792826](https://developer.apple.com/forums/thread/792826) |
| `NSXPCListener.setConnectionCodeSigningRequirement` is available from macOS 13 | Apple | [docs](https://developer.apple.com/documentation/foundation/nsxpclistener/setconnectioncodesigningrequirement(_:)) |
| Changing a daemon's signing identifier can break upgrades | Apple DTS | [thread 795022](https://developer.apple.com/forums/thread/795022) |
| macOS 27's launchd will not load plists carrying the quarantine attribute | Apple | [macOS 27 notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes) |
| Root in a launchd daemon was denied a removable device until the GUI app obtained access. Internal partitions: **unknown** | Apple DTS | [thread 802650](https://developer.apple.com/forums/thread/802650) |
| Control-click no longer bypasses Gatekeeper from macOS 15 | Apple | [news](https://developer.apple.com/news/?id=saqachfa) |
| A container resize needs all its APFS volumes unlocked, and snapshots limit a shrink | Apple | [diskutil(8)](https://keith.github.io/xcode-man-pages/diskutil.8.html) |
| Liquid Glass is for controls and navigation. A content-layer slider may take it while being dragged | Apple | [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) |
| The HIG says people should choose when to enter full screen. Chris's brief overrides this: see `DESIGN.md` D9 | Apple | [Going full screen](https://developer.apple.com/design/human-interface-guidelines/going-full-screen) |
| No hosted GitHub runner covers macOS 13 or 14 | GitHub | [Runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) |

No public specification of Setup Assistant's visuals exists. Our references should be captures from a real Mac or VM.

## 7. UX lessons from other installers

| Source | Lesson we take |
|---|---|
| [Disk Utility](https://support.apple.com/guide/disk-utility/partition-a-physical-disk-dskutl14027/mac) | Used and free shading inside each segment. Drag paired with a typed size. Nothing happens until Apply |
| [GParted](https://gparted.org/display-doc.php?name=help-manual) | Graphic and numeric controls update together. Changes queue until Apply |
| Ubuntu ubiquity ([LP 1049048](https://bugs.launchpad.net/bugs/1049048), [426739](https://bugs.launchpad.net/ubuntu/+source/ubiquity/+bug/426739), [42532](https://launchpad.net/ubuntu/+source/ubiquity/+bug/42532)) | Label each side, use real units, make the handle obvious, and do not default to a useless minimum |
| [Canonical's installer redesign](https://canonical.com/blog/how-we-designed-the-new-ubuntu-desktop-installer) | The partition confirmation deserves its own screen |
| [Anaconda reclaim](https://www.fedoraproject.org/wiki/Changes/Anaconda_Reclaim_Disk_Space) | Lead with the outcome, not partition jargon |
| [Pop!_OS recovery](https://system76.com/support/pop-recovery) | Keep repair distinct from reinstall |
| [HIG Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts), [NN/g](https://www.nngroup.com/articles/confirmation-dialog/) | Name the verb, never "OK". Keep nonstandard confirmation for the truly destructive case |
| [HIG Progress](https://developer.apple.com/design/human-interface-guidelines/progress-indicators) | Do not use fake even progress. If something stalls, say so and say what to do |

## 8. Our own prior work

| Piece | Where | State | Reuse |
|---|---|---|---|
| Hand install of 13 Nov | `integrations/siliconforest/m1-native-boot/install/` (main) | **Ran on the real M1.** Stub + SFBOOT only; root predates it; macOS not shrunk | Boot chain, failure table, `sf_stop`, stage-size rule, GPT check |
| SF-AJ engine | `install/engine/` (`installer` branch, `cbad80a6d`) | 33 tests on a disk model. **Never run on a Mac** | Plan, gate rules, layout digest, FakeMac, recordings, firmware slot, kernel-line check |
| SF-AJ comparison and test plan | `docs/roadmap/issues/SF-AJ-installer.md` (same branch) | Written | Real-hardware checklist |
| Release image recipe | `release/` (`release-image`, `56923db93`) | Boots in QEMU; **no published release** | Root layers, boot files, `sf_personalize.py`, `SHA256SUMS` + SSH signature |
| Installer image packaging | `release/installer-image/` (`image-install`, `2d9df0061`) | Builds a fixed 4 GiB root | `install.json`, xz parts, firmware slot, first-boot unpacker |
| Branding | `integrations/siliconforest/branding/`, `desktop/themes/` | In use | Mark, Canopy and Clearing palettes, wallpaper generator |

All three branches are far behind `main`, and the image they build predates the current system. The installer design assumes
a new image from the current integration line (see `DESIGN.md` section 16).
