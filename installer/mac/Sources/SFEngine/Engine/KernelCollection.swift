import Foundation
import Compression

/// The kernel collection as a release ships it: separate hashed inputs, linked on this Mac
/// (docs/installer/PAYLOAD.md §13). Same rules as installer/payload/release/kc_release.py, the reference
/// these are tested against.
public struct KernelCollection: Codable, Sendable, Hashable {
    public struct File: Codable, Sendable, Hashable {
        public var path: String
        public var artifact: String
        public var mode: Int
    }
    public struct Bundle: Codable, Sendable, Hashable {
        /// `kexts/<Name>.kext` or `codeless/<Name>.kext`, relative to the assembly directory.
        public var dir: String
        public var files: [File]
    }
    /// The macOS kc-builder (artifact name).
    public var tool: String
    public var toolSigning: String
    public var kernel: String
    public var bundles: [Bundle]
    /// kc-builder's options exactly: inputs relative to the assembly directory, the output as `@OUTPUT@`.
    public var linkArgs: [String]
    public var collectionSHA256: String
    public var collectionBytes: Int64
    /// The boot-argument template artifact, personalised at S42.
    public var bootargsTemplate: String

    public static let output = "@OUTPUT@"
    static let kinds = ["-kext": "kexts", "-codeless": "codeless"]

    public init(tool: String, toolSigning: String, kernel: String, bundles: [Bundle], linkArgs: [String],
                collectionSHA256: String, collectionBytes: Int64, bootargsTemplate: String) {
        self.tool = tool; self.toolSigning = toolSigning; self.kernel = kernel; self.bundles = bundles; self.linkArgs = linkArgs
        self.collectionSHA256 = collectionSHA256; self.collectionBytes = collectionBytes; self.bootargsTemplate = bootargsTemplate
    }

