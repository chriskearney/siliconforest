import Foundation

/// Typed verbs: the only things the engine can ask the backend to do to a disk. Partitions are
/// named by UUID; a verb never carries a shell string or a diskN.
public enum DiskVerb: Codable, Sendable, Hashable {
    case resize(store: String, to: Int64)
    /// `to == 0`: grow to fill the free space directly after (removal only).
    case grow(store: String)
    case addPartition(role: String, after: String, content: String, label: String, bytes: Int64)
    case formatFAT32(partition: String, label: String)
    case addVolume(store: String, name: String, role: String)
    case writeFiles(partition: String, volumeRole: String?, files: [String])
    case writeRaw(partition: String, offset: Int64, bytes: Int64)
    case deleteContainer(partition: String)
    case eraseToFree(partition: String)

    public var target: String {
        switch self {
        case .resize(let s, _), .grow(let s), .addVolume(let s, _, _): return s
        case .addPartition(_, let a, _, _, _): return a
        case .formatFAT32(let p, _), .writeFiles(let p, _, _), .writeRaw(let p, _, _), .deleteContainer(let p), .eraseToFree(let p): return p
        }
    }

    public var summary: String {
        switch self {
        case .resize(let s, let to): return "resize \(s.prefix(8)) to \(to)"
        case .grow(let s): return "grow \(s.prefix(8))"
        case .addPartition(let r, _, _, _, let b): return "add \(r) (\(b) B)"
        case .formatFAT32(let p, let l): return "format \(p.prefix(8)) FAT32 \(l)"
        case .addVolume(_, let n, let r): return "add volume \(n) (\(r))"
        case .writeFiles(let p, _, let f): return "write \(f.count) file(s) to \(p.prefix(8))"
        case .writeRaw(let p, let o, let b): return "raw write \(b) B at \(o) on \(p.prefix(8))"
        case .deleteContainer(let p): return "delete container \(p.prefix(8))"
        case .eraseToFree(let p): return "erase \(p.prefix(8)) to free space"
        }
    }
}

/// Ported from SF-AJ's `sf_gate.py` (ENGINE §6). Every disk-changing verb passes `admit` before it
/// runs and `verifyAfter` after; the gate is built from the approved plan and the job's journal,
/// so it knows exactly which objects this job created.
public struct Gate: Sendable {
    public let plan: EnginePlan
    /// The partition table saved before the first write.
    public let original: ImageTopology
    /// Partition UUIDs this job created, by role (from journal evidence).
    public var created: [String: String]

    public init(plan: EnginePlan, original: ImageTopology, created: [String: String] = [:]) {
        self.plan = plan; self.original = original; self.created = created
    }

    var ownedUUIDs: Set<String> {
        var s = Set(created.values)
        if plan.operation == .remove, let o = plan.owned { s.formUnion(o.all) }
        return s
    }

    public func admit(_ verb: DiskVerb, now: ImageTopology, rollback: Bool = false) throws {
        func refuse(_ why: String) -> SafetyRefusal { SafetyRefusal("gate: \(verb.summary): \(why)") }
        switch verb {
        case .resize(let store, let to):
            guard store == plan.macOS.store else { throw refuse("only the planned container may be resized") }
            if plan.operation == .install {
                if rollback { guard to == plan.macOS.from else { throw refuse("rollback grows back to exactly \(plan.macOS.from)") } }
                else { guard to == plan.macOS.to else { throw refuse("not the planned size \(plan.macOS.to)") } }
                guard now.partition(uuid: store)?.size != to else { throw refuse("already that size") }
                if rollback {
                    // Growing back needs the space directly after macOS to be free of anything we made.
                    if let n = now.next(after: store), ownedUUIDs.contains(n.uuid) { throw refuse("our partitions are still in the way") }
                }
            } else {
                throw refuse("removal grows macOS only to fill, never to a size")
            }
        case .grow(let store):
            guard plan.operation == .remove, store == plan.macOS.store else { throw refuse("only removal regrows macOS") }
            if let n = now.next(after: store), ownedUUIDs.contains(n.uuid) { throw refuse("our partitions are still in the way") }
        case .addPartition(let role, let after, let content, _, let bytes):
            guard plan.operation == .install, !rollback, let np = plan.partition(role) else { throw refuse("not in the plan") }
            guard np.content == content, np.bytes == bytes else { throw refuse("differs from the planned partition") }
            guard created[role] == nil else { throw refuse("this job already created its \(role)") }
            let expectedAfter: String? = np.after == "@macos" ? plan.macOS.store : created[String(np.after.dropFirst())]
            guard let expectedAfter, after == expectedAfter else { throw refuse("must follow \(np.after)") }
            // Inside the planned span: from the end of macOS (resized) to the next pre-existing partition.
            guard let prev = now.partition(uuid: after) else { throw refuse("predecessor not found") }
            let nextOriginal = original.next(after: plan.macOS.store)
            let limit = nextOriginal?.offset ?? (now.size - 20_480)
            guard prev.end + bytes <= limit else { throw refuse("would run into the next existing partition") }
            if after == plan.macOS.store { guard prev.size == plan.macOS.to else { throw refuse("macOS isn't at its planned size yet") } }
        case .formatFAT32(let p, _), .writeFiles(let p, _, _), .writeRaw(let p, _, _):
            guard created.values.contains(p) else { throw refuse("only objects this job created may be formatted or written") }
            if case .writeRaw(_, let off, let b) = verb, let part = now.partition(uuid: p) {
                guard off >= 0, off + b <= part.size else { throw refuse("outside the partition") }
            }
        case .addVolume(let store, _, _):
            guard created["stub"] == store else { throw refuse("volumes are added only to this job's stub") }
        case .deleteContainer(let p), .eraseToFree(let p):
            guard ownedUUIDs.contains(p) else { throw refuse("only what this job (or the proved install) created may be deleted") }
            // An install deletes nothing outside a rollback, except the booter diskutil added for it.
            if plan.operation == .install && !rollback && p != created["booter"] { throw refuse("an install deletes nothing except while rolling back") }
        }
    }

    /// After each change: stop everything if any pre-existing partition moved, vanished or changed
    /// size, apart from the planned resize, or if anything appeared that this job didn't make.
    public func verifyAfter(_ now: ImageTopology) throws {
        for p in original.partitions {
            guard let q = now.partition(uuid: p.uuid) else {
                if plan.operation == .remove, plan.owned?.all.contains(p.uuid) == true { continue }
                throw EngineError(.inconsistent, "partition \(p.uuid) vanished")
            }
            guard q.offset == p.offset else { throw EngineError(.inconsistent, "partition \(p.uuid) moved") }
            if p.uuid == plan.macOS.store {
                let allowed: Set<Int64> = plan.operation == .install ? [plan.macOS.from, plan.macOS.to] : [p.size, plan.macOS.to]
                guard allowed.contains(q.size) else { throw EngineError(.inconsistent, "macOS is \(q.size) bytes, neither planned size") }
            } else if q.size != p.size {
                throw EngineError(.inconsistent, "partition \(p.uuid) changed size")
            }
        }
        let known = Set(original.partitions.map(\.uuid)).union(created.values)
        if let stranger = now.partitions.first(where: { !known.contains($0.uuid) }) {
            throw EngineError(.inconsistent, "an unexpected partition appeared (\(stranger.content), \(stranger.size) B)")
        }
    }
}
