import SwiftUI
import AppKit
import SFInstallKit

/// Renders every screen offscreen with ImageRenderer, from the same views the app shows, with the
/// backdrop frozen at a fixed time. Never opens a window.
@MainActor
struct Snapshotter {
    var outDir: URL
    var sizes: String
    var only: String?
    var appearance: String
    /// Backdrop time used for every frame (chosen for a nice spread of pulses and motes).
    var time: Double = 137.0

    struct Scenario {
        var name: String
        var dark: Bool
        var build: @MainActor () async -> InstallerModel
    }

    func run() async {
        let parsed: [(CGFloat, CGFloat, CGFloat)] = sizes.split(separator: ",").compactMap { spec in
            let parts = spec.split(separator: "@")
            let wh = parts[0].split(separator: "x").compactMap { Double($0) }
            guard wh.count == 2 else { return nil }
            return (CGFloat(wh[0]), CGFloat(wh[1]), CGFloat(parts.count > 1 ? Double(parts[1]) ?? 2 : 2))
        }
        var list = scenarios()
        if let only { let keys = only.split(separator: ","); list = list.filter { s in keys.contains { s.name.contains($0) } } }
        if appearance == "dark" { list = list.filter { $0.dark } }
        if appearance == "light" { list = list.filter { !$0.dark } }
        for s in list {
            let model = await s.build()
            for (w, h, scale) in parsed {
                let dir = outDir.appendingPathComponent("\(Int(w * scale))x\(Int(h * scale))")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let url = dir.appendingPathComponent("\(s.name).png")
                render(model: model, dark: s.dark, size: CGSize(width: w, height: h), scale: scale, to: url)
                print("✓ \(url.path)")
            }
        }
    }

