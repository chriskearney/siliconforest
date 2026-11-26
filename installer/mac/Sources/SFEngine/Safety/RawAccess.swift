// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// Preview10: every open of a raw device (`/dev/rdiskN…`) goes through here. On macOS even root needs
// Full Disk Access (TCC kTCCServiceSystemPolicyAllFiles) for SFHelper to open the internal disk's raw
// device; without it open(2) fails with EPERM. That failure used to surface as a generic "can't read"
// refusal deep inside planning. Now it is a typed error the app recognises and turns into the
// Privileges screen, and the helper's up-front probe uses the same open.

import Foundation

/// macOS refused a raw device or a TCC-protected file to this process (EPERM/EACCES while root).
public struct FullDiskAccessDenied: Error, LocalizedError, Equatable, Sendable {
    public var path: String
    public var code: Int32
    public init(path: String, code: Int32) { self.path = path; self.code = code }
    public var errorDescription: String? {
        "macOS denied SFHelper access to \(path) (\(String(cString: strerror(code)))). Turn on Full Disk Access for SFHelper in System Settings → Privacy & Security → Full Disk Access."
    }
}

public enum RawAccess {
    /// EPERM/EACCES as root on a raw device or a protected path is a privacy (TCC) denial, not a permissions bit.
    public static func isPrivacyDenial(_ e: Int32, euid: uid_t = geteuid()) -> Bool {
        euid == 0 && (e == EPERM || e == EACCES)
    }

    /// strerror text for an error `open` threw.
    public static func message(_ error: Error) -> String {
        if let p = error as? POSIXError { return String(cString: strerror(p.code.rawValue)) }
        return error.localizedDescription
    }

    /// open(2) with the denial typed. Returns the descriptor; the caller closes it.
    public static func open(_ path: String, _ flags: Int32,
                            opener: (String, Int32) -> Int32 = { Darwin.open($0, $1) },
                            euid: uid_t = geteuid()) throws -> Int32 {
        let fd = opener(path, flags)
        if fd >= 0 { return fd }
        let e = errno
        if isPrivacyDenial(e, euid: euid) { throw FullDiskAccessDenied(path: path, code: e) }
        throw POSIXError(POSIXErrorCode(rawValue: e) ?? .EIO)
    }
}
