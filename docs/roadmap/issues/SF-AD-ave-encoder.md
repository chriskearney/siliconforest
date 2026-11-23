# SF-AD — AVE encoder source-port study

**Status, 22 November 2026: H.264 encode works on the M1 (J293/T8103).** The November 15 pause below
is history. `/dev/sfave` boots the preloaded 13.5 firmware on its first ioctl and encodes IPPP
H.264 (`integrations/siliconforest/m1-ave/README.md`). Observed on the M1:

- Synthetic 720p: 50.96 dB against the source, about 3.6 ms per frame. 1920x1088 and 2560x1600 decode.
- The desktop recorder encodes 2560x1600 at up to 60 fps through the AVE (about 16 ms per frame) and
  uses software only when the AVE cannot open (`terminal-app/compositor/wm-darwin-record-ave.patch`).
- FFmpeg `-c:v h264_sfave` output decodes through `-hwaccel sfavd`, one AVD job per frame, with picture
  hashes equal to software decode (`m1-ave/build-ffmpeg-hw.nix`).
- `bakein.sh` with normal capture on this kernel: 50 PASS, 0 FAIL, 2 SKIP.

Not done or not established: HEVC, B frames and two-reference P frames (they hang on T8103), encoding
without the DPE tunables file, a VideoToolbox encoder, and an install step that generates that
file (it is on this M1 only, never in this repository). The default `rebase/build-kc.nix` has no
room for this kext; `m1-ave/tools/pack-collection.sh` adds it to the installed collection. Stopping
GPU clients once left them stuck in the kernel and blocked the next GL client on a fence until a
reboot; that was not reproduced in the gate and its cause is open.

**Paused by owner on 2026-11-15. Source and private inputs are preserved.
No further AVE builds, boots, probes or extraction are authorized.**
The first target is T8103/J293; preserve the working PDAppleAVD decoder and audio.

## Paused 2026-11-15

The first hardware INFO attempt used CODEX-TB's additive CIO07AVE collection
and the immutable v7 diagnostic. It booted without a panic and retained NHI
startup, but INFO failed at 09:00:28Z: `abi=1 bytes=192 flags=0 caps=0
soc=0x8103 segments=0 error=19` (ENODEV). Returned TEXT/DATA sizes and flags
were zero; iBoot, firmware and RTKit identity strings were empty. Thus the
probe accepted no firmware segments. This does **not** establish absent or
incompatible firmware: metadata validation failed before TEXT was mapped.
Previously observed live ADT still had pre-loaded=1, TEXT0xcc000/flags3,
DATA0x128000/flags0. The diagnostic rejected the padded256-byte chosen
firmware-version property before looking for its NUL at offset16. A bounded
metadata fix and stage diagnostics were SDK-built as v11 but never booted.
The detached ring/DAPF work was host-tested and SDK-compiled separately; it
was not linked into the v11 live diagnostic and has never touched hardware.

Actual AppleAVE2FW/RTKit tags, exact preloaded ABI/table compatibility and full
cold DATA preservation were not established. Stage1/2 heap placement supplies
partial allocator-exclusion evidence only. No DATA mapping/copy, AVE power,
reset, MMIO, DART/DAPF programming, mailbox start or hardware encoding occurred.
VideoToolbox's working OpenH264 software compression is independent of AVE.

Existing ignored private inputs are retained at `private/ave/kernel-source-v1/`
(bounded IPSW ZIP ranges, BuildManifest and kernelcache),
`private/ave/acis-13.5-v1.bin` (504-byte extracted DPE table), and
`private/ave/live-adt-metadata-v1.json` through `live-adt-metadata-v4.json`
(read-only metadata, not firmware dumps). Source/build/input/output hashes stay
only in `private/ave/ledger.json`, `kernel-source-v1/acquisition-ledger.jsonl`,
`metadata-ledger.jsonl` and `toolchain-ledger.jsonl`; extraction stdout/stderr
remain alongside them. No firmware image or RAM dump was acquired, and no
extracted table was transferred or installed. Existing build/boot receipts
remain under ignored `runs/sffinch/`; nothing is deleted.

