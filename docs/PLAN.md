# SiliconForest implementation and maintenance plan

## Intended result

An independently maintained kernel for **existing Apple Silicon Omarchy
installations**, owned and released by `iconidentify`. Users run one bootstrap
command once, then receive signed packages through pacman. This is not an x86
kernel or a new macOS-to-Linux installer.

The SiliconForest repositories and release keys determine what gets shipped.
Upstream projects remain sources of code and fixes; no approval or participation
from those projects is needed to maintain this personal fork. Preserve their
licenses and attribution. Hardware dependencies and downstream ABI contracts
still need to be maintained.

## 1. Establish the baseline

Initial baseline, inspected on 2026-10-18:

- Kernel: Omacom `integration/aurora`,
  `5d570a78a4ab29ac383ec8988be2356dfc6c8a75`, Linux 7.1.12.
- m1n1: Omacom `integration/aurora`,
  `d05ba17dfb771871d608225be42968bbb1e75a18`.
- Personal m1n1 branch: `fec93c15a03b1f5243a3794b495b48ea6a596fcc`,
  which removes only the inherited `AGENTS.md`.
- Kernel config: `tools/aurora-sep/recipes/release20/kernel/config`
  from that kernel baseline, copied into `configs/kernel.config` with its hash.
- Compiler baseline: LLVM 22.1.8; kernel Rust 1.93.1; m1n1 Rust 1.89.0.

The kernel's upstream release20 package used `c46d7dcdb871...`; the requested
integration tip adds release recipe/installer/userspace changes on top. Keep the
requested integration tip as the initial source pin and qualify its own outputs.

Use `siliconforest/next` in each source repository for reviewed integration work. Build from
full locked commits, and create immutable source tags for releases. Update the
source lock whenever either source branch advances. Do not force-push published
release tags. The historical kernel repository remains archived and is not part
of the release workflow. The new `iconidentify/siliconforest-linux` repository
preserves full Linux history and has its own Git storage and origin remote.

### Reviewed M3 source integration

The maintained kernel now includes the PR358/PR363 M3 Pro/Max source stack as an
isolated development variant, selected by `CONFIG_SILICONFOREST_M3` and disabled
in the normal configuration. Its separate UAPI header, Type-C dependencies and
DTB paths preserve the current implementations. The source manifest and review
record the exact merged commit and local fixes. Host checks and enabled driver
object/DTB compilation passed. Current m1n1 and Mesa source profiles are now
reviewed and pinned in sources.lock.json. Full kernel/module linkage,
source-derived J516C board data and target hardware qualification remain before
an M3 binary release. Native Mesa requires the alternative native UAPI, including
its G17 driver on Neo; the default kernel configuration remains unchanged. Do not enable this profile in the public bootstrap by default.

### Current source and toolchain update

The canonical source names are siliconforest-linux, siliconforest-m1n1 and
siliconforest-mesa. The default bootloader now includes current Asahi upstream,
Eryk's J514S handoffs, the Max handoff and the Air ISP fix. Its upstream GPL
transition and older MIT/component notices are retained. Default bootloader
builds now use Rust 1.99.0; the separate older Neo profile uses 1.89.0. M4/M5
profiles are source snapshots and are not qualified. Ten inherited G15 stand-in
fixture failures remain documented; do not represent the complete suite as green.
The original baseline above is historical, not the current release pin.

## 2. Build and package

The checked-in helpers compile a distinct kernel and a stage 2 m1n1 payload.
The next work is packaging these outputs and recording a reproducible builder:

1. Build in an isolated builder with a pinned image digest and saved package
   inventory. The current source/toolchain pins are a starting point, not a claim
   of bit-for-bit reproducibility. Record bindgen, pahole, LLVM, Rust, config,
   source commits, environment, and build logs.
