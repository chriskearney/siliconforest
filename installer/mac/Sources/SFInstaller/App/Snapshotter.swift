import SwiftUI
import AppKit
import SFInstallKit
import SFCopy
import SFDesign
import SFFlow

/// Renders every screen offscreen with ImageRenderer, from the same views the app shows, with the
/// Grove frozen at a fixed time. Never opens a window.
@MainActor
struct Snapshotter {
    var outDir: URL
    var sizes: String
    var only: String?
    var appearance: String
    var time: Double = 137.0

    struct Scenario {
        var name: String
        var dark: Bool
        var build: @MainActor () async -> Session
    }

    func run() async {
        let parsed: [(CGFloat, CGFloat, CGFloat)] = sizes.split(separator: ",").compactMap { spec in
            let parts = spec.split(separator: "@")
            let wh = parts[0].split(separator: "x").compactMap { Double($0) }
            guard wh.count == 2 else { return nil }
            return (CGFloat(wh[0]), CGFloat(wh[1]), CGFloat(parts.count > 1 ? Double(parts[1]) ?? 2 : 2))
        }
        var list = scenarios()
        if let only { let keys = only.split(separator: ","); list = list.filter { s in keys.contains { s.name.hasPrefix($0) } } }
        if appearance == "dark" { list = list.filter { $0.dark } }
        if appearance == "light" { list = list.filter { !$0.dark } }
        for sc in list {
            let session = await sc.build()
            for (w, h, scale) in parsed {
                let dir = outDir.appendingPathComponent("\(Int(w * scale))x\(Int(h * scale))")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let url = dir.appendingPathComponent("\(sc.name).png")
                render(session, dark: sc.dark, size: CGSize(width: w, height: h), scale: scale, to: url)
                print("✓ \(url.path)")
            }
        }
    }

