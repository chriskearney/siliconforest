// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// What the installer app's helper needs to run a full install itself (preview6): find this Mac's
// internal startup disk by identity, the typed confirmation for one plan, and the runtime
// authorization the helper writes after that confirmation and an administrator's approval.

import Foundation
import SFEngine
import SFInstallKit

/// The internal disk this Mac started from, found read-only: `/`'s APFS physical store, its whole
/// disk, and that disk's GPT UUID. Never a remembered diskN.
public enum StartupDisk {
    /// `/`'s APFS volume. macOS mounts `/` from a sealed snapshot of the System volume, `/dev/disk3s1s1`
    /// (the M5 shows exactly that): the volume is `disk3s1`. Anything else that isn't a disk identifier is refused.
    public static func volume(mountedFrom raw: String) throws -> String {
        var s = raw
        if s.hasPrefix("/dev/") { s.removeFirst(5) }
        if let r = s.range(of: #"^disk[0-9]+s[0-9]+s[0-9]+$"#, options: .regularExpression), r == s.startIndex..<s.endIndex,
           let cut = s.range(of: "s", options: .backwards) {
            s = String(s[..<cut.lowerBound])
        }
        return try ImageGuard.normalise(s).id
    }

    public static func rootVolume() throws -> String {
        var fs = statfs()
        guard statfs("/", &fs) == 0 else { throw SafetyRefusal("can't read the startup volume") }
        return try volume(mountedFrom: withUnsafeBytes(of: fs.f_mntfromname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) })
    }

    /// The startup volume's whole disk (diskutil only; no raw device is opened).
    public static func wholeDisk(query: ToolRunner = ProcessToolRunner()) throws -> String {
        let rootID = try rootVolume()
        let root = try Query.dict(query, ["/usr/sbin/diskutil", "info", "-plist", rootID])
        let stores = (root["APFSPhysicalStores"] as? [[String: Any]] ?? []).compactMap { $0["APFSPhysicalStore"] as? String }
        guard stores.count == 1, let store = stores.first else { throw SafetyRefusal("this Mac's startup volume doesn't have exactly one APFS physical store") }
        return try ImageGuard.normalise(store).whole
    }

    public static func find(query: ToolRunner = ProcessToolRunner()) throws -> (uuid: String, whole: String) {
        let whole = try wholeDisk(query: query)
        let info = try Query.dict(query, ["/usr/sbin/diskutil", "info", "-plist", whole])
        let uuid = try WholeDiskIdentity.uuid(whole, info: info)
        guard try StubOnlyRun.internalWholeDisk(diskUUID: uuid, query: query) == whole else { throw SafetyRefusal("the startup disk's UUID doesn't resolve back to \(whole)") }
        return (uuid, whole)
    }
}

/// What the person types before the helper may write: the name of the macOS volume the space comes from
/// (preview13: the only thing; the erase phrase was dropped, and the administrator dialog stays as the
/// second deliberate step). The helper derives the expected name from its own plan and disk read, so a
/// typed name for some other plan or disk never matches.
public struct TypedConfirmation: Codable, Sendable, Hashable {
    public var diskName: String
    public init(diskName: String) { self.diskName = diskName }

    /// The macOS System volume's name in the container the plan shrinks ("Macintosh HD").
    public static func diskName(plan: EnginePlan, topology: ImageTopology) -> String? {
        guard let mac = topology.partition(uuid: plan.macOS.store) else { return nil }
        let vols = mac.apfs?.volumes ?? []
        return (vols.first { $0.roles.contains("System") } ?? vols.first)?.name
    }

    /// Whole gigabytes (10^9, as Finder shows them), rounded up, that macOS gives up.
    public static func gigabytes(plan: EnginePlan) -> Int64 {
        let taken = max(0, plan.macOS.from - plan.macOS.to)
        return (taken + 999_999_999) / 1_000_000_000
    }

