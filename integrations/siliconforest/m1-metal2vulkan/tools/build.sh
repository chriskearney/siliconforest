#!/bin/bash
# SPDX-License-Identifier: MIT
# Builds the metal2vulkan stage for the M1's SiliconForest on an x86-64 Linux host (the box), with no
# nix and nothing installed system-wide except, optionally, lavapipe for the CPU baseline:
#   1. rustup (user-local) with metal2vulkan's pinned nightly + the aarch64-apple-darwin std, and
#      LLVM's ld64.lld as the Mach-O linker against text stubs (zig's libSystem.tbd, our
#      libiconv.tbd); no Apple SDK. zig's own Mach-O linker is NOT used: on SiliconForest its
#      output with thread-local variables (every Rust std binary) crashes at start (SIGSEGV,
#      23 Nov; a C hello without TLV runs, the same Rust hello linked by ld64.lld runs)
#   2. metal2vulkan at $M2V_REV (pin.env), our patch 0001 applied
#   3. Linux binaries -> CPU baseline on lavapipe (if a Vulkan CPU ICD is present), recording every
#      text the tools hand to llvm-as (asmcache/<sha256>.bc) so the M1 needs no LLVM
#   4. aarch64-apple-darwin binaries: harness, conformance (replay leg only), metal2vulkan (CLI),
#      sf-metal-smoke, sf-llvm-as-cache, sf-metallib-census
#   5. the stage tree in $WORK/stage (bin/, asmcache/, share/, src/ = fixtures, device profiles, recordings) and
#      SHA256SUMS
# Usage: tools/build.sh [WORK=/workspace/sfm2v-build]
set -euo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
. "$HERE/pin.env"
WORK=${1:-/workspace/sfm2v-build}
mkdir -p "$WORK" && cd "$WORK"
export CARGO_HOME=${CARGO_HOME:-$HOME/.cargo} RUSTUP_HOME=${RUSTUP_HOME:-$HOME/.rustup}
export PATH="$CARGO_HOME/bin:$WORK/zig-x86_64-linux-$ZIG_VERSION:$WORK/LLVM-$LLVM_VERSION-Linux-X64/bin:$PATH"
export RUSTC_WRAPPER=   # metal2vulkan's own wrapper wants kache; plain rustc here

# 1. toolchains
command -v rustup >/dev/null || curl -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --default-toolchain none --profile minimal
rustup toolchain install "$RUST_TOOLCHAIN" --profile minimal --target aarch64-apple-darwin
[ -x "zig-x86_64-linux-$ZIG_VERSION/zig" ] || curl -sL "https://ziglang.org/download/$ZIG_VERSION/zig-x86_64-linux-$ZIG_VERSION.tar.xz" | tar -xJ
if [ ! -x "LLVM-$LLVM_VERSION-Linux-X64/bin/llvm-as" ]; then
  curl -fsSL -o llvm.tar.xz "https://github.com/llvm/llvm-project/releases/download/llvmorg-$LLVM_VERSION/LLVM-$LLVM_VERSION-Linux-X64.tar.xz"
  tar -xJf llvm.tar.xz "LLVM-$LLVM_VERSION-Linux-X64/bin/llvm-as" "LLVM-$LLVM_VERSION-Linux-X64/bin/lld" \
    "LLVM-$LLVM_VERSION-Linux-X64/bin/ld64.lld" && rm llvm.tar.xz
fi
# text stubs for the Darwin link: libSystem from zig (MIT), libiconv written here
mkdir -p stubs/usr/lib
cp "zig-x86_64-linux-$ZIG_VERSION/lib/libc/darwin/libSystem.tbd" stubs/usr/lib/
ln -sf libSystem.tbd stubs/usr/lib/libc.tbd; ln -sf libSystem.tbd stubs/usr/lib/libm.tbd
cat > stubs/usr/lib/libiconv.tbd <<'TBD'
--- !tapi-tbd
tbd-version:     4
targets:         [ arm64-macos ]
install-name:    '/usr/lib/libiconv.2.dylib'
current-version: 7
compatibility-version: 7
exports:
  - targets:         [ arm64-macos ]
    symbols:         [ _iconv, _iconv_open, _iconv_close, _libiconv, _libiconv_open, _libiconv_close ]
...
TBD
export CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER="$WORK/LLVM-$LLVM_VERSION-Linux-X64/bin/ld64.lld"
DARWIN_LINK="-C linker-flavor=ld64.lld -C link-arg=-syslibroot -C link-arg=$WORK/stubs"

