# M3 Pro: two displays through a Thunderbolt dock

Source candidate: `88eee3ea5595849a5b8eefe508b7981f488b9bc8`, based on the installed SiliconForest `e4b97a383d11` kernel. This is an attended test candidate, not a hardware qualification claim.

The reproduced topology is a CalDigit TS3 Plus with one monitor on DisplayPort and a second monitor on a USB-C-to-HDMI adapter in the downstream Thunderbolt port. The installed driver starts the first DisplayPort tunnel but rejects the second with `-EOPNOTSUPP`. Both fabric admission and the T6030 PHY clock helper explicitly exclude DP IN1.

The carry adapts the previously built, never boot-tested implementation `8753b9ff351e`. Each tunnel has a source owner, rate and clock-user bit. A disconnect stops only that stream, and the shared PLL is stopped only for the last user. PCLK1 remains enabled while DP IN1 needs it. Failed PLL shutdown retains ownership. Stale sources cannot stop another source's clock, and one source cannot drive both streams simultaneously.

Physical dual-stream wiring is separated from the ordered M1/M2 allocation policy. Native T6030 processors retain their route ownership and expose each connector's actual CRTC. Named mux descriptions are added to the J514S/J516S device trees. Other machines retain their prior policy and clock sequences; this does not enable a new SoC or remove its qualification checks. The GPU UAPI is unchanged.

## Source evidence

- CI runs the new clock/mutation and wiring controls alongside existing M1/M2 clock and route checks.
- Actual-body clock/callback harness: 19 cases, including 128 complete rate/source/start/stop combinations with independent retunes, startup faults, failed cleanup and failed final stop.
- ASan/UBSan is run on the same extracted clock/callback translation unit.
- Shared DT-wiring harness: 22 cases; absent, invalid, partial, legacy and named descriptions.
- Existing M1/M2 clock controls: 16 cases.
- Route snapshot/control harness passes after adding the current clamshell fields to its host fixture.
- Replacing the callback or wiring classifier with the installed driver's body fails the new tests. Six deliberately broken variants are detected: dropping the shared-clock prerequisite, removing source ownership, allowing a duplicate source, stopping a shared PLL, losing a failed-start owner, and selecting the wrong clock.
- All 115 production Apple DTBs compared: only `t6030-j514s.dtb` and `t6030-j516s.dtb` change.
- No changes to `include/uapi` or `rust/uapi`.

Display/PHY/fabric KUnit on the candidate: 362 run, 361 pass, one existing skip, zero failures. Full production build and hardware results must be recorded before promotion. The older broad `dp-release-tests.py` host fixture has pre-existing drift against current display/Type-C fields and does not compile against this baseline; it is not counted as a passing gate. The new clock harness executes the real changed callback and PHY functions directly.

## Installation and hardware gates

Use a new signed matched candidate assembled from the installed bootlogo1 bundle, retaining its stage-1 admission and stage-2 artwork. Kernel and device tree must be installed together; never substitute a DTB independently. Retain the previous UKI, loader, packages and exact configuration for rollback.

Capture both DRM connectors and their actual modes, verify GL/Vulkan readback and kernel health, then test dock reconnect and individual monitor disconnects with the owner. A successful compile or EDID read alone does not establish a working picture. A native HDMI port consumes one of the two external processors; this change does not create a third external display pipeline. Bandwidth sharing PR154 remains outside this carry.

## Hardware admission remains blocked

The first attended candidate (88eee3ea5595) boots and passes hardware OpenGL and Vulkan readback. Both external displays have EDID, separate active CRTCs and firmware mode/swap completions. The owner reports that the downstream USB-C/HDMI Dell still has no HDMI signal, including at 1280x720. The Samsung remains usable. This is a failed physical-display result, not release qualification.

A follow-up adds opt-in packet counters with distinct downstream indices for both streams and dynamic-debug crossbar clock snapshots. Defaults remain unchanged. No release promotion or merge is authorized by these source tests alone.

## USB4 converter-service experiment

At 77d1631f0324, both host video counters increase and both corresponding dock ingress counters increase. Crossbar gate status agrees with its configuration. The owner still reports that the Dell is black; compositor screenshots and packet counters are not physical HDMI qualification.

0303da29c078 tests a possible missing converter-service path on the existing fixed-HDMI T6030 pipeline while borrowed by USB4. It is disabled by default and controllable only by root through appledrm.usb4_sink_service. No new platform or initialization scope is enabled. Direct Type-C, disconnected and crashed paths remain excluded. Display KUnit passes 364 with one existing skip; three deliberate broken variants are caught, and the restored service suite passes 7/7. This experiment must not become a release default without a real picture and further review.
