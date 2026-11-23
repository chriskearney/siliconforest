import Foundation
import SFInstallKit

/// ENGINE §7 state codes, in execution order. S42 runs after S47 because the kernel is personalised
/// with the root partition's UUID and LBA, which exist only once S45 has created it.
public enum StepCode: String, Codable, Sendable, CaseIterable {
    case S00, S05, S08, S10, S15, S20, S25, S30, S32, S35, S40, S45, S46, S47, S42, S50, S52, S55, S60, S65, S68, S70
    case U10, U20, U30, U40

    public static let install: [StepCode] = [.S00, .S05, .S08, .S10, .S15, .S20, .S25, .S30, .S32, .S35, .S40, .S45, .S46, .S47, .S42,
                                             .S50, .S52, .S55, .S60, .S65, .S68, .S70]
    public static let removal: [StepCode] = [.U10, .U20, .U30, .U40]

    /// Steps at or past S20 write to the disk (ENGINE §7 "first disk write below this line").
    public var writesDisk: Bool {
        switch self {
        case .S00, .S05, .S08, .S10, .S15: return false
        default: return true
        }
    }

    public var title: String {
        switch self {
        case .S00: return "Preflight"
        case .S05: return "Approved"
        case .S08: return "Helper"
        case .S10: return "Fetch the release"
        case .S15: return "Verify every file"
        case .S20: return "Update macOS's admin list (updatePreboot)"
        case .S25: return "Shrink macOS"
        case .S30: return "Create the stub container"
        case .S32: return "Create the stub's volumes"
        case .S35: return "Install the stub's startup files"
        case .S40: return "Create and format SFBOOT"
        case .S45: return "Create the root partition"
        case .S46: return "Remove the Apple_Boot booter diskutil adds"
        case .S47: return "Write the root image and read it back"
        case .S42: return "Personalise and copy stage 2 and the kernel"
        case .S50: return "Write the firmware slot"
        case .S52: return "Write the boot-receipt slot"
        case .S55: return "Stage the boot object"
        case .S60: return "Stage SiliconForest Setup for recoveryOS"
        case .S65: return "Set SiliconForest for the next startup (bless)"
        case .S68: return "Hand off to recoveryOS"
        case .S70: return "Awaiting recovery"
        case .U10: return "Restore the previous startup disk"
        case .U20: return "Delete SiliconForest's partitions"
        case .U30: return "Give the space back to macOS"
        case .U40: return "Check the partition table against the original"
        }
    }
}

public enum StepStatus: String, Codable, Sendable {
    case none, intent, evidence, checkpoint, simulated, rollbackIntent, rolledBack
}

/// The state a journal describes. The journal decides the state (ENGINE §7).
public struct JobState: Sendable {
    public var plan: EnginePlan?
    public var original: ImageTopology?
    public var status: [StepCode: StepStatus] = [:]
    public var evidence: [StepCode: JArgs] = [:]
    public var created: [String: String] = [:]
    public var end: JobEnd?
    public var failed: [StepCode: String] = [:]
    public var approvals: [ApprovalNeeded] = []

    /// "No changes were made" only when the journal proves it: no intent at or past S20.
    public var noChangesMade: Bool

    public init(_ records: [JournalRecord]) {
        var noChanges = true
        for r in records {
            let code = r.step.flatMap(StepCode.init(rawValue:))
            switch r.kind {
            case .begin:
                if let s = r.args?["plan"]?.string { plan = try? Canonical.decoder().decode(EnginePlan.self, from: Data(s.utf8)) }
                if let s = r.args?["original"]?.string { original = try? Canonical.decoder().decode(ImageTopology.self, from: Data(s.utf8)) }
            case .intent:
                if let code { status[code] = .intent; if code.writesDisk { noChanges = false } }
            case .evidence, .check:
                guard let code else { break }
                if r.kind == .check, r.result?["outcome"]?.string != "done" { break }
                status[code] = .evidence
                evidence[code] = r.result ?? [:]
                if let role = r.result?["role"]?.string, let uuid = r.result?["uuid"]?.string { created[role] = uuid }
                if let booter = r.result?["booter"]?.string { created["booter"] = booter }
            case .checkpoint: if let code { status[code] = .checkpoint }
            case .simulated:
                if let code { status[code] = .simulated }
                if let a = r.args, let step = r.step {
                    approvals.append(ApprovalNeeded(step: step, command: a["command"].flatMap { if case .a(let v) = $0 { return v.compactMap(\.string) }; return nil } ?? [],
                                                    reason: a["reason"]?.string ?? ""))
                }
            case .failed: if let code { failed[code] = r.note ?? "" }
            case .rollbackIntent: if let code { status[code] = .rollbackIntent }
            case .rolledBack:
                if let code {
                    status[code] = .rolledBack
                    if let role = r.result?["removed"]?.string { created.removeValue(forKey: role) }
                }
            case .end: end = r.result?["end"]?.string.flatMap(JobEnd.init(rawValue:))
            case .note, .rollbackEvidence: break
            }
        }
        noChangesMade = noChanges
    }

