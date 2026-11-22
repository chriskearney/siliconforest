# SFAppleAVE source port — milestone 1 boot on the INFO ioctl

The 2026-11-15 pause is lifted for the diagnostic coprocessor boot only.
`start()` publishes `/dev/sfave` and does not touch the hardware. The first
root INFO ioctl maps preloaded TEXT/DATA, snapshots cold DATA, and runs the
T8103 ASC/RTKit handshake. `SFAVE_CAP_H264` means that handshake reached READY.
There is no H.264 encode session in this driver. Do not commit Apple firmware,
DPE tables, or boot blobs.

The first INFO boot had no panic but returned ENODEV19, flags0/caps0,
soc0x8103/segments0 and empty identities, before TEXT mapping. A padded metadata
property guard was fixed and SDK-built as v11, not booted. No encoder hardware
was started. Detached transport/DAPF helpers compile as a separate SDK OBJECT
target, not into the live diagnostic. The commands below document reproducibility
for the host checks. Milestone 1 stops at the handshake; it is not an encoder.

`kernel/upstream` contains unchanged GPL command/ADT parsers from the pinned
upstream in NOTICE. `sfave_preload.c` rejects unknown firmware identities,
missing cold reservations, malformed/overlapping ranges and malformed Acis
input. Its DPE callback adapter ports upstream RMW, enable and masked readback
order. It does not map/power hardware or establish that memory was reserved.
The owned command/ADT copies pass2259+1270 upstream host checks; the new
identity/preload/DPE tests and private-path/extractor checks also pass.
The copied upstream IPC/phase-ring test adds32120 synthetic checks. These
use synthetic/source-defined cases only, no private Apple inputs:

```
bash integrations/siliconforest/m1-ave/host-test/run.sh
```

First live metadata query found pre-loaded AVE with TEXT0xcc000 and
DATA0x128000. The chosen iBoot identity maps exactly to13.5 in pinned m1n1,
consistent with the installed stub's documented13.5 installer selection.
This is not the M1's newer macOS installation. Actual TEXT AppleAVE2FW/RTKit
build tags and early cold DATA preservation are still to be measured before
command submission. No nearest-version ABI override is permitted.

Owner-authorized DPE reproduction, run from the repository root:

```
# Run this read-only script ON SiliconForest; retain JSON privately here.
python3 integrations/siliconforest/m1-ave/tools/preload-metadata.py
# Arguments below are private owner-selected provenance, not repository config.
python3 integrations/siliconforest/m1-ave/tools/fetch-kernelcache.py \
  --url "$APPLE_PUBLIC_IPSW_URL" --build "$APPLE_BUILD" \
  --directory private/ave/new-source
PATH="$LZFSE_TOOL_BIN:$PATH" python3 integrations/siliconforest/m1-ave/tools/extract-dpe.py \
  --kernelcache private/ave/new-source/kernelcache.release.mac13g \
  --source "$APPLE_PUBLIC_IPSW_URL" --build "$APPLE_BUILD" --os-version 13.5 \
  --metadata private/ave/live-adt-metadata.json --output private/ave/new-acis.bin
```

`fetch-kernelcache.py` accepts only HTTPS Apple CDN IPSW URLs. It fetches bounded
ZIP ranges, checks manifest model/version/build, and materializes ONLY the
manifest and J293 kernelcache. All raw ranges, member bytes and per-input
source/build/SHA256 records stay under git-ignored private/ave/. It does not
claim a whole-IPSW hash for a partial fetch. `extract-dpe.py` uses the vendored
GPL extractor with notices and restricts Acis layout to0/1/39 entries. Install
lzfse through our Nix package (`pkgs.lzfse`), not on either Mac.

The first matching table has been extracted and is held privately pending
preload identity/reservation evidence. No firmware image was fetched. No table
has been transferred or installed. Future table installation is allowed ONLY
on the M1 SiliconForest root, with its own private install ledger. Firmware
TEXT/DATA must ONLY be adopted from this machine's iBoot preload. Never upload
those segments to Linux/M5 or reconstruct them from a firmware file.

A diagnostic-only SFAppleAVE service and /dev/sfave INFO now compile against
the SiliconForest SDK. An explicit root INFO ioctl reads metadata and bounded TEXT
identity only when
ADT puts both segments in DRAM below XNU physBase; it neither maps DATA nor
programs hardware, and reports caps=0. It does not assert stage1/2 preserved
cold DATA. sfave-info is the Linux-built client. No extra boot argument is needed (important at the native608-byte limit).
Optional sfave=1 prefetches INFO; modes above1 refuse. No encoder is enabled.

`sfave_ipc.c` ports the exact T8103/13.5 polling boot conversation through
platform callbacks: W1C-before-scratch, DevID13/DevType10, FwIPC/heap info,
seven strict channel descriptors and bounded ready polling. It validates all
descriptors before initializing any ring, retains failed state and never frees
potentially live DMA. Synthetic peer/fault tests cover malformed late
descriptors, address bounds, register failure and finite timeouts. It SDK
compiles but is deliberately NOT called by the diagnostic service: real cold
preload, power, DART/DAPF and coherent memory ownership are still prerequisites.

`sfave_dapf.c` ports T8103's sixteen-slot filter programming through non-posted
32/64-bit callbacks, retaining upstream r4/start/end/r0 order and readback.
It accepts live segment addresses, verifies the known ADT window, rejects a
locked filter or missing stopped/cold-reserved preconditions, and propagates
I/O faults without releasing resources. It emits no firmware/DPE dumps and is
also detached from the diagnostic. Synthetic write-order/width and fault
tests pass; these do not prove actual power, stopped-core or filter state.

Remaining port (paused): early reservation handoff, encoding ioctls,
PMGR/DART/DAPF, actual scratch-register/ring IPC (not RTKit messaging), H264 IPPP
session/teardown and VideoToolbox hardware compression. The independent
OpenH264 software fallback is already installed and qualified. First hardware
milestone is30x1280x720 test-pattern frames, ffmpeg decode, PSNR>=40dB, then
fps/CPU comparison. Source/host checks do not establish any of those results.
