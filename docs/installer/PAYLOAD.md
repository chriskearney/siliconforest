<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Chris Kearney and the SiliconForest contributors -->

# SiliconForest Installer: the shippable release payload

Companion to [`DESIGN.md`](DESIGN.md) (sections 8.3, 10 and 16) and [`ENGINE.md`](ENGINE.md) (S10 to S52). Started
24 November 2026 with Chris's go, **with the real-disk write switch off**. Code: [`installer/payload/`](../../installer/payload/).
Tests: [`tests/test_installer_payload.py`](../../tests/test_installer_payload.py). CI: `.github/workflows/installer-payload.yml`.

> **Status, milestone P1.** Everything here runs on ordinary files, disk images and the M5. Nothing has written to a real
> disk, touched the Air, or booted. Section 11 says what is proven, and section 12 says what is left.

## 1. What a release is

One directory, the assets of one GitHub release. Every file is listed in `SHA256SUMS`, which is signed.

| File | Role |
|---|---|
| `siliconforest-V-root.ext4.xz.NN` | The installer root (section 3), xz, split below 2 GiB. The parts concatenate to one stream |
| `siliconforest-V-root.manifest.tsv` | Every entry of that root: path, type, mode, owner, size, SHA-256 |
| `sf-stage1.bin`, `boot.bin`, `bootargs.template` | Stage 1, stage 2 and the boot-argument template, as built |
| `kc-builder`, `LICENSE.kc-tools`, `kc.kernel`, `kc.<kind>.<Bundle>.kext.<path>` | The kernel collection as separate files, linked on the Mac (section 13): the signed macOS linker and its BSD-3-Clause licence, the kernel, and every file of every driver bundle. **The collection itself is not in a release** |
| `install.json` | `siliconforest-install/3`: sizes, hashes, slot offsets, growth limit, profiles, and the **names, sizes and SHA-256 of the Apple firmware the installer must extract on the Mac** |
| `SHA256SUMS`, `SHA256SUMS.sig` | Every file's hash, and an SSH Ed25519 signature over it, namespace `siliconforest-release` |

No Apple file is in a release. (The kernel and the kexts are built from open source, some of it Apple's; they are the
separate inputs of section 13, published under the distribution decision, DESIGN D13.) Firmware and the stub's files come from Apple's 13.5 restore image on the user's Mac (D7).
Their digests are in the release so the extraction is checked before the first write.

## 2. Build pipeline

```
release/image.nix (rootfs) ──► prepare_root.py ──► installer root + root.json
                                     │
                         grow_check.py (proof only)
                                     │
boot files ─┐                        ▼
names.tsv ──┼──────────────► make_release.py ──► release dir, signed
profiles ───┘                        │
                                     ▼
                           verify_release.py  (and, next, the Swift verifier at S10–S15)
```

`rehearse.sh OUT` runs all of it on a synthetic root, or on a real one with `--base`.

## 3. The installer root

`prepare_root.py BASE OUT` copies the release root (`siliconforest-root.ext4` + `root.manifest.tsv`, the output of
`release/image.nix` on the `release-image` branch) and adds, through `debugfs` on the file only:

| Entry | Bytes | What |
|---|---|---|
| `/private/var/db/sf-firmware-slot` | 32 MiB | One contiguous **initialised** extent. Header `SFFWSLOT1`. The installer writes the extracted firmware here at S50 |
| `/private/var/db/sf-boot-receipt` | 64 KiB | One contiguous initialised extent, all zeros. The installer writes the header at S52 |
| `/usr/libexec/sf-installer-firstboot` | | The first-start job (section 4) |
| `/usr/libexec/sf-boot-receipt` | | Writes one receipt stage, in place, with `fsync` |
| `/usr/libexec/sf-unpack-firmware` | | Validates the slot (length, SHA-256, names) before touching `/Library/Firmware` (from the `image-install` branch) |
| `org.siliconforest.firstboot.plist` | | Now runs `sf-installer-firstboot`, which ends by running the release's own `sf-firstboot` |

