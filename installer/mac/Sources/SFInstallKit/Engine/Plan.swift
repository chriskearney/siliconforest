import Foundation

/// D5: start SiliconForest once and keep macOS as the default, or make SiliconForest the default
/// only after it has started successfully.
public enum AfterSetup: String, Codable, Sendable, CaseIterable {
    case startOnceKeepMacOS
    case makeDefaultAfterSuccess
}

public struct InstallOptions: Codable, Sendable, Hashable {
    /// Total SiliconForest footprint: stub + SFBOOT + root.
    public var siliconForestSize: Int64
    /// Name at startup (the stub volume's name in the startup picker).
    public var installName: String
    public var afterSetup: AfterSetup
    public var channel: String
    public var keepDownloads: Bool

    public init(siliconForestSize: Int64, installName: String = "SiliconForest", afterSetup: AfterSetup = .startOnceKeepMacOS,
                channel: String = "Stable", keepDownloads: Bool = false) {
        self.siliconForestSize = siliconForestSize; self.installName = installName; self.afterSetup = afterSetup
        self.channel = channel; self.keepDownloads = keepDownloads
    }

    /// The startup picker truncates long names; APFS volume names have a restricted character set.
    public static func validate(name: String) -> String? {
        let t = name.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return "empty" }
        if t.count > 28 { return "long" }
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: " -_."))
        if t.unicodeScalars.contains(where: { !allowed.contains($0) }) { return "characters" }
        return nil
    }
}

public enum StepID: String, Codable, Sendable, CaseIterable {
    // install (ENGINE.md §7 state codes in `InstallStep.code`)
    case fetch, verifyDownloads, resize, stubPartition, stubFiles, bootPartition, rootPartition, rootImage, readBack,
         bootFiles, firmware, finalPreparations
    // removal (DESIGN.md §8.4)
    case setMacOSStartup, removeSiliconForest, returnSpace, checkResult
}

/// The named phases people see (UX-FLOW §8, §9 and U3). Steps map onto them.
public enum Phase: String, Codable, Sendable, CaseIterable {
    case downloading, verifying
    case makingRoom, startupVolume, writing, checking, drivers, finalPreparations
    case removalStartup, removalRemove, removalReturn, removalCheck

    public var isPreparing: Bool { self == .downloading || self == .verifying }
}

public struct InstallStep: Codable, Sendable, Hashable, Identifiable {
    public var id: StepID
    /// ENGINE.md state code ("S25").
    public var code: String
    public var phase: Phase
    public var title: String
    public var operations: [DiskOperation]
    /// Undoes this step. Empty when nothing is left behind or a later undo covers it.
    public var undo: [DiskOperation]
    public var weight: Double
    public var estimatedSeconds: Double
    public var reversible: Bool
    /// False while a step can't be safely interrupted (the resize, the startup change): no Cancel.
    public var interruptible: Bool
}

public struct InstallPlan: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable { case install, uninstall }

    public var kind: Kind
    public var profileID: String
    public var releaseVersion: String
    public var options: InstallOptions
    public var disk: String
    public var macOSPartition: String
    public var macOSSizeBefore: Int64
    public var macOSSizeAfter: Int64
    public var macOSFreeAfter: Int64
    public var stubSize: Int64
    public var bootSize: Int64
    public var rootSize: Int64
    public var downloadReleaseBytes: Int64
    public var downloadAppleBytes: Int64
    public var steps: [InstallStep]

    public var siliconForestSize: Int64 { stubSize + bootSize + rootSize }
    public var estimatedSeconds: Double { steps.reduce(0) { $0 + $1.estimatedSeconds } }
    /// Every command the plan would run, in order ("Show What Would Happen").
    public var allCommands: [[String]] { steps.flatMap { $0.operations.flatMap { $0.commands() } } }
    /// Index of the first step that writes to the disk; everything before it leaves the disk untouched.
    public var firstWriteIndex: Int { steps.firstIndex { $0.operations.contains(where: \.isMutating) } ?? steps.count }
    public var phases: [Phase] { steps.reduce(into: [Phase]()) { if !$0.contains($1.phase) { $0.append($1.phase) } } }
}

