// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// What the grower may write to: a plain file, or a disk device that `hdiutil info` lists as an
// attached disk image. Nothing else. DiskArbitration is used only to find and refuse mounted or busy
// targets, to unmount on request, and to claim the disk so nothing mounts it during the grow.
// There is no real-disk path here; S48 on a real disk goes through the helper's gate (SFEngine).

import DiskArbitration
import Foundation

public final class Target {
    public enum Kind: Equatable { case file, diskImage(imagePath: String, bsdName: String) }
    public let requestedPath: String
    public let ioPath: String
    public let kind: Kind
    let claim: DiskClaim?

    init(requestedPath: String, ioPath: String, kind: Kind, claim: DiskClaim?) {
        self.requestedPath = requestedPath; self.ioPath = ioPath; self.kind = kind; self.claim = claim
    }

    public func release() { claim?.release() }
    public var describe: String {
        switch kind {
        case .file: return "file \(ioPath)"
        case let .diskImage(img, bsd): return "/dev/\(bsd), attached disk image \(img) (I/O through \(ioPath))"
        }
    }
}

public enum TargetGuard {
    /// Images attached right now: whole-disk BSD name ("disk8") -> image path, from `hdiutil info -plist`.
    public static func attachedImages() throws -> [String: String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = ["info", "-plist"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw Ext4Error("target", "hdiutil info failed")
        }
        var map: [String: String] = [:]
        for img in plist["images"] as? [[String: Any]] ?? [] {
            guard let path = img["image-path"] as? String else { continue }
            for e in img["system-entities"] as? [[String: Any]] ?? [] {
                if let dev = e["dev-entry"] as? String, let bsd = wholeDisk(dev) { map[bsd] = path }
            }
        }
        return map
    }

    /// "/dev/rdisk8s2" -> ("disk8", "disk8s2"); nil for anything else.
    public static func parse(_ path: String) -> (whole: String, bsd: String)? {
        var name = path
        guard name.hasPrefix("/dev/") else { return nil }
        name.removeFirst(5)
        if name.hasPrefix("r") { name.removeFirst() }
        guard name.hasPrefix("disk") else { return nil }
        let rest = name.dropFirst(4)
        let parts = rest.split(separator: "s", maxSplits: 1, omittingEmptySubsequences: false)
        guard let n = parts.first, !n.isEmpty, n.allSatisfy(\.isNumber) else { return nil }
        if parts.count == 2 { guard !parts[1].isEmpty, parts[1].allSatisfy(\.isNumber) else { return nil } }
        return ("disk" + n, name)
    }

    static func wholeDisk(_ dev: String) -> String? { parse(dev)?.whole }

    /// Mounted filesystems whose source is this disk or one of its slices.
    public static func mounts(of whole: String) -> [String] {
        var ptr: UnsafeMutablePointer<statfs>?
        let n = getmntinfo(&ptr, MNT_NOWAIT)
        guard n > 0, let mnts = ptr else { return [] }
        var out: [String] = []
        for i in 0..<Int(n) {
            var m = mnts[i]
            let from = withUnsafeBytes(of: &m.f_mntfromname) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            let on = withUnsafeBytes(of: &m.f_mntonname) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            if from == "/dev/\(whole)" || from.hasPrefix("/dev/\(whole)s") { out.append(on) }
        }
        return out
    }

