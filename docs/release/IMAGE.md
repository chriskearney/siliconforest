<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Chris Kearney and the SiliconForest contributors -->

# The SiliconForest release image: what it is, how it is built, how it is checked

Status, 18 November 2026: the recipe builds the root, boot and release files and the root
boots in QEMU to the desktop, from the build outputs the owner's M1 carries; the build from a
clean clone is in progress; nothing has been published or installed. Read "What is proven"
before relying on any of it.

The owner's M1 (13-inch MacBook Pro, J293) runs SiliconForest from its own disk since
13 November 2026. Its root filesystem was assembled by hand: an upstream PureDarwin image
copied once, then several hundred installs by different work streams. Nothing could build
that root again. `release/image.nix` is the recipe that does: from this repository and the
source lock it builds the root filesystem, the boot files and the release files that an
installer writes to another machine.

## What the recipe builds

`release/image.nix` is a function of the pinned package set, the upstream base image, the
kernel collection, the two boot stages and the named build outputs of `release/packages.nix`.
It returns four things:

| Output | Contents |
|---|---|
| `rootfs` | `siliconforest-root.ext4` (the root, its contents plus 25 % and 64 MiB of room; the installer grows it to the partition), `root.manifest.tsv` (every entry: path, type, mode, owner, size, sha256 or link target), `image.json` (layers and their store paths, ext4 parameters), `layers.log` |
| `bootfiles` | `sf-stage1.bin`, `boot.bin` (stage 2 for this release's root), `kernel.kc` (the collection), `bootargs.template`, `pdsf_pack.py`, `sf_personalize.py`, `boot.json` (sizes, sha256, the release root UUID, the packing options) |
| `release` | `siliconforest-<version>-root.ext4.zst.NN` (zstd, parts below 1.9 GiB for GitHub's 2 GiB asset limit), `siliconforest-<version>-boot.tar.zst`, `siliconforest-<version>-root.manifest.tsv`, `MANIFEST.tsv`, `SHA256SUMS` |
| `qemu` | a GPT disk for QEMU's arm64 `virt` machine: the QEMU base's EFI partition and collection with this root, for the comparison run |

How the root is made (all inside the Nix sandbox, no root privileges):

1. The ext4 root of upstream's arm64 `virt` minimal image (the renamed tip, see
   `integrations/siliconforest/rebase/pd.nix`) is unpacked with `debugfs rdump`.
2. The build outputs are laid over it in the order of `release/image/layers.nix`, each at its
   prefix, with its exclusions and, where needed, only the files it names
   (`release/image/assemble.py stage`). A later layer replaces an earlier one's file.
3. The tree's own files that are installed as they are (wallpapers, `LICENSE`, `NOTICE`,
   `LICENSING.md`, `LICENSES/` under `/usr/share/doc/siliconforest`) are added;
   `release/image/remove.txt` removes the base's QEMU kernel collections.
