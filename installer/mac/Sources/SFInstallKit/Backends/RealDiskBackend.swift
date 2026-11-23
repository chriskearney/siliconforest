import Foundation
import IOKit

/// Runs a fixed set of read-only system queries. Anything not on the allow-list is refused before
/// a process is created, so a bug elsewhere cannot turn this into a way to change the disk.
public enum ReadOnlyCommand {
    /// Exact argv prefixes that may run. Every entry is a query.
    static let allowList: [[String]] = [
        ["/usr/sbin/diskutil", "list", "-plist"],
        ["/usr/sbin/diskutil", "apfs", "list", "-plist"],
        ["/usr/bin/fdesetup", "status"],
        ["/usr/bin/csrutil", "status"],
        ["/usr/sbin/sysctl", "-n", "hw.model"],
        ["/usr/sbin/sysctl", "-n", "hw.target"],
        ["/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"],
        ["/usr/bin/sw_vers", "-productVersion"],
        ["/usr/bin/sw_vers", "-buildVersion"],
        ["/usr/bin/pmset", "-g", "batt"],
    ]

    /// Words that never appear in a query we run, checked in addition to the allow-list.
    static let forbidden: Set<String> = [
        "resizeContainer", "addPartition", "eraseVolume", "eraseDisk", "partitionDisk", "deleteContainer",
        "deleteVolume", "addVolume", "mergePartitions", "splitPartition", "mount", "unmount", "bless", "bputil",
        "configure-boot", "nvram", "disable", "enable", "authenticated-root", "-w",
    ]

    public static func isAllowed(_ argv: [String]) -> Bool {
        if argv.contains(where: { forbidden.contains($0) }) { return false }
        // `diskutil info -plist <device>`: exactly one device identifier.
        if argv.count == 4, Array(argv.prefix(3)) == ["/usr/sbin/diskutil", "info", "-plist"] {
            return argv[3].range(of: #"^disk[0-9]+(s[0-9]+)*$"#, options: .regularExpression) != nil
        }
        return allowList.contains(argv)
    }

    public static func run(_ argv: [String]) throws -> Data {
        guard isAllowed(argv) else { throw BackendError.commandNotAllowed(argv.joined(separator: " ")) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0])
        p.arguments = Array(argv.dropFirst())
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        try? out.fileHandleForReading.close(); try? out.fileHandleForWriting.close()
        // csrutil/fdesetup print status and can exit non-zero on some states; the text is what matters.
        if p.terminationStatus != 0 && argv[0].hasSuffix("diskutil") {
            throw BackendError.commandFailed(argv.joined(separator: " "), p.terminationStatus)
        }
        return data
    }

    static func text(_ argv: [String]) -> String? {
        (try? run(argv)).flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func plist(_ argv: [String]) throws -> [String: Any] {
        let data = try run(argv)
        guard let obj = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw BackendError.parse(argv.joined(separator: " "))
        }
        return obj
    }
}

/// Executes privileged disk operations. The only implementation in this phase refuses; a real one
/// belongs in a signed privileged helper (SMAppService), not in the app.
public protocol PrivilegedExecutor: Sendable {
    func run(_ commands: [[String]]) async throws
}

public struct RefusingExecutor: PrivilegedExecutor {
    public init() {}
    public func run(_ commands: [[String]]) async throws {
        throw BackendError.mutationRefused("no privileged helper in this build")
    }
}

