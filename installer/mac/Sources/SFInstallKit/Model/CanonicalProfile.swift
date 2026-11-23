import Foundation

/// The canonical device profile format: `installer/profiles/<ID>.json`, described by
/// `installer/profiles/device-profile.schema.json` and docs/installer/ADDING-A-MAC.md.
/// Decoded leniently (only what the installer uses) and mapped onto `DeviceProfile`.
struct CanonicalProfile: Decodable {
    var schema_version: Int?
    var id: String
    var status: String?
    var status_reason: String?
    var identity: Identity
    var host_macos: HostMacOS?
    var stub: Stub?
    var boot: Boot?
    var kernel: Kernel?
    var layout: Layout
    var hardware: Hardware?
    var firmware: Firmware?
    var quirks: [Quirk]?

    struct Identity: Decodable {
        var target_type: String?
        var hw_model: String?
        var device_class: String?
        var soc: String
        var chip_id: String?
        var marketing_name: String?
    }
    struct HostMacOS: Decodable {
        var minimum: String?
        var maximum_tested_major: Int?
        var maximum_allowed_major: Int?
        var blocked_majors: [Blocked]?
        var gated_majors: [Gated]?
        struct Blocked: Decodable { var major: Int; var reason: String }
        struct Gated: Decodable { var major: Int; var gate: String?; var passed: Bool?; var reason: String }
    }
    struct Stub: Decodable {
        var version: String?
        var build: String?
        var restore_image: RestoreImage?
        var partition_bytes: Int64?
        var minimum_iboot: String?
        struct RestoreImage: Decodable { var url: String?; var bytes: Int64?; var approximate_download_bytes: Int64? }
    }
    struct Boot: Decodable {
        var stage1: Stage1?
        var stage2: Stage2?
        struct Stage1: Decodable { var artifact: String? }
        struct Stage2: Decodable { var path: String?; var kernel_path: String? }
    }
    struct Kernel: Decodable { var arguments: [String]? }
    struct Layout: Decodable {
        var alignment_bytes: Int64?
        var macos_free_reserve_bytes: Int64?
        var small_disk_threshold_bytes: Int64?
        var small_disk_reserve_bytes: Int64?
        var drift_margin: Drift?
        var partitions: [Part]
        var root: Root?
        struct Drift: Decodable { var fraction: Double?; var maximum_bytes: Int64? }
        struct Part: Decodable { var role: String; var type: String?; var format: String?; var label: String?; var bytes: Int64? }
        struct Root: Decodable { var default_bytes: Int64?; var default_disk_fraction: Double?; var low_space_note_bytes: Int64?; var min_bytes: Int64? }
    }
    struct Hardware: Decodable {
        var power_button: PowerButton?
        var kernel_extensions: [Kext]?
        struct PowerButton: Decodable { var location: String?; var hold_copy: String? }
        struct Kext: Decodable { var name: String }
    }
    struct Firmware: Decodable {
        var items: [Item]?
        struct Item: Decodable {
            var id: String
            var `class`: String?
            var source: Source?
            var install_as: String?
            struct Source: Decodable { var kind: String?; var path: String? }
        }
    }
    struct Quirk: Decodable { var id: String; var severity: String?; var summary: String; var effect: String? }

    /// Root minimum is a property of the release (release.root.min_bytes, ENGINE.md §4). Until a
    /// release manifest exists the installer uses this placeholder.
    static let placeholderRootMinBytes: Int64 = 16 * 1_000_000_000

