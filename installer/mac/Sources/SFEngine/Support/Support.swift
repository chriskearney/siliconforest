import Foundation
import CommonCrypto

/// SHA-256 through CommonCrypto (DESIGN §7.3 keeps CryptoKit out of anything recoveryOS might run).
public struct SHA256Hasher {
    private var ctx = CC_SHA256_CTX()
    public init() { CC_SHA256_Init(&ctx) }
    public mutating func update(_ data: Data) {
        data.withUnsafeBytes { raw in _ = CC_SHA256_Update(&ctx, raw.baseAddress, CC_LONG(raw.count)) }
    }
    public mutating func update(_ bytes: UnsafeRawBufferPointer) { _ = CC_SHA256_Update(&ctx, bytes.baseAddress, CC_LONG(bytes.count)) }
    public mutating func finalize() -> String {
        var out = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&out, &ctx)
        return out.map { String(format: "%02x", $0) }.joined()
    }
    public static func hex(_ data: Data) -> String { var h = SHA256Hasher(); h.update(data); return h.finalize() }
    public static func hex(_ string: String) -> String { hex(Data(string.utf8)) }
    public static func file(_ url: URL, limit: Int64? = nil) throws -> String {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        return try stream(h, limit: limit)
    }
    /// Hashes `limit` bytes (or to EOF) from a handle in 1 MiB reads.
    public static func stream(_ h: FileHandle, limit: Int64? = nil) throws -> String {
        var hasher = SHA256Hasher()
        var left = limit ?? Int64.max
        while left > 0 {
            let chunk = try h.read(upToCount: Int(min(left, 1 << 20))) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(chunk)
            left -= Int64(chunk.count)
        }
        return hasher.finalize()
    }
}

/// Canonical JSON: sorted keys, no escaped slashes, ISO-8601 dates. Digests are taken over this.
public enum Canonical {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
    public static func data<T: Encodable>(_ v: T) throws -> Data { try encoder().encode(v) }
    public static func digest<T: Encodable>(_ v: T) throws -> String { SHA256Hasher.hex(try data(v)) }
}

/// The engine's error taxonomy (ENGINE.md §13). Every failure maps to one class with a way out.
public enum EngineErrorClass: String, Codable, Sendable {
    case blocked, transient, userFixable = "user-fixable", appleTool = "apple-tool", inconsistent, bootFailed = "boot-failed", internalError = "internal"
}

public struct EngineError: Error, LocalizedError, Equatable, Sendable, Codable {
    public var errorClass: EngineErrorClass
    public var message: String
    /// The real tool output or code, when an Apple tool failed.
    public var detail: String?
    public init(_ c: EngineErrorClass, _ message: String, detail: String? = nil) {
        errorClass = c; self.message = message; self.detail = detail
    }
    public var errorDescription: String? { detail.map { "\(message) (\($0))" } ?? message }
}

/// Refusals by the safety chokepoint. Never retried, never downgraded to a warning.
public struct SafetyRefusal: Error, LocalizedError, Equatable, Sendable {
    public var reason: String
    public init(_ reason: String) { self.reason = reason }
    public var errorDescription: String? { "Refused: \(reason)" }
}

/// An operation that, on a disk image, would need root (or a real Mac) and therefore Chris's approval.
/// The engine records it and simulates the step instead of working around it.
public struct ApprovalNeeded: Codable, Sendable, Hashable {
    public var step: String
    public var command: [String]
    public var reason: String
    public init(step: String, command: [String], reason: String) { self.step = step; self.command = command; self.reason = reason }
}

enum Clock {
    static func now() -> Date { Date() }
    static func stamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }
}

extension FileManager {
    func ensureDirectory(_ url: URL) throws {
        try createDirectory(at: url, withIntermediateDirectories: true)
    }
}