    static func part(_ s: Substring) -> Bool {
        guard let f = s.unicodeScalars.first, s.count <= 81, CharacterSet.alphanumerics.contains(f), f.isASCII else { return false }
        return s.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "._+-".unicodeScalars.contains($0)) }
    }
    static func artifactName(_ dir: String, _ path: String) -> String {
        let p = dir.split(separator: "/", maxSplits: 1)
        guard p.count == 2 else { return "" }
        return "kc.\(p[0]).\(p[1]).\(path.replacingOccurrences(of: "/", with: "."))"
    }

    /// Refuses anything outside the release link format, before any file is touched.
    public func validate(release: ReleaseManifest) throws {
        func bad(_ why: String) -> EngineError { EngineError(.inconsistent, "the release's kernel collection is malformed: \(why)") }
        var kernelSeen = false, outSeen = false, baseSeen = false, order: [String] = []
        var i = 0
        while i < linkArgs.count {
            guard i + 1 < linkArgs.count else { throw bad("option \(linkArgs[i]) has no value") }
            let (opt, val) = (linkArgs[i], linkArgs[i + 1])
            switch opt {
            case "-kernel":
                guard !kernelSeen, val == "kernel" else { throw bad("-kernel") }
                kernelSeen = true
            case "-kext", "-codeless":
                let parts = val.split(separator: "/", omittingEmptySubsequences: false)
                guard parts.count == 2, String(parts[0]) == Self.kinds[opt], Self.part(parts[1]), parts[1].hasSuffix(".kext"), !order.contains(val)
                else { throw bad("bundle \(val)") }
                order.append(val)
            case "-kc-base":
                guard !baseSeen, (1...16).contains(val.count), val.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { throw bad("-kc-base") }
                baseSeen = true
            case "-o":
                guard !outSeen, val == Self.output else { throw bad("-o") }
                outSeen = true
            default:
                throw bad("option \(opt) is not part of the release link format")
            }
            i += 2
        }
        guard kernelSeen, outSeen, baseSeen else { throw bad("-kernel, -kc-base and -o are required") }
        guard order == bundles.map(\.dir) else { throw bad("bundles are not exactly link_args' bundles, in order") }
        var used: Set<String> = [tool, kernel, bootargsTemplate]
        for b in bundles {
            var paths: Set<String> = []
            guard !b.files.isEmpty else { throw bad("\(b.dir) has no files") }
            for f in b.files {
                guard f.path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy(Self.part), !paths.contains(f.path),
                      [0o644, 0o755].contains(f.mode), f.artifact == Self.artifactName(b.dir, f.path) else { throw bad("file entry \(f.path)") }
                paths.insert(f.path)
                used.insert(f.artifact)
            }
        }
        for a in used where release.artifact(a) == nil { throw bad("\(a) is not a release artifact") }
        guard collectionSHA256.count == 64, collectionSHA256.allSatisfy({ $0.isHexDigit && !$0.isUppercase }), collectionBytes > 0 else {
            throw bad("no expected collection hash")
        }
    }

    /// install.json (`siliconforest-install/3`) → this. Only the kernel collection and what personalises it.
    public static func fromInstallJSON(_ data: Data) throws -> (KernelCollection, rootFilesystemUUID: String?) {
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any], let kc = o["kernel_collection"] as? [String: Any],
              let tool = kc["tool"] as? [String: Any], let toolName = tool["artifact"] as? String, let signing = tool["signing"] as? String,
              let kernel = kc["kernel"] as? String, let args = kc["link_args"] as? [String], let sha = kc["collection_sha256"] as? String,
              let n = kc["collection_bytes"] as? Int64 ?? (kc["collection_bytes"] as? Int).map(Int64.init),
              let bl = kc["bundles"] as? [[String: Any]], let boot = o["boot"] as? [String: Any], let tmpl = boot["bootargs"] as? String
        else { throw EngineError(.inconsistent, "install.json has no usable kernel_collection") }
        let bundles: [Bundle] = try bl.map { b in
            guard let dir = b["dir"] as? String, let fl = b["files"] as? [[String: Any]] else { throw EngineError(.inconsistent, "kernel_collection bundle") }
            return Bundle(dir: dir, files: try fl.map { f in
                guard let p = f["path"] as? String, let a = f["artifact"] as? String, let m = f["mode"] as? Int else {
                    throw EngineError(.inconsistent, "kernel_collection file")
                }
                return File(path: p, artifact: a, mode: m)
            })
        }
        let fs = (o["root"] as? [String: Any])?["fs_uuid"] as? String
        return (KernelCollection(tool: toolName, toolSigning: signing, kernel: kernel, bundles: bundles, linkArgs: args,
                                 collectionSHA256: sha, collectionBytes: n, bootargsTemplate: tmpl), fs)
    }
}

/// S17: link the collection from verified inputs, in a private directory, and accept only the expected bytes.
public enum KernelCollectionAssembler {
    public struct Result: Sendable { public var collection: URL; public var sha256: String; public var bytes: Int64; public var seconds: Double }

