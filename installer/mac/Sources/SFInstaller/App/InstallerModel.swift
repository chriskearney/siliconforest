import SwiftUI
import Observation
import SFInstallKit

enum Screen: String, CaseIterable, Hashable {
    case welcome, compatibility, beforeYouBegin, disk, options, review, installing, recovery, done
    case manage, uninstallReview, uninstalling, uninstallDone
    case failure

    /// Screens shown inside the glass panel (the rest are full-bleed heroes).
    var usesPanel: Bool { self != .welcome && self != .done && self != .uninstallDone }

    /// Position in the install flow for the step indicator.
    var flowIndex: Int? {
        switch self {
        case .compatibility: return 0
        case .beforeYouBegin: return 1
        case .disk: return 2
        case .options: return 3
        case .review: return 4
        case .installing: return 5
        case .recovery: return 6
        default: return nil
        }
    }

    /// Parallax camera position per screen: the view drifts as you move through the flow.
    var camera: Double {
        switch self {
        case .welcome: return -0.9
        case .compatibility: return -0.6
        case .beforeYouBegin: return -0.35
        case .disk: return -0.1
        case .options: return 0.1
        case .review: return 0.3
        case .installing: return 0.5
        case .recovery: return 0.7
        case .done: return 0.95
        case .manage, .uninstallReview: return -0.4
        case .uninstalling, .uninstallDone: return 0.2
        case .failure: return 0
        }
    }

    static let flowTitles = ["Check", "Prepare", "Disk", "Options", "Review", "Install", "Finish"]
}

enum StepRunState: Equatable {
    case pending, running, done, failed, undoing, undone, skipped, undoFailed
}

enum RunMode: Equatable {
    case dryRun
    case readOnly
}

@Observable
@MainActor
final class InstallerModel {
    // Where we are
    var screen: Screen = .welcome
    var forward = true
    var showQuitConfirm = false
    var logOpen = false

    // Environment
    let mode: RunMode
    var backend: any DiskBackend
    var fixtureName: String
    var profile: DeviceProfile?
    var facts: SystemFacts?
    var snapshot: DiskSnapshot?
    var loadError: String?

    // Compatibility
    var checks: [CompatibilityCheck] = []
    var checksRevealed = 0
    var checksRunning = false

    // Choices
    var siliconForestSize: Int64 = 0
    var installName = "SiliconForest"
    var defaultBoot: BootChoice = .macOS
    var backupConfirmed = false

    // Run
    var plan: InstallPlan?
    var stepStates: [StepRunState] = []
    var currentStep: Int?
    var stepFraction: Double = 0
    var stepDetail = ""
    var log: [LogLine] = []
    var runStarted: Date?
    var failureMessage: String?
    var failedStep: Int?
    var rollbackClean: Bool?
    var rollingBack = false
    var journalURL: URL?
    var finalSnapshot: DiskSnapshot?
    /// Frozen ETA text for snapshots.
    var etaOverride: String?

    // Manage
    var selectedInstall: SiliconForestInstall?

    // Snapshot-only presentation state
    var snapshotHold: Double?
    var snapshotDiskTag = false
    var snapshotNameFocus = false
    var snapshotBusy = false
    /// Where journals go; nil = ~/Library/Application Support/SiliconForest Installer/Journals.
    var journalDirectory: URL?
    var quitConfirmed = false

    private var runner: InstallRunner?
    private(set) var runTask: Task<Void, Never>?

    init(mode: RunMode, backend: any DiskBackend, fixtureName: String) {
        self.mode = mode
        self.backend = backend
        self.fixtureName = fixtureName
    }

    // MARK: Derived

    var disk: PhysicalDisk? { snapshot?.internalDisk }
    var constraints: SizingConstraints? {
        guard let profile, let disk else { return nil }
        return SizingConstraints(profile: profile, disk: disk)
    }
    var existingInstalls: [SiliconForestInstall] { snapshot?.siliconForestInstalls ?? [] }
    var canContinueFromChecks: Bool { checksRevealed >= checks.count && !checks.isEmpty && CompatibilityChecker.canProceed(checks) }
    var nameError: String? { InstallOptions.validate(name: installName) }
    var isDryRun: Bool { mode == .dryRun }

