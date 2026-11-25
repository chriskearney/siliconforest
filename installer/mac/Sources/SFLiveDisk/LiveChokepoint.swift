import Foundation
import SFEngine
import SFInstallKit

/// A disk-changing command, parsed. Anything that does not parse into one of these shapes is refused
/// before any device is looked at: there is no "run this string".
public enum LiveMutation: Sendable, Equatable {
    case resize(container: String, size: ResizeSize)
    case addPartition(after: String, format: NewFormat, bytes: Int64)
    case eraseToFree(String)
    case deleteContainer(String)
    /// `groupWith` is the Data volume a new System volume joins (SFStub, as upstream stub.py).
    case addVolume(container: String, groupWith: String? = nil)
    /// SFStub makes the empty container's default volume its Data volume (upstream prepare_volume).
    case changeVolumeRole(volume: String)
    case renameVolume(String)
    case formatFAT32(device: String)
    case mount(String)
    case unmount(String)
    case detachImage

    public enum ResizeSize: Sendable, Equatable { case bytes(Int64), fillFree }
    public enum NewFormat: Sendable, Equatable { case apfs(label: String), efi, linuxFilesystem }

    public static let efiGUID = "C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
    public static let linuxGUID = "0FC63DAF-8483-4772-8E79-3D69D8477DE4"

    static func device(_ s: String) -> String? {
        guard let (id, _) = try? ImageGuard.normalise(s) else { return nil }
        return id
    }
    static func partitionID(_ s: String) -> String? {
        guard let id = device(s), id.range(of: #"^disk[0-9]+s[0-9]+$"#, options: .regularExpression) != nil else { return nil }
        return id
    }
    static func bytes(_ s: String) -> Int64? {
        guard s.hasSuffix("B"), let n = Int64(s.dropLast()), n > 0 else { return nil }
        return n
    }
    /// A name for a partition or volume: never an option or a placeholder, no path or control characters.
    static func plainLabel(_ s: String) -> Bool {
        guard !s.isEmpty, s.utf8.count <= 63, let f = s.unicodeScalars.first, f != "-", f != "%", f != " " else { return false }
        return !s.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7f || $0 == "/" || $0 == "\\" || $0 == "%" }
    }

    public static func parse(_ argv: [String]) throws -> LiveMutation {
        func bad(_ why: String = "not a disk command this build runs") -> SafetyRefusal { SafetyRefusal("\(why): \(argv.joined(separator: " "))") }
        guard argv.count >= 2 else { throw bad() }
        switch argv[0] {
        case "/usr/sbin/diskutil":
            switch argv[1] {
            case "apfs":
                guard argv.count >= 3 else { throw bad() }
                switch argv[2] {
                case "resizeContainer":
                    guard argv.count == 5, let id = partitionID(argv[3]) else { throw bad() }
                    if argv[4] == "0" { return .resize(container: id, size: .fillFree) }
                    guard let n = bytes(argv[4]) else { throw bad() }
                    return .resize(container: id, size: .bytes(n))
                case "deleteContainer":
                    guard argv.count == 4, let id = partitionID(argv[3]) else { throw bad() }
                    return .deleteContainer(id)
                case "addVolume":
                    // engine:  addVolume <container ref> APFS <name> -role <role> -nomount
                    // SFStub:  addVolume <container ref> apfs <name> -role B|R|D
                    //          addVolume <container ref> apfs <name> -role S -groupWith <Data volume>
                    guard argv.count >= 8, let ref = device(argv[3]), plainLabel(argv[5]), argv[6] == "-role" else { throw bad() }
                    let role = argv[7]
                    if argv[4] == "APFS", argv.count == 9, argv[8] == "-nomount",
                       role.range(of: #"^[A-Za-z]{1,3}$"#, options: .regularExpression) != nil { return .addVolume(container: ref) }
                    guard argv[4] == "apfs" else { throw bad() }
                    if argv.count == 8, ["B", "R", "D"].contains(role) { return .addVolume(container: ref) }
                    guard argv.count == 10, role == "S", argv[8] == "-groupWith", let g = partitionID(argv[9]) else { throw bad() }
                    return .addVolume(container: ref, groupWith: g)
                case "changeVolumeRole":
                    // changeVolumeRole <volume> D: only ever to Data
                    guard argv.count == 5, let id = partitionID(argv[3]), argv[4] == "D" else { throw bad() }
                    return .changeVolumeRole(volume: id)
                default: throw bad()
                }
            case "addPartition":
                guard argv.count == 6, let after = partitionID(argv[2]), let n = bytes(argv[5]) else { throw bad() }
                if argv[3] == "APFS", plainLabel(argv[4]) { return .addPartition(after: after, format: .apfs(label: argv[4]), bytes: n) }
                guard argv[4] == "%noformat%" else { throw bad() }
                if argv[3] == "%\(efiGUID)%" { return .addPartition(after: after, format: .efi, bytes: n) }
                if argv[3] == "%\(linuxGUID)%" { return .addPartition(after: after, format: .linuxFilesystem, bytes: n) }
                throw bad("a partition type this build never creates")
            case "eraseVolume":
                guard argv.count == 5, argv[2] == "free", argv[3] == "none" || argv[3] == "free", let id = partitionID(argv[4]) else { throw bad() }
                return .eraseToFree(id)
            case "mount":
                guard argv.count == 4, argv[2] == "nobrowse", let id = partitionID(argv[3]) else { throw bad() }
                return .mount(id)
            case "unmount":
                guard argv.count == 3, let id = partitionID(argv[2]) else { throw bad() }
                return .unmount(id)
            case "rename":
                // rename <volume> <name>: SFStub names the Data volume "<label> - Data"
                guard argv.count == 4, let id = partitionID(argv[2]), plainLabel(argv[3]) else { throw bad() }
                return .renameVolume(id)
            default: throw bad()   // partitionDisk, eraseDisk, unmountDisk, eject, …
            }
        case "/sbin/newfs_msdos":
            guard argv.count == 6, argv[1] == "-F", argv[2] == "32", argv[3] == "-v", plainLabel(argv[4]), let id = partitionID(argv[5]) else { throw bad() }
            return .formatFAT32(device: id)
        case "/usr/bin/hdiutil":
            guard argv.count >= 3, argv[1] == "detach", device(argv[2]) != nil, argv.count == 3 || (argv.count == 4 && argv[3] == "-force") else { throw bad() }
            return .detachImage
        default: throw bad()
        }
    }

    /// The device identifiers a command names.
    public var devices: [String] {
        switch self {
        case .resize(let c, _): return [c]
        case .addPartition(let a, _, _): return [a]
        case .eraseToFree(let d), .deleteContainer(let d), .mount(let d), .unmount(let d): return [d]
        case .changeVolumeRole(let d), .renameVolume(let d): return [d]
        case .addVolume(let c, let g): return g.map { [c, $0] } ?? [c]
        case .formatFAT32(let d): return [d]
        case .detachImage: return []
        }
    }
}

/// The one door for every command or raw write that changes the target disk. Every call re-proves,
/// from a fresh read, that the device belongs to the target (`TargetAuthority`) and that the command is
/// one the protection receipt permits, then runs it. There is no other path from the engine to
/// `diskutil`, `newfs_msdos` or a raw device, and no flag that skips a check.
public final class LiveChokepoint: @unchecked Sendable {
    public struct Record: Sendable, Hashable {
        public var argv: [String]
        public var status: Int32?
    }

