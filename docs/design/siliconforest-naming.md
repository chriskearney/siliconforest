# SiliconForest naming and attribution

State: 17 November 2026. Branch `sf-rename` carries the rename; `main` does not. Nothing here has
been installed on the M1. What was built and booted from the renamed tree is at the end
("Proof"), with what was not.

SiliconForest is a fork of PureDarwin. Until now the fork showed in few places: the machine said
`puredarwin`, the kernel extensions were `PD…`, the processes `pd…`, the bundle identifiers
`org.puredarwin.…`. This note fixes what every name becomes, which names stay and why, and how
the rename is repeated when upstream changes.

## 1. The rule in one paragraph

Everything that is ours or upstream PureDarwin's own naming takes the SiliconForest name. A name
stays when it belongs to somebody else (Apple's API, Linux, BSD, a file format already on disk),
when it is attribution (copyright and licence lines, the name PureDarwin where it means upstream),
or when it is evidence of what was done under the old name (records, receipts, kept revisions).
The rename is done by one tool with one rule table, `tools/sf_rename.py`, on three trees: this
repository, a checkout of upstream PureDarwin, and the Chonkstep Darwin source.

## 2. The map

| Kind | Before | After | Rule |
|---|---|---|---|
| Product name, any spelling | `PureDarwin`, `puredarwin`, `PUREDARWIN` | `SiliconForest`, `siliconforest`, `SILICONFOREST` | R1 |
| Bundle identifiers | `org.puredarwin.driver.X`, `org.puredarwin.kext.X`, `org.puredarwin.iokit.X` | `org.siliconforest.driver.X`, … | R1 |
| launchd labels | `org.puredarwin.hostname`, `org.puredarwin.dmesg-save`, … | `org.siliconforest.hostname`, … | R1 |
| C identifiers and file names | `pd_nvme_gate`, `PD_DART_x`, `_PD_X_H`, `__pd_make` | `sf_nvme_gate`, `SF_DART_x`, `_SF_X_H`, `__sf_make` | R2 |
| the same inside a longer name | `sysctl__kern_pd_avd`, `virgl_pd_winsys`, `F_PD_SAMEFILE`, `DYLD_PD_MISSING_OK` | `sysctl__kern_sf_avd`, `virgl_sf_winsys`, `F_SF_SAMEFILE`, `DYLD_SF_MISSING_OK` | R2: lower case `x_pd_y` always, except behind other people's prefixes (`pf_pd_*`, `usb_pd_*`, …); upper case `X_PD_Y` only behind listed prefixes (`kHIDUsage_PD_*` and register names stay) |
| a prefix pasted by the preprocessor | `pd_##f`, `PD_##NAME` | `sf_##f`, `SF_##NAME` | R2c (found by building OpenGL: `static … pd_##f` beside the renamed use `sf_eglGetProcAddress`) |
| compiler definitions | `-DPD_CORECRYPTO_DIR=…`, `-DPDGOP=1` | `-DSF_CORECRYPTO_DIR=…`, `-DSFGOP=1` | all rules also apply after `-D`/`-U` |
| libraries | `libPDGOP.a`, `-lPDGOP`, `libpdavd`, `-lpdavd`, `libpd_virgl_shim`, `kPDGPU_Present` | `libSFGOP.a`, `-lSFGOP`, `libsfavd`, `-lsfavd`, `libsf_virgl_shim`, `kSFGPU_Present` | R3 to R5 also apply after `lib`, `-l` and the constant prefix `k` |
| Rust types generated from `pd_` names | `PdWindowPositionV1`, `PdSpeaker` | `SfWindowPositionV1`, `SfSpeaker` | R12 |
| directories named `pd` | `src/Kernel/fbsdkpi/pd/`, `${FBSDKPI_DIR}/pd` | `…/sf/`, `${FBSDKPI_DIR}/sf` | R11 |
| two-prefix names | `PD_SF_FENCE_FIRST` | `SF_FENCE_FIRST` | R2b |
| Classes, kexts, frameworks, constants | `PDAppleAVD`, `PDArmPlatformExpert`, `kPDAudioOutputDevice`, `libPDSurface` | `SFAppleAVD`, `SFArmPlatformExpert`, `kSFAudioOutputDevice`, `libSFSurface` | R3 |
| All-capital names | `PDGOP`, `PDM1SPIHID`, `PDAVD_IOC_DECODE`, `HAVE_PDGOP`, `DTYPE_PDLFILE` | `SFGOP`, `SFM1SPIHID`, `SFAVD_IOC_DECODE`, `HAVE_SFGOP`, `DTYPE_SFLFILE` | R4 |
| Boot arguments | `pdavd=`, `pdm1kbd=`, `pdm1tpscroll=`, `pdnvme=`, `pdagx_diag=`, `pdpoweroff=`, `pdgopmode=`, `pdtime=`, `pdstack=` (about 110 in both trees) | `sfavd=`, `sfm1kbd=`, `sfm1tpscroll=`, `sfnvme=`, `sfagx_diag=`, … | R5 |
| Programs and devices | `pdplay`, `pdtone`, `pdvolume`, `pdvideo`, `pdtbtest`, `pdmtl`, `pdinstall`, `pdbless`, `pdpowerd`, `pdaccountsd`, `/dev/pdavd`, sysctl `kern.pd_avd.*`, `hw.pdled` | `sfplay`, `sftone`, `sfvolume`, `sfvideo`, `sftbtest`, `sfmtl`, `sfinstall`, `sfbless`, `sfpowerd`, `sfaccountsd`, `/dev/sfavd`, `kern.sf_avd.*`, `hw.sfled` | R5, R2 |
| Daemons and tools with a hyphen | `pd-netd`, `pd-dhcp`, `pd-net-up`, `pd-backlight`, `pd-wifipm`, `pd-console-login`, `pd-rebuild-kc` | `sf-netd`, `sf-dhcp`, `sf-net-up`, `sf-backlight`, `sf-wifipm`, `sf-console-login`, `sf-rebuild-kc` | R6 |
| Functions and variables `pdCamel` | `pdTraceName`, `pdHIDPublishSupportedQueues` | `sfTraceName`, `sfHIDPublishSupportedQueues` | R7 |
| Packages "for PD" | `metal-pd.nix`, `libindium-pd`, `0001-pd-runtime-layout.patch` | `metal-sf.nix`, `libindium-sf`, `0001-sf-runtime-layout.patch` | R8, R9 |
| Installed paths | `/usr/standalone/PureDarwin/`, `/EFI/PureDarwin/BOOTX64.EFI`, `/Library/User Pictures/PureDarwin/` | `/usr/standalone/SiliconForest/`, `/EFI/SiliconForest/BOOTX64.EFI`, … | R1 |
| Repository | `integrations/puredarwin/` | `integrations/siliconforest/` (all of it moves; frozen files keep their bytes and their own names) | path rule |

`pdm1…` needs no rule of its own: `pdm1kbd` and the other `pdm1…` boot arguments are in the R5
vocabulary, `PDM1SPIHID` and `PDM1KeyboardHW` fall under R4 and R3.

R10: where a phrase named both ("SiliconForest PureDarwin guest", `puredarwin-siliconforest-boot-kexts`)
the result says the name once.

Rules R4 to R6 and R8 work from vocabularies in `tools/sf_rename_data.json`, because `pd` followed
by letters is usually somebody else's word (`pdev`, `pdata`, `pdrv`, `PDE`, `PDPT`). A name that is
in neither the rename vocabulary nor the list of other people's words makes `check` fail, so a new
upstream name is classified by a person once and then stays classified.

## 3. Whose name is it

| Class | What | Treatment |
|---|---|---|
| Ours | everything written in this lab in upstream's style: the M1 kexts (`PDM1*`, `PDApple*`, `PDBwfm`, `PDDcp`, `PDAgx`, `PDGpuDT`, `PDCpuPower`, …), `pd_dart`, `pd_tb`, `pd_nvme`, `pd_hid`, `pd_dcp`, `pd_avd`, `pd-netd`, `pd-dhcp`, `pdplay`, `pdvideo`, the boot arguments, the Cocoa and compositor patches' helpers | renamed |
| Upstream PureDarwin's | its kexts and classes (`PDArmPlatformExpert`, `PDSun60iDisplay`, `PDIOSurface`, `PDSerialHID`, …), its bundle identifiers (`org.puredarwin.iokit.IOUSBFamily`), its libraries' internals (`pd_cgl_*`, `pd_vk_*`, `pd_lkpi_*`, `PDSurface`, `PDGOP`), its tools (`pdmtl`, `pdinstall`, `pdbless`), its image recipe (hostname, `SystemVersion.plist`, launchd jobs) | renamed in our fork commit of upstream (section 5); our patches and recipes use the new names |
| Finch's | names inside files taken from Finch (`SFNetworking.h` is Finch's own and unrelated to this rename; `FinchLayoutItem.h`); our glue around them (`PDFinchSymbolImage`) | Finch's names stay; our glue is renamed. Finch's notices and the "Taken from Finch" tables stay as they are |
| External contract | `Darwin` (the kernel's name: `uname -s`, the triple `aarch64-apple-darwin`, `darwin` in every path of the toolchain); Apple-compatible class, framework and symbol names (`IOKit`, `NS…`, `CF…`, `PDFKit`'s `PDFDocument`…); XNU's `pd_entry_t`; Linux and BSD identifiers (`pdev`, `pdata`, `pf_pd_*`, `kHIDUsage_PD_*`, PowerVR's `PDVFS`, `pdfork`); the names of the Linux-derived driver files as Linux has them; `sources/puredarwin-*` (the local clones of upstream are upstream); URLs, `github:PureDarwin/…`, `flake.lock` owners; Nix store paths of builds that exist | never renamed. The list of other people's `pd…`/`PD…` words is in `tools/sf_rename_data.json` (`lower_false`, `caps_false`, `hyphen_false`) and in the tool (`SNAKE_KEEP`, `CAMEL_KEEP`) |
| File formats already written | magics `PDAJ` (AVD recordings, `.pdaj` files), `PDHFSRT1`, `PDAOT003`, `PDDB`, `PDSB`, `PDRL`, the stage record `pdsf`/`PDSF` | stay: files and disks written with them exist. Numeric magics are untouched by construction |
| Attribution | every line with a copyright or licence notice, SPDX lines, author lines; "PureDarwin Project"; `PUREDARWIN_LICENSE.txt`; "upstream PureDarwin", "a fork of PureDarwin" | never changed (the tool skips the line or the phrase; proof in section 8) |
| Frozen evidence and history | `reports/`, `archive/`, `planning/`, `docs/` except `docs/design/`, `AGENTS.md`, the lab scaffold of 7 to 9 November (`config/`, `core/`, `contracts/`, `probe/`, `specs/`, `tests/`, `userspace/`, `fixtures/`, the scaffold's tools and the frozen recovery controllers under `tools/`), `integrations/m1-boot-window/`; under `integrations/`: 29 hash-bound streams that the release does not reach, the parked `m1-apcie-bridge` leaves, every `before/`, `after/`, `validation*/`, `revisions/`, `attempts/`, numbered leaf and build output, the snapshot `chonkstep-darwin/desktop-shell/source/` | bytes and file names untouched. Those under `integrations/puredarwin/` move with the directory to `integrations/siliconforest/` so that relative references keep working; a record that names `integrations/puredarwin/x` means `integrations/siliconforest/x` |

### Exceptions, one by one

| File or name | Why it is not renamed | What a later change would involve |
|---|---|---|
| `integrations/…/m1-firstboot/host_console.py` | hash-pinned host-side controller tool; never edited. It contains no PD name | nothing to do |
| `integrations/…/m1-bringup/normal_image.py` | hash-pinned host-side image tool; never edited. Its `PINS['puredarwin']` and the record field `source_commit` name upstream's revision `e7aa00a6` | owner approval; then the key could become `upstream`, with a new pin of the file's hash wherever it is recorded (`m1-apcie-bridge/native_bootargs_host_revision/*/baseline-files.json` and the launcher tree on the M5) and a new launcher base tree. It gains nothing visible |
| the launcher base tree (`runs/m1-desktop-010/pcie-m2-host-001/lab`, outside git) and the 10 patches against it (`launcher-native.patch`, `host_progress-smp.patch`, `quiet-boot.patch`, …) | host side, hash-pinned lineage; its member gate asks for the collection members by their old names (`PDM1SPIHID`, …) | **needed before a hypervisor boot of a renamed collection through `tools/pcie_iterate.sh`**: change the gate's member names in the base tree, regenerate the patches (the method is in `docs/roadmap/issues/SF-V-rebase.md`). A disk boot does not use the launcher |
| `integrations/…/rebase/pd.nix`, `SF_PD` | they select the upstream PureDarwin revision; the name says what it is | the owner may prefer `upstream.nix` / `SF_UPSTREAM`; one line in the rule table |
| `pdsf`, `PDSF`, `pdsfstop` | the native-boot stage record format and its files; `sfsf` would be the result | rename by hand to `sfstage` if wanted; the stage image on SFBOOT carries the format |
| `PDNB1`, the lines `PDNB …` of the resident EL2 page (`m1-native-boot/stub/el2_drop.S`, `native_stub.py`; `pdsf_boot.c`, `native_boot.py` and two tests read the mark) | the page is pinned by hash to the one that booted on the machine (`STUB_SHA256`); its parameter mark is the number `0x31424e4450` and its messages are in its bytes. The rename had changed one message and the texts that compare the mark, but not the number: stage 2 did not build and would not have found its page. Put back on 17 November (`PDNB`, `PDNB1` are in `caps_false`) | a new page (mark `SFNB1`, new hash, new `native_stub.py`) is a page that has never booted: with the owner's approval and a boot on the machine |
| 58 files under `m1-thunderbolt/` and `m1-sound/safetyd/tests/upstream-ref/` | Linux and speakersafetyd files taken as they are; their SHA-256 is in a provenance manifest | none: they are not ours |
| `README.md` | written by hand: it says what is SiliconForest and what is upstream | |
| `xnu-loader`, `kc-tools`, `iig-tools` (flake inputs `github:PureDarwin/…`, fetched by hash) | upstream's separate repositories. The two tools run on the build host and ship nowhere; the EFI loader is used by the QEMU and PC images, not on the M1 (m1n1 starts the kernel there), and prints upstream's name on QEMU's boot console | fork each the same way (`fork`), point the flake inputs at the local forks. Only worth it if a PC or QEMU image is ever released |
| `PD_BASE` in upstream's PowerVR driver | Imagination's page-directory field, pasted into `ROGUE_MMUCTRL_PC_DATA_PD_BASE_*` | none |
| "Redistributable PureDarwin SDK …", the installer's "PureDarwin comes as is, without warranty" strings | lines with redistribution or warranty wording are treated as notices and skipped; neither ships on the M1 | by hand if the installer is ever shipped |
| `SF_PD`-style collisions | see section 4 | |

Superseded pins: in the release directories the tool renames source files whose SHA-256 an older
receipt records (`m1-keyboard/adapter-source-validation.json`, `m1-trackpad-child/source-validation.json`,
`m1-firefox-kernel/avd-source-manifest.json`, `m1-wayland/patches.json`, the `reports/sprint-010`
build reviews). The receipts are not rewritten; they describe the bytes at commit `93738b915`,
the last commit before the rename, where every one of them still verifies. Tests that compare
against those hashes fail on `sf-rename` for that reason and no other.

One frozen file is read by the release build: `m1-native-input/revisions/002/candidate.patch`
(the IOHIDFamily publication patch in the default collection). It stays as it is; the tool writes
its renamed copy `m1-native-input/hid-publication-rev002.patch`, and the recipe uses that copy
without the manifest's per-file hash comparison (those hashes are of upstream's text before the
rename). The patch must still apply exactly.

