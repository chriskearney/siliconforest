import Foundation

/// One row of the live checklist (UX-FLOW §2). The engine returns facts; SFCopy turns them into words.
public struct CompatibilityCheck: Sendable, Hashable, Identifiable {
    public enum Status: String, Sendable { case pass, warning, fail, info }
    public enum Kind: String, Sendable, CaseIterable {
        case thisMac, macOS, firmware, account, fileVault, disk, freeSpace, power, internet
    }

    public var kind: Kind
    public var status: Status
    public var finding: Finding
    public var id: Kind { kind }
}

public enum Finding: Sendable, Hashable {
    case supportedMac(String)
    case unsupportedMac(this: String, supported: String)
    case macOSSupported(String)
    case macOSTooOld(have: String, need: String)
    case macOSBlocked(major: Int, reason: String)
    case macOSUntested(have: String, newestTested: Int)
    /// A required target still behind its gate: refused in release builds, allowed in dry runs.
    case macOSGated(major: Int, gate: String, reason: String)
    case macOSUnknown
    case firmwareCurrent
    case firmwareOld(have: String, need: String)
    case firmwareUnknown
    case admin(String)
    case notAdmin(String)
    case fileVaultOn, fileVaultOff
    case fileVaultConverting(percent: Int?)
    case fileVaultUnknown
    case diskHealthy(Int64)
    case diskNonStandard
    case lockedVolume(String)
    case enoughSpace(available: Int64)
    case notEnoughSpace(needed: Int64, reserve: Int64, shortfall: Int64)
    case noMacOSContainer
    case powerConnected
    case onBattery(percent: Int?)
    case internetConnected
    case internetOffline
    case internetNotChecked
}

/// What the app should open on, from the disk and the journal (UX-FLOW §2, blocked variants).
public enum EntryState: Sendable, Hashable {
    case fresh
    case installed(SiliconForestInstall)
    case handMade(SiliconForestInstall)
    case unfinished(stepTitle: String)
    case awaitingRecovery
}

