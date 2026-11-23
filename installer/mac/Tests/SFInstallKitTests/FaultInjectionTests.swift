import Foundation
import Testing
@testable import SFEngine
import SFInstallKit

/// A runner that fails the first command matching a predicate, as a failing diskutil would.
final class FailingRunner: ToolRunner, @unchecked Sendable {
    let inner = ProcessToolRunner()
    let match: @Sendable ([String]) -> Bool
    let result: ToolResult
    private let lock = NSLock()
    private var fired = false
    init(match: @escaping @Sendable ([String]) -> Bool, status: Int32 = 1, stderr: String) {
        self.match = match; result = ToolResult(status: status, stderr: Data(stderr.utf8))
    }
    func run(_ argv: [String], stdin: Data?) throws -> ToolResult {
        lock.lock()
        if !fired && match(argv) { fired = true; lock.unlock(); return result }
        lock.unlock()
        return try inner.run(argv, stdin: stdin)
    }
}

/// Stands in for the resize process: hangs, fails with a known diskutil error, or reports its exit late.
final class FaultLauncher: ResizeLauncher, @unchecked Sendable {
    enum Mode { case hang(seconds: Double), fail(String), delayExit(seconds: Double) }
    let mode: Mode
    let real = SpawnLauncher()
    init(_ mode: Mode) { self.mode = mode }

    final class Delayed: ResizeProcess, @unchecked Sendable {
        let inner: ResizeProcess; let delay: Double
        private var exitedAt: Date?
        init(_ inner: ResizeProcess, delay: Double) { self.inner = inner; self.delay = delay }
        var pid: Int32 { inner.pid }
        func isRunning() -> Bool {
            if inner.isRunning() { return true }
            if exitedAt == nil { exitedAt = Date() }
            return Date().timeIntervalSince(exitedAt!) < delay
        }
        func exitStatus() -> Int32? { isRunning() ? nil : inner.exitStatus() }
    }

    func launch(_ argv: [String], log: URL) throws -> ResizeProcess {
        switch mode {
        case .hang(let s): return try real.launch(["/bin/sleep", String(s)], log: log)   // never touches the disk
        case .fail(let msg):
            try (msg + "\n").write(to: log, atomically: true, encoding: .utf8)
            return try real.launch(["/usr/bin/false"], log: log.appendingPathExtension("false"))
        case .delayExit(let s): return Delayed(try real.launch(argv, log: log), delay: s)
        }
    }
    func reattach(pid: Int32) -> ResizeProcess? { real.reattach(pid: pid) }
}

final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [EngineEvent] = []
    func add(_ e: EngineEvent) { lock.lock(); _events.append(e); lock.unlock() }
    var events: [EngineEvent] { lock.lock(); defer { lock.unlock() }; return _events }
    var resize: [ResizeEvent] { events.compactMap { if case .resize(let r) = $0 { return r }; return nil } }
}

@Suite("Fault injection on disk images", .serialized, .enabled(if: ImageLab.enabled))
struct FaultInjectionTests {

