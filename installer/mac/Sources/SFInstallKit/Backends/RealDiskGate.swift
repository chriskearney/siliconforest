import Foundation

/// The two keys for writing to a real, internal disk (DESIGN §14.11, ENGINE §12). Both are off by
/// default; no flag, argument or environment variable can open the gate from outside.
///
///  1. **Compile key.** `SF_REAL_DISK_WRITES` must be defined when the code is built. `Package.swift`
///     never defines it, CI refuses to run with it, and `scripts/check-real-disk-gate.sh` proves no
///     shipped binary contains the real-disk authority. Without it `evaluate` is closed before it even
///     looks for the authorization file, and the type that can name an internal disk does not exist.
///  2. **Runtime key.** A root-owned authorization file that names this exact plan, this exact disk
///     (its GPT UUID), and a short validity window. Chris puts it there for one install; it is never
///     shipped, never created by the app, and expires on its own.
///
/// `RefusingExecutor` stays the default privileged executor, and a gate that is open only lets the
/// helper's `LiveDiskBackend` try: every command still passes the protection receipt.
public enum RealDiskGate {
    /// The compile key.
    public static var compiledIn: Bool {
        #if SF_REAL_DISK_WRITES
        return true
        #else
        return false
        #endif
    }

    public static let authorizationPath = "/var/db/org.siliconforest.installer/real-disk-authorization.json"
    public static let format = "siliconforest-real-disk-authorization/1"
    /// What the person who creates the file is declaring.
    public static let statement = "I have a current backup of this disk and approve this exact plan writing to it."
    /// No authorization lasts longer than this, whatever its file says.
    public static let maxValidity: TimeInterval = 2 * 3600

    public struct Authorization: Codable, Sendable, Hashable {
        public var format: String
        public var statement: String
        public var planDigest: String
        /// The target whole disk's GPT UUID (`diskutil info -plist` `DiskUUID`), never a diskN.
        public var diskUUID: String
        public var notBefore: Date
        public var notAfter: Date
        public init(planDigest: String, diskUUID: String, notBefore: Date, notAfter: Date) {
            self.format = RealDiskGate.format; self.statement = RealDiskGate.statement
            self.planDigest = planDigest; self.diskUUID = diskUUID; self.notBefore = notBefore; self.notAfter = notAfter
        }
    }

    public enum Closed: Error, Equatable, Sendable, CustomStringConvertible {
        case notCompiled
        case noAuthorization
        case unsafeFile(String)
        case badFormat(String)
        case notRoot
        case notYetValid
        case expired
        case windowTooLong
        case planMismatch
        case diskMismatch

        public var description: String {
            switch self {
            case .notCompiled: return "real-disk writes are not compiled into this build"
            case .noAuthorization: return "there is no real-disk authorization"
            case .unsafeFile(let w): return "the authorization file is not safe to trust (\(w))"
            case .badFormat(let w): return "the authorization is malformed (\(w))"
            case .notRoot: return "real-disk writes need the root helper"
            case .notYetValid: return "the authorization is not valid yet"
            case .expired: return "the authorization has expired"
            case .windowTooLong: return "the authorization's validity window is too long"
            case .planMismatch: return "the authorization is for a different plan"
            case .diskMismatch: return "the authorization is for a different disk"
            }
        }
    }

    /// What the gate looks at on the file system. Tests inject this; the helper uses `.system`.
    public struct FileProbe: Sendable {
        public struct Stat: Sendable {
            public var isRegular: Bool; public var isSymlink: Bool; public var uid: UInt32; public var mode: UInt16
            public init(isRegular: Bool, isSymlink: Bool, uid: UInt32, mode: UInt16) { self.isRegular = isRegular; self.isSymlink = isSymlink; self.uid = uid; self.mode = mode }
        }
        public var lstat: @Sendable (String) -> Stat?
        public var read: @Sendable (String) -> Data?
        public init(lstat: @escaping @Sendable (String) -> Stat?, read: @escaping @Sendable (String) -> Data?) { self.lstat = lstat; self.read = read }

        public static let system = FileProbe(
            lstat: { path in
                var st = stat()
                guard Foundation.lstat(path, &st) == 0 else { return nil }
                return Stat(isRegular: (st.st_mode & S_IFMT) == S_IFREG, isSymlink: (st.st_mode & S_IFMT) == S_IFLNK,
                            uid: st.st_uid, mode: UInt16(st.st_mode & 0o7777))
            },
            read: { FileManager.default.contents(atPath: $0) })
    }

    /// Whether the runtime key is open for this plan and disk. Checks the compile key first and does not
    /// read anything when it is closed.
    public static func evaluate(planDigest: String, diskUUID: String, path: String = authorizationPath,
                                now: Date = Date(), uid: UInt32 = UInt32(getuid()), probe: FileProbe = .system,
                                compiled: Bool = compiledIn) -> Result<Authorization, Closed> {
        guard compiled else { return .failure(.notCompiled) }
        guard uid == 0 else { return .failure(.notRoot) }
        guard let st = probe.lstat(path) else { return .failure(.noAuthorization) }
        guard st.isRegular, !st.isSymlink else { return .failure(.unsafeFile("not a regular file")) }
        guard st.uid == 0 else { return .failure(.unsafeFile("not owned by root")) }
        guard st.mode & 0o022 == 0 else { return .failure(.unsafeFile("writable by group or others")) }
        let dir = (path as NSString).deletingLastPathComponent
        if let d = probe.lstat(dir) { guard d.uid == 0, d.mode & 0o022 == 0 else { return .failure(.unsafeFile("its directory is not root-only")) } }
        guard let data = probe.read(path) else { return .failure(.noAuthorization) }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let a: Authorization
        do { a = try dec.decode(Authorization.self, from: data) } catch { return .failure(.badFormat("not valid JSON for this format")) }
        guard a.format == format, a.statement == statement else { return .failure(.badFormat("wrong format or statement")) }
        guard a.notAfter.timeIntervalSince(a.notBefore) <= maxValidity, a.notAfter > a.notBefore else { return .failure(.windowTooLong) }
        guard now >= a.notBefore else { return .failure(.notYetValid) }
        guard now < a.notAfter else { return .failure(.expired) }
        guard !planDigest.isEmpty, a.planDigest == planDigest else { return .failure(.planMismatch) }
        guard !diskUUID.isEmpty, a.diskUUID.uppercased() == diskUUID.uppercased() else { return .failure(.diskMismatch) }
        return .success(a)
    }
}
