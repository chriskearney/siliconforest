import SwiftUI
import Combine
import SFInstallKit
import SFCopy
import SFDesign

/// Every screen of docs/installer/UX-FLOW.md that this app shows.
public enum Screen: Hashable, Sendable {
    case welcome
    case check
    case prepare            // Before you begin
    case space              // Choose your space
    case options            // A few choices
    case review
    case approve            // Allow the installer to make changes
    case preparing
    case installing
    case recovery           // Get ready for Recovery
    case inRecovery(RecoveryStage)   // SFRecovery, simulated in the dry run
    case finish(FinishOutcome)
    case removeWhat         // U1
    case removeConfirm      // U2
    case removing           // U3
    case removed            // U4
    case failure

    /// Step dots: Check · Prepare · Space · Review · Install · Recovery · Finish.
    public var dotIndex: Int? {
        switch self {
        case .check: return 0
        case .prepare: return 1
        case .space, .options: return 2
        case .review: return 3
        case .approve, .preparing, .installing: return 4
        case .recovery, .inRecovery: return 5
        case .finish: return 6
        default: return nil
        }
    }

    /// Parallax position: the view drifts as you move through the flow.
    public var camera: Double {
        switch self {
        case .welcome: return -0.9
        case .check: return -0.65
        case .prepare: return -0.45
        case .space: return -0.25
        case .options: return -0.1
        case .review: return 0.05
        case .approve, .preparing: return 0.2
        case .installing: return 0.4
        case .recovery, .inRecovery: return 0.6
        case .finish: return 0.85
        case .removeWhat, .removeConfirm: return -0.4
        case .removing, .removed: return -0.2
        case .failure: return 0
        }
    }

    var isRun: Bool { self == .preparing || self == .installing || self == .removing }
}

public enum RecoveryStage: Hashable, Sendable { case password, working, ready }
public enum FinishOutcome: Hashable, Sendable { case verifying, installed, partial, didNotStart }

public enum RunMode: Equatable, Sendable { case dryRun, readOnly }

/// What a failure means for the person's Mac (UX-FLOW Part 5).
public enum FailureKind: Equatable, Sendable {
    case nothingChanged      // E1
    case canUndo             // E2
    case undoing             // E3
    case undone              // E4
    case needsAttention      // E5
    case removalStopped
    case notOurs
}

/// The one observable session (DESIGN §5): owns the current screen; screens are pure functions of it.
@MainActor
public final class Session: ObservableObject {
    // Where we are
    @Published public var screen: Screen = .welcome
    @Published public var showQuitConfirm = false
    @Published public var showDetails = false
    @Published public var showWhatIs = false
    @Published public var showDiagnostics = false
    @Published public var showCommands = false
    @Published public var showWhyNoStop = false

    // Environment
    public let mode: RunMode
    public let backend: any DiskBackend
    public let release: ReleaseInfo
    @Published public var profile: DeviceProfile?
    @Published public var facts: SystemFacts?
    @Published public var snapshot: DiskSnapshot?
    @Published public var loadError: String?

    // Check
    @Published public var checks: [CompatibilityCheck] = []
    @Published public var checksRevealed = 0
    @Published public var checksRunning = false
    @Published public var entry: EntryState = .fresh

    // Choices
    @Published public var siliconForestSize: Int64 = 0
    @Published public var sizeText = ""
    @Published public var limitHit: SizingConstraints.Limit = .none
    @Published public var showPartitionDetails = false
    @Published public var installName = "SiliconForest"
    @Published public var afterSetup: AfterSetup = .startOnceKeepMacOS
    @Published public var showAdvanced = false
    @Published public var keepDownloads = false
    @Published public var backupConfirmed = false
    @Published public var showSecurity = false
    @Published public var removeConfirmText = ""

    // Run
    @Published public var plan: InstallPlan?
    @Published public var stepStates: [RowState] = []
    @Published public var stepFraction: [Double] = []
    @Published public var stepDuration: [Double] = []
    @Published public var currentStep: Int?
    @Published public var stepDetail = ""
    @Published public var log: [LogLine] = []
    @Published public var runStarted: Date?
    @Published public var failureMessage: String?
    @Published public var failureKind: FailureKind?
    @Published public var failedStep: Int?
    @Published public var journalURL: URL?
    @Published public var undoProgress: [RowState] = [.waiting, .waiting, .waiting]
    @Published public var recoveryCountdown = 15
    @Published public var selectedInstall: SiliconForestInstall?
    /// Dawn reached during installation (frozen afterwards until the receipt is read).
    @Published public var dawnReached: Double = 0

