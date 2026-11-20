//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// swift-foundation swift-6.3.1-RELEASE, c20150400269a6afffe5b3a9f9fa8bbd51d69e1a.
// SiliconForest: scoped UUID value/API; use libSystem UUID functions directly.
// Optional Codable/reflection/comparison/random-generator and NSUUID wrappers
// are outside this slice. Reject noncanonical C-string input before parsing.
import SFUUIDRuntime

public typealias uuid_t = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
public typealias uuid_string_t = (Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8)

/// Represents UUID strings, which can be used to uniquely identify types, interfaces, and other items.
@available(macOS 10.8, iOS 6.0, tvOS 9.0, watchOS 2.0, *)
public struct UUID : Hashable, Equatable, CustomStringConvertible, Sendable {
    public private(set) var uuid: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

    /* Create a new UUID with RFC 4122 version 4 random bytes */
    public init() {
        withUnsafeMutablePointer(to: &uuid) {
            $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<uuid_t>.size) {
                uuid_generate_random($0)
            }
        }
    }

    @inline(__always)
    internal func withUUIDBytes<R>(_ work: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R {
        return try withExtendedLifetime(self) {
            try withUnsafeBytes(of: uuid) { rawBuffer in
                return try rawBuffer.withMemoryRebound(to: UInt8.self) { buffer in
                    return try work(buffer)
                }
            }
        }
    }

    /// Create a UUID from a string such as "E621E1F8-C36C-495A-93FC-0C247A3E6E5F".
    ///
    /// Returns nil for invalid strings.
    public init?(uuidString string: __shared String) {
        guard string.utf8.count == 36 && string.utf8.allSatisfy({ $0 > 0 && $0 < 128 }) else {
            return nil
        }
        let res = withUnsafeMutablePointer(to: &uuid) {
            $0.withMemoryRebound(to: UInt8.self, capacity: 16) { bytes in
                string.withCString { uuid_parse($0, bytes) }
            }
        }
        if res != 0 {
            return nil
        }
    }

    /// Create a UUID from a `uuid_t`.
    public init(uuid: uuid_t) {
        self.uuid = uuid
    }

    /// Returns a string created from the UUID, such as "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
    public var uuidString: String {
        var bytes: uuid_string_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        return withUUIDBytes { valBuffer in
            withUnsafeMutablePointer(to: &bytes) { strPtr in
                strPtr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<uuid_string_t>.size) { str in
                    uuid_unparse_upper(valBuffer.baseAddress!, str)
                    return String(cString: str)
                }
            }
        }
    }

    public func hash(into hasher: inout Hasher) {
        withUnsafeBytes(of: uuid) { buffer in
            hasher.combine(bytes: buffer)
        }
    }

    public var description: String {
        return uuidString
    }

    public var debugDescription: String {
        return description
    }

    public static func ==(lhs: UUID, rhs: UUID) -> Bool {
        withUnsafeBytes(of: lhs) { lhsPtr in
            withUnsafeBytes(of: rhs) { rhsPtr in
                let lhsTuple = lhsPtr.loadUnaligned(as: (UInt64, UInt64).self)
                let rhsTuple = rhsPtr.loadUnaligned(as: (UInt64, UInt64).self)
                return (lhsTuple.0 ^ rhsTuple.0) | (lhsTuple.1 ^ rhsTuple.1) == 0
            }
        }
    }
}
