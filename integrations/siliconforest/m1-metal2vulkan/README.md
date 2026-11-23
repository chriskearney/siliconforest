# m1-metal2vulkan: the Metal API on Vulkan (metal2vulkan) for SiliconForest

Why this bridge, the alternatives and the owner's exclusion of Darling/PureDarwin code:
[`docs/metal/BRIDGE-RESEARCH.md`](../../../docs/metal/BRIDGE-RESEARCH.md).

## Pieces

| Piece | Source | Licence |
|---|---|---|
| metal2vulkan (translator, AIR front end, runtime, harness, conformance suite) | [steelbrain/metal2vulkan](https://github.com/steelbrain/metal2vulkan) at `M2V_REV` in `pin.env`, fetched by `tools/build.sh` | LGPL-3.0-or-later (of GPL-2.0-or-later OR LGPL-3.0-or-later) |
| `patches/0001-conformance-replay-only-without-native-metal.patch` | ours: under `--cfg sf_replay_only` the conformance suite on Darwin builds its replay leg only, without `objc2-metal` (Apple's Metal); 25 `cfg` lines | LGPL-3.0-or-later (a change to their files) |
| `smoke/` (`sf-metal-smoke`, `sf-llvm-as-cache`) | ours | MIT |
| `tools/build.sh`, `tools/sfm2v.sh`, `pin.env` | ours | MIT |
| Vulkan on the M1 | the installed system's loader `/usr/local/lib/libvulkan.1.dylib` and Honeykrisp (SF-AC); the runtime dlopens the loader | MIT / Apache-2.0 |

Nothing from Darling or PureDarwin is used (NOTICE).

## Build (x86-64 Linux, e.g. the box; no nix, no Apple SDK)

```
integrations/siliconforest/m1-metal2vulkan/tools/build.sh /workspace/sfm2v-build
```

Rust `nightly-2026-11-03` (metal2vulkan's pin) with the `aarch64-apple-darwin` std, LLVM 23.1.6's
`ld64.lld` as the Mach-O linker (it signs ad hoc) against text stubs (zig 0.15.2's `libSystem.tbd`
and a `libiconv.tbd` the script writes), and `llvm-as` 23.1.6 on the host. Do not link with zig's
own Mach-O linker (cargo-zigbuild): its Rust binaries die with SIGSEGV at start on SiliconForest
(thread-local variables), while the same code linked by `ld64.lld` runs. With a
CPU Vulkan driver (lavapipe) on the host it also runs the smoke test, the harness and the
conformance replay there first (the CPU baseline, `runs/`), recording every text handed to
`llvm-as` into `asmcache/` so the M1 needs no LLVM. Output: `$WORK/stage` + `SHA256SUMS`. Rust's warning that `xcrun` cannot find a MacOSX.sdk is expected:
the link uses the text stubs, and the binaries link `libSystem` and `libiconv` only.

## Run on the M1 (installed SiliconForest, over SSH; nothing installed system-wide)

```
tools/sfm2v.sh push          # stage -> /private/var/db/sfm2v (checksummed; old one kept as sfm2v.prev)
tools/sfm2v.sh smoke         # floor verdict, compute 1 Mi floats bit-exact, 256x256 triangle vs CPU
tools/sfm2v.sh harness       # authored compute/render workloads, checked then timed
tools/sfm2v.sh replay        # 1,325 Metal-recorded conformance cases on the M1's GPU
tools/sfm2v.sh revert | remove
```

Environment the runner sets: `CARGO_MANIFEST_DIR` (where the tools find their fixtures and
recordings, under `src/`), `METAL2VULKAN_LLVM_AS=bin/sf-llvm-as-cache`, `SF_M2V_ASMCACHE`.
Off-screen runs take no `gui.lock`; anything windowed takes it first, as the other SF GPU tools do.

## Results

| Where | Test | Result |
|---|---|---|
| box, lavapipe (CPU) | `sf-metal-smoke` | PASS: compute 0/1,048,576 differ; triangle 0/65,536 pixels differ (20,770 inside, fnv `0xf1521a2d`) |
| box, lavapipe | `harness --runtime new` | exit 0: 26 authored pipelines, 0 refused, every workload matched its CPU reference |
| box, lavapipe | `conformance replay --cpu` | 139 exact, 243 announced, 130 divergent, 805 refused, 5 lacks-feature, 3 never-returned (CPU baseline only) |
| M1 | all of the above | **not run yet**: the M1 was unreachable (no ARP answer on 10.1.1.211) from 22 Nov 23:44 PST |

## Census of a shipped metallib

`sf-metallib-census <lib.metallib> <profile.json> [--quiet]` translates every function of a
`.metallib` alone (`Device::compile_function`) for one Khronos device profile and tallies what
compiles and what is refused, with the reason. It is used for OpenH1 (`docs/metal/OPENH1.md`).
