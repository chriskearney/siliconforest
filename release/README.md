# Minimal SiliconForest installer candidate

This branch implements release verification, candidate packaging and installation
plumbing. **There is no qualified binary release or public install command yet.**
Every profile in `profiles.json` is a target, not a support claim. The installer
refuses an unsigned, unqualified, mismatched or incomplete release before changing
packages or boot components. No Mac was installed, flashed or rebooted during
this development.

The requested minimum is M1 MacBook Air J313, M1 13-inch MacBook Pro J293,
M1 Pro 14-inch MacBook Pro J314S, and M3 Pro. M2 machines and M3 Air are targets
too. The catalog lists the 23 existing M1/M2 board DTBs, the two normal M3 Pro
DTBs, the alternative J514S native DTB, and the J613 Air profiles. J615 and other
unqualified M3 boards are not admitted by similarity.

## What the small installer owns

Exactly three release packages, plus their runtime dependencies:

| Package | Payload | Source |
| --- | --- | --- |
| linux-siliconforest | Unique kernel ABI, modules, config and matching board DTBs; installed alongside the distribution kernel | siliconforest-linux |
| mesa-siliconforest | Production ARM64 GLVND/EGL/GBM/DRI libraries and the profile's actual Vulkan ICD, if present | siliconforest-mesa, with an explicit compatibility branch when required |
| m1n1-siliconforest | Stage 2 payload at a separate owned path, installer archive and a hook that verifies the complete active set | siliconforest-m1n1; integration helper from this control repository |

The existing installed stage 1, machine firmware, machine calibration and U-Boot
are retained. U-Boot must match the qualified package/file identity. The new
installer does not install Touch ID/SEP services, libfprint, APFS write policy,
video-decoder bridges, performance daemons, diagnostic runners or desktop themes.
Previously installed services are not removed as a side effect of switching the
graphics/boot stack.

The source repositories supply code. This existing `siliconforest` control
repository locks their combination, builds packages, signs the package database
and manifest, and supplies the bootstrap. Independent moving `latest` releases
from the three source repositories must not be assembled on the recipient's Mac.

## Board profiles are essential

| Target | Kernel and Mesa selection | Current release gap |
| --- | --- | --- |
| M1/M2 | Normal kernel and existing AGX2 paths in main Mesa | ARM64 production package builds and per-board/firmware install and rollback tests |
| M3 Pro, prior working path | Normal kernel and compat/m3-pro-legacy Mesa | Port the old launcher's release/firmware admission to an honest SiliconForest contract; preserve its required session integration |
| M3 Pro J514S, new native path | CONFIG_SILICONFOREST_M3 and main native Mesa | Full kernel build and handoff/GPU qualification; USB4 is disabled in this variant |
| M3 Air, 14.x path | Normal kernel and compat/m3-legacy Mesa | Existing handoff/session admission and calibration assumptions must be reviewed; do not enable power stand-ins by default |
| M3 Air J613, 26.6.2 / 25G83 | Normal kernel and compat/m3-air-hal200 | Separate build and runtime admission; OpenGL only, no native Vulkan or external display in the pinned kernel |

Normal and native kernel output directories and release suffixes are separate.
The alternative display DTB set has J514S and J516C only; it is not a replacement
for every normal M3 DTB. J613 DTBs at the current pin, including 25G83, need
kernel 17a9930f or later and wait for atcphy1. An older kernel entry alone is not
rollback for that new DTB: restore the previous stage 2/DTB set too.

## Build candidates without installing

Provision a dedicated ARM64 build environment with the dependencies documented
in the root README and Mesa's source validation report. Installer/package tools
need Python 3.11+, libarchive tools, pacman/makepkg and GnuPG. Package preparation
never runs sudo, installs builder dependencies or changes the host's boot chain.

```sh
make sources
make verify
make build-kernel                     # normal, build/linux
KERNEL_VARIANT=m3-native make build-kernel  # separate build/linux-m3-native
make build-m1n1
make build-mesa                       # main production GLVND build, ARM64 only
make installer                       # standalone dist/siliconforest.pyz
python3 dist/siliconforest.pyz --check # read-only, on an existing Omarchy Mac
```

The compatibility Mesa branches need their own isolated source checkout and
qualified build options/session integration. The main build command is not a
compatibility-branch builder. `package.py` checks the exact profile source,
kernel variant, production GLVND prefix, ARM64 ELF headers and stage 2 flags.
It rejects the x86/shim Mesa build used for source validation.

After real builds, for example for the M1/M2 candidate:

```sh
python3 scripts/package.py kernel --profile m1-m2 --source sources/linux \
  --build build/linux --version 20261018.normal --output dist/packages
python3 scripts/package.py mesa --profile m1-m2 --source sources/mesa \
  --build build/mesa-package --version 20261018.normal --output dist/packages
python3 scripts/package.py m1n1 --profile m1-m2 --source sources/m1n1 \
  --build sources/m1n1/build --version 20261018.normal --output dist/packages
```