# 2. sources
[ -d metal2vulkan/.git ] || git clone -q "$M2V_REPO" metal2vulkan
git -C metal2vulkan fetch -q origin "$M2V_REV" 2>/dev/null || true
git -C metal2vulkan checkout -q --force "$M2V_REV" && git -C metal2vulkan clean -qfd crates
git -C metal2vulkan apply "$HERE/patches/0001-conformance-replay-only-without-native-metal.patch"
rm -rf sf-metal-smoke && cp -r "$HERE/smoke" sf-metal-smoke

# 3. Linux build, CPU baseline, llvm-as recording
cat > llvm-as-record <<REC
#!/bin/bash
set -o pipefail
T=\$(mktemp); cat > "\$T"; H=\$(sha256sum "\$T" | cut -d' ' -f1)
llvm-as "\$@" < "\$T" > "\$T.bc"; rc=\$?
[ \$rc -eq 0 ] && cp "\$T.bc" "$WORK/asmcache/\$H.bc" && cat "\$T.bc"
rm -f "\$T" "\$T.bc"; exit \$rc
REC
chmod +x llvm-as-record; mkdir -p asmcache runs
B="-p metal2vulkan-harness -p metal2vulkan-conformance -p metal2vulkan --features metal2vulkan/cli --bins"
(cd metal2vulkan && cargo build --release -j"${JOBS:-4}" $B)
(cd sf-metal-smoke && cargo build --release -j"${JOBS:-4}")
llvm-as < metal2vulkan/crates/metal2vulkan-validation/fixtures/public/examples/runtime_examples.ll > runtime_examples.bc
if command -v vulkaninfo >/dev/null && vulkaninfo --summary 2>/dev/null | grep -q llvmpipe; then
  export METAL2VULKAN_LLVM_AS="$WORK/llvm-as-record"
  sf-metal-smoke/target/release/sf-metal-smoke runtime_examples.bc runs/smoke-lavapipe.ppm | tee runs/smoke-lavapipe.log
  (cd metal2vulkan && target/release/harness --runtime new --runs 1 --warmup 0) > runs/harness-lavapipe.log 2>&1 || true
  (cd metal2vulkan && target/release/conformance replay --cpu) > runs/conformance-lavapipe.log 2>&1 || true
  unset METAL2VULKAN_LLVM_AS
else
  echo "build.sh: no lavapipe; asmcache holds only what step 3 assembled directly" >&2
fi

# 4. arm64 Darwin build (the replay-only cfg keeps objc2-metal and every Apple framework out)
(cd metal2vulkan && RUSTFLAGS="--cfg sf_replay_only $DARWIN_LINK" cargo build --release -j"${JOBS:-4}" --target aarch64-apple-darwin $B)
(cd sf-metal-smoke && RUSTFLAGS="$DARWIN_LINK" cargo build --release -j"${JOBS:-4}" --target aarch64-apple-darwin)

# 5. stage
rm -rf stage && mkdir -p stage/bin stage/share stage/src/crates/metal2vulkan-devtools stage/src/crates/metal2vulkan-validation stage/src/crates/metal2vulkan-conformance
D=metal2vulkan/target/aarch64-apple-darwin/release; S=sf-metal-smoke/target/aarch64-apple-darwin/release
cp $D/harness $D/conformance $D/metal2vulkan $D/scratch-holder $S/sf-metal-smoke $S/sf-llvm-as-cache $S/sf-metallib-census stage/bin/
cp -r asmcache stage/asmcache
cp runtime_examples.bc stage/share/
cp metal2vulkan/crates/metal2vulkan-devtools/Cargo.toml stage/src/crates/metal2vulkan-devtools/
cp -r metal2vulkan/crates/metal2vulkan-validation/fixtures metal2vulkan/crates/metal2vulkan-validation/profiles stage/src/crates/metal2vulkan-validation/
for x in recordings probes known-gaps-rt.tsv Cargo.toml; do cp -r metal2vulkan/crates/metal2vulkan-conformance/$x stage/src/crates/metal2vulkan-conformance/; done
for f in LICENSE LICENSE-GPL-2.0 LICENSE-GPL-3.0 LICENSE-LGPL-3.0; do cp metal2vulkan/$f stage/share/metal2vulkan.$f; done
cp "$HERE/NOTICE" stage/share/NOTICE.sfm2v
echo "$M2V_REV" > stage/share/M2V_REV
(cd stage && find . -type f ! -name SHA256SUMS -print0 | xargs -0 sha256sum | LC_ALL=C sort -k2 > SHA256SUMS)
echo "stage: $WORK/stage ($(du -sh stage | cut -f1), $(wc -l < stage/SHA256SUMS) files)"