    public static func expected(plan: EnginePlan, topology: ImageTopology) -> TypedConfirmation? {
        diskName(plan: plan, topology: topology).map { TypedConfirmation(diskName: $0) }
    }

    /// Case and spacing are forgiven: surrounding white space is dropped and any run of white space inside
    /// counts as one space. Different letters (or an empty name) never match.
    public static func normalized(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ").lowercased()
    }

    public func matches(_ expected: TypedConfirmation) -> Bool {
        let want = Self.normalized(expected.diskName)
        return !want.isEmpty && Self.normalized(diskName) == want
    }
}

/// Writes the runtime authorization (RealDiskGate) for one plan and disk. Only the root helper calls it,
/// after the typed confirmation and an administrator's approval; `sfinstrun` still never writes it.
public enum AuthorizationFile {
    public static func authorization(planDigest: String, diskUUID: String, now: Date = Date(), hours: Double = 2) -> RealDiskGate.Authorization {
        RealDiskGate.Authorization(planDigest: planDigest, diskUUID: diskUUID.uppercased(), notBefore: now.addingTimeInterval(-5),
                                   notAfter: now.addingTimeInterval(min(hours * 3600, RealDiskGate.maxValidity) - 5))
    }

    /// Directory 0700 and file 0600, written to a temporary name and renamed into place; a symlink in the
    /// way is refused. Ownership is the writer's: root in the helper.
    public static func write(_ a: RealDiskGate.Authorization, to path: String = RealDiskGate.authorizationPath) throws {
        let fm = FileManager.default
        let dir = (path as NSString).deletingLastPathComponent
        var st = stat()
        if lstat(dir, &st) == 0 {
            guard (st.st_mode & S_IFMT) == S_IFDIR else { throw SafetyRefusal("\(dir) is not a directory") }
            guard st.st_uid == geteuid() else { throw SafetyRefusal("\(dir) is not owned by the helper") }
        } else {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        chmod(dir, 0o700)
        if lstat(path, &st) == 0, (st.st_mode & S_IFMT) != S_IFREG { throw SafetyRefusal("\(path) is not a regular file") }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(a)
        let tmp = dir + "/.authorization-\(UUID().uuidString)"
        let fd = Darwin.open(tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw SafetyRefusal("can't create the authorization file (\(String(cString: strerror(errno))))") }
        let ok = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) == $0.count } && fsync(fd) == 0
        close(fd)
        guard ok, rename(tmp, path) == 0 else { unlink(tmp); throw SafetyRefusal("can't write the authorization file") }
    }

    public static func remove(_ path: String = RealDiskGate.authorizationPath) { unlink(path) }
}

/// The stage 1 the installer app accepts (preview7): stage 1 v2, m1n1 121fcbf + the SiliconForest patch + the A/B
/// try-once slot choice (abboot), tag `121fcbf…-siliconforest-stage1-v2`, rebuilt byte-identical by
/// integrations/siliconforest/m1-native-boot/install/abboot/build_stage1_v2.sh. v1 (`44c1ef0b…`, previews 1–6)
/// is no longer accepted.
public enum StagePin {
    public static let stage1SHA256 = "c4be30876d39f7416145e56f56b021bc96e54c3b35899be12658a4406421994d"
    /// The v1 stage 1 of previews 1–6, kept only to say so in the refusal.
    public static let stage1V1SHA256 = "44c1ef0bda96224f5fe8c6228cc12ec1966b7781f38844cea960b21b47654318"
    public static let stage1Bytes: Int64 = 4_325_376

    public static func check(_ m: ReleaseManifest) throws {
        guard let a = m.artifact(m.stage1) else { throw SafetyRefusal("the release has no stage 1") }
        guard a.sha256 == stage1SHA256, a.bytes == stage1Bytes else {
            throw SafetyRefusal("the release's stage 1 is \(a.sha256.prefix(8))…\(a.sha256 == stage1V1SHA256 ? " (v1)" : ""), not the pinned v2 \(stage1SHA256.prefix(8))…")
        }
    }
}
