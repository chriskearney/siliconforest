import Foundation

/// GPT partition content as diskutil reports it (`Content` in `diskutil list -plist`).
public enum PartitionContent: String, Codable, Sendable, Hashable {
    case appleAPFSISC = "Apple_APFS_ISC"
    case appleAPFS = "Apple_APFS"
    case appleAPFSRecovery = "Apple_APFS_Recovery"
    case efi = "EFI"
    case linuxFilesystem = "Linux Filesystem"
    case microsoftBasicData = "Microsoft Basic Data"
    case unknown = "Unknown"

    public init(diskutil: String) {
        switch diskutil {
        case "Apple_APFS_ISC": self = .appleAPFSISC
        case "Apple_APFS": self = .appleAPFS
        case "Apple_APFS_Recovery": self = .appleAPFSRecovery
        case "EFI", "C12A7328-F81F-11D2-BA4B-00A0C93EC93B": self = .efi
        case "Linux Filesystem", "0FC63DAF-8483-4772-8E79-3D69D8477DE4": self = .linuxFilesystem
        case "Microsoft Basic Data", "DOS_FAT_32": self = .microsoftBasicData
        default: self = .unknown
        }
    }
}

public struct APFSVolume: Codable, Sendable, Hashable, Identifiable {
    public var identifier: String
    public var name: String
    public var roles: [String]
    public var capacityInUse: Int64
    public var fileVault: Bool
    public var locked: Bool

    public var id: String { identifier }

    public init(identifier: String, name: String, roles: [String] = [], capacityInUse: Int64 = 0, fileVault: Bool = false, locked: Bool = false) {
        self.identifier = identifier; self.name = name; self.roles = roles
        self.capacityInUse = capacityInUse; self.fileVault = fileVault; self.locked = locked
    }

    enum CodingKeys: String, CodingKey { case identifier, name, roles, capacityInUse, fileVault, locked }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try c.decode(String.self, forKey: .identifier)
        name = try c.decode(String.self, forKey: .name)
        roles = try c.decodeIfPresent([String].self, forKey: .roles) ?? []
        capacityInUse = try c.decodeIfPresent(Int64.self, forKey: .capacityInUse) ?? 0
        fileVault = try c.decodeIfPresent(Bool.self, forKey: .fileVault) ?? false
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
    }
}

public struct APFSContainer: Codable, Sendable, Hashable {
    /// Synthesised disk, e.g. "disk3".
    public var reference: String
    public var capacityCeiling: Int64
    public var capacityFree: Int64
    public var volumes: [APFSVolume]

    public init(reference: String, capacityCeiling: Int64, capacityFree: Int64, volumes: [APFSVolume]) {
        self.reference = reference; self.capacityCeiling = capacityCeiling; self.capacityFree = capacityFree; self.volumes = volumes
    }

    public var capacityUsed: Int64 { capacityCeiling - capacityFree }
    public var hasMacOSSystem: Bool { volumes.contains { $0.roles.contains("System") } }
    public var fileVaultOn: Bool { volumes.contains { $0.fileVault } }
}

public struct Partition: Codable, Sendable, Hashable, Identifiable {
    public var identifier: String
    public var offset: Int64
    public var size: Int64
    public var content: PartitionContent
    /// Volume or partition name (FAT label, APFS volume group name…).
    public var name: String?
    public var container: APFSContainer?
    /// Free-form facts the installer stamps on what it creates ("sf.version", "sf.installName").
    public var metadata: [String: String]

    public var id: String { identifier }
    public var end: Int64 { offset + size }

    public init(identifier: String, offset: Int64, size: Int64, content: PartitionContent, name: String? = nil,
                container: APFSContainer? = nil, metadata: [String: String] = [:]) {
        self.identifier = identifier; self.offset = offset; self.size = size; self.content = content
        self.name = name; self.container = container; self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey { case identifier, offset, size, content, name, container, metadata }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try c.decode(String.self, forKey: .identifier)
        offset = try c.decode(Int64.self, forKey: .offset)
        size = try c.decode(Int64.self, forKey: .size)
        content = try c.decode(PartitionContent.self, forKey: .content)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        container = try c.decodeIfPresent(APFSContainer.self, forKey: .container)
        metadata = try c.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }
}

public struct PhysicalDisk: Codable, Sendable, Hashable, Identifiable {
    public var identifier: String
    public var mediaName: String
    public var size: Int64
    public var blockSize: Int64
    public var isInternal: Bool
    /// Sorted by offset.
    public var partitions: [Partition]
    /// Bytes the GPT itself reserves at the start and end of the disk.
    public var reservedHead: Int64
    public var reservedTail: Int64

    public var id: String { identifier }

    public init(identifier: String, mediaName: String, size: Int64, blockSize: Int64 = 4096, isInternal: Bool = true,
                partitions: [Partition], reservedHead: Int64 = 24_576, reservedTail: Int64 = 20_480) {
        self.identifier = identifier; self.mediaName = mediaName; self.size = size; self.blockSize = blockSize
        self.isInternal = isInternal; self.partitions = partitions.sorted { $0.offset < $1.offset }
        self.reservedHead = reservedHead; self.reservedTail = reservedTail
    }

