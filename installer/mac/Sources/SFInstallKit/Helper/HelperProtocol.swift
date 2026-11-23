import Foundation
import SFIdentity

/// Names the app and the helper share. The XPC protocol itself lives in SFHelperKit
/// (`SFHelperXPC`: verbs only, never "run this command"); identities in SFIdentity.
public enum HelperIdentity {
    public static let signingIdentifier = SigningIdentity.helperIdentifier
    public static let launchdPlist = SigningIdentity.helperLaunchdPlist
    public static let machService = SigningIdentity.helperMachService
}