public enum PlanError: Error, LocalizedError, Equatable {
    case noMacOSContainer
    case notEnoughSpace(needed: Int64, available: Int64)
    case sizeOutOfRange(min: Int64, max: Int64)
    case invalidName(String)
    case notOurs(String)

    public var errorDescription: String? {
        switch self {
        case .noMacOSContainer: return "The macOS container wasn’t found on the internal disk."
        case .notEnoughSpace(let n, let a): return "SiliconForest needs \(Bytes.format(n)); only \(Bytes.format(a)) can be freed."
        case .sizeOutOfRange(let lo, let hi): return "Choose a size between \(Bytes.format(lo)) and \(Bytes.format(hi))."
        case .invalidName(let m): return "Invalid name (\(m))."
        case .notOurs(let why): return "This installation can’t be proved to be ours: \(why)."
        }
    }
}

public enum Planner {
    public static func installPlan(profile: DeviceProfile, snapshot: DiskSnapshot, options: InstallOptions,
                                   release: ReleaseInfo = .placeholder) throws -> InstallPlan {
        guard let disk = snapshot.internalDisk, let c = SizingConstraints(profile: profile, disk: disk, release: release) else {
            throw PlanError.noMacOSContainer
        }
        guard c.isFeasible else { throw PlanError.notEnoughSpace(needed: c.minimum, available: c.maximum) }
        guard options.siliconForestSize >= c.minimum, options.siliconForestSize <= c.maximum else {
            throw PlanError.sizeOutOfRange(min: c.minimum, max: c.maximum)
        }
        if let problem = InstallOptions.validate(name: options.installName) { throw PlanError.invalidName(problem) }

        let part = profile.partitioning
        let align = max(part.alignmentBytes, 4096)
        let mac = c.macOSPartition
        let newMacSize = Bytes.alignDown(c.macOSSize(for: options.siliconForestSize), to: align)
        let stub = part.stubContainerBytes, boot = part.bootPartition.bytes
        let root = Bytes.alignDown(options.siliconForestSize - stub - boot, to: align)
        let name = options.installName.trimmingCharacters(in: .whitespaces)
        let installID = String(UUID().uuidString.prefix(8))
        let stamp: [String: String] = ["sf.installName": name, "sf.profile": profile.id, "sf.installID": installID,
                                       "sf.version": release.version]
        let stubVersion = profile.support.preferredStubFirmware ?? "13.5"
        let appleBytes = profile.support.stubDownloadBytes ?? 720_000_000
        let fw = profile.firmware.map(\.summary)

        func step(_ id: StepID, _ code: String, _ phase: Phase, _ title: String, ops: [DiskOperation], undo: [DiskOperation] = [],
                  weight: Double, seconds: Double, interruptible: Bool = true) -> InstallStep {
            InstallStep(id: id, code: code, phase: phase, title: title, operations: ops, undo: undo, weight: weight,
                        estimatedSeconds: seconds, reversible: true, interruptible: interruptible)
        }

        let steps: [InstallStep] = [
            // Before the first write (D6): fetch and verify everything.
            step(.fetch, "S10", .downloading, "Download SiliconForest \(release.version) and Apple’s startup files",
                 ops: [.download(item: "siliconforest-\(release.version)-\(profile.id).tar", url: "https://<channel>/siliconforest/\(release.version)/\(profile.id)", bytes: release.downloadBytes),
                       .download(item: "startup files (macOS \(stubVersion))", url: profile.support.stubRestoreImageURL ?? "https://updates.cdn-apple.com/…", bytes: appleBytes)],
                 weight: 10, seconds: 240),
            step(.verifyDownloads, "S15", .verifying, "Check every file",
                 ops: [.checkFiles(label: "SiliconForest \(release.version) and startup files", bytes: release.downloadBytes + appleBytes)],
                 weight: 2, seconds: 30),
            // First disk write below this line.
            step(.resize, "S25", .makingRoom, "Shrink macOS",
                 ops: [.resizeContainer(partition: mac.identifier, newSize: newMacSize)],
                 undo: [.resizeContainer(partition: mac.identifier, newSize: 0)], weight: 16, seconds: 180, interruptible: false),
            step(.stubPartition, "S30", .startupVolume, "Create the startup volume",
                 ops: [.addPartition(after: mac.identifier, slot: "stub", content: .appleAPFS, name: name, size: stub,
                                     metadata: stamp.merging(["sf.role": "stub"]) { a, _ in a })],
                 undo: [.deleteAPFSContainer("@stub")], weight: 3, seconds: 15),
            step(.stubFiles, "S35", .startupVolume, "Install Apple’s startup files (macOS \(stubVersion))",
                 ops: [.writeFiles(target: "@stub", label: "startup files", items: ["System (boot firmware)", "Preboot", "Recovery (paired recoveryOS)"], bytes: appleBytes)],
                 weight: 12, seconds: 120),
            step(.bootPartition, "S40", .writing, "Create \(part.bootPartition.name)",
                 ops: [.addPartition(after: "@stub", slot: "boot", content: .efi, name: part.bootPartition.name, size: boot,
                                     metadata: stamp.merging(["sf.role": "boot"]) { a, _ in a })],
                 undo: [.deletePartition("@boot")], weight: 2, seconds: 8),
            step(.rootPartition, "S45", .writing, "Create the SiliconForest partition",
                 ops: [.addPartition(after: "@boot", slot: "root", content: .linuxFilesystem, name: "SF root", size: root,
                                     metadata: stamp.merging(["sf.role": "root"]) { a, _ in a })],
                 undo: [.deletePartition("@root")], weight: 2, seconds: 8),
            step(.rootImage, "S47", .writing, "Write SiliconForest",
                 ops: [.writeImage(target: "@root", image: "siliconforest-\(release.version)-root.img", bytes: release.rootImageBytes)],
                 weight: 26, seconds: 360),
            step(.readBack, "S47", .checking, "Check what was written",
                 ops: [.verify(target: "@root", label: "SiliconForest", bytes: release.rootImageBytes)],
                 weight: 10, seconds: 120),
            // Personalised after the root exists: the kernel writes only inside the root named on its command line.
            step(.bootFiles, "S42", .drivers, "Personalise the kernel for this Mac",
                 ops: [.writeFiles(target: "@boot", label: "stage 2 and kernel", items: [profile.kernel.stage2, profile.kernel.collection, "sf/install.json"], bytes: 96 * Bytes.mb)],
                 weight: 3, seconds: 20),
            step(.firmware, "S50", .drivers, fw.isEmpty ? "Add firmware for this Mac" : "Add \(fw.joined(separator: " and ")) firmware",
                 ops: [.writeFiles(target: "@root", label: "firmware slot and boot receipt slot", items: profile.firmware.map(\.destination) + ["receipt slot"], bytes: 32 * Bytes.mib)],
                 weight: 3, seconds: 20),
            step(.finalPreparations, "S55–S68", .finalPreparations, "Stage the Recovery step and set the next startup",
                 ops: [.writeFiles(target: "@stub", label: "stage 1 and SiliconForest Setup", items: [profile.kernel.stage1, "SiliconForest Setup.app", "SFInstall/plan.json"], bytes: 40 * Bytes.mb),
                       .bless(target: "@stub", label: name, nextOnly: true)],
                 // Undo restores the previous default, whichever OS it was (ENGINE §7, S65).
                 undo: [.bless(target: mac.identifier, label: "the previous startup system", nextOnly: false)], weight: 4, seconds: 25, interruptible: false),
        ]

        return InstallPlan(kind: .install, profileID: profile.id, releaseVersion: release.version, options: options, disk: disk.identifier,
                           macOSPartition: mac.identifier, macOSSizeBefore: mac.size, macOSSizeAfter: newMacSize,
                           macOSFreeAfter: max(0, newMacSize - c.macOSUsed), stubSize: stub, bootSize: boot, rootSize: root,
                           downloadReleaseBytes: release.downloadBytes, downloadAppleBytes: appleBytes, steps: steps)
    }

