// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// Preview7: the shipped app's helper selects the stub this install created as the startup disk (S65),
// and a removal resets the startup disk to macOS if the selection points at SiliconForest (U10).
// Preview13 (Chris, 26 November 2026): S65 is a PERSISTENT selection (`--setBoot`, no `--nextonly`), as Asahi's
// installer does (docs/installer/RESEARCH.md), so that the next boot the person starts from startup options is
// the stub's one true recoveryOS. `--nextonly` stays only in SFRecoveryKit's R50. The engine never runs a tool itself: it builds an argument list here, from the plan's own
// partitions, and hands it to an injectable `BlessRunner`. No runner (the default; every lab tool and
// every test) means the old behaviour: the command is journaled as simulated and nothing runs.

import Foundation
import SFInstallKit

public struct BlessResult: Sendable, Equatable {
    public var status: Int32
    public var output: String
    public init(status: Int32, output: String) { self.status = status; self.output = output }
}

public protocol BlessRunner: Sendable {
    func execute(_ argv: [String]) -> BlessResult
}

/// Preview13: bytes that live in locked memory and are zeroed on `wipe()` (SFHelperKit's `SecureBytes`).
public protocol SecretBytesProvider: AnyObject, Sendable {
    func withBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R
    func wipe()
}

/// A volume owner's login for `bless` on Apple Silicon (owner authentication). Only the short name is ever
/// logged or journaled; the password is never printed, stored or journaled, and is wiped after one use.
public final class BlessCredential: @unchecked Sendable {
    public let owner: String
    public let secret: any SecretBytesProvider
    public init(owner: String, secret: any SecretBytesProvider) { self.owner = owner; self.secret = secret }
}

/// A runner that can send a password on `bless`'s standard input (`--user <owner> --stdinpass`), and only that.
public protocol PasswordBlessRunner: BlessRunner {
    func execute(_ argv: [String], password: any SecretBytesProvider) -> BlessResult
}

public enum BlessGuard {
    public static let tool = "/usr/sbin/bless"

    public struct Refusal: Error, CustomStringConvertible, Sendable {
        public var reason: String
        public var description: String { reason }
        init(_ r: String) { reason = r }
    }

