import Foundation
import Compression
import SFEngine
import SFInstallKit

/// Faults the tests inject into the live backend itself. Every one is off by default and none can be
/// switched on from outside the process.
public struct LiveFaults: Sendable {
    /// The raw image write fails after this many bytes (an I/O error or a cut that leaves a partial).
    public var shortWriteAfter: Int64?
    /// One bit of the written stream is flipped at this offset (a bad write the read-back must catch).
    public var flipBitAtByte: Int64?
    /// Runs after the release is verified and before the final pre-write check of the root image.
    public var tamperBeforeWrite: (@Sendable (URL) -> Void)?
    public init(shortWriteAfter: Int64? = nil, flipBitAtByte: Int64? = nil, tamperBeforeWrite: (@Sendable (URL) -> Void)? = nil) {
        self.shortWriteAfter = shortWriteAfter; self.flipBitAtByte = flipBitAtByte; self.tamperBeforeWrite = tamperBeforeWrite
    }
}

/// The engine's backend for a disk the helper may really write to (ENGINE §12). It runs the same
/// typed verbs as `DiskImageBackend`, and the same engine drives both, but every one passes three
/// independent checks before anything is written:
///
///  1. the **target authority** proves the device belongs to the one disk of this job (a disk image
///     in tests; the internal disk, by GPT UUID, only in a build with `SF_REAL_DISK_WRITES` and with
///     a valid runtime authorization);
///  2. the **protection receipt**, derived from the approved plan and the partition table the journal
///     saved, refuses anything but the planned macOS resize and partitions inside the freed span, so the
///     Linux stub, ESP and root (and Apple's own partitions) cannot be named;
///  3. the engine's own **gate**, as before.
///
/// Before its first write it verifies every release file against the manifest, and immediately before
/// streaming the root image it verifies that image (and what it decompresses to) again. After every
/// change it re-reads the table and the content of protected partitions; on any difference it trips
/// and refuses everything else.
public final class LiveDiskBackend: EngineBackend, @unchecked Sendable {
    public let authority: TargetAuthority
    public let chokepoint: LiveChokepoint
    public var faults = LiveFaults()
    public var targetLabel: String { authority.label }
    public var query: ToolRunner { authority.query }

    private let lock = NSLock()
    private var armed: ProtectionReceipt?
    private var heads: [String: String] = [:]
    private var expected: (manifest: ReleaseManifest, dir: URL)?
    private var verifiedRelease: String?
    private var cached: (generation: Int, at: Date, topology: ImageTopology)?
    public var topologyTTL: TimeInterval = 2
    /// How much of each protected Linux partition is hashed to prove it was never written (1 MiB).
    public static let headBytes = 1 << 20

    public init(authority: TargetAuthority, runner: ToolRunner = ProcessToolRunner()) {
        self.authority = authority
        let holder = ReceiptHolder()
        self.holder = holder
        self.chokepoint = LiveChokepoint(authority: authority, runner: runner, receipt: { try holder.get() })
    }

    final class ReceiptHolder: @unchecked Sendable {
        private let lock = NSLock()
        private var value: ProtectionReceipt?
        func set(_ r: ProtectionReceipt) { lock.lock(); value = r; lock.unlock() }
        func get() throws -> ProtectionReceipt {
            lock.lock(); defer { lock.unlock() }
            guard let value else { throw SafetyRefusal("protection receipt: this backend hasn't been armed with an approved plan") }
            return value
        }
    }
    private let holder: ReceiptHolder

    public var receipt: ProtectionReceipt? { lock.lock(); defer { lock.unlock() }; return armed }

    // MARK: arming