Each slot is written as `0xff` first so `debugfs` allocates real blocks, then the extent tree is read
(`debugfs extents`) and must be **one extent, not marked uninitialised**, and the raw bytes at that physical offset must be
the file's. Then the final contents are written there. Every entry is read back with mode and owner, and `e2fsck -fn` must
be clean. `root.json` records the image size and SHA-256, the filesystem UUID, both slots' physical offsets and the
growth limit.

On the real 0.1.0 root (`siliconforest-rootfs-0.1.0`, 2,173,026,304 bytes, store path `0gzy6hbx…`) on the i9:

| | Value |
|---|---|
| Firmware slot offset | 1,729,200,128 |
| Receipt slot offset | 1,762,754,560 |
| Installer root SHA-256 | `ce208533…6b85` |
| `e2fsck -fn` | clean: 72,474 / 112,880 inodes, 430,796 / 530,524 blocks |
| Growth limit | 2,233,382,993,920 bytes (259 reserved GDT blocks) |

## 4. First start and the boot receipt

The receipt follows DESIGN section 8.3. The installer writes `SFRCPT1\ninstall=<32 hex>\n` into the zero slot through the
raw partition at S52 (`receipt.write_header`, which refuses a slot that is not all zeros). In SiliconForest,
`sf-installer-firstboot` runs at every start from launchd and is idempotent:

1. Records `root-mounted` (only if `/` is ext4) and `launchd-up`.
2. Installs the slot's firmware into `/Library/Firmware` once, and records `firmware-installed`.
3. Runs the release's own `/usr/libexec/sf-firstboot`.
4. Waits up to 600 s for the desktop session's Wayland socket (`/private/var/run/gpu-desktop/wayland-0`) and records
   `desktop-ready`.

`sf-boot-receipt` writes `<stage> <unix time>\n` at the first NUL byte, never truncates or reallocates, refuses bytes after
the end, writes a stage once, and does nothing (exit 3) without the installer's header, so a development install is never
touched. Back in macOS, `receipt.classify` gives `installed`, `partial:<stage>`, `empty`, `foreign` or `invalid`. It is the
reference for the Swift reader, which is not written yet.

## 5. The first-boot account (not built)

What the 0.1.0 root does today, read from the image:

- Every account is locked (`*` in `master.passwd`), including `sf` (uid 501).
- The desktop session (`org.siliconforest.desktop` → `sf-session`) runs **as root** without a login.
- The console runs a root shell with no login (`/etc/ttys` and `sf-console-login`).
- `sshd` accepts only public keys, only for root, and the image has no authorised key.

So nobody can log in remotely, but anyone at the keyboard is root. That is acceptable on the developer's own Mac and not on
anyone else's (DESIGN section 16, item 4). The fix belongs to the system, not to the installer:

1. A first-start screen in the desktop that creates the owner's account (full name, short name, password), with the desktop
   held until it exists.
2. The session started as that user after a login, with an administrator path for root work.
3. The console shell behind `login`.

The installer's part is small: install.json gains `account: "first-start"` and the Verified screen waits for an
`account-created` receipt stage. **None of this is implemented.** It needs a Darwin boot to test (the QEMU virt machine
first), and it is the largest piece of open work here (section 12).

## 6. Root growth

Decision for P1: **the helper grows the filesystem offline, from macOS, before the first start**. This is new step **S48
root-grow**, after S47's full read-back and before S50 and S52.

- The release root is built at its content size plus slack. `install.json` declares `sizing: "grow"` with `min_bytes` set
  to the image size and `grow.max_bytes` set to the reserved GDT blocks' limit.
