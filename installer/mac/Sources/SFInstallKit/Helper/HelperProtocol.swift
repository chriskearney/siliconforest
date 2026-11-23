import Foundation

/// The privileged helper's API (docs/installer/DESIGN.md §6.3): verbs, never commands. The helper
/// rebuilds the plan from its own read of the disk, the verified release and the profile, and refuses
/// if the digest differs from what the person approved. Placeholder: nothing implements this yet.
///
/// Mechanism (§6.1): `SMAppService.daemon(plistName: "org.siliconforest.installer.helper.plist")`,
/// plist in `Contents/Library/LaunchDaemons/`, `BundleProgram` = `Contents/MacOS/SFHelper`, one Mach
/// service, signing identifier frozen as `org.siliconforest.installer.helper`. Both ends pin each
/// other's Developer ID with `setConnectionCodeSigningRequirement` (§6.2). Needs a properly signed app.
@objc public protocol SFHelperProtocol {
    func readTopology(reply: @escaping (Data?, Error?) -> Void)
    /// Re-derives the plan as root and compares digests before the first write.
    func begin(plan: Data, signature: Data, reply: @escaping (UUID?, Error?) -> Void)
    func resume(jobID: UUID, reply: @escaping (Error?) -> Void)
    func rollback(jobID: UUID, reply: @escaping (Error?) -> Void)
    func beginRemoval(ticket: Data, reply: @escaping (UUID?, Error?) -> Void)
    /// Kept in memory, sent on stdin, then wiped.
    func authorizeBless(password: Data, reply: @escaping (Error?) -> Void)
    /// Journal tail.
    func events(after sequence: UInt64, reply: @escaping (Data?, Error?) -> Void)
    func exportDiagnostics(to handle: FileHandle, reply: @escaping (Error?) -> Void)
}

public enum HelperIdentity {
    public static let signingIdentifier = "org.siliconforest.installer.helper"
    public static let launchdPlist = "org.siliconforest.installer.helper.plist"
    public static let machService = "org.siliconforest.installer.helper"
}
