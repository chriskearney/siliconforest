import Foundation
import SFEngine
import SFInstallKit

/// What a live backend is allowed to be pointed at.
public enum LiveTargetKind: Sendable, Equatable {
    /// A disk image the installer attached itself, under the allowed directory (tests, rehearsal).
    case diskImage(path: String)
    /// The Mac's internal disk, named by its GPT UUID. Only `InternalDiskAuthority` makes one, and that
    /// type exists only in a build with `SF_REAL_DISK_WRITES`.
    case internalDisk(diskUUID: String)
}

/// Proves, at the moment of use, that a device belongs to the one disk this job may write to. The
/// first of the live backend's three independent checks (the other two: the protection receipt and
/// the engine's gate).
public protocol TargetAuthority: Sendable {
    var kind: LiveTargetKind { get }
    /// Read-only queries (`diskutil list/info`, `hdiutil info`) run through this.
    var query: ToolRunner { get }
    /// For the journal: image path, or "internal disk <uuid>".
    var label: String { get }
    /// The target's physical whole disk now, found by identity and never by a remembered diskN.
    func wholeDisk() throws -> String
    /// Throws `SafetyRefusal` unless `device` (partition, whole disk or synthesised APFS disk) is part of the target.
    func authorize(_ device: String) throws
    /// Fault injection only: power loss on an image. A real disk can't be detached.
    func detach(force: Bool) throws
    func attach() throws
}

/// The target is one attached disk image under an allowed directory. Every question goes through
/// `ImageGuard` first, so a device that is not this image never reaches `diskutil`.
public struct ImageTargetAuthority: TargetAuthority {
    public let imagePath: String
    public let imageGuard: ImageGuard
    public var query: ToolRunner { imageGuard.query }
    public var kind: LiveTargetKind { .diskImage(path: imagePath) }
    public var label: String { imagePath }

    public init(imagePath: URL, allowedRoot: URL = ImageGuard.defaultRoot, query: ToolRunner = ProcessToolRunner()) {
        self.imagePath = ImageGuard.resolve(imagePath.path)
        self.imageGuard = ImageGuard(allowedRoot: allowedRoot, query: query)
    }

    public func wholeDisk() throws -> String {
        let imgs = try imageGuard.attachedImages()
        guard let img = imgs.first(where: { ImageGuard.resolve($0.imagePath) == imagePath }) else {
            throw EngineError(.inconsistent, "the disk image is not attached", detail: imagePath)
        }
        guard let whole = img.partitionMapDisk else { throw EngineError(.inconsistent, "the image has no partition map") }
        return try imageGuard.authorize(whole).imageWholeDisk
    }

    public func authorize(_ device: String) throws {
        let a = try imageGuard.authorize(device)
        guard ImageGuard.resolve(a.imagePath) == imagePath else {
            throw SafetyRefusal("\(a.identifier) belongs to \(a.imagePath), not this job's image")
        }
    }

    public func detach(force: Bool) throws {
        let w = try wholeDisk()
        let r = try ProcessToolRunner().run(["/usr/bin/hdiutil", "detach", w] + (force ? ["-force"] : []))
        guard r.ok else { throw EngineError(.appleTool, "hdiutil detach failed", detail: r.err) }
    }

    public func attach() throws {
        guard imageGuard.isUnderAllowedRoot(imagePath) else { throw SafetyRefusal("image outside the allowed directory") }
        let r = try ProcessToolRunner().run(["/usr/bin/hdiutil", "attach", "-nomount", "-nobrowse", "-noverify", "-noautofsck", imagePath])
        guard r.ok else { throw EngineError(.appleTool, "hdiutil attach failed", detail: r.err) }
        // hdiutil can return before Disk Arbitration (and so diskutil) knows the new disk. Wait for it,
        // so the first question after a reattach doesn't see a half-attached image.
        let deadline = Date().addingTimeInterval(10)
        while (try? wholeDisk()) == nil, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        _ = try wholeDisk()
    }
}
