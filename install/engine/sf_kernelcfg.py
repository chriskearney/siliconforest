# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Write this Mac's root partition into sf/kernel.bin.

sf/kernel.bin is a list of records (integrations/siliconforest/m1-native-boot/b1/pdsf_pack.py,
src/pdsf.h): CONFIG (text: `bootargs=...` and keys), KERNEL (the kernel collection, gzip), END.
The release's command-line template (release/image/bootargs.template on the release-image
branch) names the root partition with three tokens that stand for values only the installed
disk knows:

    sfnvme_part=@SF_PARTUUID@ sfnvme_part_lba=@SF_PART_LBA@ sfnvme_part_blocks=@SF_PART_BLOCKS@

They are the storage driver's write fence (m1-storage/kernel/SFAppleNVMe.cpp): it writes only
inside the partition with that GUID, first block and length, and only if both GPT copies agree.
An unfilled token is not a GUID, so the driver refuses the partition and the root: fail closed.
The release's own sf_personalize.py packs sf/kernel.bin from the template; this module checks
the result (`verify`: it must name exactly this Mac's root partition, and its records must be
whole), and can fill the tokens of an already packed CONFIG record (`personalize`), keeping
every other record byte for byte.
"""
import hashlib
import re
import struct
import zlib

MAGIC, VERSION, ALIGN = 0x46534450, 1, 16
END, CONFIG, KERNEL, RAMDISK = 0, 1, 2, 3
HEADER = struct.Struct('<IHHIIQQ')
BOOTARGS_CAPACITY = 608            # firmware BootArgs revision 2 (M1), terminating NUL included
TOKENS = ('@SF_PARTUUID@', '@SF_PART_LBA@', '@SF_PART_BLOCKS@')
GUID = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')


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
    guid = partuuid.lower()
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


def verify(data, partuuid, first_block, blocks, fs_uuid=None):
    """Raise ConfigError unless `data` is a whole record list whose command line names exactly
    this partition (and, if given, the release's root filesystem) once each."""
    recs = parse(data)
    kinds = [r[0] for r in recs]
    if kinds[0] != CONFIG or kinds.count(CONFIG) != 1 or kinds.count(KERNEL) != 1 or kinds[-1] != END:
        raise ConfigError('expected CONFIG, KERNEL, [RAMDISK], END; found %r' % kinds)
    words = bootargs(data).split()
    want = {'sfnvme_part': partuuid.lower(), 'sfnvme_part_lba': str(first_block), 'sfnvme_part_blocks': str(blocks)}
    if fs_uuid is not None:
        want['boot-uuid'] = fs_uuid.lower()
    for key, value in want.items():
        found = [w for w in words if w.startswith(key + '=')]
        if found != ['%s=%s' % (key, value)]:
            raise ConfigError('the command line has %r for %s, not %s' % (found, key, value))
    if '@' in ' '.join(words):
        raise ConfigError('an unfilled token is left in the command line')
