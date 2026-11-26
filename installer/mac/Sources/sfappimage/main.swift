// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// sfappimage: the installer app's real install path, end to end, against a DISK IMAGE FILE (preview6).
// A lab/test tool, never in the app bundle. It runs the shipped HelperService in this process on an
// anonymous NSXPC listener, pointed at an attached sparse image through the live backend
// (ImageTargetAuthority, the same LiveDiskBackend and protection receipt as the internal disk), and
// drives it with the app's own LiveInstallController and ReleaseFetcher: the calls the Session makes.
// It can SIGKILL itself part-way (helper and app together, like a crash), and `resume` picks the
// unfinished job up from the journal, as the app does on relaunch.
//
//   sfappimage make    --image PATH                      create a J313-shaped sparse image (under .build-images) and attach it
//   sfappimage install --image PATH --release-dir D --state DIR [--ipsw URL|PATH] [--kill-at S47:0.3] [--size 40G]
//                     --kill-at S60:+8 kills 8 s after step S60 starts (a step without byte progress)
//   sfappimage resume  --image PATH --release-dir D --state DIR [--ipsw ...]
//   sfappimage refusals --image PATH --release-dir D --state DIR   the confirmation and begin refusals, no writes
//   sfappimage detach  --image PATH                      detach only this image
//
// Real disks are out of reach: the target is an ImageTargetAuthority, which refuses anything that is not
// an attached image under the images directory.

import Foundation
import SFEngine
import SFHelperKit
import SFInstallKit
import SFLiveDisk
import SFStub
import SFAppEngine

setvbuf(stdout, nil, _IOLBF, 0)

struct Args {
    var cmd = ""
    var kv: [String: String] = [:]
    init(_ argv: [String]) throws {
        guard argv.count >= 2 else { throw LiveError("usage: sfappimage <make|install|resume|refusals|detach> ...") }
        cmd = argv[1]
        var i = 2
        while i < argv.count {
            guard argv[i].hasPrefix("--"), i + 1 < argv.count else { throw LiveError("bad argument \(argv[i])") }
            kv[String(argv[i].dropFirst(2))] = argv[i + 1]; i += 2
        }
    }
    func req(_ k: String) throws -> String { guard let v = kv[k] else { throw LiveError("missing --\(k)") }; return v }
    func url(_ k: String) throws -> URL { URL(fileURLWithPath: try req(k)) }
}

/// The administrator approval stand-in: images only. The shipped helper uses AdminCheck.system.
let testApproval = Data("sfappimage: image-only approval stand-in".utf8)

/// The bless stand-in: NEVER runs bless. It records every argument list it is handed (and refuses any that
/// BlessGuard wouldn't allow, like the real runner), and keeps a pretend "startup selection" in a file so a
/// kill-and-resume or a later removal sees what an earlier run set. `--bless fail` makes setBoot exit 1.
struct RecordingBless: BlessRunner {
    var dir: URL
    var failSet: Bool
    func execute(_ argv: [String]) -> BlessResult {
        guard BlessGuard.isAllowed(argv) else { log("REFUSED \(argv)"); return BlessResult(status: 126, output: "refused") }
        log(argv.joined(separator: " "))
        let selection = dir.appendingPathComponent("bless-selection.txt")
        if argv == BlessGuard.getBoot { return BlessResult(status: 0, output: (try? String(contentsOf: selection, encoding: .utf8)) ?? "/dev/disk0s1\n") }
        if failSet && argv.contains("--setBoot") { return BlessResult(status: 1, output: "bless: simulated failure") }
        // --mount P --setBoot: the pretend selection becomes P's device.
        var fs = statfs()
        let dev = statfs(argv[2], &fs) == 0 ? withUnsafeBytes(of: fs.f_mntfromname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) } : "?"
        try? (dev + "\n").write(to: selection, atomically: true, encoding: .utf8)
        return BlessResult(status: 0, output: "")
    }
    func log(_ line: String) {
        let u = dir.appendingPathComponent("bless-calls.log")
        let h = (try? FileHandle(forWritingTo: u)) ?? { FileManager.default.createFile(atPath: u.path, contents: nil); return try! FileHandle(forWritingTo: u) }()
        h.seekToEndOfFile(); h.write(Data((line + "\n").utf8)); try? h.close()
    }
}

