import Foundation
import SFIdentity
import SFInstallKit
import SFEngine
import SFLiveDisk

/// What the helper works on. The shipped helper's target is `.none`. `.image` rehearses on a disk image
/// with the image-only backend. `.live` runs the `LiveDiskBackend` against a `TargetAuthority`: an
/// attached disk image in tests, and only in a build with `SF_REAL_DISK_WRITES` plus a valid runtime
/// authorization (RealDiskGate), the internal disk (ENGINE §12).
public struct HelperConfig: Sendable {
    /// `.internalDisk`: this Mac's startup disk, found by identity at each plan, through
    /// `InternalDiskAuthority`. It exists only in a build with `SF_REAL_DISK_WRITES`; without it every
    /// verb that would touch the disk answers `noTarget`.
    public enum Target: Sendable { case none, image(URL), live(any TargetAuthority), internalDisk }
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
    /// Set: the engine builds the stub with SFStub (needed by a stub-only plan).
    public var stubSource: StubSource?
    /// `begin` refuses a plan the person hasn't confirmed (`confirm`) in the last 2 hours.
    public var requireConfirmation = true
    /// Where the helper writes the runtime authorization after a confirmation (internal disk only).
    public var authorizationPath = RealDiskGate.authorizationPath
    /// Where imported releases are copied (root-only in production). Nil: next to the work directory.
    public var releaseStore: URL?
    /// Checks the administrator's authorization sent with `confirm`. Production: `.system`.
    public var adminCheck: AdminCheck = .never
    /// Tests only: accept a TEST-ONLY rehearsal release on import.
    public var allowRehearsalRelease = false
    /// The release key's allowed_signers (nil: SFRelease's lookup, the app bundle's copy).
    public var allowedSigners: URL?
    /// Runs the one-time bless after the stub is staged (S65), and the removal's reset (U10). Only SFHelper
    /// in a SF_REAL_DISK_WRITES build sets a real one; tests set a recorder; nil simulates (the lab tools).
    public var blessRunner: BlessRunner?
    /// Restarts this Mac (`restartIntoInstalledSystem`). Same rules: nil refuses.
    public var restartAction: (@Sendable () -> Void)?
    /// Seconds between the restart verb's reply and the restart itself.
    public var restartDelay: TimeInterval = 3

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
    let lock = NSLock()
    var running: Set<UUID> = []
    var lastError: [UUID: String] = [:]
    /// The release imported by `importRelease` (verified in the helper's own store).
    var imported: (manifest: ReleaseManifest, dir: URL)?
    /// Plans offered by `planInstall` / `removalPlan`, by digest, with what the person must type.
    var offers: [String: (plan: EnginePlan, expected: TypedConfirmation, diskUUID: String?)] = [:]
    /// Confirmed plan digests and until when.
    var confirmed: [String: Date] = [:]
    /// Live events per job (not journaled): step titles, SFStub progress, bytes, diskutil percentages.
    var live: [UUID: [LiveEvent]] = [:]
    var liveSeq: UInt64 = 0
    private var passwords: [UUID: SecureBytes] = [:]
    /// Tests look at this to prove the password was wiped.
    public private(set) var lastPassword: SecureBytes?

    public init(config: HelperConfig, lifecycle: HelperLifecycle? = nil) {
        self.config = config
        self.lifecycle = lifecycle ?? HelperLifecycle(idleTimeout: config.idleTimeout)
    }

    // MARK: plumbing

    func backend(planDigest: String? = nil) throws -> any EngineBackend {
        switch config.target {
        case .image(let url): return DiskImageBackend(imagePath: url, allowedRoot: config.allowedImageRoot)
        case .live(let authority): return LiveDiskBackend(authority: authority)
        case .internalDisk:
            #if SF_REAL_DISK_WRITES
            guard let planDigest else { throw HelperError.make(.refused, "the internal disk is only opened for one confirmed plan") }
            guard geteuid() == 0 else { throw HelperError.make(.refused, "the internal disk needs the root helper") }
            let disk = try StartupDisk.find()
            return LiveDiskBackend(authority: try InternalDiskAuthority(planDigest: planDigest, diskUUID: disk.uuid,
                                                                       gate: { [path = config.authorizationPath] in
                                                                           RealDiskGate.evaluate(planDigest: planDigest, diskUUID: disk.uuid, path: path) }))
            #else
            _ = planDigest
            throw HelperError.make(.noTarget, "This build can't write to an internal disk (no SF_REAL_DISK_WRITES).")
            #endif
        case .none: throw HelperError.make(.noTarget, "This build of the helper has no disk target; nothing is written.")
        }
    }

