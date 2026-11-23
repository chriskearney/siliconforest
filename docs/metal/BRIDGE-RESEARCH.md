# Metal on SiliconForest: which bridge (research and decision, 22-23 November 2026)

Question from the owner: the best Metal-to-Vulkan bridge for SiliconForest, compared on translation
fidelity, performance, feature coverage, maintenance and fit; port it as SiliconForest's Metal API
layer and work toward a notable Metal app running through it.

**Decision: [steelbrain/metal2vulkan](https://github.com/steelbrain/metal2vulkan)** (translator +
AIR front end + `metal2vulkan-runtime`, the Metal API on Vulkan), on the M1's existing Vulkan
driver (Honeykrisp, SF-AC). Recipe and tests: `integrations/siliconforest/m1-metal2vulkan/`.

## Exclusion (owner, 22 November 2026)

Nothing from **Darling** (darlinghq) or **PureDarwin** is used, vendored, linked or called by this
work, including their Metal code: darling-metal, Indium (and the iglunix original it is forked
from), Iridium, mslc, PureDarwin's MetalKit/`PDMetalLayerBackend`. They appear below only so the
table is complete and the reason they were not chosen is on record. `metal2vulkan` at the pinned
revision contains no reference to any of them (`git grep -i 'darling\|puredarwin\|indium\|iridium'`
over the tree: no match). The earlier experiment SF-AE (`integrations/siliconforest/m1-metal/`) and
the canonical `Metal.framework` installed on 15 November (`finch/Metal`, darling-metal) are
Darling-based; this work does not touch them. Replacing that framework is a decision for the
owner (see "Needs the owner").

## Direction first: what SiliconForest has underneath

- The M1's GPU stack is the Asahi DRM driver in our kernel plus **Mesa**: Honeykrisp Vulkan
  (Omacom's "Borealis" build, `DRIVER_ID_MESA_HONEYKRISP`, API 1.4.363, 153 device extensions,
  vkcube composited zero-copy on Chonkstep) and asahi GL/EGL (SF-AC, SF-G).