    /// Every journal state has a way forward and a way back. One uninterrupted install runs; right
    /// after each journal record reaches the disk, the image and journal are forked — the disk and
    /// journal exactly as a crash at that record would leave them — and on the fork a fresh engine
    /// must (a) resume to the end and (b), on a second fork, roll back to the original partition
    /// table. Every record with SF_FULL_SWEEP=1; a fixed sample otherwise.
    @Test func everyJournalStateHasAWayForwardAndBack() throws {
        let c = try ImageLab.fresh(.j293); defer { c.finish() }
        let profile = try ImageLab.profile()
        let original = try c.backend.topology()
        let plan = try ImageLab.plan(c, profile: profile)
        let j = try ChainJournal(directory: c.journalDir)
        let e = try ImageLab.engine(c, journal: j, profile: profile)
        try e.begin(plan)
        let sample: Set<UInt64> = ImageLab.sweepRecords ?? [2, 9, 13, 16, 22, 28, 35, 41, 47, 53, 60, 64]
        nonisolated(unsafe) var forward = 0, back = 0
        nonisolated(unsafe) var failures: [String] = []
        j.afterAppend = { rec in
            guard ImageLab.fullSweep || sample.contains(rec.seq) else { return }
            do {
                defer { try? c.backend.attach() }          // the reference run continues on the original
                let (a, aj) = try ImageLab.fork(c, journal: j)
                defer { a.finish() }
                let (b, bj) = try ImageLab.fork(a, journal: aj)
                if rec.kind != .end {
                    let be = try ImageLab.engine(b, journal: bj, profile: profile)
                    if try be.rollback() != .rolledBack { failures.append("record \(rec.seq): rollback didn't finish") }
                    if try b.backend.topology().digestForm != original.digestForm { failures.append("record \(rec.seq): table differs after rollback") }
                    back += 1
                }
                b.finish()
                try a.backend.attach()
                let fe = try ImageLab.engine(a, journal: aj, profile: profile)
                let end = try fe.run()
                if end != .handedOff { failures.append("record \(rec.seq): forward ended \(end)") }
                try ImageEngineTests.expectInstalled(a, journal: aj, plan: plan)
                forward += 1
            } catch {
                failures.append("record \(rec.seq) (\(rec.kind.rawValue) \(rec.step ?? "")): \(error)")
            }
        }
        #expect(try e.run() == .handedOff)
        j.afterAppend = nil
        try ImageEngineTests.expectInstalled(c, journal: j, plan: plan)
        #expect(failures.isEmpty, "\(failures)")
        print("everyJournalState: \(j.records.count) records, \(forward) forward resumes, \(back) rollbacks, full=\(ImageLab.fullSweep)")
        #expect(forward >= (ImageLab.fullSweep ? j.records.count - 1 : sample.count - 1))
    }

    /// The same for a rollback: fork after each rollback record; each fork's rollback, resumed by a
    /// fresh engine, must finish and restore the table (J313, so Linux must also be untouched).
    @Test func everyRollbackStateFinishes() throws {
        let c = try ImageLab.fresh(.j313); defer { c.finish() }
        let profile = try ImageLab.profile("J313")
        let original = try c.backend.topology()
        let plan = try ImageLab.plan(c, profile: profile)
        let j = try ChainJournal(directory: c.journalDir)
        let e = try ImageLab.engine(c, journal: j, profile: profile, faults: FaultPlan(killAfterCommand: .S60))
        try e.begin(plan)
        #expect(throws: SimulatedKill.self) { try e.run() }
        let jr = try ChainJournal(directory: c.journalDir, jobID: j.jobID)
        let start = jr.records.count
        nonisolated(unsafe) var resumed = 0
        nonisolated(unsafe) var failures: [String] = []
        jr.afterAppend = { rec in
            guard ImageLab.fullSweep || (Int(rec.seq) - start) % 3 == 1 else { return }
            do {
                defer { try? c.backend.attach() }
                let (a, aj) = try ImageLab.fork(c, journal: jr)
                defer { a.finish() }
                if try ImageLab.engine(a, journal: aj, profile: profile).rollback() != .rolledBack { failures.append("rollback record \(rec.seq)") }
                if try a.backend.topology().digestForm != original.digestForm { failures.append("table after rollback record \(rec.seq)") }
                try Self.expectLinuxUntouched(a, original: original)
                resumed += 1
            } catch { failures.append("rollback record \(rec.seq): \(error)") }
        }
        #expect(try ImageLab.engine(c, journal: jr, profile: profile).rollback() == .rolledBack)
        jr.afterAppend = nil
        #expect(failures.isEmpty, "\(failures)")
        #expect(try c.backend.topology().digestForm == original.digestForm)
        try Self.expectLinuxUntouched(c, original: original)
        print("everyRollbackState: \(jr.records.count - start) rollback records, \(resumed) resumed forks")
        #expect(resumed >= 5)
    }

