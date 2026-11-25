// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors

import Foundation

/// CRC-32 (IEEE 802.3, the zip checksum), slicing-by-8. Our own code.
public struct CRC32: Sendable {
    public private(set) var value: UInt32 = 0

    public init() {}

    /// Eight 256-entry tables, flat: entry `k * 256 + i` is table k.
    static let table: [UInt32] = {
        var t = [UInt32](repeating: 0, count: 8 * 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
            t[i] = c
        }
        for k in 1..<8 {
            for i in 0..<256 {
                let prev: UInt32 = t[(k - 1) * 256 + i]
                t[k * 256 + i] = (prev >> 8) ^ t[Int(prev & 0xFF)]
            }
        }
        return t
    }()

    public mutating func update(_ buf: UnsafeRawBufferPointer) {
        guard var q = buf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
        var c: UInt32 = ~value
        var n = buf.count
        Self.table.withUnsafeBufferPointer { t in
            // Small steps with explicit types: one long XOR chain times out the type checker on some toolchains.
            @inline(__always) func at(_ k: Int, _ x: UInt32) -> UInt32 { t[k &* 256 &+ Int(x & 0xFF)] }
            while n >= 8 {
                var a: UInt32 = UInt32(q[0])
                a |= UInt32(q[1]) << 8
                a |= UInt32(q[2]) << 16
                a |= UInt32(q[3]) << 24
                a ^= c
                var b: UInt32 = UInt32(q[4])
                b |= UInt32(q[5]) << 8
                b |= UInt32(q[6]) << 16
                b |= UInt32(q[7]) << 24
                var r: UInt32 = at(7, a)
                r ^= at(6, a >> 8)
                r ^= at(5, a >> 16)
                r ^= at(4, a >> 24)
                r ^= at(3, b)
                r ^= at(2, b >> 8)
                r ^= at(1, b >> 16)
                r ^= at(0, b >> 24)
                c = r
                q += 8; n -= 8
            }
            while n > 0 { c = at(0, c ^ UInt32(q[0])) ^ (c >> 8); q += 1; n -= 1 }
        }
        value = ~c
    }

    public mutating func update<D: ContiguousBytes>(_ data: D) { data.withUnsafeBytes { update($0) } }

    public static func checksum<D: ContiguousBytes>(_ data: D) -> UInt32 { var c = CRC32(); c.update(data); return c.value }
}
