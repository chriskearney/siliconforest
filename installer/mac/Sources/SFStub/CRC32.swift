// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors

import Foundation

/// CRC-32 (IEEE 802.3, the zip checksum), slicing-by-8. Our own code.
public struct CRC32: Sendable {
    public private(set) var value: UInt32 = 0

    public init() {}

    static let tables: [[UInt32]] = {
        var t = [[UInt32]](repeating: [UInt32](repeating: 0, count: 256), count: 8)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
            t[0][i] = c
        }
        for i in 0..<256 {
            for k in 1..<8 { t[k][i] = (t[k - 1][i] >> 8) ^ t[0][Int(t[k - 1][i] & 0xFF)] }
        }
        return t
    }()

    public mutating func update(_ buf: UnsafeRawBufferPointer) {
        var c = ~value
        let t = Self.tables
        var n = buf.count
        guard var q = buf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
        t[0].withUnsafeBufferPointer { t0 in t[1].withUnsafeBufferPointer { t1 in t[2].withUnsafeBufferPointer { t2 in
        t[3].withUnsafeBufferPointer { t3 in t[4].withUnsafeBufferPointer { t4 in t[5].withUnsafeBufferPointer { t5 in
        t[6].withUnsafeBufferPointer { t6 in t[7].withUnsafeBufferPointer { t7 in
            while n >= 8 {
                let a = c ^ (UInt32(q[0]) | UInt32(q[1]) << 8 | UInt32(q[2]) << 16 | UInt32(q[3]) << 24)
                let b = UInt32(q[4]) | UInt32(q[5]) << 8 | UInt32(q[6]) << 16 | UInt32(q[7]) << 24
                c = t7[Int(a & 0xFF)] ^ t6[Int((a >> 8) & 0xFF)] ^ t5[Int((a >> 16) & 0xFF)] ^ t4[Int(a >> 24)]
                  ^ t3[Int(b & 0xFF)] ^ t2[Int((b >> 8) & 0xFF)] ^ t1[Int((b >> 16) & 0xFF)] ^ t0[Int(b >> 24)]
                q += 8; n -= 8
            }
            while n > 0 { c = t0[Int((c ^ UInt32(q[0])) & 0xFF)] ^ (c >> 8); q += 1; n -= 1 }
        }}}}}}}}
        value = ~c
    }

    public mutating func update<D: ContiguousBytes>(_ data: D) { data.withUnsafeBytes { update($0) } }

    public static func checksum<D: ContiguousBytes>(_ data: D) -> UInt32 { var c = CRC32(); c.update(data); return c.value }
}