    enum CodingKeys: String, CodingKey { case identifier, mediaName, size, blockSize, isInternal, partitions, reservedHead, reservedTail }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(identifier: try c.decode(String.self, forKey: .identifier),
                  mediaName: try c.decodeIfPresent(String.self, forKey: .mediaName) ?? "Internal SSD",
                  size: try c.decode(Int64.self, forKey: .size),
                  blockSize: try c.decodeIfPresent(Int64.self, forKey: .blockSize) ?? 4096,
                  isInternal: try c.decodeIfPresent(Bool.self, forKey: .isInternal) ?? true,
                  partitions: try c.decode([Partition].self, forKey: .partitions),
                  reservedHead: try c.decodeIfPresent(Int64.self, forKey: .reservedHead) ?? 24_576,
                  reservedTail: try c.decodeIfPresent(Int64.self, forKey: .reservedTail) ?? 20_480)
    }

    /// Partitions plus the free gaps between them, in disk order.
    public var layout: [LayoutSegment] {
        var out: [LayoutSegment] = []
        var cursor = reservedHead
        for p in partitions {
            if p.offset - cursor >= Bytes.mib { out.append(.free(offset: cursor, size: p.offset - cursor)) }
            out.append(.partition(p))
            cursor = p.end
        }
        let tail = size - reservedTail
        if tail - cursor >= Bytes.mib { out.append(.free(offset: cursor, size: tail - cursor)) }
        return out
    }

    /// Free bytes directly after the given partition (before the next partition or the end).
    public func freeAfter(_ identifier: String) -> Int64 {
        guard let i = partitions.firstIndex(where: { $0.identifier == identifier }) else { return 0 }
        let next = i + 1 < partitions.count ? partitions[i + 1].offset : size - reservedTail
        return max(0, next - partitions[i].end)
    }

    public func partition(_ identifier: String) -> Partition? { partitions.first { $0.identifier == identifier } }

    /// The APFS container that holds the macOS this installer is running from (or, in a fixture,
    /// the largest container with a System volume).
    public var macOSPartition: Partition? {
        partitions.filter { $0.content == .appleAPFS && ($0.container?.hasMacOSSystem ?? false) && !$0.looksLikeSiliconForest }
            .max { $0.size < $1.size }
    }

    public func nextPartitionIdentifier() -> String {
        let used = Set(partitions.compactMap { Int($0.identifier.split(separator: "s").last ?? "") })
        var n = 1
        while used.contains(n) { n += 1 }
        return "\(identifier)s\(n)"
    }
}

public enum LayoutSegment: Sendable, Hashable, Identifiable {
    case partition(Partition)
    case free(offset: Int64, size: Int64)

    public var id: String {
        switch self {
        case .partition(let p): return p.identifier
        case .free(let o, _): return "free@\(o)"
        }
    }
    public var size: Int64 {
        switch self {
        case .partition(let p): return p.size
        case .free(_, let s): return s
        }
    }
}

public struct DiskSnapshot: Codable, Sendable, Hashable {
    public var disks: [PhysicalDisk]

    public init(disks: [PhysicalDisk]) { self.disks = disks }

    public var internalDisk: PhysicalDisk? { disks.first { $0.isInternal } ?? disks.first }

    public var siliconForestInstalls: [SiliconForestInstall] {
        guard let disk = internalDisk else { return [] }
        return SiliconForestInstall.detect(on: disk)
    }
}

// MARK: - Classification (docs/installer/ENGINE.md §3)

/// Every partition gets exactly one class, and the class decides what the installer may do to it.
public enum PartitionClass: String, Codable, Sendable, Hashable {
    case appleISC = "apple.isc", appleRecovery = "apple.recovery"   // None, ever
    case macOSPrimary = "macos.primary"                               // Resize only
    case macOSOther = "macos.other"                                   // None
    case osForeign = "os.foreign"                                     // None
    case sfOwned = "sf.owned"                                         // Update, Repair, Remove
    case sfPartial = "sf.partial"                                     // Resume, Roll back
    case sfUnproven = "sf.unproven"                                   // None: explain and stop
    case unknown = "unknown"                                          // None
}

extension Partition {
    /// The installer's marker: written on everything it creates, with the install ID that also
    /// appears in its journal. Name alone never proves ownership.
    public var sfRole: String? { metadata["sf.role"] }
    public var sfInstallID: String? { metadata["sf.installID"] }
    var hasSFMarker: Bool { sfRole != nil && sfInstallID != nil }

    /// Looks like SiliconForest (by name or type), whether or not we can prove it.
    var looksLikeSiliconForest: Bool {
        if sfRole != nil { return true }
        let n = (name ?? "").lowercased()
        if n.hasPrefix("sfboot") { return true }
        if n.contains("siliconforest") { return true }
        if content == .appleAPFS, let c = container, c.capacityCeiling <= 16 * Bytes.gb,
           c.volumes.contains(where: { $0.name.localizedCaseInsensitiveContains("SiliconForest") }) { return true }
        return false
    }
}

