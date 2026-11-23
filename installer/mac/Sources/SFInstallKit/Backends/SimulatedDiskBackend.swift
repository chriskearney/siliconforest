import Foundation

/// A fake Mac described by JSON: system facts plus a disk layout. Fixtures live in
/// `installer/mac/Fixtures/disks`.
public struct DiskFixture: Codable, Sendable {
    public var name: String
    public var summary: String?
    public var facts: SystemFacts
    public var disks: [PhysicalDisk]

    public var snapshot: DiskSnapshot { DiskSnapshot(disks: disks) }

    public static func load(_ url: URL) throws -> DiskFixture {
        try JSONDecoder().decode(DiskFixture.self, from: Data(contentsOf: url))
    }

    /// Loads `Fixtures/disks/<name>.json`.
    public static func named(_ name: String) throws -> DiskFixture {
        try load(SourceTree.fixtures.appendingPathComponent("disks/\(name).json"))
    }

    public static func available() -> [URL] {
        let dir = SourceTree.fixtures.appendingPathComponent("disks")
        return ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

/// Makes an operation fail, to exercise rollback.
public struct FailureInjection: Codable, Sendable, Hashable {
    /// Fail the first operation of this kind…
    public var operation: DiskOperation.Kind?
    /// …or the first operation in this step.
    public var step: StepID?
    /// How far through the operation to fail (0…1).
    public var atFraction: Double
    public var message: String
    /// Fail rollback operations too (a "rollback could not finish" scenario).
    public var duringRollback: Bool

    public init(operation: DiskOperation.Kind? = nil, step: StepID? = nil, atFraction: Double = 0.4,
                message: String? = nil, duringRollback: Bool = false) {
        self.operation = operation; self.step = step; self.atFraction = atFraction; self.duringRollback = duringRollback
        self.message = message ?? "Simulated failure\(step.map { " in \($0.rawValue)" } ?? "")\(operation.map { " during \($0.rawValue)" } ?? "")"
    }
}

public actor SimulatedDiskBackend: DiskBackend {
    public nonisolated let kind: BackendKind = .simulated
    private var state: DiskSnapshot
    private let facts: SystemFacts
    /// Multiplies every simulated duration. 1.0 feels like a real (but brisk) install; tests use 0.
    public var timeScale: Double
    private var failures: [FailureInjection]
    public private(set) var performed: [DiskOperation] = []

    public init(fixture: DiskFixture, timeScale: Double = 1.0, failures: [FailureInjection] = []) {
        self.state = fixture.snapshot
        self.facts = fixture.facts
        self.timeScale = timeScale
        self.failures = failures
    }

    public func setTimeScale(_ scale: Double) { timeScale = scale }
    public func inject(_ failure: FailureInjection) { failures.append(failure) }
    public func clearFailures() { failures.removeAll() }

    public func systemFacts() async throws -> SystemFacts {
        try await pause(0.15)
        return facts
    }

    public func snapshot() async throws -> DiskSnapshot {
        try await pause(0.2)
        return state
    }

    public func perform(_ operation: DiskOperation, context: OperationContext, resolve: @Sendable (PartRef) -> String,
                        progress: ProgressHandler) async throws -> OperationResult {
        let commands = operation.commands(resolve: resolve)
        let duration = Self.duration(of: operation, in: state)
        let failure = failures.firstIndex { f in
            (f.duringRollback || !context.isRollback) &&
            ((f.operation != nil && f.operation == operation.kind) || (f.step != nil && f.step == context.step))
        }

        // Validate before "running", the way diskutil refuses up front.
        var projected = state
        let created = try DiskModelMutator.apply(operation, to: &projected, resolve: resolve)

        let ticks = max(1, Int(duration * timeScale / 0.05))
        for t in 1...ticks {
            try Task.checkCancellation()
            let fraction = Double(t) / Double(ticks)
            if let fi = failure, fraction >= failures[fi].atFraction {
                let f = failures.remove(at: fi)
                throw BackendError.injectedFailure(f.message)
            }
            await progress(fraction, Self.detail(for: operation, fraction: fraction))
            if timeScale > 0 { try await Task.sleep(nanoseconds: UInt64(0.05 * 1_000_000_000)) }
        }
        state = projected
        performed.append(operation)
        return OperationResult(createdIdentifier: created, commands: commands.map { $0.map { $0.replacingOccurrences(of: "<new>", with: created ?? "<new>") } }, executed: true)
    }

    private func pause(_ seconds: Double) async throws {
        if timeScale > 0 { try await Task.sleep(nanoseconds: UInt64(seconds * min(timeScale, 1) * 1_000_000_000)) }
    }

    /// Seconds at timeScale 1. Shaped like the real thing, compressed so a full dry run takes about
    /// a minute and a half.
    static func duration(of op: DiskOperation, in s: DiskSnapshot) -> Double {
        switch op {
        case .resizeContainer(_, let size):
            return size == 0 ? 9 : 14
        case .addPartition: return 2.2
        case .deletePartition: return 1.6
        case .deleteAPFSContainer: return 2.4
        case .download(_, _, let bytes): return 3 + Double(bytes) / Double(Bytes.gb) * 3.5
        case .writeFiles(_, _, _, let bytes): return 1.2 + Double(bytes) / Double(Bytes.gb) * 3
        case .writeImage(_, _, let bytes): return 4 + Double(bytes) / Double(Bytes.gb) * 2.4
        case .verify(_, _, let bytes): return 1 + Double(bytes) / Double(Bytes.gb) * 0.9
        case .checkFiles(_, let bytes): return 1 + Double(bytes) / Double(Bytes.gb) * 0.6
        case .bless: return 2.0
        }
    }

    static func detail(for op: DiskOperation, fraction: Double) -> String {
        switch op {
        case .resizeContainer(_, let size):
            return size == 0 ? "Growing the container…" : (fraction < 0.25 ? "Checking the container…" : fraction < 0.85 ? "Moving data blocks…" : "Updating the partition map…")
        case .addPartition(_, _, _, let name, _, _): return "Creating “\(name)”…"
        case .deletePartition(let p), .deleteAPFSContainer(let p): return "Removing \(p)…"
        case .download(let item, _, let bytes):
            return "\(Bytes.format(Int64(Double(bytes) * fraction))) of \(Bytes.format(bytes)) · \(item)"
        case .writeFiles(_, let label, _, _): return "Copying \(label)…"
        case .writeImage(_, _, let bytes): return "\(Bytes.format(Int64(Double(bytes) * fraction))) of \(Bytes.format(bytes)) written"
        case .verify(_, let label, _): return "Reading back \(label)… \(Int(fraction * 100))%"
        case .checkFiles(let label, _): return "Checking \(label)…"
        case .bless(_, let label, _): return "Setting the startup disk to \(label)…"
        }
    }
}