    public func done(_ c: StepCode) -> Bool { status[c] == .checkpoint || status[c] == .simulated }
}

public enum CheckResult: Sendable, Equatable {
    case done(JArgs)
    case notDone
    case cannotTell(String)
}

/// Where fault injection strikes (tests only; the app never builds one).
public struct FaultPlan: Sendable {
    /// Kill the engine right after journal record `seq` reaches the disk.
    public var killAfterRecord: UInt64?
    /// Kill after this step's disk command ran, before its evidence is journaled.
    public var killAfterCommand: StepCode?
    /// As `killAfterCommand`, and detach the image first: a power cut.
    public var powerLossAfterCommand: StepCode?
    /// The helper dies this many seconds into a resize, leaving `diskutil` running.
    public var resizeDieAfter: Double?
    public init(killAfterRecord: UInt64? = nil, killAfterCommand: StepCode? = nil, powerLossAfterCommand: StepCode? = nil, resizeDieAfter: Double? = nil) {
        self.killAfterRecord = killAfterRecord; self.killAfterCommand = killAfterCommand; self.powerLossAfterCommand = powerLossAfterCommand
        self.resizeDieAfter = resizeDieAfter
    }
}

public enum EngineEvent: Sendable {
    case step(StepCode, String)
    case resize(ResizeEvent)
    case checked(StepCode, CheckResult)
    case rollback(StepCode)
    case simulated(ApprovalNeeded)
}

/// Runs an approved plan against a disk image, journaling intent before and evidence after every
/// change. `run` starts or resumes; `rollback` undoes everything up to the recovery handoff.
public final class InstallEngine: @unchecked Sendable {
    public let backend: DiskImageBackend
    public let journal: ChainJournal
    public let profile: DeviceProfile
    public let release: ReleaseManifest?
    /// Where the release's files come from (a channel URL in the app; a local directory here).
    public let releaseSource: URL?
    /// The work directory for downloads (inside macOS's container on a real Mac).
    public let workDir: URL
    public var faults: FaultPlan
    public var launcher: ResizeLauncher
    public var resizeTiming: ResizeSupervisor.Timing
    public var onEvent: (@Sendable (EngineEvent) -> Void)?
    /// Optional path to a built SFRecovery binary to stage (S60); a placeholder file otherwise.
    public var recoveryBinary: URL?
    /// For removal: the install's proof.
    public var proof: InstallProof?
    /// The operation in progress, for error reports.
    var breadcrumb: String?

    public init(backend: DiskImageBackend, journal: ChainJournal, profile: DeviceProfile, release: ReleaseManifest?, releaseSource: URL?,
                workDir: URL, faults: FaultPlan = FaultPlan(), launcher: ResizeLauncher = SpawnLauncher(),
                resizeTiming: ResizeSupervisor.Timing = .init()) {
        self.backend = backend; self.journal = journal; self.profile = profile; self.release = release
        self.releaseSource = releaseSource; self.workDir = workDir; self.faults = faults; self.launcher = launcher; self.resizeTiming = resizeTiming
        if let k = faults.killAfterRecord {
            journal.afterAppend = { rec in if rec.seq == k { throw SimulatedKill(at: "after journal record \(k) (\(rec.kind.rawValue) \(rec.step ?? ""))") } }
        }
    }

    public var state: JobState { JobState(journal.records) }

    // MARK: begin

