# SPDX-License-Identifier: MIT
"""Read the Linux payload from the standard PE/COFF UKI container."""
import hashlib
from pathlib import Path
import struct

from .release import require


def check(path, expected):
    data = Path(path).read_bytes()
    require(len(data) >= 64 and data[:2] == b'MZ', 'Boot image is not a PE UKI')
    pe = struct.unpack_from('<I', data, 60)[0]
    require(pe >= 64 and pe + 24 <= len(data) and data[pe:pe + 4] == b'PE\0\0',
            'Invalid UKI PE header')
    machine, count = struct.unpack_from('<HH', data, pe + 4)
    optional = struct.unpack_from('<H', data, pe + 20)[0]
    table = pe + 24 + optional
    require(machine == 0xAA64 and 0 < count <= 96 and optional >= 112 and
            table + count * 40 <= len(data) and struct.unpack_from('<H', data, pe + 24)[0] == 0x20B,
            'Require a bounded ARM64 PE32+ UKI')
    sections = {}
    for index in range(count):
        header = table + index * 40
        name = data[header:header + 8].rstrip(b'\0')
        size = struct.unpack_from('<I', data, header + 8)[0]
        raw_size, offset = struct.unpack_from('<II', data, header + 16)
        if name in (b'.linux', b'.initrd'):
            require(name not in sections and 0 < size <= raw_size and
                    offset >= table + count * 40 and offset + raw_size <= len(data),
                    'Invalid or duplicate UKI payload section')
            sections[name] = data[offset:offset + size]
    require(b'.linux' in sections and b'.initrd' in sections, 'UKI lacks Linux or initramfs')
    require(hashlib.sha256(sections[b'.linux']).hexdigest() == expected,
            'Generated UKI does not contain the pinned kernel Image')