extension PhysicalDisk {
    /// Classifies every partition. Pure; golden-tested against the fixtures.
    public func classify() -> [String: PartitionClass] {
        var out: [String: PartitionClass] = [:]
        let installs = SiliconForestInstall.detect(on: self)
        for i in installs { for p in i.partitions { out[p.identifier] = i.partitionClass } }
        let primary = macOSPartition?.identifier
        for p in partitions where out[p.identifier] == nil {
            switch p.content {
            case .appleAPFSISC: out[p.identifier] = .appleISC
            case .appleAPFSRecovery: out[p.identifier] = .appleRecovery
            case .appleAPFS:
                if p.identifier == primary { out[p.identifier] = .macOSPrimary }
                else if p.container?.hasMacOSSystem == true { out[p.identifier] = .macOSOther }
                else { out[p.identifier] = .unknown }
            case .efi, .linuxFilesystem, .microsoftBasicData: out[p.identifier] = .osForeign
            case .unknown: out[p.identifier] = .unknown
            }
        }
        return out
    }

    /// The standard Apple layout (ISC first, Recovery container present) the installer requires.
    public var hasStandardAppleLayout: Bool {
        partitions.first?.content == .appleAPFSISC && partitions.contains { $0.content == .appleAPFSRecovery }
    }
}

/// One SiliconForest install found on a disk.
public struct SiliconForestInstall: Sendable, Hashable, Identifiable {
    public var name: String
    public var version: String?
    public var installedAt: String?
    public var installID: String?
    public var stub: Partition?
    public var boot: Partition?
    public var root: Partition?
    /// `sf.owned` when markers and layout prove it ours, `sf.unproven` otherwise.
    public var partitionClass: PartitionClass
    /// Why it isn't proven (shown under "Learn More").
    public var unprovenReason: String?

    public var id: String { (stub ?? root ?? boot)?.identifier ?? name }
    public var partitions: [Partition] { [stub, boot, root].compactMap { $0 }.sorted { $0.offset < $1.offset } }
    public var totalBytes: Int64 { partitions.reduce(0) { $0 + $1.size } }
    public var isComplete: Bool { stub != nil && boot != nil && root != nil }
    public var isOwned: Bool { partitionClass == .sfOwned }

    /// Space macOS gets back: from the first partition to the next one after the last, gaps included.
    public func reclaimableBytes(on disk: PhysicalDisk) -> Int64 {
        guard let first = partitions.first, let last = partitions.last else { return 0 }
        return last.end + disk.freeAfter(last.identifier) - first.offset
    }

    static func detect(on disk: PhysicalDisk) -> [SiliconForestInstall] {
        let parts = disk.partitions
        let candidates = parts.filter { $0.looksLikeSiliconForest }
        guard !candidates.isEmpty else { return [] }
        // Group by install ID when marked; unmarked SiliconForest-looking partitions form one group.
        var groups: [String: [Partition]] = [:]
        for p in candidates { groups[p.sfInstallID ?? "unmarked", default: []].append(p) }
        var out: [SiliconForestInstall] = []
        for (key, group) in groups.sorted(by: { $0.key < $1.key }) {
            let stub = group.first { $0.content == .appleAPFS }
            let boot = group.first { $0.content == .efi || $0.content == .microsoftBasicData }
            let root = group.first { $0.content == .linuxFilesystem }
            var reasons: [String] = []
            if key == "unmarked" || !group.allSatisfy(\.hasSFMarker) { reasons.append("it has no installer marker") }
            // Expected layout: stub, SFBOOT, root, contiguous, in that order.
            let ordered = [stub, boot, root].compactMap { $0 }
            let idx = ordered.compactMap { p in parts.firstIndex { $0.identifier == p.identifier } }
            if idx != idx.sorted() { reasons.append("its partitions are not in the installer's order (stub, SFBOOT, root)") }
            else if let lo = idx.first, let hi = idx.last, hi - lo + 1 != idx.count { reasons.append("its partitions are not next to each other") }
            let name = stub?.metadata["sf.installName"] ?? stub?.container?.volumes.first { $0.name.localizedCaseInsensitiveContains("SiliconForest") }?.name
                ?? stub?.name ?? "SiliconForest"
            let meta = (stub ?? root ?? boot)?.metadata ?? [:]
            out.append(SiliconForestInstall(name: name, version: meta["sf.version"], installedAt: meta["sf.installedAt"],
                                            installID: key == "unmarked" ? nil : key, stub: stub, boot: boot, root: root,
                                            partitionClass: reasons.isEmpty ? .sfOwned : .sfUnproven,
                                            unprovenReason: reasons.isEmpty ? nil : reasons.joined(separator: "; ")))
        }
        return out
    }
}
