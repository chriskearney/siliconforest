import Foundation

public struct CompatibilityCheck: Sendable, Hashable, Identifiable {
    public enum Status: String, Sendable { case pass, warning, fail, info }
    public enum Kind: String, Sendable, CaseIterable {
        case model, macOS, fileVault, freeSpace, startupSecurity, power, existingInstall
    }

    public var kind: Kind
    public var title: String
    public var status: Status
    /// One line under the title.
    public var detail: String
    /// The value at the right of the row ("MacBookPro17,1", "212 GB free").
    public var value: String

    public var id: Kind { kind }
    public var symbol: String {
        switch kind {
        case .model: return "laptopcomputer"
        case .macOS: return "apple.terminal"
        case .fileVault: return "lock.shield"
        case .freeSpace: return "internaldrive"
        case .startupSecurity: return "checkmark.shield"
        case .power: return "bolt.batteryblock"
        case .existingInstall: return "tree"
        }
    }
}

public enum CompatibilityChecker {
    /// The checks, in the order the UI reveals them.
    public static func run(facts: SystemFacts, snapshot: DiskSnapshot, profile: DeviceProfile?) -> [CompatibilityCheck] {
        var out: [CompatibilityCheck] = []

        // Model
        let modelText = [facts.hwModel, facts.board].compactMap { $0 }.joined(separator: " · ")
        if let profile, profile.matches(hwModel: facts.hwModel, board: facts.board) {
            out.append(.init(kind: .model, title: "Supported Mac", status: .pass,
                             detail: "\(profile.marketingName) · \(profile.soc.name) (\(profile.soc.id))",
                             value: facts.hwModel ?? profile.id))
        } else {
            out.append(.init(kind: .model, title: "Mac model", status: .fail,
                             detail: "This Mac\(modelText.isEmpty ? "" : " (\(modelText))") isn’t supported yet. SiliconForest starts with the 13-inch MacBook Pro with M1.",
                             value: facts.chipName ?? facts.hwModel ?? "Unknown"))
        }

        // macOS
        let minimum = profile?.support.minMacOS ?? "12.3"
        if let v = facts.macOSVersion {
            let ok = OSVersion(v) >= OSVersion(minimum)
            out.append(.init(kind: .macOS, title: MacOSName.name(for: v), status: ok ? .pass : .fail,
                             detail: ok ? "Version \(v)\(facts.macOSBuild.map { " (\($0))" } ?? "") · \(minimum) or later is required"
                                        : "Update to macOS \(minimum) or later in System Settings → General → Software Update.",
                             value: v))
        } else {
            out.append(.init(kind: .macOS, title: "macOS version", status: .warning, detail: "Couldn’t read the macOS version.", value: "—"))
        }

        // FileVault
        switch facts.fileVault {
        case .on:
            out.append(.init(kind: .fileVault, title: "FileVault is on", status: .pass,
                             detail: "Fine to leave on. You’ll unlock macOS once during the recoveryOS step.", value: "On"))
        case .off:
            out.append(.init(kind: .fileVault, title: "FileVault is off", status: .pass,
                             detail: "Nothing to do. SiliconForest doesn’t touch FileVault.", value: "Off"))
        case .encrypting, .decrypting:
            out.append(.init(kind: .fileVault, title: "FileVault is busy", status: .fail,
                             detail: "Wait for FileVault to finish \(facts.fileVault == .encrypting ? "encrypting" : "decrypting") before resizing the disk.", value: "In progress"))
        case .unknown:
            out.append(.init(kind: .fileVault, title: "FileVault", status: .warning, detail: "Couldn’t read the FileVault state.", value: "Unknown"))
        }

        // Free space
        if let disk = snapshot.internalDisk, let mac = disk.macOSPartition, let container = mac.container, let profile {
            let need = profile.minimumFootprint + profile.partitioning.macOSMinFreeBytes
            let available = container.capacityFree + disk.freeAfter(mac.identifier)
            let ok = available >= need
            out.append(.init(kind: .freeSpace, title: ok ? "Enough free space" : "Not enough free space", status: ok ? .pass : .fail,
                             detail: ok ? "SiliconForest needs at least \(Bytes.format(profile.minimumFootprint)), and macOS keeps \(Bytes.format(profile.partitioning.macOSMinFreeBytes)) free."
                                        : "Free up at least \(Bytes.format(need - available)) in macOS, then check again.",
                             value: "\(Bytes.format(available)) free"))
        } else {
            out.append(.init(kind: .freeSpace, title: "Free space", status: .fail, detail: "Couldn’t find the macOS container on the internal disk.", value: "—"))
        }

        // Startup security (SIP + boot policy)
        let sipText: String
        switch facts.sip {
        case .enabled: sipText = "SIP on"
        case .disabled: sipText = "SIP off"
        case .custom: sipText = "SIP custom"
        case .unknown: sipText = "SIP unknown"
        }
        out.append(.init(kind: .startupSecurity, title: "Startup security", status: facts.sip == .unknown ? .warning : .pass,
                         detail: "macOS keeps Full Security. SiliconForest gets its own Permissive policy, set in recoveryOS.",
                         value: sipText))

        // Power
        let p = facts.power
        if p.onACPower {
            out.append(.init(kind: .power, title: "Connected to power", status: .pass,
                             detail: "Keep the charger connected until the installer finishes.", value: p.batteryPercent.map { "\($0)%" } ?? "AC"))
        } else if let pct = p.batteryPercent, pct >= 50 {
            out.append(.init(kind: .power, title: "On battery", status: .warning,
                             detail: "Connect the charger before you install. Resizing must not be interrupted.", value: "\(pct)%"))
        } else {
            out.append(.init(kind: .power, title: "Battery low", status: .fail,
                             detail: "Connect the charger. The installer won’t resize the disk on a low battery.", value: p.batteryPercent.map { "\($0)%" } ?? "—"))
        }

        // Existing installs
        let existing = snapshot.siliconForestInstalls
        if !existing.isEmpty {
            out.append(.init(kind: .existingInstall, title: existing.count == 1 ? "SiliconForest is already installed" : "\(existing.count) SiliconForest installs found",
                             status: .info,
                             detail: "You can add another install, or manage the existing one from the Welcome screen.",
                             value: existing.map(\.name).joined(separator: ", ")))
        }
        return out
    }

    public static func canProceed(_ checks: [CompatibilityCheck]) -> Bool {
        !checks.contains { $0.status == .fail }
    }
}
