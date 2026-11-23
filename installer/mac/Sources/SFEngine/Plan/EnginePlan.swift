import Foundation
import SFInstallKit

/// What the person chose on the Review screen. With the disk, the profile and the release, it
/// determines the plan exactly, so the helper can rebuild it and compare digests.
public struct InstallRequest: Codable, Sendable, Hashable {
    public var siliconForestBytes: Int64
    public var installName: String
    /// Random, made by the app; also written into the receipt slot and every marker.
    public var installID: String
    public init(siliconForestBytes: Int64, installName: String = "SiliconForest", installID: String) {
        self.siliconForestBytes = siliconForestBytes; self.installName = installName; self.installID = installID
    }
}

/// The release as the engine needs it: names, sizes and hashes of every artifact, and the slot
/// offsets inside the root image (DESIGN §8.3, §10).
public struct ReleaseManifest: Codable, Sendable, Hashable {
    public struct Artifact: Codable, Sendable, Hashable {
        public var name: String
        public var bytes: Int64
        public var sha256: String
    }
    public var version: String
    public var artifacts: [Artifact]
    /// The root filesystem image as written to the raw partition, and its hash after decompression.
    public var rootImage: String
    public var rootImageBytes: Int64
    public var rootImageSHA256: String
    public var rootImageCompressed: Bool
    public var rootMinBytes: Int64
    public var firmwareSlotOffset: Int64
    public var firmwareSlotBytes: Int64
    public var receiptSlotOffset: Int64
    public var receiptSlotBytes: Int64
    /// Files that go onto the stub's System volume (the parts of Apple's 13.5 image; fakes in tests).
    public var stubFiles: [String]
    public var stage1: String
    public var stage2: String
    public var kernel: String
    public var firmware: String

    public func artifact(_ name: String) -> Artifact? { artifacts.first { $0.name == name } }
    public var digest: String { (try? Canonical.digest(self)) ?? "" }
}

public struct ProfileRef: Codable, Sendable, Hashable {
    public var id: String
    public var sha256: String
}

/// ENGINE §5: an immutable value whose digest is what the person approves.
public struct EnginePlan: Codable, Sendable, Hashable {
    public enum Operation: String, Codable, Sendable { case install, remove }

    public struct Resize: Codable, Sendable, Hashable {
        /// The macOS container's partition UUID.
        public var store: String
        public var from: Int64
        public var to: Int64
    }

    public struct NewPartition: Codable, Sendable, Hashable {
        public var role: String          // stub, boot, root
        /// "@macos", "@stub", "@boot": the partition it follows.
        public var after: String
        public var bytes: Int64
        public var content: String       // Apple_APFS, EFI, Linux Filesystem
        public var label: String
    }

    /// For removal: what the install's journal proves is ours, by partition UUID.
    public struct Owned: Codable, Sendable, Hashable {
        public var stub: String?
        public var boot: String?
        public var root: String?
        public var all: [String] { [stub, boot, root].compactMap { $0 } }
    }

    public var format = "siliconforest-plan/1"
    public var operation: Operation
    public var profile: ProfileRef
    public var release: String          // manifest digest
    public var releaseVersion: String
    public var request: InstallRequest?
    public var layoutDigest: String
    public var macOS: Resize
    public var partitions: [NewPartition]
    public var owned: Owned?
    /// The install job a removal undoes.
    public var installJob: UUID?
    /// The original partition table saved by the install, which removal must restore.
    public var originalLayoutDigest: String?
    public var humanSteps: [String]
    public var digest: String = ""

    public func computeDigest() -> String {
        var copy = self
        copy.digest = ""
        return (try? Canonical.digest(copy)) ?? ""
    }

    public func sealed() -> EnginePlan { var p = self; p.digest = computeDigest(); return p }
    public var isSealed: Bool { !digest.isEmpty && digest == computeDigest() }

    public func partition(_ role: String) -> NewPartition? { partitions.first { $0.role == role } }
}

public struct PlanRefusal: Error, LocalizedError, Equatable {
    public var reason: String
    public var errorDescription: String? { reason }
}

/// Builds plans from a live read of the disk. Deterministic: the same disk, profile, release and
/// request give the same digest, which is how `bind` proves the approved plan still applies.
public enum EnginePlanner {
    public static let align: Int64 = 1 << 20

    public static func profileRef(_ profile: DeviceProfile) -> ProfileRef {
        let url = SourceTree.installerRoot.appendingPathComponent("profiles/\(profile.id).json")
        let sha = (try? SHA256Hasher.file(url)) ?? SHA256Hasher.hex(profile.id)
        return ProfileRef(id: profile.id, sha256: sha)
    }

    /// The smallest macOS may become: ENGINE §4's floor, and never below APFS's preferred minimum.
    public static func macOSMinimum(_ c: SizingConstraints, limits: TopologyReader.ResizeLimits) -> Int64 {
        let m = max(c.macOSFloor, limits.minimumPreferred)
        return ((m + align - 1) / align) * align
    }

