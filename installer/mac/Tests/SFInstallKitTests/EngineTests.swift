import Foundation
import Testing
@testable import SFInstallKit

private func fixture(_ name: String) throws -> DiskFixture { try DiskFixture.named(name) }
private func j293() throws -> DeviceProfile {
    try #require(ProfileStore.profile(id: "J293"))
}

@Suite("Profiles")
struct ProfileTests {
    @Test func everyCanonicalProfileLoads() throws {
        let all = ProfileStore.loadAll()
        #expect(all.contains { $0.id == "J293" } && all.contains { $0.id == "J313" })
        let air = try #require(ProfileStore.profile(id: "J313"))
        #expect(air.matches(hwModel: "MacBookAir10,1", board: nil) && air.soc.id == "t8103")
    }

    @Test func loadsCanonicalJ293() throws {
        let p = try j293()
        #expect(p.sourceFormat == "canonical")   // installer/profiles/J293.json, not a fixture
        #expect(p.soc.id == "t8103" && p.soc.name == "Apple M1")
        #expect(p.modelIdentifiers.contains("MacBookPro17,1"))
        #expect(p.board == "J293AP")
        #expect(p.support.minMacOS == "13.5")
        #expect(p.support.gatedMajors.contains { $0.major == 27 && $0.gate == "S11" && !$0.passed })
        #expect(p.support.maximumTestedMajor == 27)
        #expect(p.partitioning.stubContainerBytes == 2_499_805_184)
        #expect(p.partitioning.bootPartition.name == "SFBOOT" && p.partitioning.bootPartition.bytes == 524_288_000)
        #expect(p.partitioning.alignmentBytes == 1_048_576)
        #expect(p.partitioning.macOSMinFreeBytes == 38_000_000_000)
        #expect(p.partitioning.rootFilesystem == "ext4")
        #expect(p.kernel.bootArgs.contains("sfnvme=3"))
        #expect(p.powerButtonCopy?.contains("Touch ID") == true)
        #expect(p.minimumFootprint < p.recommendedFootprint)
        #expect(p.matches(hwModel: "MacBookPro17,1", board: nil))
        #expect(p.matches(hwModel: nil, board: "j293ap"))
        #expect(!p.matches(hwModel: "Mac17,2", board: "J704AP"))
    }

    @Test func minimalProfileDecodesWithDefaults() throws {
        let json = #"{"id":"J999","soc":{"id":"t9999","name":"Test"},"partitioning":{"stubContainerBytes":1,"bootPartition":{"name":"B","format":"fat32","bytes":1},"rootMinBytes":1,"rootRecommendedBytes":2,"macOSMinFreeBytes":1,"alignmentBytes":4096,"rootFilesystem":"ext4"},"futureKey":true}"#
        let p = try ProfileDecoder.decode(Data(json.utf8))
        #expect(p.board == "J999AP")
        #expect(p.firmware.isEmpty && p.quirks.isEmpty)
        #expect(p.support.status == "experimental")
    }
}

@Suite("Disk model and sizing")
struct SizingTests {
    @Test func detectsMacOSAndNoInstall() throws {
        let s = try fixture("j293-512").snapshot
        let d = try #require(s.internalDisk)
        #expect(d.macOSPartition?.identifier == "disk0s2")
        #expect(s.siliconForestInstalls.isEmpty)
    }

    @Test func detectsExistingInstall() throws {
        let installs = try fixture("j293-512-installed").snapshot.siliconForestInstalls
        #expect(installs.count == 1)
        let i = try #require(installs.first)
        #expect(i.isComplete && i.isOwned)
        #expect(i.partitions.map(\.identifier) == ["disk0s4", "disk0s5", "disk0s6"])
    }

