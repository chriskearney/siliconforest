import Foundation
import SFInstallKit
import SFCopy

// sfinstallctl: the installer engine without the UI. Dry runs against fixtures, read-only analysis
// of this Mac, and plan rehearsals that print every command without running any.

let usage = """
sfinstallctl: SiliconForest installer engine

USAGE
  sfinstallctl profiles
  sfinstallctl fixtures
  sfinstallctl facts      [--real | --fixture NAME]
  sfinstallctl disk       [--real | --fixture NAME]
  sfinstallctl check      [--real | --fixture NAME] [--profile ID]
  sfinstallctl plan       [--real | --fixture NAME] [--size 80G] [--name NAME] [--default macos|siliconforest]   (siliconforest = default after a successful start)
  sfinstallctl install    [--fixture NAME] [--size 80G] [--speed X] [--fail-step STEP | --fail-op KIND] [--journal PATH]
  sfinstallctl uninstall  [--fixture NAME] [--speed X] [--journal PATH]
  sfinstallctl rehearse   --real [--size 80G]     plan against this Mac and record every command; nothing runs
  sfinstallctl journal    PATH

Default fixture: j293-512 (j293-512-installed for uninstall). --speed 0 is instant, 1 is the UI's pace.
Nothing in this tool writes to a disk. --real only reads (diskutil list/info, fdesetup/csrutil status, sysctl).
"""

struct Args {
    var command: String
    var flags: [String: String] = [:]
    var positional: [String] = []

    init(_ argv: [String]) {
        command = argv.first ?? "help"
        var i = 1
        while i < argv.count {
            let a = argv[i]
            if a.hasPrefix("--") {
                let key = String(a.dropFirst(2))
                if i + 1 < argv.count, !argv[i + 1].hasPrefix("--") { flags[key] = argv[i + 1]; i += 2 } else { flags[key] = "true"; i += 1 }
            } else { positional.append(a); i += 1 }
        }
    }
    var real: Bool { flags["real"] == "true" }
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("error: \(msg)\n".utf8))
    exit(1)
}

func backend(_ args: Args, defaultFixture: String = "j293-512") throws -> any DiskBackend {
    if args.real { return RealDiskBackend() }
    let name = args.flags["fixture"] ?? defaultFixture
    let fixture = name.hasSuffix(".json") ? try DiskFixture.load(URL(fileURLWithPath: name)) : try DiskFixture.named(name)
    var failures: [FailureInjection] = []
    if let s = args.flags["fail-step"] {
        guard let step = StepID(rawValue: s) else { fail("unknown step \(s); one of \(StepID.allCases.map(\.rawValue).joined(separator: ", "))") }
        failures.append(FailureInjection(step: step))
    }
    if let k = args.flags["fail-op"] {
        guard let kind = DiskOperation.Kind(rawValue: k) else { fail("unknown op \(k)") }
        failures.append(FailureInjection(operation: kind))
    }
    let speed = Double(args.flags["speed"] ?? "0") ?? 0
    return SimulatedDiskBackend(fixture: fixture, timeScale: speed, failures: failures)
}

func profile(_ args: Args, facts: SystemFacts) -> DeviceProfile? {
    if let id = args.flags["profile"] { return ProfileStore.profile(id: id) }
    return ProfileStore.profile(matching: facts) ?? (args.real ? nil : ProfileStore.profile(id: "J293"))
}

func printLayout(_ disk: PhysicalDisk) {
    let classes = disk.classify()
    print("\(disk.identifier)  \(disk.mediaName)  \(Bytes.format(disk.size))")
    for seg in disk.layout {
        switch seg {
        case .partition(let p):
            var line = "  \(p.identifier.padding(toLength: 10, withPad: " ", startingAt: 0)) \(p.content.rawValue.padding(toLength: 20, withPad: " ", startingAt: 0)) \(Bytes.format(p.size).padding(toLength: 10, withPad: " ", startingAt: 0))"
            if let c = p.container { line += " \(c.reference): \(Bytes.format(c.capacityUsed)) used, \(Bytes.format(c.capacityFree)) free" }
            if let n = p.name { line += "  “\(n)”" }
            if let cls = classes[p.identifier] { line += "  [\(cls.rawValue)]" }
            print(line)
        case .free(_, let size):
            print("  (free)     \("".padding(toLength: 20, withPad: " ", startingAt: 0)) \(Bytes.format(size))")
        }
    }
}

