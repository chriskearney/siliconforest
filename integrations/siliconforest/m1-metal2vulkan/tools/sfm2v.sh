#!/bin/bash
# SPDX-License-Identifier: MIT
# The metal2vulkan stage on the M1's installed SiliconForest, over SSH. Nothing of the installed
# system is replaced: everything lives in /private/var/db/sfm2v; Vulkan is the system's
# (/usr/local/lib/libvulkan.1.dylib + Honeykrisp, SF-AC), found by the runtime's dlopen.
#   sfm2v.sh push [STAGE]   copy $WORK/stage (tools/build.sh) to sfm2v.new, compare every file's
#                           SHA-256 there with SHA256SUMS, then sfm2v -> sfm2v.prev, sfm2v.new -> sfm2v
#   sfm2v.sh smoke          floor check, compute and triangle (bin/sf-metal-smoke), frame to /tmp
#   sfm2v.sh harness [ARGS] the compute harness (checked against the CPU, then timed)
#   sfm2v.sh replay [CASES] the conformance suite's replay leg on the M1's GPU
#   sfm2v.sh run CMD...     any command with the stage's environment
#   sfm2v.sh revert         sfm2v.prev back (sfm2v goes to sfm2v.bad)
#   sfm2v.sh remove         rm -rf /private/var/db/sfm2v* (the whole footprint)
# GPU runs are off-screen and take no gui.lock; a windowed run must take it first (README).
set -euo pipefail
read -r -a SSH <<< "${SFM2V_SSH:-ssh -o ConnectTimeout=15 m1}"
D=/private/var/db/sfm2v
ENV="export CARGO_MANIFEST_DIR=$D/src/crates/metal2vulkan-devtools METAL2VULKAN_LLVM_AS=$D/bin/sf-llvm-as-cache SF_M2V_ASMCACHE=$D/asmcache PATH=$D/bin:\$PATH; cd $D;"
case "${1:-}" in
push)
  STAGE=${2:-${WORK:-/workspace/sfm2v-build}/stage}
  tar -C "$STAGE" -cf - . | "${SSH[@]}" "rm -rf $D.new && mkdir -p $D.new && cd $D.new && tar xf -"
  "${SSH[@]}" "cd $D.new && find . -type f ! -name SHA256SUMS -print0 | xargs -0 shasum -a 256 | LC_ALL=C sort -k2" > /tmp/sfm2v.$$.there
  if ! diff -q "$STAGE/SHA256SUMS" /tmp/sfm2v.$$.there >/dev/null; then
    echo "sfm2v: the copy on the M1 differs; left in $D.new"; rm -f /tmp/sfm2v.$$.*; exit 1
  fi
  echo "$(wc -l < /tmp/sfm2v.$$.there) files equal on the M1"; rm -f /tmp/sfm2v.$$.*
  "${SSH[@]}" "rm -rf $D.prev; [ -d $D ] && mv $D $D.prev; mv $D.new $D; cat $D/share/M2V_REV"
  ;;
smoke)   "${SSH[@]}" "$ENV sf-metal-smoke share/runtime_examples.bc /tmp/sfm2v-smoke.ppm" ;;
harness) shift; "${SSH[@]}" "$ENV harness --runtime new ${*:---runs 3 --warmup 1}" ;;
replay)  shift; "${SSH[@]}" "$ENV conformance replay $*" ;;
run)     shift; "${SSH[@]}" "$ENV $*" ;;
revert)  "${SSH[@]}" "[ -d $D.prev ] && rm -rf $D.bad && mv $D $D.bad && mv $D.prev $D && cat $D/share/M2V_REV" ;;
remove)  "${SSH[@]}" "rm -rf $D $D.new $D.prev $D.bad" ;;
*) sed -n '3,15p' "$0"; exit 2 ;;
esac
