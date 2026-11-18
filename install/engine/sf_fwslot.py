# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Hand this Mac's Wi-Fi and Bluetooth firmware to SiliconForest.

The firmware is Apple's and is never shipped by SiliconForest. The installer's engine (the
Asahi Linux installer) collects it on the user's Mac from Apple's recovery image for this
model, into `vendorfw/firmware.tar` with the names Linux's brcmfmac driver uses, which are
the names SiliconForest's drivers look for: brcm/ (Wi-Fi and Bluetooth, /Library/Firmware/brcm)
and apple/dfrmtfw-<board>.bin, apple/tpmtfw-<board>.bin (Touch Bar and trackpad,
/Library/Firmware/apple).

SiliconForest's storage driver reads only its own root partition, so the firmware has to be
inside it. The release's root image contains a preallocated, contiguous file (the slot) at a
byte offset the release manifest gives. An empty slot starts with the line `SFFWSLOT1`.
The installer writes, at that offset of the new root partition:

    4096-byte header: b'SFFWSLOT1\\nlength=<payload bytes>\\nsha256=<hex>\\n', zero padded
    payload:          a tar of those members of firmware.tar

and SiliconForest's first start checks the header and unpacks the payload. Only file data
inside one existing file changes; the filesystem's metadata is not touched.
"""
import hashlib
import io
import tarfile

HEAD = 4096
EMPTY = b'SFFWSLOT1\n'
WANT = ('brcm/', 'apple/dfrmtfw-', 'apple/tpmtfw-')


class SlotError(Exception):
    pass


def payload(firmware_tar):
    """A tar with the members of the engine's firmware.tar that SiliconForest's drivers load."""
    src = tarfile.open(firmware_tar, 'r:')
    out = io.BytesIO()
    dst = tarfile.open(fileobj=out, mode='w', format=tarfile.USTAR_FORMAT)
    names = set()
    for m in src.getmembers():
        if not m.name.startswith(WANT) or '..' in m.name.split('/'):
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