    var options: InstallOptions {
        InstallOptions(siliconForestSize: siliconForestSize, installName: installName.trimmingCharacters(in: .whitespaces), defaultBoot: defaultBoot)
    }

    var overallProgress: Double {
        guard let plan else { return 0 }
        let total = plan.steps.reduce(0) { $0 + $1.weight }
        var done = 0.0
        for (i, s) in plan.steps.enumerated() {
            if stepStates.indices.contains(i), stepStates[i] == .done { done += s.weight }
            else if i == currentStep { done += s.weight * stepFraction }
        }
        return total > 0 ? min(1, done / total) : 0
    }

    var etaText: String {
        if let etaOverride { return etaOverride }
        guard let plan, let started = runStarted else { return "" }
        let p = overallProgress
        // Before there's signal, use the plan's estimate scaled to how fast this run is going.
        let elapsed = Date().timeIntervalSince(started)
        let remaining: Double = p > 0.04 ? elapsed / p * (1 - p) : plan.estimatedSeconds * (isDryRun ? 0.15 : 1)
        return Self.friendlyRemaining(remaining)
    }

    static func friendlyRemaining(_ s: Double) -> String {
        if s < 20 { return "Less than a minute remaining" }
        if s < 90 { return "About a minute remaining" }
        let m = Int((s / 60).rounded())
        return "About \(m) minutes remaining"
    }

    // MARK: Loading