func printPlan(_ plan: InstallPlan) {
    print("\(plan.kind == .install ? "Install" : "Uninstall") plan · \(plan.profileID) · \(plan.disk)")
    print("  macOS container \(plan.macOSPartition): \(Bytes.format(plan.macOSSizeBefore)) → \(Bytes.format(plan.macOSSizeAfter))")
    if plan.kind == .install {
        print("  SiliconForest “\(plan.options.installName)”: \(Bytes.format(plan.siliconForestSize)) = stub \(Bytes.format(plan.stubSize)) + boot \(Bytes.format(plan.bootSize)) + root \(Bytes.format(plan.rootSize))")
        print("  After setup: \(plan.options.afterSetup == .startOnceKeepMacOS ? Copy.Options.startOnce : Copy.Options.makeDefault)")
        print("  Downloads: \(Copy.Review.downloadValue(release: plan.downloadReleaseBytes, apple: plan.downloadAppleBytes))")
    }
    print("  Estimated time: \(Int(plan.estimatedSeconds / 60)) min")
    for (i, s) in plan.steps.enumerated() {
        print(String(format: "  %2d. %@  %@  [%@]", i + 1, s.code, s.title, Copy.Installing.phase(s.phase)))
        for op in s.operations { for argv in op.commands() { print("        $ \(CommandRender.render(argv))") } }
        for op in s.undo { for argv in op.commands() { print("        ↺ \(CommandRender.render(argv))") } }
    }
}

func run(_ plan: InstallPlan, on backend: any DiskBackend, journalPath: String?) async -> Int32 {
    let url = journalPath.map { URL(fileURLWithPath: $0) } ?? Journal.newURL(kind: plan.kind, backend: backend.kind)
    let journal = Journal(url: url)
    let runner = InstallRunner(backend: backend, journal: journal)
    var status: Int32 = 0
    var lastPct = -1
    for await event in runner.run(plan) {
        switch event {
        case .stepStarted(let i): print("▸ [\(i + 1)/\(plan.steps.count)] \(plan.steps[i].code) \(plan.steps[i].title)")
        case .progress(_, let f, _):
            let pct = Int(f * 100)
            if pct / 25 != lastPct / 25 { lastPct = pct }
        case .log(let line):
            switch line.level {
            case .command: print("    $ \(line.text)")
            case .planned: print("      (\(line.text))")
            case .error: print("    \(line.text)")
            case .warning: print("    ! \(line.text)")
            default: break
            }
        case .stepCompleted(let i): print("  ✓ \(plan.steps[i].title)")
        case .failed(let i, let m): print("  ✗ \(plan.steps[i].title): \(m)"); status = 2
        case .rollbackStarted(let steps): print("↺ rolling back \(steps.count) step(s)")
        case .rollbackStep(let i, let state): if state != .running { print("  ↺ \(plan.steps[i].title): \(state.rawValue)") }
        case .rollbackFinished(let clean): print(clean ? "↺ rolled back cleanly: the disk is as it was" : "↺ rollback INCOMPLETE: see the journal")
        case .finished(let snap):
            print("✓ \(plan.kind.rawValue) finished")
            if let d = snap.internalDisk { printLayout(d) }
        case .cancelled: print("cancelled"); status = 3
        case .stopped: print("stopped"); status = 2
        }
    }
    print("journal: \(url.path)")
    return status
}