    // Snapshot-only presentation state
    public var etaOverride: String?
    public var snapshotBusy = false
    public var snapshotHandleActive = false
    public var snapshotNameFocus = false
    public var journalDirectory: URL?
    public var stepPace: Double = 1
    public var quitConfirmed = false

    private var runner: InstallRunner?
    public private(set) var runTask: Task<Void, Never>?
    private var stoppedCheckpoint: Checkpoint?
    private var stepStartTimes: [Int: Date] = [:]

    public init(mode: RunMode, backend: any DiskBackend, release: ReleaseInfo = .placeholder) {
        self.mode = mode
        self.backend = backend
        self.release = release
    }

    // MARK: Derived

    public var isDryRun: Bool { mode == .dryRun }
    public var disk: PhysicalDisk? { snapshot?.internalDisk }
    public var constraints: SizingConstraints? {
        guard let profile, let disk else { return nil }
        return SizingConstraints(profile: profile, disk: disk, release: release)
    }
    public var ownedInstall: SiliconForestInstall? { snapshot?.siliconForestInstalls.first(where: \.isOwned) }
    public var anyInstall: SiliconForestInstall? { snapshot?.siliconForestInstalls.first }
    public var checksDone: Bool { checksRevealed >= checks.count && !checks.isEmpty }
    public var blocker: Finding? { CompatibilityChecker.blocker(checks) }
    public var canContinueFromChecks: Bool {
        guard checksDone, blocker == nil else { return false }
        if case .fresh = entry { return true }
        return false
    }
    public var nameError: String? { InstallOptions.validate(name: installName).map(Copy.Options.nameError) }
    public var isBusy: Bool { (screen.isRun && (runTask != nil || snapshotBusy)) }
    public var canStopNow: Bool {
        guard let plan, let i = currentStep, plan.steps.indices.contains(i) else { return true }
        return plan.steps[i].interruptible
    }
    public var options: InstallOptions {
        InstallOptions(siliconForestSize: siliconForestSize, installName: installName.trimmingCharacters(in: .whitespaces),
                       afterSetup: afterSetup, keepDownloads: keepDownloads)
    }

    /// The Grove's time of day (VISUAL-DESIGN §1).
    public var dawn: Double {
        switch screen {
        case .welcome, .check: return 0
        case .prepare, .space, .options, .review: return 0.07
        case .approve, .preparing: return 0.1
        case .installing: return 0.12 + 0.48 * overallProgress
        case .recovery, .inRecovery: return max(0.6, dawnReached)
        case .finish(let o): return o == .installed ? 1 : 0.6
        case .removeWhat, .removeConfirm, .removing, .removed: return 0.04
        case .failure: return 0.05
        }
    }

    public var overallProgress: Double {
        guard let plan else { return 0 }
        let total = plan.steps.reduce(0) { $0 + $1.weight }
        var done = 0.0
        for (i, s) in plan.steps.enumerated() {
            if stepStates.indices.contains(i), stepStates[i] == .pass { done += s.weight }
            else if i == currentStep, stepFraction.indices.contains(i) { done += s.weight * stepFraction[i] }
        }
        return total > 0 ? min(1, done / total) : 0
    }

    /// Progress of the installing phases only (Preparing has its own screen).
    public var installProgress: Double {
        guard let plan else { return 0 }
        let steps = plan.steps.enumerated().filter { !$0.element.phase.isPreparing }
        let total = steps.reduce(0) { $0 + $1.element.weight }
        var done = 0.0
        for (i, s) in steps {
            if stepStates.indices.contains(i), stepStates[i] == .pass { done += s.weight }
            else if i == currentStep, stepFraction.indices.contains(i) { done += s.weight * stepFraction[i] }
        }
        return total > 0 ? min(1, done / total) : 0
    }

