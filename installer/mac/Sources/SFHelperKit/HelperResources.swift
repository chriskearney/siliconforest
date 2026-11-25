import Foundation
import SFInstallKit
import SFEngine
import SFLiveDisk
import SFStub

/// What the shipped helper builds the stub from (preview6): the app bundle's profile and icon, Apple's
/// 13.5 restore image by range from the profile's CDN URL, and this Mac's own admin list.
public enum HelperResources {
    /// macOS's `AdminUserRecoveryInfo.plist` in the Preboot volume of the startup volume group.
    public static func adminUsersPlist(query: ToolRunner = ProcessToolRunner()) throws -> URL {
        let info = try Query.dict(query, ["/usr/sbin/diskutil", "info", "-plist", try StartupDisk.rootVolume()])
        guard let group = info["APFSVolumeGroupID"] as? String else { throw SafetyRefusal("the startup volume has no volume group") }
        return URL(fileURLWithPath: "/System/Volumes/Preboot/\(group.uppercased())/var/db/AdminUserRecoveryInfo.plist")
    }

    public static func stubSource(profileID: String, resources: URL, adminUsers: URL? = nil, restoreImage: String? = nil,
                                  profileURL: URL? = nil, icon: URL? = nil) throws -> StubSource {
        let profileURL = profileURL ?? resources.appendingPathComponent("Profiles/\(profileID).json")
        return StubSource(profile: try StubProfile.load(profile: profileURL), restoreImage: restoreImage,
                          adminUsers: try adminUsers ?? adminUsersPlist(),
                          volumeIcon: icon ?? resources.appendingPathComponent("AppIcon.icns"), rootOnly: geteuid() == 0)
    }
}
