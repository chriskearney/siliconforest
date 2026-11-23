import Foundation

/// Everything the installer knows about one Mac model. One JSON file per Mac
/// (`installer/profiles/<ID>.json`); adding a Mac should need a profile and nothing else in the
/// engine. Unknown keys are ignored and most keys are optional, so the profile format can grow
/// without breaking older builds of the app.
public struct DeviceProfile: Codable, Sendable, Identifiable, Hashable {
    public var schemaVersion: Int
    /// Board family, e.g. "J293".
    public var id: String
    public var marketingName: String
    /// `sysctl hw.model` values, e.g. ["MacBookPro17,1"].
    public var modelIdentifiers: [String]
    /// `sysctl hw.target` / device tree target, e.g. "J293AP".
    public var board: String
    public var soc: SoC
    public var support: Support
    public var partitioning: Partitioning
    public var firmware: [FirmwareItem]
    public var kernel: Kernel
    public var quirks: [Quirk]

    public struct SoC: Codable, Sendable, Hashable {
        /// "t8103"
        public var id: String
        /// "Apple M1"
        public var name: String
        public var chipID: String?
    }

    public struct Support: Codable, Sendable, Hashable {
        /// supported | experimental | planned
        public var status: String
        /// Oldest macOS the installer accepts on this model ("12.3").
        public var minMacOS: String
        /// Firmware versions the stub may carry; SiliconForest's boot chain is tested against these.
        public var stubFirmware: [String]
        public var preferredStubFirmware: String?
        /// Newest macOS major the profile has been tested on; newer ones get a warning.
        public var maximumTestedMajor: Int? = nil
        /// macOS majors the installer refuses, with the reason shown to the user.
        public var blockedMajors: [BlockedMajor] = []
        /// Majors that are targets but stay refused by release builds until a named gate passes (D11).
        public var gatedMajors: [GatedMajor] = []
        /// macOS build of the stub (e.g. "22G74").
        public var stubBuild: String? = nil
        public var stubRestoreImageURL: String? = nil
        /// What the installer actually fetches from the restore image (partial reads).
        public var stubDownloadBytes: Int64? = nil
        /// Oldest system firmware (iBoot) the stub needs, e.g. "iBoot-8422.141.2".
        public var minimumIBoot: String? = nil

        public struct BlockedMajor: Codable, Sendable, Hashable {
            public var major: Int
            public var reason: String
        }
        public struct GatedMajor: Codable, Sendable, Hashable {
            public var major: Int
            public var gate: String
            public var passed: Bool
            public var reason: String
        }
    }

    public struct Partitioning: Codable, Sendable, Hashable {
        /// APFS container that holds the stub macOS (boot policy + stage 1). Asahi-style.
        public var stubContainerBytes: Int64
        public var bootPartition: BootPartition
        /// Smallest SiliconForest root (ext4) the installer will create.
        public var rootMinBytes: Int64
        public var rootRecommendedBytes: Int64
        /// Free space macOS must keep after shrinking (updates, swap, snapshots).
        public var macOSMinFreeBytes: Int64
        /// Partition boundaries are aligned to this.
        public var alignmentBytes: Int64
        public var rootFilesystem: String
        /// Disks smaller than this keep only `smallDiskReserveBytes` free in macOS (with a warning).
        public var smallDiskThresholdBytes: Int64? = nil
        public var smallDiskReserveBytes: Int64? = nil
        /// Safety margin for macOS writing while we work: min(max, fraction × resizable span).
        public var driftFraction: Double? = nil
        public var driftMaximumBytes: Int64? = nil
        /// Default root = max(rootRecommendedBytes, fraction × disk).
        public var rootDefaultDiskFraction: Double? = nil
        /// Below this, the editor notes that SiliconForest will be short of room.
        public var rootLowSpaceNoteBytes: Int64? = nil

        public struct BootPartition: Codable, Sendable, Hashable {
            public var name: String
            public var format: String
            public var bytes: Int64
        }
    }

    public struct FirmwareItem: Codable, Sendable, Hashable, Identifiable {
        public var id: String
        /// Where macOS keeps it (read at install time, never shipped by us).
        public var source: String
        public var destination: String
        public var summary: String
    }

    public struct Kernel: Codable, Sendable, Hashable {
        public var stage1: String
        public var stage2: String
        public var collection: String
        public var kexts: [String]
        public var bootArgs: [String]
    }

    public struct Quirk: Codable, Sendable, Hashable, Identifiable {
        public var id: String
        public var summary: String
        public var severity: String? = nil
        public var effect: String? = nil
    }

    /// Copy for the power-button step of the recoveryOS handoff (model-specific).
    public var powerButtonCopy: String? = nil
    /// Where the profile came from (canonical installer/profiles file or a fixture).
    public var sourceFormat: String = "fixture"

    /// Smallest total SiliconForest footprint: stub + boot + minimum root.
    public var minimumFootprint: Int64 {
        partitioning.stubContainerBytes + partitioning.bootPartition.bytes + partitioning.rootMinBytes
    }

    public var recommendedFootprint: Int64 {
        partitioning.stubContainerBytes + partitioning.bootPartition.bytes + partitioning.rootRecommendedBytes
    }

    public func matches(hwModel: String?, board: String?) -> Bool {
        if let hwModel, modelIdentifiers.contains(where: { $0.caseInsensitiveCompare(hwModel) == .orderedSame }) { return true }
        if let board, board.caseInsensitiveCompare(self.board) == .orderedSame { return true }
        return false
    }
}

