#!/bin/bash
# Proves the real-disk compile key is off in what we ship (DESIGN §14.11, ENGINE §12).
#
#   check-real-disk-gate.sh <binary-or-.app>...        fail if any of them contains InternalDiskAuthority
#   check-real-disk-gate.sh --expect-compiled <binary> positive control: fail unless it does
#
# Also always fails if the environment or Package.swift tries to open the key. `InternalDiskAuthority`
# is the only type that can point the live backend at an internal disk, and it exists only when
# SF_REAL_DISK_WRITES is defined at build time.
set -euo pipefail
cd "$(dirname "$0")/.."

expect=absent
if [[ "${1:-}" == "--expect-compiled" ]]; then expect=present; shift; fi

if [[ -n "${SF_REAL_DISK_WRITES:-}" || -n "${SF_ALLOW_REAL_DISK_WRITES:-}" ]]; then
  echo "✗ SF_REAL_DISK_WRITES / SF_ALLOW_REAL_DISK_WRITES are set in the environment" >&2; exit 1
fi
if grep -v '^[[:space:]]*//' Package.swift | grep -q 'SF_REAL_DISK_WRITES'; then
  echo "✗ Package.swift defines SF_REAL_DISK_WRITES" >&2; exit 1
fi

bins=()
for arg in "$@"; do
  if [[ -d "$arg" ]]; then
    while IFS= read -r f; do bins+=("$f"); done < <(find "$arg/Contents/MacOS" "$arg/Contents/Helpers" -type f -perm -u+x 2>/dev/null)
  else
    bins+=("$arg")
  fi
done
[[ ${#bins[@]} -gt 0 ]] || { echo "usage: check-real-disk-gate.sh [--expect-compiled] <binary-or-app>..." >&2; exit 2; }

status=0
for b in "${bins[@]}"; do
  [[ -f "$b" ]] || { echo "✗ not a file: $b" >&2; status=1; continue; }
  # (count rather than grep -q: with pipefail, grep closing the pipe early would read as "absent")
  n=$(strings -a "$b" | grep -c 'InternalDiskAuthority' || true)
  if [[ "$n" -gt 0 ]]; then found=present; else found=absent; fi
  if [[ "$found" == "$expect" ]]; then echo "✓ $(basename "$b"): InternalDiskAuthority $found"
  else echo "✗ $(basename "$b"): InternalDiskAuthority is $found, expected $expect" >&2; status=1; fi
done
exit $status