    @Test func handMadeInstallIsUnprovenAndRefused() throws {
        let snap = try fixture("j293-512-devinstall").snapshot
        let i = try #require(snap.siliconForestInstalls.first)
        #expect(i.partitionClass == .sfUnproven)
        #expect(throws: PlanError.self) { try Planner.uninstallPlan(install: i, snapshot: snap) }
        if case .handMade = CompatibilityChecker.entryState(snapshot: snap, journal: nil) {} else { Issue.record("expected hand-made entry state") }
    }

    @Test func classificationOfAppleLayout() throws {
        let d = try #require(try fixture("j293-512").snapshot.internalDisk)
        let c = d.classify()
        #expect(c["disk0s1"] == .appleISC && c["disk0s2"] == .macOSPrimary && c["disk0s3"] == .appleRecovery)
        #expect(d.hasStandardAppleLayout)
    }

    @Test func constraintsRespectUsedSpaceAndHeadroom() throws {
        let p = try j293()
        let d = try #require(try fixture("j293-512").snapshot.internalDisk)
        let c = try #require(SizingConstraints(profile: p, disk: d))
        #expect(c.isFeasible)
        // ENGINE.md §4: macOS keeps used + reserve + downloads + drift
        #expect(c.macOSSize(for: c.maximum) >= c.macOSUsed + c.reserve + c.downloads + c.drift)
        #expect(c.reserve == 38_000_000_000 && !c.isSmallDisk)
        #expect(c.drift <= 8 * Bytes.gib)
        // default = max(profile default, 25% of the disk), never the minimum
        #expect(c.recommended > c.minimum && c.recommended >= c.stub + c.boot + Int64(Double(d.size) * 0.25) - Bytes.gb)
        #expect(c.snap(1) == c.minimum)
        #expect(c.snap(Int64.max / 4) == c.maximum)
        #expect(c.snap(80 * Bytes.gb + 300 * Bytes.mb) == 80 * Bytes.gb)
        #expect(c.limit(for: c.maximum + Bytes.gb) == .macOSReserve)
        #expect(c.presets.map(\.id).first == "recommended" && c.presets.contains { $0.id == "maximum" })
    }

    @Test func fullDiskIsInfeasible() throws {
        let p = try j293()
        let d = try #require(try fixture("j293-256-full").snapshot.internalDisk)
        let c = try #require(SizingConstraints(profile: p, disk: d))
        #expect(!c.isFeasible)
        #expect(c.shortfall > 0)
        #expect(throws: PlanError.self) {
            try Planner.installPlan(profile: p, snapshot: fixture("j293-256-full").snapshot, options: InstallOptions(siliconForestSize: 20 * Bytes.gb))
        }
    }

    @Test func byteParsingAndFormatting() {
        #expect(Bytes.parse("80G") == 80 * Bytes.gb)
        #expect(Bytes.parse("512M") == 512 * Bytes.mb)
        #expect(Bytes.parse("1.5T") == 1_500 * Bytes.gb)
        #expect(Bytes.format(414 * Bytes.gb) == "414 GB")
        #expect(Bytes.format(2_500_000_000) == "2.5 GB")
        #expect(Bytes.format(524_288_000) == "524 MB")
    }
}

@Suite("Compatibility")
struct CompatibilityTests {
    @Test func readyFixturePasses() throws {
        let f = try fixture("j293-512")
        let checks = CompatibilityChecker.run(facts: f.facts, snapshot: f.snapshot, profile: try j293())
        #expect(CompatibilityChecker.canProceed(checks))
        #expect(checks.first?.kind == .thisMac)
    }

    @Test func fullDiskAndBatteryBlock() throws {
        let f = try fixture("j293-256-full")
        let checks = CompatibilityChecker.run(facts: f.facts, snapshot: f.snapshot, profile: try j293())
        #expect(!CompatibilityChecker.canProceed(checks))
        #expect(checks.first { $0.kind == .freeSpace }?.status == .fail)
        #expect(checks.first { $0.kind == .power }?.status == .fail)   // AC is required
    }