CODEX-TB restored known-good non-AVE CIO07 at09:03:02Z and reaped its UART
reader at09:03:03Z. CIO08 was then installed and verified at09:08:35Z without AVE
(capsule `c63179b7b9f2…`). Its 57-module manifest contains no PDAppleAVE,
and live service/device-node and boot-argument inventories confirm no AVE
kext or `pdave` argument. NHI and the internal desktop remain healthy.
All prior inclusion/probe requests are withdrawn in coordination log and
requests-for-CODEX-TB.md; the kernel owner must retain a non-AVE collection
with no pdave boot argument. No AVE boot or probe is queued by this stream.

Only after an explicit owner resume, the next step would be review the already
built bounded metadata fix and arrange a fresh INFO-only slot on the kernel
owner's then-current known-good base. Establish actual TEXT identity and
complete cold DATA preservation before selecting ABI/table or implementing
live power/DMA/session integration. The30-frame hardware PSNR/fps/CPU milestone,
VT hardware compression and compositor recording hookup remain unimplemented.

The sections below retain the source study and pre-pause history; their future
work and reproduction commands are not authorization to resume.

Owner decision on 15 November authorizes extracting the Acis DPE table from a
macOS kernel image. Inputs and extracted bytes stay under git-ignored
`private/ave/`; source/build/SHA-256 belong only in its private ledger. The only
authorized transfer of extracted bytes is to this M1's SiliconForest firmware
directory, recorded in an install ledger. Reproducible extraction code belongs
in the repository; Apple bytes do not. Encoder firmware remains exclusively
this machine's iBoot preload. No firmware file may be fetched or installed.

First measure the live `/arm-io/ave` identity/version properties and segment
sizes on SiliconForest. The M1's macOS27.0 installation does not identify the
preload. Upstream selects exact13.5 or26.6/26.6.2 ABIs and rejects unknown
versions; do not force13.5 on an unknown image. Match the kernel/table choice to
that measurement and document the compatibility evidence before any encode.
CODEX-TB owns the kernel collection and boot slots; request the early preload
reservation and kext on its current base rather than building another base.

Live read-only IORegistry metadata on15 November now confirms `pre-loaded=1`,
TEXT size`0xcc000` (flags3), DATA size`0x128000` (flags0), and chosen
iBoot identity mapping exactly to13.5 in the pinned m1n1 firmware table. This
matches upstream13.5 H13G placement sizes. Actual TEXT build-string validation
and cold DATA reservation are still pending; size agreement alone is not ABI
proof. A matching13.5 kernelcache and manifest were subsequently acquired by bounded
ZIP range requests from Apple CDN; Acis extraction produced the expected0/1/39
entry layout and is held privately pending the remaining checks. CODEX-TB has the early
reservation/identity request. Detailed live metadata remains private.

A second property-name inventory found `segment-names=__TEXT;__DATA` and no
AVE-specific build/identity property. The chosen system firmware is newer than
the stub iBoot; neither that nor the main macOS installation replaces the
TEXT-tag check. The SDK-built diagnostic now publishes root-only INFO with
lazy inventory and requires no extra boot argument (the current native kernel
command line is close to its608-byte limit). It still leaves DATA untouched
and reports no encoder capabilities. The copied upstream IPC/ring selftest
now passes32120 synthetic checks in addition to2259 command and1270 ADT checks.
No live mailbox handshake, DMA ordering or encoding result is implied.

