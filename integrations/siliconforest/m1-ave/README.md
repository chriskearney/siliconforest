# SFAppleAVE: the Apple Video Encoder on T8103

`/dev/sfave` encodes H.264 IPPP on the M1. `start()` publishes the node and does not touch the
hardware. The first ioctl maps the preloaded TEXT and DATA, snapshots cold DATA, powers the block,
programs DAPF and both DARTs (streams 0 and 1, one table), and runs the ASC/RTKit handshake. A
stream then runs upstream's encode session (`kernel/upstream/ave_session.c`, byte-identical at the
pin in `NOTICE`) on a small Linux API shim (`kernel/lxshim`, `kernel/sfave_lx.c`). There is no
interrupt handler: replies are read by polling the IPC rings, and every wait has a deadline.
B frames and two-reference P frames are off, because H.264 hangs with them on T8103.

- `SFAVE_IOC_INFO`, `SFAVE_IOC_ENC_START`, `SFAVE_IOC_ENC_FRAME`, `SFAVE_IOC_ENC_STOP`:
  `include/sfave/sfave_ioctl.h`. The last close ends a stream its owner left open.
- `user/sfave-info.c`: the state of the coprocessor. `user/sfave-enc.c`: NV12 (a synthetic pattern or
  stdin) to Annex-B.
- The desktop's recorder encodes through this device, with software only when it cannot open:
  `../terminal-app/compositor/wm-darwin-record-ave.patch`, `../desktop/system/sf-screenrecord`.
- FFmpeg: `build-ffmpeg-hw.nix` adds `h264_sfave` (`ffmpeg/0001-h264-sfave-encoder.patch`) and the AVD
  hwaccel to the recorder's build. libx264 stays the default H.264 encoder.

Do not commit Apple firmware, DPE tables, or boot blobs. The AVE firmware is the one iBoot preloaded.
The DPE tunables are read at the first start from
`/Library/Firmware/apple/ave-13.5-dpe-acis_8103.bin`, a file generated from the machine owner's macOS
13.5 kernelcache with the commands below and kept out of this repository. The driver holds only the
loader and the programming path. Without the file the handshake still completes and the miss is logged;
encoding without it has not been tested.

`kernel/upstream` contains unchanged GPL session, command and ADT code from the pinned
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
