import Foundation

/// What the install engine needs from a disk backend: typed verbs on partitions named by UUID, and
/// nothing that takes a command line. `DiskImageBackend` (images only) and `LiveDiskBackend`
/// (SFLiveDisk: behind the two-key real-disk gate and a protection receipt) both conform; the engine
/// cannot tell them apart, so everything the image sweeps prove about the engine holds for both.
public protocol EngineBackend: AnyObject, Sendable {
    /// For the journal and logs: the image path, or "internal disk <uuid>".
    var targetLabel: String { get }

    /// Read-only diskutil queries (info, list, listVolumeGroups).
    var query: ToolRunner { get }

    func topology() throws -> ImageTopology
    func freshTopology() throws -> ImageTopology
    func limits(store uuid: String) throws -> TopologyReader.ResizeLimits
    func identifier(_ uuid: String) throws -> String

    func addPartition(after uuid: String, content: String, label: String, bytes: Int64) throws -> String
    func formatFAT32(_ uuid: String, label: String) throws
    /// `apfs addVolume <container> apfs <name> -role <role> [-groupWith <volume>]`: upstream stub.py's shape,
    /// so the stub's volumes come out as Asahi's do. `groupWith` is a volume UUID.
    func addVolume(container storeUUID: String, name: String, role: String, groupWith: String?) throws
    /// `apfs changeVolumeRole <volume> <role>`.
    func changeVolumeRole(container storeUUID: String, volume: String, role: String) throws
    /// `rename <volume> <name>`.
    func renameVolume(container storeUUID: String, volume: String, name: String) throws
    func volumeURL(store uuid: String, role: String?) throws -> URL
    func fatURL(_ uuid: String) throws -> URL
    func deleteContainer(_ uuid: String) throws
    func eraseToFree(_ uuid: String) throws

    func writeImage(_ uuid: String, source: URL, compressed: Bool, progress: ((Int64) -> Void)?) throws -> (bytes: Int64, sha256: String)
    func hashRaw(_ uuid: String, bytes: Int64) throws -> String
    func readRaw(_ uuid: String, offset: Int64, count: Int) throws -> Data
    func writeRaw(_ uuid: String, offset: Int64, data: Data) throws

    /// Fault injection only: what a power cut looks like. Real internal disks refuse it.
    func detach(force: Bool) throws

    /// Proves and invalidates for a resize the supervisor is about to launch itself.
    func authorizeResize(_ argv: [String]) throws

    /// Called by the engine whenever a job starts or resumes, with the plan and the partition table the
    /// journal saved before the first write. A backend that protects partitions derives its protection
    /// receipt from exactly these, so the receipt survives a crash. No-op for images.
    func arm(plan: EnginePlan, original: ImageTopology) throws

    /// Called with the release the job installs and where its files are; a backend that checks
    /// releases verifies them itself before its first write. No-op for images.
    func expectRelease(_ release: ReleaseManifest?, in directory: URL)
}

public extension EngineBackend {
    func arm(plan: EnginePlan, original: ImageTopology) throws {}
    func expectRelease(_ release: ReleaseManifest?, in directory: URL) {}
}

extension DiskImageBackend: EngineBackend {
    public var targetLabel: String { imagePath }
    public func authorizeResize(_ argv: [String]) throws {
        try chokepoint.authorizeAll(argv)
        chokepoint.invalidate()
    }
}