    @Test func unsupportedMacFails() throws {
        var facts = try fixture("j293-512").facts
        facts.hwModel = "Mac17,2"; facts.board = "J704AP"
        let checks = CompatibilityChecker.run(facts: facts, snapshot: try fixture("j293-512").snapshot, profile: nil)
        #expect(checks.first { $0.kind == .thisMac }?.status == .fail)
    }

    @Test func oldMacOSFails() throws {
        var facts = try fixture("j293-512").facts
        facts.macOSVersion = "13.4"
        let checks = CompatibilityChecker.run(facts: facts, snapshot: try fixture("j293-512").snapshot, profile: try j293())
        #expect(checks.first { $0.kind == .macOS }?.status == .fail)
        facts.macOSVersion = "27.0"
        let blocked = CompatibilityChecker.run(facts: facts, snapshot: try fixture("j293-512").snapshot, profile: try j293())
        if case .macOSBlocked(let major, _)? = blocked.first(where: { $0.kind == .macOS })?.finding { #expect(major == 27) } else { Issue.record("27 not blocked in a release build") }
        let dev = CompatibilityChecker.run(facts: facts, snapshot: try fixture("j293-512").snapshot, profile: try j293(), allowGatedMajors: true)
        #expect(dev.first { $0.kind == .macOS }?.status == .warning)
        facts.macOSVersion = "28.0"
        let tooNew = CompatibilityChecker.run(facts: facts, snapshot: try fixture("j293-512").snapshot, profile: try j293(), allowGatedMajors: true)
        #expect(tooNew.first { $0.kind == .macOS }?.status == .fail)
        #expect(OSVersion("12.3") > OSVersion("12.2.1"))
        #expect(OSVersion("26.5.2") > OSVersion("15.6"))
    }
}

@Suite("Install engine")
struct EngineTests {
    func run(_ plan: InstallPlan, on backend: any DiskBackend) async -> (events: [InstallEvent], journal: [JournalEntry]) {
        let journal = Journal(url: nil)
        var events: [InstallEvent] = []
        for await e in InstallRunner(backend: backend, journal: journal).run(plan) { events.append(e) }
        return (events, await journal.entries)
    }

    @Test func planShape() throws {
        let p = try j293()
        let plan = try Planner.installPlan(profile: p, snapshot: try fixture("j293-512").snapshot, options: InstallOptions(siliconForestSize: 80 * Bytes.gb))
        #expect(plan.siliconForestSize <= 80 * Bytes.gb)
        #expect(plan.macOSSizeBefore - plan.macOSSizeAfter >= 80 * Bytes.gb - 4096)
        // D6: everything is downloaded and verified before the first disk write
        #expect(plan.steps.first?.id == .fetch)
        #expect(plan.steps[plan.firstWriteIndex].id == .resize)
        #expect(plan.steps[..<plan.firstWriteIndex].allSatisfy { $0.phase.isPreparing })
        #expect(plan.steps.last?.id == .finalPreparations)
        // firmware goes into the root's slot, after the image is written
        let fw = try #require(plan.steps.firstIndex { $0.id == .firmware })
        let img = try #require(plan.steps.firstIndex { $0.id == .rootImage })
        #expect(fw > img)
        #expect(plan.steps[fw].operations.allSatisfy { if case .writeFiles(let t, _, _, _) = $0 { return t == "@root" }; return false })
        // the resize can't be cancelled midway
        #expect(plan.steps.first { $0.id == .resize }?.interruptible == false)
        let cmds = plan.allCommands.map { $0.joined(separator: " ") }
        #expect(cmds.contains { $0.contains("diskutil apfs resizeContainer disk0s2") })
        #expect(cmds.contains { $0.contains("%\(GUID.linuxFilesystem)%") })
    }

    @Test func invalidNamesRejected() {
        #expect(InstallOptions.validate(name: "") != nil)
        #expect(InstallOptions.validate(name: String(repeating: "a", count: 29)) != nil)
        #expect(InstallOptions.validate(name: "Bad/Name") != nil)
        #expect(InstallOptions.validate(name: "SiliconForest 2") == nil)
    }

