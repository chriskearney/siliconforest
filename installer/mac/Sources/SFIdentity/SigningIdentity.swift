import Foundation

/// Who signs what (DESIGN §6.1, §6.2, §11). The ONE place the team ID lives: the app, the helper
/// and the recovery binary all pin each other through these strings.
///
/// Developer ID signing is pending Chris's go. Every build so far is ad hoc (`codesign -s -`), which
/// does not satisfy these requirements; the in-process XPC tests pin the test binary's own ad hoc
/// requirement instead, and prove the Developer ID requirement rejects it.
public enum SigningIdentity {
    /// Chris Kearney's Developer ID team.
    public static let teamID = "Z642ZK8JK4"

    /// Frozen forever (§6.1): changing one orphans installed helpers.
    public static let appIdentifier = "org.siliconforest.installer"
    public static let helperIdentifier = "org.siliconforest.installer.helper"
    public static let recoveryIdentifier = "org.siliconforest.recovery"

    public static let helperMachService = "org.siliconforest.installer.helper"
    public static let helperLaunchdPlist = "org.siliconforest.installer.helper.plist"

    /// The designated requirement for a Developer ID Application signature with our team (§6.2).
    public static func developerIDRequirement(identifier: String, team: String = teamID) -> String {
        """
        anchor apple generic and identifier "\(identifier)" and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ \
        and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = "\(team)"
        """
    }

    /// What the helper requires of its client (the app).
    public static var appRequirement: String { developerIDRequirement(identifier: appIdentifier) }
    /// What the app requires of the helper it talks to.
    public static var helperRequirement: String { developerIDRequirement(identifier: helperIdentifier) }
    /// What the helper checks on the SFRecovery binary before staging it on the stub.
    public static var recoveryRequirement: String { developerIDRequirement(identifier: recoveryIdentifier) }
}