    /// `/dev/disk3s1s1` (the sealed snapshot `/` is mounted from) → `disk3s1`; `/dev/disk7s1` → `disk7s1`.
    public static func baseVolume(mountedFrom raw: String) throws -> String {
        var s = raw
        if s.hasPrefix("/dev/") { s.removeFirst(5) }
        guard s.range(of: #"^disk[0-9]+s[0-9]+(s[0-9]+)?$"#, options: .regularExpression) != nil else { throw Refusal("not an APFS volume device: \(raw)") }
        if s.range(of: #"^disk[0-9]+s[0-9]+s[0-9]+$"#, options: .regularExpression) != nil, let cut = s.range(of: "s", options: .backwards) { s = String(s[..<cut.lowerBound]) }
        return s
    }

    /// statfs(2)'s device for a mount point.
    public static func systemMountedFrom(_ path: String) -> String? {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return nil }
        return withUnsafeBytes(of: fs.f_mntfromname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    /// A mount point of an APFS volume (by its disk identifier, snapshot suffix ignored), from the kernel's mount
    /// table. Read-only: it never mounts anything (the protection receipt forbids mounting macOS's container).
    public static func systemMountPoint(ofVolume identifier: String) -> String? {
        let n = getfsstat(nil, 0, MNT_NOWAIT)
        guard n > 0 else { return nil }
        var buf = Array(repeating: statfs(), count: Int(n))
        let got = getfsstat(&buf, Int32(MemoryLayout<statfs>.stride * Int(n)), MNT_NOWAIT)
        guard got > 0 else { return nil }
        for fs in buf.prefix(Int(got)) {
            let from = withUnsafeBytes(of: fs.f_mntfromname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            let on = withUnsafeBytes(of: fs.f_mntonname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            if (try? baseVolume(mountedFrom: from)) == identifier, on == "/" || on.hasPrefix("/Volumes/") { return on }
        }
        return nil
    }

    static func safePath(_ p: String) -> Bool {
        p.hasPrefix("/") && !p.contains("..") && !p.contains("//") && p.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7f } && p.utf8.count < 1024
    }

    /// The selection of the stub this install created: `bless --mount <its System volume> --setBoot` (persistent, no
    /// `--nextonly`), with `--user <owner> --stdinpass` when a volume owner's login is given. Refused unless the mount
    /// point is a /Volumes mount of the stub container's System volume.
    public static func setStartupDisk(mount: URL, stub: ImagePartition, owner: String? = nil, mountedFrom: (String) -> String?) throws -> [String] {
        let p = mount.path
        guard safePath(p), p.hasPrefix("/Volumes/"), p.count > "/Volumes/".count else { throw Refusal("the stub's mount point isn't a volume under /Volumes: \(p)") }
        guard let apfs = stub.apfs, let sys = apfs.volumes.first(where: { $0.roles.contains("System") }) else { throw Refusal("the stub has no System volume") }
        guard let dev = mountedFrom(p), (try? baseVolume(mountedFrom: dev)) == sys.identifier else {
            throw Refusal("\(p) isn't the stub's System volume (\(sys.identifier))")
        }
        return [tool, "--mount", p, "--setBoot"] + (try ownerArguments(owner))
    }

    /// `--user <owner> --stdinpass`: the owner's password goes on stdin, never on the command line.
    static func ownerArguments(_ owner: String?) throws -> [String] {
        guard let owner else { return [] }
        guard validOwner(owner) else { throw Refusal("not a valid user name for bless: \(owner)") }
        return ["--user", owner, "--stdinpass"]
    }

    /// A macOS short account name: letters, digits, dot, underscore, hyphen. Nothing that could be an option or a path.
    public static func validOwner(_ s: String) -> Bool {
        s.range(of: #"^[A-Za-z0-9._][A-Za-z0-9._-]{0,63}$"#, options: .regularExpression) != nil
    }

    /// The command sends a password on stdin.
    public static func usesPassword(_ argv: [String]) -> Bool { argv.contains("--stdinpass") }

    /// bless's output with the password (and its line) removed, in case a tool ever echoes it.
    public static func scrub(_ text: String, password: String) -> String {
        guard !password.isEmpty else { return text }
        return text.replacingOccurrences(of: password, with: "•••")
    }

    /// bless said the account isn't allowed to change the startup disk, or needs a password.
    public static func looksLikeOwnerAuthFailure(_ output: String) -> Bool {
        let o = output.lowercased()
        return o.contains("owner authentication") || o.contains("authentication required") || o.contains("not authorized") || o.contains("incorrect password")
    }

    public static let getBoot = [tool, "--getBoot"]

    /// Removal: back to macOS. `mount` is the macOS container's System volume ("/" for the running startup volume,
    /// or its /Volumes mount); it must resolve to that container's System volume.
    public static func restoreBoot(mount: String, macOS: ImagePartition, owner: String? = nil, mountedFrom: (String) -> String?) throws -> [String] {
        guard safePath(mount), mount == "/" || mount.hasPrefix("/Volumes/") else { throw Refusal("not a volume mount: \(mount)") }
        guard let apfs = macOS.apfs, let sys = apfs.volumes.first(where: { $0.roles.contains("System") }) else { throw Refusal("the macOS container has no System volume") }
        guard let dev = mountedFrom(mount), (try? baseVolume(mountedFrom: dev)) == sys.identifier else {
            throw Refusal("\(mount) isn't macOS's System volume (\(sys.identifier))")
        }
        return [tool, "--mount", mount, "--setBoot"] + (try ownerArguments(owner))
    }

    /// The shapes a runner may execute, and nothing else: `--getBoot`; `--mount <"/" or /Volumes/x> --setBoot`; and the
    /// same with `--user <owner> --stdinpass` (the owner's login on stdin). `--nextonly` is not one of them: the
    /// helper never sets a one-time boot (SFRecoveryKit's R50 does, in recoveryOS, with its own tools).
    public static func isAllowed(_ argv: [String]) -> Bool {
        guard argv.first == tool else { return false }
        if argv == getBoot { return true }
        guard argv.count == 4 || argv.count == 7, argv[1] == "--mount", safePath(argv[2]), argv[3] == "--setBoot",
              argv[2] == "/" || argv[2].hasPrefix("/Volumes/") else { return false }
        if argv.count == 7 { return argv[4] == "--user" && validOwner(argv[5]) && argv[6] == "--stdinpass" }
        return true
    }

    /// Whether `bless --getBoot`'s output names this volume (its /dev node, the volume's identifier, or its mount point).
    public static func names(getBootOutput out: String, volume: ImageVolume, mount: String?) -> Bool {
        let o = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !o.isEmpty else { return false }
        return (mount.map { $0 != "/" && o.contains($0) } ?? false)
            || o.range(of: #"(?<![A-Za-z0-9])"# + NSRegularExpression.escapedPattern(for: volume.identifier) + #"(?![0-9])"#, options: .regularExpression) != nil
    }

    /// What the person runs themselves when bless failed.
    public static func manual(mountPath: String) -> String { "sudo /usr/sbin/bless --mount \"\(mountPath)\" --setBoot" }
    public static func manual(volumeName: String) -> String { "sudo /usr/sbin/bless --mount \"/Volumes/\(volumeName)\" --setBoot" }
}