    /// Power cut (forced detach) right after the command of each disk step; the image comes back
    /// with new diskN numbers, and the engine finds everything again by UUID.
    @Test func powerLossAfterEachDiskStepResumes() throws {
        let c = try ImageLab.fresh(.j293); defer { c.finish() }
        let profile = try ImageLab.profile()
        let plan = try ImageLab.plan(c, profile: profile)
        let j = try ChainJournal(directory: c.journalDir)
        try ImageLab.engine(c, journal: j, profile: profile).begin(plan)
        let cuts: [StepCode] = [.S25, .S30, .S32, .S35, .S40, .S45, .S46, .S47, .S42, .S50, .S52, .S55, .S60, .S68]
        var wholeDisks: Set<String> = [try c.backend.wholeDisk()]
        // A small blank image attached while ours is "off" takes its diskN, so ours comes back renumbered.
        let spacerURL = c.dir.appendingPathComponent("spacer.dmg")
        #expect(try ProcessToolRunner().run(["/usr/bin/hdiutil", "create", "-quiet", "-size", "10m", "-layout", "GPTSPUD", spacerURL.path]).ok)
        let spacer = DiskImageBackend(imagePath: spacerURL)
        defer { if spacer.isAttached() { try? spacer.detach(force: true) } }
        for (i, cut) in cuts.enumerated() {
            let e = try ImageLab.engine(c, journal: try ChainJournal(directory: c.journalDir, jobID: j.jobID), profile: profile,
                                        faults: FaultPlan(powerLossAfterCommand: cut))
            #expect(throws: SimulatedKill.self) { try e.run() }
            #expect(!c.backend.isAttached())
            if i % 2 == 0 { try spacer.attach() }
            try c.backend.attach()
            if i % 2 == 0 { try spacer.detach(force: true) }
            wholeDisks.insert(try c.backend.wholeDisk())
        }
        #expect(wholeDisks.count >= 2, "the image came back under different disk numbers: \(wholeDisks)")
        let e = try ImageLab.engine(c, journal: try ChainJournal(directory: c.journalDir, jobID: j.jobID), profile: profile)
        #expect(try e.run() == .handedOff)
        try ImageEngineTests.expectInstalled(c, journal: try ChainJournal(directory: c.journalDir, jobID: j.jobID), plan: plan)
        let checks = JobState(try ChainJournal(directory: c.journalDir, jobID: j.jobID).records)
        _ = checks
        print("powerLoss: image came back as \(wholeDisks.sorted())")
    }

    /// diskutil fails creating the root: the step stops with the real error; Roll Back restores the
    /// table, and on a second copy Try Again finishes.
    @Test func failingDiskutilStopsThenRollBackOrTryAgain() throws {
        let c = try ImageLab.fresh(.j293); defer { c.finish() }
        let profile = try ImageLab.profile()
        let original = try c.backend.topology()
        let plan = try ImageLab.plan(c, profile: profile)
        let runner = FailingRunner(match: { $0.contains("addPartition") && $0.contains("%0FC63DAF-8483-4772-8E79-3D69D8477DE4%") },
                                   stderr: "Error: -69850: The disk is too small for the requested operation (simulated)")
        let failing = DiskImageBackend(imagePath: c.image, runner: runner)
        let (release, src) = try ImageLab.release()
        let j = try ChainJournal(directory: c.journalDir)
        let e = InstallEngine(backend: failing, journal: j, profile: profile, release: release, releaseSource: src, workDir: c.workDir,
                              resizeTiming: .tests)
        try e.begin(plan)
        do { try e.run(); Issue.record("should have failed") } catch let err as EngineError {
            #expect(err.errorClass == .appleTool && (err.detail ?? "").contains("-69850"))
        }
        #expect(JobState(j.records).failed[.S45] != nil)
        let (fork, fj) = try ImageLab.fork(c, journal: j)
        #expect(try ImageLab.engine(fork, journal: fj, profile: profile).rollback() == .rolledBack)
        #expect(try fork.backend.topology().digestForm == original.digestForm)
        fork.finish()
        try c.backend.attach()
        // Try Again on the original copy.
        #expect(try ImageLab.engine(c, journal: try ChainJournal(directory: c.journalDir, jobID: j.jobID), profile: profile).run() == .handedOff)
    }

