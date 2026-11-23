import Foundation
import SFIdentity

/// The privileged helper's XPC interface (DESIGN §6.3). Verbs only: there is no "run this command",
/// no device names, no paths to write. The helper reads the disk itself, rebuilds every plan from
/// its own read, the verified release and the profile, and refuses on any difference.
///
/// Payloads are canonical JSON (`Data`) so both sides decode the same Codable types from SFEngine.
@objc public protocol SFHelperXPC {
    /// Version, build, minimum client build, unfinished jobs.
    func helperInfo(reply: @escaping (Data?, NSError?) -> Void)
    /// The partition table of the helper's target, read now.
    func readTopology(reply: @escaping (Data?, NSError?) -> Void)
    /// Opens a job for an approved install plan: re-derives the plan and compares digests (§5).
    func begin(plan: Data, reply: @escaping (String?, NSError?) -> Void)
    /// Starts or continues a job (resume after a crash is the same call). Returns once it is running;
    /// progress comes from `events`.
    func resume(job: String, reply: @escaping (NSError?) -> Void)
    /// Rolls a job back (allowed until the recovery handoff).
    func rollback(job: String, reply: @escaping (NSError?) -> Void)
    /// The removal plan the helper derives from a finished install's own journal (shown for approval).
    func removalPlan(installJob: String, reply: @escaping (Data?, NSError?) -> Void)
    /// Opens a removal job, if the helper's plan still has the digest the person approved.
    func beginRemoval(installJob: String, planDigest: String, reply: @escaping (String?, NSError?) -> Void)
    /// The owner's password for `bless`: held in locked memory, sent on stdin, then wiped.
    func authorizeBless(job: String, password: Data, reply: @escaping (NSError?) -> Void)
    /// Journal records after `sequence` (the app's live view and its way to reattach).
    func events(job: String, after sequence: UInt64, reply: @escaping (Data?, NSError?) -> Void)
    /// The job's state, derived from its journal.
    func jobStatus(job: String, reply: @escaping (Data?, NSError?) -> Void)
    /// Redacted diagnostics written to a handle the app opened (nothing is sent anywhere).
    func exportDiagnostics(job: String, to handle: FileHandle, reply: @escaping (NSError?) -> Void)
}

public enum HelperErrorCode: Int, Sendable {
    case refused = 1, planMismatch, noSuchJob, busy, failed, needsApproval, noTarget, clientTooOld
}

public enum HelperError {
    public static let domain = "org.siliconforest.installer.helper"
    public static func make(_ code: HelperErrorCode, _ message: String, detail: String? = nil) -> NSError {
        var info: [String: Any] = [NSLocalizedDescriptionKey: message]
        if let detail { info[NSLocalizedFailureReasonErrorKey] = detail }
        return NSError(domain: domain, code: code.rawValue, userInfo: info)
    }
}

/// Every selector the interface has, for the test that proves there is no command-running verb.
public enum HelperVerbs {
    public static let expected: Set<String> = [
        "helperInfoWithReply:", "readTopologyWithReply:", "beginWithPlan:reply:", "resumeWithJob:reply:", "rollbackWithJob:reply:",
        "removalPlanWithInstallJob:reply:", "beginRemovalWithInstallJob:planDigest:reply:", "authorizeBlessWithJob:password:reply:",
        "eventsWithJob:after:reply:", "jobStatusWithJob:reply:", "exportDiagnosticsWithJob:to:reply:",
    ]

    public static func selectors() -> Set<String> {
        var out = Set<String>()
        var n: UInt32 = 0
        for required in [true, false] {
            guard let list = protocol_copyMethodDescriptionList(SFHelperXPC.self, required, true, &n) else { continue }
            for i in 0..<Int(n) { if let s = list[i].name { out.insert(NSStringFromSelector(s)) } }
            free(list)
        }
        return out
    }
}
