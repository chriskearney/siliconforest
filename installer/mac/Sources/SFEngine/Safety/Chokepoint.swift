import Foundation

/// The one door for every command or write that changes a disk. Each call re-proves, through
/// `ImageGuard`, that every device it names is backed by one of our disk images, then runs it.
/// There is no other path from the engine to `diskutil`, `newfs_msdos`, `hdiutil detach` or a raw
/// device, and no flag that skips the check (DESIGN §14.11).
public final class ImageChokepoint: @unchecked Sendable {
    public struct Record: Sendable, Hashable {
        public var argv: [String]
        public var devices: [String]
        public var image: String
        public var status: Int32?
    }

    public let imageGuard: ImageGuard
    public let runner: ToolRunner
    private let lock = NSLock()
    private var _records: [Record] = []

    public init(imageGuard: ImageGuard, runner: ToolRunner = ProcessToolRunner()) {
        self.imageGuard = imageGuard
        self.runner = runner
    }

    public var records: [Record] { lock.lock(); defer { lock.unlock() }; return _records }

    /// Bumped by every command and raw write through here: readers' caches are valid only within
    /// one generation. The safety checks themselves are never cached.
    private var _generation = 0
    public var generation: Int { lock.lock(); defer { lock.unlock() }; return _generation }
    public func invalidate() { lock.lock(); _generation += 1; lock.unlock() }

    /// Mutating command shapes the engine uses. Anything else is refused before any check.
    static func allowedShape(_ argv: [String]) -> Bool {
        guard argv.count >= 2 else { return false }
        switch argv[0] {
        case "/usr/sbin/diskutil":
            let verbs: Set<String> = ["addPartition", "eraseVolume", "partitionDisk", "mount", "unmount", "unmountDisk", "eject"]
            if verbs.contains(argv[1]) { return true }
            if argv[1] == "apfs", argv.count >= 3 {
                if argv[2] == "resizeContainer" { return !argv.contains("limits") }
                return ["addVolume", "deleteContainer", "deleteVolume"].contains(argv[2])
            }
            return false
        case "/sbin/newfs_msdos": return true
        case "/usr/bin/hdiutil": return argv[1] == "detach"
        default: return false
        }
    }

    static func deviceTokens(_ argv: [String]) -> [String] {
        argv.dropFirst().filter { $0.range(of: #"^(/dev/)?r?disk[0-9]+(s[0-9]+)?$"#, options: .regularExpression) != nil }
    }

    /// Proves every device in `argv` is image-backed and part of one image; returns the proofs.
    @discardableResult
    public func authorizeAll(_ argv: [String]) throws -> [AuthorizedDevice] {
        try ForbiddenTools.check(argv)
        guard Self.allowedShape(argv) else { throw SafetyRefusal("not an allowed disk command: \(argv.joined(separator: " "))") }
        let tokens = Self.deviceTokens(argv)
        guard !tokens.isEmpty else { throw SafetyRefusal("a disk command must name its device: \(argv.joined(separator: " "))") }
        let proofs = try tokens.map { try imageGuard.authorize($0) }
        guard Set(proofs.map(\.imageWholeDisk)).count == 1 else { throw SafetyRefusal("one command may touch only one image") }
        return proofs
    }

    /// Runs a mutating command after proving its targets. Every call checks again.
    public func run(_ argv: [String], stdin: Data? = nil) throws -> ToolResult {
        let proofs = try authorizeAll(argv)
        invalidate()
        defer { invalidate() }
        let result = try runner.run(argv, stdin: stdin)
        lock.lock()
        _records.append(Record(argv: argv, devices: proofs.map(\.identifier), image: proofs[0].imagePath, status: result.status))
        lock.unlock()
        return result
    }

    /// Opens a partition's raw device. Writes are refused on whole disks (the partition table is
    /// changed only through diskutil).
    public func openRaw(_ device: String, write: Bool) throws -> FileHandle {
        let proof = try imageGuard.authorize(device)
        let (id, whole) = try ImageGuard.normalise(device)
        if write && id == whole { throw SafetyRefusal("raw writes to a whole disk are never allowed (\(id))") }
        let path = "/dev/r\(id)"
        if write { invalidate() }
        let fd = open(path, write ? O_RDWR : O_RDONLY)
        guard fd >= 0 else { throw EngineError(.appleTool, "couldn't open \(path)", detail: String(cString: strerror(errno))) }
        lock.lock()
        _records.append(Record(argv: ["<raw \(write ? "rw" : "ro")>", path], devices: [id], image: proof.imagePath, status: 0))
        lock.unlock()
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    /// The mount point of an image-backed volume, proved two ways: diskutil names it, and statfs on
    /// that path reports the same device. File writes happen only below a URL from here.
    public func mountPoint(of device: String) throws -> URL {
        let proof = try imageGuard.authorize(device)
        let info = try Query.dict(imageGuard.query, ["/usr/sbin/diskutil", "info", "-plist", proof.identifier])
        guard let mp = info["MountPoint"] as? String, !mp.isEmpty else {
            throw EngineError(.transient, "\(proof.identifier) is not mounted")
        }
        guard mp.hasPrefix("/Volumes/") else { throw SafetyRefusal("\(proof.identifier) is mounted outside /Volumes (\(mp))") }
        var st = statfs()
        guard statfs(mp, &st) == 0 else { throw EngineError(.transient, "can't stat \(mp)") }
        let from = withUnsafePointer(to: &st.f_mntfromname) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) } }
        guard from == "/dev/\(proof.identifier)" else { throw SafetyRefusal("\(mp) is mounted from \(from), not \(proof.identifier)") }
        return URL(fileURLWithPath: mp, isDirectory: true)
    }
}
