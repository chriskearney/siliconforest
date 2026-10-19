# PR148 attended qualification plan

This is a plan, not a passed hardware report. The owner authorizes installed
updates and necessary test reboots on J516S/14.7 and J313/13.5. Claude owns
target leases, baseline collection and target changes; Codex owns build,
signing and publication. Preserve every existing recovery entry and historical
lab reference. Do not perform an unrelated system upgrade.

Exact sources: Linux `54add20fd52ed9619483b22e21d79bbefecc2072`, public Mesa
`7515336b3dfbe8943b555ffec9817b9ed64379a8`, m1n1
`aca1258c2d7daad7db7079d4f89bb8217659f7ac`. J516S uses native-gpu with the
normal display/PHY/USB4/PMP stack. J313 uses the normal kernel, the distribution's
existing LLVM runtime owner, and loader packaging without the native-GPU hook.
The memory-floor experiment is excluded and HDMI audio remains opt-in.

Follow the baseline, preflight, signed single-board candidate, actual default
boot, rebooted coordinated rollback and verification procedure in
[the original attended plan](20261018-attended-plan.md), with these source pins
and the new manifests replacing its historical pins. Verify exact package,
Image, DTB, config, loader and U-Boot hashes before each install. Never reuse
old helper scripts' hardcoded transaction paths or identities.

1. Check current leases and session activity. Record existing packages,
   boot chain, all boot menu/recovery files and hashes, desktop/display modes,
   renderer readback and baseline GPU errors. Take leases before mutation.
2. Validate owner signatures, archive metadata and receipts, target runtime
   dependencies, available root/ESP space and cached recovery packages. On
   J516S preserve all three bootable UKIs, every loader backup and existing
   lossless recovery archives. The prior owner-approved attended ESP exception
   applies; do not discard recovery bytes or weaken general policy.
3. Install only the exact signed candidate using its matched installer and
   `--test-candidate`, retaining terminal input for actual package prompts.
   Announce each reboot and verify the installed default, not a one-shot boot.
4. Run the manifest-aware hardware collector: exact running identities and
   package/file hashes, hardware GL/Vulkan pixels, compositor-owned libraries,
   responsive desktop and attached display modes. Exercise and restore screen
   and keyboard brightness. Run the standard Quake demo1 smoke sequentially
   and record settings, FPS and GPU recovery counters.
5. On J516S inspect workqueue warnings, both display modes and display
   failures. HDMI hotplug/standby/audio and suspend/resume need the appropriate
   connected equipment and an available wake person. Record unavailable tests
   explicitly; boot/readback evidence does not qualify them.
6. Coordinate rollback; reboot; verify the prior complete package set,
   tracked boot/config files, default kernel and renderer/desktop baseline.
   Then reinstall the candidate and verify another default boot.
7. Publish only after reviewing actual results. Use new immutable component
   artifacts and exact board/firmware child releases, without broadening board
   admission. Keep desktop frames, raw journals and identifying details local.
8. Run the published versioned one-liner on both Macs and verify actual
   default boots. Promote the latest catalog after those public installer
   checks, then verify its canonical latest-download bootstrap.