- S48 runs `resize2fs` on the unmounted raw root partition (the job's own partition, so the gate already allows it), then
  `e2fsck -fn`. The idempotent check is "the superblock's block count equals the partition's".
- Growing into reserved GDT blocks moves no existing block. That is why the slot offsets in install.json stay valid. It is
  proven below and rechecked by `grow_check.py`.

Why not at first start: the Darwin ext4 driver has no online resize, and the root cannot be resized offline while it is
the root. Why not a Swift grower: it would be new filesystem code on the riskiest path, whereas `resize2fs` is the
reference implementation.

Cost, for Chris to decide: `resize2fs` is GPL-2.0 (e2fsprogs). Shipping a macOS build of it inside the dmg means a GPL
binary in our release, with its source offer. The alternative is a restricted Swift grower, tested differentially against
`resize2fs`, at about 1 to 2 weeks.

Proven on files: the real 0.1.0 installer root grown to **96 GiB** (25,165,824 blocks), `e2fsck -fn` clean, both slots one
extent at the same offsets with the same bytes, UUID unchanged. Not yet proven: that the Darwin ext4 driver mounts a root
grown this way. resize2fs leaves new groups `INODE_UNINIT` and `BLOCK_UNINIT`, which the driver's code handles but no boot
has exercised. That needs a QEMU or G6 boot.

## 7. Release trust

As DESIGN section 10, made concrete:

- `make_release.py` signs `SHA256SUMS` with `ssh-keygen -Y sign -n siliconforest-release`.
- `verify_release.py` checks the following, failing closed at the first problem:
  1. The signature, against an `allowed_signers` file.
  2. `SHA256SUMS` lists every file and only those, with no paths or links.
  3. Every SHA-256.
  4. install.json agrees with `SHA256SUMS` on every artifact's size and hash.
  5. Slots are inside the image, aligned and not overlapping, and the growth limit is above the image.
  6. The root parts decompress to exactly `image_sha256`.
- **The release key.** Chris made the offline Ed25519 release key on 24 November 2026. Its fingerprint
  (`SHA256:y5XAQCFbvtrcB7JG73cXZajUSTrIOewSASbcoVKspQc`) is in `sfrelease.RELEASE_KEY_FINGERPRINTS`, and its
  `allowed_signers` line is `installer/payload/release/allowed_signers`. The private key stays offline and is never committed.
- `make_test_key.sh` makes a throwaway key whose comment says `TEST-ONLY`. A rehearsal must be signed by such a key, and such
  a key can sign nothing else. install.json records `rehearsal: true`, and the verifier refuses a rehearsal unless asked
  with `--allow-rehearsal`. Test keys are made in a temporary directory and never committed.
- The channel file (`channel.json` + `.sig`, sequence numbers) is not built yet. `install.json` carries `sequence` for it.
- In the engine, S15 today hashes artifacts against a `ReleaseManifest` it is given. The Swift side still needs the
  signature check and the install.json mapping (`SFRelease`, section 12). The Python verifier is the reference it will be
  tested against.

## 8. Firmware from Apple's 13.5 restore image

`firmware/extract_firmware.py --profile installer/profiles/J313.json --work DIR` runs on a Mac:

1. Opens the profile's restore image URL. Only the needed ranges are fetched: every response must be HTTP 206 with the exact
   `Content-Range`, and the remote size must equal the profile's (`remote_zip.py`, zip64).
2. Reads `BuildManifest.plist`, checks version and build (13.5, 22G74), and selects exactly one build identity by board,
   chip, device class, behaviour and variant.
3. Streams that identity's BaseSystem dmg (CRC-32 and size checked) and attaches it read-only with
   `hdiutil attach -readonly -nobrowse`. It is a disk image, so no disk of the Mac is touched.
4. Names the Wi-Fi firmware with `firmware/wifi.py`, a port of Asahi v0.9.2's `asahi_firmware/wifi.py` (MIT, notice kept),
   and keeps what the profile's items ask for.
5. Writes `firmware-slot-<board>.bin` (header + a ustar archive that `sf-unpack-firmware` accepts) into DIR, and a names
   file with board, name, size and SHA-256.

The names file is committed: [`firmware/names/13.5-22G74-J313.tsv`](../../installer/payload/firmware/names/13.5-22G74-J313.tsv).
The firmware never is.

Run on the M5 on 24 November 2026 for J313:

- BaseSystem `022-15462-082.dmg` (1,815,115,416 bytes). 652 MB were fetched instead of the 12.9 GB image.
- Five Wi-Fi files, the same five the Air's Linux uses. All five SHA-256s equal the Air's own Asahi `vendorfw` manifest
  (from the 22 November backup), including `shikoku.bin` = `c1c8e9ac…`.
- **Differential against Asahi v0.9.2:** the original collector and the port, run on the same mounted BaseSystem, give the
  same 276 names with the same hashes.
- The slot unpacked with macOS's own perl through `sf-unpack-firmware` gives the same five files and hashes.

Not done: J293's Touch Bar firmware (`multitouch.py` and its img4 and ASN.1 parsing, about 1,000 lines), so the J293
extraction stops with "no extractor yet". The Swift port for the installer (`SFFirmware`, DESIGN section 17) is also not
done; the Python tool is its reference.

## 9. SFStub (milestone M1 done)

**Decision, Chris, 24 November 2026, 3:27 PM PT: full Swift port, NO Asahi fallback** (DESIGN section 6.4). The Python
0.9.2 code and any Python runtime are never shipped, bundled or integrated. Asahi v0.9.2 runs only as the reference
oracle in tests on the M5 or the i9, against disk images. Ported files carry Asahi's MIT attribution
([`LICENSES/third-party/asahi-installer-LICENSE.txt`](../../LICENSES/third-party/asahi-installer-LICENSE.txt)). No
newer Asahi code (possibly GPL) is used or read.

`installer/mac/Sources/SFStub` is the Swift port of Asahi v0.9.2's `stub.py`, `urlcache.py` and the stub parts of
`osinstall.py` and `util.py` (tag `v0.9.2`, commit `dffbb38e`). `sfstubctl` drives it on disk images only (every
`diskutil` target goes through `ImageGuard`). The pieces:

- `RangeSource`: https range reads with the 206 and exact `Content-Range` rule, the profile's size checked against
  HEAD, a bounded block cache. `ZipReader`: zip64, raw DEFLATE through Apple's Compression, CRC-32 and size checks.
- `RestoreImage`: version and build check, exactly one identity from the profile, the trimmed `BuildManifest.plist`
  written byte for byte as Python's `plistlib` writes it.
- `StubPlanner`: upstream's actions in upstream's order, as data. `StubStager`: downloads and checks every member the
  plan needs **before the first disk write** (DESIGN D6): 57 members (1,881,234,156 bytes unpacked), 710,035,591 of the
  image's 12,893,195,726 bytes fetched (the rest is never read).
- `StubWriter`: the plan written with Python's file semantics (`makedirs`, `copy`, `copytree`/`copy2`), the
  Recovery `arm64eBaseSystem.dmg` as a decmpfs LZFSE resource fork, the System volume's FinderInfo and bootable
  flag, `schg` on the admin-user plist, and the m1n1 boot object with its variables.

**M1 result (M5, macOS 26.5, 24 November 2026, runs `stubdiff-20261124-160316` and `-160821`):** on the 13.5 (22G74)
j313ap image, Asahi v0.9.2 and SFStub each built the 2,499,805,184-byte `SiliconForest` container on its own sparse
disk image. `scripts/stub-differential.sh` dumped both: 115 entries vs 115 (65 files, 1,881,590,626 bytes as read),
**0 differences** in paths, types, modes, owners, BSD flags, every xattr (decmpfs header and compressed resource fork
byte for byte), SHA-256 of contents, symlink targets, volume names, roles, volume group, encryption, bootable flag
and container size. The 23-command sequences (diskutil, xattr, fsctl, chflags, m1n1 build) are equal and match the
committed `Tests/StubDifferential/fixtures/asahi-v0.9.2-commands.txt`. Both sides got Asahi's own step2 payload and
a synthetic icon and stage 1, so the trees are comparable.

The normalisations, the complete list (anything else that differs fails):

| | What | Why |
|---|---|---|
| N1 | The volume group UUID → `<VGID>` in paths, symlink targets and file contents | Random per container |
| N2 | The Preboot volume UUID → `<PREBOOT_UUID>` in file contents (step2.sh) | Random per container |
| N3 | Mount points → `<System>`, `<Data>`, `<Preboot>`, `<Recovery>` in symlinks and commands | Chosen by macOS |
| N4 | Timestamps and inode numbers are not compared | Wall clock |
| N5 | `.fseventsd`, `.Spotlight-V100`, `.Trashes`, `.TemporaryItems`, `.DocumentRevisions-V100` at a volume root are listed, not compared | Created by macOS on mount |
| N6 | Disk identifiers in the command sequence → the volume's role | Chosen by macOS |

In the M1 runs only `step2.sh` needed N1/N2, and only `.fseventsd` (Data, System) was excluded by N5.

Deliberate differences from upstream, none visible in the tree: the range and size rules above; staging before any
write; upstream's "Multiple volumes" check (which compared string keys against tuple keys, so never fired) and its
`rstrip(" - Data")` (which strips characters, not the suffix) fixed; full IPSW (Erase) only, no OTA paths; firmware
collection left to `SFFirmware`; the step2 app, logo and m1n1 object come in as a payload.

Tests: `StubReaderTests` and `StubBuildTests` (in `SFInstallKitTests`) run on a synthetic restore image built in the
test, with no Apple bits, in CI (`installer-mac.yml`, job `stub`). The real-image differential test is skipped there
with its reason; run it on the M5 with `installer/mac/scripts/stub-differential.sh` (needs root, the staged image
members and the pinned Asahi checkout).

Not yet done (SFStub M2–M5): the production SiliconForest payload (Setup app, `sf-launcher`, `SFRecovery`, plan.json,
stub_info) in place of Asahi's step2 app; the engine's S30/S35 calling SFStub through the image chokepoint and helper
verbs, with journal and resume; progress and fault injection; and a real-hardware run (G5/G6, with Chris). Boot
personalization and Recovery pairing cannot be proven on images.

The supported IPSW range is the profiles' single entry, 13.5 (22G74).

## 10. Rehearsal releases in CI

`installer-payload.yml` runs the tests, then `rehearse.sh` on a synthetic root (same ext4 features as the release root,
no SiliconForest binaries) with placeholder boot files and a throwaway TEST-ONLY key. It also checks that a rehearsal is
refused without `--allow-rehearsal` and that a tampered copy is refused. It uploads and publishes nothing.

The real-root rehearsal runs on the builder:

```sh
installer/payload/rehearse.sh OUT --base <rootfs store path> --boot <boot dir> --grow $((96<<30))
```

Run on the i9 on 24 November 2026, as release `0.1.0-rehearsal.1`, signed with a TEST-ONLY key that was then left in the
work directory:

- Base: the real 0.1.0 root.
- Boot files: stage 1 and stage 2 from the 0.1.0 release, and the J313 G1 installed-system kernel collection `b3115d93…`.
- Firmware names: J313's.
- Result: the root compressed to one 301,952,196-byte xz part in 68 s, and the deep verification passed in 6 s, including
  the decompressed root's SHA-256.

It is a rehearsal of the tooling only. **It has not been booted, and its boot files are not a tested J313 install set.**

## 11. What P1 proved, and how

| Claim | Evidence |
|---|---|
| The installer root can be made from the real release root without modifying it, with both slots contiguous and initialised, and stays fsck-clean | `prepare_root.py` on `siliconforest-rootfs-0.1.0` (i9). Tests on a synthetic root |
| It grows in place to a partition's size without moving the slots | `grow_check.py`: 2.17 GB to 96 GiB on the real root. Tests |
| The receipt writer appends once, in place, fsynced, and leaves non-installer roots alone | Tests run the perl writer and the Python classifier |
| Firmware extraction from Apple's 13.5 image is correct for J313 | Same hashes as the Air's Asahi `vendorfw`. 276/276 differential against Asahi v0.9.2. Unpacked by macOS perl |
| A release is signed and every artifact verified before use, and tampering, unlisted files, another key, a swapped install.json, or a test key on a real release are refused | Tests. CI rehearsal |
| SFStub builds the same stub content as Asahi v0.9.2 from the 13.5 image by range reads | Differential test on disk images on the M5: 0 differences, equal command sequence (section 9) |
| Not proven | Any boot of the installer root. Darwin mounting a grown root. The receipt written by a real first start. The Swift verifier and reader. A stub built by SFStub booting on hardware |

## 12. What is left

| Item | Work | Estimate | Needs Chris? |
|---|---|---|---|
| Swift `SFRelease`: sshsig Ed25519 verify (CryptoKit), install.json → `ReleaseManifest`, wired in before S10 | Code + tests against this verifier | 2–3 days | No |
| S48 root-grow in the engine, and the macOS `resize2fs` build | Code, image tests on the M5 | 2–3 days | **Yes: GPL binary in the dmg, or a Swift grower** |
| Swift receipt reader and firmware-slot writer, matched to `receipt.py` and the slot format | Code + tests | 2 days | No |
| Boot the installer root, grown, in QEMU virt: receipt stages, firmware install, fsck afterwards | Builder + QEMU | 2–4 days | No |
| First-boot account (section 5) | System work in the desktop, session and console | 1–2 weeks | **Yes: the design of the account screen** |
| SFStub M2–M4: production payload, S30/S35 engine wiring with journal and resume, progress, fault injection (M1 done, section 9; no fallback, DESIGN §6.4) | Code, image runs on the M5 | 1.5–2.5 weeks | **Yes: sign-off on the normalisations; G5/G6 hardware go for the real run** |
| J293 Touch Bar firmware extraction (`multitouch.py`) | Port + check | 2–3 days | No |
| `SFFirmware` (Swift) for the installer itself | Port of `extract_firmware.py` | 3–4 days | No |
| Rebuild the release root from the current integration line (DESIGN section 16, item 1) and the J313 boot files | Builder | 1–2 days of builder time | No |
| Channel file, rollback protection, two public keys in the app | Code | 2 days | No |
| **The offline release signing key** | **Done 24 Nov 2026:** made offline on the M3; fingerprint in `sfrelease.RELEASE_KEY_FINGERPRINTS`, line in `release/allowed_signers` | | Done |
| Distribution terms for the kernel collection and root (RELEASE_CHECKLIST blocker 4) | **Decided by Chris, 24 Nov 2026:** free to download and open source before any public release (DESIGN D13) | | Done; the GPL/APSL presentation detail stays open in RELEASE_CHECKLIST 4 |

## 13. Kernel collection: linked on the Mac

Started 24 November 2026 (Chris, voice 3:54 PM PT). A release no longer ships one prelinked collection (`kernel.kc`).
It ships the collection's inputs as separate hashed files and the exact link options, and the installer links them
on the user's Mac. Code: [`installer/payload/release/kc_release.py`](../../installer/payload/release/kc_release.py) (the
reference the Swift engine is tested against), the tool: [`integrations/siliconforest/kc-builder/`](../../integrations/siliconforest/kc-builder/README.md).