### Numbers (tool output, 17 November)

| Tree | Files | Renamed or moved | Content changed | Distinct names | Occurrences |
|---|---|---|---|---|---|
| this repository | 12,013 tracked: 3,573 live, 8,367 frozen, 58 third-party as is, 10 launcher patches, 8 kept by name | 10,826 moved to `integrations/siliconforest/` (the live ones also renamed by the rules) | 1,720 | 3,816 | 33,603 |
| upstream fork commit | 33,085 + corecrypto's 305 | about 1,600 | about 2,000 | 4,528 (without corecrypto) | 32,249 |
| Chonkstep Darwin source (`vendor/` left out) | 3,675 | 0 | 20 | 26 | 164 |

Other people's words that match a `pd` pattern and stay: 114 lower-case words, 98 all-capital
ones, 5 hyphenated, 23 prefixes of `x_pd_y`, Apple's PDFKit family, 4 single identifiers.

## 4. Collisions

| Collision | Resolution |
|---|---|
| `PD_SF_FENCE_FIRST`, `PD_SF_FENCE_BLOCKS` (the write fence) would become `SF_SF_…` | R2b: `SF_FENCE_FIRST`, `SF_FENCE_BLOCKS`. No `SF_FENCE_*` existed. Values untouched (section 7) |
| `SF_PD` (environment variable: which upstream revision) | stays: `PD` alone is no rule's match, and it names upstream |
| `SF_PDAVD_CONTEXT_STATS`, `sf_pdavd_capture_pool` (the compositor's `SF_` + the device `pdavd`) | `SF_SFAVD_CONTEXT_STATS`, `sf_sfavd_capture_pool`: prefix of the component, then the device's name. Ugly, unambiguous; a hand rename to `SF_AVD_…` is open |
| `pdsf*`, `PDSF*` | exception (above) |
| `SF_STAGED`, `sf_nv12_*`, `sf-session`, `sf-trace`, `/private/var/db/sf*` | already ours; no `pd` counterpart maps onto them (`pd_nv12_*` does not exist) |
| `SFNetworking.h` (Finch) | no `PDNetworking.h` exists; nothing maps onto it |
| `PDFinchSymbolImage` → `SFFinchSymbolImage` next to `SFFinch` (a macro argument in `finch/VideoToolbox`) | different names, different files |
| `pd_entry` → `sf_entry`, `pd_log` → `sf_log`, `pd_fd`/`pd_id`/`pd_mapping`/`pd_name` → `sf_…` (upstream: XNU's shared-region and socket-filter fields `sf_fd`, `sf_name`, …) | the old and the new name never occur in the same file (checked); they are struct members and locals of unrelated code |
| `/dev/pdavd` → `/dev/sfavd` next to `/private/var/db/sfavd` (a test directory on the M1) | a device node and a directory; different namespaces |
| `SF-xx` document ids | no rule produces `SF-` from anything |
| "SiliconForest (PureDarwin 26.5 …)" and similar phrases that named both | R10 says the name once; neofetch's line becomes "SiliconForest 26.5 …" (an explicit edit in the tool) |

`tools/sf_rename.py inventory` prints every mapped name that already exists in the tree; the
table above is that list, read.

Not renamed, knowingly: two Rust type names in the speaker safety daemon, `PdspkInfo` and `PdspkVolume`
(`m1-sound/safetyd`): R12 asks for a capital after `Pd`, and they name nothing outside their file. And a name inside a longer camelCase word (`initWithPDSurface:`,
`isPDKext`). The class it mentions is renamed; the selector or variable keeps its spelling. It
compiles (definition and use carry the same word) and is visible nowhere outside the source.

## 5. Upstream: a fork commit made by the tool

Upstream reaches the build as one Git revision of a local clone (`integrations/…/rebase/pd.nix`).
The SiliconForest tree is that revision plus **one commit**: the rename, made by

    tools/sf_rename.py fork sources/puredarwin-rebase c713d8fb9b048a38e2242d67e29b9957ced8c495

which leaves branch `siliconforest/c713d8fb` in the clone; the commit id is `FORK_REV` in the tool
and the `rev` in `pd.nix`. Author, committer and date are fixed, so the same upstream revision and
the same rules give the same commit id; this was observed (two runs of one rule set, one id).
There is no string patching at build time and nothing is patched in a binary: the compiler sees
SiliconForest names in every file.

Upstream's one submodule, `external/corecrypto` (another repository, with upstream's build glue
in it: `pd/kext.cmake`, `PD_CORECRYPTO_*`), cannot be reached by a rename of the main tree. `fork`
puts its files, at the commit upstream records, into the fork commit as ordinary files and
renames them with the rest; `.gitmodules` goes. The flake's `path:./external/corecrypto` input
then reads those files. corecrypto is under its own licence and is not redistributed: the fork
commit lives in the local clone only, like the submodule did.

Why a generated fork commit and not a hand-kept fork branch: about 2,000 of upstream's 33,085 files
change and about 1,600 are renamed. A branch kept by hand would conflict with nearly every upstream
commit. A generated commit never conflicts, because it is not merged: it is made again.

Taking upstream changes later:

1. fetch upstream into the clone; choose the revision `R`;
2. `tools/sf_rename.py fork sources/puredarwin-rebase R`, then `check --tree` on a checkout of the
   result. New upstream names that the vocabularies do not know make `check` fail and are listed:
   add each to the rename vocabulary or to the other people's words;
3. put the new commit id in `pd.nix`; build. Our patches are already in SiliconForest names and
   apply to the renamed tree exactly as the old patches applied to upstream's;
4. a single upstream commit can be taken as a patch the same way: `git format-patch -1`, run the
   patch text through the rules (`transform_text`), apply.

The Chonkstep Darwin source (`sources/chonkstep-darwin`, a local clone that is never pushed from here; Chonkstep
itself is public, GPL-3.0-only, and a copy of it is vendored in this repository, see `NOTICE`) is renamed with the
same command (`tree`), without its `vendor/` directory. "Chonkstep" itself is the desktop's name
and stays.

The old pin (upstream `e7aa00a6`) is forked the same way, because the Cocoa stream still builds from it
(`integrations/siliconforest/cocoa/pin.nix`, `arm64.nix`, `build-cocoa-root.nix`: AppKit, CoreText, Onyx2D,
CoreGraphics, QuartzCore, libWindowServer, IOSurface, OpenGL and everything that imports them):

    tools/sf_rename.py fork sources/puredarwin-baseline e7aa00a60f0b56ef35aa24252e81467787bf71ea

leaves branch `siliconforest/e7aa00a6` = `04b6ecb44f8d6d8c650b8e3e1912bc57b881265d`; the three Cocoa recipes name that
commit. Three names that exist only at the pin were classified for it (`pd-wayland-session` and the boot argument
`pdmmcsync` renamed, `pde0` an AMD page-directory word that stays); none of them occurs at the tip, so the tip's
fork commit is unchanged. `check --tree` is clean on the pin's fork and `licence-proof` finds 0 changed notice lines
(32,580 files compared, 1,841 changed). Both forks were made again with rule R2c (17 November, evening): the tip's is now `cd001928` (`FORK_REV`, `rebase/pd.nix`;
it was `e7110de8`), differing from the earlier one in `src/Frameworks/OpenGL/CGL.c` and
`src/Libraries/libSystem/libc/darwin/sf_arm64_abi.c` only. Everything built from the tip before that is rebuilt.
`SF_PD=pin` in `rebase/pd.nix` still names upstream's own tree and is not
built by the recipes of this branch.