    public var remainingText: String {
        if let etaOverride { return etaOverride }
        guard let plan, let started = runStarted else { return "" }
        let p = overallProgress
        let elapsed = Date().timeIntervalSince(started)
        let est = plan.estimatedSeconds * (isDryRun ? 0.12 : 1)
        return Copy.Installing.remaining(p > 0.05 ? elapsed / p * (1 - p) : est)
    }

    /// State of one named phase from its steps.
    public func phaseState(_ phase: Phase) -> RowState {
        guard let plan else { return .waiting }
        let idx = plan.steps.indices.filter { plan.steps[$0].phase == phase }
        let states = idx.compactMap { stepStates.indices.contains($0) ? stepStates[$0] : nil }
        if states.contains(.fail) { return .fail }
        if !states.isEmpty, states.allSatisfy({ $0 == .pass }) { return .pass }
        if states.contains(.working) || (states.contains(.pass) && states.contains(.waiting)) { return .working }
        if states.contains(.undone) { return .undone }
        return .waiting
    }

    public func phaseDuration(_ phase: Phase) -> Double {
        guard let plan else { return 0 }
        return plan.steps.indices.filter { plan.steps[$0].phase == phase }.reduce(0) { $0 + (stepDuration.indices.contains($1) ? stepDuration[$1] : 0) }
    }

    public func phaseFraction(_ phase: Phase) -> Double {
        guard let plan else { return 0 }
        let idx = plan.steps.indices.filter { plan.steps[$0].phase == phase }
        let w = idx.reduce(0.0) { $0 + plan.steps[$1].weight }
        let done = idx.reduce(0.0) { acc, i in
            acc + plan.steps[i].weight * (stepStates[i] == .pass ? 1 : (stepFraction.indices.contains(i) ? stepFraction[i] : 0))
        }
        return w > 0 ? done / w : 0
    }

    // MARK: Loading