    func load() async {
        do {
            let f = try await backend.systemFacts()
            let s = try await backend.snapshot()
            apply(facts: f, snapshot: s)
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    func apply(facts f: SystemFacts, snapshot s: DiskSnapshot) {
        facts = f
        snapshot = s
        profile = ProfileStore.profile(matching: f) ?? (mode == .readOnly ? ProfileStore.profile(id: "J293") : nil)
        checks = CompatibilityChecker.run(facts: f, snapshot: s, profile: ProfileStore.profile(matching: f))
        if let c = constraints, siliconForestSize == 0 { siliconForestSize = c.recommended }
    }

    // MARK: Navigation

    func go(_ s: Screen, forward: Bool = true) {
        self.forward = forward
        withAnimation(.spring(response: 0.62, dampingFraction: 0.9)) { screen = s }
        if s == .compatibility { runChecks() }
    }

    func back() {
        switch screen {
        case .compatibility: go(.welcome, forward: false)
        case .beforeYouBegin: go(.compatibility, forward: false)
        case .disk: go(.beforeYouBegin, forward: false)
        case .options: go(.disk, forward: false)
        case .review: go(.options, forward: false)
        case .manage: go(.welcome, forward: false)
        case .uninstallReview: go(.manage, forward: false)
        default: break
        }
    }

    var canGoBack: Bool {
        [.compatibility, .beforeYouBegin, .disk, .options, .review, .manage, .uninstallReview].contains(screen)
    }

    /// True while something is changing the (simulated) disk.
    var isBusy: Bool { (screen == .installing || screen == .uninstalling) && (runTask != nil || snapshotBusy) }

    func runChecks() {
        guard !checksRunning else { return }
        checksRunning = true
        checksRevealed = 0
        Task {
            // Re-read the Mac so the list reflects now, then reveal rows one by one.
            if let f = try? await backend.systemFacts(), let s = try? await backend.snapshot() { apply(facts: f, snapshot: s) }
            for i in 0..<checks.count {
                try? await Task.sleep(nanoseconds: 420_000_000)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { checksRevealed = i + 1 }
            }
            checksRunning = false
        }
    }

    // MARK: Install / uninstall

    func startInstall() {
        guard let profile, let snapshot else { return }
        do {
            let p = try Planner.installPlan(profile: profile, snapshot: snapshot, options: options)
            begin(p, screen: .installing)
        } catch {
            failureMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            go(.failure)
        }
    }

    func startUninstall() {
        guard let install = selectedInstall, let snapshot else { return }
        do {
            let p = try Planner.uninstallPlan(install: install, snapshot: snapshot, profileID: profile?.id ?? "J293")
            begin(p, screen: .uninstalling)
        } catch {
            failureMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            go(.failure)
        }
    }

    private func begin(_ p: InstallPlan, screen target: Screen) {
        plan = p
        stepStates = Array(repeating: .pending, count: p.steps.count)
        currentStep = nil
        stepFraction = 0
        log = []
        failureMessage = nil
        failedStep = nil
        rollbackClean = nil
        rollingBack = false
        runStarted = Date()
        let url = Journal.newURL(kind: p.kind, backend: backend.kind, in: journalDirectory ?? Journal.defaultDirectory())
        journalURL = url
        let r = InstallRunner(backend: backend, journal: Journal(url: url))
        runner = r
        go(target)
        runTask = Task { [weak self] in
            for await event in r.run(p) {
                guard let self else { return }
                self.handle(event)
            }
            self?.runTask = nil
        }
    }

    func cancelRun() {
        Task { await runner?.cancel() }
    }

    func handle(_ e: InstallEvent) {
        switch e {
        case .stepStarted(let i):
            withAnimation(.easeOut(duration: 0.25)) {
                currentStep = i
                stepFraction = 0
                stepStates[i] = .running
            }
        case .progress(let i, let f, let d):
            if i == currentStep { stepFraction = f; stepDetail = d }
        case .log(let line):
            log.append(line)
            if log.count > 600 { log.removeFirst(log.count - 600) }
        case .stepCompleted(let i):
            withAnimation(.easeOut(duration: 0.25)) { stepStates[i] = .done }
        case .failed(let i, let m):
            stepStates[i] = .failed
            failedStep = i
            failureMessage = m
            go(.failure)
        case .rollbackStarted(let steps):
            rollingBack = true
            for i in steps where stepStates[i] == .done { stepStates[i] = .pending }
            if screen != .failure { go(.failure) }
        case .rollbackStep(let i, let state):
            withAnimation(.easeOut(duration: 0.2)) {
                switch state {
                case .running: stepStates[i] = .undoing
                case .done: stepStates[i] = .undone
                case .skipped: if stepStates[i] != .failed { stepStates[i] = .skipped }
                case .failed: stepStates[i] = .undoFailed
                }
            }
        case .rollbackFinished(let clean):
            rollingBack = false
            rollbackClean = clean
            Task { if let s = try? await backend.snapshot() { snapshot = s } }
        case .finished(let snap):
            finalSnapshot = snap
            snapshot = snap
            currentStep = nil
            if plan?.kind == .install {
                go(.recovery)
            } else {
                go(.uninstallDone)
            }
        case .cancelled:
            rollingBack = false
        }
    }

    func retryAfterFailure() {
        if plan?.kind == .uninstall { go(.manage, forward: false) } else { go(.review, forward: false) }
    }

    // MARK: Quit

    func requestQuit() {
        withAnimation(.easeOut(duration: 0.2)) { showQuitConfirm = true }
    }

    var quitMessage: (title: String, body: String, confirm: String, cancel: String) {
        if isBusy {
            return ("Stop and quit?",
                    "The current step will finish, then every change is rolled back before the installer quits. Your Mac will be as it was.",
                    "Stop and Roll Back", "Keep Going")
        }
        if screen == .recovery {
            return ("Quit before the recoveryOS step?", "SiliconForest is installed but won’t start until you finish the recoveryOS step. You can open the installer again for the instructions.", "Quit", "Stay")
        }
        return ("Quit the installer?", "Nothing has been changed on your Mac.", "Quit", "Cancel")
    }

    func confirmQuit() {
        if isBusy {
            showQuitConfirm = false
            cancelRun()
            Task {
                while runTask != nil { try? await Task.sleep(nanoseconds: 100_000_000) }
                terminate()
            }
        } else {
            terminate()
        }
    }

    func terminate() {
        quitConfirmed = true
        NSApp.terminate(nil)
    }
}
