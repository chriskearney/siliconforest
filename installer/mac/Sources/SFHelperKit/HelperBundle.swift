import Foundation
import ServiceManagement
import Security
import SFIdentity

/// Where the helper lives in the app and how it is registered (DESIGN §6.1).
///
/// ```
/// SiliconForest Installer.app/Contents/
///   MacOS/SiliconForest Installer        the app (org.siliconforest.installer)
///   MacOS/SFHelper                       the helper (org.siliconforest.installer.helper; Info.plist in __TEXT,__info_plist)
///   Library/LaunchDaemons/org.siliconforest.installer.helper.plist
///   Helpers/SFRecovery                   staged onto the stub for recoveryOS
///   Resources/RecoveryPayload/           sf-launcher, sf-step2.sh
/// ```
///
/// Registration path (not run in this build; it would prompt the person at the console):
/// 1. After Review, the app calls `SMAppService.daemon(plistName:).register()`.
/// 2. `.requiresApproval`: the app explains, then `SMAppService.openSystemSettingsLoginItems()`;
///    the person turns the helper on in System Settings → General → Login Items.
/// 3. `.enabled`: the app connects to the Mach service with `HelperClient()`; launchd starts the helper.
/// 4. When the job ends, `unregister()`. The journal stays in `/var/db/org.siliconforest.installer/`.
/// SMAppService accepts only a properly signed app (Developer ID, same team as the helper), so this
/// waits for Developer ID signing, which is pending Chris's go.
public enum HelperBundle {
    public static func launchdPlist() -> [String: Any] {
        [
            "Label": SigningIdentity.helperIdentifier,
            "BundleProgram": "Contents/MacOS/SFHelper",
            "MachServices": [SigningIdentity.helperMachService: true],
            "AssociatedBundleIdentifiers": [SigningIdentity.appIdentifier],
            // Started on demand by a connection; exits when idle (HelperLifecycle).
            "ProcessType": "Interactive",
        ]
    }

    public static func helperInfoPlist(version: String, build: String) -> [String: Any] {
        [
            "CFBundleIdentifier": SigningIdentity.helperIdentifier,
            "CFBundleName": "SFHelper",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build,
            "CFBundleInfoDictionaryVersion": "6.0",
            "SMAuthorizedClients": [SigningIdentity.appRequirement],
        ]
    }

    /// Writes both plists (used by scripts/make-app.sh through `sfinstallctl helper-plists`).
    public static func write(to dir: URL, version: String, build: String) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let l = try PropertyListSerialization.data(fromPropertyList: launchdPlist(), format: .xml, options: 0)
        try l.write(to: dir.appendingPathComponent(SigningIdentity.helperLaunchdPlist))
        let i = try PropertyListSerialization.data(fromPropertyList: helperInfoPlist(version: version, build: build), format: .xml, options: 0)
        try i.write(to: dir.appendingPathComponent("SFHelper-Info.plist"))
    }
}

/// Registers the helper with SMAppService, refusing up front unless this process is the app,
/// running from /Applications, signed with our Developer ID. Nothing in this build calls it.
public enum HelperRegistration {
    public enum Refusal: Error, Equatable { case notInApplications, notDeveloperIDSigned }

    /// Checks only; never touches SMAppService.
    public static func preflight(bundle: Bundle = .main) -> Refusal? {
        guard bundle.bundleURL.path.hasPrefix("/Applications/") else { return .notInApplications }
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return .notDeveloperIDSigned }
        var req: SecRequirement?
        guard SecRequirementCreateWithString(SigningIdentity.appRequirement as CFString, [], &req) == errSecSuccess, let req,
              SecCodeCheckValidity(code, [], req) == errSecSuccess else { return .notDeveloperIDSigned }
        return nil
    }

    @available(macOS 13.0, *)
    public static func register() throws -> SMAppService.Status {
        if let r = preflight() { throw r }
        let service = SMAppService.daemon(plistName: SigningIdentity.helperLaunchdPlist)
        try service.register()
        return service.status
    }

    @available(macOS 13.0, *)
    public static func unregister() throws {
        if let r = preflight() { throw r }
        try SMAppService.daemon(plistName: SigningIdentity.helperLaunchdPlist).unregister()
    }
}