    /// The target's partition table and the macOS container's resize limits, read-only (no write authority).
    func readTarget() throws -> (topology: ImageTopology, limits: TopologyReader.ResizeLimits?, diskUUID: String?) {
        switch config.target {
        case .internalDisk:
            #if SF_REAL_DISK_WRITES
            let disk = try StartupDisk.find()
            let (t, l) = try StubOnlyRun.read(.internalDisk(disk.uuid))
            return (t, l, disk.uuid)
            #else
            throw HelperError.make(.noTarget, "This build can't read an internal disk for an install (no SF_REAL_DISK_WRITES).")
            #endif
        default:
            let b = try backend()
            let t = try b.topology()
            return (t, try t.macOS.map { try b.limits(store: $0.uuid) }, nil)
        }
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

    func engine(_ j: ChainJournal, planDigest: String? = nil, operation: EnginePlan.Operation? = nil) throws -> InstallEngine {
        let st = JobState(j.records)
        let digest = planDigest ?? st.plan?.digest
        let rel = try release(for: j, plan: st.plan, operation: operation)
        let e = InstallEngine(backend: try backend(planDigest: digest), journal: j, profile: try profile(), release: rel.manifest, releaseSource: rel.dir,
                              workDir: config.workDirectory.appendingPathComponent(j.jobID.uuidString), resizeTiming: config.resizeTiming)
        e.recoveryBinary = config.recoveryBinary
        e.stubSource = config.stubSource
        e.bless = config.blessRunner
        if (operation ?? st.plan?.operation ?? .install) == .install, e.stubSource == nil, case .internalDisk = config.target {
            throw HelperError.make(.refused, "the helper can't build the stub (no profile, icon or admin list)")
        }
        let id = j.jobID
        e.onEvent = { [weak self] ev in self?.record(id, ev) }
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

    func reply<T>(_ r: (T?, NSError?) -> Void, _ body: () throws -> T) {
        do { r(try body(), nil) } catch { r(nil, Self.nsError(error)) }
    }

    // MARK: verbs

    public func helperInfo(reply: @escaping (Data?, NSError?) -> Void) {
        self.reply(reply) {
            let target: String
            switch config.target {
            case .image(let u): target = "image \(u.lastPathComponent)"
            case .live(let a): target = "live \(a.label)"
            case .internalDisk: target = RealDiskGate.compiledIn ? "internal disk" : "internal disk (not compiled in)"
            case .none: target = "none"
            }
            let unfinished = ChainJournal.unfinished(in: config.journalDirectory).map { $0.deletingPathExtension().lastPathComponent }
            return try Canonical.data(HelperInfo(identifier: SigningIdentity.helperIdentifier, build: config.helperBuild,
                                                 minimumClientBuild: config.policy.minimumClientBuild, target: target, unfinishedJobs: unfinished))
        }
    }

    public func readTopology(reply: @escaping (Data?, NSError?) -> Void) {
        self.reply(reply) { try Canonical.data(try readTarget().topology) }
    }

    public func begin(plan: Data, reply: @escaping (String?, NSError?) -> Void) {
        self.reply(reply) {
            let p = try Canonical.decoder().decode(EnginePlan.self, from: plan)
            guard p.operation == .install else { throw HelperError.make(.refused, "use beginRemoval for a removal") }
            try requireConfirmed(p.digest)
            let j = try ChainJournal(directory: config.journalDirectory)
            do { try rememberRelease(for: j); try engine(j, planDigest: p.digest).begin(p) } catch {
                try? FileManager.default.removeItem(at: releaseNote(j))
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
            let read = try readTarget()
            let plan = try EnginePlanner.removalPlan(topology: read.topology, profile: try profile(), proof: proof)
            offer(plan, topology: read.topology, diskUUID: read.diskUUID)
            return try Canonical.data(plan)
        }
    }

    public func beginRemoval(installJob: String, planDigest: String, reply: @escaping (String?, NSError?) -> Void) {
        self.reply(reply) {
            let proof = try InstallProofReader.proof(from: try journal(installJob))
            let plan = try EnginePlanner.removalPlan(topology: try readTarget().topology, profile: try profile(), proof: proof)
            guard plan.digest == planDigest else { throw HelperError.make(.planMismatch, "the disk changed since you confirmed the removal") }
            try requireConfirmed(plan.digest)
            let j = try ChainJournal(directory: config.journalDirectory)
            let e = try engine(j, planDigest: plan.digest, operation: .remove)
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