These commands create candidate packages, not qualified releases. Headers are a
separate future optional package; the installer does not require them to boot.
The current preflight refuses installed DKMS modules until matching headers are
packaged and that path is qualified.

Copy `release.example.json` to a candidate manifest and record the actual package
filenames, versions, hashes, source commits, exact board/OS-firmware identity,
kernel release, DTB, U-Boot path/hash, configuration hash, loader hash, kernel
image hash and installed boot paths. The template's placeholders are not release
evidence. Each manifest currently selects one exact board DTB; use separate
manifests for boards with different DTBs.

```sh
python3 scripts/release.py --manifest build/candidate.json \
  --packages dist/packages --output dist/candidate
```

An unsigned candidate emits no `install.sh`. Only after the exact set has an
attended hardware report covering the desktop, actual hardware renderer, complete
boot chain and recovery/rollback may its qualification fields become passed.
Then use an existing owner signing identity:

```sh
python3 scripts/release.py --manifest build/qualified.json \
  --packages dist/packages --output dist/qualified --signing-key FULL_FINGERPRINT
```

The assembler signs each package, the repository database and the manifest. It
exports only the public key and renders an immutable-release bootstrap with the
installer hash and full signing fingerprint embedded. It does not create a
signing identity, upload releases, install anything or reboot. Publish the full
fingerprint independently before distributing the bootstrap.

A single public command for multiple models uses a signed catalog. Its input is
`{"schema":1,"id":"RELEASE_TAG","releases":[{"release":"CHILD_TAG","boards":["apple,j313"],"firmware":["EXACT_VERSION"]}]}`.
Create one child release per qualified board/firmware/profile combination, with
the same signing identity. `scripts/release.py --catalog build/catalog.json
--output dist/catalog --signing-key FULL_FINGERPRINT` creates its bootstrap.
The selector requires exactly one board/firmware match and re-verifies the child
manifest, packages and database. It never guesses a profile or upgrades OS firmware.

## Installation and recovery behavior

The generated bootstrap supports `--check` and `--dry-run`. Installation checks
the actual paired ESP PARTUUID, available space, pacman state, existing U-Boot
and supported boot backend. Current overlay installations stop for qualification
instead of silently dropping overlays. All three packages and the database must
match the signed manifest before elevation/package changes. The bootstrap's
first version downloads once for preflight and again under elevation; eliminating
that duplicate transfer is a later optimization, not a reason to skip verification.

Before the transaction, it records old packages/configuration, backs up existing
UKIs, and places an old `boot.bin` plus recovery instructions on the paired ESP.
The currently installed replacement packages and stock kernel must be in pacman's
cache for rollback. Missing cached versions stop before mutation. A signed
SiliconForest channel is configured and one `pacman -Syu` transaction installs
the three packages; the stock kernel is retained. No signature bypass, forced
overwrite or unrelated service enablement is used.

The generic m1n1 updater is disabled with a marked configuration block while
SiliconForest owns stage 2. Its own hook checks package versions and all boot
hashes, preserving the exact DTB instead of choosing the newest module directory.
Required handoff options are explicit in the signed manifest. Initramfs/boot-menu
generation and the referenced output image are checked before stage 2 is replaced
with an fsynced atomic rename and readback. The kernel menu is rebuilt by the
existing Limine or GRUB tools; those layouts still need real-machine rehearsal.

On failure, configuration and saved boot files are restored, and the transaction
records that packages may have changed. This is not an atomic rollback of an
entire pacman system upgrade. The transaction directory contains the exact cached
previous stack and hashes. Use the saved installer archive or a separately retained
copy with `sudo python3 siliconforest.pyz --rollback /var/lib/siliconforest/transactions/ID`.
The removal guard requires this coordinated path for an active stack. Recovery
before the boot menu requires restoring the old `m1n1/boot.bin` from the paired
ESP's `siliconforest-recovery/ID` directory and booting its matching old kernel.
The previous OS package upgrade and any newly trusted public signing key are not
automatically undone by stack rollback. Neither installation nor rollback reboots.

## Checks completed and remaining

The host suite exercises real ephemeral GPG signatures, wrong identities,
tampering, source receipts, extra database packages, board/firmware restrictions,
configuration preservation, boot-input changes, atomic-file refusal and stage 2
assembly. It writes only test fixtures and does not exercise pacman installation.
The packed installer is also checked to refuse this x86 builder.

Still required before sharing an install command: complete ARM64 kernel/Mesa
package builds; native library dependency and package-conflict inspection; the
legacy M3 session-admission port; owner signing identity/channel publication;
and install, update and rollback rehearsal for the requested machines. Source
host checks and the old upstream installer's test history do not replace those
results for these newly combined packages.

References: [Asahi stage 2 format](https://asahilinux.org/docs/alt/boot-process-guide/),
[pacman transactions](https://man.archlinux.org/man/pacman.8.en),
[signature policy](https://man.archlinux.org/man/pacman.conf.5.en), and
[Mesa installation](https://docs.mesa3d.org/install.html).