    public static func installPlan(topology: ImageTopology, limits: TopologyReader.ResizeLimits, profile: DeviceProfile,
                                   release: ReleaseManifest, request: InstallRequest) throws -> EnginePlan {
        guard let mac = topology.macOS else { throw PlanRefusal(reason: "no macOS container on this disk") }
        let info = ReleaseInfo(version: release.version, downloadBytes: release.artifacts.reduce(0) { $0 + $1.bytes },
                               rootImageBytes: release.rootImageBytes, rootMinBytes: release.rootMinBytes, rootSizing: .growable)
        let snap = topology.snapshot()
        guard let disk = snap.internalDisk, let c = SizingConstraints(profile: profile, disk: disk, release: info) else {
            throw PlanRefusal(reason: "can't size this disk")
        }
        if let problem = InstallOptions.validate(name: request.installName) { throw PlanRefusal(reason: "invalid name (\(problem))") }
        let stub = profile.partitioning.stubContainerBytes, boot = profile.partitioning.bootPartition.bytes
        let macMin = macOSMinimum(c, limits: limits)
        let pool = mac.size + topology.freeAfter(uuid: mac.uuid)
        let sfMax = ((pool - macMin) / align) * align
        let sf = (request.siliconForestBytes / align) * align
        guard sf >= c.minimum else { throw PlanRefusal(reason: "SiliconForest needs at least \(Bytes.format(c.minimum))") }
        guard sf <= sfMax else { throw PlanRefusal(reason: "at most \(Bytes.format(max(0, sfMax))) can be freed (macOS keeps \(Bytes.format(macMin)))") }
        let to = ((min(mac.size, pool - sf)) / align) * align
        let root = sf - stub - boot
        guard root >= max(profile.partitioning.rootMinBytes, release.rootMinBytes), root >= release.rootImageBytes else {
            throw PlanRefusal(reason: "root partition would be smaller than the release needs")
        }
        return EnginePlan(operation: .install, profile: profileRef(profile), release: release.digest, releaseVersion: release.version,
                          request: request, layoutDigest: topology.layoutDigest,
                          macOS: .init(store: mac.uuid, from: mac.size, to: to),
                          partitions: [
                            .init(role: "stub", after: "@macos", bytes: stub, content: "Apple_APFS", label: request.installName),
                            .init(role: "boot", after: "@stub", bytes: boot, content: "EFI", label: profile.partitioning.bootPartition.name),
                            .init(role: "root", after: "@boot", bytes: root, content: "Linux Filesystem", label: "SF root"),
                          ],
                          owned: nil, installJob: nil, originalLayoutDigest: topology.layoutDigest,
                          humanSteps: ["enterOneTrueRecovery", "authenticateMachineOwner"]).sealed()
    }

    /// DESIGN §8.4: removal of exactly what an install journal proves it created.
    public static func removalPlan(topology: ImageTopology, profile: DeviceProfile, proof: InstallProof) throws -> EnginePlan {
        guard let mac = topology.partition(uuid: proof.macOSStore) else { throw PlanRefusal(reason: "macOS container from the install is gone") }
        for u in proof.owned.all where topology.partition(uuid: u) == nil {
            throw PlanRefusal(reason: "partition \(u) recorded by the install is missing")
        }
        // Owned partitions must be contiguous right after macOS, in the installer's order.
        let ids = topology.partitions.map(\.uuid)
        guard let mi = ids.firstIndex(of: mac.uuid) else { throw PlanRefusal(reason: "macOS container not found") }
        let expected = proof.owned.all
        guard Array(ids.dropFirst(mi + 1).prefix(expected.count)) == expected else {
            throw PlanRefusal(reason: "the install's partitions are not where the installer put them")
        }
        return EnginePlan(operation: .remove, profile: profileRef(profile), release: "", releaseVersion: proof.releaseVersion, request: nil,
                          layoutDigest: topology.layoutDigest, macOS: .init(store: mac.uuid, from: mac.size, to: proof.macOSOriginalSize),
                          partitions: [], owned: proof.owned, installJob: proof.job, originalLayoutDigest: proof.originalLayoutDigest,
                          humanSteps: []).sealed()
    }

    /// The helper's check at `begin`: rebuild from its own read and refuse unless the digests match,
    /// then recheck the resize against the live minimum (ENGINE §5).
    public static func bind(_ approved: EnginePlan, topology: ImageTopology, limits: TopologyReader.ResizeLimits,
                            profile: DeviceProfile, release: ReleaseManifest?, proof: InstallProof? = nil) throws {
        guard approved.isSealed else { throw PlanRefusal(reason: "the plan's digest doesn't match its contents") }
        let rebuilt: EnginePlan
        switch approved.operation {
        case .install:
            guard let release, let request = approved.request else { throw PlanRefusal(reason: "install plan without release or request") }
            guard release.digest == approved.release else { throw PlanRefusal(reason: "the release differs from the approved one") }
            rebuilt = try installPlan(topology: topology, limits: limits, profile: profile, release: release, request: request)
        case .remove:
            guard let proof else { throw PlanRefusal(reason: "removal without an install proof") }
            rebuilt = try removalPlan(topology: topology, profile: profile, proof: proof)
        }
        guard rebuilt.layoutDigest == approved.layoutDigest else { throw PlanRefusal(reason: "the disk changed since the plan was approved") }
        guard rebuilt.digest == approved.digest else { throw PlanRefusal(reason: "the rebuilt plan differs from the approved one") }
        if approved.operation == .install {
            let info = ReleaseInfo(version: release!.version, downloadBytes: 0, rootImageBytes: release!.rootImageBytes,
                                   rootMinBytes: release!.rootMinBytes, rootSizing: .growable)
            guard let c = SizingConstraints(profile: profile, disk: topology.snapshot().internalDisk!, release: info) else {
                throw PlanRefusal(reason: "can't size this disk")
            }
            let live = macOSMinimum(c, limits: limits)
            guard approved.macOS.to >= live else {
                throw PlanRefusal(reason: "macOS now needs \(Bytes.format(live)); the plan would shrink it to \(Bytes.format(approved.macOS.to))")
            }
        }
    }
}

/// What a finished install's journal proves (DESIGN §14.5: we delete only what is proved ours).
public struct InstallProof: Codable, Sendable, Hashable {
    public var job: UUID
    public var installID: String
    public var releaseVersion: String
    public var macOSStore: String
    public var macOSOriginalSize: Int64
    public var originalLayoutDigest: String
    public var owned: EnginePlan.Owned
}