- There is **no native Metal driver** (nothing that speaks Metal's command model to the AGX).
- Therefore the bridge must implement **Metal on top of Vulkan**. **MoltenVK** and Mesa's
  **KosmicKrisp** go the other way (Vulkan on top of Metal); they only make sense on a system whose
  native API is Metal, i.e. Apple's macOS. They are out on architecture, not on quality.

## Candidates (all checked against their repositories on 22-23 November 2026)

Activity = commits in the 30 days before 23 November (GitHub API, capped at 100 per page, so
"100" means 100 or more).

| Candidate | What it is | Direction | Licence | Activity | Shader input | API surface | Verdict |
|---|---|---|---|---|---|---|---|
| [steelbrain/metal2vulkan](https://github.com/steelbrain/metal2vulkan) | AIR→SPIR-V translator (compute, render, tessellation, tile, mesh) **and** `metal2vulkan-runtime`, the Metal object model on a Vulkan 1.3 device (`ash`) | Metal on Vulkan | GPL-2.0-or-later OR **LGPL-3.0-or-later** | 100+ (created 22 Jul 2026; head 23 Nov) | AIR / metallib | Rust, Metal-shaped (device, queues, command buffers, compute/render/blit encoders, heaps, ICBs, events, presenting) | **Chosen** |
| [UniXNU/AdrenoMetal](https://github.com/UniXNU/AdrenoMetal) | Objective-C frontend (a `_MTLDevice` subclass plug-in) over metal2vulkan, on Turnip (Adreno) | Metal on Vulkan | MIT | 100+ | via metal2vulkan; source compiles through Apple's own `MTLCompiler` | Obj-C, as a plug-in **inside Apple's** Metal.framework (iPadOS 17) | Not usable as is (needs Apple's framework); **reference design** for our Obj-C layer |
| [oosexgang/hakios-metal](https://github.com/oosexgang/hakios-metal) | Native Metal driver: AIR→NIR→ir3 inside Mesa, Adreno only; hakios also runs UniXNU's metal2vulkan route side by side ([plan](https://github.com/oosexgang/hakios-xnu-kernel/blob/main/docs/metal-plan.md): 100-104 fps native vs 50-57 fps via metal2vulkan on their phone) | native | MIT | 100+ | AIR | Obj-C plug-in in Apple's framework | Not portable (Adreno/ir3); evidence that a native AIR→NIR→AGX path is the long-term speed ceiling |
| [JoshuaSWarren/metal2vk](https://github.com/JoshuaSWarren/metal2vk) | **MSL compute kernels** → SPIR-V via clang (C++ for OpenCL + a `metal_stdlib` shim) + patched clspv; measured on M1 Max/Honeykrisp (31/31 MLX kernels match) | shader only | MIT | 15 | MSL source (compute only) | none (a C runner) | Useful later for the **MSL-source gap** (compute); no API, no graphics |
| [CrossGL/crosstl](https://github.com/CrossGL/crosstl) | Source-to-source shader translator through its own IR (Metal in, SPIR-V/GLSL/... out) | shader only | Apache-2.0 | 100+ | MSL source | none | Candidate for the MSL-source gap; not evaluated on real MSL tonight |
| [google/dawn](https://github.com/google/dawn), [gfx-rs/wgpu](https://github.com/gfx-rs/wgpu) | WebGPU implementations with Vulkan backends | WebGPU on Vulkan | BSD-3 / MIT+Apache-2.0 | 100+ | WGSL / SPIR-V (Metal only as a *backend* output) | WebGPU | Not a Metal implementation: neither reads MSL/AIR nor exposes Metal's object model |
| [KhronosGroup/MoltenVK](https://github.com/KhronosGroup/MoltenVK) | Vulkan on Metal | wrong way | Apache-2.0 | 0 (last push 13 Oct) | SPIR-V→MSL | Vulkan | Out (direction); also below metal2vulkan's floor on macOS per its README |
| Mesa KosmicKrisp ([features.txt](https://gitlab.freedesktop.org/mesa/mesa/-/raw/main/docs/features.txt), "kk") | Vulkan on Metal, in Mesa | wrong way | MIT | Mesa | — | Vulkan | Out (direction) |
| AIR producers: [zig-metallib](https://github.com/TheBCann/zig-metallib), [metal-ir-pipeline](https://github.com/imperatormk/metal-ir-pipeline), [LLVM Metal/AIR target RFC](https://discourse.llvm.org/t/rfc-add-an-apple-metal-air-backend-target/90936), [metal-info](https://deepwiki.com/kagurasumusun/metal-info) | Reverse-engineered LLVM IR → AIR/metallib writers and the MSL→AIR mapping | compilers | various / none stated | low | — | — | Building blocks for an open MSL→AIR compiler (our gap) |
| darlinghq/indium (+ iglunix/indium), Iridium, darling-metal, mslc | Metal on Vulkan (C++ core, AIR→SPIR-V, Obj-C ABI, MSL subset compiler) | Metal on Vulkan | 0BSD / MPL-2.0 / MIT | 100+ | AIR, MSL subset | Obj-C | **Excluded by the owner** (Darling) |

## Why metal2vulkan

**Translation fidelity.** It is built around a written contract: input the device cannot run
exactly is a *typed refusal* naming the Metal feature, never a module that computes something else;
near-equivalents are recorded per pipeline as precision notes
([README](https://github.com/steelbrain/metal2vulkan#readme), `docs/REFUSALS.md`). Its conformance
suite replays **1,325 cases whose answers were recorded on real Metal** on any Vulkan device and
compares field by field (`crates/metal2vulkan-conformance`). No other candidate measures itself
against Metal like this.

**Feature coverage.** Its generated census of the macOS 27.2 SDK's Metal headers
(`docs/METAL-COVERAGE.md`): 623 items implemented, 1,088 missing (sized S/M/L/XL), 424 out of
scope (ray tracing, multi-GPU, IOSurface, drawables, **source compiles** - the consumer's). The
translator covers compute, render, tessellation, tile and mesh pipelines from AIR, argument
buffers, ICBs and function constants. The runtime covers devices, memory blocks, buffers,
textures, samplers, queues, command buffers, events, compute/blit/render encoders, ICBs and
presenting.

**Performance.** Compute runs on the GPU's native arithmetic with recorded differences, a
persistent pipeline cache, and a harness that times every workload against a CPU-checked result.
Third-party numbers: hakios measured metal2vulkan at about half of a native AIR→NIR driver on
Adreno; a native path stays the long-term ceiling, not a reason to start there.

**Maintenance.** The most active candidate (100+ commits in 30 days, a release discipline with
pinned toolchain, typed errors and a conformance ledger), already consumed by two independent
projects (UniXNU, hakios).

**Fit for SiliconForest.**
- Its runtime needs only the Vulkan loader, opened at run time; the binaries we built link
  `libSystem` and `libiconv` alone (checked in the Mach-O load commands) - no Apple framework.
- Its Vulkan floor (Vulkan 1.3, robustness2/nullDescriptor, calibrated timestamps, Bresenham
  lines, descriptor indexing, BDA) is met by Honeykrisp upstream (Mesa `features.txt` lists `hk`
  for every floor extension); whether **our** build on **our** kernel meets it is the first check
  `sf-metal-smoke` prints on the M1.
- Licence: LGPL-3.0-or-later is compatible with the repo's mixed licensing (MIT core, GPL-2.0
  Asahi ports, MPL-2.0 files); fetched at a pin, not copied.
- It is Rust with a Metal-shaped API; SiliconForest still has to provide the Obj-C ABI
  (`Metal.framework`, `MTLCreateSystemDefaultDevice`, the protocols) on top - which is the part
  that makes it *SiliconForest's* Metal layer.

## What it does not give us (the gaps, in the order they block a real app)

1. **The Objective-C `Metal.framework` ABI.** metal2vulkan is Rust; apps call
   `objc_msgSend`. We need an SF framework exporting the Metal classes/protocols, forwarding to
   the runtime through a C ABI. AdrenoMetal's MIT frontend (`NativeBridgeMetalFrontend.mm`,
   about 5,900 lines) is the reference to read; it plugs into Apple's framework, ours must be the framework.
2. **MSL source compilation** (`newLibraryWithSource:`). Out of metal2vulkan's scope; the only
   open MSL compiler that existed (mslc) is Darling's and excluded. Most portable apps (SDL3's GPU
   API, bgfx, Filament, llama.cpp's ggml-metal) hand Metal MSL text at run time, so this gates
   nearly every notable app. Options: clang + a `metal_stdlib` header shim emitting LLVM IR,
   rewritten to AIR (the mapping is documented by metal-info, the IR→AIR rewrite shown by
   zig-metallib/metal-ir-pipeline), feeding metal2vulkan's AIR front end - one shader path for
   precompiled metallibs and source. metal2vk's clspv route covers compute kernels meanwhile.
3. **Presentation**: CAMetalLayer/drawables into WindowServer/Chonkstep. The runtime presents to a
   Vulkan surface; Honeykrisp's Wayland WSI already works on SF (vkcube), so the layer can be a
   Wayland subsurface.
4. **IOSurface** sharing (dma-buf) - the runtime imports/exports dma-bufs; our IOSurface is shared
   memory today (SF-AE).

## Status of the port (23 November 2026, 00:30 PST)

- `integrations/siliconforest/m1-metal2vulkan/`: pin (`eb69a32`), our patch (the conformance
  suite's replay leg on Darwin without Apple's Metal: `--cfg sf_replay_only`), `tools/build.sh`
  (box-only cross-build: rustup nightly-2026-11-03, LLVM's `ld64.lld` against text stubs, no
  Apple SDK; zig's Mach-O linker was dropped because its Rust binaries crash at start on SF),
  `tools/sfm2v.sh` (stage at `/private/var/db/sfm2v`, nothing system-wide), and `smoke/`
  (`sf-metal-smoke`, ours: floor check, a 1 Mi-element compute dispatch checked bit-exact, a
  256x256 triangle checked pixel by pixel against a CPU rasteriser; `sf-llvm-as-cache`, which
  serves the build host's `llvm-as` output by SHA-256 so the M1 needs no LLVM).
- Built for arm64 Darwin (Mach-O, ad-hoc signed): `harness`, `conformance`, `metal2vulkan`,
  `sf-metal-smoke`, `sf-llvm-as-cache`.
- **Box baseline on lavapipe (CPU Vulkan, not the M1):** smoke PASS (compute 0 of 1,048,576
  differ; triangle 0 of 65,536 pixels differ, 20,770 inside); harness: 26 authored pipelines, 0
  refused, every workload matched its CPU reference (exit 0); conformance replay: 139 exact, 243
  announced (equal within a declared notice), 130 divergent, 805 refused, 5 lacks-feature, 3
  never-returned (lavapipe lacks ASTC, multisample counts and more; these numbers are the CPU
  baseline to compare the M1 against, not a claim about the M1).
- **M1 (23 November, 00:38-00:45 PST):** SiliconForest 26.5 (Darwin 25.5.0), Vulkan through
  Borealis (Mesa 26.3.0-devel, derived from Honeykrisp; API 1.4.363, conformance 1.4.6.2) on
  "Apple M1 (G13G B1)". The first stage (zig-linked) died at start with SIGSEGV before any Vulkan
  call. A Rust hello linked by `ld64.lld` ran, so every binary was relinked that way. The M1 went
  offline again at about 00:45 before the relinked stage could be pushed. GPU results are pending.
- **OpenH1 test case:** [OPENH1.md](OPENH1.md). All 2,071 functions of its shipped
  `shaders.metallib` translate under the lavapipe profile.

## Demo plan (notable Metal app)

The chosen test case is OpenH1 (Halo, AGPL): [OPENH1.md](OPENH1.md) has its staged plan and API gaps.

In order; each step has a check that fails loudly:
1. M1: `sfm2v.sh push`, `smoke` (floor verdict, compute, triangle frame), `harness`, `replay`.
2. Windowed: the smoke triangle presented through the runtime's swapchain on a Wayland surface
   under Chonkstep, taking `gui.lock`; captured and compared with the off-screen frame.
3. `SFMetal.framework` (Obj-C, MIT, ours) over a C ABI of the runtime: `MTLCreateSystemDefaultDevice`,
   buffers, textures, compute/render encoders, `newLibraryWithData:` (metallib/AIR), CAMetalLayer.
   Installed side by side (not replacing the canonical framework) until the owner decides.
4. MSL compiler (gap 2), compute first.
5. Notable app: candidates whose licences allow it and that ship no Apple binaries: SDL3's
   `testgpu_spinning_cube` (zlib; MSL text from `cube.*.msl.h`, needs step 4) and llama.cpp's
   ggml-metal backend (MIT; compute only, MSL source, needs step 4's compute path). An unmodified
   Homebrew bottle is the strongest proof (as with ffmpeg on SF), loaded against our framework.

## Needs the owner

- The canonical `/System/Library/Frameworks/Metal.framework` on the M1 is darling-metal
  (installed 15 November by policy; rollback receipt `/private/var/db/sffinch/install-Metal-v1/receipt.json`).
  Under the new exclusion it should be replaced by SFMetal over metal2vulkan once step 3 passes,
  or removed now (returning to no Metal.framework). Not touched tonight.
- SF itself builds on PureDarwin's libobjc/Foundation/CoreFoundation (SF-AE). The exclusion was
  read as covering Metal code; if it is meant to cover PureDarwin as a whole, that is a far larger
  change than Metal and needs its own decision.
- GPU runs that might wedge the machine were previously watched over the M5's UART
  (`m1-vulkan/tools/sfvk-careful.sh`); the M5 is off limits for this thread, so first M1 runs go
  without UART capture.