    @Test func dryRunInstallProducesExpectedLayout() async throws {
        let f = try fixture("j293-512")
        let backend = SimulatedDiskBackend(fixture: f, timeScale: 0)
        let plan = try Planner.installPlan(profile: try j293(), snapshot: f.snapshot, options: InstallOptions(siliconForestSize: 80 * Bytes.gb, installName: "Grove"))
        #expect(plan.steps.contains { $0.operations.contains { if case .bless(_, _, true) = $0 { return true }; return false } })
        let (events, journal) = await run(plan, on: backend)
        guard case .finished(let snap)? = events.last else { Issue.record("did not finish: \(events.last.map { "\($0)" } ?? "nil")"); return }
        let installs = snap.siliconForestInstalls
        #expect(installs.count == 1)
        #expect(installs.first?.name == "Grove")
        #expect(installs.first?.isComplete == true && installs.first?.isOwned == true)
        #expect(snap.internalDisk?.macOSPartition?.size == plan.macOSSizeAfter)
        // journal: plan, a checkpoint per step, finished
        #expect(journal.first?.event == .planned)
        #expect(journal.filter { $0.event == .checkpoint }.count == plan.steps.count)
        #expect(journal.last?.event == .finished)
        #expect(JournalState(entries: journal).finished)
    }

    @Test(arguments: [StepID.resize, .stubPartition, .stubFiles, .rootPartition, .rootImage, .readBack, .firmware, .finalPreparations])
    func failureAnywhereRollsBackToOriginalLayout(step: StepID) async throws {
        let f = try fixture("j293-512")
        let backend = SimulatedDiskBackend(fixture: f, timeScale: 0, failures: [FailureInjection(step: step, atFraction: 0.5)])
        let plan = try Planner.installPlan(profile: try j293(), snapshot: f.snapshot, options: InstallOptions(siliconForestSize: 64 * Bytes.gb))
        let (events, journal) = await run(plan, on: backend)
        #expect(events.contains { if case .failed = $0 { return true }; return false })
        guard case .rollbackFinished(let clean)? = events.last else { Issue.record("no rollback"); return }
        #expect(clean)
        let after = try await backend.snapshot()
        #expect(after.internalDisk?.partitions.map(\.identifier) == f.snapshot.internalDisk?.partitions.map(\.identifier))
        #expect(after.internalDisk?.macOSPartition?.size == f.snapshot.internalDisk?.macOSPartition?.size)
        #expect(JournalState(entries: journal).rolledBack)
    }

    @Test func stoppedRunCanBeUndoneOnRequest() async throws {
        let f = try fixture("j293-512")
        let backend = SimulatedDiskBackend(fixture: f, timeScale: 0, failures: [FailureInjection(step: .rootImage, atFraction: 0.5)])
        let plan = try Planner.installPlan(profile: try j293(), snapshot: f.snapshot, options: InstallOptions(siliconForestSize: 64 * Bytes.gb))
        let journal = Journal(url: nil)
        let runner = InstallRunner(backend: backend, journal: journal)
        var stopped: (Checkpoint, Int)?
        for await e in runner.run(plan, autoRollback: false) { if case .stopped(let c, let i) = e { stopped = (c, i) } }
        let (cp, idx) = try #require(stopped)
        #expect(!JournalState(entries: await journal.entries).noChangesMade)
        #expect(try await backend.snapshot().internalDisk?.partitions.count == 6)   // left as it was when it stopped
        var clean: Bool?
        for await e in runner.rollback(plan, from: cp, failedIndex: idx) { if case .rollbackFinished(let c) = e { clean = c } }
        #expect(clean == true)
        #expect(try await backend.snapshot().internalDisk?.partitions.map(\.identifier) == f.snapshot.internalDisk?.partitions.map(\.identifier))
    }

