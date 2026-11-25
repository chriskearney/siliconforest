// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// A whole disk's GPT disk GUID. On a real Mac `diskutil info -plist disk0` has no DiskUUID for the whole
// disk (only partitions carry one: found on the M5, 25 Nov 2026), and IOMedia doesn't publish it either,
// so it is read from the GPT header itself: two blocks from the raw device, read-only, nothing else.
// The primary header is at LBA 1; its CRC, signature and own LBA are checked before the GUID is believed.

import Foundation
import SFEngine

public enum WholeDiskIdentity {
    /// diskutil's DiskUUID when it gives one for the whole disk (disk images and test doubles do), else
    /// the GPT header's disk GUID from `/dev/r<whole>` (root for an internal disk).
    public static func uuid(_ whole: String, info: [String: Any]) throws -> String {
        if let u = info["DiskUUID"] as? String, !u.isEmpty { return u.uppercased() }
        guard whole.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil else { throw SafetyRefusal("not a whole disk: \(whole)") }
        let bs = (info["DeviceBlockSize"] as? Int) ?? 512
        return try GPTHeader.diskGUID(device: "/dev/r\(whole)", blockSize: bs)
    }
}

public enum GPTHeader {
    public static func diskGUID(device: String, blockSize: Int) throws -> String {
        guard [512, 4096].contains(blockSize) else { throw SafetyRefusal("unexpected block size \(blockSize) on \(device)") }
        let fd = Darwin.open(device, O_RDONLY)
        guard fd >= 0 else {
            throw SafetyRefusal("can't read \(device)'s partition table (\(String(cString: strerror(errno))))\(geteuid() == 0 ? "" : "; this needs root")")
        }
        defer { close(fd) }
        var buf = [UInt8](repeating: 0, count: blockSize * 2)
        let n = buf.withUnsafeMutableBytes { pread(fd, $0.baseAddress, blockSize * 2, 0) }
        guard n == blockSize * 2 else { throw SafetyRefusal("short read of \(device)'s partition table") }
        return try guid(header: Array(buf[blockSize..<(blockSize * 2)]))
    }

    /// The disk GUID from a primary GPT header block (LBA 1).
    public static func guid(header h: [UInt8]) throws -> String {
        guard h.count >= 92, Array(h[0..<8]) == Array("EFI PART".utf8) else { throw SafetyRefusal("no GPT header at LBA 1") }
        func le32(_ o: Int) -> UInt32 { (0..<4).reduce(UInt32(0)) { $0 | UInt32(h[o + $1]) << (8 * UInt32($1)) } }
        func le64(_ o: Int) -> UInt64 { (0..<8).reduce(UInt64(0)) { $0 | UInt64(h[o + $1]) << (8 * UInt64($1)) } }
        let size = Int(le32(12))
        guard size >= 92, size <= h.count else { throw SafetyRefusal("the GPT header's size is wrong") }
        var c = Array(h[0..<size]); c[16] = 0; c[17] = 0; c[18] = 0; c[19] = 0
        guard crc32(c) == le32(16) else { throw SafetyRefusal("the GPT header's CRC doesn't match") }
        guard le64(24) == 1 else { throw SafetyRefusal("the GPT header isn't the primary one") }
        let g = Array(h[56..<72])
        // Mixed endian: the first three fields little-endian, the last two as stored.
        let b = [g[3], g[2], g[1], g[0], g[5], g[4], g[7], g[6]] + Array(g[8..<16])
        let hex = b.map { String(format: "%02X", $0) }.joined()
        let s = hex
        func part(_ a: Int, _ n: Int) -> Substring { s.dropFirst(a).prefix(n) }
        let u = "\(part(0, 8))-\(part(8, 4))-\(part(12, 4))-\(part(16, 4))-\(part(20, 12))"
        guard u != "00000000-0000-0000-0000-000000000000", UUID(uuidString: u) != nil else { throw SafetyRefusal("the GPT disk GUID is empty") }
        return u
    }

    static func crc32(_ d: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for byte in d {
            c ^= UInt32(byte)
            for _ in 0..<8 { c = (c >> 1) ^ (0xEDB8_8320 & (0 &- (c & 1))) }
        }
        return ~c
    }
}
