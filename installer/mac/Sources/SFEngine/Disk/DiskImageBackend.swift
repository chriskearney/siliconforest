import Foundation
import Compression

/// The engine's acting half on disk images: every verb resolves partition UUIDs on a fresh read,
/// then runs real `diskutil`/`newfs_msdos` or raw I/O through the chokepoint. Nothing here can reach
/// a device that `ImageGuard` hasn't just proved is one of our images.
public final class DiskImageBackend: @unchecked Sendable {
    public let chokepoint: ImageChokepoint
    public var query: ToolRunner { chokepoint.imageGuard.query }
    /// The image file this backend works on. Its whole disk is looked up on every call, because
    /// diskN numbers change after a detach and reattach (power loss).
    public let imagePath: String

    public init(imagePath: URL, chokepoint: ImageChokepoint) {
        self.imagePath = ImageGuard.resolve(imagePath.path)
        self.chokepoint = chokepoint
    }

    public convenience init(imagePath: URL, allowedRoot: URL = ImageGuard.defaultRoot, runner: ToolRunner = ProcessToolRunner(),
                            query: ToolRunner = ProcessToolRunner()) {
        self.init(imagePath: imagePath, chokepoint: ImageChokepoint(imageGuard: ImageGuard(allowedRoot: allowedRoot, query: query), runner: runner))
    }

    // MARK: identity

    /// The whole disk the image is attached as right now, proved by the guard.
    public func wholeDisk() throws -> String {
        let imgs = try chokepoint.imageGuard.attachedImages()
        guard let img = imgs.first(where: { ImageGuard.resolve($0.imagePath) == imagePath }) else {
            throw EngineError(.inconsistent, "the disk image is not attached", detail: imagePath)
        }
        guard let whole = img.partitionMapDisk else { throw EngineError(.inconsistent, "the image has no partition map") }
        let proof = try chokepoint.imageGuard.authorize(whole)
        return proof.imageWholeDisk
    }

    public func isAttached() -> Bool { (try? wholeDisk()) != nil }

    private let cacheLock = NSLock()
    private var cached: (generation: Int, at: Date, topology: ImageTopology)?
    /// How long a read stays good when nothing has gone through the chokepoint since.
    public var topologyTTL: TimeInterval = 2

    /// The partition table now. Reused only within one chokepoint generation and for `topologyTTL`
    /// seconds, so every check after a change reads the disk afresh.
    public func topology() throws -> ImageTopology {
        let gen = chokepoint.generation
        cacheLock.lock()
        if let c = cached, c.generation == gen, Date().timeIntervalSince(c.at) < topologyTTL { cacheLock.unlock(); return c.topology }
        cacheLock.unlock()
        let t = try TopologyReader.read(try wholeDisk(), query: query)
        cacheLock.lock(); cached = (gen, Date(), t); cacheLock.unlock()
        return t
    }

    /// Always reads the disk (verification after a change).
    public func freshTopology() throws -> ImageTopology {
        chokepoint.invalidate()
        return try topology()
    }

    public func limits(store uuid: String) throws -> TopologyReader.ResizeLimits {
        try TopologyReader.limits(try identifier(uuid), query: query)
    }

    public func identifier(_ uuid: String) throws -> String {
        guard let p = try topology().partition(uuid: uuid) else { throw EngineError(.inconsistent, "partition \(uuid) not found") }
        return p.identifier
    }

    // MARK: verbs (each through the chokepoint)

