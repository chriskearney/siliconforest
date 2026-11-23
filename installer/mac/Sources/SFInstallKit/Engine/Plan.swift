import Foundation

public enum BootChoice: String, Codable, Sendable, CaseIterable {
    case macOS, siliconForest
}

public struct InstallOptions: Codable, Sendable, Hashable {
    /// Total SiliconForest footprint: stub + boot + root.
    public var siliconForestSize: Int64
    public var installName: String
    public var defaultBoot: BootChoice
    public var stubFirmware: String?

    public init(siliconForestSize: Int64, installName: String = "SiliconForest", defaultBoot: BootChoice = .macOS, stubFirmware: String? = nil) {
        self.siliconForestSize = siliconForestSize; self.installName = installName
        self.defaultBoot = defaultBoot; self.stubFirmware = stubFirmware
    }

    /// Volume names: letters, digits, spaces, dashes; 1–28 characters (the stub's APFS volume name
    /// shows in the startup picker, which truncates long names).
    public static func validate(name: String) -> String? {
        let t = name.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return "Give the install a name." }
        if t.count > 28 { return "Keep the name to 28 characters or fewer." }
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: " -_."))
        if t.unicodeScalars.contains(where: { !allowed.contains($0) }) { return "Use letters, numbers, spaces and dashes." }
        return nil
    }
}

public enum StepID: String, Codable, Sendable, CaseIterable {
    // install
    case preflight, savePartitionTable, shrinkMacOS, createStub, installStub, createBoot, createRoot,
         extractFirmware, writeSystem, installBootChain, verify, prepareRecovery
    // uninstall
    case removeRoot, removeBoot, removeStub, growMacOS, finishUninstall
}

public struct InstallStep: Codable, Sendable, Hashable, Identifiable {
    public var id: StepID
    public var title: String
    /// Shown while the step runs ("Making room for SiliconForest…").
    public var activeTitle: String
    public var detail: String
    public var operations: [DiskOperation]
    /// Undoes this step. Empty when the step leaves nothing behind, or when a later undo covers it
    /// (files copied into a partition disappear with the partition).
    public var undo: [DiskOperation]
    /// Relative share of the progress bar.
    public var weight: Double
    /// Seconds a real run is expected to take, for the ETA.
    public var estimatedSeconds: Double
    /// Some uninstall steps can't be taken back.
    public var reversible: Bool
}

public struct InstallPlan: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable { case install, uninstall }

    public var kind: Kind
    public var profileID: String
    public var options: InstallOptions
    public var disk: String
    public var macOSPartition: String
    public var macOSSizeBefore: Int64
    public var macOSSizeAfter: Int64
    public var stubSize: Int64
    public var bootSize: Int64
    public var rootSize: Int64
    public var steps: [InstallStep]

    public var siliconForestSize: Int64 { stubSize + bootSize + rootSize }
    public var estimatedSeconds: Double { steps.reduce(0) { $0 + $1.estimatedSeconds } }

    /// Every command the plan would run, in order, for display and for the journal.
    public var allCommands: [[String]] { steps.flatMap { $0.operations.flatMap { $0.commands() } } }
}

public enum PlanError: Error, LocalizedError, Equatable {
    case noMacOSContainer
    case notEnoughSpace(needed: Int64, available: Int64)
    case sizeOutOfRange(min: Int64, max: Int64)
    case invalidName(String)
    case nothingToUninstall

    public var errorDescription: String? {
        switch self {
        case .noMacOSContainer: return "The macOS container wasn’t found on the internal disk."
        case .notEnoughSpace(let n, let a): return "SiliconForest needs \(Bytes.format(n)); only \(Bytes.format(a)) can be freed."
        case .sizeOutOfRange(let lo, let hi): return "Choose a size between \(Bytes.format(lo)) and \(Bytes.format(hi))."
        case .invalidName(let m): return m
        case .nothingToUninstall: return "No SiliconForest install was found."
        }
    }
}

