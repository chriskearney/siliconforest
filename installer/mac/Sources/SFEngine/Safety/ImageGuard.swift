import Foundation

/// A device the guard has proved is backed by one of our disk images, at the moment of the check.
public struct AuthorizedDevice: Sendable, Hashable {
    /// "disk7s2", as asked.
    public var identifier: String
    /// The physical whole disk of the image ("disk7"), even for a synthesised APFS disk.
    public var imageWholeDisk: String
    /// Resolved path of the image file under the allowed directory.
    public var imagePath: String
}

/// THE safety check for every mutating command (DESIGN §14.11, ENGINE §12): the target must be
/// attached from a disk image under `allowedRoot`, and diskutil must agree it is a disk image whose
/// parent whole disk is that image. Internal, physical and synthesised-from-physical disks are
/// refused. The `hdiutil info` check runs first, so a disk that is not one of our images is refused
/// without diskutil ever being asked about it.
public struct ImageGuard: Sendable {
    public let allowedRoot: String
    public let query: ToolRunner
    public static let imageExtensions: Set<String> = ["sparseimage", "dmg", "sparsebundle"]

    public init(allowedRoot: URL, query: ToolRunner = ProcessToolRunner()) {
        self.allowedRoot = Self.resolve(allowedRoot.path)
        self.query = query
    }

    /// Default allowed directory: `installer/mac/.build-images` in the source tree.
    public static var defaultRoot: URL { SFEnginePaths.imagesDirectory }

    static func resolve(_ path: String) -> String {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(path, &buf) != nil else { return (path as NSString).standardizingPath }
        return String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// "disk5", "/dev/rdisk5s3" → ("disk5s3" form, whole "disk5"). Anything else is refused.
    public static func normalise(_ raw: String) throws -> (id: String, whole: String) {
        var s = raw
        if s.hasPrefix("/dev/") { s.removeFirst(5) }
        if s.hasPrefix("rdisk") { s.removeFirst() }
        guard s.range(of: #"^disk[0-9]+(s[0-9]+)?$"#, options: .regularExpression) != nil else {
            throw SafetyRefusal("not a disk identifier: \(raw)")
        }
        let digits = s.dropFirst(4).prefix { $0.isNumber }
        return (s, "disk\(digits)")
    }

    public struct AttachedImage: Sendable, Hashable {
        public var imagePath: String
        public var entities: Set<String>
        /// The entity carrying the partition map: the image's physical whole disk.
        public var partitionMapDisk: String?
    }

    /// Images attached right now (`hdiutil info -plist`).
    public func attachedImages() throws -> [AttachedImage] {
        let info = try Query.dict(query, ["/usr/bin/hdiutil", "info", "-plist"])
        return (info["images"] as? [[String: Any]] ?? []).compactMap { img in
            guard let path = img["image-path"] as? String else { return nil }
            let raw = img["system-entities"] as? [[String: Any]] ?? []
            let ents = raw.compactMap { ($0["dev-entry"] as? String).map { String($0.dropFirst(5)) } }
            let map = raw.first { $0["content-hint"] as? String == "GUID_partition_scheme" }.flatMap { ($0["dev-entry"] as? String).map { String($0.dropFirst(5)) } }
            return AttachedImage(imagePath: path, entities: Set(ents), partitionMapDisk: map)
        }
    }

    public func isUnderAllowedRoot(_ imagePath: String) -> Bool {
        let p = Self.resolve(imagePath)
        let ext = (p as NSString).pathExtension.lowercased()
        return p.hasPrefix(allowedRoot + "/") && Self.imageExtensions.contains(ext) && !p.contains("/../")
    }

    public func authorize(_ raw: String) throws -> AuthorizedDevice {
        let (id, whole) = try Self.normalise(raw)

        // 1. hdiutil: the device (and its whole disk) must be an entity of one attached image under the
        //    allowed directory. Nothing else is consulted before this passes.
        let images = try attachedImages()
        guard let img = images.first(where: { $0.entities.contains(id) }) else {
            throw SafetyRefusal("\(id) is not attached from a disk image")
        }
        guard img.entities.contains(whole) else { throw SafetyRefusal("\(id): its whole disk \(whole) is not part of the same image") }
        guard isUnderAllowedRoot(img.imagePath) else {
            throw SafetyRefusal("\(id) is backed by \(img.imagePath), outside \(allowedRoot)")
        }

        // 2. diskutil must agree: a virtual disk-image device, not internal, whose parent whole disk is
        //    in the same image, and (for a synthesised APFS disk) whose physical stores are too.
        let info = try Query.dict(query, ["/usr/sbin/diskutil", "info", "-plist", id])
        guard info["BusProtocol"] as? String == "Disk Image" else {
            throw SafetyRefusal("\(id): diskutil reports protocol \(info["BusProtocol"] as? String ?? "?"), not Disk Image")
        }
        // Partitions of an image carry no VirtualOrPhysical key; whole and synthesised disks must say Virtual.
        if let vp = info["VirtualOrPhysical"] as? String { guard vp == "Virtual" else { throw SafetyRefusal("\(id) is \(vp), not a virtual device") } }
        else if id == whole { throw SafetyRefusal("\(id) doesn't say it is virtual") }
        guard info["Internal"] as? Bool == false else { throw SafetyRefusal("\(id) is internal") }
        guard let parent = info["ParentWholeDisk"] as? String, img.entities.contains(parent) else {
            throw SafetyRefusal("\(id): parent whole disk is not in the image")
        }
        var imageWhole = parent
        if let stores = info["APFSPhysicalStores"] as? [[String: Any]] {
            let ids = stores.compactMap { $0["APFSPhysicalStore"] as? String }
            guard !ids.isEmpty else { throw SafetyRefusal("\(id): APFS disk without a physical store") }
            for s in ids {
                guard img.entities.contains(s), let w = try? Self.normalise(s).whole, img.entities.contains(w) else {
                    throw SafetyRefusal("\(id): APFS physical store \(s) is not in the image")
                }
                imageWhole = w
            }
        } else if parent != whole {
            throw SafetyRefusal("\(id): diskutil's parent \(parent) differs from \(whole)")
        }
        // The physical whole disk itself must say it is a disk image.
        if imageWhole != id {
            let w = try Query.dict(query, ["/usr/sbin/diskutil", "info", "-plist", imageWhole])
            guard w["BusProtocol"] as? String == "Disk Image", w["Internal"] as? Bool == false, w["WholeDisk"] as? Bool == true,
                  w["VirtualOrPhysical"] as? String == "Virtual" else {
                throw SafetyRefusal("\(imageWhole) is not a whole disk image")
            }
        }
        return AuthorizedDevice(identifier: id, imageWholeDisk: imageWhole, imagePath: Self.resolve(img.imagePath))
    }
}

public enum SFEnginePaths {
    /// installer/mac/.build-images (git-ignored).
    public static var imagesDirectory: URL {
        URL(fileURLWithPath: #filePath)     // …/installer/mac/Sources/SFEngine/Safety/ImageGuard.swift
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build-images", isDirectory: true)
    }
}
