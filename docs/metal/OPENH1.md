# OpenH1 (GOAT H1) as the metal2vulkan test case on SiliconForest

The goal is OpenH1's Mac renderer (Metal) running on the M1 13" Pro (J293) under SiliconForest. It
would go through metal2vulkan on Honeykrisp (Borealis). This page covers the staged plan, the Metal
API surface OpenH1 uses compared with what metal2vulkan provides, and the gaps. Bridge choice:
[BRIDGE-RESEARCH.md](BRIDGE-RESEARCH.md).

- Project: <https://github.com/OpenH1/goath1>, AGPL-3.0-or-later. Surveyed at
  `4549a984dc3a87708c652a77b449af7731686e59` (2026-11-22).
- Nothing from OpenH1 is vendored here. Its code, its built `shaders.metallib` and any Halo data
  are staged only on the build box and the M1. They are never committed.
- Halo game data (maps, and recordings, which carry guest memory taken from the maps) is
  proprietary. It is used only from Chris's own copy and is never downloaded.
- Darling and PureDarwin (including darling-metal, Indium, Iridium and mslc) are excluded, as they
  are throughout this work.

## How OpenH1 drives Metal

- `port/macos/host_metal.m` and `xgpu_metal*.m` (about 26k lines) are the Mac backend. It is
  Objective-C against `Metal.framework`, `QuartzCore` (`CAMetalLayer`, `CAMetalDisplayLink`) and
  `MetalFX`, with SDL3 (Cocoa) for the window and input.
- Shaders: `tools/macos_shaders.py` compiles the MSL emitted by `port/linux/src/xgpu_msl.c` into
  `shaders.metallib` with Apple's `xcrun metal`. The game loads it with `newLibraryWithURL:`
  (`xgpu_metal.m:1734`). Pipelines come from the library's functions or from function-constant
  specialisation (`xgpu_combiner_fragment`, 39 constants).