    public let authority: TargetAuthority
    public let runner: ToolRunner
    private let lock = NSLock()
    private var _records: [Record] = []
    private var _generation = 0
    private var _tripped: String?
    /// Supplies the receipt (derived by the backend from the journal's saved table).
    var receipt: () throws -> ProtectionReceipt

    init(authority: TargetAuthority, runner: ToolRunner, receipt: @escaping () throws -> ProtectionReceipt) {
        self.authority = authority; self.runner = runner; self.receipt = receipt
    }

    public var records: [Record] { lock.lock(); defer { lock.unlock() }; return _records }
    public var generation: Int { lock.lock(); defer { lock.unlock() }; return _generation }
    public func invalidate() { lock.lock(); _generation += 1; lock.unlock() }

    /// After a protection violation nothing more is ever run through this chokepoint.
    public var tripped: String? { lock.lock(); defer { lock.unlock() }; return _tripped }
    func trip(_ why: String) { lock.lock(); if _tripped == nil { _tripped = why }; lock.unlock() }

    func readTopology() throws -> ImageTopology {
        try TopologyReader.read(try authority.wholeDisk(), query: authority.query)
    }

    /// Which partition a device identifier belongs to: itself, or the store of an APFS container (or
    /// one of its volumes) that the identifier names. nil for the whole disk.
    static func owner(of id: String, in t: ImageTopology) -> ImagePartition? {
        if let p = t.partition(id: id) { return p }
        return t.partitions.first { p in
            guard let a = p.apfs else { return false }
            return a.reference == id || a.volumes.contains { $0.identifier == id }
        }
    }