func startOfRun() -> Date { Date() }
let t0 = startOfRun()
func stamp() -> String { String(format: "%7.1fs", Date().timeIntervalSince(t0)) }

final class Helper {
    let listener = NSXPCListener.anonymous()
    let service: HelperService
    let delegate: HelperListenerDelegate
    init(image: URL, state: URL, ipsw: String?) throws {
        let fm = FileManager.default
        for d in ["journal", "work", "releases", "inputs"] { try fm.createDirectory(at: state.appendingPathComponent(d), withIntermediateDirectories: true) }
        let inputs = state.appendingPathComponent("inputs")
        let admin = inputs.appendingPathComponent("AdminUserRecoveryInfo.plist")
        if !fm.fileExists(atPath: admin.path) {
            try PropertyListSerialization.data(fromPropertyList: ["users": ["image-test"]], format: .xml, options: 0).write(to: admin)
        }
        let icon = inputs.appendingPathComponent("AppIcon.icns")
        if !fm.fileExists(atPath: icon.path) {
            try fm.copyItem(atPath: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericFolderIcon.icns", toPath: icon.path)
        }
        var cfg = HelperConfig(target: .live(ImageTargetAuthority(imagePath: image)),
                               journalDirectory: state.appendingPathComponent("journal"), workDirectory: state.appendingPathComponent("work"),
                               profileID: "J313", release: nil, releaseSource: nil,
                               policy: ConnectionPolicy(clientRequirement: CodeIdentity.ownDesignatedRequirement() ?? "", minimumClientBuild: 0),
                               idleTimeout: 3600)
        cfg.releaseStore = state.appendingPathComponent("releases")
        cfg.adminCheck = AdminCheck { $0 == testApproval }
        cfg.blessRunner = RecordingBless(dir: state, failSet: ProcessInfo.processInfo.environment["SF_FAKE_BLESS"] == "fail")
        cfg.shutdownDelay = 0.2
        cfg.shutdownAction = { try? Data("shut down requested\n".utf8).write(to: state.appendingPathComponent("shutdown-requested.txt")) }
        cfg.allowedSigners = SourceTree.installerRoot.appendingPathComponent("payload/release/allowed_signers")
        let rec = SourceTree.packageRoot.appendingPathComponent(".build-unit/debug/SFRecovery")
        if fm.fileExists(atPath: rec.path) { cfg.recoveryBinary = rec }
        cfg.stubSource = try HelperResources.stubSource(profileID: "J313", resources: SourceTree.packageRoot,
                                                         adminUsers: admin, restoreImage: ipsw, profileURL: SourceTree.installerRoot.appendingPathComponent("profiles/J313.json"), icon: icon)
        service = HelperService(config: cfg, lifecycle: HelperLifecycle(idleTimeout: 3600, onIdle: {}))
        delegate = HelperListenerDelegate(service: service)
        listener.delegate = delegate
        listener.resume()
    }
    func controller() -> LiveInstallController {
        let ep = listener.endpoint
        return LiveInstallController { HelperClient(endpoint: ep, requirement: CodeIdentity.ownDesignatedRequirement()) }
    }
}

func parseKill(_ s: String?) -> (String, Double)? {
    guard let s else { return nil }
    let p = s.split(separator: ":"); guard p.count == 2 else { return nil }
    if p[1].hasPrefix("+"), let secs = Double(p[1].dropFirst()) { return (String(p[0]), -secs) }   // negative: seconds after the step starts
    guard let f = Double(p[1]) else { return nil }
    return (String(p[0]), f)
}

/// The Installing screen's view of progress, as text.
func follow(_ ctl: LiveInstallController, job: String, kill: (String, Double)?) throws -> LiveProgress {
    var lastStep = ""
    var lastBytesPrint = Date.distantPast
    return try ctl.follow(job) { p in
        for e in p.events {
            switch e.kind {
            case "step":
                if e.step != lastStep {
                    lastStep = e.step; print("\(stamp())  \(e.step)  \(e.text)")
                    if let (step, at) = kill, step == e.step, at < 0 {
                        DispatchQueue.global().asyncAfter(deadline: .now() + -at) {
                            print("\(stamp())  KILL -9 \(Int(-at)) s into \(step) (helper and controller together, like a crash)")
                            fflush(stdout)
                            Darwin.kill(getpid(), SIGKILL)
                        }
                    }
                }
            case "bytes":
                let f = Double(e.done ?? 0) / Double(max(1, e.total ?? 1))
                if Date().timeIntervalSince(lastBytesPrint) > 5 || f >= 1 {
                    lastBytesPrint = Date()
                    print("\(stamp())     \(e.step) \(e.text) \(e.done ?? 0)/\(e.total ?? 0) B (\(Int(f * 100))%)")
                }
                if let (step, at) = kill, at >= 0, step == e.step, e.text == "write", f >= at {
                    print("\(stamp())  KILL -9 at \(e.step) \(Int(f * 100))% (helper and controller together, like a crash)")
                    fflush(stdout)
                    Darwin.kill(getpid(), SIGKILL)
                }
            case "resize": print("\(stamp())     diskutil: \(e.percent.map { "\($0)% " } ?? "")\(e.text)")
            case "simulated": print("\(stamp())     simulated: \(e.text)")
            case "checked": print("\(stamp())     resume check \(e.step): \(e.text)")
            case "progress":
                if let d = e.done, let t = e.total, d == t || d % 25 == 0 { print("\(stamp())     \(e.step) \(e.text)") }
            default: print("\(stamp())     \(e.kind) \(e.step) \(e.text)")
            }
        }
    }
}

func report(_ p: LiveProgress) {
    print("end: \(p.end ?? "unfinished"), running \(p.running), error \(p.lastError ?? "none"), \(p.records) journal records")
    print("completed: \(p.completed.joined(separator: " "))")
    for a in p.approvals { print("  waiting for the person: \(a.step) \(a.command.joined(separator: " "))") }
    if p.end == "handed-off" {
        print("Finish screen:")
        if let b = p.bless, b.set {
            print("  SiliconForest is installed. Startup disk set to “\(b.volumeName)” (\(b.confirmed ? "bless --getBoot confirmed it" : "not reported by --getBoot")). Button: Shut Down (enabled: \(b.canShutDown))")
            print("  · \(AfterHandoff.fallback)")
        } else {
            print("  The installer couldn't set the next boot (\(p.bless?.note ?? "no report")). Manual steps:")
            for s in AfterHandoff.manualSteps(installName: p.installName ?? "SiliconForest", command: p.bless?.manualCommand) { print("  · \(s)") }
        }
    }
}

func main() async throws {
    let a = try Args(CommandLine.arguments)
    switch a.cmd {
    case "make":
        let img = try a.url("image")
        let dir = img.deletingLastPathComponent()
        let u = try ImageFixtures.create(.j313, in: dir, name: img.deletingPathExtension().lastPathComponent)
        let b = DiskImageBackend(imagePath: u)
        try b.attach()
        print("made and attached \(u.path): \(try b.wholeDisk())")
    case "detach":
        let b = DiskImageBackend(imagePath: try a.url("image"))
        if b.isAttached() { try b.detach(force: true); print("detached") } else { print("not attached") }
    case "refusals":
        let h = try Helper(image: try a.url("image"), state: try a.url("state"), ipsw: a.kv["ipsw"])
        let ctl = h.controller()
        let rel = try await ReleaseFetcher(cache: try a.url("state").appendingPathComponent("cache"),
                                           allowedSigners: h.service.config.allowedSigners).fetch(.folder(try a.url("release-dir")))
        _ = try ctl.importRelease(rel.dir)
        let offer = try ctl.offer(bytes: a.kv["size"].flatMap(Bytes.parse), name: nil)
        var refused = 0
        func expectRefusal(_ what: String, _ body: () throws -> Void) {
            do { try body(); print("NOT REFUSED: \(what)") } catch { refused += 1; print("refused as it should: \(what): \((error as NSError).localizedDescription)") }
        }
        expectRefusal("begin before any confirmation") { _ = try ctl.begin(offer.plan) }
        expectRefusal("wrong disk name") { _ = try ctl.confirm(planDigest: offer.plan.digest, typed: TypedConfirmation(diskName: "Macintosh HD"), authorization: testApproval) }
        expectRefusal("empty name") { _ = try ctl.confirm(planDigest: offer.plan.digest, typed: TypedConfirmation(diskName: "  "), authorization: testApproval) }
        expectRefusal("no administrator approval") { _ = try ctl.confirm(planDigest: offer.plan.digest, typed: offer.expected, authorization: Data()) }
        expectRefusal("a plan the helper never offered") { _ = try ctl.confirm(planDigest: String(repeating: "0", count: 64), typed: offer.expected, authorization: testApproval) }
        var tampered = offer.plan; tampered.macOS.to -= Bytes.gb
        expectRefusal("a changed plan") { _ = try ctl.begin(tampered.sealed()) }
        print("refusals: \(refused)/6; journal jobs left: \(ChainJournal.unfinished(in: try a.url("state").appendingPathComponent("journal")).count)")
        if refused != 6 { exit(1) }
    case "install":
        let h = try Helper(image: try a.url("image"), state: try a.url("state"), ipsw: a.kv["ipsw"])
        let ctl = h.controller()
        print("\(stamp())  helper: \(try ctl.info().target)")
        // Screen: Getting the release (download or local folder → cache → local verify → helper import + verify)
        let rel = try await ReleaseFetcher(cache: try a.url("state").appendingPathComponent("cache"),
                                           allowedSigners: h.service.config.allowedSigners).fetch(.folder(try a.url("release-dir"))) { n, d, t, _ in
            if d == t || d % 20 == 0 { print("\(stamp())     fetched \(d)/\(t) (\(n))") }
        }
        print("\(stamp())  release \(rel.manifest.version) verified in the app's cache (\(rel.dir.lastPathComponent))")
        let sum = try ctl.importRelease(rel.dir)
        print("\(stamp())  helper imported and verified \(sum.version): \(sum.files) files, stage 1 \(sum.stage1SHA256.prefix(16))…")
        // Screen: Review (the helper's plan)
        let offer = try ctl.offer(bytes: a.kv["size"].flatMap(Bytes.parse), name: nil)
        print("\(stamp())  plan \(offer.plan.digest.prefix(16))… on \(offer.target): macOS \(offer.plan.macOS.from) → \(offer.plan.macOS.to) B")
        for p in offer.plan.partitions { print("        new \(p.role) \(p.bytes) B \(p.content) “\(p.label)”") }
        print("        steps: \(offer.steps.map(\.code).joined(separator: " "))")
        // Screen: Confirm (type the disk name and the phrase; administrator approval)
        print("\(stamp())  typing “\(offer.expected.diskName.uppercased())” (case is forgiven); administrator approval (image stand-in)")
        let c = try ctl.confirm(planDigest: offer.plan.digest, typed: offer.expected, authorization: testApproval)
        print("\(stamp())  confirmed until \(c.validUntil) (authorization file written: \(c.authorizationFileWritten), images need none)")
        // Screen: Installing
        let job = try ctl.begin(offer.plan)
        print("\(stamp())  began job \(job)")
        try ctl.start(job)
        let p = try follow(ctl, job: job, kill: parseKill(a.kv["kill-at"]))
        report(p)
        if p.end != "handed-off" { exit(1) }
    case "restart":
        // The finish screen's button: the helper's restart verb (a recorder here; the real one is shutdown -h now).
        let h = try Helper(image: try a.url("image"), state: try a.url("state"), ipsw: a.kv["ipsw"])
        let ctl = h.controller()
        guard let job = try ctl.installs().first?.job else { throw LiveError("no finished install") }
        let st = try a.url("state").appendingPathComponent("shutdown-requested.txt")
        try? FileManager.default.removeItem(at: st)
        do { try ctl.shutDown(job); try await Task.sleep(nanoseconds: 1_000_000_000) } catch { print("shut down refused: \((error as NSError).localizedDescription)") }
        print("restart recorder: \(FileManager.default.fileExists(atPath: st.path) ? "shut down requested" : "NOT requested")")
    case "remove":
        // The Remove SiliconForest screens through the app's code path: list, plan, type, administrator, begin, follow.
        let h = try Helper(image: try a.url("image"), state: try a.url("state"), ipsw: a.kv["ipsw"])
        let ctl = h.controller()
        let hc = HelperClient(endpoint: h.listener.endpoint, requirement: CodeIdentity.ownDesignatedRequirement())
        let list = try ctl.installs()
        print("\(stamp())  installs found: \(list.map { "\($0.name) \($0.installID) removable=\($0.removable)\($0.note.map { " (\($0))" } ?? "")" }.joined(separator: "; "))")
        guard let target = list.first(where: \.removable) else { throw LiveError("nothing removable") }
        let before = try hc.topology()
        let offer = try ctl.offerRemoval(target.job)
        print("\(stamp())  removal plan \(offer.plan.digest.prefix(16))…: macOS \(offer.plan.macOS.from) → \(offer.plan.macOS.to) B; steps \(offer.steps.map(\.code).joined(separator: " ")); type “\(offer.expected.diskName)”")
        func expectRefusal(_ what: String, _ body: () throws -> Void) {
            do { try body(); print("NOT REFUSED: \(what)"); exit(1) } catch { print("refused as it should: \(what): \((error as NSError).localizedDescription)") }
        }
        expectRefusal("removal begun before any confirmation") { _ = try ctl.beginRemoval(installJob: target.job, plan: offer.plan) }
        expectRefusal("removal with another volume's name") { _ = try ctl.confirm(planDigest: offer.plan.digest, typed: TypedConfirmation(diskName: "Some Other Volume"), authorization: testApproval) }
        let c = try ctl.confirm(planDigest: offer.plan.digest, typed: offer.expected, authorization: testApproval)
        print("\(stamp())  confirmed until \(c.validUntil)")
        let job = try ctl.beginRemoval(installJob: target.job, plan: offer.plan)
        print("\(stamp())  began removal job \(job)")
        try ctl.start(job)
        let p = try follow(ctl, job: job, kill: parseKill(a.kv["kill-at"]))
        report(p)
        guard p.end == "committed" else { exit(1) }
        let after = try hc.topology()
        let mb = before.partitions.first { $0.uuid == offer.plan.macOS.store }?.size ?? 0, ma = after.partitions.first { $0.uuid == offer.plan.macOS.store }?.size ?? 0
        print("macOS container: \(mb) B before removal, \(ma) B after; plan's original size \(offer.plan.macOS.to) B")
        print("layout digest now \(after.layoutDigest.prefix(16))…, original \((offer.plan.originalLayoutDigest ?? "").prefix(16))…: \(after.layoutDigest == (offer.plan.originalLayoutDigest ?? "") ? "IDENTICAL" : "DIFFERENT")")
        print("partitions after: \(after.partitions.map { "\($0.content) \($0.size)" }.joined(separator: ", "))")
        print("installs left: \(try ctl.installs().count)")
        if after.layoutDigest != (offer.plan.originalLayoutDigest ?? "") || ma != offer.plan.macOS.to { exit(1) }
    case "resume":
        let h = try Helper(image: try a.url("image"), state: try a.url("state"), ipsw: a.kv["ipsw"])
        let ctl = h.controller()
        // What the app does on relaunch: ask the helper for unfinished jobs and offer to resume.
        let jobs = try ctl.unfinishedJobs()
        print("\(stamp())  unfinished jobs: \(jobs.joined(separator: ", "))")
        guard jobs.count == 1, let job = jobs.first else { throw LiveError("expected exactly one unfinished job") }
        let before = try ctl.progress(job, after: 0)
        print("\(stamp())  resuming \(job): \(before.records) records, completed \(before.completed.joined(separator: " "))")
        try ctl.start(job)
        let p = try follow(ctl, job: job, kill: parseKill(a.kv["kill-at"]))
        report(p)
        if p.end != "handed-off" && p.end != "committed" { exit(1) }
    default:
        throw LiveError("unknown command \(a.cmd)")
    }
}

do { try await main() } catch {
    FileHandle.standardError.write(Data("sfappimage: \((error as? LocalizedError)?.errorDescription ?? "\(error)")\n".utf8))
    exit(1)
}