public enum CompatibilityChecker {
    /// The checks, in the order the UI reveals them.
    /// `allowGatedMajors`: dev builds and dry runs may pass a gated major (D11); release builds refuse it.
    public static func run(facts: SystemFacts, snapshot: DiskSnapshot, profile: DeviceProfile?,
                           release: ReleaseInfo = .placeholder, allowGatedMajors: Bool = false) -> [CompatibilityCheck] {
        var out: [CompatibilityCheck] = []
        func add(_ k: CompatibilityCheck.Kind, _ s: CompatibilityCheck.Status, _ f: Finding) { out.append(.init(kind: k, status: s, finding: f)) }

        // This Mac
        if let profile, profile.matches(hwModel: facts.hwModel, board: facts.board) {
            add(.thisMac, .pass, .supportedMac(profile.marketingName))
        } else {
            let this = [facts.chipName, facts.hwModel].compactMap { $0 }.joined(separator: ", ")
            add(.thisMac, .fail, .unsupportedMac(this: this.isEmpty ? "This Mac" : this, supported: "MacBook Pro (13-inch, M1, 2020)"))
        }

        // macOS: within the profile's range (D11 blocks untested new majors)
        let minimum = profile?.support.minMacOS ?? "13.5"
        if let v = facts.macOSVersion {
            let major = OSVersion(v).parts.first ?? 0
            if OSVersion(v) < OSVersion(minimum) {
                add(.macOS, .fail, .macOSTooOld(have: v, need: minimum))
            } else if let b = profile?.support.blockedMajors.first(where: { $0.major == major }) {
                add(.macOS, .fail, .macOSBlocked(major: b.major, reason: b.reason))
            } else if let g = profile?.support.gatedMajors.first(where: { $0.major == major && !$0.passed }) {
                add(.macOS, allowGatedMajors ? .warning : .fail,
                    allowGatedMajors ? .macOSGated(major: g.major, gate: g.gate, reason: g.reason) : .macOSBlocked(major: g.major, reason: g.reason))
            } else if let max = profile?.support.maximumTestedMajor, major > max {
                add(.macOS, .fail, .macOSBlocked(major: major, reason: "Not tested yet."))
            } else {
                add(.macOS, .pass, .macOSSupported(v))
            }
        } else {
            add(.macOS, .warning, .macOSUnknown)
        }

        // Startup firmware at least the stub's minimum iBoot
        if let have = facts.systemFirmware, let need = profile?.support.minimumIBoot {
            add(.firmware, iBootAtLeast(have, need) ? .pass : .fail, iBootAtLeast(have, need) ? .firmwareCurrent : .firmwareOld(have: have, need: need))
        } else if facts.systemFirmware != nil {
            add(.firmware, .pass, .firmwareCurrent)
        } else {
            add(.firmware, .warning, .firmwareUnknown)
        }

        // Account
        let user = facts.userFullName ?? facts.userName ?? "You"
        if facts.isAdmin == false { add(.account, .fail, .notAdmin(user)) } else { add(.account, .pass, .admin(user)) }

        // FileVault
        switch facts.fileVault {
        case .on: add(.fileVault, .pass, .fileVaultOn)
        case .off: add(.fileVault, .pass, .fileVaultOff)
        case .encrypting, .decrypting: add(.fileVault, .fail, .fileVaultConverting(percent: facts.fileVaultPercent))
        case .unknown: add(.fileVault, .warning, .fileVaultUnknown)
        }

        // Disk layout and locked volumes
        let disk = snapshot.internalDisk
        if let disk, disk.hasStandardAppleLayout {
            if let locked = disk.macOSPartition?.container?.volumes.first(where: \.locked) {
                add(.disk, .fail, .lockedVolume(locked.name))
            } else {
                add(.disk, .pass, .diskHealthy(disk.size))
            }
        } else {
            add(.disk, .fail, .diskNonStandard)
        }

        // Free space (ENGINE §4)
        if let disk, let profile, let c = SizingConstraints(profile: profile, disk: disk, release: release) {
            if c.isFeasible {
                add(.freeSpace, .pass, .enoughSpace(available: c.maximum))
            } else {
                add(.freeSpace, .fail, .notEnoughSpace(needed: c.minimum, reserve: c.reserve, shortfall: c.shortfall))
            }
        } else if let mac = disk?.macOSPartition?.container {
            add(.freeSpace, .info, .enoughSpace(available: mac.capacityFree))
        } else {
            add(.freeSpace, .fail, .noMacOSContainer)
        }

        // Power: AC required (ENGINE §2 blocks Install until connected)
        add(.power, facts.power.onACPower ? .pass : .fail, facts.power.onACPower ? .powerConnected : .onBattery(percent: facts.power.batteryPercent))

        // Internet
        switch facts.internet {
        case true?: add(.internet, .pass, .internetConnected)
        case false?: add(.internet, .fail, .internetOffline)
        case nil: add(.internet, .info, .internetNotChecked)
        }
        return out
    }

    public static func canProceed(_ checks: [CompatibilityCheck]) -> Bool { !checks.contains { $0.status == .fail } }

    /// The first blocking finding decides the headline.
    public static func blocker(_ checks: [CompatibilityCheck]) -> Finding? { checks.first { $0.status == .fail }?.finding }

    public static func entryState(snapshot: DiskSnapshot, journal: JournalState?) -> EntryState {
        if let j = journal, j.isInterrupted, let plan = j.plan {
            if j.checkpoint.completed.contains(.finalPreparations) { return .awaitingRecovery }
            let i = j.resumeIndex
            return .unfinished(stepTitle: i < plan.steps.count ? plan.steps[i].title : "")
        }
        let installs = snapshot.siliconForestInstalls
        if let hand = installs.first(where: { !$0.isOwned }) { return .handMade(hand) }
        if let owned = installs.first(where: \.isOwned) { return .installed(owned) }
        return .fresh
    }

    /// "iBoot-8422.141.2" style comparison.
    static func iBootAtLeast(_ have: String, _ need: String) -> Bool {
        func nums(_ s: String) -> String { String(s.drop { !$0.isNumber }) }
        return OSVersion(nums(have)) >= OSVersion(nums(need))
    }
}
