#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Generate original PDF fixtures without external fonts or images."""
import argparse
from pathlib import Path


def stream(content):
    return b'<< /Length %d >>\nstream\n' % len(content) + content + b'endstream'


def document_fixture():
    return [
        b'<< /Type /Catalog /Pages 2 0 R >>',
        b'<< /Type /Pages /Count 1 /Kids [3 0 R] >>',
        b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 72 72] '
        b'/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
        b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
        stream(b'BT /F1 6 Tf 10 20 Td (Finch PDF fixture) Tj ET\n'),
        b'<< /Title (Finch fixture) >>',
    ]


def view_fixture():
    pages = (
        (b'1 0 0', b'Field notes'),
        (b'0 1 0', b'Canopy survey'),
        (b'0 0 1', b'River crossing'),
    )
    objects = [
        b'<< /Type /Catalog /Pages 2 0 R >>',
        b'<< /Type /Pages /Count 3 /Kids [5 0 R 7 0 R 9 0 R] >>',
        b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
        b'<< /Title (SiliconForest reading test) >>',
    ]
    for color, label in pages:
        content = (color + b' rg 48 60 144 60 re f\n'
                   b'0 0 0 rg BT /F1 20 Tf 32 148 Td (' + label + b') Tj ET\n')
        stream_id = len(objects) + 2
        objects.extend((
            b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 240 180] '
            b'/Resources << /Font << /F1 3 0 R >> >> /Contents %d 0 R >>' % stream_id,
            stream(content),
        ))
    return objects


def make_pdf(objects, info_id):
    data = bytearray(b'%PDF-1.4\n%\xe2\xe3\xcf\xd3\n')
    offsets = []
    for i, obj in enumerate(objects, 1):
        offsets.append(len(data))
        data += b'%d 0 obj\n' % i + obj + b'\nendobj\n'
    xref = len(data)
    size = len(objects) + 1
    data += b'xref\n0 %d\n0000000000 65535 f \n' % size
    for offset in offsets:
        data += b'%010d 00000 n \n' % offset
    data += (b'trailer\n<< /Size %d /Root 1 0 R /Info %d 0 R >>\n'
             b'startxref\n%d\n%%%%EOF\n' % (size, info_id, xref))
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--view', action='store_true',
                        help='generate three colored pages for render and navigation checks')
    args = parser.parse_args()
    objects, info_id = (view_fixture(), 4) if args.view else (document_fixture(), 6)
    with args.destination.open('xb') as output:
        output.write(make_pdf(objects, info_id))


if __name__ == '__main__':
    main()