    public static func resolve(_ path: String, unmount: Bool = false) throws -> Target {
        if path.hasPrefix("/dev/") {
            guard let (whole, bsd) = parse(path) else { throw Ext4Error("target", "\(path) is not a disk device name") }
            guard let image = try attachedImages()[whole] else {
                throw Ext4Error("not-disk-image", "/dev/\(whole) is not an attached disk image (hdiutil info); real disks are refused")
            }
            var mounted = mounts(of: whole)
            if !mounted.isEmpty {
                guard unmount else { throw Ext4Error("mounted", "/dev/\(whole) is mounted at \(mounted.joined(separator: ", ")); pass --unmount") }
                try DiskClaim.unmount(bsd: bsd, whole: bsd == whole)
                mounted = mounts(of: whole)
                guard mounted.isEmpty else { throw Ext4Error("busy", "/dev/\(whole) is still mounted at \(mounted.joined(separator: ", "))") }
            }
            let claim = try DiskClaim(bsd: bsd)
            // The image must still be the one we checked (no detach/reattach in between).
            guard try attachedImages()[whole] == image else { claim.release(); throw Ext4Error("target", "/dev/\(whole) changed while claiming") }
            return Target(requestedPath: path, ioPath: "/dev/r\(bsd)", kind: .diskImage(imagePath: image, bsdName: bsd), claim: claim)
        }
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        var st = stat()
        guard stat(url.path, &st) == 0 else { throw Ext4Error("target", "cannot stat \(path)") }
        guard st.st_mode & S_IFMT == S_IFREG else { throw Ext4Error("target", "\(path) is not a regular file") }
        if try attachedImages().values.contains(where: { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path == url.path }) {
            throw Ext4Error("busy", "\(path) is attached as a disk image; detach it or grow the /dev node instead")
        }
        return Target(requestedPath: path, ioPath: url.path, kind: .file, claim: nil)
    }
}

/// A DiskArbitration claim on one disk, held for the length of the grow.
final class DiskClaim {
    private let session: DASession
    private let disk: DADisk
    private static let queue = DispatchQueue(label: "org.siliconforest.ext4grow.da")
    private var released = false

    final class Box { var dissenter: String?; let sem = DispatchSemaphore(value: 0) }

    init(bsd: String) throws {
        guard let s = DASessionCreate(kCFAllocatorDefault) else { throw Ext4Error("busy", "DiskArbitration session failed") }
        session = s
        DASessionSetDispatchQueue(s, DiskClaim.queue)
        guard let d = DADiskCreateFromBSDName(kCFAllocatorDefault, s, bsd) else { throw Ext4Error("busy", "no disk \(bsd)") }
        disk = d
        let box = Box()
        let ctx = Unmanaged.passRetained(box).toOpaque()
        DADiskClaim(d, DADiskClaimOptions(kDADiskClaimOptionDefault), nil, nil, { _, dissenter, ctx in
            let b = Unmanaged<DiskClaim.Box>.fromOpaque(ctx!).takeRetainedValue()
            if let dis = dissenter { b.dissenter = "status \(DADissenterGetStatus(dis))" }
            b.sem.signal()
        }, ctx)
        guard box.sem.wait(timeout: .now() + 30) == .success else { throw Ext4Error("busy", "DiskArbitration did not answer the claim for \(bsd)") }
        if let why = box.dissenter { throw Ext4Error("busy", "\(bsd) is claimed or busy (\(why))") }
    }

    static func unmount(bsd: String, whole: Bool) throws {
        guard let s = DASessionCreate(kCFAllocatorDefault) else { throw Ext4Error("busy", "DiskArbitration session failed") }
        DASessionSetDispatchQueue(s, queue)
        defer { DASessionSetDispatchQueue(s, nil) }
        guard let d = DADiskCreateFromBSDName(kCFAllocatorDefault, s, bsd) else { throw Ext4Error("busy", "no disk \(bsd)") }
        let box = Box()
        let ctx = Unmanaged.passRetained(box).toOpaque()
        DADiskUnmount(d, DADiskUnmountOptions(whole ? kDADiskUnmountOptionWhole : kDADiskUnmountOptionDefault), { _, dissenter, ctx in
            let b = Unmanaged<DiskClaim.Box>.fromOpaque(ctx!).takeRetainedValue()
            if let dis = dissenter { b.dissenter = "status \(DADissenterGetStatus(dis))" }
            b.sem.signal()
        }, ctx)
        guard box.sem.wait(timeout: .now() + 30) == .success else { throw Ext4Error("busy", "unmount of \(bsd) timed out") }
        if let why = box.dissenter { throw Ext4Error("busy", "\(bsd) could not be unmounted (\(why)); it is in use") }
    }

    func release() {
        guard !released else { return }
        released = true
        DADiskUnclaim(disk)
        DASessionSetDispatchQueue(session, nil)
    }

    deinit { release() }
}