The reference is aquarat's GPL-2.0-only
[apple-m-series-ave-driver, pinned at 9ab14e45281e8f61fb499b760408028171a5f2b5](https://github.com/aquarat/apple-m-series-ave-driver/tree/9ab14e45281e8f61fb499b760408028171a5f2b5).
It is cloned, git-ignored, under `sources/ref-ave` with a sparse source/document
checkout. No Apple-derived data was checked out from upstream. The later owner-authorized
kernel/DPE acquisition is held only under ignored private/ave/, with its provenance
recorded only in the private ledger. No firmware image or RAM dump was fetched. Upstream documentation
is CC BY-SA 4.0; this report cites it and the code without copying its prose or
tables. Its LGPL FFmpeg patches are separate from the GPL driver.

## Decision and first scope

The session/command code is a useful source-port base. It is **not ready to run
under the owner's “iBoot-preloaded firmware only” rule**. The current Linux path
still opens a firmware Mach-O file, and its enabled DPE initialization loads
AppleAVE2-derived register tables. The firmware file path must be replaced with preload adoption; the DPE table
may now be extracted privately from a matching kernel image before a hardware attempt. A Linux build alone would not
settle either problem.

Start with one T8103 instance, H.264, NV12, one reference, no B frames, fixed QP,
explicit dimensions/strides and a bounded synchronous request. Upstream records
H.264 B/two-reference hangs on this SoC; its source clamps that configuration.
Do not enable HEVC, P010, reordering, multipass, multiple clients, suspend or
warm recovery merely because their fields exist. The older M1 results in
[docs/89](https://github.com/aquarat/apple-m-series-ave-driver/blob/9ab14e45281e8f61fb499b760408028171a5f2b5/docs/89-t8103-m1.md)
are upstream evidence, not SiliconForest evidence. Later ADT/cold-DATA changes
explicitly say their current hardware runs remain outstanding in
[docs/99](https://github.com/aquarat/apple-m-series-ave-driver/blob/9ab14e45281e8f61fb499b760408028171a5f2b5/docs/99-adt-placement.md)
and [docs/100](https://github.com/aquarat/apple-m-series-ave-driver/blob/9ab14e45281e8f61fb499b760408028171a5f2b5/docs/100-no-apple-data.md).

## Source structure and PureDarwin mapping

The driver directory is about 24k lines, including roughly 3.4k lines of wire
ABI headers. `ave_session.c` alone is about 5.8k lines. Porting is substantially
more than translating the V4L2 entry points.

| Upstream piece | Role | SiliconForest mapping / required work |
|---|---|---|
| `ave_soc.c/.h`, `ave_adt.c/.h`, `ave_version.c` | SoC banks, power topology, live firmware placement and exact firmware ABI selection | Read the **live** `/arm-io/ave` and `dart-ave` through IORegistry/ADT. Validate J293's actual segments; never adopt the J313/J274 physical addresses in the reference row. Keep version rejection. The selector recognizes 13.5 and 26.6/26.6.2, but T8103's mapped image/DATA facts and demonstrated path are 13.5 H13G. Controller macOS version does not identify the M1's stub firmware. |
| `ave_drv.c`, `ave_hw.h` | Probe/start/stop, power, interrupts, DPE initialization | Follow `m1-avd/kernel/PDAppleAVD.cpp`: IOKit service shell, MMIO descriptors, interrupt event sources, locks, bounded waits, `pd_lfile` device. Use `pd_soc.cpp`'s `pd_pmgr_enable_node`/reset/state helpers with AVE's own domains and ordering. Both T8103 ME domains matter; AVD gate IDs are not substitutes. T8103's row has no PMP vote. |
| `ave_fw.c` | Image adoption/copy, TEXT validation, DATA handling, DMA mapping | Replace file-based `request_firmware()` paths with a validated, reserved iBoot-preload handoff. This is a new adapter, not PDAppleAVD's firmware-file reader. Preserve TEXT and cold DATA before a general allocator can overwrite them. |
| `ave_dapf.c`, `ave_smmu.c` | CPUDART/DAPF permissions, stream diagnostics, observed SMMU faults | Reuse DART page-table/IOBufferMemoryDescriptor primitives from `pd_avd_dart.cpp` and sound's fixed DART adapter, **not their address-space policy**. AVD allocates from 64MiB in a 2GiB window; AVE needs fixed firmware/DATA IOVAs, device-specific streams and DAPF translations. SMMU code is an optional observer, not another generic DART reset target. |
| `ave_ipc.c`, `ave_abi_boot.h`, `ave_abi.h` | Boot exchange, FwIPC channels, phase-bit rings and wire layouts | AVE uses eight scratch registers/doorbell and shared rings. It explicitly **does not use RTKit endpoint messaging**. Existing RTKit infrastructure supplies patterns for DMA ownership, interrupts, cache barriers and waits; its HELLO/endpoint transport cannot be reused as AVE's protocol. Implement the actual AVE handshake/ring state machine. |
| `ave_cmd.c/.h`, `ave_session.c/.h`, `ave_gop.h` | Commands, work-surface sizing, session lifecycle, frame submissions and replies | Retain GPL provenance and the protocol packing; replace Linux allocations, work queues/completions and timeout mechanics through a narrow OS interface. Validate every firmware reply before using offsets or lengths. Keep GOP policy minimal initially. |
| `ave_v4l2.c/.h` | vb2/m2m queues, controls, mmap/DMABUF, Linux format enumeration | Replace with `/dev/pdave`; do not emulate V4L2 in XNU. Keep policy, sizes and state transitions that are independent of vb2. A future userland `libpdave` feeds VTCompressionSession; do not put GPL session bodies in an LGPL FFmpeg userland module. |

These mappings are code observations from the
[upstream driver](https://github.com/aquarat/apple-m-series-ave-driver/tree/9ab14e45281e8f61fb499b760408028171a5f2b5/driver),
particularly [the non-RTKit transport](https://github.com/aquarat/apple-m-series-ave-driver/blob/9ab14e45281e8f61fb499b760408028171a5f2b5/driver/ave_ipc.c),
and our existing [AVD kernel shell](../../../integrations/puredarwin/m1-avd/kernel/PDAppleAVD.cpp),
[DART allocator](../../../integrations/puredarwin/m1-avd/kernel/pd_avd_dart.h)
and [PMGR interface](../../../integrations/puredarwin/m1-sound/kernel/pd_soc.h).
They do not establish that AVE DMA, interrupts or firmware run on our M1.

## Apple-derived inputs: exact requirements and possible replacements

### What “Acis DPE input unresolved” means

It is a small **host-side hardware register initialization program**, not the
encoder firmware and not simply a set of optional quality presets. For T8103,
the `Acis_8103` input supplies one CAC-default and 39 CAC-8-bit
`{register offset, bits to clear, bits to set}` entries. The reference applies
them after power-on, checks the readback, and enables the DPE. Its normal source
is a table in **AppleAVE2.kext**, not the ASC firmware iBoot preloads.

**We cannot currently promise any encoding without it, including lower-quality
encoding.** The driver's own comment says the option became enabled by default
because every working encode needed it. `dpe_tunables=0` merely skips the entire
programming/enable function and leaves reset defaults; returning zero there is
not an encoder result. The reviewed M1 success used the correct Acis table.
Another SoC's table failed readback on M1. Treat the missing input as a functional
bring-up prerequisite, not a quality tradeoff. This does not prove that an
independently developed initialization could never work; it means that neither
successful output nor a safe reduced-function fallback has been demonstrated.
See the pinned [driver's rationale and loader](https://github.com/aquarat/apple-m-series-ave-driver/blob/9ab14e45281e8f61fb499b760408028171a5f2b5/driver/ave_drv.c#L235)
and [M1 differences](https://github.com/aquarat/apple-m-series-ave-driver/blob/9ab14e45281e8f61fb499b760408028171a5f2b5/docs/89-t8103-m1.md#2-the-port).

**No demonstrated derivation from iBoot's remaining memory was found.** The
preloaded ASC TEXT/DATA and its tunable records are different inputs; the driver
notes that this firmware does not program the host DPE block. Nothing reviewed
identifies the Acis host table inside those preloaded segments. Merely preserving
them therefore does not resolve this dependency. If iBoot actually leaves the
DPE programmed, an early, on-device capture of its powered register state could
help develop an independent initializer. But that premise is unmeasured; a
power-domain reset may already erase it, and final register values do not recover
the original clear/set masks, ordering, or volatile/status-bit semantics. Reading
unpowered or wrong-generation banks can reset the machine. Such a future capture
needs the kernel/boot owner and must keep all runtime Apple-derived bytes private
on the device. That earlier derivation study performed no MMIO access or memory
dump. The later authorized private kernel-table extraction is described above;
no preloaded firmware segment was copied.

The distinction between **ASC firmware tunables in DATA** and **host DPE
register tables** is essential. An empty ASC table was used successfully in
upstream's older M1 experiment; that experiment still used the Acis DPE table.
It does not prove the DPE data can be omitted.

| Input in the current reference | Origin / current use | Owner-compliant route and limit |
|---|---|---|
| `apple/ave_h13g.bin` | Unwrapped AppleAVE2FW_H13G Mach-O, requested by `ave_fw_load()` and other identity/restore helpers | Do **not** fetch, copy or install this firmware file. An authorized kernelcache/IPSW is solely a source for the private DPE table. Adopt only the copy iBoot already loaded, identified by `pre-loaded` and `segment-ranges` (32-byte entries). Rewrite image-walk/validation paths to consume reserved segments and known protocol/layout facts. Whether all bytes needed for validation/restart remain in J293's preload must be measured; the upstream file loader cannot simply be called unchanged. |
| `apple/ave-13.5-dpe-acis_8103.bin` | Host DPE settings from AppleAVE2.kext's `gs_sAVE_DPE_CfgSet_Acis_8103`, normally generated from a macOS13.5 `kernelcache.release.mac13g` (the extractor also finds the same set in the other13.5 kernelcaches). Acis has 0 CAT-default, 1 CAC-default and 39 CAC-8-bit entries. `AVEDPE01` stores three counts plus `{offset,clear,set}` triples. | **Extraction now authorized; version compatibility remains unresolved.** Extract from the selected matching kernel image into `private/ave/`, with source/build/hash only in the private ledger. Do not substitute another SoC table or assume the13.5 table fits an unidentified preload. `dpe_tunables=0` skips initialization/enable; it does not establish even low-quality encoding. The source says every working encode needed it; the cited T8103 success used Acis. No successful omission or preload-memory derivation was found. An early private on-device register capture might inform independent initialization only if iBoot actually programmed and preserved the block, which is unmeasured. Final values alone do not reveal masks/order/status semantics. |
| Pristine DATA / `apple/ave-13.5-h13g-data-pristine.bin` | Firmware DATA plus BSS and iBoot fills, used for owned DATA/restart. The T8103 reference DATA span is0x128000; actual placement must come from the live ADT. On stock-m1n1 J274 Linux overwrote the preload; the Linux solution builds DATA from the firmware **file**. | Reserve/copy this boot's cold DATA before allocator use or first ASC start, retain it privately on-device, restore only after proven quiescence. Do not dump it to Linux/M5/repository. If already overwritten, fail and require a fresh boot with a proper handoff; a disk firmware file or another machine's dump is outside scope. Check that our boot memory reservation actually covers both segments before any driver experiment. |
| ASC tunables (`TUNS`/`TUNZ`) and tag fills (`CpAd`, `WrAd`, `IOBA`, `SOC_`) | iBoot writes fields in DATA. The image has an empty ASC-tunable table; upstream reconstructed T8103 DATA with that table when its live copy was gone. | Prefer the exact cold preload. A deliberate empty-table reconstruction would need the corresponding preloaded image bytes and separately reviewed validation, not borrowed H13S values. Upstream's successful empty-ASC result does not authorize skipping DPE tables. |
| STKG stack-guard field | Per-boot iBoot value; an older research builder retained a sample cookie | Keep the current boot's value private with its DATA snapshot. Do not copy the research sample; no shared sample value is needed for the interface. |
| Command/field/register facts, DevInfo identifiers and image hashes | Wire/API facts and identity digests in GPL source; not firmware byte blobs | Retain field-by-field provenance. Docs/100 separately flags43 Start_AVC and9 per-frame default-field values as an author judgment case. Prefer named independent settings over copying opaque blocks. Hash identity alone does not supply firmware or certify a different version. |

The input inventory and extraction format are checked against
[docs/100](https://github.com/aquarat/apple-m-series-ave-driver/blob/9ab14e45281e8f61fb499b760408028171a5f2b5/docs/100-no-apple-data.md),
[the DPE loader](https://github.com/aquarat/apple-m-series-ave-driver/blob/9ab14e45281e8f61fb499b760408028171a5f2b5/driver/ave_drv.c#L612),
[the firmware loader](https://github.com/aquarat/apple-m-series-ave-driver/blob/9ab14e45281e8f61fb499b760408028171a5f2b5/driver/ave_fw.c#L1648)
and [T8103's SoC data](https://github.com/aquarat/apple-m-series-ave-driver/blob/9ab14e45281e8f61fb499b760408028171a5f2b5/driver/ave_soc.c).
Only the reviewed `m1-ave/tools` wrappers implement the newly authorized
extraction scope. Upstream firmware-fetch/reconstruction commands remain
outside that scope.

## Local host-only checks

On this Linux builder,upstream's ASan/UBSan command-builder self-test passed
2259 checks,including its negative control;the synthetic ADT parser passed1270
checks. The optional real Apple ADT case was skipped because no dump was fetched.
Logs are in `runs/sffinch/ave-{abi,adt}-host-selftest.log`. These compile ordinary
host programs only,not a kernel/module,and establish no hardware or firmware
execution. No Apple-derived input was needed for these host checks.

## Proposed `/dev/pdave` contract

Use a versioned, fixed-width ABI modeled on the ownership discipline of
`pdavd_ioctl.h`, rather than its stateless codec-control payloads. AVE is a
**stateful encoder**: its context owns reference frames and work surfaces.
The ioctl/session contract remains a design proposal. Initial pure preload/DPE validation/programming code, unchanged command/ADT
parsers, and a diagnostic-only PDAppleAVE service with INFO ioctl are staged
under `m1-ave`. The kext SDK build passes; codec capabilities stay zero, DATA
is untouched, and no power/DMA/session or hardware result is implemented yet.

| Operation | Initial behavior |
|---|---|
| INFO | ABI/size, actual firmware identity/availability, supported codec/pixel format, dimension/stride limits, busy/fault state. Advertise no codec until its prerequisites are valid. |
| CREATE | H.264/NV12, dimensions, Y/UV strides, fixed QP, frame-rate numerator/denominator, bounded buffer counts; returns an opaque per-open context ID. One active hardware session initially; second CREATE returns busy. |
| ALLOC / MAP | Kernel-owned, wired input/output buffers mapped through AVE's own DART. Input mapping writable, output mapping read-only to userland. Return generation-tagged IDs/lengths, never physical addresses or caller-chosen IOVAs. Defer external IOSurface/DMABUF import. |
| ENCODE | Input buffer ID, output buffer ID, PTS/duration and force-IDR flag; bounded synchronous completion returning produced length, DTS/PTS, keyframe flag and actual error/status. Initial no-reordering policy keeps one frame in flight. Validate all ranges/overflow before DMA. |
| DRAIN / DESTROY | Flush valid pending output, then prove firmware stopped referencing buffers before unmapping/freeing. On timeout mark the context/device faulted; never report successful drain or recycle an active DMA buffer. A reboot may be the only valid recovery. |

An optional later poll/dequeue interface can add asynchronous jobs after lifetime
rules are measured. Keep explicit sizes/reserved-zero fields and Linux/Darwin
cross-layout checks. A future CLI generates NV12 locally, submits30 1280x720 IPPP
frames, then software-decodes the output with ffmpeg: frame count/dimensions,
valid timing, ≥40dB PSNR on that test pattern, repeated context teardown and
bounded fault handling. That would be new M1 evidence; current upstream PSNR or
host ABI checks are not substitutes.

## Effort, risks and next decision

My estimate, **after** preload and DPE prerequisites are resolved:1–3 engineering
days for the OS interface/source split;3–7 for power/DART/DAPF/boot IPC;5–10 for
session/ioctl plumbing and the first repeated30-frame H.264 test. These are
planning ranges, not measured performance or a delivery promise. Firmware/DPE
input investigation has no bounded estimate yet. HEVC, CVPixelBuffer import,
VTCompressionSession and recovery/suspend need separate follow-on work.

The largest risks are cold DATA loss during boot, firmware-build/ABI mismatch,
DAPF writes at the wrong power/start phase causing a system error, incorrect
DART ownership/cache ordering, firmware reply lengths and timeout teardown of
active DMA. The reference's H.264 B-frame restriction and latest unrerun changes
must remain visible. Preserve separate GPL kernel files and LGPL/MIT userland
interfaces; keep preloaded firmware bytes on-device. Authorized kernel/DPE
inputs stay under private/ave/, except the explicitly permitted M1 table install.

Next work is the live preload/version inventory, a reproducible private DPE
extractor, then the source port and CODEX-TB integration request. The owner has
resolved the permission question; actual ABI/table compatibility and cold DATA
reservation remain technical prerequisites. Keep software encoding available;
do not report AVE hardware support before the30-frame/PSNR milestone.

## Diagnostic collection capacity, 15 November

The earlier CIO03 collection and packed kernel.bin were independently reproduced
byte for byte from its frozen derivation inputs. Adding only the stripped INFO
kext fails the unchanged overlap checker: the added module pushes prelink info
into kernel TEXT. The first unstripped attempt and stripped retry remain failed
receipts. No boot was reserved and no target changed. CODEX-TB has the exact
layout finding and diagnostic artifact for its next capacity-qualified current
collection. Do not drop unrelated modules or boot a collection rejected by this
gate to obtain a version string.

CIO07 later passed the additive capacity gate with all57 original module UUIDs
unchanged and only PDAppleAVE added. CODEX-TB performed that first INFO boot,
then restored non-AVE CIO07 as recorded in the pause section. The earlier CIO03
capacity failures remain preserved; they are not the final hardware result.

## The screen recorder's seam for AVE (DESK11, 17 November)

The owner asked that the H.264 screen recorder be able to use AVE once it works, with the
software encoder kept as the fallback. No AVE work was done (the stream is paused); the
compositor (`chonkstep-darwin-desktop`, compositor patch 35) has the seam:

- **Frames**: NV12 (4:2:0, two planes), BT.709 limited range, converted on the GPU from the frame on
  the screen into one of five shareable buffers per recording size: a linear asahi GEM object
  exported as a dma-buf, `width * height * 3 / 2` bytes, Y at offset 0 (pitch `width`), interleaved
  U/V at `width * height` (pitch `width`), width a multiple of 8, height of 2. Each frame comes with
  its time (microseconds, on a 60 Hz grid) after its GPU fence passed. The buffer is the encoder's
  until it hands it back (no copy is made on the compositor's side).
- **Interface** (`wm-darwin/src/encoder.rs`): `trait Encoder { fn push(&mut self, frame: &NvFrame)
  -> Result<(), String>; fn finish(self: Box<Self>) -> Result<EncoderSummary, String>; }`, where
  `NvFrame` has the mapped bytes, the size, the dma-buf fd and the time. `encoder::open` picks the
  back end by policy `record_encoder=auto|software|hardware` when a recording starts:
  `auto` = hardware when `hardware::open` succeeds, else software; `hardware` alone fails the
  recording with a notice when there is none.
- **Software back end** (in use): `/usr/local/bin/ffmpeg` with libx264, a separate GPL program
  (`integrations/puredarwin/desktop/recording/build-ffmpeg-x264.nix`), fed a Matroska stream of
  raw NV12 frames with their times over a socket; ffmpeg also writes the QuickTime file.
- **Hardware back end** (`encoder::hardware`): a stub whose `probe` says "not available".
  What the AVE side must provide for it: a `VTCompressionSession` (our VideoToolbox) or a direct
  `/dev/pdave` session that (1) takes NV12 frames of the recording's size (up to 2560x1600) from
  an IOSurface-compatible `CVPixelBuffer` wrapping that dma-buf (or imports the dma-buf for its own
  DART: the "external import" deferred in the contract above), with a PTS; (2) returns H.264 (or
  HEVC) access units with PTS/DTS, keyframe flag and the parameter sets (avcC or Annex B); (3)
  releases each input buffer when the hardware no longer reads it (the recorder then reuses it);
  (4) drains and finishes on demand. Muxing stays separate from encoding: the elementary stream
  goes into a QuickTime file through ffmpeg (`-c copy` from a stream with times) or the
  recorder's own movie writer (`record.rs`, which today writes Photo-JPEG samples).
