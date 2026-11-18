# SF-AJ: Installer: one command from macOS (#64)

INSTALL stream, 18 November 2026. User documentation: `docs/INSTALL.md`. Code: `install.sh` (the
one-line command's target, assembled), `install/bootstrap.sh`, `install/engine/`, `install/models.tsv`,
`install/tests/`, `tests/test_sf_installer.py`.

## State in one paragraph

The installer exists and refuses to install, because no release exists: `--check` and `--dry-run`
work as soon as the Asahi engine package can be downloaded. Its planning was tested against
recorded `diskutil` outputs (eight synthetic layouts and one scrubbed recording from a real Mac),
and the whole install, update and uninstall were run end to end through its safety gate against a
model of a Mac's disk. The Asahi Linux installer's own code (v0.9.2, the engine) was run behind the
gate against that model for every disk step it takes (resize, the stub partition and its volumes,
SFBOOT, FAT format, root partition, root image write, boot partition files, boot object), and issued
exactly the commands the simulation assumes. **Nothing has been run on a real Mac**: no install, no
dry run (the real Mac we could read from is an unsupported model, used for read-only fixtures). The
same engine code, with a hand-made kit, installed the stub and SFBOOT on the owner's M1 on 13
November 2026 (`integrations/siliconforest/m1-native-boot/install/INSTALL.md`).

## The process as a user experiences it

1. Paste `curl -fsSL https://raw.githubusercontent.com/chriskearney/siliconforest/main/install.sh | sh` into Terminal on macOS.
2. It checks the Mac (model table, macOS 13.5–26, admin at the console, Rosetta, FileVault, snapshots, power) and reads the disk; anything wrong stops with a sentence and "Nothing was changed".
3. It fetches its engine (the Asahi Linux installer package, SHA-256 pinned) and the release's signed `SHA256SUMS` and `install.json`.
4. It shows the disk and a numbered list of exactly what will change (macOS shrinks by X and keeps Y free; three new partitions; nothing else).
5. The user types `install`; sudo asks for the password; the plan is made again and must match.
6. Downloads are checked against `SHA256SUMS`; macOS is shrunk; the stub (from Apple's macOS 13.5 restore files), SFBOOT and the root are made and filled (the root read back and checked); Wi-Fi/Bluetooth/Touch Bar firmware is collected from Apple's recovery image and put into the root; the root partition's identifiers go into `sf/kernel.bin`.
7. The password once more (bless); the Asahi installer's recovery instructions; the Mac shuts down.
8. Hold power, choose SiliconForest, sign in, `bputil` and `kmutil` with the macOS password (Apple requires the owner to do this).
9. SiliconForest starts; the user sets macOS back as the startup disk; from then on SiliconForest is chosen at start.
10. `--update` replaces the boot files; `--uninstall` removes everything and gives the space back to macOS.

What exists: all ten steps in code. Tested: 2, 4, 5 (plan comparison), the disk part of 6, 7's bless/shutdown and 10, on the disk model; 3 and 6's downloads only in the sh test with a pretend Mac (no signed manifest exists to verify, signature verification was exercised by hand on a real Mac's LibreSSL with a test key); 1, 8, 9 never.

## Lessons: Asahi Linux installer, Omacom's installer, our own kit

Sources read: `AsahiLinux/asahi-installer` v0.9.2 (`src/main.py`, `diskutil.py`, `osinstall.py`, `stub.py`,
`step2/step2.sh`, `urlcache.py`, `scripts/bootstrap-prod.sh`, `build.sh`); `omacom/omarchy-mac-installer`
(c07e54c: README, `Engine/`, `Engine/installer_data.json`, `Engine/source-lock.json`) and the earlier
script route `omacom/omarchy-mac` (667500c, README); our kit `integrations/siliconforest/m1-native-boot/install/`.

| Topic | Asahi Linux installer | Omacom (omarchy-mac-installer) | Our kit (13 Nov) | What we adopt | What we do differently, and why |
|---|---|---|---|---|---|
| Entry | `curl https://alx.sh \| sh`; bootstrap in `if true; then … fi` against truncation; versioned tarball; `caffeinate -dis sudo -E` | a notarized app (dmg, Homebrew cask); "there is no curl \| sh path" | tarball copied over ssh | curl \| sh, truncation guard (one function called last), caffeinate, sudo only after the plan | the tarball is checked against a pinned SHA-256 (Asahi's bootstrap trusts TLS alone); no notarized app (no Developer ID; a script is reviewable) |
| Python | python.org framework + libffi inside the tarball | Asahi's `.28` runtime base, pinned file by file | Asahi's tarball, for its Python only | the Asahi v0.9.2 tarball, byte for byte | none; stock macOS has no Python (`/usr/bin/python3` is a stub that offers the developer tools) |
| Which Macs | `DEVICES`/`CHIP_MIN_VER` in code | signed catalog; `supported-models.json`; "This Mac isn't supported yet" | one machine by hand | a data table; refusal names the Mac and lists the supported ones | the release manifest can only narrow the table (Omacom: the catalog decides) |
| macOS range | ≥13.5 (12.3 expert); no upper bound | ≥15 (`LSMinimumSystemVersion`) | 13.5 stub firmware | ≥13.5; stub firmware 13.5 only | an upper bound (26): our drivers are tested against one firmware; Asahi needed a macOS 27 picker fix, so new majors are refused until tested |
| Checks | console user (not ssh-only), admin in macOS's Preboot list (runs `updatePreboot` if stale), Rosetta relaunch, a ProMotion firmware bug | power, FileVault, free space, before asking for a password | `sf-preflight.sh` (read-only, partition list) | all of these, before any password | FileVault encrypting/decrypting is refused (a resize during conversion is asking for trouble); battery is a warning |
| Shrinking macOS | `resizeContainer … limits`; keep 38 GB; `MinimumSizePreferred`; warn when snapshots hold >16 GB; "may appear to freeze"; First Aid hint on failure | size editable in GB; 38 GB recommended; "free space shown is not space the installer can release" | no resize (space made from Linux) | the same formula and messages, and how much *could* be offered | resize is part of the one plan, not a separate menu action that returns to the menu |
| Consent | menu; separate "Continue?" for the resize; then questions; then it writes | backup checkbox; plans bound to a digest of the disk layout | the menu, cut down by a patch | Omacom's plan-bound-to-layout idea | one typed confirmation after a numbered list of every change; the plan is rebuilt under sudo and must equal the confirmed one |
| Stub | built from single files of Apple's IPSW over HTTP ranges; Finish Installation.app; `step2.sh` | the same engine, plus a restore-image helper for encrypted newer restore images | Asahi's | Asahi's, unchanged | stub firmware fixed to 13.5 (`supported_fw`), the version SiliconForest's drivers were brought up on |
| Recovery step | `step2.sh`: clear texts for "wrong recoveryOS" and "not 1TR"; `bputil -nc`, `kmutil configure-boot` | a native Recovery app | Asahi's | Asahi's step 2 and its words, unchanged | none |
| Firmware | collected from the recovery ramdisk into `vendorfw/` on the ESP; Linux's initramfs unpacks it | the same (and more for newer Macs) | not collected | Asahi's collection, `copy_firmware` to SFBOOT | the brcm/ (Wi-Fi, Bluetooth) and apple/dfrmtfw, tpmtfw (Touch Bar, trackpad) files also go into a preallocated slot inside the root, because SiliconForest's storage driver reads only its root (`sfnvme_readfence=1`) and macOS cannot write ext4 |
| OS package | `installer_data.json`; zip with `esp/` tree and raw images; `expand`; streamed by HTTP range | Asahi package format, catalog-pinned | our `installer_data.json` + zip | the format, as is | downloaded whole and checked before use: Asahi's range reader drops a URL's query string, so it cannot stream GitHub release assets (signed redirects), and a stream cannot be checked before it is written |
| Integrity | TLS (+ zip CRC) | Ed25519-signed catalog, SHA-256 of engine and image, trust root in the app | SHA-256 manifest of the kit | a signed list of every file's SHA-256 | an SSH signature (Ed25519) of `SHA256SUMS`, IMAGE's scheme, verified by macOS's own `ssh-keygen -Y verify` (OpenSSH 10.2 on macOS 26.5.2: a good and a tampered signature tried on a real Mac, nothing written); macOS's LibreSSL 3.3.6 has no Ed25519, an ECDSA P-256 `openssl dgst` check also works there and was the first draft |
| Compression | zip (deflate) | zip | none | xz for the root and boot files | not zstd: stock macOS cannot decompress it (its `tar` calls an external `zstd` that is absent; tried on a real Mac), while liblzma is in macOS and in the engine's Python |
| Root image | written raw from the package zip by the engine (`image`) | the same | written from Linux by hand | | written by our code from the xz parts straight onto the new partition, then read back and compared with the release's SHA-256 (no `e2fsck` or `resize2fs` on macOS) |
| Per-machine data | appends the ESP PARTUUID and `chainload=` to m1n1 | the same | the same | the same | new: the root partition's GUID, first block and length go into `sf/kernel.bin`'s command line (the storage driver's write fence), packed on the Mac by the release's own `sf_personalize.py` (IMAGE) and then checked by ours (`sf_kernelcfg.verify`: exactly this partition and the release's root, once each); the root filesystem UUID is a per-release constant, never changed at install |
| Default startup disk | blesses the new OS (step 2 needs its paired recovery) and leaves it default | the same; user picks at start | the same, then the owner set Linux back | the same | the user is told to set macOS back after the first start: SiliconForest cannot change NVRAM, and a failed start must land in macOS |
| Dangerous menu items | "m: Upgrade m1n1 on an existing OS", "v: Rebuild vendor firmware" for any stub | engine overlay | removed by `main-menu.patch` (with our stage 1, "m" would overwrite another system's stub) | | no menu at all: the engine is driven step by step; the gate refuses blessing or formatting anything this run did not create |
| Telemetry | reports install statistics (`REPORT`) | none found | unset | | none (the engine's `REPORT` is removed from the environment) |
| Uninstall | none; the partitioning cheatsheet | typed phrase, refuses layouts it does not recognize, grows macOS back, removal record | `sf-uninstall.sh` (print, `--execute` after typing the container) | refuse unknown layouts; typed word; grow macOS back | refuses while SiliconForest is the startup disk; leaves the space free if another partition sits between |
| Interruptions | "p: Repair an incomplete installation" | journal; retry of recovery authorization; unfinished removal blocks new runs | none | a journal of every change | an incomplete installation is recognized (down to "stub partition made, no volumes yet") and removed by `--uninstall`; resizing is naturally idempotent (the next plan sees the free space) |
| Tests | none automated for the disk logic | portable suite with fixtures; `--simulate`; release builds refuse it | `test_kit.py`: the installer's own code with recorders | fixtures, a simulation | the simulation's command sequence is checked against what the real Asahi code issued on the same model (`fixtures/asahi-v0.9.2-commands.txt`) |

## Can the unmodified Asahi installer install SiliconForest? Verdict

**Its code, yes; its program, no.** We reuse the Asahi installer's code **unmodified** (the published
v0.9.2 package, checked by digest, none of its files changed) and drive it with our data and one
overlay (`install/engine/`), as Omacom does with a heavier overlay. Running Asahi's `main.py` with
only our `installer_data.json` (what "unmodified or lightly configured" would mean) is not enough,
for five reasons found in its source:

1. Nothing in it can write this Mac's root partition into `sf/kernel.bin` after the partitions exist;
   without that the kernel refuses its root (by design: the write fence).
2. Its menu offers "upgrade m1n1 on an existing OS" for every stub: with our stage 1 as its boot
   object, that would replace another system's (Asahi Linux's) first stage with ours.
3. It asks several questions and writes between them; there is no single confirmation listing every
   change, and no check that the disk is still as planned.
4. Its package reader cannot stream from GitHub release assets (it drops the redirect's query string)
   and does not verify a package before writing it.
5. It reports installs to Asahi's statistics server unless the environment says otherwise.

Everything hard (the stub from Apple's restore image, the recovery step, firmware collection, the
partition bookkeeping, years of field fixes) is inherited by running its code as it is. The overlay
adds the plan, the gate, the identifiers and the firmware slot. Recommendation: keep this route
(decision D1 below).

## Structure and safety properties

    install.sh            POSIX sh, macOS tools only: platform checks, engine download (SHA-256),
                          release signature (ssh-keygen -Y verify over SHA256SUMS), install.json,
                          artifact downloads (resume, size, SHA-256)
    install/engine/       Python, run by the engine's Python:
      sf_disk.py          diskutil plists -> layout; free areas, our pieces, others, digest
      sf_plan.py          facts (read-only commands), checks, plans for install/uninstall/update
      sf_gate.py          the one door for every change; journal; simulation hook
      sf_engine.py        plan -> confirm -> sudo -> same plan -> Asahi engine behind the gate
      sf_kernelcfg.py     checks the packed sf/kernel.bin names exactly this root partition
      sf_fwslot.py        firmware tar into the root's firmware slot
      sf_manifest.py      install.json schema, cross-checked against the signed SHA256SUMS
    install/models.tsv    the model table (data)
    install/tools/assemble.py   install.sh = bootstrap.sh + engine files as here-documents

- Read-only until one typed confirmation that follows a numbered list of every change; `--dry-run`
  prints the plan and stops; no command-line flag skips the confirmation.
- The plan is made again under sudo from a fresh read of the disk and must equal the confirmed plan
  (partition table digest, sizes, targets).
- Every disk change, ours or the engine's, passes `Gate.run`/`Gate.open`: the engine's `diskutil`
  calls, `subprocess`, raw `open` and `os.system` are rerouted there. It allows only: the planned
  resize of the planned container to the planned size, once; new partitions after the planned
  partition (or one this run made) within the planned space; volume changes, FAT format, raw writes
  and bless only on what this run created; in an uninstall only the planned deletions and growing
  macOS. `dd`, `gpt`, `kmutil`, `bputil` (other than `-d`), NVRAM writes and anything unknown are refused.
- After each change the gate reads the table again and stops everything if a partition that existed
  moved, vanished or changed size (except the planned macOS resize).
- macOS's volumes are never opened for writing; the only change to macOS's container is its size.
- Logs: `~/Library/Logs/SiliconForest/installer-<time>.log`; journal
  `/var/db/siliconforest-installer/journal.jsonl` (a start and an end line for every change); a copy of
  the log and `sf/install.json` on SFBOOT.
- The root image is written by our code through the gate and read back; a short, long or different
  image stops the install before the boot files are written.
- Without a signed release it never gets past the plan; without a pinned release key it refuses any
  release it finds.

## Tests

- `tests/test_sf_installer.py` (in CI through `tools/ci_check.py`), 33 tests, all pass (18 November 2026,
  Python 3.14 here; CI runs 3.12): model table; fixtures current; FakeMac's plists have the keys and
  types of the real recording; the real recording parses (three partitions, a container with two
  macOS systems) and is refused as the wrong model; macOS range; console/admin/Rosetta/battery;
  FileVault on and converting; release narrowing; plans for stock, size requests, too little space
  (with the size that would fit), snapshot overhead, Asahi with and without free space, already
  installed, partial (two depths), uninstall plans; digest; CONFIG rewriting and its refusals
  (checked with `pdsf_pack.py`) and its verifier; the firmware slot; install.json mutations and the
  SHA256SUMS cross-check; the root write refusing a short, wrong or oversized image; the gate refusing 15 kinds
  of wrong command and stopping when another partition moves; install → update → uninstall end to
  end on the model, ending with the same partitions at the same offsets and sizes as before; uninstall when deleting
  the container leaves its partition; `sf_engine.main` for check, dry run, no release, declined
  confirmation (no change issued); `install.sh` assembled, refusing on Linux, and on a pretend Mac
  (PATH stand-ins for uname, sysctl, sw_vers, curl) refusing Rosetta and reaching the engine.
- `install/tests/test_with_asahi.py` (local, needs the Asahi source): passes; the real Asahi v0.9.2
  modules behind the gate on the model; its 10 changing commands are the recorded fixture.
- Fixtures: `install/tests/fixtures/m1-*` are **synthetic** (`make_fixtures.py`: values made up, UUIDs
  derived from scenario names). `real-m5-scrubbed` is a recording of read-only commands on a real Mac
  (an M5, macOS 26.5.2), scrubbed by `scrub_recording.py`: every UUID renumbered, long hashes zeroed,
  non-default volume names replaced, the user name replaced, drive statistics dropped, and the
  output searched for every original value. `system_profiler` was recorded but not kept (the installer
  reads the model with `sysctl`).
- shellcheck: not run on this workstation (its shellcheck binary is broken; fetching another was
  refused). The CI step `shellcheck -s sh install.sh install/bootstrap.sh` on GitHub's runner found one
  warning (SC2034, an unused variable) in commit 63ed753d3, already gone in 0a294f565, whose CI run passed
  in full. `sh -n` and `bash --posix -n` pass.
- `python3 tools/ci_check.py`: accepted (one known test NOT RUN for a missing artefact, as on every clone).

## Real-hardware test (designed, not run; needs a machine and the owner's go)

Machine: a **spare** 13-inch M1 MacBook Pro set to a stock layout by macOS's own "Erase All Content
and Settings" (not DFU), macOS 13.5 or later. **Not the owner's M1**: its layout was made by hand
(SiliconForest's root lies before its stub), so the installer would call it incomplete, and
`--uninstall` there would remove its stub and SFBOOT but not its root. Not the M5 (not supported,
and it is a work Mac). A person at the machine; a second computer to copy logs to.

Checklist, with what to keep from each step (`diskutil list`, `diskutil apfs list`, the installer's
log and journal):

1. `--check`, `--dry-run`, `--dry-run --size 30`, `--size 1000`: plans as expected; refusals worded right.
2. Ctrl-C at the confirmation; answer something other than `install`: nothing changed (compare listings).
3. Install with defaults. Note times of each phase. Before the recovery step, from macOS: the
   partitions are where the plan said; `shasum -a 256` of `sf/boot.bin` matches the release's
   `boot.bin`; `sf/kernel.bin`'s command line names the root's GUID, first block and length as
   `diskutil info` gives them; the firmware slot (read-only `dd` of 4 KiB at the slot offset of the root
   partition) starts `SFFWSLOT1\nlength=`.
4. Recovery step: wrong ways first (release the button early; press twice) to see Asahi's texts; then right.
5. First start: the mark, the desktop, Wi-Fi joins a network (the firmware arrived), a terminal works,
   restart lands in SiliconForest (it is the default).
6. Set macOS as startup disk; restart twice: macOS; `diskutil verifyVolume /` clean; free space as planned.
7. Picker → SiliconForest three times; each starts.
8. `--update` with a second release (a different kernel.bin): `.old` files kept; SiliconForest starts.
9. Interrupt an install after the stub partition exists (Ctrl-C during the Apple downloads): `--check`
   reports an incomplete installation; `--uninstall` removes exactly it.
10. `--uninstall` of the full install: refused while SiliconForest is default; then succeeds; the
    partition table equals step 1's (offsets, sizes, UUIDs of Apple's partitions); macOS's container is
    its old size; `diskutil verifyVolume /` clean; install again works.

Stop and recover (macOS from the picker) at any unexpected output; never DFU; never edit the journal.
Pass: every step as written, macOS unharmed after each.

## Agreed with IMAGE and BUILD, and what is still open (18 November 2026; `runs/m1-coord/requests-for-*`)

Agreed: one root filesystem UUID per release (`release/identity.nix` on the release-image branch),
stage 2 built for it (BUILD), the root image carries it and the installer never changes it; per
machine only the kernel's command line changes, packed on the Mac by the release's
`sf_personalize.py` (lower-case partition GUID, 4096-byte blocks) and checked by `sf_kernelcfg`;
IMAGE's `SHA256SUMS` + SSH signature (namespace `siliconforest-release`, identity
`release@siliconforest`). IMAGE's `sf_personalize.py` was run here on a synthetic boot directory with
its real `bootargs.template` and our check accepted the result (555 characters of command line).

Asked of IMAGE, not yet answered: xz instead of zstd for the root parts and the boot tar (zstd
cannot be decompressed on stock macOS); `siliconforest-<v>-install.json` (`install/manifest.example.json`)
listed in `SHA256SUMS`; `sf-stage1.bin` and `siliconforest.icns` in the boot tar; the firmware slot in
the root image (a contiguous preallocated file whose first block starts `SFFWSLOT1`) and a first-start
job that unpacks it into /Library/Firmware/brcm and /Library/Firmware/apple (IMAGE proposed writing the
firmware into the image with `debugfs` on the installing machine: macOS has no debugfs); whether the
root grows to its partition at first start (no `resize2fs` on macOS); the licence questions per artifact.
Answered for IMAGE: account at install time and Homebrew at install time or first run are owner
decisions (D8, D9 below); Apple applications: the installer does nothing (D5).

## Decisions for the owner

- **D1. Engine: reuse the Asahi installer, or our own script?** Recommendation: **reuse** (as built):
  the unmodified v0.9.2 package plus our overlay. A shell-only installer would have to reimplement
  the stub (ranged reads of Apple's restore image, Preboot/Recovery set-up, step 2), the most fragile
  and most field-tested part. Cost: we depend on Asahi's package format and code; we pin it and mirror it.
- **D2. Hosting and signing.** Recommendation: GitHub Releases of this repository (2 GiB per file: the
  root image comes in parts under 1.9 GiB, each checked); the Asahi package mirrored there with its own
  digest, Asahi's CDN as fallback; `SHA256SUMS` signed with an SSH Ed25519 key that the owner makes and
  keeps offline (`ssh-keygen -Y sign -n siliconforest-release`; only the public half goes into
  `install.sh`), one signature per release. Until the key exists, the installer refuses every release.
- **D3. Supported models.** Recommendation: a Mac is listed as supported only after SiliconForest boots on
  that model and one real install and uninstall have been done on it (section 13 of `docs/INSTALL.md`);
  the release manifest can narrow the list, never widen it; today one model.
- **D4. Default startup disk.** Recommendation: **stay opt-in** (macOS default; SiliconForest chosen at
  start), as now. SiliconForest cannot change NVRAM, and every failed start should land in macOS.
- **D5. Apple applications.** Recommendation: the installer does nothing about them; a later helper copies
  the user's own copies from their macOS over the network; licence questions are the user's.
- **D6. Licences of built images** (IMAGE lists them per artifact; not decided here): GPL-2.0 kernel
  extensions linked into an APSL kernel collection; corecrypto (CODEX-BUILD reports PureDarwin uses an
  MPL-2.0 reimplementation); Firefox and other third-party binaries in the root; fonts; Apple's binary
  driver licence in PureDarwin's tree. Firmware is never shipped (extracted on the user's Mac). The
  Asahi package (MIT) and the Python inside it (PSF) are redistributable with their notices.
- **D8. The first account** (IMAGE's question): recommendation: the first start asks for a user name
  and password and makes that person's account (an administrator); no account without a password.
- **D9. Homebrew pieces** (IMAGE's question): recommendation: in the release image (checked like everything
  else), not fetched at first start, so a fresh install works offline after Wi-Fi joins.
- **D7. The one-liner's URL.** Recommendation: `main` until the first release, then the release tag in the
  documented command, so the script and the release it expects match.

## Not done

- No run on a real Mac (by rule); the real-hardware test above needs a spare J293 and the owner's go.
- No release, manifest, release key or artifacts (IMAGE; D2).
- Firmware slot and first-start unpacker: proposed to IMAGE, not agreed; root growth at first start unknown.
- Re-running only the recovery authorization ("repair", Asahi's `p`) is not wired: an install whose
  step 5 was skipped is complete on disk, and repeating step 5 by hand works as Asahi documents; a stale
  admin list after the install needs Asahi's repair, not offered yet.
- The engine path that needs a real Mac (Asahi's SystemInfo, stub contents, firmware collection, bless,
  step 2) has run only in Asahi's own installs and, unmodified, on the owner's M1 via the kit; never behind
  our gate.
- The sudo re-run passes the engine's DYLD variables through `env`: not tried on macOS.
- Helper for Apple applications; in-place root updates; external disks; other models.
