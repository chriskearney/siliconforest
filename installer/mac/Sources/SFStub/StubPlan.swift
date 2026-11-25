// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// The stub's content, as an ordered list of actions. Ported from Asahi Linux installer v0.9.2
// (tag v0.9.2, commit dffbb38e): src/stub.py StubInstaller.install_files and copy_admin_users,
// src/util.py PackageInstaller.extract/extract_tree, and the boot-object write in src/osinstall.py
// OSInstaller.install via src/m1n1.py build. Copyright (c) 2021 The Asahi Linux contributors, MIT
// (LICENSES/third-party/asahi-installer-LICENSE.txt).
//
// Deliberate differences (ENGINE.md section 10, DESIGN.md section 6.4):
//  - Planning is pure: the plan is computed from the restore image's directory and plists, and every member
//    it names is downloaded and checked (StubStager) before the first write to the stub (DESIGN D6).
//  - What upstream copies from its own package (logo, step2 app, step2.sh, IAPhysicalMedia.plist, the
//    m1n1 object) comes in as a StubPayload. SiliconForest ships its own; the differential test feeds
//    upstream's so the two trees can be compared exactly.
//  - Full IPSW (Erase) only; upstream's OTA paths (AssetData/, BXDIFF50 recompression) are not ported.
//  - Firmware collection (StubInstaller.collect_firmware) is not part of the stub: SFFirmware owns it.

import Foundation

public enum StubVolume: String, Sendable, CaseIterable, Codable {
    case system = "System", data = "Data", preboot = "Preboot", recovery = "Recovery"
}

/// A path inside one of the stub's volumes. `path` is relative to the volume root ("" is the root).
public struct StubPath: Hashable, Sendable, CustomStringConvertible {
    public var volume: StubVolume
    public var path: String
    public init(_ volume: StubVolume, _ path: String) { self.volume = volume; self.path = path }
    public func appending(_ p: String) -> StubPath {
        StubPath(volume, path.isEmpty ? p : (p.isEmpty ? path : path + "/" + p))
    }
    public var description: String { "\(volume.rawValue):/\(path)" }
}

public enum StubToken: Sendable, Equatable {
    case vgid, prebootVolumeUUID
    case literal(String)
}

/// The non-Apple files the stub carries. Upstream's came from its own package directory.
public struct StubPayload: Sendable {
    /// `.VolumeIcon.icns` (upstream: `logo.icns`, copied with its mode).
    public var volumeIcon: URL
    /// The recovery app bundle, copied like `shutil.copytree` (modes and flags kept, symlinks followed).
    public var appSource: URL
    public var appName: String
    /// A script written into the app with tokens substituted, then made 0755 (upstream: step2.sh).
    public var script: (pathInApp: String, template: URL, tokens: [String: StubToken])?
    /// `.IAPhysicalMedia` (copied with its mode).
    public var physicalMedia: URL
    /// The boot object (m1n1 stage 1) and its variables, written into the app (upstream: osinstall's m1n1.build).
    public var bootObject: (pathInApp: String, stage1: URL, variables: [String])?

    public init(volumeIcon: URL, appSource: URL, appName: String, script: (pathInApp: String, template: URL, tokens: [String: StubToken])?,
                physicalMedia: URL, bootObject: (pathInApp: String, stage1: URL, variables: [String])?) {
        self.volumeIcon = volumeIcon; self.appSource = appSource; self.appName = appName; self.script = script
        self.physicalMedia = physicalMedia; self.bootObject = bootObject
    }
}

/// Where the stub's volumes are and who they are. Built by the volume-preparation step.
public struct StubTarget: Sendable {
    public var roots: [StubVolume: URL]
    /// The volume group UUID (the Data and System volumes' group).
    public var vgid: String
    /// The Preboot volume's own UUID (upstream: preboot_vgid, substituted for ##PREBOOT##).
    public var prebootVolumeUUID: String
    public init(roots: [StubVolume: URL], vgid: String, prebootVolumeUUID: String) {
        self.roots = roots; self.vgid = vgid; self.prebootVolumeUUID = prebootVolumeUUID
    }
}

