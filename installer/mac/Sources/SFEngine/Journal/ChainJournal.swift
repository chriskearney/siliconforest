import Foundation

/// A JSON value small enough for journal arguments and results.
public enum JValue: Codable, Sendable, Hashable {
    case s(String), i(Int64), b(Bool), a([JValue]), o([String: JValue]), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .b(v) }
        else if let v = try? c.decode(Int64.self) { self = .i(v) }
        else if let v = try? c.decode(String.self) { self = .s(v) }
        else if let v = try? c.decode([JValue].self) { self = .a(v) }
        else { self = .o(try c.decode([String: JValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .s(let v): try c.encode(v)
        case .i(let v): try c.encode(v)
        case .b(let v): try c.encode(v)
        case .a(let v): try c.encode(v)
        case .o(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public var string: String? { if case .s(let v) = self { return v }; return nil }
    public var int: Int64? { if case .i(let v) = self { return v }; return nil }
    public var bool: Bool? { if case .b(let v) = self { return v }; return nil }
    public subscript(_ k: String) -> JValue? { if case .o(let d) = self { return d[k] }; return nil }
}

public typealias JArgs = [String: JValue]

/// One journal record (ENGINE §9). The record before a write states intent; the record after states
/// what is proved. Each record carries the hash of the previous one.
public struct JournalRecord: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        /// Job opened: plan, its digest, the original partition table.
        case begin
        case intent, evidence, checkpoint
        /// The step ran in simulation because, on an image, it needs root or a real Mac.
        case simulated
        /// A resumed step's idempotent check: done, not done, or cannot tell.
        case check
        case failed
        case rollbackIntent = "rollback-intent", rollbackEvidence = "rollback-evidence", rolledBack = "rolled-back"
        case note
        /// The job ended: committed, rolled-back or abandoned.
        case end
    }
    public var seq: UInt64
    public var prev: String
    /// ISO-8601 UTC with milliseconds, kept as text so a record re-reads byte-identical.
    public var t: String
    public var kind: Kind
    public var step: String?
    public var args: JArgs?
    public var result: JArgs?
    public var note: String?

    /// sha256 of this record's canonical JSON. The next record's `prev`.
    public var hash: String { (try? Canonical.digest(self)) ?? "" }
}

public enum JobEnd: String, Codable, Sendable { case committed, rolledBack = "rolled-back", abandoned, handedOff = "handed-off" }

public struct JournalCorruption: Error, LocalizedError, Equatable {
    public var line: Int
    public var reason: String
    public var errorDescription: String? { "Journal damaged at line \(line): \(reason)" }
}

/// Append-only, hash-chained, fsync'd per record. Root-only in the helper
/// (`/var/db/org.siliconforest.installer/journal/<job>.jsonl`); tests use a temporary directory.
public final class ChainJournal: @unchecked Sendable {
    public let url: URL
    public let jobID: UUID
    private let lock = NSLock()
    private(set) public var records: [JournalRecord] = []
    /// Called after each record reaches the disk. Fault injection throws here to "kill" the engine
    /// at exactly that record.
    public var afterAppend: (@Sendable (JournalRecord) throws -> Void)?
    /// Set when loading dropped a torn final line (power lost mid-write).
    public private(set) var recoveredTornTail = false

    public static let defaultDirectory = URL(fileURLWithPath: "/var/db/org.siliconforest.installer/journal", isDirectory: true)

    public init(directory: URL, jobID: UUID = UUID()) throws {
        self.jobID = jobID
        url = directory.appendingPathComponent("\(jobID.uuidString).jsonl")
        try FileManager.default.ensureDirectory(directory)
        if FileManager.default.fileExists(atPath: url.path) {
            let (recs, torn) = try Self.load(url)
            records = recs
            recoveredTornTail = torn
            if torn { try rewrite() }
        } else {
            guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw EngineError(.internalError, "can't create the journal at \(url.path)")
            }
        }
    }

    /// Opens an existing job's journal.
    public static func open(_ url: URL) throws -> ChainJournal {
        guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { throw EngineError(.internalError, "not a job journal: \(url.lastPathComponent)") }
        return try ChainJournal(directory: url.deletingLastPathComponent(), jobID: id)
    }

    /// Lists unfinished jobs in a directory (the next launch routes these to Resume).
    public static func unfinished(in dir: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "jsonl" }.filter { url in
            guard let (recs, _) = try? load(url) else { return true }
            return !recs.contains { $0.kind == .end }
        }
    }

    @discardableResult
    public func append(_ kind: JournalRecord.Kind, step: String? = nil, args: JArgs? = nil, result: JArgs? = nil, note: String? = nil) throws -> JournalRecord {
        lock.lock()
        let rec = JournalRecord(seq: UInt64(records.count + 1), prev: records.last?.hash ?? String(repeating: "0", count: 64),
                                t: Clock.stamp(), kind: kind, step: step, args: args, result: result, note: note)
        do {
            var line = try Canonical.data(rec)
            line.append(0x0A)
            let h = try FileHandle(forWritingTo: url)
            defer { try? h.close() }
            try h.seekToEnd()
            try h.write(contentsOf: line)
            try h.synchronize()   // fsync per record: a record that isn't on disk isn't a record
            records.append(rec)
        } catch {
            lock.unlock()
            throw error
        }
        lock.unlock()
        try afterAppend?(rec)
        return rec
    }

    private func rewrite() throws {
        var data = Data()
        for r in records { data.append(try Canonical.data(r)); data.append(0x0A) }
        try data.write(to: url, options: .atomic)
    }

    /// Reads and verifies the chain. A torn final line (no newline, or not JSON) is dropped and
    /// reported; any other break in the chain is corruption.
    public static func load(_ url: URL) throws -> ([JournalRecord], tornTail: Bool) {
        let data = try Data(contentsOf: url)
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: false).map { Data($0) }
        var torn = false
        if let last = lines.last, last.isEmpty { lines.removeLast() } else if !lines.isEmpty, !data.isEmpty { torn = true }
        var out: [JournalRecord] = []
        let d = Canonical.decoder()
        for (i, line) in lines.enumerated() {
            guard let r = try? d.decode(JournalRecord.self, from: line) else {
                if i == lines.count - 1 { torn = true; break }
                throw JournalCorruption(line: i + 1, reason: "not a record")
            }
            let expectedPrev = out.last?.hash ?? String(repeating: "0", count: 64)
            guard r.prev == expectedPrev, r.seq == UInt64(out.count + 1) else {
                throw JournalCorruption(line: i + 1, reason: "hash chain broken")
            }
            out.append(r)
        }
        return (out, torn)
    }
}
