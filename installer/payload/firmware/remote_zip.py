# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Read members of a zip (Apple's restore image) from a local file or over HTTPS ranges.

Only the bytes needed are fetched: the end of central directory, the central directory, and the
members asked for. Every range response must be HTTP 206 with a Content-Range that names exactly
the requested span and the expected total size (ENGINE.md section 10). Zip64 is supported, as
restore images are larger than 4 GiB. Each member's CRC-32 and size are checked as it streams.
Python 3.9 compatible (macOS Command Line Tools).
"""

import re
import struct
import urllib.request
import zlib


class ZipError(Exception):
    pass


class LocalSource(object):
    def __init__(self, path):
        self.f = open(path, "rb")
        self.f.seek(0, 2)
        self.size = self.f.tell()

    def read(self, offset, n):
        self.f.seek(offset)
        data = self.f.read(n)
        if len(data) != n:
            raise ZipError("short read")
        return data


class HTTPSource(object):
    def __init__(self, url, expected_size=None, timeout=60):
        if not url.startswith("https://"):
            raise ZipError("only https URLs")
        self.url, self.timeout = url, timeout
        self.bytes_fetched = 0
        req = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(req, timeout=timeout) as r:
            self.size = int(r.headers["Content-Length"])
            if "bytes" not in (r.headers.get("Accept-Ranges") or ""):
                raise ZipError("server does not offer byte ranges")
        if expected_size and self.size != expected_size:
            raise ZipError("remote size %d, expected %d" % (self.size, expected_size))

    def read(self, offset, n, attempts=4):
        last = None
        for _ in range(attempts):
            try:
                req = urllib.request.Request(self.url, headers={"Range": "bytes=%d-%d" % (offset, offset + n - 1)})
                with urllib.request.urlopen(req, timeout=self.timeout) as r:
                    if r.status != 206:
                        raise ZipError("expected HTTP 206, got %d" % r.status)
                    cr = r.headers.get("Content-Range", "")
                    if cr != "bytes %d-%d/%d" % (offset, offset + n - 1, self.size):
                        raise ZipError("Content-Range %r does not match the request" % cr)
                    data = r.read()
                if len(data) != n:
                    raise ZipError("short range body")
                self.bytes_fetched += n
                return data
            except (OSError, ZipError) as e:  # urllib errors are OSErrors
                last = e
        raise ZipError("range %d+%d failed: %s" % (offset, n, last))


class Member(object):
    def __init__(self, name, method, crc, csize, usize, header_offset):
        self.name, self.method, self.crc = name, method, crc
        self.csize, self.usize, self.header_offset = csize, usize, header_offset


class RemoteZip(object):
    def __init__(self, source):
        self.src = source
        self.members = {}
        self._read_directory()

    def _read_directory(self):
        tail_len = min(self.src.size, 65536 + 22)
        tail = self.src.read(self.src.size - tail_len, tail_len)
        i = tail.rfind(b"PK\x05\x06")
        if i < 0:
            raise ZipError("no end of central directory")
        (_, _, _, _, count, cd_size, cd_off, _) = struct.unpack("<IHHHHIIH", tail[i:i + 22])
        if cd_off == 0xFFFFFFFF or count == 0xFFFF or cd_size == 0xFFFFFFFF:
            j = tail.rfind(b"PK\x06\x07", 0, i)
            if j < 0:
                raise ZipError("zip64 locator missing")
            (_, _, eocd64_off, _) = struct.unpack("<IIQI", tail[j:j + 20])
            rec = self.src.read(eocd64_off, 56)
            if rec[:4] != b"PK\x06\x06":
                raise ZipError("zip64 end record missing")
            (_, _, _, _, _, _, _, count, cd_size, cd_off) = struct.unpack("<IQHHIIQQQQ", rec)
        cd = self.src.read(cd_off, cd_size)
        p = 0
        for _ in range(count):
            if cd[p:p + 4] != b"PK\x01\x02":
                raise ZipError("bad central directory entry")
            (_, _, _, flags, method, _, _, crc, csize, usize, nlen, xlen, clen, _, _, _, hoff) = \
                struct.unpack("<IHHHHHHIIIHHHHHII", cd[p:p + 46])
            name = cd[p + 46:p + 46 + nlen].decode("utf-8")
            extra = cd[p + 46 + nlen:p + 46 + nlen + xlen]
            q = 0
            while q + 4 <= len(extra):
                tag, sz = struct.unpack("<HH", extra[q:q + 4])
                if tag == 1:
                    vals = list(struct.unpack("<%dQ" % (sz // 8), extra[q + 4:q + 4 + (sz // 8) * 8]))
                    if usize == 0xFFFFFFFF:
                        usize = vals.pop(0)
                    if csize == 0xFFFFFFFF:
                        csize = vals.pop(0)
                    if hoff == 0xFFFFFFFF:
                        hoff = vals.pop(0)
                q += 4 + sz
            if flags & 1:
                raise ZipError("%s is encrypted" % name)
            self.members[name] = Member(name, method, crc, csize, usize, hoff)
            p += 46 + nlen + xlen + clen

    def find(self, pattern):
        rx = re.compile(pattern)
        return sorted(n for n in self.members if rx.fullmatch(n))

    def stream(self, name, chunk=8 << 20):
        """Yield the member's uncompressed bytes; raises if CRC-32 or size disagree."""
        m = self.members[name]
        hdr = self.src.read(m.header_offset, 30)
        if hdr[:4] != b"PK\x03\x04":
            raise ZipError("bad local header for %s" % name)
        nlen, xlen = struct.unpack("<HH", hdr[26:30])
        start = m.header_offset + 30 + nlen + xlen
        if m.method == 0:
            dec = None
        elif m.method == 8:
            dec = zlib.decompressobj(-15)
        else:
            raise ZipError("%s: unsupported method %d" % (name, m.method))
        crc, out, off = 0, 0, 0
        while off < m.csize:
            n = min(chunk, m.csize - off)
            data = self.src.read(start + off, n)
            off += n
            if dec is not None:
                data = dec.decompress(data)
            crc = zlib.crc32(data, crc)
            out += len(data)
            yield data
        if dec is not None:
            data = dec.flush()
            crc = zlib.crc32(data, crc)
            out += len(data)
            if data:
                yield data
        if out != m.usize or (crc & 0xFFFFFFFF) != m.crc:
            raise ZipError("%s failed its CRC-32 or size check" % name)

    def read(self, name):
        return b"".join(self.stream(name))