4. The two installers of the tree that made the M1's root run against the staged root, as they
   ran on the M1: `m1-storage/system/sf-install.sh` (session, halt, clock, boot tools, dock
   items) and `m1-storage/userland/sf-userland-install.sh` (SSH, the account `sf`, the
   environment file, Homebrew's links).
5. Owners, modes and time stamps are set (`assemble.py owners`: root:wheel, 0755/0644 by the
   execute bit, the exceptions of `release/image/permissions.tsv`, every time stamp 1) and the
   manifest is written; in the same fakeroot session `mke2fs -d` makes the filesystem with a
   fixed UUID and hash seed and `E2FSPROGS_FAKE_TIME=1`.
6. The build fails unless the filesystem's feature line is exactly the M1 root's
   (`has_journal ext_attr resize_inode dir_index filetype extent 64bit flex_bg
   metadata_csum_seed sparse_super large_file huge_file dir_nlink extra_isize metadata_csum`,
   the set SiliconForest's ext4 driver has been reading since 13 November) and `e2fsck -fn`
   finds nothing.

### Where the layers come from

The order, prefixes and exclusions were read off the installed M1: a read-only listing of its
root (232,754 entries) was hashed and every file matched against the build outputs on the
workstation (`release/image/tools/classify.py`, below). Where the hand install took only part
of an output (the CGL build: one library to `/System/Library`, its dispatch libraries to the
canonical GL prefix), the layer says so with `only`.

## The installed root, classified

Every entry of the M1's root, by class (18 November 2026, kernel 50, renamed user space):

| Class | Entries | Of them files | Bytes in files |
|---|---:|---:|---:|
| built from this tree (a lab recipe's output, a tree file, a file an install script of the tree makes, or a directory or link an install made) | 12,166 | 10,956 | 547 MiB |
| upstream base (same bytes as the base image, or an upstream PureDarwin package) | 10,485 | 9,671 | 220 MiB |
| third-party, fetched (Homebrew bottles and Homebrew's own tree, Mozilla's Firefox bundle, fonts) | 55,607 | 24,212 | 1,200 MiB |
| must not ship | 154,496 | 129,839 | 15,524 MiB |
| unknown | 0 | 0 | 0 |

"Must not ship" is: the owner's data and his coding agent (`/var/root`, `/Users/sf`,
`/usr/local/lib/claude-code`), his desktop choices, dock pins and audio levels, test stages,
packets and backups under `/private/var/db/sf*` (15 GB of the total), logs and run-time state,
host keys, the remembered-network file, firmware from his machine (`/Library/Firmware`),
Apple's Terminal and Activity Monitor, every previous copy kept beside a replacement
(`*.before-*`, `*.old*`, `*.pre-*`, `*.next`), crash reports, caches, the Firefox runtime's
install receipts, logs, rollback copies and the overrides that were tried and not selected,
test programs of earlier streams whose build outputs are gone, and two tools copied in by hand.

The 212 files that matched no build output at first were identified one by one; the rules are
in `release/image/tools/classify.py` (`KNOWN`). Among them: `/usr/lib/dyld` is macos-apps-root's
dyld (36876aa6…) with one executed page rewritten by the kernel in the page cache (pointer
authentication lowering; checked page by page with the rebuild stream's `pac-lower.py`); the
cursor theme is written by the compositor itself (`--write-cursor-theme`; a release makes it at
first start, below); Activity Monitor's support libraries and tools come from
`integrations/siliconforest/activity-monitor/libs/build.sh` and `tools/`, which have no Nix
recipe yet; netd's launchd job carries `--live-after 0`, added by hand on 17 November and since
`sf-netd.c`'s default.

## What a release does not contain, and how each piece arrives

| Piece | Why it is not in the release | How it arrives |
|---|---|---|
| Wi-Fi firmware, NVRAM, CLM, txcap (`/Library/Firmware/brcm`), the Touch Bar and video decoder firmware (`/Library/Firmware/apple`) | Apple's firmware, no redistribution right | the installer copies them from the target's own Asahi Linux firmware into the two (empty) directories the root ships with, before the root is written |
| Mozilla's Firefox bundle (`/Applications/Firefox.app/Contents/Resources/Mozilla.app`) and the outer bundle's `Info.plist` (it copies keys of Mozilla's) | redistribution under Mozilla's terms is not settled (the trademark policy restricts a patched build under the Firefox name) | fetched at install time from Mozilla (`firefox/acquire.py`: the DMG release.json's `mozilla_sha512` names, Mozilla's SHA512SUMS); the runtime around it is ours and in the root (below) |
| Terminal.app, Activity Monitor.app and anything taken from them | Apple's applications | the user copies them from their own macOS with a helper (INSTALL) |
| Homebrew bottles beyond the system's set | each bottle's own licence | the person installs them with `brew` (the client ships) |
| host keys | per machine | made at the first start of the SSH server (`sf-sshd`) |

## Homebrew in the root

`/opt/homebrew` ships in the root (`release/image/homebrew.nix`): the system's set of formulae
(m1-storage/tools/sf_userland_push.sh `SF_FORMULAE`: what the root's own programs call, Firefox's
launcher on `python@3.14`, `/bin/bash`, `make`, `sqlite3`, the brew client's `git`, and the tools of
a usable shell) with its dependency closure, 63 bottles pinned by sha256 in
`release/image/homebrew.lock.json` and fetched from Homebrew's public registry, the brew client
(Homebrew/brew at a pinned revision, BSD-2-Clause) and its portable Ruby. `homebrew/hb_pour.py`
pours and relocates them as on the M1, owner 501:20. Every keg's licence is in the lock and in
`/opt/homebrew/.sf-licences.tsv`; by count: MIT 15, GPL-3.0-or-later 11, Apache-2.0 4,
BSD-2-Clause 4, Apache-2.0 OR MIT 4, BSD-3-Clause 3, GPL-2.0-or-later 2, and single ones
(Python-2.0, Ruby, MPL-2.0, ISC, blessing, Unicode, LGPL-3.0-or-later, GPL-3.0-only, GCC's runtime
exception, combinations). The M1 has ten more kegs the owner added with `brew` (neovim, lua, vim, ...):
they are his, not the system's. Built from the lock, the prefix equals the M1's for every one of
the 48,298 files and links they share but one, Python's framework library, which is the same
file with three executed pages lowered by the kernel (`pac-lower.py`).

## First start on another machine

- Host name `siliconforest` (upstream's `sf-set-hostname` job).
- Accounts: `root`, whose shell is zsh, and `sf` (uid 501, group staff), the account the
  desktop's user programs and Homebrew run as, without a password (as on the M1). Setting a
  password or adding a person's own account is the installer's question to ask.
- No remembered networks: `/Library/Preferences/SystemConfiguration` exists and is empty, so
  `sf-netd` joins nothing until a network is joined once (`wifiutil`).
- Firmware is looked up at `/Library/Firmware/brcm` and `/Library/Firmware/apple`.
- The desktop session (`org.siliconforest.desktop`), the dock with its default pins and the
  forest wallpaper, as `sf-install.sh` sets them; DejaVu Sans (2.37, from nixpkgs, with its
  licence) where the desktop reads it.
- `org.siliconforest.firstboot` runs `/usr/libexec/sf-firstboot` at every start; it acts only
  when its result is missing: today it writes the pointer set (`/usr/share/icons/default`)
  with the compositor, as the owner's M1 has it.

## Firefox's runtime

`release/image/firefox-runtime.nix` lays out what `firefox/prepare-install.py --system-layout`
and the install scripts made on the M1: the 13 providers of `release.json`'s `recipes`, built
from those recipes with the recorded arguments (AppKit, Onyx2D and CoreText as `Frameworks/`,
AppKit's `Versions/C` link), the three selected overrides (`network-v1`, `audio-clock-v1`,
`video-clock-0172-v1`, their `Frameworks/` only), `release.json` written from
`release/image/firefox-selection.json` (the choices; the records are recomputed), the launcher
`Firefox.app/Contents/MacOS/firefox-sf` (`firefox/daily-launch.py`) with `system-runtime.json`,
and the desktop entry. Fed with the build outputs the M1 carries, it gives 840 of the M1's
entries byte for byte; the rest are the receipts, logs, rollback copies and unselected overrides
it leaves out by design, `release.json`'s records (store paths) and two files of a later build
in `video-clock-0172-v1`. The launcher's dry plan (`firefox-sf --sf-plan`) against this tree,
run on the workstation in a private mount namespace, is the M1's plan exactly, except the
per-process service name and the profile directory under the caller's home.

## The boot files and the target's identifiers

The boot partition (FAT, label `SFBOOT`) holds `sf/boot.bin` (stage 2) and `sf/kernel.bin`
(the configuration record and the collection). They are a pair and are installed together.

- Every release has one root filesystem UUID, derived from its version
  (`release/identity.nix`). The root image carries it; stage 2 is built for it
  (`release/boot-stages.nix { rootUUID = identity.rootUUID; }`) and keeps its exact-root rule:
  it boots that UUID and no other. The installer does not change the root's UUID.
- The kernel arguments name the target's own partition (`sfnvme_part`, its first block and
  length). `bootargs.template` is install/build.sh's command line with four fields;
  `sf_personalize.py` fills them in (the release root UUID and the three partition values the
  installer reads from the target's partition table) and packs `sf/kernel.bin` with the
  release's own `pdsf_pack.py`, then checks both records and that each identifier occurs once.
  No identifier of any machine is in a release file.

## Rules for writing the root

The ext4 driver of kernels before 50 left metadata that Linux's `e2fsck` rejects (issue #61).
So: Linux writes a SiliconForest root only as a whole new image (the installer's `dd` of a
verified image, then `resize2fs` and `e2fsck -fn` on it, before SiliconForest ever starts on
it), and never mounts an existing SiliconForest root read-write unless `e2fsck -fn` has just
found it clean. The release's own image is made by `mke2fs` and checked by `e2fsck -fn` in the
build.

## Packaging, checksums and signing

`MANIFEST.tsv` lists every release file with its size and sha256, plus the size and sha256 of
the uncompressed root. `SHA256SUMS` lists every file including the manifest. The recipe does
not sign: the owner signs `SHA256SUMS` with his release key,

    ssh-keygen -Y sign -f <release key> -n siliconforest-release SHA256SUMS

and the installer, which carries the public key in an allowed-signers file
(`release@siliconforest namespaces="siliconforest-release" ssh-ed25519 ...`), checks it with
`release/image/sf_verify_release.py`: the signature, every file's sha256, then the parts
decompressed and hashed against the uncompressed line. SSH signatures need nothing beyond
OpenSSH, which macOS and Linux both have. No key exists yet: making it is the owner's step.

## Licence questions, by artifact (the owner decides; nothing is published until then)

| Artifact | What in it carries a question |
|---|---|
| `boot.tar.zst`: `kernel.kc` | an APSL-2.0 kernel linked with GPL-2.0 kernel extensions (the PCIe host bridge and DART ported from Linux, the Asahi-derived display and GPU pieces) in one collection; corecrypto is the MPL-2.0 open reimplementation (Vali0004/corecrypto), not Apple's, but its "experimental, unaudited" status should be stated |
| `boot.tar.zst`: `sf-stage1.bin`, `boot.bin` | m1n1 (MIT) and our stage-2 code (MIT): no question known |
| `root.ext4` | the Homebrew bottles (63 formulae, licences above; GPL-2.0 and GPL-3.0 ones need a source offer: bash, coreutils, gawk, grep, gnu-sed, gnu-tar, findutils, make, nano, wget, gettext, readline, gmp, mpfr, libunistring, libidn2, git, ...); DejaVu fonts (Bitstream Vera licence, its text installed beside them); Noto Thai (OFL-1.1, beside them); the same GPL-2.0 kexts as on-disk bundles in `/System/Library/Extensions`; GPL binaries needing a source offer (the Chonkstep desktop GPL-3.0-only, FFmpeg with x264, Perl under Artistic or GPL, the Darling-derived Metal pieces); fonts (each needs its licence text beside it); whatever upstream PureDarwin ships under Apple's binary driver licence (not established) |
| `root.manifest.tsv`, `MANIFEST.tsv`, `SHA256SUMS` | none: paths, sizes and hashes |

Firmware, Apple's applications and Mozilla's bundle are in no artifact.

## What is proven, and how to check it

All of this was done on the workstation, 18 November 2026, with the build outputs the M1 itself
carries (the local driver `runs/image/local.nix`, not committed: store paths). The from-clone
build of `release/packages.nix` was not finished when this was written.

- **Root image** builds; its own checks pass (the M1 root's exact ext4 feature line,
  `e2fsck -fn` clean, both installers rc 0). `nix-build --check` rebuilt the root, the boot
  files and the release files a second time to the same bytes (same machine, same inputs; a
  build on another machine is CODEX-BUILD's from-clone check).
- **Compared with the M1** (`compare.py`, the build with Homebrew, the Activity Monitor libraries,
  the Thai fonts and the Finch frameworks): 71,942 entries the same. 48 files differ in content,
  each explained: 20 files of an older build of the Cocoa root the M1 still carries, others of
  other builds of the same Finch, kernel-header, macOS-apps and Activity Monitor recipes (the
  M1's Activity Monitor libraries are an earlier build of the same sources), the rename
  stage's newer files, `dyld` the image's own with one page lowered by the kernel, the DejaVu
  fonts (another release of the font), `*.xnu` (the pre-rename base's halt/reboot), netd's
  hand-edited job, `release.json`'s records. 12 entries differ in type: framework links in the
  image where the M1 has flattened copies. Present only on the M1, outside what must not ship:
  the ten Homebrew kegs the owner added himself, Mozilla's bundle (install time), the pointer
  set (first start). Homebrew alone: 48,297 of the 48,298 shared files and links are
  identical; the other is Python's library with three pages lowered by the kernel. Present
  only in the image: files of whole build outputs the hand install did not copy (headers, man
  pages, licences). Modes: 6,448 files read-only (0444) on the M1 are 0644 in the image; the
  M1's copies came from the Nix store by hand.
- **Boot and release files** build: release 0.1.0 is a 2.2 GB root (292 MB as one zstd part),
  an 8.6 MB boot archive, the manifest, `MANIFEST.tsv`, `SHA256SUMS`. `sf_verify_release.py`
  accepts them unsigned and with an SSH signature by a throwaway key, and refuses a changed
  `SHA256SUMS`. `sf_personalize.py` packs `sf/kernel.bin` from the real boot files with
  invented partition values; both records check; `boot.bin` is copied unchanged.
- **QEMU** (`release/image/qemu/prepare-run.sh`, then `run-vnc.sh`; arm64 `virt`, TCG, four
  vCPUs, host load 25 to 60): the kernel finds the root by the release's UUID and mounts it;
  launchd starts the root's jobs, the SSH server makes its host key, `sf-firstboot` writes the
  pointer set (83 cursors, its log); perl, zsh and ssh run. With the compositor patch
  `wm-darwin-app-ready-deadline-env.patch` and the QEMU run's longer deadlines, the terminal
  starts, reports ready and its window is on screen with the shell's prompt (pictures through
  QEMU's VNC server, runs 9, 10 and 16: `runs/image/qemu/run16/shots`). The dock starts (its log),
  but no picture shows it: the terminal fills the 800x600 screen. Typing is not shown: every run
  in which keys reached the guest (through the emulated USB keyboard over VNC, or the autopilot's
  synthetic records) and several without ended with the compositor killed by SIGBUS. A core dump
  (run 16) places it in `wm_darwin::presenter::Scanout::write_damage`, writing into the
  firmware framebuffer's mapping, which the dump reports unreadable: the QEMU graphics path
  (IOGOPFramebuffer on ramfb), not a file of the root. It happens with the M1's own compositor
  build as well, at 800x600 and 1024x768, with and without the kernel's framebuffer console.
  Open, for the desktop's and the QEMU loop's owners.
- **Firefox's runtime**: 840 entries byte for byte with the M1's; the launcher's dry plan equals
  the M1's. Firefox itself was not started (no Mozilla bundle, no Homebrew in the image).
- Not done: an install on any machine; the from-clone build and its reproducibility.

## Tools

- `release/image/tools/list-meta.pl`: the read-only listing of a root (lstat only; runs on the
  M1's Perl, nothing else needed). Hashes are taken in a second pass over a file list.
- `release/image/tools/classify.py`: the classification above, from the listing, the hashes,
  the base image's listing and hash indexes of build outputs and of the tree.
- `release/image/compare.py`: built root against a classified listing.
- `release/image/sf_personalize.py`, `release/image/sf_verify_release.py`: for the installer.