    func render(_ s: Session, dark: Bool, size: CGSize, scale: CGFloat, to url: URL) {
        let view = RootView(s: s)
            .environment(\.theme, Theme(isDark: dark))
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.isSnapshot, true)
            .environment(\.backdropTime, time)
            .environment(\.screenSize, size)
            .frame(width: size.width, height: size.height)
        let r = ImageRenderer(content: view)
        r.scale = scale
        r.proposedSize = ProposedViewSize(size)
        guard let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            print("✗ render failed: \(url.lastPathComponent)"); return
        }
        try? png.write(to: url)
    }

    // MARK: building states

    func base(_ fixture: String = "j293-512", failures: [FailureInjection] = []) async -> Session {
        let f = try! DiskFixture.named(fixture)
        let s = Session(mode: .dryRun, backend: SimulatedDiskBackend(fixture: f, timeScale: 0, failures: failures))
        s.journalDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("sf-snapshot-journals")
        s.stepPace = 0
        await s.load()
        s.setSize(100 * Bytes.gb)
        s.backupConfirmed = true
        s.checksRevealed = s.checks.count
        return s
    }

    func waitForRun(_ s: Session) async {
        for _ in 0..<400 where s.runTask != nil || s.screen == .approve { try? await Task.sleep(nanoseconds: 10_000_000) }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    func logUntil(_ fixture: String, plan: InstallPlan, step: StepID) async -> [LogLine] {
        let b = SimulatedDiskBackend(fixture: try! DiskFixture.named(fixture), timeScale: 0, failures: [FailureInjection(step: step, atFraction: 0.5)])
        let r = InstallRunner(backend: b, journal: Journal(url: nil))
        var lines: [LogLine] = []
        var t = Date(timeIntervalSince1970: 1_795_000_000)
        for await e in r.run(plan, autoRollback: false) {
            if case .log(var l) = e { t = t.addingTimeInterval(3.7); l.time = t; lines.append(l) }
            if case .failed = e { break }
        }
        return lines.filter { $0.level != .error }
    }

    /// A run frozen part-way through `step`.
    func midRun(_ fixture: String, remove: Bool = false, at step: StepID, fraction: Double, detail: String, eta: String) async -> Session {
        let s = await base(fixture)
        let plan: InstallPlan
        if remove {
            s.selectedInstall = s.ownedInstall
            plan = try! Planner.uninstallPlan(install: s.selectedInstall!, snapshot: s.snapshot!)
        } else {
            plan = try! Planner.installPlan(profile: s.profile!, snapshot: s.snapshot!, options: s.options)
        }
        s.plan = plan
        let idx = plan.steps.firstIndex { $0.id == step }!
        s.stepStates = plan.steps.indices.map { $0 < idx ? .pass : ($0 == idx ? .working : .waiting) }
        s.stepFraction = plan.steps.indices.map { $0 < idx ? 1 : ($0 == idx ? fraction : 0) }
        s.stepDuration = plan.steps.map { $0.estimatedSeconds * 0.9 }
        s.currentStep = idx
        s.stepDetail = detail
        s.etaOverride = eta
        s.log = await logUntil(fixture, plan: plan, step: step)
        s.journalURL = URL(fileURLWithPath: "/tmp/20261122-231500-\(remove ? "uninstall" : "install")-dryrun.jsonl")
        s.screen = remove ? .removing : (plan.steps[idx].phase.isPreparing ? .preparing : .installing)
        s.snapshotBusy = true
        s.dawnReached = s.dawn
        return s
    }

    func installed() async -> Session {
        let s = await base()
        s.startInstall()
        await waitForRun(s)
        return s
    }

    func scenarios() -> [Scenario] {
        var list: [Scenario] = []
        func add(_ name: String, dark: Bool = true, _ build: @escaping @MainActor () async -> Session) { list.append(Scenario(name: name, dark: dark, build: build)) }

        for dark in [true, false] {
            let sfx = dark ? "" : "-light"
            add("01-welcome\(sfx)", dark: dark) { await base() }
            add("02-check\(sfx)", dark: dark) { let s = await base(); s.screen = .check; return s }
            add("04-space\(sfx)", dark: dark) { let s = await base(); s.screen = .space; s.snapshotHandleActive = true; return s }
            add("06-review\(sfx)", dark: dark) { let s = await base(); s.screen = .review; return s }
            add("09-installing\(sfx)", dark: dark) {
                await midRun("j293-512", at: .rootImage, fraction: 0.46, detail: "3.4 GB of 7.3 GB written", eta: "About 6 minutes left")
            }
            add("12-finish\(sfx)", dark: dark) { let s = await installed(); s.screen = .finish(.installed); return s }
        }
        add("02b-check-running") { let s = await base(); s.screen = .check; s.checksRevealed = 4; s.checksRunning = true; return s }
        add("02c-check-no-space") { let s = await base("j293-256-full"); s.screen = .check; return s }
        add("02d-check-hand-made") { let s = await base("j293-512-devinstall"); s.screen = .check; return s }
        add("02e-check-macbook-air") { let s = await base("j313-256"); s.screen = .check; return s }
        add("04c-space-macbook-air") { let s = await base("j313-256"); s.setSize(s.constraints!.recommended); s.screen = .space; return s }
        add("03-before-you-begin") { let s = await base(); s.screen = .prepare; s.showSecurity = true; return s }
        add("04b-space-limit") {
            let s = await base(); s.screen = .space; s.setSize(Int64.max / 4); s.showPartitionDetails = true; return s
        }
        add("05-options") { let s = await base(); s.screen = .options; s.snapshotNameFocus = true; return s }
        add("06b-what-would-happen") { let s = await base(); s.screen = .review; s.showCommands = true; return s }
        add("07-approve") {
            let s = await base(); s.plan = try? Planner.installPlan(profile: s.profile!, snapshot: s.snapshot!, options: s.options); s.screen = .approve; return s
        }
        add("08-preparing") {
            await midRun("j293-512", at: .fetch, fraction: 0.93, detail: "", eta: "4 min left")
        }
        add("09b-installing-details") {
            let s = await midRun("j293-512", at: .rootImage, fraction: 0.46, detail: "3.4 GB of 7.3 GB written", eta: "About 6 minutes left")
            s.showDetails = true; return s
        }
        add("09c-installing-resize") {
            await midRun("j293-512", at: .resize, fraction: 0.55, detail: "Moving data blocks…", eta: "About 14 minutes left")
        }
        add("10-recovery") { let s = await installed(); s.screen = .recovery; return s }
        add("11-in-recovery") { let s = await installed(); s.screen = .inRecovery(.password); return s }
        add("11b-in-recovery-working") { let s = await installed(); s.screen = .inRecovery(.working); s.recoveryWorking = 2; return s }
        add("13-remove") { let s = await base("j293-512-installed"); s.screen = .removeWhat; return s }
        add("14-remove-confirm") { let s = await base("j293-512-installed"); s.removeConfirmText = "SiliconForest"; s.screen = .removeConfirm; return s }
        add("15-removing") {
            await midRun("j293-512-installed", remove: true, at: .returnSpace, fraction: 0.38, detail: "Growing the container…", eta: "About a minute left")
        }
        add("16-removed") {
            let s = await base("j293-512-installed"); s.startRemoval(); await waitForRun(s); return s
        }
        add("17-stopped-can-undo") {
            let s = await base(failures: [FailureInjection(step: .rootImage, atFraction: 0.46, message: "Write failed at 3.4 GB: I/O error on /dev/rdisk0s6 (simulated)")])
            s.startInstall(); await waitForRun(s); return s
        }
        add("17b-undone") {
            let s = await base(failures: [FailureInjection(step: .rootImage, atFraction: 0.46, message: "Write failed at 3.4 GB: I/O error on /dev/rdisk0s6 (simulated)")])
            s.startInstall(); await waitForRun(s); s.undoChanges(); await waitForRun(s); return s
        }
        add("17c-stopped-nothing-changed") {
            let s = await base(failures: [FailureInjection(step: .fetch, atFraction: 0.6, message: "The download from Apple failed: connection timed out.")])
            s.startInstall(); await waitForRun(s); return s
        }
        add("18-quit-confirm") {
            let s = await midRun("j293-512", at: .rootImage, fraction: 0.46, detail: "3.4 GB of 7.3 GB written", eta: "About 6 minutes left")
            s.showQuitConfirm = true; return s
        }
        return list
    }
}