    public func arm(plan: EnginePlan, original: ImageTopology) throws {
        let r = try ProtectionReceipt.derive(plan: plan, original: original)
        lock.lock()
        if let a = armed, a.planDigest != r.planDigest { lock.unlock(); throw SafetyRefusal("protection receipt: this backend is armed for another plan") }
        let already = armed != nil
        armed = r
        lock.unlock()
        holder.set(r)
        if already { return }
        // The disk must be the disk the journal saw, and everything protected must be where it was.
        try authority.authorize(try authority.wholeDisk())
        let now = try chokepoint.readTopology()
        if let v = r.violation(in: now) {
            chokepoint.trip(v)
            throw EngineError(.inconsistent, "The disk isn't the one this job started on", detail: v)
        }
        try sealHeads(r, now)
    }

    private func sealHeads(_ r: ProtectionReceipt, _ t: ImageTopology) throws {
        var h: [String: String] = [:]
        for e in r.protected where e.kind == .linuxRoot || e.kind == .other {
            guard let p = t.partition(uuid: e.uuid) else { continue }
            h[e.uuid] = try headHash(p)
        }
        lock.lock(); heads = h; lock.unlock()
    }

    private func headHash(_ p: ImagePartition) throws -> String {
        let fh = try chokepoint.openRaw(p.identifier, write: false)
        defer { try? fh.close() }
        return try SHA256Hasher.stream(fh, limit: Int64(min(p.size, Int64(Self.headBytes))))
    }

    /// Re-reads the disk and refuses everything from now on if any protected partition changed.
    @discardableResult
    func verifyProtected(content: Bool, _ t: ImageTopology? = nil) throws -> ImageTopology {
        let r = try holder.get()
        let now = try t ?? chokepoint.readTopology()
        if let v = r.violation(in: now) {
            chokepoint.trip(v)
            throw EngineError(.inconsistent, "A protected partition changed: stopping", detail: v)
        }
        if content {
            lock.lock(); let expectedHeads = heads; lock.unlock()
            for (uuid, want) in expectedHeads {
                guard let p = now.partition(uuid: uuid) else { continue }
                if try headHash(p) != want {
                    let why = "the start of protected partition \(uuid.prefix(8))… changed"
                    chokepoint.trip(why)
                    throw EngineError(.inconsistent, "A protected partition changed: stopping", detail: why)
                }
            }
        }
        return now
    }

    public func expectRelease(_ release: ReleaseManifest?, in directory: URL) {
        lock.lock(); expected = release.map { ($0, directory) }; lock.unlock()
    }

    /// Verifies every release file against the manifest, once per release, before the first write.
    func ensureReleaseVerified() throws {
        lock.lock(); let e = expected; let done = verifiedRelease; lock.unlock()
        guard let e else { throw SafetyRefusal("no release was given to this backend: nothing is written without verifying it first") }
        if done == e.manifest.digest { return }
        do { try ReleaseCheck.verifyArtifacts(e.manifest, in: e.dir) } catch let r as ReleaseCheck.Refusal { throw SafetyRefusal(r.reason) }
        lock.lock(); verifiedRelease = e.manifest.digest; lock.unlock()
    }

    // MARK: reads

    public func wholeDisk() throws -> String { try authority.wholeDisk() }
    public func isAttached() -> Bool { (try? wholeDisk()) != nil }

    public func topology() throws -> ImageTopology {
        let gen = chokepoint.generation
        lock.lock()
        if let c = cached, c.generation == gen, Date().timeIntervalSince(c.at) < topologyTTL { lock.unlock(); return c.topology }
        lock.unlock()
        let t = try chokepoint.readTopology()
        lock.lock(); cached = (gen, Date(), t); lock.unlock()
        return t
    }

    public func freshTopology() throws -> ImageTopology {
        chokepoint.invalidate()
        let t = try topology()
        if holderReceipt() != nil { try verifyProtected(content: true, t) }
        return t
    }

    public func limits(store uuid: String) throws -> TopologyReader.ResizeLimits {
        try TopologyReader.limits(try identifier(uuid), query: query)
    }

    public func identifier(_ uuid: String) throws -> String {
        guard let p = try topology().partition(uuid: uuid) else { throw EngineError(.inconsistent, "partition \(uuid) not found") }
        try authority.authorize(p.identifier)
        return p.identifier
    }