    public func load() async {
        do {
            let f = try await backend.systemFacts()
            let s = try await backend.snapshot()
            apply(facts: f, snapshot: s)
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    public func apply(facts f: SystemFacts, snapshot s: DiskSnapshot) {
        facts = f
        snapshot = s
        let matched = ProfileStore.profile(matching: f)
        profile = matched ?? ProfileStore.profile(id: "J293")
        checks = CompatibilityChecker.run(facts: f, snapshot: s, profile: matched, release: release, allowGatedMajors: isDryRun)
        entry = CompatibilityChecker.entryState(snapshot: s, journal: nil)
        selectedInstall = ownedInstall
        if let c = constraints, siliconForestSize == 0 || siliconForestSize > c.maximum { setSize(c.recommended) }
    }

    // MARK: Navigation

    public func go(_ s: Screen) {
        withAnimation(SFMotion.screen) { screen = s }
        if s == .check { runChecks() }
    }

    public func back() {
        switch screen {
        case .check: go(.welcome)
        case .prepare: go(.check)
        case .space: go(.prepare)
        case .options: go(.space)
        case .review: go(.options)
        case .removeWhat: go(.welcome)
        case .removeConfirm: go(.removeWhat)
        default: break
        }
    }

    public var canGoBack: Bool { [.check, .prepare, .space, .options, .review, .removeWhat, .removeConfirm].contains(screen) }

    public func runChecks() {
        guard !checksRunning else { return }
        checksRunning = true
        checksRevealed = 0
        Task {
            if let f = try? await backend.systemFacts(), let s = try? await backend.snapshot() { apply(facts: f, snapshot: s) }
            for i in 0..<checks.count {
                try? await Task.sleep(nanoseconds: UInt64(280_000_000 * stepPace))
                withAnimation(SFMotion.row) { checksRevealed = i + 1 }
                if checks[i].status == .fail { checksRevealed = checks.count; break }
            }
            checksRunning = false
        }
    }

    // MARK: Size

    public func setSize(_ bytes: Int64) {
        guard let c = constraints else { return }
        limitHit = c.limit(for: bytes)
        siliconForestSize = c.snap(bytes)
        sizeText = "\(siliconForestSize / Bytes.gb)"
    }

    public func commitSizeText() {
        guard let n = Int64(sizeText.filter(\.isNumber)) else { sizeText = "\(siliconForestSize / Bytes.gb)"; return }
        withAnimation(SFMotion.bar) { setSize(n * Bytes.gb) }
    }

    public func nudge(_ gb: Int64) { withAnimation(SFMotion.numbers) { setSize(siliconForestSize + gb * Bytes.gb) } }

    // MARK: Install

    public func startInstall() {
        guard let profile, let snapshot else { return }
        do {
            let p = try Planner.installPlan(profile: profile, snapshot: snapshot, options: options, release: release)
            plan = p
            resetRun(p)
            go(.approve)
            // The dry run has no helper to approve; continue on our own (the real app waits for SMAppService.status == .enabled).
            Task {
                try? await Task.sleep(nanoseconds: UInt64(1_800_000_000 * stepPace))
                if screen == .approve { begin(p) }
            }
        } catch {
            failureMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            failureKind = .nothingChanged
            go(.failure)
        }
    }

    public func startRemoval() {
        guard let install = selectedInstall, let snapshot else { return }
        do {
            let p = try Planner.uninstallPlan(install: install, snapshot: snapshot, profileID: profile?.id ?? "J293")
            plan = p
            resetRun(p)
            begin(p)
        } catch {
            failureKind = .notOurs
            failureMessage = (error as? LocalizedError)?.errorDescription
            go(.failure)
        }
    }

    private func resetRun(_ p: InstallPlan) {
        stepStates = Array(repeating: .waiting, count: p.steps.count)
        stepFraction = Array(repeating: 0, count: p.steps.count)
        stepDuration = Array(repeating: 0, count: p.steps.count)
        currentStep = nil
        log = []
        failureMessage = nil; failureKind = nil; failedStep = nil
        undoProgress = [.waiting, .waiting, .waiting]
        stoppedCheckpoint = nil
        stepStartTimes = [:]
    }

    public func begin(_ p: InstallPlan) {
        runStarted = Date()
        let url = Journal.newURL(kind: p.kind, backend: backend.kind, in: journalDirectory ?? Journal.defaultDirectory())
        journalURL = url
        let r = InstallRunner(backend: backend, journal: Journal(url: url))
        runner = r
        go(p.kind == .install ? .preparing : .removing)
        runTask = Task { [weak self] in
            for await event in r.run(p, autoRollback: false) {
                guard let self else { return }
                self.handle(event)
            }
            self?.runTask = nil
        }
    }

    public func handle(_ e: InstallEvent) {
        guard let plan else { return }
        switch e {
        case .stepStarted(let i):
            stepStartTimes[i] = Date()
            withAnimation(.easeOut(duration: 0.25)) {
                currentStep = i
                stepStates[i] = .working
            }
            // Preparing has its own screen; the first disk-changing step moves on to Installing.
            if plan.kind == .install, !plan.steps[i].phase.isPreparing, screen == .preparing { go(.installing) }
        case .progress(let i, let f, let d):
            stepFraction[i] = f
            if i == currentStep { stepDetail = d }
        case .log(let line):
            log.append(line)
            if log.count > 800 { log.removeFirst(log.count - 800) }
        case .stepCompleted(let i):
            stepDuration[i] = Date().timeIntervalSince(stepStartTimes[i] ?? Date())
            withAnimation(SFMotion.row) { stepStates[i] = .pass; stepFraction[i] = 1 }
            if plan.kind == .install { dawnReached = max(dawnReached, 0.12 + 0.48 * overallProgress) }
        case .failed(let i, let m):
            stepStates[i] = .fail
            failedStep = i
            failureMessage = m
        case .stopped(let cp, let i):
            stoppedCheckpoint = cp
            failedStep = i
            Task {
                let st = JournalState(entries: (try? Journal.read(journalURL!)) ?? [])
                failureKind = plan.kind == .uninstall ? .removalStopped : (st.noChangesMade || i < plan.firstWriteIndex ? .nothingChanged : .canUndo)
                go(.failure)
            }
        case .rollbackStarted:
            failureKind = .undoing
        case .rollbackStep(let i, let state):
            withAnimation(SFMotion.row) {
                switch state {
                case .running: stepStates[i] = .working
                case .done: stepStates[i] = .undone
                case .skipped: if stepStates[i] != .fail { stepStates[i] = .skipped }
                case .failed: stepStates[i] = .fail
                }
                updateUndoRows()
            }
        case .rollbackFinished(let clean):
            withAnimation(SFMotion.screen) {
                undoProgress = clean ? [.pass, .pass, .pass] : undoProgress.map { $0 == .pass ? .pass : .fail }
                failureKind = clean ? .undone : .needsAttention
            }
            Task { if let s = try? await backend.snapshot() { snapshot = s } }
        case .finished(let snap):
            snapshot = snap
            currentStep = nil
            if plan.kind == .install { go(.recovery) } else { go(.removed) }
        case .cancelled:
            break
        }
    }

    /// E3's three rows from the rollback's progress.
    private func updateUndoRows() {
        guard let plan else { return }
        func state(_ ids: [StepID]) -> RowState {
            let idx = plan.steps.indices.filter { ids.contains(plan.steps[$0].id) }
            let st = idx.map { stepStates[$0] }
            if st.contains(.working) { return .working }
            if st.allSatisfy({ $0 != .pass && $0 != .working }) && st.contains(.undone) { return .pass }
            return st.contains(.pass) ? .waiting : .pass
        }
        undoProgress[0] = state([.stubPartition, .bootPartition, .rootPartition, .finalPreparations])
        undoProgress[1] = state([.resize])
        undoProgress[2] = undoProgress[0] == .pass && undoProgress[1] == .pass ? .working : .waiting
    }

    public func undoChanges() {
        guard let plan, let runner, let cp = stoppedCheckpoint else { return }
        failureKind = .undoing
        runTask = Task { [weak self] in
            for await event in runner.rollback(plan, from: cp, failedIndex: self?.failedStep) {
                guard let self else { return }
                self.handle(event)
            }
            self?.runTask = nil
        }
    }

    public func cancelPreparing() {
        Task { await runner?.cancel() }
    }

    // MARK: Recovery (simulated in the dry run) and first start

    public func shutDownForRecovery() {
        if isDryRun {
            go(.inRecovery(.password))
        } else {
            go(.finish(.verifying))   // read-only mode never gets here (no install happens)
        }
    }

    public func allowInRecovery() {
        go(.inRecovery(.working))
        Task {
            for i in 0..<4 {
                try? await Task.sleep(nanoseconds: UInt64(900_000_000 * stepPace))
                withAnimation(SFMotion.row) { recoveryWorking = i + 1 }
            }
            go(.inRecovery(.ready))
            recoveryCountdown = 15
            while recoveryCountdown > 0, screen == .inRecovery(.ready) {
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 * stepPace))
                recoveryCountdown -= 1
            }
            if screen == .inRecovery(.ready) { restartIntoSiliconForest() }
        }
    }

