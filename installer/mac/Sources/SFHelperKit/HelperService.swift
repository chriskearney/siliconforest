import Foundation
import SFIdentity
import SFInstallKit
import SFEngine

/// What the helper works on. In this build the only target is a disk image (rehearsal); the real
/// internal disk needs a `LiveDiskBackend`, which does not exist yet and is never linked into
/// test or simulator builds (ENGINE §12).
public struct HelperConfig: Sendable {
    public enum Target: Sendable { case none, image(URL) }
    public var target: Target
    public var allowedImageRoot: URL
    /// Root-only in production (`/var/db/org.siliconforest.installer/journal`). The helper owns it;
    /// the app only ever reads events through XPC.
    public var journalDirectory: URL
    public var workDirectory: URL
    public var profileID: String
    /// The verified release (the helper verifies it itself before the first write).
    public var release: ReleaseManifest?
    public var releaseSource: URL?
    public var policy: ConnectionPolicy
    public var idleTimeout: TimeInterval
    public var helperBuild: Int
    public var resizeTiming: ResizeSupervisor.Timing
    public var recoveryBinary: URL?

    public init(target: Target, allowedImageRoot: URL = ImageGuard.defaultRoot, journalDirectory: URL = ChainJournal.defaultDirectory,
                workDirectory: URL, profileID: String, release: ReleaseManifest?, releaseSource: URL?, policy: ConnectionPolicy = ConnectionPolicy(),
                idleTimeout: TimeInterval = 30, helperBuild: Int = 1, resizeTiming: ResizeSupervisor.Timing = .init(), recoveryBinary: URL? = nil) {
        self.target = target; self.allowedImageRoot = allowedImageRoot; self.journalDirectory = journalDirectory; self.workDirectory = workDirectory
        self.profileID = profileID; self.release = release; self.releaseSource = releaseSource; self.policy = policy; self.idleTimeout = idleTimeout
        self.helperBuild = helperBuild; self.resizeTiming = resizeTiming; self.recoveryBinary = recoveryBinary
    }
}

public struct HelperInfo: Codable, Sendable {
    public var identifier: String
    public var build: Int
    public var minimumClientBuild: Int
    public var target: String
    public var unfinishedJobs: [String]
}

public struct JobSummary: Codable, Sendable {
    public var job: String
    public var running: Bool
    public var end: String?
    public var noChangesMade: Bool
    public var completed: [String]
    public var failed: [String: String]
    public var approvalsNeeded: [ApprovalNeeded]
    public var lastError: String?
    public var records: Int
}

/// The helper's side of every verb. One serial queue runs jobs; replies never wait for a job.
public final class HelperService: NSObject, SFHelperXPC, @unchecked Sendable {
    public let config: HelperConfig
    public let lifecycle: HelperLifecycle
    private let jobQueue = DispatchQueue(label: "org.siliconforest.helper.jobs")
    private let lock = NSLock()
    private var running: Set<UUID> = []
    private var lastError: [UUID: String] = [:]
    private var passwords: [UUID: SecureBytes] = [:]
    /// Tests look at this to prove the password was wiped.
    public private(set) var lastPassword: SecureBytes?

    public init(config: HelperConfig, lifecycle: HelperLifecycle? = nil) {
        self.config = config
        self.lifecycle = lifecycle ?? HelperLifecycle(idleTimeout: config.idleTimeout)
    }

    // MARK: plumbing

    func backend() throws -> DiskImageBackend {
        guard case .image(let url) = config.target else {
            throw HelperError.make(.noTarget, "This build of the helper has no disk backend; it rehearses on disk images only.")
        }
        return DiskImageBackend(imagePath: url, allowedRoot: config.allowedImageRoot)
    }

    func profile() throws -> DeviceProfile {
        guard let p = ProfileStore.profile(id: config.profileID) else { throw HelperError.make(.failed, "profile \(config.profileID) not found") }
        return p
    }

