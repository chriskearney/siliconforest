import Foundation
import SFInstallKit

public struct ImageVolume: Codable, Sendable, Hashable {
    public var identifier: String
    public var uuid: String
    public var name: String
    public var roles: [String]
}

public struct ImageAPFS: Codable, Sendable, Hashable {
    public var reference: String
    public var uuid: String
    public var capacityCeiling: Int64
    public var capacityFree: Int64
    public var volumes: [ImageVolume]
}

/// One GPT partition, identified by its partition UUID (DESIGN §14.4: never by diskN or name).
public struct ImagePartition: Codable, Sendable, Hashable {
    public var uuid: String
    public var identifier: String
    /// diskutil's content name ("Apple_APFS", "EFI", "Linux Filesystem", or a type GUID).
    public var content: String
    public var offset: Int64
    public var size: Int64
    public var volumeName: String?
    public var filesystem: String?
    public var apfs: ImageAPFS?
    public var end: Int64 { offset + size }
}

/// The partition table of one image-backed whole disk, as diskutil reports it now.
public struct ImageTopology: Codable, Sendable, Hashable {
    public var wholeDisk: String
    public var size: Int64
    public var blockSize: Int64
    public var partitions: [ImagePartition]

    public func partition(uuid: String) -> ImagePartition? { partitions.first { $0.uuid == uuid } }
    public func partition(id: String) -> ImagePartition? { partitions.first { $0.identifier == id } }

    /// The macOS-like container: the largest APFS partition with a System-role volume.
    public var macOS: ImagePartition? {
        partitions.filter { $0.content == "Apple_APFS" && ($0.apfs?.volumes.contains { $0.roles.contains("System") } ?? false) }
            .max { $0.size < $1.size }
    }

    /// Free bytes directly after a partition, up to the next partition or the GPT's backup area.
    public func freeAfter(uuid: String) -> Int64 {
        guard let i = partitions.firstIndex(where: { $0.uuid == uuid }) else { return 0 }
        let next = i + 1 < partitions.count ? partitions[i + 1].offset : size - 20_480
        return max(0, next - partitions[i].end)
    }

    public func next(after uuid: String) -> ImagePartition? {
        guard let i = partitions.firstIndex(where: { $0.uuid == uuid }), i + 1 < partitions.count else { return nil }
        return partitions[i + 1]
    }

    /// What the digest covers: every partition's type, UUID, first LBA and length, plus the disk's
    /// size and block size. Free space inside APFS is deliberately not covered (ENGINE §5).
    public struct DigestEntry: Codable, Hashable { var content: String; var uuid: String; var firstLBA: Int64; var blocks: Int64 }
    public struct DigestForm: Codable, Hashable { var size: Int64; var blockSize: Int64; var partitions: [DigestEntry] }

    public var digestForm: DigestForm {
        DigestForm(size: size, blockSize: blockSize, partitions: partitions.map {
            DigestEntry(content: $0.content, uuid: $0.uuid, firstLBA: $0.offset / blockSize, blocks: $0.size / blockSize)
        })
    }

    public var layoutDigest: String { (try? Canonical.digest(digestForm)) ?? "" }

    /// The engine's model of the same disk, so the existing planner, sizing and classifier apply.
    /// `owned` stamps the installer's marker on partitions this job's journal proves it created.
    public func snapshot(owned: [String: (role: String, installID: String)] = [:]) -> DiskSnapshot {
        let parts = partitions.map { p -> Partition in
            let container = p.apfs.map { a in
                APFSContainer(reference: a.reference, capacityCeiling: a.capacityCeiling, capacityFree: a.capacityFree,
                              volumes: a.volumes.map { APFSVolume(identifier: $0.identifier, name: $0.name, roles: $0.roles) })
            }
            var meta: [String: String] = [:]
            if let o = owned[p.uuid] { meta = ["sf.role": o.role, "sf.installID": o.installID] }
            return Partition(identifier: p.identifier, offset: p.offset, size: p.size, content: PartitionContent(diskutil: p.content),
                             name: p.volumeName, container: container, metadata: meta)
        }
        return DiskSnapshot(disks: [PhysicalDisk(identifier: wholeDisk, mediaName: "Disk Image", size: size, blockSize: blockSize,
                                                 isInternal: true, partitions: parts)])
    }
}