    func render(model: InstallerModel, dark: Bool, size: CGSize, scale: CGFloat, to url: URL) {
        let view = RootView(model: model)
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

    // MARK: scenarios

    func base(_ fixture: String = "j293-512", failures: [FailureInjection] = []) async -> InstallerModel {
        let f = try! DiskFixture.named(fixture)
        let m = InstallerModel(mode: .dryRun, backend: SimulatedDiskBackend(fixture: f, timeScale: 0, failures: failures), fixtureName: fixture)
        m.journalDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("sf-snapshot-journals")
        await m.load()
        m.siliconForestSize = 80 * Bytes.gb
        m.backupConfirmed = true
        return m
    }

    func waitForRun(_ m: InstallerModel) async {
        while m.runTask != nil { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    /// Log lines from a real (simulated) run, cut where the given step reaches `fraction`.
    func logUntil(_ fixture: String, plan: InstallPlan, step: StepID) async -> [LogLine] {
        let f = try! DiskFixture.named(fixture)
        let b = SimulatedDiskBackend(fixture: f, timeScale: 0, failures: [FailureInjection(step: step, atFraction: 0.5)])
        let r = InstallRunner(backend: b, journal: Journal(url: nil))
        var lines: [LogLine] = []
        var t = Date(timeIntervalSince1970: 1_795_000_000)
        for await e in r.run(plan) {
            if case .log(var l) = e { t = t.addingTimeInterval(3.7); l.time = t; lines.append(l) }
            if case .failed = e { break }
        }
        return lines.filter { $0.level != .error }
    }

    func midRun(_ fixture: String, uninstall: Bool, at step: StepID, fraction: Double, detail: String, eta: String) async -> InstallerModel {
        let m = await base(fixture)
        let plan: InstallPlan
        if uninstall {
            m.selectedInstall = m.existingInstalls.first
            plan = try! Planner.uninstallPlan(install: m.selectedInstall!, snapshot: m.snapshot!)
        } else {
            plan = try! Planner.installPlan(profile: m.profile!, snapshot: m.snapshot!, options: m.options)
        }
        m.plan = plan
        let idx = plan.steps.firstIndex { $0.id == step }!
        m.stepStates = plan.steps.indices.map { $0 < idx ? .done : ($0 == idx ? .running : .pending) }
        m.currentStep = idx
        m.stepFraction = fraction
        m.stepDetail = detail
        m.etaOverride = eta
        m.log = await logUntil(fixture, plan: plan, step: step)
        m.journalURL = URL(fileURLWithPath: "/tmp/20261122-221500-\(uninstall ? "uninstall" : "install")-dryrun.jsonl")
        m.screen = uninstall ? .uninstalling : .installing
        m.snapshotBusy = true
        return m
    }

    func scenarios() -> [Scenario] {
        var list: [Scenario] = []
        for dark in [true, false] {
            let suffix = dark ? "" : "-light"
            list.append(Scenario(name: "01-welcome\(suffix)", dark: dark) { await base() })
            list.append(Scenario(name: "02-compatibility\(suffix)", dark: dark) {
                let m = await base(); m.screen = .compatibility; m.checksRevealed = m.checks.count; return m
            })
            list.append(Scenario(name: "04-disk\(suffix)", dark: dark) {
                let m = await base(); m.screen = .disk; m.snapshotDiskTag = true; return m
            })
            list.append(Scenario(name: "06-review\(suffix)", dark: dark) {
                let m = await base(); m.screen = .review; m.snapshotHold = 0.42; return m
            })
            list.append(Scenario(name: "07-installing\(suffix)", dark: dark) {
                await midRun("j293-512", uninstall: false, at: .writeSystem, fraction: 0.46, detail: "3.3 GB of 7.2 GB written", eta: "About 6 minutes remaining")
            })
            if !dark { continue }
            list.append(Scenario(name: "02b-compatibility-checking", dark: true) {
                let m = await base(); m.screen = .compatibility; m.checksRevealed = 3; return m
            })
            list.append(Scenario(name: "02c-compatibility-not-ready", dark: true) {
                let m = await base("j293-256-full"); m.screen = .compatibility; m.checksRevealed = m.checks.count; return m
            })
            list.append(Scenario(name: "03-before-you-begin", dark: true) {
                let m = await base(); m.screen = .beforeYouBegin; return m
            })
            list.append(Scenario(name: "05-options", dark: true) {
                let m = await base(); m.screen = .options; m.snapshotNameFocus = true; return m
            })
            list.append(Scenario(name: "07b-installing-log", dark: true) {
                let m = await midRun("j293-512", uninstall: false, at: .writeSystem, fraction: 0.46, detail: "3.3 GB of 7.2 GB written", eta: "About 6 minutes remaining")
                m.logOpen = true; return m
            })
            list.append(Scenario(name: "08-recovery", dark: true) {
                let m = await base(); m.startInstall(); await waitForRun(m); m.screen = .recovery; return m
            })
            list.append(Scenario(name: "09-done", dark: true) {
                let m = await base(); m.startInstall(); await waitForRun(m); m.screen = .done; return m
            })
            list.append(Scenario(name: "10-manage", dark: true) {
                let m = await base("j293-512-installed"); m.selectedInstall = m.existingInstalls.first; m.screen = .manage; return m
            })
            list.append(Scenario(name: "10b-welcome-existing-install", dark: true) {
                await base("j293-512-installed")
            })
            list.append(Scenario(name: "11-uninstall-review", dark: true) {
                let m = await base("j293-512-installed"); m.selectedInstall = m.existingInstalls.first; m.screen = .uninstallReview; m.snapshotHold = 0.3; return m
            })
            list.append(Scenario(name: "12-uninstalling", dark: true) {
                await midRun("j293-512-installed", uninstall: true, at: .growMacOS, fraction: 0.38, detail: "Growing the container…", eta: "About a minute remaining")
            })
            list.append(Scenario(name: "13-uninstall-done", dark: true) {
                let m = await base("j293-512-installed"); m.selectedInstall = m.existingInstalls.first
                m.startUninstall(); await waitForRun(m); m.screen = .uninstallDone; return m
            })
            list.append(Scenario(name: "14-error-rollback", dark: true) {
                let m = await base(failures: [FailureInjection(step: .writeSystem, atFraction: 0.46, message: "Write failed at 3.3 GB: I/O error on /dev/rdisk0s6 (simulated)")])
                m.startInstall(); await waitForRun(m); m.screen = .failure; return m
            })
            list.append(Scenario(name: "15-quit-confirm", dark: true) {
                let m = await midRun("j293-512", uninstall: false, at: .writeSystem, fraction: 0.46, detail: "3.3 GB of 7.2 GB written", eta: "About 6 minutes remaining")
                m.showQuitConfirm = true; return m
            })
        }
        return list
    }
}
