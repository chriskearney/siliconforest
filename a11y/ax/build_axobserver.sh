#!/bin/bash
# Build the SiliconForest AX Observer (macOS only, requires Xcode CLI tools)
# Output: a11y/ax/axobserver (native Darwin arm64/x86_64 binary)
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/axobserver"
swiftc "$DIR/axobserver.swift" -o "$OUT" -O
echo "Built: $OUT"
echo "Run:   $OUT   (then switch apps to generate AX events)"