    @discardableResult
    func diskutil(_ args: [String], stdin: Data? = nil) throws -> ToolResult {
        let r = try chokepoint.run(["/usr/sbin/diskutil"] + args, stdin: stdin)
        guard r.ok else {
            throw EngineError(.appleTool, "diskutil \(args.prefix(2).joined(separator: " ")) failed",
                              detail: (r.err + r.out).trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").suffix(3).joined(separator: " / "))
        }
        return r
    }

    /// Adds a partition directly after `after` and returns the new partition's UUID.
    public func addPartition(after uuid: String, content: String, label: String, bytes: Int64) throws -> String {
        let before = try topology()
        guard let prev = before.partition(uuid: uuid) else { throw EngineError(.inconsistent, "partition \(uuid) not found") }
        let fs: [String]
        switch content {
        case "Apple_APFS": fs = ["APFS", label]
        case "EFI": fs = ["%C12A7328-F81F-11D2-BA4B-00A0C93EC93B%", "%noformat%"]
        default: fs = ["%0FC63DAF-8483-4772-8E79-3D69D8477DE4%", "%noformat%"]
        }
        try diskutil(["addPartition", prev.identifier] + fs + ["\(bytes)B"])
        let after = try topology()
        let old = Set(before.partitions.map(\.uuid))
        guard let new = after.partitions.first(where: { !old.contains($0.uuid) && $0.offset == prev.end }) else {
            throw EngineError(.inconsistent, "the new partition isn't where diskutil was asked to put it")
        }
        return new.uuid
    }

    public func formatFAT32(_ uuid: String, label: String) throws {
        let id = try identifier(uuid)
        let r = try chokepoint.run(["/sbin/newfs_msdos", "-F", "32", "-v", label, "/dev/r\(id)"])
        guard r.ok else { throw EngineError(.appleTool, "newfs_msdos failed", detail: r.err.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    public func addVolume(container storeUUID: String, name: String, role: String) throws {
        guard let ref = try topology().partition(uuid: storeUUID)?.apfs?.reference else { throw EngineError(.inconsistent, "no APFS container on \(storeUUID)") }
        try diskutil(["apfs", "addVolume", ref, "APFS", name, "-role", role, "-nomount"])
    }

    /// Mounts without showing the volume in Finder or on the desktop.
    public func mount(_ device: String) throws { try diskutil(["mount", "nobrowse", device]) }

    /// The mount point of the volume with `role` (or the only volume) in a container, mounting it if needed.
    public func volumeURL(store uuid: String, role: String? = nil) throws -> URL {
        guard let apfs = try topology().partition(uuid: uuid)?.apfs else { throw EngineError(.inconsistent, "no APFS container on \(uuid)") }
        guard let v = apfs.volumes.first(where: { role == nil ? true : $0.roles.contains(role!) }) ?? (role == nil ? nil : apfs.volumes.first(where: { $0.roles.isEmpty })) else {
            throw EngineError(.inconsistent, "no \(role ?? "") volume in \(apfs.reference)")
        }
        if (try? chokepoint.mountPoint(of: v.identifier)) == nil { try mount(v.identifier) }
        return try chokepoint.mountPoint(of: v.identifier)
    }

    /// The mount point of a FAT partition, mounting it if needed.
    public func fatURL(_ uuid: String) throws -> URL {
        let id = try identifier(uuid)
        if (try? chokepoint.mountPoint(of: id)) == nil { try mount(id) }
        return try chokepoint.mountPoint(of: id)
    }

    public func deleteContainer(_ uuid: String) throws {
        let id = try identifier(uuid)
        try diskutil(["apfs", "deleteContainer", id])
    }

    public func eraseToFree(_ uuid: String) throws {
        let id = try identifier(uuid)
        try diskutil(["eraseVolume", "free", "none", id])
    }

    // MARK: raw I/O

    /// Streams `source` (LZMA/xz-decoded when `compressed`) to the partition's raw device from offset
    /// 0, and returns the SHA-256 of the bytes written. Partial writes are never trusted: callers
    /// verify with a full read-back.
    public func writeImage(_ uuid: String, source: URL, compressed: Bool, progress: ((Int64) -> Void)? = nil) throws -> (bytes: Int64, sha256: String) {
        let id = try identifier(uuid)
        let out = try chokepoint.openRaw(id, write: true)
        defer { try? out.close() }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        var hasher = SHA256Hasher()
        var written: Int64 = 0
        // Raw devices take whole blocks: buffer to 1 MiB and pad the final block with zeros.
        var pending = Data()
        func flush(final: Bool) throws {
            let block = 4096
            while pending.count >= (1 << 20) || (final && !pending.isEmpty) {
                var chunk = pending.prefix(1 << 20)
                pending.removeFirst(chunk.count)
                if chunk.count % block != 0 { chunk.append(Data(count: block - chunk.count % block)) }
                try out.write(contentsOf: chunk)
            }
        }
        func feed(_ d: Data) throws {
            hasher.update(d); written += Int64(d.count); pending.append(d)
            try flush(final: false); progress?(written)
        }
        if compressed {
            let filter = try InputFilter(.decompress, using: .lzma, bufferCapacity: 1 << 20) { (n: Int) -> Data? in
                let d = try input.read(upToCount: n)
                return (d?.isEmpty ?? true) ? nil : d
            }
            while let d = try filter.readData(ofLength: 1 << 20), !d.isEmpty { try feed(d) }
        } else {
            while let d = try input.read(upToCount: 1 << 20), !d.isEmpty { try feed(d) }
        }
        try flush(final: true)
        try out.synchronize()
        return (written, hasher.finalize())
    }

    public func hashRaw(_ uuid: String, bytes: Int64) throws -> String {
        let h = try chokepoint.openRaw(try identifier(uuid), write: false)
        defer { try? h.close() }
        return try SHA256Hasher.stream(h, limit: bytes)
    }

    /// Raw devices read whole blocks only: reads the covering blocks and returns the slice asked for.
    public func readRaw(_ uuid: String, offset: Int64, count: Int) throws -> Data {
        let h = try chokepoint.openRaw(try identifier(uuid), write: false)
        defer { try? h.close() }
        let start = offset / 4096 * 4096
        let end = (offset + Int64(count) + 4095) / 4096 * 4096
        try h.seek(toOffset: UInt64(start))
        let d = try h.read(upToCount: Int(end - start)) ?? Data()
        let lo = Int(offset - start)
        return d.count >= lo + count ? d.subdata(in: lo..<(lo + count)) : Data()
    }

    /// Writes whole blocks at a block-aligned offset inside a partition.
    public func writeRaw(_ uuid: String, offset: Int64, data: Data) throws {
        precondition(offset % 4096 == 0)
        let h = try chokepoint.openRaw(try identifier(uuid), write: true)
        defer { try? h.close() }
        var d = data
        if d.count % 4096 != 0 { d.append(Data(count: 4096 - d.count % 4096)) }
        try h.seek(toOffset: UInt64(offset))
        try h.write(contentsOf: d)
        try h.synchronize()
    }

    // MARK: attach / detach (power-loss simulation and cleanup)

    /// Forced detach: what a power cut looks like from the engine's side.
    public func detach(force: Bool = true) throws {
        let w = try wholeDisk()
        let r = try chokepoint.run(["/usr/bin/hdiutil", "detach", w] + (force ? ["-force"] : []))
        guard r.ok else { throw EngineError(.appleTool, "hdiutil detach failed", detail: r.err) }
    }

    /// Attaches the image (never mounting automatically, never shown in Finder).
    public func attach() throws {
        guard chokepoint.imageGuard.isUnderAllowedRoot(imagePath) else { throw SafetyRefusal("image outside the allowed directory") }
        chokepoint.invalidate()
        defer { chokepoint.invalidate() }
        let r = try ProcessToolRunner().run(["/usr/bin/hdiutil", "attach", "-nomount", "-nobrowse", "-noverify", "-noautofsck", imagePath])
        guard r.ok else { throw EngineError(.appleTool, "hdiutil attach failed", detail: r.err) }
    }
}