    /// The rules. Throws `SafetyRefusal` when the receipt does not permit `m` on `t`.
    static func check(_ m: LiveMutation, on t: ImageTopology, receipt r: ProtectionReceipt) throws {
        func refuse(_ why: String) -> SafetyRefusal { SafetyRefusal("protection receipt: \(why)") }
        if case .detachImage = m { return }
        guard let dev = m.devices.first else { throw refuse("a command that names no device") }
        guard dev != t.wholeDisk else { throw refuse("never the whole disk (\(dev))") }
        guard let p = owner(of: dev, in: t) else { throw refuse("\(dev) is not a partition of the target") }
        if let e = r.protected.first(where: { $0.uuid == p.uuid }) {
            throw refuse("\(dev) is a protected \(e.kind.rawValue) partition")
        }
        switch m {
        case .resize(_, let size):
            guard p.uuid == r.macOSStore else { throw refuse("only the macOS container may be resized (\(dev))") }
            switch (r.operation, size) {
            case (.install, .bytes(let n)):
                guard n == r.macOSTo || n == r.macOSFrom else { throw refuse("the macOS container may only become \(r.macOSTo) B (or go back to \(r.macOSFrom) B), not \(n)") }
            case (.remove, .fillFree): break
            case (.install, .fillFree): throw refuse("an install never grows macOS to fill")
            case (.remove, .bytes): throw refuse("a removal only grows macOS to fill the freed space")
            }
        case .addPartition(_, _, let bytes):
            guard r.operation == .install else { throw refuse("a removal creates nothing") }
            if p.uuid == r.macOSStore {
                guard p.size == r.macOSTo else { throw refuse("macOS isn't at its planned size yet") }
            } else {
                guard r.isWritable(p) else { throw refuse("\(dev) is outside the span this job may use") }
            }
            guard p.end >= r.spanStart, p.end + bytes <= r.spanEnd else { throw refuse("the new partition would leave the allowed span") }
            guard bytes % t.blockSize == 0 || bytes % 512 == 0 else { throw refuse("unaligned size") }
        case .eraseToFree, .deleteContainer, .addVolume, .changeVolumeRole, .renameVolume, .formatFAT32, .mount, .unmount:
            guard p.uuid != r.macOSStore else { throw refuse("the macOS container is never erased, formatted, renamed or mounted by this build (\(dev))") }
            guard r.isWritable(p) else { throw refuse("\(dev) is outside the span this job may use") }
            if case .addVolume(_, let g?) = m, owner(of: g, in: t)?.uuid != p.uuid { throw refuse("\(g) is not a volume of the same container") }
        case .detachImage: break
        }
    }

    /// Authorises without running: for the resize supervisor, which launches its own process.
    @discardableResult
    public func authorize(_ argv: [String]) throws -> LiveMutation {
        if let why = tripped { throw SafetyRefusal("this job tripped its protection receipt (\(why)); nothing more will be written") }
        try ForbiddenTools.check(argv)
        let m = try LiveMutation.parse(argv)
        if case .detachImage = m {
            guard case .diskImage = authority.kind else { throw SafetyRefusal("only a disk image can be detached") }
            return m
        }
        let r = try receipt()
        for d in m.devices { try authority.authorize(d) }        // 1. the target authority, before diskutil is asked about it
        let t = try readTopology()                                // 2. a fresh read
        try Self.check(m, on: t, receipt: r)                      // 3. the receipt
        return m
    }

    public func run(_ argv: [String], stdin: Data? = nil) throws -> ToolResult {
        try authorize(argv)
        invalidate()
        defer { invalidate() }
        let result = try runner.run(argv, stdin: stdin)
        lock.lock(); _records.append(Record(argv: argv, status: result.status)); lock.unlock()
        return result
    }

    /// Opens a partition's raw device. Writes are for partitions this job may write, never whole disks.
    public func openRaw(_ device: String, write: Bool) throws -> FileHandle {
        if let why = tripped { throw SafetyRefusal("this job tripped its protection receipt (\(why)); nothing more will be touched") }
        let (id, whole) = try ImageGuard.normalise(device)
        try authority.authorize(id)
        if write {
            guard id != whole else { throw SafetyRefusal("raw writes to a whole disk are never allowed (\(id))") }
            let r = try receipt()
            let t = try readTopology()
            guard let p = Self.owner(of: id, in: t), p.identifier == id else { throw SafetyRefusal("\(id) is not a partition of the target") }
            guard r.isWritable(p) else { throw SafetyRefusal("protection receipt: raw writes only inside the span (\(id) is outside, or protected)") }
            invalidate()
        }
        let path = "/dev/r\(id)"
        let fd = open(path, write ? O_RDWR : O_RDONLY)
        guard fd >= 0 else { throw EngineError(.appleTool, "couldn't open \(path)", detail: String(cString: strerror(errno))) }
        lock.lock(); _records.append(Record(argv: ["<raw \(write ? "rw" : "ro")>", path], status: 0)); lock.unlock()
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    /// The mount point of a volume of the target, proved two ways (diskutil names it; statfs agrees).
    public func mountPoint(of device: String) throws -> URL {
        try authority.authorize(device)
        let info = try Query.dict(authority.query, ["/usr/sbin/diskutil", "info", "-plist", device])
        guard let mp = info["MountPoint"] as? String, !mp.isEmpty else { throw EngineError(.transient, "\(device) is not mounted") }
        guard mp.hasPrefix("/Volumes/") else { throw SafetyRefusal("\(device) is mounted outside /Volumes (\(mp))") }
        var st = statfs()
        guard statfs(mp, &st) == 0 else { throw EngineError(.transient, "can't stat \(mp)") }
        let from = withUnsafePointer(to: &st.f_mntfromname) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) } }
        guard from == "/dev/\(device)" else { throw SafetyRefusal("\(mp) is mounted from \(from), not \(device)") }
        // Files are written only below volumes this job created.
        let t = try readTopology()
        guard let p = Self.owner(of: device, in: t), try receipt().isWritable(p) else {
            throw SafetyRefusal("protection receipt: \(device) is not a volume this job may write files to")
        }
        return URL(fileURLWithPath: mp, isDirectory: true)
    }
}
