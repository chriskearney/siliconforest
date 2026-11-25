// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// Little- and big-endian field access on raw blocks. ext4 is little-endian; the jbd2 journal
// superblock is big-endian.

extension Array where Element == UInt8 {
    @inline(__always) public func le16(_ o: Int) -> UInt16 { UInt16(self[o]) | UInt16(self[o + 1]) << 8 }
    @inline(__always) public func le32(_ o: Int) -> UInt32 {
        UInt32(self[o]) | UInt32(self[o + 1]) << 8 | UInt32(self[o + 2]) << 16 | UInt32(self[o + 3]) << 24
    }
    @inline(__always) public func le64(_ o: Int) -> UInt64 { UInt64(le32(o)) | UInt64(le32(o + 4)) << 32 }
    @inline(__always) public func be32(_ o: Int) -> UInt32 {
        UInt32(self[o]) << 24 | UInt32(self[o + 1]) << 16 | UInt32(self[o + 2]) << 8 | UInt32(self[o + 3])
    }
    @inline(__always) public mutating func setLE16(_ o: Int, _ v: UInt16) {
        self[o] = UInt8(v & 0xff); self[o + 1] = UInt8(v >> 8)
    }
    @inline(__always) public mutating func setLE32(_ o: Int, _ v: UInt32) {
        for i in 0..<4 { self[o + i] = UInt8((v >> (8 * UInt32(i))) & 0xff) }
    }
    @inline(__always) public mutating func setLE64(_ o: Int, _ v: UInt64) {
        setLE32(o, UInt32(v & 0xffff_ffff)); setLE32(o + 4, UInt32(v >> 32))
    }
}

/// CRC32C (Castagnoli, reflected polynomial 0x82F63B78) with no pre- or post-inversion, which is
/// the form the ext4 format description uses: callers pass the seed (~0 for the superblock).
public enum CRC32C {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (c >> 1) ^ 0x82F6_3B78 : c >> 1 }
        return c
    }

    public static func update(_ crc: UInt32, _ bytes: ArraySlice<UInt8>) -> UInt32 {
        var c = crc
        table.withUnsafeBufferPointer { t in
            for b in bytes { c = t[Int((c ^ UInt32(b)) & 0xff)] ^ (c >> 8) }
        }
        return c
    }

    public static func update(_ crc: UInt32, _ bytes: [UInt8]) -> UInt32 { update(crc, bytes[...]) }

    public static func update(_ crc: UInt32, le32 v: UInt32) -> UInt32 {
        update(crc, [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8(v >> 24)])
    }
}

/// A plain bit set over block numbers.
struct BitSet {
    private(set) var words: [UInt64]
    let count: Int

    init(count: Int) {
        self.count = count
        words = [UInt64](repeating: 0, count: (count + 63) / 64)
    }

    @inline(__always) func get(_ i: Int) -> Bool { (words[i >> 6] >> UInt64(i & 63)) & 1 != 0 }
    @inline(__always) mutating func set(_ i: Int) { words[i >> 6] |= 1 << UInt64(i & 63) }
    mutating func set(_ start: Int, _ n: Int) { for i in start..<(start + n) { set(i) } }

    func countSet(_ start: Int, _ n: Int) -> Int {
        var c = 0
        var i = start
        let end = start + n
        while i < end {
            if i & 63 == 0, i + 64 <= end { c += words[i >> 6].nonzeroBitCount; i += 64; continue }
            if get(i) { c += 1 }
            i += 1
        }
        return c
    }

    func allClear(_ start: Int, _ n: Int) -> Bool { countSet(start, n) == 0 }
}

extension BitSet {
    /// A copy over `count` bits (at least as many as self), with the extra bits clear.
    func extended(to newCount: Int) -> BitSet {
        precondition(newCount >= count)
        var b = BitSet(count: newCount)
        for (i, w) in words.enumerated() { b.words[i] = w }
        return b
    }

    /// First run of `n` clear bits at or after `from`, below `limit`.
    func firstClearRun(from: Int, length n: Int, limit: Int) -> Int? {
        var i = from
        var run = 0
        while i < limit {
            if get(i) { run = 0 } else { run += 1; if run == n { return i - n + 1 } }
            i += 1
        }
        return nil
    }
}