    /// Opens the job: binds the approved plan to a fresh read of the disk (refusing on any difference),
    /// saves the original partition table, and records approval. Nothing is written to the disk.
    public func begin(_ approved: EnginePlan) throws {
        guard journal.records.isEmpty else { throw EngineError(.internalError, "this job has already begun") }
        let t = try backend.topology()
        let limits = try backend.limits(store: approved.macOS.store)
        try EnginePlanner.bind(approved, topology: t, limits: limits, profile: profile, release: release, proof: proof)
        let planJSON = String(decoding: try Canonical.data(approved), as: UTF8.self)
        let originalJSON = String(decoding: try Canonical.data(t), as: UTF8.self)
        try journal.append(.begin, args: ["plan": .s(planJSON), "plan_digest": .s(approved.digest), "original": .s(originalJSON),
                                          "layout_digest": .s(t.layoutDigest), "image": .s(backend.imagePath)])
    }

    // MARK: run / resume

    @discardableResult
    public func run() throws -> JobEnd {
        let st = state
        guard let plan = st.plan, let original = st.original else { throw EngineError(.internalError, "job has not begun") }
        if let end = st.end { return end }
        var gate = Gate(plan: plan, original: original, created: st.created)
        let order = plan.operation == .install ? StepCode.install : StepCode.removal
        for code in order {
            var s = state
            if s.done(code) || s.status[code] == .rolledBack { continue }
            if s.status[code] == .rollbackIntent { throw EngineError(.inconsistent, "a rollback is in progress; finish it with Roll Back") }
            gate.created = s.created
            onEvent?(.step(code, code.title))
            if s.status[code] == .evidence {
                try journal.append(.checkpoint, step: code.rawValue)
                continue
            }
            if s.status[code] == .intent {
                // Interrupted between intent and evidence: the step's idempotent check decides.
                let r = try check(code, plan: plan, gate: gate)
                onEvent?(.checked(code, r))
                switch r {
                case .done(let ev):
                    try journal.append(.check, step: code.rawValue, result: ev.merging(["outcome": .s("done")]) { a, _ in a })
                    try journal.append(.checkpoint, step: code.rawValue)
                    continue
                case .notDone:
                    try journal.append(.check, step: code.rawValue, result: ["outcome": .s("not-done")])
                case .cannotTell(let why):
                    try journal.append(.check, step: code.rawValue, result: ["outcome": .s("cannot-tell"), "why": .s(why)])
                    try journal.append(.failed, step: code.rawValue, note: "cannot tell: \(why)")
                    throw EngineError(.inconsistent, "Can't tell whether “\(code.title)” finished", detail: why)
                }
            }
            s = state
            gate.created = s.created
            do {
                try perform(code, plan: plan, gate: &gate)
            } catch let k as SimulatedKill {
                throw k
            } catch let e as SafetyRefusal {
                _ = try? journal.append(.failed, step: code.rawValue, note: e.reason)
                throw e
            } catch {
                let ns = error as NSError
                let where_ = breadcrumb.map { " during \($0)" } ?? ""
                let ee = (error as? EngineError) ?? EngineError(.internalError, error.localizedDescription + where_,
                                                                detail: "\(ns.domain) \(ns.code) \(ns.userInfo[NSFilePathErrorKey] ?? "")")
                _ = try? journal.append(.failed, step: code.rawValue, result: ["class": .s(ee.errorClass.rawValue)], note: ee.errorDescription)
                throw ee
            }
        }
        let end: JobEnd = plan.operation == .install ? .handedOff : .committed
        try journal.append(.end, result: ["end": .s(end.rawValue)])
        return end
    }

    // MARK: rollback

