# SiliconForest installer and release qualification

The installer replaces the kernel, Mesa and m1n1 stage 2 on an existing Apple
Silicon Omarchy installation. There is no qualified public install command yet.
Source profiles and signed attended candidates do not claim hardware support.

Exactly three packages form a release:

| Package | Owned payload |
| --- | --- |
| linux-siliconforest | Unique kernel ABI, modules, configuration and matching DTBs |
| mesa-siliconforest | ARM64 GLVND/EGL/GBM/DRI libraries, the selected Vulkan ICD and necessary graphics session safeguards |
| m1n1-siliconforest | Separate stage 2 payload, matched installer and transaction hooks |

The existing stage 1, machine firmware, calibration and qualified U-Boot remain
in use. No Touch ID/SEP services, video bridges, performance daemons, APFS policy
or themes are added. Replacing the old Mesa packages also replaces their owned
session integration. Unrelated services are outside the package set.

The three public source repositories provide the code. This control repository
pins their combination and builds, verifies, signs and selects complete releases.
Recipients must not combine independent moving releases from the source repos.
Private Mesa source is excluded from public releases.

## Actual hardware and profile boundaries

The available owner machines were inspected on 2026-10-18:

| Target | Observed OS firmware | Release path |
| --- | --- | --- |
| M1 Air J313 | 13.5 | Normal kernel and main Mesa AGX2 |
| M3 Pro 16-inch J516S | 14.7 | Normal kernel, legacy native OpenGL plus separately pinned legacy Vulkan |
| M1 Pro 14-inch J314S; M1 MBP 13-inch J293 | Not available for this qualification | Normal kernel and main Mesa; tests pending |
| Other M1/M2 machines | Per-machine qualification pending | 23 catalog DTBs are build targets, not tested-support claims |
| M3 Pro J514S, alternative native driver | Per-machine qualification pending | CONFIG_SILICONFOREST_M3 and main Mesa; USB4 is disabled in this variant |
| M3 Air J613, 14.x | Not confirmed | compat/m3-legacy, reviewed handoff/session admission required |
| M3 Air J613, 26.6.2 / 25G83 | Not confirmed | compat/m3-air-hal200; OpenGL only, no native Vulkan or external display in the pinned kernel |

The alternative M3 display DTB set does not cover the owner's J516S. Its normal
legacy profile preserves the working GPU ABI and native OpenGL path. The
combined Pro Mesa package records both OpenGL and Vulkan source commits.

J613 DTBs at the current pin, including 25G83, require kernel 17a9930f or later
and wait for atcphy1. An older kernel alone is not rollback for those DTBs:
restore its matching stage 2 and DTBs too. External display on the normal J613
path requires exactly firmware-compat 14 7 0 and the transactional readiness
marker. Camera support on 26.6.2 does not imply external-display support.

## Build without installing

The ordinary local build/package tools do not install dependencies or change the
builder's boot chain. Use a dedicated builder with the root README prerequisites,
Python 3.11+, libarchive, dtc, pacman/makepkg, GnuPG and the pinned compiler tools.

```sh
make sources
make verify
make build-kernel
make build-m1n1
make build-mesa   # provisioned ARM64 builder, main Mesa only
make installer
```

`scripts/mesa-recipe.py` exports exact public profile commits and verified
LLVM/SPIR-V inputs into a self-contained recipe. `lab package` builds that recipe
inside a disposable Arch Linux ARM VM; only that VM provisions dependencies.
For example, using already downloaded compiler inputs:

```sh
python3 scripts/mesa-recipe.py --profile m3-pro-legacy --source sources/mesa \
  --toolchain-inputs /path/to/verified-inputs --version UNIQUE_VERSION \
  --output build/recipes/UNIQUE_RECIPE
lab package build/recipes/UNIQUE_RECIPE --no-wait
lab build-get BUILD_ID -o dist/builds/UNIQUE_RECIPE
```

Production builds use /usr, GLVND and ARM64. Assertions stay enabled for the test
suite; software rasterization does not add an LLVM runtime dependency. Registered
Asahi test dependencies are built explicitly, including executables invoked
through DRM-shim wrappers. The runtime audit rejects build-directory search paths
and derives library dependencies. Pinned SPIRV-Tools are statically linked with
their license retained. Pro compatibility builds also test their native GL and
separately sourced Vulkan compiler paths.

Package the built kernel and m1n1 with the same unique bundle version:

```sh
python3 scripts/package.py kernel --profile m1-m2 --source sources/linux \
  --build build/linux --version UNIQUE_VERSION --output dist/packages
python3 scripts/package.py m1n1 --profile m1-m2 --source sources/m1n1 \
  --build sources/m1n1/build --version UNIQUE_VERSION --output dist/packages
```

