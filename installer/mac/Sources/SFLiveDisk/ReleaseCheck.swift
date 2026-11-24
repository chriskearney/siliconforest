import Foundation
import Compression
import SFEngine
import SFInstallKit

/// Verification of the release against its manifest, done by the live backend itself before it writes
/// a single byte to the disk. The engine's S15 does the same; this is the second, independent check
/// (the helper trusts nothing the app or an earlier step says about the files).
public enum ReleaseCheck {
    public struct Refusal: Error, LocalizedError, Equatable, Sendable {
        public var reason: String
        public var errorDescription: String? { "Refused: \(reason)" }
    }

    /// Every artifact in `dir` must exist with exactly the manifest's size and SHA-256.
    public static func verifyArtifacts(_ m: ReleaseManifest, in dir: URL) throws {
        for a in m.artifacts {
            let url = dir.appendingPathComponent(a.name)
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            guard let size = attrs?[.size] as? Int64 ?? (attrs?[.size] as? NSNumber)?.int64Value else {
                throw Refusal(reason: "release file \(a.name) is missing")
            }
            guard size == a.bytes else { throw Refusal(reason: "release file \(a.name) is \(size) B, the manifest says \(a.bytes)") }
            guard try SHA256Hasher.file(url) == a.sha256 else { throw Refusal(reason: "release file \(a.name) doesn't match its manifest hash") }
        }
    }

    /// The root image: the file as shipped must match its artifact entry, and what it decompresses to
    /// must have exactly the manifest's length and SHA-256. Reads everything, writes nothing.
    public static func verifyRootImage(_ m: ReleaseManifest, source: URL) throws {
        guard source.lastPathComponent == m.rootImage else { throw Refusal(reason: "\(source.lastPathComponent) is not the release's root image (\(m.rootImage))") }
        guard let art = m.artifact(m.rootImage) else { throw Refusal(reason: "the manifest has no entry for \(m.rootImage)") }
        guard try SHA256Hasher.file(source) == art.sha256 else { throw Refusal(reason: "the root image file doesn't match its manifest hash") }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        var hasher = SHA256Hasher()
        var total: Int64 = 0
        if m.rootImageCompressed {
            let filter = try InputFilter(.decompress, using: .lzma, bufferCapacity: 1 << 20) { (n: Int) -> Data? in
                let d = try input.read(upToCount: n)
                return (d?.isEmpty ?? true) ? nil : d
            }
            while let d = try filter.readData(ofLength: 1 << 20), !d.isEmpty { hasher.update(d); total += Int64(d.count) }
        } else {
            while let d = try input.read(upToCount: 1 << 20), !d.isEmpty { hasher.update(d); total += Int64(d.count) }
        }
        guard total == m.rootImageBytes else { throw Refusal(reason: "the root image is \(total) B decompressed, the manifest says \(m.rootImageBytes)") }
        guard hasher.finalize() == m.rootImageSHA256 else { throw Refusal(reason: "the decompressed root image doesn't match its manifest hash") }
    }
}