    func journal(_ job: String) throws -> ChainJournal {
        guard let id = UUID(uuidString: job) else { throw HelperError.make(.noSuchJob, "not a job id") }
        let url = config.journalDirectory.appendingPathComponent("\(id.uuidString).jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { throw HelperError.make(.noSuchJob, "no such job") }
        return try ChainJournal.open(url)
    }

    func engine(_ j: ChainJournal) throws -> InstallEngine {
        let e = InstallEngine(backend: try backend(), journal: j, profile: try profile(), release: config.release, releaseSource: config.releaseSource,
                              workDir: config.workDirectory.appendingPathComponent(j.jobID.uuidString), resizeTiming: config.resizeTiming)
        e.recoveryBinary = config.recoveryBinary
        return e
    }

    static func nsError(_ e: Error) -> NSError {
        if let n = e as NSError?, n.domain == HelperError.domain { return n }
        switch e {
        case let r as SafetyRefusal: return HelperError.make(.refused, r.reason)
        case let p as PlanRefusal: return HelperError.make(.planMismatch, p.reason)
        case let ee as EngineError: return HelperError.make(.failed, ee.message, detail: ee.detail)
        default: return HelperError.make(.failed, e.localizedDescription)
        }
    }

    private func reply<T>(_ r: (T?, NSError?) -> Void, _ body: () throws -> T) {
        do { r(try body(), nil) } catch { r(nil, Self.nsError(error)) }
    }

    // MARK: verbs

    public func helperInfo(reply: @escaping (Data?, NSError?) -> Void) {
        self.reply(reply) {
            let target: String
            if case .image(let u) = config.target { target = "image \(u.lastPathComponent)" } else { target = "none" }
            let unfinished = ChainJournal.unfinished(in: config.journalDirectory).map { $0.deletingPathExtension().lastPathComponent }
            return try Canonical.data(HelperInfo(identifier: SigningIdentity.helperIdentifier, build: config.helperBuild,
                                                 minimumClientBuild: config.policy.minimumClientBuild, target: target, unfinishedJobs: unfinished))
        }
    }

    public func readTopology(reply: @escaping (Data?, NSError?) -> Void) {
        self.reply(reply) { try Canonical.data(try backend().topology()) }
    }

    public func begin(plan: Data, reply: @escaping (String?, NSError?) -> Void) {
        self.reply(reply) {
            let p = try Canonical.decoder().decode(EnginePlan.self, from: plan)
            guard p.operation == .install else { throw HelperError.make(.refused, "use beginRemoval for a removal") }
            let j = try ChainJournal(directory: config.journalDirectory)
            do { try engine(j).begin(p) } catch {
                try? FileManager.default.removeItem(at: j.url)   // nothing happened: leave no job behind
                throw error
            }
            return j.jobID.uuidString
        }
    }

    public func resume(job: String, reply: @escaping (NSError?) -> Void) {
        start(job, reply: reply) { try $0.run() }
    }

    public func rollback(job: String, reply: @escaping (NSError?) -> Void) {
        start(job, reply: reply) { try $0.rollback() }
    }

    private func start(_ job: String, reply: @escaping (NSError?) -> Void, _ work: @escaping @Sendable (InstallEngine) throws -> JobEnd) {
        do {
            let j = try journal(job)
            let e = try engine(j)
            lock.lock()
            if running.contains(j.jobID) { lock.unlock(); reply(nil); return }   // already running: attach via events
            running.insert(j.jobID); lastError[j.jobID] = nil
            lock.unlock()
            lifecycle.jobStarted()
            jobQueue.async { [self] in
                var err: String?
                do { _ = try work(e) } catch { err = (error as? LocalizedError)?.errorDescription ?? "\(error)" }
                lock.lock(); running.remove(j.jobID); lastError[j.jobID] = err; lock.unlock()
                lifecycle.jobEnded()
            }
            reply(nil)
        } catch { reply(Self.nsError(error)) }
    }

    public func removalPlan(installJob: String, reply: @escaping (Data?, NSError?) -> Void) {
        self.reply(reply) {
            let proof = try InstallProofReader.proof(from: try journal(installJob))
            return try Canonical.data(try EnginePlanner.removalPlan(topology: try backend().topology(), profile: try profile(), proof: proof))
        }
    }

    public func beginRemoval(installJob: String, planDigest: String, reply: @escaping (String?, NSError?) -> Void) {
        self.reply(reply) {
            let proof = try InstallProofReader.proof(from: try journal(installJob))
            let plan = try EnginePlanner.removalPlan(topology: try backend().topology(), profile: try profile(), proof: proof)
            guard plan.digest == planDigest else { throw HelperError.make(.planMismatch, "the disk changed since you confirmed the removal") }
            let j = try ChainJournal(directory: config.journalDirectory)
            let e = try engine(j)
            e.proof = proof
            do { try e.begin(plan) } catch { try? FileManager.default.removeItem(at: j.url); throw error }
            return j.jobID.uuidString
        }
    }

    public func authorizeBless(job: String, password: Data, reply: @escaping (NSError?) -> Void) {
        let secret = SecureBytes(password)
        lastPassword = secret
        defer { secret.wipe() }
        do {
            let j = try journal(job)
            lock.lock(); passwords[j.jobID]?.wipe(); passwords[j.jobID] = nil; lock.unlock()
            // On a disk image there is no startup disk to change: S65 is simulated and recorded as
            // needing Chris's approval. The password is wiped without being used or stored.
            reply(HelperError.make(.needsApproval, "bless needs root and a real startup disk; on a disk image it is simulated",
                                   detail: "the password was held in locked memory and wiped unused"))
        } catch { reply(Self.nsError(error)) }
    }

    public func events(job: String, after sequence: UInt64, reply: @escaping (Data?, NSError?) -> Void) {
        self.reply(reply) { try Canonical.data(try journal(job).records.filter { $0.seq > sequence }) }
    }

    public func jobStatus(job: String, reply: @escaping (Data?, NSError?) -> Void) {
        self.reply(reply) {
            let j = try journal(job)
            let st = JobState(j.records)
            lock.lock(); let isRunning = running.contains(j.jobID); let err = lastError[j.jobID]; lock.unlock()
            let done = StepCode.allCases.filter { st.done($0) }.map(\.rawValue)
            return try Canonical.data(JobSummary(job: job, running: isRunning, end: st.end?.rawValue, noChangesMade: st.noChangesMade,
                                                 completed: done, failed: Dictionary(uniqueKeysWithValues: st.failed.map { ($0.key.rawValue, $0.value) }),
                                                 approvalsNeeded: st.approvals, lastError: err, records: j.records.count))
        }
    }

    public func exportDiagnostics(job: String, to handle: FileHandle, reply: @escaping (NSError?) -> Void) {
        do { try Diagnostics.write(journal: try journal(job), to: handle); try handle.close(); reply(nil) }
        catch { reply(Self.nsError(error)) }
    }
}

/// Accepts connections: the system enforces the signing requirement on the connection before any
/// message is delivered; the minimum build is checked here.
public final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    public let service: HelperService
    public init(service: HelperService) { self.service = service }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection) -> Bool {
        let policy = service.config.policy
        guard CodeIdentity.bundleBuild(pid: c.processIdentifier) >= policy.minimumClientBuild else { return false }
        c.setCodeSigningRequirement(policy.clientRequirement)
        c.exportedInterface = NSXPCInterface(with: SFHelperXPC.self)
        c.exportedObject = service
        let lifecycle = service.lifecycle
        lifecycle.connectionStarted()
        c.invalidationHandler = { lifecycle.connectionEnded() }
        c.resume()
        return true
    }
}