Packaging verifies kernel ABI, every module's version magic, DTB identities,
ARM64 ELF headers and stage 2 release flags. Loader layout comes from
m1n1-raw.elf; M3 file-part bounds are checked against the stage 1 log-buffer
boundary. Rebuilding a published version with different bytes is forbidden.
Headers remain optional future work; installed DKMS modules currently stop the
installer until that path has matching headers and qualification.

## Signed attended candidates and qualified releases

Copy release.example.json and replace every placeholder with actual package,
source, board, firmware, kernel, DTB, U-Boot and boot-component identities.
Every manifest identifies the stage 2 build version; graphics admission checks
the running device-tree version, not just the file on disk. M3 manifests
additionally require exact stage 1 and iBoot versions. A candidate
must not mark tests passed before they run.

An attended candidate has status `attended-testing`, one exact board/OS-firmware
pair and a test plan/report location. Assemble it with an existing owner key:

```sh
python3 scripts/release.py --manifest build/candidate.json \
  --packages dist/packages --output dist/candidate \
  --signing-key FULL_FINGERPRINT --test-candidate
```

This signs packages, database and manifest and exports only the public key.
It emits no install.sh. Explicit `--test-candidate` is required to install it.
The ordinary public bootstrap continues to refuse candidates.

After actual desktop, hardware-renderer, boot-chain and rollback tests pass,
record their evidence and assemble a qualified release without --test-candidate.
Only that path emits install.sh. A signed catalog selects exactly one qualified
child release by board and OS firmware; an unsupported pair stops. The signer
fingerprint and installer digest are pinned in the bootstrap. Root verifies and
copies those exact installer bytes before running Python in isolated mode.

## Installation and recovery

Preflight checks the paired ESP, root/ESP free space, package-manager state,
U-Boot identity and boot backend. Unqualified DT overlays, DKMS or M3 stage 1
handoffs stop before mutation. All three packages, their provenance receipts,
critical boot payloads, signatures and database contents must match.

Current versions of packages being replaced must be cached for recovery. The
installer records old package/configuration identities, saves every existing UKI
on root, and places the old stage 2, menu and a compressed copy of the currently
running kernel's UKI on the ESP. Historical recovery entries are retained.
Space budgeting includes those copies and bounded new UKI/stage 2 sizes.

The package transaction is local `pacman -U` of the three verified archives;
there is no hidden full-system upgrade. The stock kernel remains installed.
The existing generic m1n1 updater is frozen with a marked configuration block.
SiliconForest's hook checks the entire active set and exact boot inputs.

For Limine, BOOT_ORDER is managed in /etc/default/limine and the targeted
limine-mkinitcpio backend builds the SiliconForest UKI using temporary root
storage. It does not reinstall Limine or regenerate every installed kernel.
The output must be an ARM64 UKI containing the exact pinned Linux Image and an
initrd. Only then is stage 2 assembled from the matching DTB, loader, U-Boot and
preserved handoff settings, replaced atomically and read back. These mechanisms
still require real full-stack qualification; a maclab kernel-only boot retains
the old device tree and cannot prove a new m1n1/DTB pair.

On failure, saved configuration and boot files are restored; records explicitly
state that packages may have changed. Coordinated rollback restores the previous
boot files before package removal/reinstallation, then restores configuration:

```sh
sudo /usr/bin/python3 -I /usr/lib/siliconforest/installer.pyz \
  --rollback /var/lib/siliconforest/transactions/ID
```

A verified retained installer copy can run recovery if the installed package is
unavailable. Before Linux boots, the ESP recovery directory contains stage 2,
compressed old UKI, menu and instructions for restoring the paired old boot chain.
Installation and rollback do not reboot automatically. Newly trusted public
signing keys are not removed by stack rollback.

## Evidence

`make check` covers 27 installer tests with real ephemeral GPG signatures and
signed package fixtures, source/package tampering, exact handoffs, isolated root
elevation, UKI payload validation, cached epoch versions, a complete temporary
filesystem install/failure restore and coordinated rollback. It also runs 51
user-override cases and 10 compositor confirmation cases; a real headless Weston
case runs when available. CI passes on Ubuntu 24.04. These are host controls,
not hardware qualification.

The normal ARM64 kernel completed at 17a9930f20a0, including the built-in Rust
Asahi GPU driver, all 1,878 modules and catalog DTBs. Its ABI is
7.1.12-siliconforest-normal-17a9930f20a0 and its Image SHA256 is
0ad008defa3e779aa1dac7060ecb9621a0ab4ebe9db9c388a90b86c9290dd7ca.

ARM64 Mesa testing exposed a GCC 16.1.1 -O3 extension-chain aliasing problem.
The fix is public in Mesa c8015f63608e6eb2f859a1739462a3c77eca600a;
all 3,035 compression policy checks pass at -O0/-O2/-O3 on ARM64 and x86_64.
Fresh complete ARM64 package builds and full-stack hardware qualification remain
in progress. The available Air booted this kernel and passed boot-health; GUI
runner permission failures are unresolved and are not recorded as graphics passes.