    /// Resize: a known diskutil failure is classified (First Aid, nothing changed); a hang is
    /// reported and never killed; the helper dying mid-resize leaves diskutil running and the
    /// next engine reattaches; the topology showing the target before exit counts as done (#391).
    @Test func resizeFailureHangDeathAndEarlyCompletion() throws {
        let c = try ImageLab.fresh(.j293); defer { c.finish() }
        let profile = try ImageLab.profile()
        let plan = try ImageLab.plan(c, profile: profile)
        let j = try ChainJournal(directory: c.journalDir)
        func engine(_ l: ResizeLauncher, _ f: FaultPlan = FaultPlan()) throws -> (InstallEngine, EventLog) {
            let e = try ImageLab.engine(c, journal: try ChainJournal(directory: c.journalDir, jobID: j.jobID), profile: profile, faults: f, launcher: l)
            let log = EventLog(); e.onEvent = { log.add($0) }
            return (e, log)
        }
        try ImageLab.engine(c, journal: j, profile: profile).begin(plan)

        // 1. -69606: First Aid, macOS unchanged.
        var (e, log) = try engine(FaultLauncher(.fail("Error: -69606: A problem occurred while verifying the container (simulated)")))
        do { try e.run(); Issue.record("should fail") } catch let err as EngineError {
            #expect(err.message.contains("First Aid") && (err.detail ?? "").contains("-69606"))
        }
        #expect(try c.backend.topology().partition(uuid: plan.macOS.store)?.size == plan.macOS.from)

        // 2. Hang: a stall is reported, the process is left alone, the outcome is the truth (unchanged).
        (e, log) = try engine(FaultLauncher(.hang(seconds: 1.5)))
        #expect(throws: EngineError.self) { try e.run() }
        #expect(log.resize.contains { if case .stalled = $0 { return true }; return false })
        #expect(log.resize.contains { if case .exited(let s) = $0 { return s == 0 }; return false }, "sleep ran to its end: never killed")

        // 3. The helper dies mid-resize; the resize process keeps going (it is never killed); the
        //    next engine reattaches to it, waits for it, and tells the truth about the outcome.
        (e, log) = try engine(FaultLauncher(.hang(seconds: 2.5)), FaultPlan(resizeDieAfter: 0.1))
        #expect(throws: SimulatedKill.self) { try e.run() }
        let pid = try #require(e.lastResizePID(.S25))
        #expect(SpawnLauncher().reattach(pid: pid)?.isRunning() == true, "the resize outlived the helper")
        (e, log) = try engine(SpawnLauncher())
        #expect(throws: EngineError.self) { try e.run() }   // the stand-in changed nothing: unchanged, Try Again
        #expect(log.resize.contains(.reattached(pid: pid)))
        #expect(log.resize.contains(.exited(status: 0)), "reattached and waited for it to exit by itself")
        #expect((try ChainJournal(directory: c.journalDir, jobID: j.jobID)).records.contains { $0.result?["reattached"]?.int == Int64(pid) })
        // Try Again with the real resize.
        (e, log) = try engine(SpawnLauncher(), FaultPlan(killAfterCommand: .S30))
        #expect(throws: SimulatedKill.self) { try e.run() }
        #expect(try c.backend.topology().partition(uuid: plan.macOS.store)?.size == plan.macOS.to)

        // 4. #391 on the rollback's grow: target reached before the (delayed) exit.
        let (fork, fj) = try ImageLab.fork(c, journal: try ChainJournal(directory: c.journalDir, jobID: j.jobID))
        defer { fork.finish() }
        let fe = try ImageLab.engine(fork, journal: fj, profile: profile, launcher: FaultLauncher(.delayExit(seconds: 1.0)))
        let flog = EventLog(); fe.onEvent = { flog.add($0) }
        #expect(try fe.rollback() == .rolledBack)
        let r = flog.resize
        let reached = r.firstIndex { $0 == .targetReached }, exited = r.firstIndex { if case .exited = $0 { return true }; return false }
        #expect(reached != nil && exited != nil && reached! < exited!, "target reached before exit: \(r)")
    }