public enum Planner {
    public static func installPlan(profile: DeviceProfile, snapshot: DiskSnapshot, options: InstallOptions) throws -> InstallPlan {
        guard let disk = snapshot.internalDisk, let constraints = SizingConstraints(profile: profile, disk: disk) else {
            throw PlanError.noMacOSContainer
        }
        guard constraints.isFeasible else {
            throw PlanError.notEnoughSpace(needed: constraints.minimum, available: constraints.maximum)
        }
        guard options.siliconForestSize >= constraints.minimum, options.siliconForestSize <= constraints.maximum else {
            throw PlanError.sizeOutOfRange(min: constraints.minimum, max: constraints.maximum)
        }
        if let problem = InstallOptions.validate(name: options.installName) { throw PlanError.invalidName(problem) }

        let part = profile.partitioning
        let align = max(part.alignmentBytes, 4096)
        let mac = constraints.macOSPartition
        let newMacSize = Bytes.alignDown(constraints.macOSSize(for: options.siliconForestSize), to: align)
        let stub = part.stubContainerBytes
        let boot = part.bootPartition.bytes
        // Root takes what's left of the footprint, aligned; any remainder stays free after it.
        let root = Bytes.alignDown(options.siliconForestSize - stub - boot, to: align)
        let name = options.installName.trimmingCharacters(in: .whitespaces)
        let firmware = options.stubFirmware ?? profile.support.preferredStubFirmware ?? profile.support.stubFirmware.last ?? "13.5"
        let stamp: [String: String] = ["sf.installName": name, "sf.profile": profile.id]

        var steps: [InstallStep] = []
        steps.append(.init(id: .preflight, title: "Check your Mac", activeTitle: "Checking your Mac…",
                           detail: "Confirms the disk layout, power and security state still match what you reviewed.",
                           operations: [], undo: [], weight: 1, estimatedSeconds: 4, reversible: true))
        steps.append(.init(id: .savePartitionTable, title: "Save the partition table", activeTitle: "Saving the partition table…",
                           detail: "Records the current layout in the install journal so every later step can be undone.",
                           operations: [], undo: [], weight: 1, estimatedSeconds: 2, reversible: true))
        if newMacSize < mac.size {
            steps.append(.init(id: .shrinkMacOS, title: "Make room on your disk", activeTitle: "Making room for SiliconForest…",
                               detail: "Shrinks the macOS container from \(Bytes.format(mac.size)) to \(Bytes.format(newMacSize)). macOS keeps all of its data.",
                               operations: [.resizeContainer(partition: mac.identifier, newSize: newMacSize)],
                               undo: [.resizeContainer(partition: mac.identifier, newSize: 0)],
                               weight: 14, estimatedSeconds: 150, reversible: true))
        }
        steps.append(.init(id: .createStub, title: "Create the system container", activeTitle: "Creating the system container…",
                           detail: "A small APFS container that holds SiliconForest’s startup files and its own startup security policy.",
                           operations: [.addPartition(after: mac.identifier, slot: "stub", content: .appleAPFS, name: name, size: stub,
                                                      metadata: stamp.merging(["sf.role": "stub", "sf.version": "0.9"]) { a, _ in a })],
                           undo: [.deleteAPFSContainer("@stub")], weight: 4, estimatedSeconds: 12, reversible: true))
        steps.append(.init(id: .installStub, title: "Install startup files", activeTitle: "Installing startup files…",
                           detail: "Downloads the macOS \(firmware) boot objects from Apple and installs them with SiliconForest’s first stage.",
                           operations: [.download(item: "stub-\(firmware).aar", url: "https://updates.cdn-apple.com/<restore image for \(profile.board) \(firmware)>", bytes: 640 * Bytes.mb),
                                        .writeFiles(target: "@stub", label: "startup files", items: ["System/Library/CoreServices/boot.efi.j293.im4p", "usr/standalone/firmware", profile.kernel.stage1], bytes: 680 * Bytes.mb)],
                           undo: [], weight: 16, estimatedSeconds: 120, reversible: true))
        steps.append(.init(id: .createBoot, title: "Create \(part.bootPartition.name)", activeTitle: "Creating the boot partition…",
                           detail: "A \(Bytes.format(boot)) FAT32 partition for the second stage, the kernel collection and Wi-Fi firmware.",
                           operations: [.addPartition(after: "@stub", slot: "boot", content: .efi, name: part.bootPartition.name, size: boot,
                                                      metadata: stamp.merging(["sf.role": "boot"]) { a, _ in a })],
                           undo: [.deletePartition("@boot")], weight: 3, estimatedSeconds: 8, reversible: true))
        steps.append(.init(id: .createRoot, title: "Create the SiliconForest volume", activeTitle: "Creating the SiliconForest volume…",
                           detail: "A \(Bytes.format(root)) \(part.rootFilesystem) partition for the system and your files.",
                           operations: [.addPartition(after: "@boot", slot: "root", content: .linuxFilesystem, name: name, size: root,
                                                      metadata: stamp.merging(["sf.role": "root"]) { a, _ in a })],
                           undo: [.deletePartition("@root")], weight: 3, estimatedSeconds: 8, reversible: true))
        if !profile.firmware.isEmpty {
            steps.append(.init(id: .extractFirmware, title: "Copy device firmware", activeTitle: "Copying device firmware…",
                               detail: "Copies \(profile.firmware.map(\.summary).joined(separator: ", ")) from this Mac’s own macOS. Nothing is downloaded.",
                               operations: [.writeFiles(target: "@boot", label: "device firmware", items: profile.firmware.map(\.destination), bytes: 24 * Bytes.mb)],
                               undo: [], weight: 4, estimatedSeconds: 10, reversible: true))
        }
        steps.append(.init(id: .writeSystem, title: "Install SiliconForest", activeTitle: "Writing the system image…",
                           detail: "Writes the SiliconForest system image. It grows to fill its volume on first start.",
                           operations: [.download(item: "siliconforest-root.img.zst", url: "https://<release host>/siliconforest/\(profile.id)/root.img.zst", bytes: 2_900 * Bytes.mb),
                                        .writeImage(target: "@root", image: "siliconforest-root.img", bytes: 7_200 * Bytes.mb)],
                           undo: [], weight: 38, estimatedSeconds: 420, reversible: true))
        steps.append(.init(id: .installBootChain, title: "Install the kernel", activeTitle: "Installing the kernel…",
                           detail: "Copies the second stage and the kernel collection (\(profile.kernel.kexts.count) drivers) with this Mac’s boot arguments.",
                           operations: [.writeFiles(target: "@boot", label: "kernel and second stage", items: [profile.kernel.stage2, profile.kernel.collection, "sf/boot-args"], bytes: 96 * Bytes.mb)],
                           undo: [], weight: 6, estimatedSeconds: 20, reversible: true))
        steps.append(.init(id: .verify, title: "Verify the installation", activeTitle: "Verifying…",
                           detail: "Checks every file and image against its published checksum.",
                           operations: [.verify(target: "@boot", label: "boot partition", bytes: 120 * Bytes.mb),
                                        .verify(target: "@root", label: "system image", bytes: 7_200 * Bytes.mb)],
                           undo: [], weight: 8, estimatedSeconds: 60, reversible: true))
        steps.append(.init(id: .prepareRecovery, title: "Prepare the recoveryOS step", activeTitle: "Preparing the recoveryOS step…",
                           detail: "Writes the script recoveryOS runs to give SiliconForest its startup security policy.",
                           operations: [.writeFiles(target: "@stub", label: "recoveryOS step", items: ["step2.sh", "boot-policy.plist"], bytes: 1 * Bytes.mb)],
                           undo: [], weight: 2, estimatedSeconds: 4, reversible: true))

        return InstallPlan(kind: .install, profileID: profile.id, options: options, disk: disk.identifier,
                           macOSPartition: mac.identifier, macOSSizeBefore: mac.size, macOSSizeAfter: newMacSize,
                           stubSize: stub, bootSize: boot, rootSize: root, steps: steps)
    }

