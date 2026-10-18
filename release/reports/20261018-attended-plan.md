# Attended qualification plan — 2026-10-18

This is a plan, not a passed qualification report. Only the owner's available
J313 on OS firmware 13.5 and J516S on OS firmware 14.7 are in scope for this run.
J293, J314S, other M2 machines and M3 Air remain separate qualifications.

Use the normal kernel at 17a9930f20a0895b5980385b0b2d67edda8a24be and m1n1 at
1d6743b21c133a4522e6a3fc74183bad7a11e446. The source-identified stage 2 build is
v2.0.0-siliconforest.dev.g1d6743b21c13. Each manifest records the actual payload
hashes, U-Boot identity and exact board DTB. The J516S additionally admits only
stage 1 v1.6.1-dirty and iBoot-10151.140.19.700.2, preserving its three existing
T6030 GPU/DCP/DCPEXT handoff switches. No stage 1 or OS firmware is replaced.

1. Record the existing running kernel, desktop modes and actual Apple GPU
   OpenGL/Vulkan pixel readback. Preserve these baseline reports locally.
2. Verify current package recovery archives against their original hashes and
   package metadata, then cache them without overwriting differing files.
3. Build/audit the complete ARM64 Mesa profiles, kernel and source-identified
   m1n1 packages. Sign a single-board attended candidate with the existing owner
   key. No public install bootstrap is emitted for an attended candidate.
4. Run signature, full bundle and target preflight before mutation. Preserve
   current configuration, every UKI on root and the current stage 2, menu and
   compressed current UKI on the ESP. Do not delete historical recovery entries.
   The owner approved the smaller approximately 60–70 MiB Pro ESP reserve for
   this attended install and rollback test; the previous 120 MiB lab reserve
   remains the default policy outside this explicit exception.
5. Install through the matched installer and inspect its transaction record,
   boot entry and package audit. Announce before rebooting the owner's Pro.
6. Boot the actual installed default, then run tests/hardware/collect.py with
   --manifest. Require a matching running kernel and stage 2, exact on-disk boot
   chain and packages, hardware GL and Vulkan readback, compositor-owned Mesa
   libraries, responsive desktop, display modes and a locally retained frame.
   Do not publish desktop screenshots, serials, raw journals or private addresses.
7. Use coordinated rollback to restore the previous boot chain and package set.
   Reboot and repeat the baseline renderer/desktop checks. Record any difference;
   do not mark rollback passed from a host fixture or package exit code alone.
8. Publish a qualified immutable child only after all required evidence exists.
   Install that qualified child as the default and verify another actual boot.
   A public catalog may contain only the exact qualified board/firmware pairs.

Existing evidence: the J313 booted the new normal kernel in 29 seconds and
passed boot-health in maclab job j1018-141702-7d66. Its three GUI/OMT invocations
failed with exit 126 because /var/lib/maclab is private to root; that job is
TESTS_FAILED, not a qualification pass. It restored the previously installed
kernel afterward. Ordinary maclab jobs retain the installed m1n1/DTB and do not
prove the new full boot chain. No historical lab baseline or known-good reference
will be rewritten by this procedure.