/// Finds and loads profiles. Search order:
/// 1. an explicit directory (`--profiles` / `SF_PROFILES_DIR`);
/// 2. `installer/profiles/` in the source tree (the canonical home, written alongside DESIGN.md);
/// 3. the app bundle's `Resources/Profiles`;
/// 4. the test fixture in `installer/mac/Fixtures/profiles`.
public enum ProfileStore {
    public static func searchDirectories(explicit: URL? = nil) -> [URL] {
        var dirs: [URL] = []
        if let explicit { dirs.append(explicit) }
        if let env = ProcessInfo.processInfo.environment["SF_PROFILES_DIR"] { dirs.append(URL(fileURLWithPath: env)) }
        dirs.append(SourceTree.installerRoot.appendingPathComponent("profiles"))
        if let res = Bundle.main.resourceURL { dirs.append(res.appendingPathComponent("Profiles")) }
        dirs.append(SourceTree.packageRoot.appendingPathComponent("Fixtures/profiles"))
        return dirs
    }

    /// All profiles, first directory wins for a given id.
    public static func loadAll(explicit: URL? = nil) -> [DeviceProfile] {
        var seen: [String: DeviceProfile] = [:]
        var order: [String] = []
        for dir in searchDirectories(explicit: explicit) {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where file.pathExtension == "json" {
                guard !file.lastPathComponent.contains("schema"), let p = try? load(file) else { continue }
                if seen[p.id] == nil { seen[p.id] = p; order.append(p.id) }
            }
        }
        return order.compactMap { seen[$0] }
    }

    public static func load(_ url: URL) throws -> DeviceProfile {
        let data = try Data(contentsOf: url)
        return try ProfileDecoder.decode(data)
    }

    public static func profile(id: String, explicit: URL? = nil) -> DeviceProfile? {
        loadAll(explicit: explicit).first { $0.id.caseInsensitiveCompare(id) == .orderedSame }
    }

    public static func profile(matching facts: SystemFacts, explicit: URL? = nil) -> DeviceProfile? {
        loadAll(explicit: explicit).first { $0.matches(hwModel: facts.hwModel, board: facts.board) }
    }
}

/// Decodes a profile, accepting either the installer's own layout or a flatter one, and filling
/// defaults for optional sections so a minimal profile still loads.
enum ProfileDecoder {
    static func decode(_ data: Data) throws -> DeviceProfile {
        let d = JSONDecoder()
        // The canonical format (installer/profiles/*.json, device-profile.schema.json) is snake_case
        // with an `identity` block; the fixture format is the model below.
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], obj["identity"] != nil {
            return try d.decode(CanonicalProfile.self, from: data).deviceProfile
        }
        return try d.decode(DeviceProfile.self, from: data)
    }
}

extension DeviceProfile {
    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, marketingName, modelIdentifiers, board, soc, support, partitioning, firmware, kernel, quirks, powerButtonCopy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        id = try c.decode(String.self, forKey: .id)
        marketingName = try c.decodeIfPresent(String.self, forKey: .marketingName) ?? id
        modelIdentifiers = try c.decodeIfPresent([String].self, forKey: .modelIdentifiers) ?? []
        board = try c.decodeIfPresent(String.self, forKey: .board) ?? "\(id)AP"
        soc = try c.decode(SoC.self, forKey: .soc)
        support = try c.decodeIfPresent(Support.self, forKey: .support)
            ?? Support(status: "experimental", minMacOS: "12.3", stubFirmware: [], preferredStubFirmware: nil)
        partitioning = try c.decode(Partitioning.self, forKey: .partitioning)
        firmware = try c.decodeIfPresent([FirmwareItem].self, forKey: .firmware) ?? []
        kernel = try c.decodeIfPresent(Kernel.self, forKey: .kernel)
            ?? Kernel(stage1: "m1n1.bin", stage2: "sf/boot.bin", collection: "sf/kernel.bin", kexts: [], bootArgs: [])
        quirks = try c.decodeIfPresent([Quirk].self, forKey: .quirks) ?? []
        powerButtonCopy = try c.decodeIfPresent(String.self, forKey: .powerButtonCopy)
    }

    public init(schemaVersion: Int, id: String, marketingName: String, modelIdentifiers: [String], board: String, soc: SoC,
                support: Support, partitioning: Partitioning, firmware: [FirmwareItem], kernel: Kernel, quirks: [Quirk]) {
        self.schemaVersion = schemaVersion; self.id = id; self.marketingName = marketingName
        self.modelIdentifiers = modelIdentifiers; self.board = board; self.soc = soc; self.support = support
        self.partitioning = partitioning; self.firmware = firmware; self.kernel = kernel; self.quirks = quirks
    }
}

/// Locates the source tree at build time, so `swift run` finds fixtures and `installer/profiles`.
public enum SourceTree {
    /// installer/mac
    public static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)            // …/installer/mac/Sources/SFInstallKit/Model/DeviceProfile.swift
            .deletingLastPathComponent()           // Model
            .deletingLastPathComponent()           // SFInstallKit
            .deletingLastPathComponent()           // Sources
            .deletingLastPathComponent()           // mac
    }

    /// installer/
    public static var installerRoot: URL { packageRoot.deletingLastPathComponent() }

    public static var fixtures: URL {
        if let res = Bundle.main.resourceURL?.appendingPathComponent("Fixtures"),
           FileManager.default.fileExists(atPath: res.path) { return res }
        return packageRoot.appendingPathComponent("Fixtures")
    }
}
