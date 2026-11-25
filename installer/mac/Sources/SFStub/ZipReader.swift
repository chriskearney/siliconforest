// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// Reads members of a zip (Apple's restore image) through a RangeSource: only the end records, the
// central directory and the members asked for are fetched. Zip64 is required (restore images are
// larger than 4 GiB). Every member's CRC-32 and size are checked as it streams. The Swift counterpart
// of installer/payload/firmware/remote_zip.py, and of what upstream got from Python's zipfile.

import Compression
import Foundation

public struct ZipEntry: Sendable, Equatable {
    public var name: String
    public var method: UInt16
    public var crc32: UInt32
    public var compressedSize: UInt64
    public var size: UInt64
    public var headerOffset: UInt64
    public var externalAttributes: UInt32
    public var madeBy: UInt16

    public var isDirectory: Bool { name.hasSuffix("/") }
    /// Unix mode from the external attributes, when the archive was made on Unix (Python's zipfile looks at the same bits).
    public var unixMode: UInt32 { externalAttributes >> 16 }
    public var isSymlink: Bool { (unixMode & 0o170000) == 0o120000 }
}

public final class ZipReader {
    public let source: RangeSource
    public private(set) var entries: [ZipEntry] = []
    var byName: [String: Int] = [:]

    public init(_ source: RangeSource) throws {
        self.source = source
        try readDirectory()
    }

    static func u16(_ d: Data, _ o: Int) -> UInt16 { UInt16(d[d.startIndex + o]) | UInt16(d[d.startIndex + o + 1]) << 8 }
    static func u32(_ d: Data, _ o: Int) -> UInt32 { UInt32(u16(d, o)) | UInt32(u16(d, o + 2)) << 16 }
    static func u64(_ d: Data, _ o: Int) -> UInt64 { UInt64(u32(d, o)) | UInt64(u32(d, o + 4)) << 32 }

    func readDirectory() throws {
        let tailLen = Int(min(source.size, 65_536 + 22))
        let tail = try source.read(offset: source.size - UInt64(tailLen), length: tailLen)
        guard let i = Self.lastIndex(of: [0x50, 0x4B, 0x05, 0x06], in: tail, before: tail.count) else { throw StubError("no end of central directory") }
        var count = UInt64(Self.u16(tail, i + 10))
        var cdSize = UInt64(Self.u32(tail, i + 12))
        var cdOff = UInt64(Self.u32(tail, i + 16))
        if cdOff == 0xFFFF_FFFF || count == 0xFFFF || cdSize == 0xFFFF_FFFF {
            guard let j = Self.lastIndex(of: [0x50, 0x4B, 0x06, 0x07], in: tail, before: i) else { throw StubError("zip64 locator missing") }
            let eocd64 = Self.u64(tail, j + 8)
            let rec = try source.read(offset: eocd64, length: 56)
            guard rec.prefix(4) == Data([0x50, 0x4B, 0x06, 0x06]) else { throw StubError("zip64 end record missing") }
            count = Self.u64(rec, 32); cdSize = Self.u64(rec, 40); cdOff = Self.u64(rec, 48)
        }
        guard cdOff + cdSize <= source.size, cdSize < 256 << 20 else { throw StubError("implausible central directory") }
        let cd = try source.read(offset: cdOff, length: Int(cdSize))
        var p = 0
        for _ in 0..<count {
            guard p + 46 <= cd.count, Self.u32(cd, p) == 0x0201_4B50 else { throw StubError("bad central directory entry") }
            let madeBy = Self.u16(cd, p + 4)
            let flags = Self.u16(cd, p + 8), method = Self.u16(cd, p + 10)
            let crc = Self.u32(cd, p + 16)
            var csize = UInt64(Self.u32(cd, p + 20)), usize = UInt64(Self.u32(cd, p + 24))
            let nlen = Int(Self.u16(cd, p + 28)), xlen = Int(Self.u16(cd, p + 30)), clen = Int(Self.u16(cd, p + 32))
            let ext = Self.u32(cd, p + 38)
            var hoff = UInt64(Self.u32(cd, p + 42))
            guard p + 46 + nlen + xlen + clen <= cd.count else { throw StubError("truncated central directory") }
            let nameData = cd.subdata(in: cd.startIndex + p + 46 ..< cd.startIndex + p + 46 + nlen)
            guard let name = String(data: nameData, encoding: (flags & 0x800) != 0 ? .utf8 : .utf8) else { throw StubError("member name is not UTF-8") }
            var q = p + 46 + nlen
            let xend = q + xlen
            while q + 4 <= xend {
                let tag = Self.u16(cd, q), sz = Int(Self.u16(cd, q + 2))
                if tag == 1 {
                    var r = q + 4
                    if usize == 0xFFFF_FFFF, r + 8 <= q + 4 + sz { usize = Self.u64(cd, r); r += 8 }
                    if csize == 0xFFFF_FFFF, r + 8 <= q + 4 + sz { csize = Self.u64(cd, r); r += 8 }
                    if hoff == 0xFFFF_FFFF, r + 8 <= q + 4 + sz { hoff = Self.u64(cd, r); r += 8 }
                }
                q += 4 + sz
            }
            guard (flags & 1) == 0 else { throw StubError("\(name) is encrypted") }
            byName[name] = entries.count
            entries.append(ZipEntry(name: name, method: method, crc32: crc, compressedSize: csize, size: usize,
                                    headerOffset: hoff, externalAttributes: ext, madeBy: madeBy))
            p += 46 + nlen + xlen + clen
        }
    }