## 6. What the owner sees, and where it comes from

| Surface | Before | After | Source of truth |
|---|---|---|---|
| Host name (`hostname`, the shell prompt, `uname -n`) | `puredarwin` | `siliconforest` | upstream `image.nix`: `/bin/hostname`, `/etc/hosts`, the job `org.siliconforest.hostname`; on the M1's disk the installed `/etc/hosts` and the launchd job (section 9) |
| `sw_vers` ProductName | `PureDarwin` | `SiliconForest` | upstream `image.nix`, `SystemVersion.plist`; on the M1 `/System/Library/CoreServices/SystemVersion.plist` |
| `uname -a` | `Darwin puredarwin 25.5.0 Darwin Kernel Version …` | `Darwin siliconforest 25.5.0 Darwin Kernel Version …` | host name as above. `Darwin` is the kernel's name and stays |
| Boot console text | `PDM1SPIHID: …`, `PDBwfm: …`, `PDArmPlatformExpert…` | `SFM1SPIHID: …`, `SFBwfm: …`, … | the kexts' log strings (R3, R4) |
| Activity Monitor and `ps` | `pd-netd`, `pd-dhcp`, `pdpowerd`, `pdaccountsd` | `sf-netd`, `sf-dhcp`, `sfpowerd`, `sfaccountsd` | binary names: `m1-bwfm/netd`, upstream `src/Userspace` |
| `kextstat` | `org.puredarwin.driver.PDBwfm`, `org.puredarwin.kext.…`, `org.puredarwin.iokit.…` | `org.siliconforest.driver.SFBwfm`, … | each kext's `Info.plist` |
| `ioreg` class names | `PDArmPlatformExpert`, `PDDcp`, … | `SFArmPlatformExpert`, `SFDcp`, … | the C++ class names |
| Display make (what a Wayland client reads, Settings-like tools) | `PureDarwin` | `SiliconForest` | `sources/chonkstep-darwin` `crates/wm-darwin/src/server.rs` and the same file in the compositor builds |
| neofetch | "SiliconForest (PureDarwin 26.5 …)" through a workaround | "SiliconForest 26.5 …", the workaround keyed on `SiliconForest` | `integrations/siliconforest/desktop/neofetch/` |
| Device nodes and sysctls seen in a terminal | `/dev/pdavd`, `kern.pd_avd.state`, `hw.pdled` | `/dev/sfavd`, `kern.sf_avd.state`, `hw.sfled` | the kexts |
| Paths in title bars and prompts | `…/integrations/puredarwin/…` on the workstation; `/usr/standalone/PureDarwin` on an image | `…/integrations/siliconforest/…`; `/usr/standalone/SiliconForest` | the repository layout; upstream `image.nix` |
| launchd labels (`launchctl list`) | `org.puredarwin.*` | `org.siliconforest.*` | upstream `image.nix`, our job files |
| About text | none | planned: `/usr/share/doc/siliconforest/NOTICE` and an "About SiliconForest" entry in the desktop menu that opens it (section 10) | `NOTICE` at the top of the repository |
| Copyright strings in bundles | "… PureDarwin. All rights reserved." | unchanged | attribution; never renamed |