public enum TopologyReader {
    /// Reads one whole disk with read-only queries. Callers pass a whole disk the guard has proved.
    public static func read(_ whole: String, query: ToolRunner) throws -> ImageTopology {
        let list = try Query.dict(query, ["/usr/sbin/diskutil", "list", "-plist", whole])
        guard let entry = (list["AllDisksAndPartitions"] as? [[String: Any]])?.first(where: { $0["DeviceIdentifier"] as? String == whole }) else {
            throw EngineError(.inconsistent, "\(whole) is not attached")
        }
        let wholeInfo = try Query.dict(query, ["/usr/sbin/diskutil", "info", "-plist", whole])
        let apfs = try Query.dict(query, ["/usr/sbin/diskutil", "apfs", "list", "-plist"])
        var byStore: [String: ImageAPFS] = [:]
        for c in apfs["Containers"] as? [[String: Any]] ?? [] {
            guard let store = c["DesignatedPhysicalStore"] as? String, store.hasPrefix(whole + "s") else { continue }
            let vols = (c["Volumes"] as? [[String: Any]] ?? []).map {
                ImageVolume(identifier: $0["DeviceIdentifier"] as? String ?? "", uuid: $0["APFSVolumeUUID"] as? String ?? "",
                            name: $0["Name"] as? String ?? "", roles: $0["Roles"] as? [String] ?? [])
            }
            byStore[store] = ImageAPFS(reference: c["ContainerReference"] as? String ?? "", uuid: c["APFSContainerUUID"] as? String ?? "",
                                       capacityCeiling: (c["CapacityCeiling"] as? NSNumber)?.int64Value ?? 0,
                                       capacityFree: (c["CapacityFree"] as? NSNumber)?.int64Value ?? 0, volumes: vols)
        }
        var parts: [ImagePartition] = []
        for p in entry["Partitions"] as? [[String: Any]] ?? [] {
            guard let id = p["DeviceIdentifier"] as? String else { continue }
            let info = try Query.dict(query, ["/usr/sbin/diskutil", "info", "-plist", id])
            guard let uuid = info["DiskUUID"] as? String ?? p["DiskUUID"] as? String else {
                throw EngineError(.inconsistent, "\(id) has no partition UUID")
            }
            let name = (p["VolumeName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            parts.append(ImagePartition(uuid: uuid, identifier: id, content: p["Content"] as? String ?? "",
                                        offset: (info["PartitionMapPartitionOffset"] as? NSNumber)?.int64Value ?? 0,
                                        size: (info["Size"] as? NSNumber)?.int64Value ?? (p["Size"] as? NSNumber)?.int64Value ?? 0,
                                        volumeName: name, filesystem: info["FilesystemType"] as? String, apfs: byStore[id]))
        }
        parts.sort { $0.offset < $1.offset }
        return ImageTopology(wholeDisk: whole, size: (wholeInfo["Size"] as? NSNumber)?.int64Value ?? 0,
                             blockSize: (wholeInfo["DeviceBlockSize"] as? NSNumber)?.int64Value ?? 512, partitions: parts)
    }

    public struct ResizeLimits: Codable, Sendable, Hashable {
        public var current: Int64
        public var minimumPreferred: Int64
        public var minimumNoGuard: Int64
        public var maximum: Int64
    }

    public static func limits(_ store: String, query: ToolRunner) throws -> ResizeLimits {
        let d = try Query.dict(query, ["/usr/sbin/diskutil", "apfs", "resizeContainer", store, "limits", "-plist"])
        func n(_ k: String) -> Int64 { (d[k] as? NSNumber)?.int64Value ?? 0 }
        return ResizeLimits(current: n("CurrentSize"), minimumPreferred: n("MinimumSizePreferred"), minimumNoGuard: n("MinimumSizeNoGuard"), maximum: n("MaximumSize"))
    }
}