    /// `source(artifact)` is where S10 put that artifact (S15 has hashed it; this hashes every copy again).
    public static func assemble(_ kc: KernelCollection, release: ReleaseManifest, source: (String) -> URL, into dir: URL,
                                timeout: TimeInterval = 600) throws -> Result {
        try kc.validate(release: release)
        let fm = FileManager.default
        try? fm.removeItem(at: dir)
        let tree = dir.appendingPathComponent("inputs", isDirectory: true)
        try fm.createDirectory(at: tree, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        let out = dir.appendingPathComponent("collection")
        do {
            func take(_ artifact: String, to dst: URL, mode: Int) throws {
                guard let a = release.artifact(artifact) else { throw EngineError(.inconsistent, "\(artifact) is not in the release") }
                try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: source(artifact), to: dst)
                guard try SHA256Hasher.file(dst) == a.sha256 else {
                    throw EngineError(.inconsistent, "\(artifact) doesn't match its signed hash; it will be downloaded again")
                }
                try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: dst.path)
            }
            let tool = dir.appendingPathComponent("kc-builder")
            try take(kc.tool, to: tool, mode: 0o755)
            try take(kc.kernel, to: tree.appendingPathComponent("kernel"), mode: 0o444)
            for b in kc.bundles {
                for f in b.files { try take(f.artifact, to: tree.appendingPathComponent(b.dir).appendingPathComponent(f.path), mode: f.mode) }
            }
            let started = Date()
            let p = Process()
            p.executableURL = tool
            p.arguments = kc.linkArgs.map { $0 == KernelCollection.output ? out.path : $0 }
            p.currentDirectoryURL = tree
            p.environment = ["PATH": "/usr/bin:/bin", "LC_ALL": "C"]
            let log = dir.appendingPathComponent("kc-builder.log")
            fm.createFile(atPath: log.path, contents: nil)
            let lh = try FileHandle(forWritingTo: log)
            defer { try? lh.close() }
            p.standardOutput = lh
            p.standardError = lh
            p.standardInput = FileHandle.nullDevice
            try p.run()
            let deadline = Date().addingTimeInterval(timeout)
            while p.isRunning {
                if Date() > deadline { p.terminate(); p.waitUntilExit(); throw EngineError(.internalError, "kc-builder took longer than \(Int(timeout)) s") }
                Thread.sleep(forTimeInterval: 0.02)
            }
            guard p.terminationReason == .exit, p.terminationStatus == 0 else {
                throw EngineError(.internalError, "kc-builder failed", detail: "status \(p.terminationStatus)")
            }
            let bytes = (try fm.attributesOfItem(atPath: out.path)[.size] as? NSNumber)?.int64Value ?? -1
            let sha = try SHA256Hasher.file(out)
            guard sha == kc.collectionSHA256, bytes == kc.collectionBytes else {
                throw EngineError(.inconsistent, "the kernel collection linked on this Mac isn't the release's",
                                  detail: "\(sha.prefix(16))… \(bytes) B, expected \(kc.collectionSHA256.prefix(16))… \(kc.collectionBytes) B")
            }
            try fm.removeItem(at: tree)
            try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: out.path)
            return Result(collection: out, sha256: sha, bytes: bytes, seconds: Date().timeIntervalSince(started))
        } catch {
            try? fm.removeItem(at: out)
            throw error
        }
    }

    /// The accepted collection, re-hashed: nil unless it is exactly the release's.
    public static func accepted(_ kc: KernelCollection, in dir: URL) -> URL? {
        let out = dir.appendingPathComponent("collection")
        guard let n = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? NSNumber)?.int64Value, n == kc.collectionBytes,
              (try? SHA256Hasher.file(out)) == kc.collectionSHA256 else { return nil }
        return out
    }
}

/// `sf/kernel.bin`: PDSF records as integrations/siliconforest/m1-native-boot/b1/pdsf_pack.py writes them
/// (CONFIG, KERNEL gzip, END), the file an installed stage 2 reads from SFBOOT.
public enum PDSF {
    static let magic: UInt32 = 0x4653_4450, version: UInt16 = 1, align = 16
    static let end: UInt16 = 0, config: UInt16 = 1, kernel: UInt16 = 2
    static let gzipFlag: UInt32 = 1
    /// m1n1 xnuboot.h v2 capacity, including the terminating NUL.
    public static let bootargsCapacity = 608

    static func header(kind: UInt16, flags: UInt32, crc: UInt32, size: UInt64, raw: UInt64) -> Data {
        var d = Data()
        func le<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        le(magic); le(version); le(kind); le(flags); le(crc); le(size); le(raw)
        return d
    }

    static func record(_ kind: UInt16, _ data: Data, raw: Int? = nil, flags: UInt32 = 0) -> Data {
        var r = header(kind: kind, flags: flags, crc: CRC32.of(data), size: UInt64(data.count), raw: UInt64(raw ?? data.count))
        r.append(data)
        r.append(Data(count: (align - r.count % align) % align))
        return r
    }

