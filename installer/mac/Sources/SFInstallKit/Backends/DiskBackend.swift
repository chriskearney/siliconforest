import Foundation

public enum BackendKind: String, Codable, Sendable {
    /// A JSON-described fake disk; operations are applied to the model with realistic timing.
    case simulated
    /// The real Mac, read-only. Mutating operations are recorded as planned commands, not run.
    case realReadOnly
}

/// What `perform` is told about where an operation sits in the plan (for logs and failure injection).
public struct OperationContext: Sendable {
    public var step: StepID
    public var stepIndex: Int
    public var isRollback: Bool
    public init(step: StepID, stepIndex: Int, isRollback: Bool = false) {
        self.step = step; self.stepIndex = stepIndex; self.isRollback = isRollback
    }
}

public struct OperationResult: Sendable {
    /// Identifier of a partition the operation created ("disk0s4").
    public var createdIdentifier: String?
    /// The commands as they were (or would have been) run, with identifiers resolved.
    public var commands: [[String]]
    /// False when the backend only recorded the commands.
    public var executed: Bool
    public init(createdIdentifier: String? = nil, commands: [[String]], executed: Bool) {
        self.createdIdentifier = createdIdentifier; self.commands = commands; self.executed = executed
    }
}

public typealias ProgressHandler = @Sendable (_ fraction: Double, _ detail: String) async -> Void

public protocol DiskBackend: Sendable {
    var kind: BackendKind { get }
    func systemFacts() async throws -> SystemFacts
    func snapshot() async throws -> DiskSnapshot
    /// Performs one operation. `resolve` maps plan slots ("@stub") to identifiers.
    func perform(_ operation: DiskOperation, context: OperationContext, resolve: @Sendable (PartRef) -> String,
                 progress: ProgressHandler) async throws -> OperationResult
}

public enum BackendError: Error, LocalizedError, Equatable {
    case injectedFailure(String)
    case invalidOperation(String)
    case mutationRefused(String)
    case commandNotAllowed(String)
    case commandFailed(String, Int32)
    case parse(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .injectedFailure(let m): return m
        case .invalidOperation(let m): return m
        case .mutationRefused(let m): return "Not executed (read-only mode): \(m)"
        case .commandNotAllowed(let m): return "Command not on the read-only allow-list: \(m)"
        case .commandFailed(let c, let s): return "\(c) exited with status \(s)"
        case .parse(let m): return "Couldn’t read the disk layout: \(m)"
        case .cancelled: return "Cancelled"
        }
    }
}

// MARK: - Shared model mutation

/// Applies operations to a `DiskSnapshot` the way diskutil would, with the same refusals. Used by
/// the simulator, and by the real backend to project the layout its recorded plan would produce.
public enum DiskModelMutator {
    public static func apply(_ op: DiskOperation, to snapshot: inout DiskSnapshot, resolve: (PartRef) -> String) throws -> String? {
        guard var disk = snapshot.internalDisk, let di = snapshot.disks.firstIndex(of: disk) else {
            throw BackendError.invalidOperation("No internal disk")
        }
        var created: String?
        switch op {
        case .resizeContainer(let ref, let newSize):
            let id = resolve(ref)
            guard let i = disk.partitions.firstIndex(where: { $0.identifier == id }), var c = disk.partitions[i].container else {
                throw BackendError.invalidOperation("\(id) is not an APFS container")
            }
            var p = disk.partitions[i]
            let target = newSize == 0 ? p.size + disk.freeAfter(id) : newSize
            if target < c.capacityUsed + 1 * Bytes.gb {
                throw BackendError.invalidOperation("Can’t shrink \(id) below its used space (\(Bytes.format(c.capacityUsed)))")
            }
            if target > p.size + disk.freeAfter(id) {
                throw BackendError.invalidOperation("Not enough free space after \(id) to grow to \(Bytes.format(target))")
            }
            c.capacityFree += target - p.size
            c.capacityCeiling = target
            p.size = target
            p.container = c
            disk.partitions[i] = p

        case .addPartition(let afterRef, _, let content, let name, let size, let metadata):
            let after = resolve(afterRef)
            guard let i = disk.partitions.firstIndex(where: { $0.identifier == after }) else {
                throw BackendError.invalidOperation("No partition \(after)")
            }
            guard disk.freeAfter(after) >= size else {
                throw BackendError.invalidOperation("Only \(Bytes.format(disk.freeAfter(after))) free after \(after); \(Bytes.format(size)) needed")
            }
            let id = disk.nextPartitionIdentifier()
            var container: APFSContainer?
            if content == .appleAPFS {
                let ref = "disk\(nextSynthesizedDisk(snapshot))"
                container = APFSContainer(reference: ref, capacityCeiling: size, capacityFree: size - 20 * Bytes.mb,
                                          volumes: [APFSVolume(identifier: "\(ref)s1", name: name, roles: [], capacityInUse: 20 * Bytes.mb)])
            }
            disk.partitions.insert(Partition(identifier: id, offset: disk.partitions[i].end, size: size, content: content,
                                             name: name, container: container, metadata: metadata), at: i + 1)
            created = id

        case .deletePartition(let ref), .deleteAPFSContainer(let ref):
            let id = resolve(ref)
            guard let i = disk.partitions.firstIndex(where: { $0.identifier == id }) else {
                throw BackendError.invalidOperation("No partition \(id)")
            }
            if disk.partitions[i].container?.hasMacOSSystem == true && disk.partitions[i].sfRole == nil {
                throw BackendError.invalidOperation("Refusing to delete \(id): it holds macOS")
            }
            if case .deleteAPFSContainer = op, disk.partitions[i].content != .appleAPFS {
                throw BackendError.invalidOperation("\(id) is not an APFS container")
            }
            disk.partitions.remove(at: i)

        case .writeFiles(let ref, _, _, let bytes), .writeImage(let ref, _, let bytes):
            let id = resolve(ref)
            guard let i = disk.partitions.firstIndex(where: { $0.identifier == id }) else {
                throw BackendError.invalidOperation("No partition \(id) to write to")
            }
            if case .writeImage = op, bytes > disk.partitions[i].size {
                throw BackendError.invalidOperation("Image is larger than \(id)")
            }
            if var c = disk.partitions[i].container {
                c.capacityFree = max(0, c.capacityFree - bytes)
                disk.partitions[i].container = c
            }

        case .verify(let ref, _, _), .bless(let ref, _, _):
            let id = resolve(ref)
            guard disk.partition(id) != nil else { throw BackendError.invalidOperation("No partition \(id)") }

        case .checkFiles:
            break

        case .download:
            break
        }
        snapshot.disks[di] = disk
        return created
    }

    static func nextSynthesizedDisk(_ s: DiskSnapshot) -> Int {
        let refs = s.disks.flatMap { $0.partitions.compactMap { $0.container?.reference } }
        let nums = refs.compactMap { Int($0.dropFirst(4)) }
        return max(4, (nums.max() ?? 3) + 1)
    }
}