2. Produce `linux-siliconforest` and `linux-siliconforest-headers` for aarch64.
   Use a unique kernel release suffix for each distinct build. Install modules,
   the kernel image, and Apple DTBs beneath `/usr/lib/modules/<release>/`.
   Verify that existing Omarchy initramfs/Limine hooks create the intended entry.
3. Give the kernel its own package namespace and allow it alongside the stock
   kernel. Audit shared modprobe files, initramfs presets, and boot hooks for
   ownership collisions. Do not reuse the stock kernel's package base.
4. Package `m1n1-siliconforest` as the selected m1n1 provider, with appropriate
   `provides`, explicit conflicts, licenses, and restoration of the previous
   provider documented. A single ESP has a single active stage 2; two m1n1 package
   names do not create independent boot chains.
5. Retain the distribution's U-Boot initially, pin its package version and hash in
   every release, and verify the supported version range on target machines.
   Fork U-Boot only when a specific required change justifies maintaining it.
6. Assemble stage 2 from this m1n1, the exact kernel's DTBs, the qualified U-Boot,
   and existing machine configuration. Never collect DTBs by globbing multiple
   installed kernel releases together.
   For J613, the DTB's new disabled internal Type-C route requires kernel
   17a9930f20a0895b5980385b0b2d67edda8a24be or a descendant. Ship kernel and
   DTBs from one source pin. Its panel also depends on atcphy1 probing. The
   m1n1 external-firmware marker is a reservation promise; the kernel enables
   the controller and suppliers. The normal 14.7 display profile and 26.6.2
   camera support are separate qualification cases.

Boot-chain reference:

`Apple firmware -> installed m1n1 stage 1 -> m1n1 stage 2 + DTBs + U-Boot -> Limine/GRUB -> kernel + initramfs`

The existing installed stage 1 is outside the replacement-kernel installer.
Stage 2 is `<the paired ESP>/m1n1/boot.bin`. Locate the paired ESP using
`/proc/device-tree/chosen/asahi,efi-system-partition`, verify its PARTUUID and mount,
and preserve its vendor firmware and machine-specific settings.

## 3. Qualify a small support matrix

Start with one available Mac and its exact board/SoC and firmware identity.
Expand to other boards only with recorded results. M1/M2 is a sensible initial
qualification cohort if those are the machines available. Treat M3 and later
model support as separate qualification work.