    /// Removes one install and gives its space back to macOS.
    public static func uninstallPlan(install: SiliconForestInstall, snapshot: DiskSnapshot, profileID: String = "J293") throws -> InstallPlan {
        guard let disk = snapshot.internalDisk, let mac = disk.macOSPartition else { throw PlanError.noMacOSContainer }
        // Only space contiguous with macOS can be regrown into it.
        var reclaim = install.totalBytes
        let freeAfterInstall: Int64 = {
            guard let last = install.partitions.last else { return 0 }
            return disk.freeAfter(last.identifier)
        }()
        reclaim += freeAfterInstall
        let contiguous = (disk.partitions.firstIndex { $0.identifier == mac.identifier }.map { i in
            i + 1 < disk.partitions.count && disk.partitions[i + 1].identifier == install.stub.identifier
        }) ?? false
        let gapBefore = disk.freeAfter(mac.identifier)
        let macAfter = contiguous ? mac.size + gapBefore + reclaim : mac.size

        var steps: [InstallStep] = []
        steps.append(.init(id: .preflight, title: "Check your Mac", activeTitle: "Checking your Mac…",
                           detail: "Confirms \(install.name) is not running and the disk matches what you reviewed.",
                           operations: [], undo: [], weight: 1, estimatedSeconds: 3, reversible: true))
        steps.append(.init(id: .savePartitionTable, title: "Save the partition table", activeTitle: "Saving the partition table…",
                           detail: "Records the current layout in the journal.", operations: [], undo: [], weight: 1, estimatedSeconds: 2, reversible: true))
        if let root = install.root {
            steps.append(.init(id: .removeRoot, title: "Remove the SiliconForest volume", activeTitle: "Removing the SiliconForest volume…",
                               detail: "Deletes \(root.identifier) (\(Bytes.format(root.size))) and everything stored on it.",
                               operations: [.deletePartition(root.identifier)], undo: [], weight: 3, estimatedSeconds: 6, reversible: false))
        }
        if let boot = install.boot {
            steps.append(.init(id: .removeBoot, title: "Remove \(boot.name ?? "SFBOOT")", activeTitle: "Removing the boot partition…",
                               detail: "Deletes \(boot.identifier), the second stage and the kernel.",
                               operations: [.deletePartition(boot.identifier)], undo: [], weight: 2, estimatedSeconds: 4, reversible: false))
        }
        steps.append(.init(id: .removeStub, title: "Remove the system container", activeTitle: "Removing the system container…",
                           detail: "Deletes the stub container and its entry in the startup picker.",
                           operations: [.deleteAPFSContainer(install.stub.identifier)], undo: [], weight: 3, estimatedSeconds: 10, reversible: false))
        if contiguous {
            steps.append(.init(id: .growMacOS, title: "Give the space back to macOS", activeTitle: "Growing macOS…",
                               detail: "Grows the macOS container from \(Bytes.format(mac.size)) to \(Bytes.format(macAfter)).",
                               operations: [.resizeContainer(partition: mac.identifier, newSize: 0)], undo: [], weight: 12, estimatedSeconds: 90, reversible: false))
        }
        steps.append(.init(id: .finishUninstall, title: "Finish", activeTitle: "Finishing…",
                           detail: "Confirms macOS is the startup disk and closes the journal.", operations: [], undo: [], weight: 1, estimatedSeconds: 2, reversible: true))

        return InstallPlan(kind: .uninstall, profileID: profileID,
                           options: InstallOptions(siliconForestSize: install.totalBytes, installName: install.name),
                           disk: disk.identifier, macOSPartition: mac.identifier, macOSSizeBefore: mac.size, macOSSizeAfter: macAfter,
                           stubSize: install.stub.size, bootSize: install.boot?.size ?? 0, rootSize: install.root?.size ?? 0, steps: steps)
    }
}