@MainActor
func main() async {
    let args = Args(Array(Swift.CommandLine.arguments.dropFirst()))
    do {
        switch args.command {
        case "profiles":
            for p in ProfileStore.loadAll() {
                print("\(p.id)  \(p.marketingName)  \(p.soc.name) (\(p.soc.id))  models: \(p.modelIdentifiers.joined(separator: ","))  [\(p.support.status)]")
                print("    footprint \(Bytes.format(p.minimumFootprint)) min, \(Bytes.format(p.recommendedFootprint)) recommended; macOS \(p.support.minMacOS)+; stub fw \(p.support.stubFirmware.joined(separator: ", "))")
            }
            print("searched: " + ProfileStore.searchDirectories().map(\.path).joined(separator: "\n          "))
        case "fixtures":
            for url in DiskFixture.available() {
                let f = try DiskFixture.load(url)
                print("\(f.name.padding(toLength: 22, withPad: " ", startingAt: 0)) \(f.summary ?? "")")
            }
        case "facts":
            let b = try backend(args)
            let f = try await b.systemFacts()
            let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(data: try e.encode(f), encoding: .utf8)!)
        case "disk":
            let b = try backend(args)
            let s = try await b.snapshot()
            for d in s.disks { printLayout(d) }
            for i in s.siliconForestInstalls { print("SiliconForest install “\(i.name)” \(i.version ?? "") on \(i.partitions.map(\.identifier).joined(separator: ", ")) (\(Bytes.format(i.totalBytes)))") }
        case "check":
            let b = try backend(args)
            let facts = try await b.systemFacts(), snap = try await b.snapshot()
            let p = profile(args, facts: facts)
            let checks = CompatibilityChecker.run(facts: facts, snapshot: snap, profile: p)
            for c in checks {
                let mark = ["pass": "✓", "warning": "!", "fail": "✗", "info": "i"][c.status.rawValue]!
                print("\(mark) \(Copy.Check.label(c.kind).padding(toLength: 18, withPad: " ", startingAt: 0)) \(Copy.Check.text(c.finding))")
            }
            if let b = CompatibilityChecker.blocker(checks).flatMap({ Copy.Check.blocked($0) }) { print("\n\(b.title)\n  \(b.body)") }
            let entry = CompatibilityChecker.entryState(snapshot: snap, journal: nil)
            if let e = Copy.Check.entry(entry) { print("\n\(e.title)\n  \(e.body)") }
            if let p, let d = snap.internalDisk, let sc = SizingConstraints(profile: p, disk: d) {
                print("SiliconForest size: \(Bytes.format(sc.minimum)) – \(Bytes.format(sc.maximum)), recommended \(Bytes.format(sc.recommended)); macOS floor \(Bytes.format(sc.macOSFloor)) = used \(Bytes.format(sc.macOSUsed)) + reserve \(Bytes.format(sc.reserve)) + downloads \(Bytes.format(sc.downloads)) + drift \(Bytes.format(sc.drift))")
            }
            print(CompatibilityChecker.canProceed(checks) ? "Ready to install." : "Not ready to install.")
        case "plan", "install", "rehearse":
            if args.command == "rehearse" && !args.real { fail("rehearse needs --real (use install for dry runs)") }
            let b = try backend(args)
            let facts = try await b.systemFacts(), snap = try await b.snapshot()
            guard let p = profile(args, facts: facts) ?? (args.command == "rehearse" ? ProfileStore.profile(id: "J293") : nil) else { fail("no profile matches this Mac (\(facts.hwModel ?? "?")); pass --profile J293 to plan anyway") }
            guard let d = snap.internalDisk, let sc = SizingConstraints(profile: p, disk: d) else { fail("no macOS container found") }
            let size = args.flags["size"].flatMap(Bytes.parse) ?? sc.recommended
            let opts = InstallOptions(siliconForestSize: sc.snap(size), installName: args.flags["name"] ?? "SiliconForest",
                                      afterSetup: args.flags["default"]?.lowercased() == "siliconforest" ? .makeDefaultAfterSuccess : .startOnceKeepMacOS)
            let plan = try Planner.installPlan(profile: p, snapshot: snap, options: opts)
            printPlan(plan)
            if args.command != "plan" {
                print("")
                exit(await run(plan, on: b, journalPath: args.flags["journal"]))
            }
        case "uninstall":
            let b = try backend(args, defaultFixture: "j293-512-installed")
            let snap = try await b.snapshot()
            guard let install = snap.siliconForestInstalls.first else { fail("no SiliconForest install found") }
            guard install.isOwned else { fail("\(Copy.Remove.notOursTitle). \(Copy.Remove.notOursBody) (\(install.unprovenReason ?? ""))") }
            let plan = try Planner.uninstallPlan(install: install, snapshot: snap)
            printPlan(plan)
            if args.real { print("\n(read-only: --real uninstall only prints the plan)"); return }
            print("")
            exit(await run(plan, on: b, journalPath: args.flags["journal"]))
        case "journal":
            guard let path = args.positional.first else { fail("journal PATH") }
            let entries = try Journal.read(URL(fileURLWithPath: path))
            let f = ISO8601DateFormatter()
            for e in entries {
                var line = "\(f.string(from: e.time))  \(e.event.rawValue.padding(toLength: 18, withPad: " ", startingAt: 0)) \(e.step?.rawValue ?? "")  \(e.message)"
                if let c = e.command { line += "\n      $ \(CommandRender.render(c))\(e.executed == false ? "   (not executed)" : "")" }
                print(line)
            }
            let st = JournalState(entries: entries)
            print("state: \(st.finished ? "finished" : st.rolledBack ? "rolled back" : st.isInterrupted ? "INTERRUPTED (resume from step \(st.resumeIndex + 1))" : "empty")")
        default:
            print(usage)
        }
    } catch {
        fail((error as? LocalizedError)?.errorDescription ?? "\(error)")
    }
}

await main()
