import Foundation

/// What the installer learns about the running Mac before it plans anything.
public struct SystemFacts: Codable, Sendable, Hashable {
    /// `sysctl hw.model`, e.g. "MacBookPro17,1".
    public var hwModel: String?
    /// `sysctl hw.target`, e.g. "J293AP".
    public var board: String?
    /// `machdep.cpu.brand_string`, e.g. "Apple M1".
    public var chipName: String?
    public var macOSVersion: String?
    public var macOSBuild: String?
    public var fileVault: FileVaultState
    public var sip: SIPState
    /// Startup security of the running macOS, when it can be read without privileges (it usually
    /// cannot: `bputil -d` needs root). SiliconForest's own policy is set in recoveryOS.
    public var bootPolicy: String?
    public var power: PowerState
    public var userName: String?
    public var userFullName: String?
    public var isAdmin: Bool?
    /// IODeviceTree `system-firmware-version`, e.g. "iBoot-11881.140.96".
    public var systemFirmware: String?
    public var fileVaultPercent: Int?
    /// nil = not checked (read-only mode checks it just before downloading).
    public var internet: Bool?
    /// The system the Mac starts today (recorded so the install restores it, whichever OS it is).
    public var startupSystem: String?

    public init(hwModel: String? = nil, board: String? = nil, chipName: String? = nil, macOSVersion: String? = nil,
                macOSBuild: String? = nil, fileVault: FileVaultState = .unknown, sip: SIPState = .unknown,
                bootPolicy: String? = nil, power: PowerState = PowerState(), userName: String? = nil) {
        self.hwModel = hwModel; self.board = board; self.chipName = chipName; self.macOSVersion = macOSVersion
        self.macOSBuild = macOSBuild; self.fileVault = fileVault; self.sip = sip; self.bootPolicy = bootPolicy
        self.power = power; self.userName = userName
    }

    enum CodingKeys: String, CodingKey { case hwModel, board, chipName, macOSVersion, macOSBuild, fileVault, sip, bootPolicy, power, userName, userFullName, isAdmin, systemFirmware, fileVaultPercent, internet, startupSystem }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hwModel = try c.decodeIfPresent(String.self, forKey: .hwModel)
        board = try c.decodeIfPresent(String.self, forKey: .board)
        chipName = try c.decodeIfPresent(String.self, forKey: .chipName)
        macOSVersion = try c.decodeIfPresent(String.self, forKey: .macOSVersion)
        macOSBuild = try c.decodeIfPresent(String.self, forKey: .macOSBuild)
        fileVault = try c.decodeIfPresent(FileVaultState.self, forKey: .fileVault) ?? .unknown
        sip = try c.decodeIfPresent(SIPState.self, forKey: .sip) ?? .unknown
        bootPolicy = try c.decodeIfPresent(String.self, forKey: .bootPolicy)
        power = try c.decodeIfPresent(PowerState.self, forKey: .power) ?? PowerState()
        userName = try c.decodeIfPresent(String.self, forKey: .userName)
        userFullName = try c.decodeIfPresent(String.self, forKey: .userFullName)
        isAdmin = try c.decodeIfPresent(Bool.self, forKey: .isAdmin)
        systemFirmware = try c.decodeIfPresent(String.self, forKey: .systemFirmware)
        fileVaultPercent = try c.decodeIfPresent(Int.self, forKey: .fileVaultPercent)
        internet = try c.decodeIfPresent(Bool.self, forKey: .internet)
        startupSystem = try c.decodeIfPresent(String.self, forKey: .startupSystem)
    }
}

public enum FileVaultState: String, Codable, Sendable { case on, off, encrypting, decrypting, unknown }
public enum SIPState: String, Codable, Sendable { case enabled, disabled, custom, unknown }

public struct PowerState: Codable, Sendable, Hashable {
    public var onACPower: Bool
    public var batteryPercent: Int?
    public var charging: Bool
    public init(onACPower: Bool = true, batteryPercent: Int? = nil, charging: Bool = false) {
        self.onACPower = onACPower; self.batteryPercent = batteryPercent; self.charging = charging
    }
}

/// Semantic version compare for "12.3", "13.5.1", "26.5.2".
public struct OSVersion: Comparable, CustomStringConvertible, Sendable {
    public var parts: [Int]
    public init(_ s: String) { parts = s.split(separator: ".").map { Int($0) ?? 0 } }
    public static func < (a: OSVersion, b: OSVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }
    public static func == (a: OSVersion, b: OSVersion) -> Bool { !(a < b) && !(b < a) }
    public var description: String { parts.map(String.init).joined(separator: ".") }
}

/// macOS marketing name for a version, for friendlier copy.
public enum MacOSName {
    public static func name(for version: String) -> String {
        let major = OSVersion(version).parts.first ?? 0
        switch major {
        case 11: return "macOS Big Sur"
        case 12: return "macOS Monterey"
        case 13: return "macOS Ventura"
        case 14: return "macOS Sonoma"
        case 15: return "macOS Sequoia"
        case 26: return "macOS Tahoe"
        default: return "macOS"
        }
    }
}