    @Published public var recoveryWorking = 0

    /// Back in macOS: Installed is shown only after the boot receipt has been read (D4).
    public func restartIntoSiliconForest() {
        go(.finish(.verifying))
        Task {
            try? await Task.sleep(nanoseconds: UInt64(1_600_000_000 * stepPace))
            go(.finish(.installed))   // dry run: a simulated receipt
        }
    }

    // MARK: Quit

    public func requestQuit() { withAnimation(.easeOut(duration: 0.2)) { showQuitConfirm = true } }

    public var quitCopy: (title: String, body: String, confirm: String, cancel: String) {
        if isBusy { return (Copy.Quit.busyTitle, Copy.Quit.busyBody, Copy.Quit.busyConfirm, Copy.Quit.keepGoing) }
        if screen == .recovery { return (Copy.Quit.recoveryTitle, Copy.Quit.recoveryBody, Copy.Common.quit, Copy.Common.cancel) }
        let nothing = plan == nil || failureKind == .nothingChanged || failureKind == .undone
        return (Copy.Quit.title, nothing ? Copy.Quit.nothingChanged : "", Copy.Common.quit, Copy.Common.cancel)
    }

    public func confirmQuit() {
        showQuitConfirm = false
        if isBusy {
            Task { await runner?.cancel() }
        } else {
            terminate()
        }
    }

    public func terminate() {
        quitConfirmed = true
        NSApp.terminate(nil)
    }
}
