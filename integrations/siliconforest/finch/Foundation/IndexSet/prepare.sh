#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

if (($# != 2)); then
    printf 'Usage: %s /path/to/finch /path/to/empty/build-directory\n' "$0" >&2
    exit 2
fi

here=$(cd "$(dirname "$0")" && pwd)
source="$1/userland/Foundation/swift/Darwin/IndexSet.swift"
printf '%s  %s\n' 8b5287509947724e2afd0dec704d7b62858f9948714abb3c76ca11542a496830 "$source" | sha256sum -c
mkdir -p "$2"
test ! -e "$2/IndexSet.swift"
cp "$source" "$2/IndexSet.swift"
patch --fuzz=0 --batch --forward -d "$2" -p1 < "$here/cross.patch"
