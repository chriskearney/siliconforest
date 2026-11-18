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
# SHA-256 below, a release against its manifest, whose signature is checked with the public
# key below before the manifest is read. Log: ~/Library/Logs/SiliconForest/.

# The whole script is one function, called on the last line: a download cut short runs nothing.
sf_main() {
  set -eu
  ENGINE_VERSION=v0.9.2
  ENGINE_FILE=installer-v0.9.2.tar.gz
  ENGINE_SHA256=484d999e53b4aef27d17c4478e49567e96842f8a6cb35c073a0df5bf0bbe8276
  ENGINE_URLS="https://cdn.asahilinux.org/installer/installer-v0.9.2.tar.gz"
  # PEM public key (ECDSA P-256) that signs SiliconForest release manifests. Empty: no release has
  # been signed yet, and the installer refuses every release until the key is put here.
  RELEASE_KEY=""
  MANIFEST_URL=${SF_MANIFEST_URL:-https://github.com/chriskearney/siliconforest/releases/latest/download/siliconforest-manifest.json}

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

  # ---- the release: a signed manifest, or none yet -------------------------------------------
  MANIFEST=""
  REL=$WORK/release
  rm -f "$REL/manifest.json" "$REL/manifest.json.sig"
  if [ "$cmd" != uninstall ]; then
    if curl -fsSL --retry 2 -o "$REL/manifest.json" "$MANIFEST_URL" 2>>"$LOG" &&
       curl -fsSL --retry 2 -o "$REL/manifest.json.sig" "$MANIFEST_URL.sig" 2>>"$LOG"; then
      [ -n "$RELEASE_KEY" ] || sf_die "A release manifest exists, but this installer has no release key to check it with. Use a newer installer. Nothing was changed."
      printf '%s\n' "$RELEASE_KEY" > "$REL/release-key.pem"
      if ! openssl dgst -sha256 -verify "$REL/release-key.pem" -signature "$REL/manifest.json.sig" "$REL/manifest.json" >>"$LOG" 2>&1; then
        sf_die "The release manifest's signature is not valid. Nothing was changed."
      fi
      MANIFEST=$REL/manifest.json
      sf_say "Release manifest: signature checked."
    else
      rm -f "$REL/manifest.json" "$REL/manifest.json.sig"
      sf_say "No SiliconForest release has been published yet."
    fi
  fi

  # ---- downloads of the release, each checked ---------------------------------------------------
  if [ -n "$MANIFEST" ] && [ -z "$dry" ] && { [ "$cmd" = install ] || [ "$cmd" = update ]; }; then
    "$PY" -I "$SF/sf_engine.py" files --manifest "$MANIFEST" > "$REL/files.txt"
    while read -r name url bytes sum joined; do
      if [ "$url" = - ]; then
        sf_join "$REL" "$name" "$bytes" "$sum"
      else
        sf_fetch "$REL/$name" "$url" "$bytes" "$sum"
      fi
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

# <dir> <name> <bytes> <sha256>: join <name>.partNN (already checked) into <name>, then check it
sf_join() {
  if [ -f "$1/$2" ] && [ "$(sf_sha256 "$1/$2")" = "$4" ]; then
    return 0
  fi
  cat "$1/$2".part* > "$1/$2.joining"
  mv "$1/$2.joining" "$1/$2"
  [ "$(sf_sha256 "$1/$2")" = "$4" ] || sf_die "$2: the joined parts are not the file the release names. Nothing was changed."
  rm -f "$1/$2".part*
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

# Generated by install/tools/assemble.py from install/bootstrap.sh and install/engine/: do not edit.
sf_unpack() {
  cat > "$1/models.tsv" <<'SF_EMBED_0_END'
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
#
# The Macs the SiliconForest installer accepts. One line per board, fields separated by TABs.
# A release can narrow this list (its signed manifest names the boards it was built for); it
# can never widen it.
#
#   target          `sysctl -n hw.targettype` (the board, e.g. J293)
#   hw_model        `sysctl -n hw.model` (Apple's model identifier)
#   device_class    the board's "compatible" name as the Asahi installer uses it (j293ap)
#   chip            the SoC
#   status          supported = installable; any other word = refused with this line's note
#   macos_min       oldest macOS the installer runs on for this board
#   macos_max_major newest macOS major version tested for this board (newer ones are refused)
#   stub_firmware   macOS versions whose boot firmware SiliconForest's drivers are written against
#                   (the stub volume is built from that version's restore image, as Asahi does)
#   name            Apple's marketing name
#
# What a new board needs before it gets a line with "supported" (docs/INSTALL.md, "Other Macs"):
# a SiliconForest kernel collection, device tree handling and stage 1/stage 2 built and booted on
# that board; its storage write fence proven; one real install and uninstall on that board by a
# person who can recover it; its firmware version recorded here.
#
#target	hw_model	device_class	chip	status	macos_min	macos_max_major	stub_firmware	name
J293	MacBookPro17,1	j293ap	T8103	supported	13.5	26	13.5	MacBook Pro (13-inch, M1, 2020)
SF_EMBED_0_END
  cat > "$1/sf_disk.py" <<'SF_EMBED_1_END'
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""The Mac's internal disk as diskutil describes it. Parsing only: nothing here runs a command.

Inputs are the property lists of `diskutil list -plist`, `diskutil apfs list -plist`,
`diskutil info -plist <disk or partition>` and `diskutil info -plist /`. The way the system
disk and the free areas are found follows the Asahi Linux installer (src/diskutil.py,
MIT, "Copyright (c) 2021 The Asahi Linux contributors"): the internal physical disk whose
first partition is the iBoot system container, usable range 40 to size-34 sectors of 512
bytes, gaps under 16 MiB ignored.
"""
import hashlib
import json
import plistlib
from dataclasses import dataclass, field

FREE_THRESHOLD = 16 << 20
ALIGN = 1 << 20
LINUX_TYPES = {'Linux Filesystem', 'Linux', '0FC63DAF-8483-4772-8E79-3D69D8477DE4'}
EFI_TYPES = {'EFI', 'C12A7328-F81F-11D2-BA4B-00A0C93EC93B'}
APPLE_SYSTEM_TYPES = {'Apple_APFS_ISC', 'Apple_APFS_Recovery'}
STUB_NAME = 'SiliconForest'
BOOT_LABEL = 'SFBOOT'


def align_up(v, a=ALIGN):
    return (v + a - 1) // a * a


def align_down(v, a=ALIGN):
    return v // a * a


def gb(v):
    return '%.1f GB' % (v / 1e9)


@dataclass
class Volume:
    dev: str
    name: str
    roles: list
    filevault: bool = False
    locked: bool = False


@dataclass
class Container:
    ref: str
    store: str
    ceiling: int
    free: int
    volumes: list = field(default_factory=list)

    def system_names(self):
        return [v.name for v in self.volumes if v.roles == ['System']]


@dataclass
class Part:
    dev: str
    offset: int
    size: int
    content: str = ''
    uuid: str = ''
    label: str = ''
    free: bool = False
    container: object = None

    @property
    def end(self):
        return self.offset + self.size

    def kind(self):
        if self.free:
            return 'free'
        if self.content in APPLE_SYSTEM_TYPES:
            return 'apple-system'
        if self.content == 'Apple_APFS':
            return 'apfs'
        if self.content in EFI_TYPES:
            return 'efi'
        if self.content in LINUX_TYPES:
            return 'linux'
        return 'other'


@dataclass
class Install:
    """SiliconForest's pieces as found: the stub container, SFBOOT, the root partition."""
    stub: object = None
    boot: object = None
    root: object = None
    problems: list = field(default_factory=list)

    @property
    def complete(self):
        return bool(self.stub and self.boot and self.root and not self.problems)

    def parts(self):
        return [p for p in (self.stub, self.boot, self.root) if p is not None]


class LayoutError(Exception):
    pass


class Layout:
    def __init__(self, disk, size, block_size, parts, containers, macos_ref, internal=True):
        self.disk, self.size, self.block_size = disk, size, block_size
        self.parts, self.containers, self.macos_ref, self.internal = parts, containers, macos_ref, internal

    # ---- construction -------------------------------------------------------------------
    @classmethod
    def parse(cls, list_plist, apfs_plist, infos, root_info):
        """infos: {device identifier: `diskutil info -plist` output} for the disk and its partitions."""
        lst = plistlib.loads(list_plist)
        apfs = plistlib.loads(apfs_plist)
        infos = {k: plistlib.loads(v) for k, v in infos.items()}
        root = plistlib.loads(root_info)
        containers = {}
        for c in apfs.get('Containers', []):
            vols = [Volume(v['DeviceIdentifier'], v.get('Name', ''), list(v.get('Roles', [])),
                           bool(v.get('FileVault', False)), bool(v.get('Locked', False)))
                    for v in c.get('Volumes', [])]
            containers[c['ContainerReference']] = Container(
                c['ContainerReference'], c['DesignatedPhysicalStore'], int(c['CapacityCeiling']),
                int(c['CapacityFree']), vols)
        by_store = {c.store: c for c in containers.values()}
        disk = None
        for entry in lst.get('AllDisksAndPartitions', []):
            name = entry.get('DeviceIdentifier')
            info = infos.get(name)
            parts = entry.get('Partitions', [])
            if not info or not parts:
                continue
            if info.get('VirtualOrPhysical', 'Physical') == 'Virtual' or not info.get('Internal', False):
                continue
            if parts[0].get('Content') == 'Apple_APFS_ISC':
                disk = entry
                break
        if disk is None:
            raise LayoutError('no internal disk that starts with the iBoot system container')
        name = disk['DeviceIdentifier']
        dinfo = infos[name]
        size = int(dinfo.get('Size', disk.get('Size')))
        block = int(dinfo.get('DeviceBlockSize', 4096))
        found = []
        for p in disk['Partitions']:
            dev = p['DeviceIdentifier']
            pi = infos.get(dev)
            if pi is None:
                raise LayoutError('no diskutil info for ' + dev)
            found.append(Part(dev, int(pi['PartitionMapPartitionOffset']), int(pi['Size']), pi.get('Content', p.get('Content', '')),
                              pi.get('DiskUUID', ''), pi.get('VolumeName', '') or '', False, by_store.get(dev)))
        found.sort(key=lambda q: q.offset)
        pos, end = 40 * 512, align_down(size - 34 * 512, 4096)
        out, prev = [], name
        for q in found:
            if q.offset - pos > FREE_THRESHOLD:
                out.append(Part(prev, pos, q.offset - pos, free=True))
            out.append(q)
            prev, pos = q.dev, q.end
        if end - pos > FREE_THRESHOLD:
            out.append(Part(prev, pos, end - pos, free=True))
        macos_ref = root.get('APFSContainerReference')
        return cls(name, size, block, out, containers, macos_ref, bool(dinfo.get('Internal', False)))

    # ---- questions ------------------------------------------------------------------------
    def real_parts(self):
        return [p for p in self.parts if not p.free]

    def gaps(self):
        return [p for p in self.parts if p.free]

    def macos_part(self):
        for p in self.parts:
            if p.container is not None and p.container.ref == self.macos_ref:
                return p
        return None

    def after(self, part):
        i = self.parts.index(part)
        return self.parts[i + 1] if i + 1 < len(self.parts) else None

    def gap_after(self, part):
        nxt = self.after(part)
        return nxt if nxt is not None and nxt.free else None

    def find_ours(self):
        """SiliconForest as the installer lays it out: stub container, then SFBOOT, then root."""
        inst = Install()
        stubs = [p for p in self.parts if p.container is not None and STUB_NAME in p.container.system_names()
                 and p.container.ref != self.macos_ref]
        if not stubs:
            boots = [p for p in self.parts if p.kind() == 'efi' and p.label.upper().startswith(BOOT_LABEL)]
            if boots:
                inst.boot = boots[0]
                inst.problems.append('a %s partition (%s) without the SiliconForest startup volume' % (BOOT_LABEL, boots[0].dev))
                nxt = self.after(boots[0])
                if nxt is not None and nxt.kind() == 'linux':
                    inst.root = nxt
            return inst if inst.boot else None
        if len(stubs) > 1:
            inst.problems.append('more than one startup volume named %s (%s)' % (STUB_NAME, ', '.join(p.dev for p in stubs)))
        inst.stub = stubs[0]
        nxt = self.after(inst.stub)
        if nxt is not None and nxt.kind() == 'efi' and nxt.label.upper().startswith(BOOT_LABEL):
            inst.boot = nxt
            nxt = self.after(nxt)
            if nxt is not None and nxt.kind() == 'linux':
                inst.root = nxt
            else:
                inst.problems.append('no Linux-type root partition directly after %s' % inst.boot.dev)
        else:
            inst.problems.append('no %s partition directly after the startup volume %s' % (BOOT_LABEL, inst.stub.dev))
        return inst

    def other_systems(self):
        """Startup volumes that are neither macOS's own container nor ours (Asahi Linux and the like)."""
        out = []
        for p in self.parts:
            c = p.container
            if c is None or c.ref == self.macos_ref or p.content in APPLE_SYSTEM_TYPES:
                continue
            names = c.system_names()
            if names and STUB_NAME not in names:
                out.append('%s: %s (%s)' % (p.dev, ', '.join(names), gb(p.size)))
        for p in self.parts:
            if p.kind() in ('efi', 'linux') and not p.label.upper().startswith(BOOT_LABEL):
                out.append('%s: %s partition %s(%s)' % (p.dev, p.kind().upper() if p.kind() == 'efi' else 'Linux',
                                                         (p.label + ' ') if p.label else '', gb(p.size)))
        return out

    def digest(self):
        """Identity of the partition table as the plan saw it. Free space inside containers is left out
        (macOS changes it all the time); it is checked again before any change."""
        rows = [(p.dev, p.offset, p.size, p.content, p.uuid, bool(p.free)) for p in self.parts]
        rows.append(('macos', self.macos_ref, self.size, self.block_size))
        return hashlib.sha256(json.dumps(rows, sort_keys=True).encode()).hexdigest()

    def table(self):
        lines = []
        mac = self.macos_part()
        ours = self.find_ours()
        mine = set(p.dev for p in ours.parts()) if ours else set()
        for p in self.parts:
            if p.free:
                what = 'free space'
            elif p is mac:
                what = 'macOS (%s), %s free inside' % (', '.join(p.container.system_names()) or 'APFS', gb(p.container.free))
            elif p.dev in mine:
                what = 'SiliconForest ' + {'apfs': 'startup volume', 'efi': 'boot partition', 'linux': 'root'}.get(p.kind(), p.kind())
            elif p.content == 'Apple_APFS_ISC':
                what = 'Apple system container (iBoot)'
            elif p.content == 'Apple_APFS_Recovery':
                what = 'Apple system recovery'
            elif p.container is not None:
                what = 'APFS: ' + (', '.join(p.container.system_names()) or 'no system volume')
            else:
                what = '%s%s' % (p.content, (' "%s"' % p.label) if p.label else '')
            lines.append('  %-10s %12s  %s' % ('' if p.free else p.dev, gb(p.size), what))
        return '\n'.join(lines)
SF_EMBED_1_END
  cat > "$1/sf_plan.py" <<'SF_EMBED_2_END'
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""What the installer finds on this Mac and what it would do: facts, checks and plans.

Nothing here changes anything. `gather` runs read-only commands through the runner it is
given (tests give it recorded outputs); `check`, `plan_install`, `plan_uninstall` and
`plan_update` are pure functions of those facts. The limits on shrinking macOS follow the
Asahi Linux installer (src/main.py, MIT, "Copyright (c) 2021 The Asahi Linux
contributors"): keep 38 GB free in macOS, never go below `diskutil apfs resizeContainer
... limits`' MinimumSizePreferred, warn when snapshots make that minimum much larger.
"""
import re
from dataclasses import dataclass, field

from sf_disk import ALIGN, Layout, LayoutError, align_down, align_up, gb

STUB_BYTES = align_down(2_500_000_000, ALIGN)       # Asahi installer STUB_SIZE: 2,499,805,184
BOOT_BYTES = 524_288_000                             # SFBOOT, 500 MiB (FAT32)
MIN_FREE_MACOS = 38_000_000_000                      # Asahi installer MIN_FREE_OS
OVERHEAD_WARN = 16_000_000_000                       # Asahi installer: snapshot overhead warning
# Before a release exists the root image size is not known; these stand in and are marked as such.
PROVISIONAL_ROOT_MIN = 16 * (1 << 30)
PROVISIONAL_ROOT_DEFAULT = 48 * (1 << 30)


@dataclass
class Model:
    target: str
    hw_model: str
    device_class: str
    chip: str
    status: str
    macos_min: str
    macos_max_major: int
    stub_firmware: list
    name: str


def load_models(text):
    out = {}
    for line in text.splitlines():
        if not line.strip() or line.startswith('#'):
            continue
        f = line.split('\t')
        if len(f) != 9:
            raise ValueError('models.tsv: 9 tab-separated fields expected: ' + line)
        out[f[0].upper()] = Model(f[0].upper(), f[1], f[2], f[3], f[4], f[5], int(f[6]), f[7].split(','), f[8])
    return out


def version_tuple(v):
    return tuple(int(x) for x in re.findall(r'\d+', v or '0')[:4]) or (0,)


@dataclass
class Finding:
    level: str          # 'refuse', 'warn' or 'info'
    code: str
    text: str


@dataclass
class Facts:
    macos_version: str = ''
    macos_build: str = ''
    target: str = ''
    hw_model: str = ''
    translated: bool = False
    console_user: str = ''
    is_admin: bool = False
    filevault: str = ''
    snapshots: int = 0
    on_ac: object = None
    default_boot: str = ''
    layout: object = None
    layout_error: str = ''
    limits: dict = field(default_factory=dict)


def _out(run, *argv):
    rc, out = run(list(argv))
    return out if rc == 0 else None


def gather(run):
    """run(argv) -> (returncode, stdout bytes). Read-only commands only."""
    import plistlib
    f = Facts()
    text = lambda *a: (_out(run, *a) or b'').decode('utf-8', 'replace').strip()
    f.macos_version = text('sw_vers', '-productVersion')
    f.macos_build = text('sw_vers', '-buildVersion')
    f.target = text('sysctl', '-n', 'hw.targettype').upper()
    f.hw_model = text('sysctl', '-n', 'hw.model')
    f.translated = text('sysctl', '-in', 'sysctl.proc_translated') == '1'
    f.console_user = text('stat', '-f', '%Su', '/dev/console')
    if f.console_user:
        f.is_admin = text('dseditgroup', '-o', 'checkmember', '-m', f.console_user, 'admin').startswith('yes ')
    f.filevault = text('fdesetup', 'status')
    snaps = text('tmutil', 'listlocalsnapshots', '/')
    f.snapshots = len([l for l in snaps.splitlines() if l.strip() and not l.startswith('Snapshots for')])
    batt = text('pmset', '-g', 'batt')
    f.on_ac = ("'AC Power'" in batt) if batt else None
    f.default_boot = text('bless', '--getBoot')
    lst = _out(run, 'diskutil', 'list', '-plist')
    apfs = _out(run, 'diskutil', 'apfs', 'list', '-plist')
    root = _out(run, 'diskutil', 'info', '-plist', '/')
    try:
        if lst is None or apfs is None or root is None:
            raise LayoutError('diskutil did not answer')
        infos = {}
        for entry in plistlib.loads(lst).get('AllDisksAndPartitions', []):
            if not entry.get('Partitions'):
                continue
            for dev in [entry['DeviceIdentifier']] + [p['DeviceIdentifier'] for p in entry['Partitions']]:
                infos[dev] = _out(run, 'diskutil', 'info', '-plist', dev) or b''
        infos = {k: v for k, v in infos.items() if v}
        f.layout = Layout.parse(lst, apfs, infos, root)
        mac = f.layout.macos_part()
        if mac is not None:
            lim = _out(run, 'diskutil', 'apfs', 'resizeContainer', mac.dev, 'limits', '-plist')
            f.limits = plistlib.loads(lim) if lim else {}
    except (LayoutError, KeyError, ValueError) as e:
        f.layout, f.layout_error = None, str(e)
    return f


# ---- checks --------------------------------------------------------------------------------
def check(f, models, manifest=None):
    out = []
    add = lambda level, code, text: out.append(Finding(level, code, text))
    if f.translated:
        add('refuse', 'rosetta', 'The installer is running under Rosetta (Intel emulation). Run it from a Terminal that is not set to "Open using Rosetta".')
    m = models.get(f.target)
    supported = ', '.join('%s (%s)' % (x.name, x.target) for x in models.values() if x.status == 'supported')
    if m is None:
        add('refuse', 'model', 'This Mac (%s, board %s) is not supported. SiliconForest runs only on: %s.' % (f.hw_model or '?', f.target or '?', supported))
    elif m.status != 'supported':
        add('refuse', 'model', 'This Mac (%s) is listed but not installable yet (status: %s).' % (m.name, m.status))
    else:
        add('info', 'model', 'Mac: %s (%s, board %s, %s).' % (m.name, f.hw_model, m.target, m.chip))
        if manifest is not None and m.target not in manifest['models']:
            add('refuse', 'model', 'Release %s was not built for this Mac (board %s).' % (manifest['release'], m.target))
        lo = manifest['macos']['min'] if manifest else m.macos_min
        hi = min(manifest['macos']['max_major'], m.macos_max_major) if manifest else m.macos_max_major
        v = version_tuple(f.macos_version)
        if v < version_tuple(lo):
            add('refuse', 'macos-old', 'macOS %s is too old: update macOS to %s or newer first.' % (f.macos_version, lo))
        elif v[0] > hi:
            add('refuse', 'macos-new', 'macOS %s is newer than any version SiliconForest was tested with (up to macOS %d). Wait for an installer that lists it.' % (f.macos_version, hi))
        else:
            add('info', 'macos', 'macOS %s (%s).' % (f.macos_version, f.macos_build))
    if not f.console_user or f.console_user in ('root', '_mbsetupuser', 'loginwindow'):
        add('refuse', 'console', 'Nobody is logged in at the Mac\'s screen. Log in there first (the installer asks that person for their password).')
    elif not f.is_admin:
        add('refuse', 'admin', 'The logged-in user (%s) is not an administrator of this Mac.' % f.console_user)
    fv = f.filevault.lower()
    if 'in progress' in fv or 'encryption' in fv and 'percent' in fv:
        add('refuse', 'filevault-busy', 'FileVault is encrypting or decrypting the disk (%s). Wait until it has finished.' % f.filevault.splitlines()[0])
    elif 'is on' in fv:
        add('info', 'filevault', 'FileVault is on. That is fine: macOS stays encrypted; SiliconForest\'s own partition is not encrypted.')
    if f.snapshots:
        add('info', 'snapshots', '%d local Time Machine snapshot(s) on the startup disk; they can keep macOS from shrinking (see docs/INSTALL.md).' % f.snapshots)
    if f.on_ac is False:
        add('warn', 'battery', 'The Mac is on battery. Connect power before installing.')
    if f.layout is None:
        add('refuse', 'disk', 'Could not read the internal disk\'s layout: %s.' % (f.layout_error or 'unknown'))
        return out
    if f.layout.macos_part() is None:
        add('refuse', 'disk', 'Could not find the APFS container of the running macOS on the internal disk (is macOS started from an external disk?).')
    ours = f.layout.find_ours()
    if ours is not None and ours.complete:
        add('info', 'installed', 'SiliconForest is installed (%s). Use --update or --uninstall.' % ', '.join(p.dev for p in ours.parts()))
    elif ours is not None:
        add('refuse', 'partial', 'An incomplete SiliconForest installation is on the disk: %s. Remove it with --uninstall before installing again.' % '; '.join(ours.problems))
    others = f.layout.other_systems()
    if others:
        add('info', 'others', 'Other systems on the disk (left as they are): ' + '; '.join(others) + '.')
    return out


def refusals(findings):
    return [x for x in findings if x.level == 'refuse']


class Refusal(Exception):
    def __init__(self, findings):
        self.findings = findings
        super().__init__('; '.join(x.text for x in findings))


# ---- plans ---------------------------------------------------------------------------------
def sizes(manifest):
    if manifest:
        o = manifest['os']
        return o['root_min_bytes'], o['root_default_bytes'], False
    return PROVISIONAL_ROOT_MIN, PROVISIONAL_ROOT_DEFAULT, True


def plan_install(f, models, manifest=None, total=None):
    findings = check(f, models, manifest)
    bad = refusals(findings)
    if any(x.code == 'installed' for x in findings):
        bad.append(Finding('refuse', 'installed', 'SiliconForest is already installed; use --update, or --uninstall first.'))
    if bad:
        raise Refusal(bad)
    lay = f.layout
    root_min, root_default, provisional = sizes(manifest)
    fixed = STUB_BYTES + BOOT_BYTES
    if total is None:
        root = align_down(root_default, ALIGN)
    else:
        root = align_down(total - fixed, ALIGN)
        if root < root_min:
            raise Refusal([Finding('refuse', 'size', 'Asked for %s; SiliconForest needs at least %s (%s for its startup volume and boot partition, %s for its root).' % (
                gb(total), gb(fixed + root_min), gb(fixed), gb(root_min)))])
    need = fixed + root
    plan = dict(kind='install', layout_digest=lay.digest(), disk=lay.disk, block_size=lay.block_size,
                stub_bytes=STUB_BYTES, boot_bytes=BOOT_BYTES, root_bytes=root, total_bytes=need,
                provisional_sizes=provisional, release=manifest['release'] if manifest else None,
                resize=None, findings=[x.__dict__ for x in findings])
    mac = lay.macos_part()
    gap = next((g for g in lay.gaps() if g.size >= need), None)
    if gap is not None:
        plan.update(after=gap.dev, gap_offset=gap.offset, gap_bytes=gap.size, macos_free_after=mac.container.free)
    else:
        c = mac.container
        if not f.limits or 'MinimumSizePreferred' not in f.limits:
            raise Refusal([Finding('refuse', 'limits', 'diskutil did not say how far macOS\'s container can shrink.')])
        before = lay.gap_after(mac)
        have = before.size if before is not None else 0
        shrink = align_up(need - have, ALIGN)
        new = c.ceiling - shrink
        min_raw = align_up(c.ceiling - c.free + MIN_FREE_MACOS, ALIGN)
        min_safe = int(f.limits['MinimumSizePreferred'])
        min_size = max(min_raw, min_safe)
        overhead = min_size - min_raw
        if overhead > OVERHEAD_WARN:
            findings.append(Finding('warn', 'overhead', 'macOS cannot shrink below %s although only %s is in use: snapshots (Time Machine) or a pending macOS update hold %s. Deleting local snapshots frees it (docs/INSTALL.md).' % (
                gb(min_safe), gb(c.ceiling - c.free), gb(overhead))))
            plan['findings'] = [x.__dict__ for x in findings]
        if new < min_size:
            most = max(0, c.ceiling - min_size + have)
            room = 'At most %s can be made available' % gb(most) if most >= fixed + root_min else 'Not even the minimum (%s) can be made available' % gb(fixed + root_min)
            raise Refusal([x for x in findings if x.level == 'warn'] + [Finding('refuse', 'space', 'Not enough space: SiliconForest needs %s, and macOS must keep %s free (it has %s free now). %s; free space in macOS or ask for less with --size.' % (
                gb(need), gb(MIN_FREE_MACOS), gb(c.free), room))])
        plan['resize'] = dict(store=mac.dev, container=c.ref, from_bytes=c.ceiling, to_bytes=new, shrink_bytes=shrink, min_bytes=min_size)
        plan.update(after=mac.dev, gap_offset=mac.offset + new, gap_bytes=shrink + have, macos_free_after=c.free - shrink)
    plan['changes'] = describe_install(plan, mac)
    return plan


def describe_install(p, mac):
    lines = []
    if p['resize']:
        r = p['resize']
        lines.append('Shrink the macOS container %s (partition %s) from %s to %s, freeing %s directly after it. macOS keeps all its files and %s of free space.' % (
            r['container'], r['store'], gb(r['from_bytes']), gb(r['to_bytes']), gb(r['shrink_bytes']), gb(p['macos_free_after'])))
    else:
        lines.append('Use %s of the free space after %s (macOS is not resized).' % (gb(p['total_bytes']), p['after']))
    lines += [
        'Add a %s APFS container "SiliconForest" there: the startup volume that the startup picker shows, with its own recovery, made from Apple\'s macOS %s restore files for this Mac (downloaded from Apple).' % (gb(p['stub_bytes']), '13.5'),
        'Add a %s FAT32 partition "SFBOOT" behind it with SiliconForest\'s boot files (sf/boot.bin, sf/kernel.bin) and this Mac\'s Wi-Fi/Bluetooth firmware.' % gb(p['boot_bytes']),
        'Add a %s partition behind that and write the SiliconForest root filesystem into it.' % gb(p['root_bytes']),
        'Write this Mac\'s partition identifiers into sf/kernel.bin and copy the Wi-Fi/Bluetooth firmware into the root.',
        'Make SiliconForest the startup disk for the next start only so that its recovery can finish the setup; you set macOS back afterwards (the installer says how).',
        'Nothing else: macOS\'s volumes, your files and any other system on the disk are not written.',
    ]
    return lines


def plan_uninstall(f, models):
    lay = f.layout
    if lay is None:
        raise Refusal([Finding('refuse', 'disk', 'Could not read the disk layout: ' + f.layout_error)])
    ours = lay.find_ours()
    if ours is None:
        raise Refusal([Finding('refuse', 'not-installed', 'No SiliconForest installation was found on the internal disk. Nothing to remove.')])
    findings = []
    if ours.stub is not None:
        sub = re.match(r'^(/dev/)?(disk\d+)', f.default_boot or '')
        if sub and sub.group(2) == ours.stub.container.ref:
            raise Refusal([Finding('refuse', 'default', 'SiliconForest is the startup disk. Choose macOS first: System Settings > General > Startup Disk (or hold the power button, select macOS, hold Option and click "Always Use"), then run this again.')])
        if not sub:
            findings.append(Finding('warn', 'default-unknown', 'Could not read the current startup disk. Make sure it is macOS before you confirm.'))
    remove = []
    if ours.stub is not None:
        remove.append(dict(dev=ours.stub.dev, container=ours.stub.container.ref, what='SiliconForest startup volume (APFS container %s)' % ours.stub.container.ref,
                           offset=ours.stub.offset, bytes=ours.stub.size, uuid=ours.stub.uuid, action='deleteContainer'))
    for p, what in ((ours.boot, 'SFBOOT boot partition'), (ours.root, 'SiliconForest root partition (its files are lost)')):
        if p is not None:
            remove.append(dict(dev=p.dev, what=what, offset=p.offset, bytes=p.size, uuid=p.uuid, action='eraseVolume'))
    mac = lay.macos_part()
    # the space comes back to macOS only if nothing but free space lies between macOS and our first piece
    first = min(r['offset'] for r in remove)
    between = [p for p in lay.parts if mac.end <= p.offset < first and not p.free]
    grow = dict(store=mac.dev, container=mac.container.ref) if mac is not None and not between else None
    if grow is None:
        findings.append(Finding('info', 'no-grow', 'Another partition lies between macOS and SiliconForest; the space is left free instead of being given back to macOS.'))
    freed = sum(r['bytes'] for r in remove)
    plan = dict(kind='uninstall', layout_digest=lay.digest(), disk=lay.disk, remove=remove, grow=grow, freed_bytes=freed,
                findings=[x.__dict__ for x in findings])
    plan['changes'] = ['Delete %s: %s at %s, %s.' % (r['dev'], r['what'], gb(r['offset']), gb(r['bytes'])) for r in remove]
    plan['changes'].append('Give the %s back to macOS (grow container %s).' % (gb(freed), grow['container']) if grow else 'Leave the %s as free space.' % gb(freed))
    plan['changes'].append('Nothing else: macOS, your files and any other system are not touched.')
    return plan


def plan_update(f, models, manifest):
    findings = check(f, models, manifest)
    bad = [x for x in refusals(findings) if x.code not in ('battery',)]
    if bad:
        raise Refusal(bad)
    ours = f.layout.find_ours()
    if ours is None or not ours.complete:
        raise Refusal([Finding('refuse', 'not-installed', 'No complete SiliconForest installation found; nothing to update.')])
    bs = f.layout.block_size
    plan = dict(kind='update', layout_digest=f.layout.digest(), release=manifest['release'], boot_dev=ours.boot.dev,
                root=dict(dev=ours.root.dev, uuid=ours.root.uuid, first_block=ours.root.offset // bs, blocks=ours.root.size // bs),
                findings=[x.__dict__ for x in findings])
    plan['changes'] = ['Replace sf/boot.bin and sf/kernel.bin on %s with release %s; the current ones are kept as sf/boot.bin.old and sf/kernel.bin.old.' % (ours.boot.dev, manifest['release']),
                       'The root filesystem, the startup volume and macOS are not changed.']
    return plan
SF_EMBED_2_END
  cat > "$1/sf_manifest.py" <<'SF_EMBED_3_END'
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""The release manifest: what a SiliconForest release consists of, checked before it is used.

The manifest is a JSON file published with each release next to a detached signature
(ECDSA P-256 over SHA-256 of the exact bytes, DER; verified by install.sh with macOS's own
`openssl dgst -sha256 -verify` before this module ever sees the file). This module checks
its shape; it trusts nothing it has not checked. Schema: install/manifest.example.json.
"""
import json
import re

FORMAT = 'siliconforest-release/1'
HEX64 = re.compile(r'^[0-9a-f]{64}$')
UUID = re.compile(r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$')
NAME = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$')
VERSION = re.compile(r'^[0-9]+(\.[0-9]+){0,3}$')
ROLES = ('stage1', 'os-package')


class ManifestError(Exception):
    pass


def _need(cond, what):
    if not cond:
        raise ManifestError(what)


def _file(entry, where):
    _need(isinstance(entry, dict), where + ': not an object')
    _need(isinstance(entry.get('file'), str) and NAME.match(entry['file']), where + ': file name')
    _need(isinstance(entry.get('bytes'), int) and entry['bytes'] > 0, where + ': bytes')
    _need(isinstance(entry.get('sha256'), str) and HEX64.match(entry['sha256']), where + ': sha256')
    parts = entry.get('parts')
    if parts is not None:
        _need(isinstance(parts, list) and parts, where + ': parts')
        for i, p in enumerate(parts):
            _file(p, '%s part %d' % (where, i))
        _need(sum(p['bytes'] for p in parts) == entry['bytes'], where + ': parts do not add up to bytes')


def check(data, supported_targets):
    """Return the manifest (a dict) if it is well formed, else raise ManifestError."""
    m = json.loads(data) if isinstance(data, (bytes, str)) else data
    _need(isinstance(m, dict), 'not an object')
    _need(m.get('format') == FORMAT, 'format is not ' + FORMAT)
    _need(isinstance(m.get('release'), str) and NAME.match(m['release']), 'release')
    base = m.get('base_url')
    _need(isinstance(base, str) and base.startswith('https://') and base.endswith('/'), 'base_url must be https and end in /')
    models = m.get('models')
    _need(isinstance(models, list) and models and all(isinstance(t, str) for t in models), 'models')
    extra = [t for t in models if t not in supported_targets]
    _need(not extra, 'release names boards this installer does not support: ' + ', '.join(extra))
    mac = m.get('macos', {})
    _need(isinstance(mac.get('min'), str) and VERSION.match(mac['min']), 'macos.min')
    _need(isinstance(mac.get('max_major'), int), 'macos.max_major')
    _need(isinstance(m.get('stub_firmware'), list) and m['stub_firmware'] and
          all(isinstance(v, str) and VERSION.match(v) for v in m['stub_firmware']), 'stub_firmware')
    eng = m.get('engine', {})
    _file(eng, 'engine')
    _need(eng.get('name') == 'asahi-installer', 'engine.name')
    _need(isinstance(eng.get('urls'), list) and eng['urls'] and all(isinstance(u, str) and u.startswith('https://')
                                                                     for u in eng['urls']), 'engine.urls')
    files = m.get('files')
    _need(isinstance(files, list), 'files')
    roles = {}
    for i, f in enumerate(files):
        _file(f, 'files[%d]' % i)
        _need(f.get('role') in ROLES, 'files[%d].role' % i)
        _need(f['role'] not in roles, 'two files with role ' + f['role'])
        roles[f['role']] = f
    _need(set(roles) == set(ROLES), 'files must have exactly the roles ' + ', '.join(ROLES))
    os_ = m.get('os', {})
    _need(isinstance(os_.get('root_fs_uuid'), str) and UUID.match(os_['root_fs_uuid']), 'os.root_fs_uuid')
    for k in ('root_image_bytes', 'root_min_bytes', 'root_default_bytes', 'boot_partition_bytes'):
        _need(isinstance(os_.get(k), int) and os_[k] > 0, 'os.' + k)
    _need(os_['root_image_bytes'] % 4096 == 0, 'os.root_image_bytes is not a multiple of 4096 (the Asahi installer refuses it)')
    _need(os_['root_image_bytes'] <= os_['root_min_bytes'] <= os_['root_default_bytes'], 'os: image <= min <= default')
    _need(os_['boot_partition_bytes'] == 524288000, 'os.boot_partition_bytes must be 500 MiB (the size the installed boot chain was proven with)')
    _need(os_.get('kernel_file') == 'esp/sf/kernel.bin', 'os.kernel_file')
    _need(isinstance(os_.get('kernel_record_sha256'), str) and HEX64.match(os_['kernel_record_sha256']), 'os.kernel_record_sha256')
    slot = os_.get('firmware_slot')
    _need(isinstance(slot, dict) and isinstance(slot.get('offset'), int) and isinstance(slot.get('length'), int), 'os.firmware_slot')
    _need(slot['offset'] % 4096 == 0 and slot['length'] >= (1 << 20) and slot['offset'] + slot['length'] <= os_['root_image_bytes'],
          'os.firmware_slot must be 4096-aligned, at least 1 MiB and inside the root image')
    return m


def role(m, name):
    return next(f for f in m['files'] if f['role'] == name)
SF_EMBED_3_END
  cat > "$1/sf_kernelcfg.py" <<'SF_EMBED_4_END'
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Write this Mac's root partition into sf/kernel.bin.

sf/kernel.bin is a list of records (integrations/siliconforest/m1-native-boot/b1/pdsf_pack.py,
src/pdsf.h): CONFIG (text: `bootargs=...` and keys), KERNEL (the kernel collection, gzip), END.
A release's CONFIG names the root partition with three tokens that stand for values only the
installed disk knows:

    sfnvme_part=@SF_ROOT_PARTUUID@ sfnvme_part_lba=@SF_ROOT_LBA@ sfnvme_part_blocks=@SF_ROOT_BLOCKS@

They are the storage driver's write fence (m1-storage/kernel/SFAppleNVMe.cpp): it writes only
inside the partition with that GUID, first block and length, and only if both GPT copies agree.
An unfilled token is not a GUID, so the driver refuses the partition and the root: fail closed.
This module fills the tokens, keeps every other record byte for byte, and checks the result.
"""
import hashlib
import re
import struct
import zlib

MAGIC, VERSION, ALIGN = 0x46534450, 1, 16
END, CONFIG, KERNEL, RAMDISK = 0, 1, 2, 3
HEADER = struct.Struct('<IHHIIQQ')
BOOTARGS_CAPACITY = 608            # firmware BootArgs revision 2 (M1), terminating NUL included
TOKENS = ('@SF_ROOT_PARTUUID@', '@SF_ROOT_LBA@', '@SF_ROOT_BLOCKS@')
GUID = re.compile(r'^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$')


class ConfigError(Exception):
    pass


def parse(data):
    """[(kind, flags, payload, raw, record bytes)] up to and including END."""
    out, off = [], 0
    while True:
        if off + HEADER.size > len(data):
            raise ConfigError('record list is cut off')
        magic, version, kind, flags, crc, stored, raw = HEADER.unpack_from(data, off)
        if magic != MAGIC or version != VERSION or kind not in (END, CONFIG, KERNEL, RAMDISK):
            raise ConfigError('not a record at %#x' % off)
        if kind == END:
            out.append((END, 0, b'', 0, data[off:off + HEADER.size]))
            if off + HEADER.size != len(data):
                raise ConfigError('bytes after the END record')
            return out
        body = data[off + HEADER.size:off + HEADER.size + stored]
        if len(body) != stored:
            raise ConfigError('record reaches past the end')
        if zlib.crc32(body) != crc:
            raise ConfigError('checksum of record %d is wrong' % kind)
        size = HEADER.size + stored + (-(HEADER.size + stored) % ALIGN)
        out.append((kind, flags, body, raw, data[off:off + size]))
        off += size


def record(kind, data):
    body = HEADER.pack(MAGIC, VERSION, kind, 0, zlib.crc32(data), len(data), len(data)) + data
    return body + bytes(-len(body) % ALIGN)


def kernel_digest(data):
    recs = parse(data)
    kern = [r for r in recs if r[0] == KERNEL]
    if len(kern) != 1:
        raise ConfigError('exactly one KERNEL record expected')
    return hashlib.sha256(kern[0][2]).hexdigest()


def bootargs(data):
    cfg = [r for r in parse(data) if r[0] == CONFIG]
    text = cfg[0][2].decode('ascii')
    return next(l[len('bootargs='):] for l in text.split('\n') if l.startswith('bootargs='))


def personalize(data, partuuid, first_block, blocks, kernel_sha256=None):
    recs = parse(data)
    kinds = [r[0] for r in recs]
    if kinds[0] != CONFIG or kinds.count(CONFIG) != 1 or kinds.count(KERNEL) != 1 or kinds[-1] != END:
        raise ConfigError('expected CONFIG, KERNEL, [RAMDISK], END; found %r' % kinds)
    if kernel_sha256 is not None and kernel_digest(data) != kernel_sha256:
        raise ConfigError('the KERNEL record is not the one the release manifest names')
    guid = partuuid.upper()
    if not GUID.match(guid):
        raise ConfigError('not a partition GUID: %r' % partuuid)
    if not (isinstance(first_block, int) and isinstance(blocks, int) and first_block > 0 and blocks > 0):
        raise ConfigError('first block and block count must be positive integers')
    if recs[0][1] != 0:
        raise ConfigError('the CONFIG record is compressed; a release keeps it plain')
    text = recs[0][2].decode('ascii')
    for t in TOKENS:
        if text.count(t) != 1:
            raise ConfigError('the CONFIG record must contain %s exactly once (found %d)' % (t, text.count(t)))
    text = text.replace(TOKENS[0], guid).replace(TOKENS[1], str(first_block)).replace(TOKENS[2], str(blocks))
    if '@SF_' in text:
        raise ConfigError('an unknown @SF_ token is left in the CONFIG record')
    lines = text.split('\n')
    args = [l for l in lines if l.startswith('bootargs=')]
    if len(args) != 1:
        raise ConfigError('exactly one bootargs= line expected')
    a = args[0][len('bootargs='):]
    if len(a) >= BOOTARGS_CAPACITY or any(not 32 <= ord(c) < 127 for c in a):
        raise ConfigError('bootargs: 1..%d printable characters (%d)' % (BOOTARGS_CAPACITY - 1, len(a)))
    for key, value in (('sfnvme_part', guid), ('sfnvme_part_lba', str(first_block)), ('sfnvme_part_blocks', str(blocks))):
        if a.split().count('%s=%s' % (key, value)) != 1 or sum(1 for w in a.split() if w.startswith(key + '=')) != 1:
            raise ConfigError('%s= must appear once, as the release token' % key)
    out = record(CONFIG, text.encode('ascii')) + b''.join(r[4] for r in recs[1:])
    check = parse(out)
    if [r[0] for r in check] != kinds or any(x[4] != y[4] for x, y in zip(check[1:], recs[1:])):
        raise ConfigError('the rewritten file does not keep the other records')
    return out
SF_EMBED_4_END
  cat > "$1/sf_fwslot.py" <<'SF_EMBED_5_END'
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Hand this Mac's Wi-Fi and Bluetooth firmware to SiliconForest.

The firmware is Apple's and is never shipped by SiliconForest. The installer's engine (the
Asahi Linux installer) collects it on the user's Mac from Apple's recovery image for this
model, into `vendorfw/firmware.tar` with the names Linux's brcmfmac driver uses, which are
the names SiliconForest's driver looks for (/Library/Firmware/brcm).

SiliconForest's storage driver reads only its own root partition, so the firmware has to be
inside it. The release's root image contains a preallocated, contiguous file (the slot) at a
byte offset the release manifest gives. An empty slot starts with the line `SFFWSLOT1`.
The installer writes, at that offset of the new root partition:

    4096-byte header: b'SFFWSLOT1\\nlength=<payload bytes>\\nsha256=<hex>\\n', zero padded
    payload:          a tar of the brcm/ members of firmware.tar

and SiliconForest's first start checks the header and unpacks the payload. Only file data
inside one existing file changes; the filesystem's metadata is not touched.
"""
import hashlib
import io
import tarfile

HEAD = 4096
EMPTY = b'SFFWSLOT1\n'


class SlotError(Exception):
    pass


def payload(firmware_tar):
    """A tar with the brcm/ members (Wi-Fi and Bluetooth) of the engine's firmware.tar."""
    src = tarfile.open(firmware_tar, 'r:')
    out = io.BytesIO()
    dst = tarfile.open(fileobj=out, mode='w', format=tarfile.USTAR_FORMAT)
    names = set()
    for m in src.getmembers():
        if not m.name.startswith('brcm/') or '..' in m.name.split('/'):
            continue
        if m.isreg():
            dst.addfile(m, src.extractfile(m))
            names.add(m.name)
        elif m.islnk() and m.linkname in names:
            dst.addfile(m)
            names.add(m.name)
    dst.close()
    src.close()
    if not names:
        raise SlotError('no brcm/ firmware in ' + firmware_tar)
    return out.getvalue(), sorted(names)


def header(data):
    h = b'SFFWSLOT1\nlength=%d\nsha256=%s\n' % (len(data), hashlib.sha256(data).hexdigest().encode())
    return h + bytes(HEAD - len(h))


def write(dev, offset, length, data, opener=open):
    """Write into the slot of the root partition opened through `opener` (the gate's)."""
    if HEAD + len(data) > length:
        raise SlotError('the firmware (%d bytes) does not fit the slot (%d)' % (len(data), length - HEAD))
    if offset % HEAD:
        raise SlotError('the slot offset is not 4096-aligned')
    blob = header(data) + data
    blob += bytes(-len(blob) % HEAD)            # raw devices take whole, aligned blocks only
    with opener(dev, 'r+b', buffering=0) as fd:
        fd.seek(offset)
        head = fd.read(HEAD)
        # empty (as the image ships) or filled by an earlier run of the installer: both start so
        if not head.startswith(EMPTY):
            raise SlotError('no firmware slot at byte %d of %s: nothing written' % (offset, dev))
        fd.seek(offset)
        fd.write(blob)
        fd.seek(offset)
        if fd.read(len(blob)) != blob:
            raise SlotError('the firmware slot does not read back as written')
    return len(blob)
SF_EMBED_5_END
  cat > "$1/sf_gate.py" <<'SF_EMBED_6_END'
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""The one door every change to the disk goes through.

Every command that can change the partition table, a filesystem, the boot policy or the power
state, and every raw write to a disk device, is passed to `Gate.run` or `Gate.open`, whether
our code issues it or the Asahi installer's code does (sf_engine.py routes the engine's
`diskutil`, `newfs_msdos`, `bless`, `shutdown` and raw device opens here). The gate

  * refuses anything the confirmed plan does not name: which container may be resized and to
    exactly what size, after which partition new partitions may be added and how much space
    they may take, which devices may be formatted or written raw, which volume may be blessed,
    and in an uninstall which container and partitions may be deleted;
  * after every change, reads the partition table again and stops everything if a partition
    that existed before moved, changed size or identity (other than the planned resize);
  * writes a journal line before and after each change (the log and the resume record);
  * in simulation mode hands the command to a model of the disk instead of running it, which
    is how the tests drive the whole installer on Linux.

Read-only commands (diskutil list/info/mount, hdiutil attach -readonly, ioreg, bputil -d, ...)
pass through unchanged.
"""
import json
import os
import re
import subprocess
import time

READ_ONLY_DISKUTIL = {'list', 'info', 'mount', 'unmount', 'activity'}
READ_ONLY_APFS = {'list', 'listVolumeGroups', 'listSnapshots', 'listUsers', 'listCryptoUsers'}
PASS = {'hdiutil', 'ioreg', 'nvram', 'scutil', 'sw_vers', 'sysctl', 'chflags', 'xattr', 'mount', 'caffeinate',
        'tmutil', 'fdesetup', 'pmset', 'stat', 'dseditgroup', 'id', 'ditto', 'cp', 'sync'}
PART_TYPES = {'apfs': 'apfs', 'APFS': 'apfs', '%EFI%': 'efi', '%Linux%': 'linux'}


class Refused(Exception):
    pass


def _dev(arg):
    return re.sub(r'^/dev/r?', '', arg or '')


def _container_of(dev):
    m = re.match(r'^(disk\d+)', dev)
    return m.group(1) if m else ''


class Gate:
    def __init__(self, plan, reader, journal=None, execute=None, log=print):
        """plan: the confirmed plan (sf_plan); reader(): the current sf_disk.Layout;
        execute(argv, input) -> (rc, output): None = really run it."""
        self.plan, self.reader, self.log = plan, reader, log
        self.journal = journal
        self.execute = execute
        self.simulated = execute is not None
        self.before = {p.dev: (p.offset, p.size, p.uuid) for p in reader().real_parts()}
        self.created = {}           # dev -> kind ('apfs', 'efi', 'linux')
        self.created_containers = set()
        self.after_ok = {plan.get('after')} if plan.get('kind') == 'install' else set()
        self.used = 0
        self.resized = False
        self.grown = False
        self.removed = set()
        self.calls = []
        self._last_uuid = {}
        self.write_dirs = ()

    # ---- journal -------------------------------------------------------------------------
    def note(self, **entry):
        entry['time'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
        if self.journal:
            with open(self.journal, 'a') as fd:
                fd.write(json.dumps(entry, sort_keys=True) + '\n')

    # ---- the rules -----------------------------------------------------------------------
    def classify(self, argv):
        """None if read-only, else the name of the rule that must allow it."""
        prog = os.path.basename(argv[0])
        if prog == 'diskutil':
            verb = argv[1] if len(argv) > 1 else ''
            if verb in READ_ONLY_DISKUTIL:
                return None
            if verb == 'apfs':
                sub = argv[2] if len(argv) > 2 else ''
                if sub in READ_ONLY_APFS or (sub == 'resizeContainer' and 'limits' in argv):
                    return None
                return 'apfs ' + sub
            return verb
        if prog == 'bless':
            return 'setBoot' if '--setBoot' in argv else None
        if prog == 'bputil':
            return None if argv[1:2] == ['-d'] else 'bputil'
        if prog in ('newfs_msdos', 'shutdown', 'reboot', 'kmutil', 'gpt', 'pdisk', 'fdisk', 'dd', 'asr', 'csrutil', 'nvram-write'):
            return prog
        if prog in PASS:
            return None
        return 'unknown:' + prog

    def check(self, rule, argv):
        p, kind = self.plan, self.plan.get('kind')
        a = argv
        if kind == 'install':
            if rule == 'apfs resizeContainer':
                r = p.get('resize')
                if not r or self.resized or _dev(a[3]) != r['store'] or a[4] != str(r['to_bytes']):
                    return 'the plan resizes %s to %s bytes, once' % ((r or {}).get('store'), (r or {}).get('to_bytes'))
                return None
            if rule == 'addPartition':
                after, ptype, size = _dev(a[2]), a[3], int(a[5])
                if after not in self.after_ok:
                    return 'new partitions go after %s only' % ', '.join(sorted(x for x in self.after_ok if x))
                if ptype not in PART_TYPES:
                    return 'partition type %s is not one the plan adds' % ptype
                if self.used + size > p['total_bytes'] + (1 << 20) * 4:
                    return 'the new partitions would take more than the planned %d bytes' % p['total_bytes']
                return None
            if rule in ('apfs addVolume', 'apfs changeVolumeRole', 'rename', 'apfs updatePreboot'):
                target = _container_of(_dev(a[3] if rule.startswith('apfs') else a[2]))
                if rule == 'apfs updatePreboot':
                    # Apple's own maintenance of macOS's Preboot list of administrators (Asahi main.py check_cur_os)
                    return None
                if target not in self.created_containers:
                    return '%s is not a container this installation created' % target
                return None
            if rule == 'newfs_msdos':
                if self.created.get(_dev(a[-1])) != 'efi':
                    return '%s is not the boot partition this installation created' % a[-1]
                return None
            if rule == 'setBoot':
                dev = _dev(a[a.index('--device') + 1]) if '--device' in a else ''
                if _container_of(dev) not in self.created_containers:
                    return 'only the new SiliconForest volume may be blessed'
                return None
            if rule in ('shutdown',):
                return None
        if kind == 'uninstall':
            remove = {r['dev']: r for r in p['remove']}
            if rule == 'apfs deleteContainer':
                ok = [r for r in p['remove'] if r.get('container') == _dev(a[3]) or (r['action'] == 'deleteContainer' and r['dev'] == _dev(a[3]))]
                return None if ok else '%s is not the SiliconForest container' % a[3]
            if rule == 'eraseVolume':
                uuids = {r['uuid'] for r in p['remove'] if r.get('uuid')}
                cur = next((q for q in self.reader().real_parts() if q.dev == _dev(a[4])), None) if len(a) > 4 else None
                if a[2:4] != ['free', 'free'] or cur is None or (cur.dev not in remove and cur.uuid not in uuids):
                    return 'only "eraseVolume free free" of a SiliconForest partition is allowed'
                return None
            if rule == 'apfs resizeContainer':
                g = p.get('grow')
                if not g or _dev(a[3]) != g['store'] or a[4] != '0':
                    return 'only growing macOS (%s) back over the freed space is allowed' % (g or {}).get('store')
                return None
        return 'the plan (%s) does not include %s' % (kind, rule)

    # ---- after a change: nothing that existed may have moved --------------------------------
    def verify(self, what):
        lay = self.reader()
        now = {q.dev: (q.offset, q.size, q.uuid) for q in lay.real_parts()}
        p = self.plan
        for dev, (off, size, uuid) in self.before.items():
            if p.get('kind') == 'uninstall' and dev in {r['dev'] for r in p['remove']} and dev in self.removed:
                continue
            cur = next((v for v in now.values() if v[2] == uuid and uuid), now.get(dev))
            if cur is None:
                raise Refused('STOP after %s: partition %s (%s) has gone' % (what, dev, uuid))
            if cur[0] != off:
                raise Refused('STOP after %s: partition %s moved' % (what, dev))
            if cur[1] != size:
                r, g = p.get('resize'), p.get('grow')
                if r and dev == r['store'] and self.resized and cur[1] == r['to_bytes']:
                    continue
                if g and dev == g['store'] and self.grown and cur[1] > size:
                    continue
                raise Refused('STOP after %s: partition %s changed size (%d -> %d)' % (what, dev, size, cur[1]))
        return lay

    # ---- the door ------------------------------------------------------------------------
    def run(self, argv, why='', input=None):
        argv = [str(x) for x in argv]
        rule = self.classify(argv)
        if rule is None:
            return self._exec(argv, input, quiet=True)
        reason = self.check(rule, argv)
        if reason is not None:
            self.note(step=why, argv=argv, state='refused', reason=reason)
            raise Refused('refused %s: %s' % (' '.join(argv), reason))
        if rule in ('eraseVolume', 'apfs deleteContainer'):
            t = _dev(argv[-1])
            cur = next((q for q in self.reader().real_parts() if q.dev == t or (q.container is not None and q.container.ref == t)), None)
            self._last_uuid = {t: cur.uuid if cur is not None else ''}
        self.note(step=why, argv=argv, state='start')
        self.log('%s %s' % ('SIMULATED:' if self.simulated else 'running:', ' '.join(a if 'pass' not in a.lower() else '***' for a in argv)))
        rc, out = self._exec(argv, input)
        self.note(step=why, argv=argv, state='done' if rc == 0 else 'failed', rc=rc)
        if rc != 0:
            raise subprocess.CalledProcessError(rc, argv, out)
        self._after(rule, argv)
        return rc, out

    def _exec(self, argv, input, quiet=False):
        self.calls.append(argv)
        if self.execute is not None:
            return self.execute(argv, input)
        res = subprocess.run(argv, input=input, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        return res.returncode, res.stdout

    def _after(self, rule, argv):
        if rule == 'apfs resizeContainer':
            if self.plan['kind'] == 'install':
                self.resized = True
            else:
                self.grown = True
            self.verify(rule)
        elif rule == 'addPartition':
            after = _dev(argv[2])
            lay = self.verify(rule)
            prev = next((q for q in lay.parts if q.dev == after), None)
            new = lay.after(prev) if prev is not None else None
            lo, hi = self.plan['gap_offset'], self.plan['gap_offset'] + self.plan['gap_bytes']
            if new is None or new.free or new.dev in self.before or not (lo <= new.offset and new.end <= hi):
                raise Refused('STOP after addPartition: no new partition inside the planned free space after %s' % after)
            self.created[new.dev] = PART_TYPES[argv[3]]
            if new.container is not None:
                self.created_containers.add(new.container.ref)
            elif PART_TYPES[argv[3]] == 'apfs':
                self.created_containers.add(_container_of(new.dev))
            self.after_ok.add(new.dev)
            self.used += new.size
            self.note(step='created', dev=new.dev, kind=self.created[new.dev], uuid=new.uuid, offset=new.offset, bytes=new.size)
        elif rule in ('eraseVolume', 'apfs deleteContainer'):
            target = _dev(argv[-1])
            for r in self.plan['remove']:
                if r['dev'] == target or r.get('container') == target or r['uuid'] == self._last_uuid.get(target):
                    self.removed.add(r['dev'])
            self.verify(rule)

    def write_file(self, path, data):
        """Files on the SFBOOT partition (update): only below a directory the executor opened."""
        real = os.path.realpath(path)
        if not any(real.startswith(os.path.realpath(d) + os.sep) for d in self.write_dirs):
            raise Refused('refused write to %s: not on the SiliconForest boot partition' % path)
        self.note(step='write', path=path, bytes=len(data), state='start')
        with open(path, 'wb') as fd:
            fd.write(data)
            fd.flush()
            os.fsync(fd.fileno())
        self.note(step='write', path=path, state='done')

    def open(self, path, mode='rb', *args, **kw):
        """open() for the engine's modules: raw writes only to a root partition created here."""
        if path.startswith('/dev/') and any(c in mode for c in 'wa+'):
            dev = _dev(path)
            if self.created.get(dev) != 'linux':
                self.note(step='open', argv=[path, mode], state='refused')
                raise Refused('refused raw write to %s: not the root partition this installation created' % path)
            self.note(step='open', argv=[path, mode], state='start')
            self.log('%s raw write to %s' % ('SIMULATED:' if self.simulated else 'opening', path))
            if self.execute is not None and hasattr(self.execute, 'open_device'):
                return self.execute.open_device(path, mode, *args, **kw)
        return open(path, mode, *args, **kw)

    def system(self, command):
        """os.system for the engine (Asahi calls `shutdown -h now` / `shutdown -r now` this way)."""
        argv = command.split()
        self.run(argv, why='shutdown')
        return 0
SF_EMBED_6_END
  cat > "$1/sf_engine.py" <<'SF_EMBED_7_END'
#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""SiliconForest installer: the part that decides and the part that acts. install.sh runs it.

    sf_engine.py check     [--manifest M]                   what this Mac is and what is on its disk
    sf_engine.py install   [--dry-run] [--size N] --manifest M --artifacts D --engine E
    sf_engine.py uninstall [--dry-run]
    sf_engine.py update    [--dry-run] --manifest M --artifacts D

Everything runs read-only as the logged-in user until the plan has been shown and confirmed
once, by typing a word; then the same program runs again under sudo, reads the disk again,
makes the same plan again and acts only if both plans agree. Every change goes through
sf_gate.Gate. The install itself is done by the Asahi Linux installer's own code (the
engine, v0.9.2, unmodified, in --engine), driven step by step from here; the sequence follows
its main.py (action_install_into_free, do_install, step2), MIT, "Copyright (c) 2021 The
Asahi Linux contributors".
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import sf_fwslot  # noqa: E402
import sf_gate  # noqa: E402
import sf_kernelcfg  # noqa: E402
import sf_manifest  # noqa: E402
import sf_plan  # noqa: E402
from sf_disk import Layout, gb  # noqa: E402

STATE_DIR = '/var/db/siliconforest-installer'
STAGE1_NAME = 'siliconforest-stage1.bin'
WORDS = {'install': 'install', 'uninstall': 'uninstall', 'update': 'update'}
LOG = None


def _read(path):
    with open(path, 'rb') as fd:
        return fd.read()


def say(*a):
    text = ' '.join(str(x) for x in a)
    print(text, flush=True)
    if LOG:
        with open(LOG, 'a') as fd:
            fd.write(time.strftime('%H:%M:%S ') + text + '\n')


def real_run(argv):
    try:
        r = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        return 127, b''
    return r.returncode, r.stdout


def load_models():
    for p in (os.path.join(HERE, 'models.tsv'), os.path.join(HERE, '..', 'models.tsv')):
        if os.path.exists(p):
            return sf_plan.load_models(_read(p).decode())
    raise SystemExit('models.tsv is missing')


def load_manifest(path, models):
    if not path:
        return None
    supported = [t for t, m in models.items() if m.status == 'supported']
    return sf_manifest.check(_read(path), supported)


def show_findings(findings):
    mark = {'refuse': 'NO  ', 'warn': 'NOTE', 'info': '    '}
    for x in findings:
        level, text = (x.level, x.text) if hasattr(x, 'level') else (x['level'], x['text'])
        say('  %s %s' % (mark[level], text))


def show_plan(plan, facts):
    say('')
    say('The disk now:')
    say(facts.layout.table())
    say('')
    if plan.get('provisional_sizes'):
        say('(No SiliconForest release exists yet: the root size is a placeholder until a release names its image size.)')
    say('What will change if you confirm:')
    for i, line in enumerate(plan['changes'], 1):
        say('  %d. %s' % (i, line))
    say('')


def confirm(word, tty='/dev/tty'):
    say('Type "%s" and press Return to make these changes; anything else stops here with nothing changed.' % word)
    try:
        with open(tty) as fd:
            answer = fd.readline().strip()
    except OSError:
        answer = ''
    say('answer: %r' % answer)
    return answer == word


def plan_for(cmd, facts, models, manifest, args):
    if cmd == 'install':
        return sf_plan.plan_install(facts, models, manifest, args.size)
    if cmd == 'uninstall':
        return sf_plan.plan_uninstall(facts, models)
    return sf_plan.plan_update(facts, models, manifest)


def same_plan(a, b):
    keys = ('kind', 'layout_digest', 'resize', 'after', 'gap_offset', 'total_bytes', 'root_bytes', 'remove', 'grow', 'boot_dev', 'root', 'release')
    return all(a.get(k) == b.get(k) for k in keys)


# ---- the Asahi engine, behind the gate -------------------------------------------------------
class AsahiEngine:
    """Imports the Asahi installer's modules from `engine_dir` and routes their changes through the gate."""

    def __init__(self, engine_dir, gate):
        self.dir, self.gate = engine_dir, gate
        sys.path.insert(0, engine_dir)
        os.chdir(engine_dir)
        import diskutil, osinstall, stub, osenum, system, bugs, m1n1  # noqa: E401
        import main as amain
        from asahi_firmware.core import FWPackage
        self.diskutil, self.osinstall, self.stub, self.osenum, self.system = diskutil, osinstall, stub, osenum, system
        self.amain, self.bugs, self.m1n1, self.FWPackage = amain, bugs, m1n1, FWPackage

        class GatedSubprocess:
            PIPE, STDOUT, DEVNULL = subprocess.PIPE, subprocess.STDOUT, subprocess.DEVNULL
            CalledProcessError, CompletedProcess = subprocess.CalledProcessError, subprocess.CompletedProcess

            @staticmethod
            def run(argv, **kw):
                if gate.classify([str(a) for a in argv]) is None and gate.execute is None:
                    return subprocess.run(argv, **kw)
                rc, out = gate.run(argv, why='engine', input=kw.get('input'))
                if kw.get('check') and rc != 0:
                    raise subprocess.CalledProcessError(rc, argv, out)
                return subprocess.CompletedProcess(argv, rc, out, b'')

        def action(du, *args, verbose=False):
            gate.run(['diskutil'] + list(args), why='engine diskutil')

        for mod in (diskutil, osinstall, stub, amain, osenum, system):
            mod.subprocess = GatedSubprocess
        diskutil.DiskUtil.action = action
        osinstall.open = gate.open
        os.system = gate.system

    def install(self, plan, manifest, artifacts, log):
        A = self.amain
        sysinfo = self.system.SystemInfo()
        im = A.InstallerMain(_read('version.tag').decode().strip())
        im.sysinfo, im.expert = sysinfo, False
        self.bugs.run_checks(im)
        im.device = A.DEVICES.get(sysinfo.device_class)
        if im.device is None or sysinfo.chip_id not in A.CHIP_MIN_VER:
            raise SystemExit('The Asahi engine does not know this Mac (%s).' % sysinfo.device_class)
        dutil = self.diskutil.DiskUtil()
        dutil.get_info()
        disk = dutil.find_system_disk()
        im.sys_disk = im.cur_disk = disk
        im.dutil = dutil
        im.parts = parts = dutil.get_partitions(disk)
        im.osinfo = osinfo = self.osenum.OSEnum(sysinfo, dutil, disk)
        osinfo.collect(parts)
        im.is_edu_128gb = False
        im.cur_os = find_cur_os(parts, sysinfo)
        im.check_cur_os()
        template = installer_template(manifest, plan)
        data = {'os_list': [template]}
        with open('installer_data.json', 'w') as fd:
            json.dump(data, fd, indent=1)
        ipsw = im.choose_ipsw(template['supported_fw'])
        if plan['resize']:
            r = plan['resize']
            say('Shrinking macOS (%s) to %s; the Mac may seem to stop for a minute.' % (r['store'], gb(r['to_bytes'])))
            dutil.resizeContainer(r['store'], r['to_bytes'])
            dutil.get_info()
            parts = dutil.get_partitions(disk)
        free = [p for p in parts if p.free and p.name == plan['after'] and p.offset == plan['gap_offset']]
        if len(free) != 1:
            raise sf_gate.Refused('the planned free space (after %s at byte %d) is not there' % (plan['after'], plan['gap_offset']))
        osins = im.osins = self.osinstall.OSInstaller(dutil, data, template)
        osins.load_package()
        osins.name = 'SiliconForest'
        im.part = dutil.addPartition(free[0].name, 'apfs', 'SiliconForest', plan['stub_bytes'])
        ins = im.ins = self.stub.StubInstaller(sysinfo, dutil, osinfo)
        ins.load_ipsw(ipsw)
        ins.prepare_volume(im.part)
        ins.check_volume()
        ins.install_files(im.cur_os)
        osins.partition_disk(im.part.name, plan['boot_bytes'] + plan['root_bytes'])
        os.makedirs('vendorfw', exist_ok=True)
        pkg = self.FWPackage('vendorfw')
        ins.collect_firmware(pkg)
        pkg.close()
        osins.firmware_package = pkg
        osins.install(ins)
        efi, root = osins.efi_part, osins.part_info[1]
        mount = dutil.mount(efi.name)
        bs = plan['block_size']
        finish(self.gate, manifest, artifacts, mount, root.name, root.uuid, root.offset // bs, root.size // bs, 'vendorfw/firmware.tar', log)
        with open(os.path.join(mount, 'sf', 'install.json'), 'w') as fd:
            json.dump(dict(release=manifest['release'], vgid=ins.osi.vgid, boot_partuuid=efi.uuid.lower(), root_partuuid=root.uuid,
                           root_first_block=root.offset // bs, root_blocks=root.size // bs, installed=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())), fd, indent=1)
        if log:
            shutil.copy(log, os.path.join(mount, 'sf', 'install.log'))
        say('')
        say('The first part is done. What follows are the Asahi Linux installer\'s own instructions for the second part, in recovery.')
        say('Afterwards: the first start of SiliconForest happens by itself; then set macOS back as the startup disk (docs/INSTALL.md, "After the first start").')
        im.step2(report=False)


def find_cur_os(parts, sysinfo):
    """The running macOS, as the Asahi installer's main_loop finds it."""
    cur, default = None, None
    for p in parts:
        for osi in (p.os or []):
            if not osi.version:
                continue
            if sysinfo.boot_vgid == osi.vgid and sysinfo.boot_uuid == osi.rec_vgid:
                if p.type == 'APFS':
                    cur = osi
            elif sysinfo.boot_uuid == osi.vgid:
                cur = osi
            if sysinfo.default_boot == osi.vgid:
                default = osi
    if cur is None and sysinfo.boot_mode != 'macOS':
        cur = default
    return cur


def installer_template(manifest, plan):
    o = manifest['os']
    pkg = sf_manifest.role(manifest, 'os-package')['file']
    return dict(name='SiliconForest', default_os_name='SiliconForest', boot_object=STAGE1_NAME, next_object='sf/boot.bin',
                package=pkg, icon='siliconforest.icns', supported_fw=list(manifest['stub_firmware']),
                partitions=[dict(name='SFBOOT', type='EFI', size='%dB' % plan['boot_bytes'], format='fat', source='esp', copy_firmware=True),
                            dict(name='Root', type='Linux', size='%dB' % o['root_min_bytes'], image=o['root_image'] if 'root_image' in o else 'root.img', expand=True)])


def finish(gate, manifest, artifacts, mount, root_dev, root_uuid, first, blocks, firmware_tar, log):
    """Ours, after the engine has made the partitions: this Mac's identifiers and its firmware."""
    o = manifest['os']
    kpath = os.path.join(mount, 'sf', 'kernel.bin')
    data = _read(kpath)
    new = sf_kernelcfg.personalize(data, root_uuid, first, blocks, o['kernel_record_sha256'])
    gate.write_dirs = (os.path.join(mount, 'sf'),)
    gate.write_file(kpath, new)
    if _read(kpath) != new:
        raise sf_gate.Refused('sf/kernel.bin does not read back as written')
    say('sf/kernel.bin: root partition %s, first block %d, %d blocks.' % (root_uuid, first, blocks))
    blob, names = sf_fwslot.payload(firmware_tar)
    n = sf_fwslot.write('/dev/r' + root_dev, o['firmware_slot']['offset'], o['firmware_slot']['length'], blob, opener=gate.open)
    say('Wi-Fi/Bluetooth firmware: %d files, %d bytes into the root\'s firmware slot.' % (len(names), n))


# ---- uninstall and update (no engine needed) --------------------------------------------------
def execute_uninstall(plan, gate, reader):
    for r in plan['remove']:
        if r['action'] == 'deleteContainer':
            gate.run(['diskutil', 'apfs', 'deleteContainer', r['container']], why='uninstall: startup volume')
            left = next((q for q in reader().real_parts() if q.uuid == r['uuid'] or q.offset == r['offset']), None)
            if left is not None:
                gate.run(['diskutil', 'eraseVolume', 'free', 'free', left.dev], why='uninstall: startup volume partition')
        else:
            cur = next((q for q in reader().real_parts() if q.uuid == r['uuid']), None)
            if cur is None:
                say('%s is already gone.' % r['dev'])
                continue
            gate.run(['diskutil', 'eraseVolume', 'free', 'free', cur.dev], why='uninstall: ' + r['what'])
    if plan['grow']:
        lay = reader()
        mac = lay.macos_part()
        if mac is not None and lay.gap_after(mac) is not None:
            gate.run(['diskutil', 'apfs', 'resizeContainer', mac.dev, '0'], why='uninstall: give the space back to macOS')
        else:
            say('The freed space is not directly after macOS; it stays free.')


def execute_update(plan, gate, manifest, artifacts, run=real_run):
    import plistlib
    rc, out = run(['diskutil', 'info', '-plist', plan['boot_dev']])
    info = plistlib.loads(out) if rc == 0 else {}
    mount = info.get('MountPoint')
    if not mount:
        gate.run(['diskutil', 'mount', plan['boot_dev']], why='update: mount SFBOOT')
        info = plistlib.loads(run(['diskutil', 'info', '-plist', plan['boot_dev']])[1])
        mount = info.get('MountPoint')
    if not mount or not os.path.isdir(os.path.join(mount, 'sf')):
        raise sf_gate.Refused('SFBOOT (%s) has no sf/ directory' % plan['boot_dev'])
    import zipfile
    pkg = zipfile.ZipFile(os.path.join(artifacts, sf_manifest.role(manifest, 'os-package')['file']))
    boot, kern = pkg.read('esp/sf/boot.bin'), pkg.read('esp/sf/kernel.bin')
    r = plan['root']
    kern = sf_kernelcfg.personalize(kern, r['uuid'], r['first_block'], r['blocks'], manifest['os']['kernel_record_sha256'])
    sf = os.path.join(mount, 'sf')
    gate.write_dirs = (sf,)
    for name, data in (('boot.bin', boot), ('kernel.bin', kern)):
        path = os.path.join(sf, name)
        if os.path.exists(path) and _read(path) == data:
            say('sf/%s is already this release\'s.' % name)
            continue
        if os.path.exists(path):
            gate.write_file(path + '.old', _read(path))
        gate.write_file(path, data)
        if _read(path) != data:
            raise sf_gate.Refused('sf/%s does not read back as written' % name)
        say('sf/%s replaced (previous: sf/%s.old).' % (name, name))


def parse_size(text):
    t = text.strip().upper().rstrip('B')
    mult = 1e9
    if t.endswith('G'):
        t = t[:-1]
    elif t.endswith('T'):
        t, mult = t[:-1], 1e12
    value = float(t)
    if not 0 < value < 1e6:
        raise argparse.ArgumentTypeError('a size in GB, such as 60 or 60G')
    return int(value * mult)


def download_list(manifest):
    """Lines for install.sh: `<file> <url> <bytes> <sha256> [<joined file>]`, parts before their whole."""
    base = manifest['base_url']
    out = []
    for f in manifest['files']:
        for part in f.get('parts') or []:
            out.append('%s %s%s %d %s %s' % (part['file'], base, part['file'], part['bytes'], part['sha256'], f['file']))
        if not f.get('parts'):
            out.append('%s %s%s %d %s' % (f['file'], base, f['file'], f['bytes'], f['sha256']))
        else:
            out.append('%s - %d %s' % (f['file'], f['bytes'], f['sha256']))
    return out


# ---- main ----------------------------------------------------------------------------------
def main(argv=None):
    global LOG
    ap = argparse.ArgumentParser(description='SiliconForest installer engine (run by install.sh)')
    ap.add_argument('command', choices=('check', 'install', 'uninstall', 'update', 'files'))
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--size', type=parse_size, help='space for SiliconForest in GB (startup volume, boot partition and root)')
    ap.add_argument('--manifest')
    ap.add_argument('--artifacts')
    ap.add_argument('--engine')
    ap.add_argument('--log')
    ap.add_argument('--confirmed', help=argparse.SUPPRESS)
    args = ap.parse_args(argv)
    LOG = args.log
    models = load_models()
    manifest = load_manifest(args.manifest, models)
    if args.command == 'files':
        for line in download_list(manifest):
            print(line)
        return 0
    facts = sf_plan.gather(real_run)
    cmd = args.command
    if cmd == 'check':
        findings = sf_plan.check(facts, models, manifest)
        show_findings(findings)
        if facts.layout is not None:
            say('')
            say('The disk:')
            say(facts.layout.table())
        return 3 if sf_plan.refusals(findings) else 0
    if (cmd == 'install' and manifest is None and not args.dry_run) or (cmd == 'update' and manifest is None):
        say('There is no SiliconForest release yet, so there is nothing to install. Nothing was changed.')
        say('You can see what the installer would do with --dry-run.')
        return 4
    try:
        plan = plan_for(cmd, facts, models, manifest, args)
    except sf_plan.Refusal as e:
        show_findings(e.findings)
        say('Nothing was changed.')
        return 3
    show_findings(plan['findings'])
    show_plan(plan, facts)
    if args.dry_run:
        say('Dry run: nothing was changed.')
        return 0
    if args.confirmed is None:
        if os.geteuid() == 0:
            say('Run the installer as yourself, not as root: it asks for your password when it needs it.')
            return 2
        if not confirm(WORDS[cmd]):
            say('Stopped. Nothing was changed.')
            return 1
        path = os.path.join(args.artifacts or os.path.dirname(LOG or '/tmp/x'), 'plan-%s.json' % cmd)
        with open(path, 'w') as fd:
            json.dump(plan, fd, indent=1)
        say('Your macOS password is needed now (sudo).')
        again = ['sudo', sys.executable, '-I', os.path.abspath(__file__)] + (argv if argv is not None else sys.argv[1:]) + ['--confirmed', path]
        env = ['env', 'DYLD_LIBRARY_PATH=' + os.environ.get('DYLD_LIBRARY_PATH', ''), 'DYLD_FRAMEWORK_PATH=' + os.environ.get('DYLD_FRAMEWORK_PATH', ''),
               'SSL_CERT_FILE=' + os.environ.get('SSL_CERT_FILE', '')]
        os.execvp('caffeinate', ['caffeinate', '-dis'] + again[:1] + env + again[1:])
    # under sudo: the same plan again, or nothing
    if os.geteuid() != 0:
        say('This step must run under sudo.')
        return 2
    saved = json.loads(_read(args.confirmed))
    if not same_plan(saved, plan):
        say('The disk changed between the plan you confirmed and now. Nothing was changed; run the installer again.')
        return 5
    os.makedirs(STATE_DIR, exist_ok=True)
    journal = os.path.join(STATE_DIR, 'journal.jsonl')
    reader = lambda: sf_plan.gather(real_run).layout
    gate = sf_gate.Gate(plan, reader, journal=journal, log=say)
    gate.note(step='begin', kind=cmd, release=plan.get('release'), digest=plan['layout_digest'])
    try:
        if cmd == 'install':
            stage1 = sf_manifest.role(manifest, 'stage1')['file']
            os.makedirs(os.path.join(args.engine, 'boot'), exist_ok=True)
            shutil.copy(os.path.join(args.artifacts, stage1), os.path.join(args.engine, 'boot', STAGE1_NAME))
            os.makedirs(os.path.join(args.artifacts, 'os'), exist_ok=True)
            pkg = sf_manifest.role(manifest, 'os-package')['file']
            target = os.path.join(args.artifacts, 'os', pkg)
            if not os.path.exists(target):
                os.link(os.path.join(args.artifacts, pkg), target)
            os.environ.update(DISTRO='SiliconForest', DISTRO_DOCS='https://github.com/chriskearney/siliconforest/blob/main/docs/INSTALL.md',
                              REPO_BASE=args.artifacts)
            for k in ('REPORT', 'REPORT_TAG', 'EXPERT', 'IPSW_BASE', 'INSTALLER_DATA', 'ALLOW_VM'):
                os.environ.pop(k, None)
            AsahiEngine(os.path.abspath(args.engine), gate).install(plan, manifest, args.artifacts, LOG)
        elif cmd == 'uninstall':
            execute_uninstall(plan, gate, reader)
            say('SiliconForest has been removed. The disk now:')
            say(reader().table())
        else:
            execute_update(plan, gate, manifest, args.artifacts)
            say('Update done: SiliconForest starts release %s the next time you choose it.' % manifest['release'])
    except sf_gate.Refused as e:
        gate.note(step='stopped', reason=str(e))
        say(str(e))
        say('Stopped. The journal of what was done is %s; the log is %s.' % (journal, LOG))
        return 6
    gate.note(step='end', kind=cmd)
    return 0


if __name__ == '__main__':
    sys.exit(main())
SF_EMBED_7_END
}

sf_main "$@"