    // MARK: verbs

    @discardableResult
    func mutate(_ args: [String], needsRelease: Bool = false, stdin: Data? = nil, tool: String = "/usr/sbin/diskutil") throws -> ToolResult {
        if needsRelease { try ensureReleaseVerified() }
        let r = try chokepoint.run([tool] + args, stdin: stdin)
        guard r.ok else {
            throw EngineError(.appleTool, "\(URL(fileURLWithPath: tool).lastPathComponent) \(args.prefix(2).joined(separator: " ")) failed",
                              detail: (r.err + r.out).trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").suffix(3).joined(separator: " / "))
        }
        try verifyProtected(content: true)
        return r
    }

    public func authorizeResize(_ argv: [String]) throws {
        guard let r = holderReceipt() else { throw SafetyRefusal("protection receipt: this backend hasn't been armed with an approved plan") }
        let m = try chokepoint.authorize(argv)
        if case .resize(_, .bytes(let n)) = m, n == r.macOSTo, n != r.macOSFrom { try ensureReleaseVerified() }   // shrinking: the release comes first
        chokepoint.invalidate()
    }

    private func holderReceipt() -> ProtectionReceipt? { try? holder.get() }

    public func addPartition(after uuid: String, content: String, label: String, bytes: Int64) throws -> String {
        let before = try topology()
        guard let prev = before.partition(uuid: uuid) else { throw EngineError(.inconsistent, "partition \(uuid) not found") }
        let fs: [String]
        switch content {
        case "Apple_APFS": fs = ["APFS", label]
        case "EFI": fs = ["%\(LiveMutation.efiGUID)%", "%noformat%"]
        default: fs = ["%\(LiveMutation.linuxGUID)%", "%noformat%"]
        }
        try mutate(["addPartition", prev.identifier] + fs + ["\(bytes)B"], needsRelease: true)
        let after = try topology()
        let old = Set(before.partitions.map(\.uuid))
        guard let new = after.partitions.first(where: { !old.contains($0.uuid) && $0.offset == prev.end }) else {
            throw EngineError(.inconsistent, "the new partition isn't where diskutil was asked to put it")
        }
        return new.uuid
    }

    public func formatFAT32(_ uuid: String, label: String) throws {
        let id = try identifier(uuid)
        try mutate(["-F", "32", "-v", label, "/dev/r\(id)"], needsRelease: true, tool: "/sbin/newfs_msdos")
    }

    public func addVolume(container storeUUID: String, name: String, role: String) throws {
        guard let ref = try topology().partition(uuid: storeUUID)?.apfs?.reference else { throw EngineError(.inconsistent, "no APFS container on \(storeUUID)") }
        try mutate(["apfs", "addVolume", ref, "APFS", name, "-role", role, "-nomount"], needsRelease: true)
    }

    func mount(_ device: String) throws { try mutate(["mount", "nobrowse", device]) }

    public func volumeURL(store uuid: String, role: String?) throws -> URL {
        guard let apfs = try topology().partition(uuid: uuid)?.apfs else { throw EngineError(.inconsistent, "no APFS container on \(uuid)") }
        guard let v = apfs.volumes.first(where: { role == nil ? true : $0.roles.contains(role!) }) ?? (role == nil ? nil : apfs.volumes.first(where: { $0.roles.isEmpty })) else {
            throw EngineError(.inconsistent, "no \(role ?? "") volume in \(apfs.reference)")
        }
        if (try? chokepoint.mountPoint(of: v.identifier)) == nil { try mount(v.identifier) }
        return try chokepoint.mountPoint(of: v.identifier)
    }

    public func fatURL(_ uuid: String) throws -> URL {
        let id = try identifier(uuid)
        if (try? chokepoint.mountPoint(of: id)) == nil { try mount(id) }
        return try chokepoint.mountPoint(of: id)
    }

    public func deleteContainer(_ uuid: String) throws { try mutate(["apfs", "deleteContainer", try identifier(uuid)]) }
    public func eraseToFree(_ uuid: String) throws { try mutate(["eraseVolume", "free", "none", try identifier(uuid)]) }

    // MARK: raw I/O

    /// Streams the release's root image to the partition. Before opening the device it verifies the
    /// file against the manifest (as shipped, and decompressed) and that it fits; the stream's own hash
    /// is returned for the caller to compare, and the engine reads everything back afterwards.
    public func writeImage(_ uuid: String, source: URL, compressed: Bool, progress: ((Int64) -> Void)? = nil) throws -> (bytes: Int64, sha256: String) {
        try ensureReleaseVerified()
        lock.lock(); let e = expected; lock.unlock()
        guard let e else { throw SafetyRefusal("no release was given to this backend") }
        let dir = e.dir.standardizedFileURL.path
        guard source.standardizedFileURL.path.hasPrefix(dir + "/") else { throw SafetyRefusal("the root image isn't inside the verified release directory") }
        guard compressed == e.manifest.rootImageCompressed else { throw SafetyRefusal("the root image's compression differs from the manifest's") }
        faults.tamperBeforeWrite?(source)
        do { try ReleaseCheck.verifyRootImage(e.manifest, source: source) } catch let r as ReleaseCheck.Refusal { throw SafetyRefusal(r.reason) }
        let id = try identifier(uuid)
        guard let part = try topology().partition(uuid: uuid), part.size >= e.manifest.rootImageBytes else {
            throw SafetyRefusal("the partition is smaller than the root image")
        }

        let out = try chokepoint.openRaw(id, write: true)
        defer { try? out.close() }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        var hasher = SHA256Hasher()
        var written: Int64 = 0
        var pending = Data()
        let block = 4096
        func flush(final: Bool) throws {
            while pending.count >= (1 << 20) || (final && !pending.isEmpty) {
                var chunk = pending.prefix(1 << 20)
                pending.removeFirst(chunk.count)
                if chunk.count % block != 0 { chunk.append(Data(count: block - chunk.count % block)) }
                try out.write(contentsOf: chunk)
            }
        }
        func feed(_ d: Data) throws {
            var d = d
            hasher.update(d)
            if let f = faults.flipBitAtByte, f >= written, f < written + Int64(d.count) { d[d.startIndex + Int(f - written)] ^= 0x01 }
            written += Int64(d.count)
            if let s = faults.shortWriteAfter, written > s {
                try flush(final: true)
                throw EngineError(.appleTool, "writing the root image failed", detail: "I/O error after \(s) bytes (injected)")
            }
            pending.append(d)
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
        _ = try verifyProtected(content: true)
        return (written, hasher.finalize())
    }

    public func hashRaw(_ uuid: String, bytes: Int64) throws -> String {
        let h = try chokepoint.openRaw(try identifier(uuid), write: false)
        defer { try? h.close() }
        return try SHA256Hasher.stream(h, limit: bytes)
    }

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

    public func writeRaw(_ uuid: String, offset: Int64, data: Data) throws {
        precondition(offset % 4096 == 0)
        let h = try chokepoint.openRaw(try identifier(uuid), write: true)
        defer { try? h.close() }
        var d = data
        if d.count % 4096 != 0 { d.append(Data(count: 4096 - d.count % 4096)) }
        try h.seek(toOffset: UInt64(offset))
        try h.write(contentsOf: d)
        try h.synchronize()
        _ = try verifyProtected(content: true)
    }

    // MARK: image-only controls

    public func detach(force: Bool) throws {
        guard case .diskImage = authority.kind else { throw SafetyRefusal("a real disk can't be detached") }
        try authority.detach(force: force)
        chokepoint.invalidate()
    }

    public func attach() throws {
        guard case .diskImage = authority.kind else { throw SafetyRefusal("a real disk can't be attached") }
        chokepoint.invalidate()
        try authority.attach()
        chokepoint.invalidate()
    }
}