public enum StubAction: Sendable, CustomStringConvertible {
    /// os.makedirs(exist_ok=True): mode 0777 less the umask, parents too.
    case mkdir(StubPath)
    /// A restore-image member written to a file (open "wb": mode 0666 less the umask).
    case member(String, StubPath)
    /// A symlink whose target is the bytes of a restore-image member (extract_tree's symlink case).
    case memberSymlink(String, StubPath)
    /// Bytes written to a file (open "wb").
    case bytes(Data, StubPath, label: String)
    /// shutil.copy: contents, then the source's mode bits.
    case copyFile(URL, StubPath)
    /// shutil.copytree.
    case copyTree(URL, StubPath)
    /// A template with tokens replaced, then chmod 0755.
    case script(URL, [String: StubToken], StubPath)
    /// m1n1.build: stage 1 + the variables, one per line, then four NULs.
    case bootObject(URL, [String], StubPath)
    /// A symlink to the absolute path of another stub path as mounted now (upstream's System/Restore link).
    case symlinkToMounted(StubPath, at: StubPath)
    /// A member compressed into the file with decmpfs LZFSE (util.py stream_compress), CRC-checked after.
    case compressedMember(String, StubPath)
    case setXattr(String, Data, StubPath)
    /// chflags with a flag word; `clear` removes it.
    case chflags(UInt32, clear: Bool, StubPath, ifExists: Bool)
    case removeIfExists(StubPath)
    case setBootable(StubVolume)

    public var description: String {
        switch self {
        case .mkdir(let p): return "mkdir \(p)"
        case .member(let m, let p): return "extract \(m) -> \(p)"
        case .memberSymlink(let m, let p): return "symlink(member \(m)) \(p)"
        case .bytes(_, let p, let l): return "write \(l) -> \(p)"
        case .copyFile(let u, let p): return "copy \(u.lastPathComponent) -> \(p)"
        case .copyTree(let u, let p): return "copytree \(u.lastPathComponent) -> \(p)"
        case .script(let u, _, let p): return "script \(u.lastPathComponent) -> \(p)"
        case .bootObject(_, let v, let p): return "boot object (\(v.count) vars) -> \(p)"
        case .symlinkToMounted(let t, let p): return "symlink \(p) -> <mounted \(t)>"
        case .compressedMember(let m, let p): return "compress(lzfse) \(m) -> \(p)"
        case .setXattr(let n, _, let p): return "xattr \(n) \(p)"
        case .chflags(let f, let c, let p, _): return "chflags \(c ? "clear " : "")0x\(String(f, radix: 16)) \(p)"
        case .removeIfExists(let p): return "rm -f \(p)"
        case .setBootable(let v): return "fsctl APFSIOC_VOL_BOOTABLE \(v.rawValue)"
        }
    }
}

public enum StubPlanner {
    /// The FinderInfo upstream sets on the System volume root so the icon shows (kHasCustomIcon).
    public static let finderInfo: Data = {
        var d = Data(count: 32); d[8] = 0x04; return d
    }()
    public static let SF_IMMUTABLE: UInt32 = 0x0002_0000   // schg