    @Test func failureBeforeFirstWriteProvesNothingChanged() async throws {
        let f = try fixture("j293-512")
        let backend = SimulatedDiskBackend(fixture: f, timeScale: 0, failures: [FailureInjection(step: .fetch, atFraction: 0.5)])
        let plan = try Planner.installPlan(profile: try j293(), snapshot: f.snapshot, options: InstallOptions(siliconForestSize: 64 * Bytes.gb))
        let journal = Journal(url: nil)
        for await _ in InstallRunner(backend: backend, journal: journal).run(plan, autoRollback: false) {}
        #expect(JournalState(entries: await journal.entries).noChangesMade)
    }

    @Test func failedRollbackIsReportedNotHidden() async throws {
        let f = try fixture("j293-512")
        let backend = SimulatedDiskBackend(fixture: f, timeScale: 0, failures: [
            FailureInjection(step: .rootImage, atFraction: 0.5),
            FailureInjection(operation: .deleteAPFSContainer, duringRollback: true),
        ])
        let plan = try Planner.installPlan(profile: try j293(), snapshot: f.snapshot, options: InstallOptions(siliconForestSize: 64 * Bytes.gb))
        let (events, journal) = await run(plan, on: backend)
        guard case .rollbackFinished(let clean)? = events.last else { Issue.record("no rollback"); return }
        #expect(!clean)
        #expect(journal.contains { $0.event == .rollbackIncomplete })
    }

    @Test func resumeFromCheckpointSkipsCompletedSteps() async throws {
        let f = try fixture("j293-512")
        let plan = try Planner.installPlan(profile: try j293(), snapshot: f.snapshot, options: InstallOptions(siliconForestSize: 64 * Bytes.gb))
        // First run: let it get through createStub, then "crash" (stop reading the stream).
        let backend = SimulatedDiskBackend(fixture: f, timeScale: 0)
        let journal = Journal(url: nil)
        let runner = InstallRunner(backend: backend, journal: journal)
        let stubIndex = try #require(plan.steps.firstIndex { $0.id == .stubPartition })
        for await e in runner.run(plan) {
            if case .stepCompleted(let i) = e, i == stubIndex { break }
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        let state = JournalState(entries: await journal.entries)
        #expect(state.checkpoint.completed.contains(.stubPartition))
        #expect(state.checkpoint.slots["stub"] != nil)
        // Resume on the same backend from the checkpoint.
        let resumed = InstallRunner(backend: backend, journal: journal)
        var last: InstallEvent?
        var started: [Int] = []
        for await e in resumed.run(plan, resume: state.checkpoint) {
            if case .stepStarted(let i) = e { started.append(i) }
            last = e
        }
        #expect(!started.contains(stubIndex))
        guard case .finished(let snap)? = last else { Issue.record("resume did not finish"); return }
        #expect(snap.siliconForestInstalls.count == 1)
    }

    @Test func uninstallRestoresMacOS() async throws {
        let f = try fixture("j293-512-installed")
        let install = try #require(f.snapshot.siliconForestInstalls.first)
        let plan = try Planner.uninstallPlan(install: install, snapshot: f.snapshot)
        // DESIGN §8.4: macOS becomes the startup disk first, then removal, regrow, check
        #expect(plan.steps.map(\.id) == [.setMacOSStartup, .removeSiliconForest, .returnSpace, .checkResult])
        #expect(plan.macOSSizeAfter == f.snapshot.internalDisk!.macOSPartition!.size + install.reclaimableBytes(on: f.snapshot.internalDisk!))
        #expect(install.reclaimableBytes(on: f.snapshot.internalDisk!) >= install.totalBytes)
        let (events, _) = await run(plan, on: SimulatedDiskBackend(fixture: f, timeScale: 0))
        guard case .finished(let snap)? = events.last else { Issue.record("uninstall did not finish"); return }
        #expect(snap.siliconForestInstalls.isEmpty)
        #expect(snap.internalDisk?.macOSPartition?.size == plan.macOSSizeAfter)
        #expect(snap.internalDisk?.partitions.count == 3)
    }

    @Test func simulatorRefusesWhatDiskutilWould() throws {
        var s = try fixture("j293-512").snapshot
        #expect(throws: BackendError.self) {
            try DiskModelMutator.apply(.resizeContainer(partition: "disk0s2", newSize: 10 * Bytes.gb), to: &s, resolve: { $0 })
        }
        #expect(throws: BackendError.self) {
            try DiskModelMutator.apply(.deletePartition("disk0s2"), to: &s, resolve: { $0 })
        }
        #expect(throws: BackendError.self) {
            try DiskModelMutator.apply(.addPartition(after: "disk0s2", slot: "x", content: .appleAPFS, name: "X", size: 1 * Bytes.gb, metadata: [:]), to: &s, resolve: { $0 })
        }
    }
}