    /// Removes one install and gives its space back to macOS (DESIGN.md §8.4): make macOS the
    /// startup disk and verify it first, then delete stub, SFBOOT and root, regrow, and check.
    public static func uninstallPlan(install: SiliconForestInstall, snapshot: DiskSnapshot, profileID: String = "J293") throws -> InstallPlan {
        guard install.isOwned else { throw PlanError.notOurs(install.unprovenReason ?? "unknown") }
        guard let disk = snapshot.internalDisk, let mac = disk.macOSPartition else { throw PlanError.noMacOSContainer }
        let last = install.partitions.last
        let first = install.partitions.first
        // Everything from the first partition to the next one after the last (gaps included).
        let reclaim = install.reclaimableBytes(on: disk)
        _ = last
        let contiguous: Bool = {
            guard let i = disk.partitions.firstIndex(where: { $0.identifier == mac.identifier }), let first else { return false }
            return i + 1 < disk.partitions.count && disk.partitions[i + 1].identifier == first.identifier
        }()
        let macAfter = contiguous ? mac.size + disk.freeAfter(mac.identifier) + reclaim : mac.size

        var remove: [DiskOperation] = []
        if let s = install.stub { remove.append(.deleteAPFSContainer(s.identifier)) }
        if let b = install.boot { remove.append(.deletePartition(b.identifier)) }
        if let r = install.root { remove.append(.deletePartition(r.identifier)) }

        var steps: [InstallStep] = [
            InstallStep(id: .setMacOSStartup, code: "U10", phase: .removalStartup, title: "Make macOS the startup disk",
                        operations: [.bless(target: mac.identifier, label: "macOS", nextOnly: false)], undo: [],
                        weight: 2, estimatedSeconds: 8, reversible: true, interruptible: true),
            InstallStep(id: .removeSiliconForest, code: "U20", phase: .removalRemove, title: "Remove SiliconForest",
                        operations: remove, undo: [], weight: 6, estimatedSeconds: 20, reversible: false, interruptible: false),
        ]
        if contiguous {
            steps.append(InstallStep(id: .returnSpace, code: "U30", phase: .removalReturn, title: "Return the space to macOS",
                                     operations: [.resizeContainer(partition: mac.identifier, newSize: 0)], undo: [],
                                     weight: 12, estimatedSeconds: 90, reversible: false, interruptible: false))
        }
        steps.append(InstallStep(id: .checkResult, code: "U40", phase: .removalCheck, title: "Check the result",
                                 operations: [.checkFiles(label: "partition table against the one saved before installing", bytes: 1 * Bytes.mb)],
                                 undo: [], weight: 1, estimatedSeconds: 3, reversible: true, interruptible: true))

        return InstallPlan(kind: .uninstall, profileID: profileID, releaseVersion: install.version ?? "?",
                           options: InstallOptions(siliconForestSize: install.totalBytes, installName: install.name),
                           disk: disk.identifier, macOSPartition: mac.identifier, macOSSizeBefore: mac.size, macOSSizeAfter: macAfter,
                           macOSFreeAfter: max(0, macAfter - (mac.container?.capacityUsed ?? 0)),
                           stubSize: install.stub?.size ?? 0, bootSize: install.boot?.size ?? 0, rootSize: install.root?.size ?? 0,
                           downloadReleaseBytes: 0, downloadAppleBytes: 0, steps: steps)
    }
}