**Same bytes on both hosts.** kc-builder sorted its symbol table with `qsort`, which orders equal names differently
on glibc and Apple's libc, so a duplicated symbol bound differently on macOS. `kc-tools-sym-order.patch` makes the sort
stable; the J313 installed-system collection is `b3115d93…` from Linux `nix-build` and from the macOS kc-builder alike
(the kc-builder README has the proof, and the G2 collection too).

**In the release** (`make_release.py --kc-inputs --kc-builder [--kc-link-tool] [--kc-expect]`):

| Artifact | Role | What |
|---|---|---|
| `kc-builder` | `kc-tool` | `build-macos.sh`'s binary: Developer ID signed with hardened runtime in a release; ad-hoc in a rehearsal |
| `LICENSE.kc-tools` | `kc-tool-license` | kc-tools' BSD-3-Clause licence, shipped with the binary |
| `kc.kernel` | `kc-kernel` | the kernel |
| `kc.kexts.<Name>.kext.<path>`, `kc.codeless.<Name>.kext.<path>` | `kc-bundle-file` | every regular file of every bundle (Info.plist, executable, NOTICE…), one artifact each, `/` written `.` |

`install.json` → `kernel_collection` (`siliconforest-kc/1`): `tool` (artifact, signing, licence), `kernel`, `bundles`
(in link order: directory, and each file's path, artifact and mode), `link_args` (kc-builder's options exactly: inputs as
relative paths, the output as `@OUTPUT@`; only `-kc-base`, `-kernel`, `-kext`, `-codeless`, `-o` are allowed),
`kc_base`, and **`collection_sha256` / `collection_bytes`**: what the linked collection must be. `make_release.py` computes
them by linking the same files with the same options on the builder (`--kc-link-tool`, the Linux kc-builder of
`build-tools.nix`); `--kc-expect` cross-checks against the recipe's own collection. The collection is never written into
the release directory; its hash is signed with everything else.