    /// The ordered actions of upstream's install_files (+ copy_admin_users, + the boot object).
    public static func plan(image: RestoreImage, target vgid: String, payload: StubPayload, adminUsers: URL) throws -> [StubAction] {
        guard let bless2 = image.bootcaches["bless2"], let rbp = bless2["RestoreBundlePath"]?.string else {
            throw StubError("bootcaches.plist has no bless2.RestoreBundlePath")
        }
        guard let baseSystem = image.baseSystemMember else { throw StubError("the identity names no BaseSystem") }
        let sys = StubPath(.system, ""), pbVGID = StubPath(.preboot, vgid)
        let cs = sys.appending("System/Library/CoreServices")
        var a: [StubAction] = []

        func extract(_ member: String, into dir: StubPath) {          // util.py extract(): makedirs(dirname), then write
            let dest = dir.appending(member)
            a.append(.mkdir(StubPath(dest.volume, (dest.path as NSString).deletingLastPathComponent)))
            a.append(.member(member, dest))
        }
        func extractTree(_ prefix: String, into dest: StubPath) throws { // util.py extract_tree(), in directory order
            let src = prefix.hasSuffix("/") ? prefix : prefix + "/"
            for e in image.zip.entries where e.name.hasPrefix(src) {
                let sub = String(e.name.dropFirst(src.count))
                guard !sub.hasPrefix("/") else { throw StubError("absolute path in \(e.name)") }
                guard !sub.split(separator: "/").contains("..") else { throw StubError("\(e.name) climbs out of its tree") }
                let d = dest.appending(sub.hasSuffix("/") ? String(sub.dropLast()) : sub)
                if e.isDirectory { a.append(.mkdir(d)) }
                else if e.isSymlink { a.append(.memberSymlink(e.name, d)) }
                else { a.append(.member(e.name, d)) }
            }
        }

        // System volume
        extract("usr/standalone/bootcaches.plist", into: sys)
        a.append(.copyFile(payload.volumeIcon, sys.appending(".VolumeIcon.icns")))
        a.append(.mkdir(cs))
        extract("PlatformSupport.plist", into: cs)
        a.append(.setXattr("com.apple.FinderInfo", finderInfo, sys))
        a.append(.setBootable(.system))

        // Data volume
        a.append(.mkdir(StubPath(.data, "private/var/db/dslocal")))

        // Preboot volume
        a.append(.mkdir(pbVGID))
        let rb = pbVGID.appending(rbp)          // "./Restore", kept literally as upstream's os.path.join did
        a.append(.mkdir(rb))
        a.append(.bytes(try PythonPlistWriter.write(image.trimmedManifest), rb.appending("BuildManifest.plist"), label: "BuildManifest.plist (this identity only)"))
        extract("SystemVersion.plist", into: rb)
        extract("RestoreVersion.plist", into: rb)
        extract("usr/standalone/bootcaches.plist", into: rb)
        try extractTree("BootabilityBundle/Restore/Bootability", into: rb.appending("Bootability"))
        a.append(.member("BootabilityBundle/Restore/Firmware/Bootability.dmg.trustcache", rb.appending("Bootability/Bootability.trustcache")))
        try extractTree("Firmware/Manifests/restore/\(image.profile.identity.variant)/", into: rb)
        for m in image.restoreBundleMembers { extract(m, into: rb) }

        // copy_admin_users
        let au = pbVGID.appending("var/db/AdminUserRecoveryInfo.plist")
        a.append(.mkdir(pbVGID.appending("var/db")))
        a.append(.chflags(SF_IMMUTABLE, clear: true, au, ifExists: true))
        a.append(.copyFile(adminUsers, au))
        a.append(.chflags(SF_IMMUTABLE, clear: false, au, ifExists: false))

        // The System/Restore link to the Preboot restore bundle (upstream's macOS <12 workaround)
        a.append(.removeIfExists(sys.appending(rbp)))
        a.append(.symlinkToMounted(rb, at: sys.appending(rbp)))

        // Recovery volume
        let recVGID = StubPath(.recovery, vgid)
        a.append(.mkdir(recVGID))
        let fw = recVGID.appending("usr/standalone/firmware")
        a.append(.mkdir(fw))
        a.append(.compressedMember(baseSystem, fw.appending("arm64eBaseSystem.dmg")))

        // Wrapping up
        guard case .dict(var sv) = image.systemVersion, let uv = sv["ProductUserVisibleVersion"]?.string else {
            throw StubError("SystemVersion.plist has no ProductUserVisibleVersion")
        }
        sv["ProductUserVisibleVersion"] = .string(uv + " (stub)")
        a.append(.bytes(try PythonPlistWriter.write(.dict(sv)), cs.appending("SystemVersion.plist"), label: "SystemVersion.plist (stub)"))
        a.append(.removeIfExists(cs.appending("SystemVersion-disabled.plist")))
        let app = sys.appending(payload.appName)
        a.append(.copyTree(payload.appSource, app))
        if let s = payload.script { a.append(.script(s.template, s.tokens, app.appending(s.pathInApp))) }
        a.append(.copyFile(payload.physicalMedia, sys.appending(".IAPhysicalMedia")))
        a.append(.removeIfExists(sys.appending("IAPhysicalMedia-disabled.plist")))
        if let b = payload.bootObject { a.append(.bootObject(b.stage1, b.variables, app.appending(b.pathInApp))) }
        return a
    }

    /// Every restore-image member the plan reads, with its directory entry, for staging and sizing.
    public static func members(of plan: [StubAction], in zip: ZipReader) throws -> [ZipEntry] {
        var seen = Set<String>(), out: [ZipEntry] = []
        for act in plan {
            let name: String
            switch act {
            case .member(let m, _), .memberSymlink(let m, _), .compressedMember(let m, _): name = m
            default: continue
            }
            if seen.insert(name).inserted { out.append(try zip.require(name)) }
        }
        return out
    }
}