    /// Undoes every step newest-first, from any state up to the recovery handoff. Each undo is
    /// idempotent, so a rollback interrupted at any record can simply be run again.
    @discardableResult
    public func rollback() throws -> JobEnd {
        var st = state
        guard let plan = st.plan, let original = st.original else { throw EngineError(.internalError, "job has not begun") }
        if st.end == .rolledBack { return .rolledBack }
        guard plan.operation == .install else { throw EngineError(.blocked, "a removal can't be rolled back; it can only finish") }
        guard st.end == nil else { throw EngineError(.blocked, "this job ended (\(st.end!.rawValue)); use Remove") }
        var gate = Gate(plan: plan, original: original, created: st.created)
        for code in StepCode.install.reversed() {
            st = state
            guard let status = st.status[code], status != .rolledBack, status != .none else { continue }
            // An interrupted step may have made something: find it by span before undoing.
            if status == .intent || status == .rollbackIntent, [.S30, .S40, .S45, .S46].contains(code), st.evidence[code] == nil {
                gate.created = st.created
                if case .done(let ev) = try check(code, plan: plan, gate: gate) {
                    try journal.append(.check, step: code.rawValue, result: ev.merging(["outcome": .s("done")]) { a, _ in a })
                    st = state
                }
            }
            gate.created = st.created
            onEvent?(.rollback(code))
            try journal.append(.rollbackIntent, step: code.rawValue)
            var result: JArgs = [:]
            switch code {
            case .S10, .S15:
                try? FileManager.default.removeItem(at: workDir)
            case .S25:
                let mac = try backend.topology().partition(uuid: plan.macOS.store)
                if mac?.size != plan.macOS.from {
                    try gate.admit(.resize(store: plan.macOS.store, to: plan.macOS.from), now: try backend.topology(), rollback: true)
                    let out = try resize(plan: plan, to: plan.macOS.from, code: code)
                    guard out == .completed else { throw EngineError(.appleTool, "growing macOS back didn't finish", detail: "\(out)") }
                }
            case .S30:
                if let u = st.created["stub"], try backend.topology().partition(uuid: u) != nil {
                    try gate.admit(.deleteContainer(partition: u), now: try backend.topology(), rollback: true)
                    try backend.deleteContainer(u)
                }
                result = ["removed": .s("stub")]
            case .S40:
                if let u = st.created["boot"], try backend.topology().partition(uuid: u) != nil {
                    try gate.admit(.eraseToFree(partition: u), now: try backend.topology(), rollback: true)
                    try backend.eraseToFree(u)
                }
                result = ["removed": .s("boot")]
            case .S45:
                if let u = st.created["root"], try backend.topology().partition(uuid: u) != nil {
                    try gate.admit(.eraseToFree(partition: u), now: try backend.topology(), rollback: true)
                    try backend.eraseToFree(u)
                }
                result = ["removed": .s("root")]
            case .S46:
                if let u = st.created["booter"], try backend.topology().partition(uuid: u) != nil {
                    try gate.admit(.eraseToFree(partition: u), now: try backend.topology(), rollback: true)
                    try backend.eraseToFree(u)
                }
                result = ["removed": .s("booter")]
            case .S65:
                // Restore the previous default: simulated on an image, like the bless it undoes.
                result = ["covered": .s("simulated: restore previous startup disk (needs root)")]
            case .S68:
                if let stub = st.created["stub"], try backend.topology().partition(uuid: stub) != nil {
                    try unhide(stub: stub)
                }
            default:
                result = ["covered": .s(Self.coveredBy(code))]
            }
            if code.writesDisk { try gate.verifyAfter(try backend.freshTopology()) }
            try journal.append(.rolledBack, step: code.rawValue, result: result)
        }
        // Prove the partition table is the one saved before the first write.
        let now = try backend.topology()
        guard now.digestForm == original.digestForm else {
            try journal.append(.failed, note: "after rollback the partition table differs from the original")
            throw EngineError(.inconsistent, "The partition table doesn't match the one saved before installing")
        }
        try journal.append(.end, result: ["end": .s(JobEnd.rolledBack.rawValue), "layout_digest": .s(now.layoutDigest)])
        return .rolledBack
    }

    static func coveredBy(_ c: StepCode) -> String {
        switch c {
        case .S32, .S35, .S55, .S60: return "covered by deleting the stub container (S30)"
        case .S42: return "covered by erasing SFBOOT (S40)"
        case .S47, .S50, .S52: return "covered by erasing the root partition (S45)"
        case .S20: return "simulated; harmless and left alone"
        default: return "nothing to undo"
        }
    }

    // MARK: kills and power loss

    func afterCommand(_ code: StepCode) throws {
        if faults.powerLossAfterCommand == code {
            try backend.detach(force: true)
            throw SimulatedKill(at: "power lost after \(code.rawValue)'s command")
        }
        if faults.killAfterCommand == code { throw SimulatedKill(at: "killed after \(code.rawValue)'s command") }
    }

    // MARK: paths

    var resizeLog: URL { journal.url.deletingPathExtension().appendingPathExtension("resize.log") }
    func work(_ name: String) -> URL { workDir.appendingPathComponent(name) }
}
