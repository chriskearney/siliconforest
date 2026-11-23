import Foundation
import Testing
@testable import SFHelperKit
@testable import SFEngine
import SFIdentity
import SFInstallKit

/// A helper on an anonymous NSXPC listener in this process, talking to a client over a real
/// NSXPCConnection: the same interface, trust checks and service the launchd helper uses.
final class InProcessHelper: @unchecked Sendable {
    let listener = NSXPCListener.anonymous()
    let service: HelperService
    let delegate: HelperListenerDelegate
    init(_ config: HelperConfig, lifecycle: HelperLifecycle? = nil) {
        // Never the production idle action (exit(0)): it would end the whole test process.
        service = HelperService(config: config, lifecycle: lifecycle ?? HelperLifecycle(idleTimeout: config.idleTimeout, onIdle: {}))
        delegate = HelperListenerDelegate(service: service)
        listener.delegate = delegate
        listener.resume()
    }
    func client(requirement: String? = CodeIdentity.ownDesignatedRequirement()) -> HelperClient {
        HelperClient(endpoint: listener.endpoint, requirement: requirement)
    }
    deinit { listener.invalidate() }
}

private func tempDir() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("sf-helper-\(UUID().uuidString)") }

private func config(target: HelperConfig.Target = .none, journal: URL = tempDir(), policy: ConnectionPolicy? = nil) -> HelperConfig {
    HelperConfig(target: target, journalDirectory: journal, workDirectory: journal.appendingPathComponent("work"), profileID: "J293",
                 release: nil, releaseSource: nil,
                 policy: policy ?? ConnectionPolicy(clientRequirement: CodeIdentity.ownDesignatedRequirement() ?? "", minimumClientBuild: 0),
                 idleTimeout: 0.3, resizeTiming: .tests)
}

@Suite("Helper: XPC trust and verbs")
struct HelperTrustTests {
    @Test func theInterfaceIsVerbsOnly() {
        let sels = HelperVerbs.selectors()
        #expect(sels == HelperVerbs.expected, "\(sels.symmetricDifference(HelperVerbs.expected))")
        for s in sels {
            for word in ["command", "exec", "shell", "argv", "path", "device", "disk", "script", "run"] {
                #expect(!s.lowercased().contains(word), "\(s) looks like a way to run something")
            }
        }
    }

    @Test func requirementsCompileAndPinOneTeam() {
        for r in [SigningIdentity.appRequirement, SigningIdentity.helperRequirement, SigningIdentity.recoveryRequirement] {
            #expect(CodeIdentity.requirementCompiles(r), "\(r)")
            #expect(r.contains("certificate leaf[subject.OU] = \"Z642ZK8JK4\""))
        }
        #expect(SigningIdentity.teamID == "Z642ZK8JK4")
        #expect(CodeIdentity.ownDesignatedRequirement()?.hasPrefix("cdhash") == true, "the test binary is ad hoc signed")
    }

    @Test func aPinnedClientIsServedAndAnUnsignedOneIsNot() throws {
        let h = InProcessHelper(config())
        let info = try h.client().info()
        #expect(info.identifier == "org.siliconforest.installer.helper" && info.target == "none")
        // The helper requires our Developer ID app signature: this ad hoc test binary is refused.
        let strict = InProcessHelper(config(policy: ConnectionPolicy(clientRequirement: SigningIdentity.appRequirement, minimumClientBuild: 0)))
        #expect(throws: (any Error).self) { try strict.client().info() }
        // The client pins the helper's Developer ID signature: an ad hoc helper is refused too.
        #expect(throws: (any Error).self) { try h.client(requirement: SigningIdentity.helperRequirement).info() }
    }

    @Test func tooOldAClientIsRefused() throws {
        // A bare test binary has no CFBundleVersion: build 0, below a minimum of 1.
        let h = InProcessHelper(config(policy: ConnectionPolicy(clientRequirement: CodeIdentity.ownDesignatedRequirement() ?? "", minimumClientBuild: 1)))
        #expect(throws: (any Error).self) { try h.client().info() }
    }

