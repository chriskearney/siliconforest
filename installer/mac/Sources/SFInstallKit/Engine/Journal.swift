import Foundation

/// One line of the install journal (JSON Lines). The journal is the source of truth for resume and
/// rollback: it records the plan, every command (and whether it ran), and a checkpoint after each
/// completed step.
public struct JournalEntry: Codable, Sendable, Hashable {
    public enum Event: String, Codable, Sendable {
        case planned, partitionTable, stepStarted, command, stepCompleted, checkpoint, stepFailed,
             rollbackStarted, rollbackStep, rollbackCompleted, rollbackIncomplete, finished, cancelled, note
    }

    public var time: Date
    public var event: Event
    public var step: StepID?
    public var message: String
    public var command: [String]?
    public var executed: Bool?
    /// True for commands that change the disk; "No changes were made" is derived from their absence.
    public var mutating: Bool?
    public var checkpoint: Checkpoint?
    public var plan: InstallPlan?
    public var snapshot: DiskSnapshot?

    public init(time: Date = Date(), event: Event, step: StepID? = nil, message: String, command: [String]? = nil,
                executed: Bool? = nil, mutating: Bool? = nil, checkpoint: Checkpoint? = nil, plan: InstallPlan? = nil, snapshot: DiskSnapshot? = nil) {
        self.time = time; self.event = event; self.step = step; self.message = message; self.command = command
        self.executed = executed; self.mutating = mutating; self.checkpoint = checkpoint; self.plan = plan; self.snapshot = snapshot
    }
}

/// What has been done so far: completed steps and the identifiers of partitions the plan created.
public struct Checkpoint: Codable, Sendable, Hashable {
    public var completed: [StepID]
    public var slots: [String: String]
    public init(completed: [StepID] = [], slots: [String: String] = [:]) {
        self.completed = completed; self.slots = slots
    }
}

public actor Journal {
    public let url: URL?
    public private(set) var entries: [JournalEntry] = []
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    /// `url == nil` keeps the journal in memory (tests, snapshots).
    public init(url: URL?) {
        self.url = url
        if let url {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        }
    }

    public func append(_ entry: JournalEntry) {
        entries.append(entry)
        guard let url, var line = try? encoder.encode(entry) else { return }
        line.append(0x0A)
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: line)
            try? h.synchronize()   // a checkpoint that isn't on disk isn't a checkpoint
        }
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("SiliconForest Installer/Journals", isDirectory: true)
    }

    public static func newURL(kind: InstallPlan.Kind, backend: BackendKind, in dir: URL = defaultDirectory()) -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return dir.appendingPathComponent("\(f.string(from: Date()))-\(kind.rawValue)-\(backend == .simulated ? "dryrun" : "readonly").jsonl")
    }

    public static func read(_ url: URL) throws -> [JournalEntry] {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map { try d.decode(JournalEntry.self, from: Data($0.utf8)) }
    }
}

/// The state a journal describes, for resume-after-crash.
public struct JournalState: Sendable {
    public var plan: InstallPlan?
    public var checkpoint: Checkpoint
    public var finished: Bool
    public var rolledBack: Bool
    public var failedStep: StepID?

    /// Proved by the journal: no disk-changing command ran (UX-FLOW: "No changes were made" only when proved).
    public var noChangesMade: Bool

    /// True when an install started and neither finished nor rolled back (the app quit or crashed).
    public var isInterrupted: Bool { plan != nil && !finished && !rolledBack }

    public init(entries: [JournalEntry]) {
        plan = entries.last { $0.event == .planned }?.plan
        checkpoint = entries.last { $0.event == .checkpoint }?.checkpoint ?? Checkpoint()
        finished = entries.contains { $0.event == .finished }
        rolledBack = entries.contains { $0.event == .rollbackCompleted }
        failedStep = entries.last { $0.event == .stepFailed }?.step
        noChangesMade = !entries.contains { $0.event == .command && $0.mutating == true && $0.executed == true }
    }

    /// Index of the first step that still has to run.
    public var resumeIndex: Int {
        guard let plan else { return 0 }
        return plan.steps.firstIndex { !checkpoint.completed.contains($0.id) } ?? plan.steps.count
    }
}