    /// J313: SiliconForest goes between macOS and the existing Linux stub; Linux's stub, ESP and
    /// root are never modified, and the gate refuses to touch them even if asked.
    @Test func j313InstallLeavesLinuxAloneAndTheGateRefusesIt() throws {
        let c = try ImageLab.fresh(.j313); defer { c.finish() }
        let profile = try ImageLab.profile("J313")
        let original = try c.backend.topology()
        let plan = try ImageLab.plan(c, profile: profile)
        let j = try ChainJournal(directory: c.journalDir)
        let e = try ImageLab.engine(c, journal: j, profile: profile)
        try e.begin(plan)
        #expect(try e.run() == .handedOff)
        try ImageEngineTests.expectInstalled(c, journal: j, plan: plan)
        try Self.expectLinuxUntouched(c, original: original)
        let t = try c.backend.topology()
        let st = JobState(j.records)
        let rootUUID = try #require(st.created["root"])
        let root = try #require(t.partition(uuid: rootUUID))
        let linuxStub = try #require(original.partitions.first { $0.apfs?.volumes.contains { $0.name == "Linux stub" } ?? false })
        #expect(root.end <= linuxStub.offset, "new partitions land between macOS and the Linux stub")

        var gate = Gate(plan: plan, original: original, created: st.created)
        gate.created = st.created
        let linuxRoot = try #require(original.partitions.first { $0.content == "Linux Filesystem" })
        let esp = try #require(original.partitions.first { $0.content == "EFI" })
        for verb in [DiskVerb.eraseToFree(partition: linuxRoot.uuid), .deleteContainer(partition: linuxStub.uuid), .formatFAT32(partition: esp.uuid, label: "X"),
                     .writeRaw(partition: linuxRoot.uuid, offset: 0, bytes: 4096), .resize(store: plan.macOS.store, to: plan.macOS.to - Bytes.gb)] {
            #expect(throws: SafetyRefusal.self) { try gate.admit(verb, now: t) }
            #expect(throws: SafetyRefusal.self) { try gate.admit(verb, now: t, rollback: true) }
        }
        // Removal gives the space back and the table matches the one saved before installing.
        let proof = try InstallProofReader.proof(from: j)
        let rj = try ChainJournal(directory: c.journalDir)
        let re = try ImageLab.engine(c, journal: rj, profile: profile); re.proof = proof
        try re.begin(try EnginePlanner.removalPlan(topology: t, profile: profile, proof: proof))
        #expect(try re.run() == .committed)
        #expect(try c.backend.topology().digestForm == original.digestForm)
        try Self.expectLinuxUntouched(c, original: original)
    }

    /// The approved plan binds to the disk: any change to the table, a tampered plan, or a plan
    /// below the live APFS minimum is refused before anything is written.
    @Test func planBindingRefusesDriftTamperingAndTheLiveMinimum() throws {
        let c = try ImageLab.fresh(.j293); defer { c.finish() }
        let profile = try ImageLab.profile()
        let plan = try ImageLab.plan(c, profile: profile)
        // Tampered: change the target after sealing.
        var tampered = plan; tampered.macOS.to -= Bytes.gb
        let j1 = try ChainJournal(directory: c.journalDir)
        #expect(throws: PlanRefusal.self) { try ImageLab.engine(c, journal: j1, profile: profile).begin(tampered) }
        // Resealed but not what the disk + request give: refused on digest.
        #expect(throws: PlanRefusal.self) { try ImageLab.engine(c, journal: j1, profile: profile).begin(tampered.sealed()) }
        // Asking for more than the live minimum allows.
        let mac = try #require(try c.backend.topology().macOS)
        let limits = try c.backend.limits(store: mac.uuid)
        let (release, _) = try ImageLab.release()
        #expect(throws: PlanRefusal.self) {
            try EnginePlanner.installPlan(topology: try c.backend.topology(), limits: limits, profile: profile, release: release,
                                          request: InstallRequest(siliconForestBytes: mac.size - limits.minimumPreferred + Bytes.gb, installID: "x"))
        }
        // The disk changes after approval (a partition appears in the free space): refused.
        try c.backend.diskutil(["apfs", "resizeContainer", mac.identifier, "\(plan.macOS.to)B"])
        #expect(throws: PlanRefusal.self) { try ImageLab.engine(c, journal: j1, profile: profile).begin(plan) }
        #expect(j1.records.isEmpty, "nothing journaled, nothing written")
    }

    static func expectLinuxUntouched(_ c: ImageLab.Case, original: ImageTopology) throws {
        let t = try c.backend.topology()
        for p in original.partitions where ["Linux Filesystem", "EFI"].contains(p.content) || (p.apfs?.volumes.contains { $0.name == "Linux stub" } ?? false) {
            let q = try #require(t.partition(uuid: p.uuid))
            #expect(q.offset == p.offset && q.size == p.size && q.content == p.content)
        }
        if let root = original.partitions.first(where: { $0.content == "Linux Filesystem" }) {
            #expect(try c.backend.readRaw(root.uuid, offset: 0, count: 4096) == Data(LinuxRootSentinel.bytes))
        }
    }
}