@Suite("Read-only safety")
struct SafetyTests {
    @Test func allowListAcceptsOnlyQueries() {
        #expect(ReadOnlyCommand.isAllowed(["/usr/sbin/diskutil", "list", "-plist"]))
        #expect(ReadOnlyCommand.isAllowed(["/usr/sbin/diskutil", "info", "-plist", "disk0s2"]))
        #expect(ReadOnlyCommand.isAllowed(["/usr/bin/fdesetup", "status"]))
        #expect(!ReadOnlyCommand.isAllowed(["/usr/sbin/diskutil", "apfs", "resizeContainer", "disk0s2", "0"]))
        #expect(!ReadOnlyCommand.isAllowed(["/usr/sbin/diskutil", "addPartition", "disk0s2", "APFS", "x", "1G"]))
        #expect(!ReadOnlyCommand.isAllowed(["/usr/sbin/diskutil", "info", "-plist", "disk0s2", "extra"]))
        #expect(!ReadOnlyCommand.isAllowed(["/usr/sbin/diskutil", "info", "-plist", "/"]))
        #expect(!ReadOnlyCommand.isAllowed(["/usr/bin/csrutil", "disable"]))
        #expect(!ReadOnlyCommand.isAllowed(["/usr/sbin/nvram", "boot-args=x"]))
        #expect(!ReadOnlyCommand.isAllowed(["/usr/sbin/bless", "--mount", "/"]))
        #expect(throws: BackendError.self) { try ReadOnlyCommand.run(["/usr/sbin/diskutil", "eraseVolume", "free", "free", "disk0s9"]) }
    }

    @Test func realBackendRecordsInsteadOfExecuting() async throws {
        // The real backend projects onto a model; feed it a fixture-shaped snapshot via a plan
        // against the fixture and check every result is reported as not executed.
        let f = try fixture("j293-512")
        let plan = try Planner.installPlan(profile: try j293(), snapshot: f.snapshot, options: InstallOptions(siliconForestSize: 64 * Bytes.gb))
        let backend = RealDiskBackend()
        for op in plan.steps.flatMap(\.operations) where op.isMutating {
            // Without a projected snapshot of a J293, operations against fixture identifiers may be
            // refused by the model check; either way nothing executes.
            let r = try? await backend.perform(op, context: OperationContext(step: .fetch, stepIndex: 0), resolve: { $0 }) { _, _ in }
            #expect(r?.executed != true)
        }
    }

    @Test func parsersReadStatusText() {
        #expect(RealDiskBackend.parseFileVault("FileVault is On.") == .on)
        #expect(RealDiskBackend.parseFileVault("FileVault is Off.") == .off)
        #expect(RealDiskBackend.parseSIP("System Integrity Protection status: enabled.") == .enabled)
        #expect(RealDiskBackend.parseSIP("System Integrity Protection status: disabled.") == .disabled)
        let p = RealDiskBackend.parsePower("Now drawing from 'Battery Power'\n -InternalBattery-0 (id=1)\t64%; discharging; 3:10 remaining present: true")
        #expect(!p.onACPower && p.batteryPercent == 64)
    }
}
