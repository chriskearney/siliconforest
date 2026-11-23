import Foundation
import SFIdentity
import SFEngine

/// The app's end of the connection. It pins the helper's signature the same way the helper pins
/// the app's (DESIGN §6.2).
public final class HelperClient: @unchecked Sendable {
    public let connection: NSXPCConnection

    /// Production: the helper's Mach service (registered by SMAppService; needs a signed app).
    public convenience init(helperRequirement: String = SigningIdentity.helperRequirement) {
        self.init(connection: NSXPCConnection(machServiceName: SigningIdentity.helperMachService, options: .privileged), requirement: helperRequirement)
    }

    /// Tests: an anonymous listener's endpoint, in-process.
    public convenience init(endpoint: NSXPCListenerEndpoint, requirement: String?) {
        self.init(connection: NSXPCConnection(listenerEndpoint: endpoint), requirement: requirement)
    }

    init(connection: NSXPCConnection, requirement: String?) {
        self.connection = connection
        if let requirement { connection.setCodeSigningRequirement(requirement) }
        connection.remoteObjectInterface = NSXPCInterface(with: SFHelperXPC.self)
        connection.resume()
    }

    deinit { connection.invalidate() }

    /// Calls one verb synchronously with a timeout; connection failures (including a requirement the
    /// peer doesn't meet) come back as errors.
    public func call<T>(timeout: TimeInterval = 60, _ body: (SFHelperXPC, @escaping (T?, NSError?) -> Void) -> Void) throws -> T {
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: T?
        nonisolated(unsafe) var failure: Error?
        let proxy = connection.remoteObjectProxyWithErrorHandler { e in failure = e; sem.signal() } as! SFHelperXPC
        body(proxy) { v, e in result = v; failure = e; sem.signal() }
        guard sem.wait(timeout: .now() + timeout) == .success else { throw HelperError.make(.failed, "the helper didn't answer") }
        if let failure { throw failure }
        guard let result else { throw HelperError.make(.failed, "empty reply") }
        return result
    }

    public func callVoid(timeout: TimeInterval = 60, _ body: (SFHelperXPC, @escaping (NSError?) -> Void) -> Void) throws {
        let _: Bool = try call(timeout: timeout) { p, done in body(p) { e in done(e == nil ? true : nil, e) } }
    }

    // Typed conveniences.
    public func info() throws -> HelperInfo { try Canonical.decoder().decode(HelperInfo.self, from: try call { $0.helperInfo(reply: $1) }) }
    public func topology() throws -> ImageTopology { try Canonical.decoder().decode(ImageTopology.self, from: try call { $0.readTopology(reply: $1) }) }
    public func begin(_ plan: EnginePlan) throws -> String { try call { $0.begin(plan: try! Canonical.data(plan), reply: $1) } }
    public func resume(_ job: String) throws { try callVoid { $0.resume(job: job, reply: $1) } }
    public func rollback(_ job: String) throws { try callVoid { $0.rollback(job: job, reply: $1) } }
    public func status(_ job: String) throws -> JobSummary { try Canonical.decoder().decode(JobSummary.self, from: try call { $0.jobStatus(job: job, reply: $1) }) }
    public func events(_ job: String, after: UInt64 = 0) throws -> [JournalRecord] {
        try Canonical.decoder().decode([JournalRecord].self, from: try call { $0.events(job: job, after: after, reply: $1) })
    }
    public func removalPlan(_ installJob: String) throws -> EnginePlan {
        try Canonical.decoder().decode(EnginePlan.self, from: try call { $0.removalPlan(installJob: installJob, reply: $1) })
    }
    public func beginRemoval(_ installJob: String, digest: String) throws -> String {
        try call { $0.beginRemoval(installJob: installJob, planDigest: digest, reply: $1) }
    }

    /// Polls `jobStatus` until the job stops running.
    public func wait(_ job: String, timeout: TimeInterval = 900) throws -> JobSummary {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let s = try status(job)
            if !s.running { return s }
            Thread.sleep(forTimeInterval: 0.25)
        }
        throw HelperError.make(.failed, "timed out waiting for the job")
    }
}