    @Test func withoutATargetEveryDiskVerbRefuses() throws {
        let h = InProcessHelper(config())
        let c = h.client()
        do { _ = try c.topology(); Issue.record("no target") } catch let e as NSError { #expect(e.code == HelperErrorCode.noTarget.rawValue) }
        #expect(throws: (any Error).self) { try c.resume(UUID().uuidString) }
    }

    @Test func thePasswordIsWipedAndNeverUsedOnAnImage() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let j = try ChainJournal(directory: dir); try j.append(.begin)
        let h = InProcessHelper(config(journal: dir))
        let c = h.client()
        do { try c.callVoid { $0.authorizeBless(job: j.jobID.uuidString, password: Data("correct horse".utf8), reply: $1) }; Issue.record("should say needs approval") }
        catch let e as NSError { #expect(e.code == HelperErrorCode.needsApproval.rawValue) }
        let secret = try #require(h.service.lastPassword)
        #expect(secret.isWiped && secret.isZeroed)
        #expect(!(try String(contentsOf: j.url, encoding: .utf8)).contains("horse"))
    }

    @Test func theHelperGoesAwayWhenIdle() throws {
        let fired = Flag()
        let life = HelperLifecycle(idleTimeout: 0.2) { fired.set() }
        let h = InProcessHelper(config(), lifecycle: life)
        do { let c = h.client(); _ = try c.info(); c.connection.invalidate() }
        let deadline = Date().addingTimeInterval(5)
        while !fired.value && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        #expect(fired.value)
    }

    @Test func diagnosticsAreRedacted() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let j = try ChainJournal(directory: dir)
        try j.append(.evidence, step: "S30", result: ["uuid": .s("9EAF2394-01F2-425E-8BB4-B0918061834C"), "dev": .s("/dev/rdisk5s3 and disk5")])
        let b = Diagnostics.bundle(journal: j)
        let text = b.journal.joined()
        #expect(!text.contains("9EAF2394") && text.contains("uuid-") && !text.contains("disk5") && text.contains("rdisk-A"))
    }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock(); private var v = false
    func set() { lock.lock(); v = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return v }
}

@Suite("Helper: a whole job over XPC on a disk image", .serialized, .enabled(if: ImageLab.enabled))
struct HelperImageTests {
    @Test func installStatusEventsDiagnosticsAndRemovalOverXPC() throws {
        let c = try ImageLab.fresh(.j293); defer { c.finish() }
        let (release, src) = try ImageLab.release()
        let profile = try ImageLab.profile()
        let original = try c.backend.topology()
        let journalDir = c.journalDir
        var cfg = config(target: .image(c.image), journal: journalDir)
        cfg.release = release; cfg.releaseSource = src; cfg.workDirectory = c.workDir
        let h = InProcessHelper(cfg)
        let client = h.client()

        // The app reads the disk through the helper and builds the plan the person approves.
        let t = try client.topology()
        #expect(t.layoutDigest == original.layoutDigest)
        let plan = try ImageLab.plan(c, profile: profile)
        // A plan the helper can't rebuild is refused, and no job is left behind.
        var bad = plan; bad.macOS.to -= Bytes.gb
        #expect(throws: (any Error).self) { try client.begin(bad.sealed()) }
        #expect(ChainJournal.unfinished(in: journalDir).isEmpty)

        let job = try client.begin(plan)
        try client.resume(job)
        try client.resume(job)               // a second resume while running just attaches
        var seen: UInt64 = 0
        while try client.status(job).running {
            let ev = try client.events(job, after: seen)
            seen = ev.last?.seq ?? seen
            Thread.sleep(forTimeInterval: 0.3)
        }
        let s = try client.status(job)
        #expect(s.end == "handed-off" && s.lastError == nil, "\(s)")
        #expect(s.approvalsNeeded.map(\.step) == ["S20", "S65"])
        #expect(try client.events(job).count == s.records)
        try ImageEngineTests.expectInstalled(c, journal: try ChainJournal(directory: journalDir, jobID: UUID(uuidString: job)!), plan: plan)

        // Diagnostics through a handle the app opened.
        let out = c.dir.appendingPathComponent("diag.json")
        FileManager.default.createFile(atPath: out.path, contents: nil)
        try client.callVoid { $0.exportDiagnostics(job: job, to: try! FileHandle(forWritingTo: out), reply: $1) }
        let diag = try String(contentsOf: out, encoding: .utf8)
        #expect(diag.contains("uuid-1") && !diag.contains(plan.macOS.store))

        // Removal: the helper derives it from its own journal; the app confirms by digest.
        let removal = try client.removalPlan(job)
        #expect(throws: (any Error).self) { try client.beginRemoval(job, digest: "not-the-digest") }
        let rjob = try client.beginRemoval(job, digest: removal.digest)
        try client.resume(rjob)
        let rs = try client.wait(rjob)
        #expect(rs.end == "committed", "\(rs)")
        #expect(try c.backend.topology().digestForm == original.digestForm)
    }
}