    var deviceProfile: DeviceProfile {
        let stubBytes = layout.partitions.first { $0.role == "stub" }?.bytes ?? stub?.partition_bytes ?? 2_499_805_184
        let bootPart = layout.partitions.first { $0.role == "boot" }
        let rootPart = layout.partitions.first { $0.role == "root" }
        let rootFS = (rootPart?.format ?? "ext4").replacingOccurrences(of: "-image", with: "")
        let socName = Self.socNames[identity.soc.lowercased()] ?? identity.soc

        var support = DeviceProfile.Support(status: status ?? "development", minMacOS: host_macos?.minimum ?? "13.5",
                                            stubFirmware: stub?.version.map { [$0] } ?? [], preferredStubFirmware: stub?.version)
        support.maximumTestedMajor = host_macos?.maximum_allowed_major ?? host_macos?.maximum_tested_major
        support.gatedMajors = (host_macos?.gated_majors ?? []).map { .init(major: $0.major, gate: $0.gate ?? "?", passed: $0.passed ?? false, reason: $0.reason) }
        support.blockedMajors = (host_macos?.blocked_majors ?? []).map { .init(major: $0.major, reason: $0.reason) }
        support.stubBuild = stub?.build
        support.stubRestoreImageURL = stub?.restore_image?.url
        support.stubDownloadBytes = stub?.restore_image?.approximate_download_bytes
        support.minimumIBoot = stub?.minimum_iboot

        var part = DeviceProfile.Partitioning(
            stubContainerBytes: stubBytes,
            bootPartition: .init(name: bootPart?.label ?? "SFBOOT", format: bootPart?.format ?? "fat32", bytes: bootPart?.bytes ?? 524_288_000),
            rootMinBytes: layout.root?.min_bytes ?? Self.placeholderRootMinBytes,
            rootRecommendedBytes: layout.root?.default_bytes ?? 51_539_607_552,
            macOSMinFreeBytes: layout.macos_free_reserve_bytes ?? 38_000_000_000,
            alignmentBytes: layout.alignment_bytes ?? 1_048_576,
            rootFilesystem: rootFS)
        part.smallDiskThresholdBytes = layout.small_disk_threshold_bytes
        part.smallDiskReserveBytes = layout.small_disk_reserve_bytes
        part.driftFraction = layout.drift_margin?.fraction
        part.driftMaximumBytes = layout.drift_margin?.maximum_bytes
        part.rootDefaultDiskFraction = layout.root?.default_disk_fraction
        part.rootLowSpaceNoteBytes = layout.root?.low_space_note_bytes

        let fw: [DeviceProfile.FirmwareItem] = (firmware?.items ?? []).map { item in
            DeviceProfile.FirmwareItem(id: item.id, source: item.source?.path ?? "", destination: item.install_as ?? "",
                                       summary: Self.firmwareNames[item.class ?? ""] ?? item.class ?? item.id)
        }
        let kern = DeviceProfile.Kernel(stage1: boot?.stage1?.artifact ?? "sf-stage1.bin", stage2: boot?.stage2?.path ?? "sf/boot.bin",
                                        collection: boot?.stage2?.kernel_path ?? "sf/kernel.bin",
                                        kexts: (hardware?.kernel_extensions ?? []).map(\.name), bootArgs: kernel?.arguments ?? [])
        let q = (quirks ?? []).map { DeviceProfile.Quirk(id: $0.id, summary: $0.summary, severity: $0.severity, effect: $0.effect) }

        var p = DeviceProfile(schemaVersion: schema_version ?? 1, id: id,
                              marketingName: identity.marketing_name ?? id,
                              modelIdentifiers: identity.hw_model.map { [$0] } ?? [],
                              board: (identity.device_class ?? "\(id)ap").uppercased(),
                              soc: .init(id: identity.soc, name: socName, chipID: identity.chip_id),
                              support: support, partitioning: part, firmware: fw, kernel: kern, quirks: q)
        p.powerButtonCopy = hardware?.power_button?.hold_copy
        p.sourceFormat = "canonical"
        return p
    }

    static let socNames: [String: String] = [
        "t8103": "Apple M1", "t6000": "Apple M1 Pro", "t6001": "Apple M1 Max", "t6002": "Apple M1 Ultra",
        "t8112": "Apple M2", "t6020": "Apple M2 Pro", "t6021": "Apple M2 Max", "t6022": "Apple M2 Ultra",
    ]
    static let firmwareNames: [String: String] = [
        "wifi": "Wi-Fi (BCM4378)", "touch-bar": "Touch Bar digitizer", "bluetooth": "Bluetooth", "trackpad": "Trackpad",
    ]
}
