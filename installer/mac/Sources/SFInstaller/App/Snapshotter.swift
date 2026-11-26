import SwiftUI
import AppKit
import SFInstallKit
import SFCopy
import SFDesign
import SFFlow
import SFAppEngine
import SFHelperKit
import SFLiveDisk
import SFEngine

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
        /// A hand-built view instead of a screen (the button-state sheet).
        var custom: (@MainActor (Bool) -> AnyView)? = nil
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
                if let custom = sc.custom {
                    renderCustom(custom(sc.dark), dark: sc.dark, size: CGSize(width: w, height: h), scale: scale, to: url)
                } else {
                    render(session, dark: sc.dark, size: CGSize(width: w, height: h), scale: scale, to: url)
                }
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

    func renderCustom(_ content: AnyView, dark: Bool, size: CGSize, scale: CGFloat, to url: URL) {
        let view = content
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

    /// The real install's session (preview6+), over a simulated disk: the live screens and bars, no helper.
    func liveBase(_ fixture: String = "j293-512") async -> Session {
        let f = try! DiskFixture.named(fixture)
        let s = Session(live: LiveInstallController { throw NSError(domain: "snapshot", code: 1) },
                        origin: .github(tag: "installer-v0.1.0-preview8"),
                        backend: SimulatedDiskBackend(fixture: f, timeScale: 0, failures: []))
        s.journalDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("sf-snapshot-journals")
        await s.load()
        s.setSize(100 * Bytes.gb)
        s.backupConfirmed = true
        s.checksRevealed = s.checks.count
        return s
    }

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

    /// Preview13: a made-up helper offer, for the Confirm screens' snapshots.
    func sampleOffer(remove: Bool = false) -> InstallOffer {
        let gib: Int64 = 1 << 30
        // The plan's memberwise initializer is internal to SFEngine, so the sample is decoded from JSON.
        let json: String
        if remove {
            json = """
            {"format":"siliconforest-plan/1","operation":"remove","profile":{"id":"J313","sha256":"x"},"release":"","releaseVersion":"0.1.0-preview13",
             "layoutDigest":"x","macOS":{"store":"MAC","from":\(196 * gib),"to":\(245 * gib)},"partitions":[],
             "owned":{"stub":"S","boot":"B","root":"R"},"installJob":"\(UUID().uuidString)","originalLayoutDigest":"x","humanSteps":[],"digest":""}
            """
        } else {
            json = """
            {"format":"siliconforest-plan/1","operation":"install","profile":{"id":"J313","sha256":"x"},"release":"r","releaseVersion":"0.1.0-preview13",
             "request":{"siliconForestBytes":\(49 * gib),"installName":"SiliconForest","installID":"a1b2c3d4"},
             "layoutDigest":"x","macOS":{"store":"MAC","from":\(245 * gib),"to":\(196 * gib)},
             "partitions":[{"role":"stub","after":"@macos","bytes":\(2 * gib),"content":"Apple_APFS","label":"SiliconForest"},
                           {"role":"boot","after":"@stub","bytes":\(500 << 20),"content":"EFI","label":"SFBOOT"},
                           {"role":"root","after":"@boot","bytes":\(46 * gib),"content":"Linux Filesystem","label":"SF root"}],
             "originalLayoutDigest":"x","humanSteps":[],"digest":""}
            """
        }
        let plan = try! JSONDecoder().decode(SFEngine.EnginePlan.self, from: Data(json.utf8))
        let steps = [StepTitle(code: "S25", title: "Make room by shrinking macOS", writesDisk: true), StepTitle(code: "S47", title: "Write the Linux system", writesDisk: true)]
        return InstallOffer(plan: plan, expected: TypedConfirmation(diskName: "Macintosh HD"), gigabytes: remove ? 0 : 49, target: "Apple internal disk (disk0)",
                            diskUUID: "A1B2C3D4-0000", releaseVersion: "0.1.0-preview13", steps: steps)
    }

    func installed() async -> Session {
        let s = await base()
        s.startInstall()
        await waitForRun(s)
        return s
    }

    func scenarios() -> [Scenario] {
        var list: [Scenario] = []
        func add(_ name: String, dark: Bool = true, _ build: @escaping @MainActor () async -> Session, custom: (@MainActor (Bool) -> AnyView)? = nil) {
            list.append(Scenario(name: name, dark: dark, build: build, custom: custom))
        }

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
        // The real install (what Chris runs): no mode pill, the reading panel, bordered buttons.
        for dark in [true, false] {
            let sfx = dark ? "" : "-light"
            add("30-live-welcome\(sfx)", dark: dark) { await liveBase() }
            add("31-live-check-no-space\(sfx)", dark: dark) { let s = await liveBase("j293-256-full"); s.screen = .check; return s }
            add("32-live-check-ready\(sfx)", dark: dark) { let s = await liveBase(); s.screen = .check; return s }
            add("33-live-prepare\(sfx)", dark: dark) { let s = await liveBase(); s.screen = .prepare; return s }
            add("34-live-space\(sfx)", dark: dark) { let s = await liveBase(); s.screen = .space; s.snapshotHandleActive = true; return s }
            add("35-live-fetch-failed\(sfx)", dark: dark) {
                let s = await liveBase(); s.screen = .liveFetch; s.live?.activity = .failed("couldn't download SHA256SUMS (HTTP 404)"); return s
            }
            add("36-live-fetching\(sfx)", dark: dark) {
                let s = await liveBase(); s.screen = .liveFetch; s.live?.activity = .downloading(FetchProgress(file: "boot.bin", filesDone: 7, filesTotal: 133, bytes: 41_000_000)); return s
            }
            add("37-live-finish\(sfx)", dark: dark) {
                let s = await liveBase(); s.screen = .liveFinish
                let j = #"{"set":true,"volumeName":"SiliconForest","confirmed":false,"note":"","manualCommand":"","canShutDown":true}"#
                s.live?.blessReport = try? JSONDecoder().decode(BlessReport.self, from: Data(j.utf8))
                s.live?.job = "20261125-190000-install"
                return s
            }
            add("38-live-remove-list\(sfx)", dark: dark) { let s = await liveBase(); s.screen = .liveRemoveList; s.live?.installsLoaded = true; return s }
            add("39-button-states\(sfx)", dark: dark, { await liveBase() }, custom: { dark in AnyView(ButtonStatesSheet()) })
            // Preview10: the Privileges screen and the error box.
            add("40-live-privileges-login-items\(sfx)", dark: dark) {
                let s = await liveBase(); s.screen = .livePrivileges; s.live?.privileges = .needsHelperApproval; return s
            }
            add("41-live-privileges-full-disk-access\(sfx)", dark: dark) {
                let s = await liveBase(); s.screen = .livePrivileges
                s.live?.appBundle = URL(fileURLWithPath: "/Applications/SiliconForest Installer.app")
                s.live?.privileges = .needsFullDiskAccess(PrivilegeReport(fullDiskAccess: .missing, probe: "/dev/rdisk0", detail: "Operation not permitted"))
                return s
            }
            add("42-live-privileges-checking\(sfx)", dark: dark) { let s = await liveBase(); s.screen = .livePrivileges; s.live?.privileges = .checking; return s }
            add("43-live-privileges-failed\(sfx)", dark: dark) {
                let s = await liveBase(); s.screen = .livePrivileges
                s.live?.privileges = .failed("The installer's helper didn't answer: The connection to service named org.siliconforest.installer.helper was invalidated.")
                return s
            }
            // Preview13: the Confirm screens, the installing screen with the quiet notice, and the finish screen's retry.
            add("45-live-confirm\(sfx)", dark: dark) {
                let s = await liveBase(); s.screen = .liveConfirm; s.live?.offer = sampleOffer(); s.live?.release = nil
                s.live?.startupOwners = StartupDiskOwners(owners: ["chris"], defaultOwner: "chris"); s.live?.startupOwner = "chris"
                return s
            }
            add("46-live-confirm-matched\(sfx)", dark: dark) {
                let s = await liveBase(); s.screen = .liveConfirm; s.live?.offer = sampleOffer(); s.live?.typedName = "  macintosh   hd "
                s.live?.startupOwners = StartupDiskOwners(owners: ["chris"], defaultOwner: "chris"); s.live?.startupOwner = "chris"
                return s
            }
            add("47-live-remove-confirm\(sfx)", dark: dark) {
                let s = await liveBase(); s.screen = .liveRemoveConfirm; s.live?.offer = sampleOffer(remove: true); s.live?.isRemoval = true; return s
            }
            add("48-live-installing-resize\(sfx)", dark: dark) {
                let s = await liveBase(); s.screen = .liveInstalling
                let t = ["S01": "Check the disk", "S10": "Download the release", "S20": "Read the partition table", "S25": "Make room by shrinking macOS", "S30": "Create the SiliconForest partitions", "S47": "Write the Linux system", "S65": "Set the startup disk"]
                s.live?.rows = t.keys.sorted().map { c in
                    LiveRun.StepRow(code: c, title: t[c]!, writesDisk: c >= "S25", state: c < "S25" ? .pass : (c == "S25" ? .working : .waiting), started: nil, seconds: nil)
                }
                s.live?.currentCode = "S25"; s.live?.diskutilPercent = 41; s.live?.diskutilLine = "Shrinking APFS container"
                return s
            }
            add("49-live-finish-bless-failed\(sfx)", dark: dark) {
                let s = await liveBase(); s.screen = .liveFinish
                let j = #"{"set":false,"volumeName":"SiliconForest","confirmed":false,"note":"macOS needs your login to set the startup disk.","manualCommand":"sudo /usr/sbin/bless --mount /Volumes/SiliconForest --setBoot --nextonly","canShutDown":false,"needsPassword":true,"canRetry":true}"#
                s.live?.blessReport = try? JSONDecoder().decode(BlessReport.self, from: Data(j.utf8))
                s.live?.startupOwners = StartupDiskOwners(owners: ["chris"], defaultOwner: "chris"); s.live?.startupOwner = "chris"
                s.live?.job = "20261125-190000-install"
                return s
            }
            add("44-live-error-plan\(sfx)", dark: dark) {
                let s = await liveBase(); s.screen = .liveFetch
                s.live?.failedDuring = .planning
                s.live?.activity = .failed("Refused: can't read /dev/rdisk0's partition table (Device not configured)")
                return s
            }
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


/// Every kind of control in its four states, on the reading panel (preview8 audit sheet).
struct ButtonStatesSheet: View {
    @Environment(\.theme) private var theme
    var body: some View {
        ZStack {
            Grove(camera: 0.4, dawn: 0)
            ContentPanel(width: 1180, height: 620, welcome: false)
            VStack(alignment: .leading, spacing: 22) {
                Text("Buttons: normal · hover · pressed · disabled").font(SFType.inter(22, .semibold)).foregroundStyle(theme.text)
                row("Primary", { Button("Continue") {}.buttonStyle(SFPrimaryButtonStyle()) })
                row("Secondary", { Button("Open Storage Settings") {}.buttonStyle(SFTextButtonStyle()) })
                row("Quiet (Details…)", { Button("Details") {}.buttonStyle(SFQuietButtonStyle()) })
                row("Destructive", { Button("Remove SiliconForest") {}.buttonStyle(SFDestructiveButtonStyle()) })
            }
            .padding(48)
            .frame(width: 1180, height: 620, alignment: .topLeading)
        }
    }
    @ViewBuilder private func row<B: View>(_ name: String, _ make: @escaping () -> B) -> some View {
        HStack(spacing: 28) {
            Text(name).font(SFType.label).foregroundStyle(theme.textSecondary).frame(width: 150, alignment: .leading)
            make()
            make().environment(\.buttonStateOverride, .hover)
            make().environment(\.buttonStateOverride, .pressed)
            make().disabled(true)
        }
    }
}