## 7. The safety-gated files

`m1-storage/kernel/pd_nvme_wgate.c`, `pd_nvme_wgate.h`, `m1-storage/kernel-rw/pd_nvme_wring.h`,
`m1-native-boot/reboot/pd_halt_gate.h` become `sf_nvme_wgate.c`, `sf_nvme_wgate.h`,
`sf_nvme_wring.h`, `sf_halt_gate.h`, with identifier substitution only.
`tools/sf_rename.py safety-proof 93738b915` shows, for each file: the new text is the old text
with the rules applied; mapping the names back gives the old file byte for byte (so every constant
and expression is the same); the lists of numeric literals are identical; no `sf` name was in the
old file. Then it compiles the old and the new units (`pd_nvme_wgate.c`, `pd_nvme_gate.c`,
`pd_nvme_wring.c` with and without the host-test macro, and a unit that emits every function of
`pd_halt_gate.h`) with the same compiler and flags and compares: section bytes identical, symbol
tables, relocation tables and disassembly identical once the names are mapped back. Result on
this workstation: all true. The compiler was the host's `gcc 16.2.1` for x86-64, not the arm64
kernel compiler; the kernel build of the same files is covered by the collection build.

## 8. Attribution

`NOTICE` at the top of the repository names every source with its licence and what was taken.
The rename never changes a line that carries a copyright or licence notice: the tool skips every
line with "copyright", "(c) year", ©, an SPDX line, "licen[sc]e", "all rights reserved", author
and sign-off lines, the permission, redistribution and warranty sentences. The proof compares
each file before the rename with the file it became, line by line, and fails when a line that
differs is such a line: `tools/sf_rename.py licence-proof <base> <head>` for this repository and
`… --tree sources/puredarwin-rebase` for the fork commit. Lines that only name a licence
identifier inside a description (a kext's `CFBundleGetInfoString`: "GPL-2.0; … at /dev/sfavd")
are renamed; the proof counts them and checks that the identifier is the same before and after. Plan: the build installs
`NOTICE` as `/usr/share/doc/siliconforest/NOTICE` with the licence texts beside it, and the
desktop menu gets "About SiliconForest", which shows it. Neither is built yet.

MIT was chosen for SiliconForest's own original code on 17 November 2026. The grant
and copyright notice are `LICENSE-SILICONFOREST-MIT`. `LICENSES/MIT.txt` is a template
with placeholders. The root `LICENSE` is a notice: the repository is not under that
licence as a whole, and adopted code keeps the licence it came with (`NOTICE`, `LICENSES/`).
Some files still need provenance review. What remains is in `docs/RELEASE_CHECKLIST.md`
and `LICENSE_STATUS.md`.

## 9. Kexts for hardware this machine does not have

The default M1 collection still carries upstream's boot kexts for other boards. Proposed for the
release collection (`rebase/build-kc.nix`, `omitKexts`), in addition to what is already left out
(`SFSerialHID`, the Tegra set, `SFGadgetFamily`, `SFFBSDem`):

| Drop | Hardware |
|---|---|
| `SFPowerVR` | Imagination GPUs |
| `SFSun60iDisplay` | Allwinner A523 |
| `SFSg2002SD`, `SFSg2002Eth` | Sophgo SG2002 |
| `SFQcomTLMM`, `SFQcomGeniI2C` | Qualcomm |
| `SFI2CFamily`, `SFI2CHID` | I2C HID of the Qualcomm laptops (only if nothing of ours links against `SFI2CFamily`) |
| `IOVirtIOFamily`, `IOVirtIOGPU`, `IOVirtIOBlock`, `IOVirtIONet`, `SFEcamPCI` | QEMU `virt`; the QEMU image has its own collection |

Not dropped without a boot on the M1. The source of all of them stays in the fork, renamed.
The collection links without these thirteen (`nix-build rebase/build-kc.nix --arg omit '[ … ]'`:
32.6 MB against 34.6 MB); that variant was built, never booted.

## 10. Re-running

    tools/sf_rename.py inventory            # names by rule, collisions
    tools/sf_rename.py apply                # this repository (idempotent: a second run changes nothing)
    tools/sf_rename.py check                # fails on an old name outside the allow-list
    tools/sf_rename.py check --tree DIR     # the same for a renamed checkout
    tools/sf_rename.py licence-proof 93738b915 HEAD
    tools/sf_rename.py safety-proof 93738b915

`sf-rename` is `main` plus two commits: the mechanical one (exactly the output of `apply` on its
parent) and the hand-written one (`NOTICE`, the README's head, the note in `AGENTS.md`, the M1
install plan, the link below, the QEMU tool's switch for the audio server). While `main` keeps
moving under old names, `sf-rename` is not merged into: it is made again from the new `main`
(`git checkout -B sf-rename main`, `tools/sf_rename.py apply`, commit, cherry-pick the
hand-written commit). `check` says when the result is clean; a new name it does not know is
classified once in the vocabularies.

`integrations/puredarwin` remains as a symbolic link to `siliconforest` (in the hand-written
commit). The frozen recovery controllers under `tools/`, the scaffold's tests and every record
name files by the old path; with the link they keep working and the required local checks of
`AGENTS.md` keep passing without a frozen file being edited. It can go when those are retired.