/// Reads the real Mac. Never writes: mutating operations are rendered as commands, journaled by the
/// runner, applied to a projected copy of the layout (so later steps resolve), and reported as not
/// executed.
public actor RealDiskBackend: DiskBackend {
    public nonisolated let kind: BackendKind = .realReadOnly
    private var projected: DiskSnapshot?
    private let executor: PrivilegedExecutor
    public private(set) var plannedCommands: [[String]] = []

    public init(executor: PrivilegedExecutor = RefusingExecutor()) {
        self.executor = executor
    }

    public func systemFacts() async throws -> SystemFacts {
        var f = SystemFacts()
        f.hwModel = ReadOnlyCommand.text(["/usr/sbin/sysctl", "-n", "hw.model"])
        f.board = ReadOnlyCommand.text(["/usr/sbin/sysctl", "-n", "hw.target"])
        f.chipName = ReadOnlyCommand.text(["/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"])
        f.macOSVersion = ReadOnlyCommand.text(["/usr/bin/sw_vers", "-productVersion"])
        f.macOSBuild = ReadOnlyCommand.text(["/usr/bin/sw_vers", "-buildVersion"])
        f.fileVault = Self.parseFileVault(ReadOnlyCommand.text(["/usr/bin/fdesetup", "status"]) ?? "")
        f.sip = Self.parseSIP(ReadOnlyCommand.text(["/usr/bin/csrutil", "status"]) ?? "")
        f.power = Self.parsePower(ReadOnlyCommand.text(["/usr/bin/pmset", "-g", "batt"]) ?? "")
        f.bootPolicy = nil // `bputil -d` needs root; read in recoveryOS instead.
        f.userName = NSUserName()
        f.userFullName = NSFullUserName().split(separator: " ").first.map(String.init)
        f.isAdmin = Self.isAdmin()
        f.systemFirmware = Self.systemFirmwareVersion()
        f.internet = nil   // checked just before downloading
        return f
    }

    public func snapshot() async throws -> DiskSnapshot {
        let s = try Self.readSnapshot()
        projected = s
        return s
    }

    public func perform(_ operation: DiskOperation, context: OperationContext, resolve: @Sendable (PartRef) -> String,
                        progress: ProgressHandler) async throws -> OperationResult {
        if projected == nil { projected = try Self.readSnapshot() }
        var model = projected!
        let created = try DiskModelMutator.apply(operation, to: &model, resolve: resolve)
        let commands = operation.commands(resolve: resolve).map { $0.map { $0.replacingOccurrences(of: "<new>", with: created ?? "<new>") } }

        #if SF_REAL_DISK_WRITES
        // Compile-time gate (never set by Package.swift) AND a runtime gate. Even when both are open,
        // the executor in this phase refuses: writes need the signed privileged helper.
        if operation.isMutating && RealDiskWriteGate.runtimeAllowed {
            try await executor.run(commands)
            projected = model
            return OperationResult(createdIdentifier: created, commands: commands, executed: true)
        }
        #endif

        plannedCommands.append(contentsOf: commands)
        projected = model
        await progress(1, "Planned (not executed)")
        return OperationResult(createdIdentifier: created, commands: commands, executed: false)
    }

    // MARK: in-process reads (no processes, no privileges)

    /// IODeviceTree:/chosen `system-firmware-version`.
    static func systemFirmwareVersion() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/chosen")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let data = IORegistryEntryCreateCFProperty(entry, "system-firmware-version" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data else { return nil }
        return String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
    }

    /// Member of the local admin group.
    static func isAdmin() -> Bool? {
        guard let pw = getpwuid(getuid()), let admin = getgrnam("admin") else { return nil }
        var groups = [Int32](repeating: 0, count: 128)
        var n = Int32(groups.count)
        guard getgrouplist(pw.pointee.pw_name, Int32(bitPattern: pw.pointee.pw_gid), &groups, &n) != -1 else { return nil }
        return groups.prefix(Int(n)).contains(Int32(bitPattern: admin.pointee.gr_gid))
    }

    // MARK: parsing

    static func parseFileVault(_ s: String) -> FileVaultState {
        if s.contains("FileVault is On") { return s.contains("Encryption in progress") ? .encrypting : (s.contains("Decryption in progress") ? .decrypting : .on) }
        if s.contains("FileVault is Off") { return .off }
        return .unknown
    }

    static func parseSIP(_ s: String) -> SIPState {
        if s.contains("Custom Configuration") || s.contains("unknown (Custom") { return .custom }
        if s.contains("status: enabled") { return .enabled }
        if s.contains("status: disabled") { return .disabled }
        return .unknown
    }

    static func parsePower(_ s: String) -> PowerState {
        var p = PowerState(onACPower: s.contains("'AC Power'"))
        if let r = s.range(of: #"(\d+)%"#, options: .regularExpression) { p.batteryPercent = Int(s[r].dropLast()) }
        p.charging = s.contains("; charging;")
        return p
    }

    static func readSnapshot() throws -> DiskSnapshot {
        let list = try ReadOnlyCommand.plist(["/usr/sbin/diskutil", "list", "-plist"])
        let apfs = try ReadOnlyCommand.plist(["/usr/sbin/diskutil", "apfs", "list", "-plist"])
        var containersByStore: [String: APFSContainer] = [:]
        for c in apfs["Containers"] as? [[String: Any]] ?? [] {
            let vols = (c["Volumes"] as? [[String: Any]] ?? []).map { v in
                APFSVolume(identifier: v["DeviceIdentifier"] as? String ?? "?", name: v["Name"] as? String ?? "",
                           roles: v["Roles"] as? [String] ?? [], capacityInUse: (v["CapacityInUse"] as? NSNumber)?.int64Value ?? 0,
                           fileVault: v["FileVault"] as? Bool ?? false, locked: v["Locked"] as? Bool ?? false)
            }
            let container = APFSContainer(reference: c["ContainerReference"] as? String ?? "?",
                                          capacityCeiling: (c["CapacityCeiling"] as? NSNumber)?.int64Value ?? 0,
                                          capacityFree: (c["CapacityFree"] as? NSNumber)?.int64Value ?? 0, volumes: vols)
            if let store = c["DesignatedPhysicalStore"] as? String { containersByStore[store] = container }
        }

        var disks: [PhysicalDisk] = []
        for whole in list["AllDisksAndPartitions"] as? [[String: Any]] ?? [] {
            guard let id = whole["DeviceIdentifier"] as? String, whole["Content"] as? String == "GUID_partition_scheme" else { continue }
            let info = try ReadOnlyCommand.plist(["/usr/sbin/diskutil", "info", "-plist", id])
            guard info["Internal"] as? Bool == true, info["VirtualOrPhysical"] as? String != "Virtual" else { continue }
            var parts: [Partition] = []
            for p in whole["Partitions"] as? [[String: Any]] ?? [] {
                guard let pid = p["DeviceIdentifier"] as? String else { continue }
                let pinfo = try ReadOnlyCommand.plist(["/usr/sbin/diskutil", "info", "-plist", pid])
                let content = PartitionContent(diskutil: p["Content"] as? String ?? "")
                parts.append(Partition(identifier: pid,
                                       offset: (pinfo["PartitionMapPartitionOffset"] as? NSNumber)?.int64Value ?? 0,
                                       size: (p["Size"] as? NSNumber)?.int64Value ?? 0,
                                       content: content,
                                       name: (p["VolumeName"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                                       container: containersByStore[pid]))
            }
            disks.append(PhysicalDisk(identifier: id, mediaName: info["MediaName"] as? String ?? "Internal SSD",
                                      size: (info["Size"] as? NSNumber)?.int64Value ?? 0,
                                      blockSize: (info["DeviceBlockSize"] as? NSNumber)?.int64Value ?? 4096,
                                      isInternal: true, partitions: parts))
        }
        guard !disks.isEmpty else { throw BackendError.parse("no internal GPT disk") }
        return DiskSnapshot(disks: disks)
    }
}

#if SF_REAL_DISK_WRITES
enum RealDiskWriteGate {
    /// Requires an explicit environment opt-in *and* root. The app is never root; only a helper is.
    static var runtimeAllowed: Bool {
        ProcessInfo.processInfo.environment["SF_ALLOW_REAL_DISK_WRITES"] == "I-have-a-backup" && getuid() == 0
    }
}
#endif