- `newLibraryWithSource:` is only a fallback. It is used for the fixed and clear shaders when the
  library lacks them (`:1883`), the combiner when the library lacks it (`:1891`), a pixel program
  the library does not have (`:2073`, e.g. a custom map's), and the `resolve_light` tile shader and
  one `host_metal.m:577` debug path.
- `halo_replay` (`port/macos/tools/halo_replay.m`) replays a recording made with
  `HALO_RENDER_RECORD` through the same backend, with no game loop. A recording holds guest memory
  derived from the maps, so it counts as game data.
- `xgpu_metal_test` (`port/macos/tests/xgpu_metal_test.m`) needs no data. Its shaders are MSL
  strings compiled at run time (`newLibraryWithSource:`), in an SDL3 window.

## API surface vs metal2vulkan

metal2vulkan = translator (AIR→SPIR-V) + `metal2vulkan-runtime` (Rust Vulkan objects with Metal
semantics). It has no Objective-C ABI. Statuses are from metal2vulkan's `docs/METAL-COVERAGE.md`
at the pinned revision.

| OpenH1 uses | metal2vulkan | SiliconForest must supply |
|---|---|---|
| `MTLCreateSystemDefaultDevice`, buffers, textures (incl. BC, depth/stencil, MSAA), samplers, render/blit/compute encoders, `addCompletedHandler:`, depth bias, fill mode, mipmap generation, visibility results | runtime implements | the ObjC `Metal.framework` shim (`MTLDevice` etc. as ObjC objects over the Rust runtime) |
| `newLibraryWithURL:` (shaders.metallib) | translator parses metallib; the URL method itself is "missing (S)" | read the file and call `Library::from_metallib` |
| Function constants (`MTLFunctionConstantValues`) | translator implements | pass-through |
| `newLibraryWithSource:` (fallbacks above, `xgpu_metal_test`) | out of scope (no MSL compiler) | an MSL→AIR compiler. No acceptable open one exists (the only one, mslc, is Darling's, so excluded). **Gap.** |
| `MTLBinaryArchive` (`newBinaryArchiveWithDescriptor:` ×3, `MTLPipelineOptionFailOnBinaryArchiveMiss`) | out of scope (consumer's) | an archive that always misses or a `VkPipelineCache`. OpenH1 falls back to a plain compile on a miss and runs with no archive. |
| `CAMetalLayer`, `nextDrawable`, `presentDrawable:` | runtime presents to a `VkSurfaceKHR` | `QuartzCore` `CAMetalLayer` over SF's window server surface. **Gap.** |
| `CAMetalDisplayLink` (`host_metal.m:2418`) | none | display-paced callbacks from the compositor's frame clock. **Gap.** |
| MetalFX `MTLFXTemporalScaler`/`SpatialScaler` | none | have `supportsDevice:` answer NO; OpenH1 then skips upscaling (`xgpu_metal_temporal.m:298-303`) |
| Tile pipelines (`newRenderPipelineStateWithTileDescriptor:`, `dispatchThreadsPerTile:`, imageblocks) for the MSAA light resolve | translator implements `TileRenderPipelineDescriptor`; runtime is "missing (L)" | have `supportsFamily:MTLGPUFamilyApple4` answer NO; OpenH1 then averages the codes instead (`xgpu_metal.m:2151`) |
| `supportsFamily:` | "missing (S)" | the answers are chosen to steer OpenH1 onto paths the runtime has (above) |
| Memoryless storage | runtime has none on the M1 path | used only when `HALO_METAL_MEMORYLESS` is set; leave it unset |
| Counter sample buffers / GPU timestamps | "missing (M)" | statistics only. Return nil and let OpenH1 skip timings. |
| `MTLCaptureManager` | none | stub (debug only) |
| SDL3 Cocoa window (`SDL_WINDOW_METAL`) | n/a | SDL3's Cocoa backend needs AppKit `NSWindow`/`NSView` with a `CAMetalLayer`. **Gap** (depends on SF's AppKit). |

## Shader census: OpenH1's shipped library through the translator

Library: `shaders.metallib` from the OpenH1 release build 2550 (`OpenH1-debug.dmg`), 21,229,283
bytes, sha256 `ba0089b3…ca704`. It is project build output (AGPL) and was staged on the box only.
Tool: `sf-metallib-census`
(`integrations/siliconforest/m1-metal2vulkan/smoke/src/bin/`). It translates each function alone
(`Device::compile_function`, constants at their defaults) for one Khronos device profile.

| Device profile | Functions | Compiled | Refused |
|---|---|---|---|
| `gate-lavapipe-x86_64` (lavapipe, Mesa 26.0.8) | 2,071 (184 vertex, 1,887 fragment, 0 compute) | **2,071** | 0 |
| `runtime-floor` (metal2vulkan's minimum device) | 2,071 | 1,885 | 186 fragment: `SubgroupOperations; needs SubgroupStage(Fragment)` |

Every shader in the shipped game translates to SPIR-V. The only device-dependent need is subgroup
operations in fragment shaders, used by 186 pixel programs and `xgpu_world_ao_pass`. Honeykrisp's
`subgroupSupportedStages` decides whether that works on the M1. It will be checked there with a
`vulkaninfo --json` profile of the real device. Not yet covered: each specialisation of
`xgpu_combiner_fragment` (the constant values come from the game at run time), and running the
translated SPIR-V (`compile_function` translates and validates; it does not draw).

## Stages

1. **Docs, licence and box build.** Done for docs and licence. OpenH1's `configure.py` on Linux
   emits only Linux/Windows/Android targets. The macOS target needs Apple's clang, the macOS SDK
   (Metal, QuartzCore and AppKit headers) and `xcrun metal`, none of which can be used on the box or
   on SF. So the Mac binaries cannot be built here, and SF needs the ones OpenH1 ships.
   `shaders.metallib` is taken from the release. The Linux `halo_replay` target configures, but its
   build needs clang and cmake. It was not built, because it uses OpenH1's own Vulkan backend, not
   Metal.
2. **Smallest piece.**
   - The library half is done: the census above.
   - `xgpu_metal_test` needs `newLibraryWithSource:` (no MSL compiler; see the gap) plus SDL3/AppKit.
   - `halo_replay` (off-screen, no `--window`) is the smallest real path. It needs `newLibraryWithURL:`,
     the core encoders, `supportsFamily:` answers, a missing archive and no presentation. It also
     needs the SF ObjC `Metal.framework` shim over metal2vulkan-runtime (not written yet) and a
     recording. **A recording is game data: Chris would have to make one with his own copy**
     (`HALO_RENDER_RECORD=…` on his Mac) and place it on the M1 himself.
3. **The full game.** Needs everything in stage 2 plus `CAMetalLayer`/`CAMetalDisplayLink`, SDL3
   Cocoa windows, input, audio, and Chris's own maps.

## What SF must build next (in order)

1. The ObjC `Metal.framework` shim over `metal2vulkan-runtime`: device, resources, encoders,
   `newLibraryWithURL:`, function constants, `supportsFamily:`, nil archives and counters. This is
   enough for an off-screen `halo_replay`.
2. `CAMetalLayer`/`CAMetalDrawable` on SF's compositor surface (Vulkan WSI), then
   `CAMetalDisplayLink`.
3. An MSL compiler. There is no acceptable open one today, so OpenH1 runs only with the shipped
   library. Custom maps whose pixel programs the library lacks would fail to draw.