**Verification** (`verify_release.py`, `kc_release.check_section`): every kc artifact listed with its role and none
unused; the bundles exactly `link_args`' bundles, in order; artifact names derived from paths; no `..` or unusual path;
no option outside the format; a release (not a rehearsal) must ship a Developer ID signed kc-builder.

**Assembly on the Mac** (engine S17, before the first disk write; `kc_release.assemble`): copy each input from the
verified download into a fresh private directory, re-hashing each against the signed hash as it is copied; the tool too;
run kc-builder with exactly `link_args` (fixed `PATH`, no other environment, a timeout); accept the output only if it has
exactly `collection_sha256` and `collection_bytes`, else delete it and stop. kc-builder's "link_kext failed (skipping)"
does not exit non-zero, so this hash is the check that catches a skipped kext. **S42** packs the accepted collection into
PDSF records (CONFIG with the personalised boot arguments, KERNEL gzip, END: `pdsf_pack.py`'s format) as `sf/kernel.bin`,
and only then writes it to SFBOOT, through the gate and the disk backend like every other write.

**Rehearsals.** Without real inputs, `rehearse.sh` makes synthetic ones and links them with
`release/rehearsal_kc_builder.py`, a stand-in that hashes its inputs (signing `rehearsal-stand-in`, refused outside
rehearsals). On the builder, with real inputs (24 November 2026, i9, `~/sf-payload-work/kc-rehearsal/g6`, TEST-ONLY key):

    nix-build integrations/siliconforest/kc-builder/release-inputs.nix          # G6 inputs, 54 kexts + 13 codeless
    installer/payload/rehearse.sh OUT --kc <out>/inputs --kc-builder <build-macos.sh>/kc-builder \
        --kc-link-tool <build-tools.nix>/bin/kc-builder --kc-expect b3115d93…

Result: 130 artifacts (67 bundles), `collection_sha256` `b3115d93…` (33,842,862 bytes) computed by the Linux tool and equal to
`--kc-expect`; deep verification passed. `kc_release.assemble` on the M5 with the release's ad-hoc macOS kc-builder: `b3115d93…`
in 0.43 s.

**Still open:** the engine step in Swift (S17/S42), the release workflow building and signing kc-builder with the
Developer ID identity, and the decision on duplicate symbols (kc-builder README, "Needs a decision").