Reuse [maclab](https://github.com/iconidentify/maclab) for kernel smoke tests:
boot health, GUI startup, actual hardware renderer, Wi-Fi, Bluetooth, audio,
keyboard/trackpad, USB, and a deliberate return to the known-good kernel.
Record explicit pass/fail/not-tested results per board. Real suspend/resume needs
an attended wake test; a devices-only suspend test is not proof of full suspend.

maclab's ordinary kernel boot uses the **currently installed DTB and stage 2**.
It cannot establish that newly built DTBs or m1n1 work. Qualify the exact installed
pair with recovery available. The lab's
[A/B install design](https://github.com/iconidentify/maclab/blob/main/docs/ab-installs.md)
is a proposal, with unresolved dual-install details; do not assume that it is
already a working automatic recovery system.

Existing M3 userspace contains exact Aurora kernel marker checks. The M3 Pro
release20 recipe writes `aurora-m3pro-profile`, and its Mesa launcher admits
specific source identities. Do not forge those markers for an unqualified
SiliconForest build. Either establish compatibility and maintain an explicit userspace
contract, or keep that model out of the supported hardware-rendering matrix.
Other experimental GPUs require the same care with their userspace interfaces.

Keep Touch ID, APFS/SEP policy changes, GPU experiments, and unrelated desktop
changes outside the initial replacement-kernel bootstrap. The inherited kernel
still contains upstream drivers; document their behavior accurately and avoid
automatically enabling new services or changing machine configuration.

## 4. Create the public package channel

Create signed pacman packages and a signed repository database under SiliconForest's
own hosting, using separate `testing` and `stable` channels. A static HTTPS host
can serve the repository; do not require upstream release assets for installation.
Retain the prior stable package set and source tags for recovery.

Create the signing identity as a deliberate owner action. Keep private signing
material out of this repository, logs, and PR builds. Export a public keyring
package and publish the full fingerprint independently. The bootstrap must pin
that fingerprint and verify the signed keyring/repository chain. HTTPS alone does
not provide independent verification against compromise of the publishing account.

For every release, publish a signed manifest with:

- Channel, release ID, supported boards, firmware identities/ranges, test report.
- Kernel commit, m1n1 commit, config hash, generated config, builder identity.
- Package names/versions, hashes, signing fingerprint, U-Boot identity.
- DTB-set digest, required Mesa/userspace versions, bootloader compatibility.
- Previous release and instructions for restoring its complete boot components.

CI can compile, check package layouts, and upload candidate artifacts. Promotion
to stable follows hardware results for that manifest. The initial CI in this repo
only checks development tooling; it does not build, sign, or release packages.

## 5. Implement the one-command bootstrap

The final one-liner will download an installer from an immutable, qualified
SiliconForest release. Publish it only after this path has been exercised end to end:

1. Run preflight as the normal user: supported aarch64 board, Omarchy install,
   firmware identity, installed kernel and boot packages, active bootloader,
   paired writable ESP, free space, and package-manager state.
2. Provide `--check` and `--dry-run`. Unsupported boards or firmware stop before
   package or ESP writes. Experimental support requires a named explicit option.
3. Verify the release manifest and pinned signing identity. Download and verify
   the full package set before changing anything. Request elevation only for the
   package and boot operations.
4. Preserve the existing kernel package and boot entry. Save `boot.bin`, boot
   configuration, provider package versions, m1n1 settings, and package rollback
   artifacts with hashes and a recovery description accessible from macOS recovery.
5. Add the signed pacman channel idempotently. Install the approved package set
   with a full-system upgrade strategy; do not perform an Arch partial upgrade.
6. Build and verify the initramfs/UKI and boot entry. Stage a complete new
   `boot.bin` beside the old one, flush it, and rename on the same ESP. Detect and
   report hook errors; a successful package transaction alone is not boot success.
7. Select a test boot where supported, with an explicit return path, and print
   the exact changes plus recovery instructions. Do not reboot without the user's
   instruction. Record success after boot health checks.

An old kernel entry alone is **not** full rollback: it still receives the active
m1n1 and DTB. Test compatibility with that fallback, and document offline stage 2
restoration for failures before the kernel menu. A bootloader one-shot does not
recover a failure inside m1n1 itself.

## 6. Maintain a manageable release cadence

Review upstream Linux stable/security updates and selected Apple Silicon changes
weekly. Stage them in the personal branches, update the lock, build candidates,
run the supported-board checks, then publish to testing. Promote a known candidate
to stable after its recorded qualification. Respond sooner to relevant security
fixes or regressions. Do not automatically merge or publish a moving upstream tip.

Start with one stable line and one testing line. Publish release notes listing
changes, actual tested hardware, limitations, and rollback. Keep kernel source,
boot-chain support, and userspace dependencies together in the support policy.
This is a downstream kernel maintenance project initially; adding broad GPU,
firmware, installer, and desktop ownership would substantially increase the work.

## Next deliverable

One signed **testing** release for one explicitly qualified Mac, with working
packages, an install/rollback rehearsal, and recorded results for the exact
kernel/m1n1/DTB/U-Boot set. Then implement and exercise the bootstrap on that same
configuration before advertising a stable public one-liner.

References: [Asahi boot chain and version interactions](https://asahilinux.org/docs/alt/boot-process-guide/),
[m1n1 build and stage 2 guide](https://asahilinux.org/docs/sw/m1n1-user-guide/),
[Apple Silicon OS interoperability](https://asahilinux.org/docs/platform/open-os-interop/).