    public static func configText(bootargs: String) throws -> Data {
        guard !bootargs.isEmpty, bootargs.count < bootargsCapacity, bootargs.unicodeScalars.allSatisfy({ (32..<127).contains($0.value) }) else {
            throw EngineError(.inconsistent, "the boot arguments must be 1 to \(bootargsCapacity - 1) printable ASCII characters")
        }
        return Data("bootargs=\(bootargs)\n".utf8)
    }

    public static func kernelBin(bootargs: String, collection: Data) throws -> Data {
        var d = record(config, try configText(bootargs: bootargs))
        d.append(record(kernel, try Gzip.compress(collection), raw: collection.count, flags: gzipFlag))
        d.append(header(kind: end, flags: 0, crc: 0, size: 0, raw: 0))
        return d
    }

    /// The records of a kernel.bin, for read-back checks and tests: (kind, payload after gunzip).
    public static func records(_ d: Data) throws -> [(UInt16, Data)] {
        var out: [(UInt16, Data)] = []
        var o = 0
        func u<T: FixedWidthInteger>(_ at: Int, _: T.Type) -> T { d.subdata(in: d.startIndex + at ..< d.startIndex + at + MemoryLayout<T>.size).withUnsafeBytes { T(littleEndian: $0.loadUnaligned(as: T.self)) } }
        while o + 32 <= d.count {
            guard u(o, UInt32.self) == magic else { throw EngineError(.inconsistent, "not a PDSF record at \(o)") }
            let kind = u(o + 6, UInt16.self), flags = u(o + 8, UInt32.self), crc = u(o + 12, UInt32.self)
            let size = Int(u(o + 16, UInt64.self)), raw = Int(u(o + 24, UInt64.self))
            if kind == end { return out }
            guard o + 32 + size <= d.count else { throw EngineError(.inconsistent, "PDSF record runs past the end") }
            let body = d.subdata(in: d.startIndex + o + 32 ..< d.startIndex + o + 32 + size)
            guard CRC32.of(body) == crc else { throw EngineError(.inconsistent, "PDSF record CRC") }
            let payload = flags & gzipFlag != 0 ? try Gzip.decompress(body, expected: raw) : body
            out.append((kind, payload))
            o += 32 + size
            o += (align - o % align) % align
        }
        throw EngineError(.inconsistent, "PDSF has no end record")
    }
}

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func of(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        d.withUnsafeBytes { for b in $0 { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) } }
        return c ^ 0xFFFF_FFFF
    }
}

/// gzip (RFC 1952) around Compression's raw DEFLATE (its `.zlib` is RFC 1951 without a header).
enum Gzip {
    static func compress(_ d: Data) throws -> Data {
        var out = Data([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 3])   // no name, mtime 0, OS Unix: the same input gives the same bytes
        var body = Data()
        let f = try OutputFilter(.compress, using: .zlib) { (c: Data?) in if let c { body.append(c) } }
        var i = 0
        while i < d.count { let n = min(1 << 20, d.count - i); try f.write(d.subdata(in: d.startIndex + i ..< d.startIndex + i + n)); i += n }
        try f.finalize()
        out.append(body)
        withUnsafeBytes(of: CRC32.of(d).littleEndian) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(truncatingIfNeeded: d.count).littleEndian) { out.append(contentsOf: $0) }
        return out
    }

    static func decompress(_ g: Data, expected: Int) throws -> Data {
        guard g.count > 18, g[g.startIndex] == 0x1f, g[g.startIndex + 1] == 0x8b, g[g.startIndex + 2] == 8, g[g.startIndex + 3] == 0 else {
            throw EngineError(.inconsistent, "not a plain gzip member")
        }
        var out = Data()
        let f = try OutputFilter(.decompress, using: .zlib) { (c: Data?) in if let c { out.append(c) } }
        try f.write(g.subdata(in: g.startIndex + 10 ..< g.endIndex - 8))
        try f.finalize()
        let crc = g.subdata(in: g.endIndex - 8 ..< g.endIndex - 4).withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        guard out.count == expected, CRC32.of(out) == crc else { throw EngineError(.inconsistent, "gzip payload size or CRC") }
        return out
    }
}
