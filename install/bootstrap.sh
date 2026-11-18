#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
#
# SiliconForest installer for macOS on a supported Apple silicon Mac (docs/INSTALL.md).
#
#   curl -fsSL https://raw.githubusercontent.com/chriskearney/siliconforest/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/chriskearney/siliconforest/main/install.sh | sh -s -- --dry-run
#
# Options:  --check       what this Mac is and what is on its disk (changes nothing)
#           --dry-run     the full plan, with sizes (changes nothing)
#           --size <GB>   space for SiliconForest (default: what the release recommends)
#           --uninstall   remove SiliconForest and give the space back to macOS
#           --update      replace SiliconForest's boot files with a newer release
#           --help
#
# This file is install/bootstrap.sh with the engine's Python files embedded by
# install/tools/assemble.py; edit those, then run the assembler. Nothing on the disk changes
# before you have seen the plan and typed the word it asks for. Downloads are checked before
# use: the engine (the Asahi Linux installer v0.9.2, which brings its own Python) against the
# SHA-256 below; a release by its SHA256SUMS, whose SSH signature is checked with macOS's own
# ssh-keygen against the key below before anything else of the release is read; then every
# file against SHA256SUMS. Log: ~/Library/Logs/SiliconForest/.

# The whole script is one function, called on the last line: a download cut short runs nothing.
sf_main() {
  set -eu
  ENGINE_VERSION=v0.9.2
  ENGINE_FILE=installer-v0.9.2.tar.gz
  ENGINE_SHA256=484d999e53b4aef27d17c4478e49567e96842f8a6cb35c073a0df5bf0bbe8276
  ENGINE_URLS="https://cdn.asahilinux.org/installer/installer-v0.9.2.tar.gz"
  # The key that signs releases, as an ssh-keygen allowed-signers line:
  #   release@siliconforest namespaces="siliconforest-release" ssh-ed25519 AAAA...
  # Empty: no release has been signed yet, and the installer refuses every release until it is here.
  RELEASE_SIGNERS=""
  RELEASE_BASE=${SF_RELEASE_BASE:-https://github.com/chriskearney/siliconforest/releases/latest/download/}

  cmd=install
  dry=""
  size=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --check) cmd=check ;;
      --dry-run) dry=--dry-run ;;
      --size) [ $# -ge 2 ] || sf_die "--size needs a number of GB"; size=$2; shift ;;
      --size=*) size=${1#--size=} ;;
      --uninstall) cmd=uninstall ;;
      --update) cmd=update ;;
      --help|-h) sf_usage; return 0 ;;
      *) sf_die "unknown option: $1 (try --help)" ;;
    esac
    shift
  done

  # ---- this has to be macOS, natively on Apple silicon --------------------------------------
  if [ "$(uname -s 2>/dev/null)" != Darwin ] || [ ! -e /System/Library/CoreServices/SystemVersion.plist ]; then
    sf_die "The SiliconForest installer runs on macOS (on the Mac you install it on). Nothing was changed."
  fi
  export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
  export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
  if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" != 1 ]; then
    sf_die "This is not an Apple silicon Mac. SiliconForest needs one. Nothing was changed."
  fi
  if [ "$(sysctl -in sysctl.proc_translated 2>/dev/null || echo 0)" = 1 ]; then
    sf_die "This Terminal runs under Rosetta. Open Terminal without \"Open using Rosetta\" and run the command again. Nothing was changed."
  fi
  if [ "$(id -u)" = 0 ]; then
    sf_die "Run the installer as yourself, not with sudo: it asks for your password when it needs it."
  fi

  WORK=${SF_WORK:-$HOME/Library/Caches/SiliconForest/installer}
  LOGDIR=${SF_LOGDIR:-$HOME/Library/Logs/SiliconForest}
  mkdir -p "$WORK" "$LOGDIR" "$WORK/release"
  LOG="$LOGDIR/installer-$(date -u +%Y%m%dT%H%M%SZ).log"
  : > "$LOG"
  sf_say "SiliconForest installer ($cmd${dry:+, dry run}); log: $LOG"
  sf_say "macOS $(sw_vers -productVersion) on $(sysctl -n hw.model) (board $(sysctl -n hw.targettype 2>/dev/null || echo '?'))"

  # ---- our part of the engine: the planner, the gate, the identifiers ----------------------
  SF=$WORK/sf
  rm -rf "$SF"
  mkdir -p "$SF"
  sf_unpack "$SF"

  # ---- Python: the one inside the Asahi installer package (stock macOS has none) -------------
  ENGINE=$WORK/engine-$ENGINE_VERSION
  if [ -n "${SF_PYTHON:-}" ]; then
    PY=$SF_PYTHON
  else
    sf_engine_fetch
    PY=$ENGINE/Frameworks/Python.framework/Versions/3.13/bin/python3.13
    export DYLD_LIBRARY_PATH="$ENGINE/Frameworks/Python.framework/Versions/Current/lib"
    export DYLD_FRAMEWORK_PATH="$ENGINE/Frameworks"
    export SSL_CERT_FILE="$ENGINE/Frameworks/Python.framework/Versions/Current/etc/openssl/cert.pem"
  fi
  [ -x "$PY" ] || sf_die "No Python in the engine package ($PY). Nothing was changed."

  # ---- the release: signed SHA256SUMS and install.json, or none yet ---------------------------
  MANIFEST=""
  REL=$WORK/release
  rm -f "$REL/SHA256SUMS" "$REL/SHA256SUMS.sig" "$REL/allowed_signers" "$REL"/*-install.json
  if [ "$cmd" != uninstall ]; then
    if curl -fsSL --retry 2 -o "$REL/SHA256SUMS" "${RELEASE_BASE}SHA256SUMS" 2>>"$LOG" &&
       curl -fsSL --retry 2 -o "$REL/SHA256SUMS.sig" "${RELEASE_BASE}SHA256SUMS.sig" 2>>"$LOG"; then
      [ -n "$RELEASE_SIGNERS" ] || sf_die "A release exists, but this installer has no release key to check it with. Use a newer installer. Nothing was changed."
      printf '%s\n' "$RELEASE_SIGNERS" > "$REL/allowed_signers"
      if ! ssh-keygen -Y verify -f "$REL/allowed_signers" -I release@siliconforest -n siliconforest-release \
           -s "$REL/SHA256SUMS.sig" < "$REL/SHA256SUMS" >>"$LOG" 2>&1; then
        sf_die "The release's signature is not valid. Nothing was changed."
      fi
      line=$(grep -E '^[0-9a-f]{64}  siliconforest-[A-Za-z0-9._+-]+-install\.json$' "$REL/SHA256SUMS" | head -n 1)
      [ -n "$line" ] || sf_die "The release names no install.json. Nothing was changed."
      ijson=${line#*  }
      curl -fsSL --retry 2 -o "$REL/$ijson" "$RELEASE_BASE$ijson" 2>>"$LOG" || sf_die "Could not download $ijson. Nothing was changed."
      [ "$(sf_sha256 "$REL/$ijson")" = "${line%%  *}" ] || sf_die "$ijson is not the file the signed release names. Nothing was changed."
      MANIFEST=$REL/$ijson
      sf_say "Release: signature checked ($ijson)."
    else
      rm -f "$REL/SHA256SUMS" "$REL/SHA256SUMS.sig"
      sf_say "No SiliconForest release has been published yet."
    fi
  fi

  # ---- downloads of the release, each checked ---------------------------------------------------
  if [ -n "$MANIFEST" ] && [ -z "$dry" ] && { [ "$cmd" = install ] || [ "$cmd" = update ]; }; then
    "$PY" -I "$SF/sf_engine.py" files --manifest "$MANIFEST" > "$REL/files.txt"
    while read -r name bytes sum; do
      sf_fetch "$REL/$name" "$RELEASE_BASE$name" "$bytes" "$sum"
    done < "$REL/files.txt"
  fi

  # ---- the engine decides, shows, asks, and (after one confirmation, under sudo) acts ----------
  set -- "$cmd"
  [ -z "$dry" ] || set -- "$@" "$dry"
  [ -z "$size" ] || set -- "$@" --size "$size"
  [ -z "$MANIFEST" ] || set -- "$@" --manifest "$MANIFEST"
  set -- "$@" --artifacts "$REL" --engine "$ENGINE" --log "$LOG"
  rc=0
  if (: < /dev/tty) 2>/dev/null; then
    "$PY" -I "$SF/sf_engine.py" "$@" < /dev/tty || rc=$?
  else
    "$PY" -I "$SF/sf_engine.py" "$@" || rc=$?
  fi
  sf_say "(log: $LOG)"
  return "$rc"
}

sf_usage() {
  sed -n '6,16p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//' || true
  printf '%s\n' "Usage: install.sh [--check | --dry-run | --uninstall | --update] [--size GB]"
}

sf_die() {
  printf '%s\n' "$*" >&2
  [ -z "${LOG:-}" ] || printf '%s\n' "$*" >> "$LOG"
  exit 1
}

sf_say() {
  printf '%s\n' "$*"
  [ -z "${LOG:-}" ] || printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*" >> "$LOG"
}

sf_sha256() {
  shasum -a 256 "$1" | cut -d' ' -f1
}

# <file> <url> <bytes> <sha256>: download (resuming a partial file), then check size and digest
sf_fetch() {
  if [ -f "$1" ] && [ "$(sf_sha256 "$1")" = "$4" ]; then
    sf_say "  have $(basename "$1")"
    return 0
  fi
  sf_say "  downloading $(basename "$1") ($(($3 / 1000000)) MB)"
  curl -fL --retry 3 -C - --progress-bar -o "$1" "$2" || curl -fL --retry 3 --progress-bar -o "$1" "$2" ||
    sf_die "Could not download $2. Nothing was changed; run the same command again to resume."
  [ "$(wc -c < "$1" | tr -d ' ')" = "$3" ] || { rm -f "$1"; sf_die "$(basename "$1") has the wrong size. Nothing was changed; run again."; }
  [ "$(sf_sha256 "$1")" = "$4" ] || { rm -f "$1"; sf_die "$(basename "$1") is not the file the release names (SHA-256). Nothing was changed."; }
}

sf_engine_fetch() {
  if [ -f "$ENGINE/.verified" ] && [ -x "$ENGINE/Frameworks/Python.framework/Versions/3.13/bin/python3.13" ]; then
    return 0
  fi
  sf_say "Fetching the installer engine (the Asahi Linux installer $ENGINE_VERSION, about 22 MB)"
  tgz=$WORK/$ENGINE_FILE
  got=""
  for u in $ENGINE_URLS; do
    if [ -f "$tgz" ] && [ "$(sf_sha256 "$tgz")" = "$ENGINE_SHA256" ]; then got=1; break; fi
    if curl -fsSL --retry 2 -o "$tgz" "$u" 2>>"$LOG" && [ "$(sf_sha256 "$tgz")" = "$ENGINE_SHA256" ]; then got=1; break; fi
  done
  [ -n "$got" ] || sf_die "Could not get the installer engine with the expected SHA-256. Nothing was changed."
  rm -rf "$ENGINE"
  mkdir -p "$ENGINE"
  tar -xzf "$tgz" -C "$ENGINE"
  [ "$(cat "$ENGINE/version.tag")" = "$ENGINE_VERSION" ] || sf_die "The engine package is not $ENGINE_VERSION."
  : > "$ENGINE/.verified"
}

# @@EMBED@@ (install/tools/assemble.py replaces this line with the engine files)
sf_unpack() {
  here=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || here=""
  [ -f "$here/engine/sf_engine.py" ] || sf_die "Run the assembled install.sh, or this file from a checkout (install/bootstrap.sh)."
  cp "$here"/engine/*.py "$here/models.tsv" "$1/"
}

sf_main "$@"