    static func lastIndex(of pat: [UInt8], in d: Data, before end: Int) -> Int? {
        var i = end - pat.count
        while i >= 0 {
            if d[d.startIndex + i] == pat[0], d[d.startIndex + i + 1] == pat[1], d[d.startIndex + i + 2] == pat[2], d[d.startIndex + i + 3] == pat[3] { return i }
            i -= 1
        }
        return nil
    }

    public func entry(_ name: String) -> ZipEntry? { byName[name].map { entries[$0] } }

    public func require(_ name: String) throws -> ZipEntry {
        guard let e = entry(name) else { throw StubError("\(name) is not in the restore image") }
        return e
    }

    /// Streams the member's uncompressed bytes to `sink` in chunks. Throws if the CRC-32 or size disagree,
    /// after the last chunk; a caller that writes must treat its output as untrusted until this returns.
    public func stream(_ e: ZipEntry, chunk: Int = 8 << 20, _ sink: (Data) throws -> Void) throws {
        let hdr = try source.read(offset: e.headerOffset, length: 30)
        guard Self.u32(hdr, 0) == 0x0403_4B50 else { throw StubError("bad local header for \(e.name)") }
        let start = e.headerOffset + 30 + UInt64(Self.u16(hdr, 26)) + UInt64(Self.u16(hdr, 28))
        var crc = CRC32()
        var produced: UInt64 = 0
        func emit(_ d: Data) throws { crc.update(d); produced += UInt64(d.count); try sink(d) }
        switch e.method {
        case 0:
            var off: UInt64 = 0
            while off < e.compressedSize {
                let n = Int(min(UInt64(chunk), e.compressedSize - off))
                try emit(try source.read(offset: start + off, length: n))
                off += UInt64(n)
            }
        case 8:
            let inflater = try Inflater()
            var off: UInt64 = 0
            while off < e.compressedSize {
                let n = Int(min(UInt64(chunk), e.compressedSize - off))
                let input = try source.read(offset: start + off, length: n)
                off += UInt64(n)
                try inflater.feed(input, final: off == e.compressedSize, emit)
            }
            guard inflater.finished else { throw StubError("\(e.name): deflate stream did not end") }
        default:
            throw StubError("\(e.name): unsupported compression method \(e.method)")
        }
        guard produced == e.size else { throw StubError("\(e.name): \(produced) bytes, the directory says \(e.size)") }
        guard crc.value == e.crc32 else { throw StubError("\(e.name): CRC-32 mismatch") }
    }

    public func read(_ name: String) throws -> Data {
        let e = try require(name)
        guard e.size < 256 << 20 else { throw StubError("\(name) is too big to read into memory") }
        var out = Data(capacity: Int(e.size))
        try stream(e) { out.append($0) }
        return out
    }
}

/// Raw DEFLATE (zip method 8) through Apple's Compression framework (COMPRESSION_ZLIB is RFC 1951 raw deflate).
final class Inflater {
    var stream = compression_stream(dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!, dst_size: 0,
                                    src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!, src_size: 0, state: nil)
    let outSize = 1 << 20
    let out: UnsafeMutablePointer<UInt8>
    private(set) var finished = false

    init() throws {
        out = .allocate(capacity: outSize)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            out.deallocate()
            throw StubError("can't start the deflate decoder")
        }
    }

    deinit { compression_stream_destroy(&stream); out.deallocate() }

    func feed(_ input: Data, final: Bool, _ emit: (Data) throws -> Void) throws {
        try input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            stream.src_ptr = raw.bindMemory(to: UInt8.self).baseAddress ?? UnsafePointer<UInt8>(bitPattern: 1)!
            stream.src_size = raw.count
            repeat {
                stream.dst_ptr = out
                stream.dst_size = outSize
                let st = compression_stream_process(&stream, final ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)
                let n = outSize - stream.dst_size
                if n > 0 { try emit(Data(bytes: out, count: n)) }
                switch st {
                case COMPRESSION_STATUS_OK:
                    if final && n == 0 && stream.src_size == 0 { throw StubError("deflate stream is truncated") }
                    continue
                case COMPRESSION_STATUS_END: finished = true; return
                default: throw StubError("corrupt deflate data")
                }
            } while final || stream.src_size > 0 || stream.dst_size == 0
        }
    }
}
