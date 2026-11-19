#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

if (($# != 1)); then
    printf 'Usage: %s /path/to/swift-foundation > DateInterval.swift\n' "$0" >&2
    exit 2
fi

source="$1/Sources/FoundationEssentials/DateInterval.swift"
printf '%s  %s\n' b6d8e18c41928597fd42ec2d2b7cdc68d8dccf6cfdb1623c50328ae9921e4d0d "$source" | sha256sum -c >&2
# The retained Objective-C Foundation does not provide NSDateInterval.
sed '/^#if FOUNDATION_FRAMEWORK/,$d' "$source"
