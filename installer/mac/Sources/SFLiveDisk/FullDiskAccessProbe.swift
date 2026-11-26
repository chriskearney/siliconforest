// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// Preview10: the helper's harmless Full Disk Access probe. It opens the startup disk's raw device
// read-only and closes it at once (no read, no write); if the startup disk can't be named it opens a
// TCC-protected file read-only instead. EPERM/EACCES as root means macOS hasn't given SFHelper Full
// Disk Access. The install needs it: the GPT disk GUID (disk identity) is only on the raw device, and
// the install writes partitions through their raw devices.
//
// Raw-device users in the helper, all behind this check (planInstall, planRemoval, begin, resume and
// readTopology on the internal disk call `requireFullDiskAccess` first) and all typed through RawAccess:
//   SFLiveDisk/GPTDiskGUID.swift      GPTHeader.diskGUID: read-only, two blocks (disk identity)
//   SFLiveDisk/LiveChokepoint.swift   openRaw: partition raw reads/writes inside the protection receipt
//   SFLiveDisk/LiveDiskBackend.swift  newfs_msdos on /dev/r<partition> (a child of the helper; same TCC grant)

import Foundation
import SFEngine

public struct PrivilegeReport: Codable, Equatable, Sendable {
    public enum FullDiskAccess: String, Codable, Sendable { case granted, missing, unknown }
    public var fullDiskAccess: FullDiskAccess
    /// What was opened (a device or file path; never contents).
    public var probe: String
    /// strerror text when the probe failed.
    public var detail: String?
    public init(fullDiskAccess: FullDiskAccess, probe: String, detail: String? = nil) {
        self.fullDiskAccess = fullDiskAccess; self.probe = probe; self.detail = detail
    }
}

public enum FullDiskAccessProbe {
    /// Protected by TCC's SystemPolicyAllFiles on every supported macOS; exists on every Mac.
    public static let protectedFile = "/Library/Application Support/com.apple.TCC/TCC.db"

    public static func run(wholeDisk: () -> String? = { try? StartupDisk.wholeDisk() },
                           opener: (String, Int32) -> Int32 = { Darwin.open($0, $1) },
                           euid: uid_t = geteuid()) -> PrivilegeReport {
        var paths: [String] = []
        if let w = wholeDisk(), w.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil { paths.append("/dev/r\(w)") }
        paths.append(protectedFile)
        var last: PrivilegeReport?
        for p in paths {
            do {
                let fd = try RawAccess.open(p, O_RDONLY, opener: opener, euid: euid)
                close(fd)
                return PrivilegeReport(fullDiskAccess: .granted, probe: p)
            } catch let d as FullDiskAccessDenied {
                return PrivilegeReport(fullDiskAccess: .missing, probe: p, detail: String(cString: strerror(d.code)))
            } catch {
                last = PrivilegeReport(fullDiskAccess: .unknown, probe: p, detail: RawAccess.message(error))
            }
        }
        return last ?? PrivilegeReport(fullDiskAccess: .unknown, probe: "")
    }
}
