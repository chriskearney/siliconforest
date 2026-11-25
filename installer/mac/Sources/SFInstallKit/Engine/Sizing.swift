import Foundation

/// What the release brings (placeholder until release manifests exist: DESIGN §10, ENGINE §4).
public struct ReleaseInfo: Sendable, Hashable {
    public enum RootSizing: Sendable, Hashable {
        /// The helper grows the root offline at S48 to fill its partition (`sf-ext4grow`).
        case growable
        /// The root partition equals the image size; the size handle is locked.
        case fixed(Int64)
    }
    public var version: String
    public var downloadBytes: Int64
    public var rootImageBytes: Int64
    public var rootMinBytes: Int64
    /// Largest root partition this release can grow into. Default is the 0.1.0 cap.
    public var rootMaxBytes: Int64
    public var rootSizing: RootSizing

    /// Growth limit of the 0.1.0 installer root, from its reserved GDT blocks (Chris, 24 Nov 2026):
    /// (1 GDT block + 259 reserved) × 64 descriptors per 4 KiB block × 32,768 blocks per group
    /// × 4,096 bytes = 2,233,382,993,920 (exactly 2,080 GiB). The grower still refuses a larger target.
    public static let rootGrowCapBytes: Int64 = 2_233_382_993_920

    public init(version: String, downloadBytes: Int64, rootImageBytes: Int64, rootMinBytes: Int64, rootSizing: RootSizing,
                rootMaxBytes: Int64 = ReleaseInfo.rootGrowCapBytes) {
        self.version = version; self.downloadBytes = downloadBytes; self.rootImageBytes = rootImageBytes
        self.rootMinBytes = rootMinBytes; self.rootSizing = rootSizing; self.rootMaxBytes = rootMaxBytes
    }

    public static let placeholder = ReleaseInfo(version: "0.3", downloadBytes: 3_400_000_000, rootImageBytes: 7_300_000_000,
                                                rootMinBytes: 8_500_000_000, rootSizing: .growable)
}

/// How big SiliconForest can be on this disk (docs/installer/ENGINE.md §4).
///
/// ```
/// macos_floor = align_up(used + reserve + downloads + drift)
/// sf_max      = container + adjacent_free - macos_floor
/// sf_min      = STUB + BOOT + ROOT_MIN
/// default     = STUB + BOOT + max(profile default, 25% of the disk), capped by sf_max
/// ```
public struct SizingConstraints: Sendable, Hashable {
    public var macOSPartition: Partition
    public var freeAfterMacOS: Int64
    public var macOSUsed: Int64
    /// 38 GB normally; 1 GB on small disks (with a warning).
    public var reserve: Int64
    public var isSmallDisk: Bool
    /// Bytes still to download into macOS's container before the first write.
    public var downloads: Int64
    /// Margin for macOS writing while we work.
    public var drift: Int64
    /// The smallest macOS may become.
    public var macOSFloor: Int64
    public var minimum: Int64
    public var maximum: Int64
    public var recommended: Int64
    public var step: Int64
    public var stub: Int64
    public var boot: Int64
    public var rootLocked: Bool
    public var lowSpaceNote: Int64
    /// Largest root partition this release can grow into (`ReleaseInfo.rootMaxBytes`).
    public var rootMaxBytes: Int64
    /// True when `maximum` is the grow cap, not the macOS reserve (for the size-handle explanation).
    public var isCappedByRootGrow: Bool

    public var pool: Int64 { macOSPartition.size + freeAfterMacOS }
    public var isFeasible: Bool { maximum >= minimum }
    /// How much would have to be freed in macOS when infeasible.
    public var shortfall: Int64 { max(0, minimum - maximum) }

    public init?(profile: DeviceProfile, disk: PhysicalDisk, release: ReleaseInfo = .placeholder) {
        guard let mac = disk.macOSPartition, let container = mac.container else { return nil }
        let p = profile.partitioning
        let align = max(p.alignmentBytes, 4096)
        macOSPartition = mac
        freeAfterMacOS = disk.freeAfter(mac.identifier)
        macOSUsed = container.capacityUsed
        isSmallDisk = p.smallDiskThresholdBytes.map { disk.size < $0 } ?? false
        reserve = isSmallDisk ? (p.smallDiskReserveBytes ?? p.macOSMinFreeBytes) : p.macOSMinFreeBytes
        downloads = (profile.support.stubDownloadBytes ?? 720_000_000) + release.downloadBytes
        let span = max(0, mac.size + freeAfterMacOS - macOSUsed)
        drift = min(p.driftMaximumBytes ?? 8 * Bytes.gib, Int64(Double(span) * (p.driftFraction ?? 0.05)))
        macOSFloor = Self.alignUp(macOSUsed + reserve + downloads + drift, to: align)
        stub = p.stubContainerBytes
        boot = p.bootPartition.bytes
        step = Bytes.gb
        lowSpaceNote = p.rootLowSpaceNoteBytes ?? 40 * Bytes.gb
        let rootMin = max(p.rootMinBytes, release.rootMinBytes)
        rootMaxBytes = max(rootMin, release.rootMaxBytes)
        switch release.rootSizing {
        case .growable:
            rootLocked = false
            minimum = stub + boot + rootMin
            let diskMax = ((mac.size + freeAfterMacOS - macOSFloor) / Bytes.gb) * Bytes.gb
            let growMax = stub + boot + rootMaxBytes
            isCappedByRootGrow = growMax < diskMax
            maximum = min(diskMax, growMax)
            let rootDefault = max(p.rootRecommendedBytes, Int64(Double(disk.size) * (p.rootDefaultDiskFraction ?? 0)))
            recommended = min(max(stub + boot + Self.roundGB(rootDefault), minimum), maximum)
        case .fixed(let bytes):
            rootLocked = true
            isCappedByRootGrow = false
            minimum = stub + boot + bytes
            maximum = min(minimum, mac.size + freeAfterMacOS - macOSFloor)
            recommended = minimum
        }
    }

    static func alignUp(_ v: Int64, to a: Int64) -> Int64 { ((v + a - 1) / a) * a }
    static func roundGB(_ v: Int64) -> Int64 { ((v + Bytes.gb / 2) / Bytes.gb) * Bytes.gb }

    /// Size of the macOS container once SiliconForest takes `siliconForest` bytes of the pool.
    public func macOSSize(for siliconForest: Int64) -> Int64 { min(macOSPartition.size, pool - siliconForest) }
    /// Free space macOS keeps after resizing.
    public func macOSFree(for siliconForest: Int64) -> Int64 { max(0, macOSSize(for: siliconForest) - macOSUsed) }

    public func clamp(_ size: Int64) -> Int64 {
        guard isFeasible else { return minimum }
        return min(max(size, minimum), maximum)
    }

    /// Snaps to whole gigabytes, keeping the exact min/max reachable.
    public func snap(_ size: Int64) -> Int64 {
        let c = clamp(size)
        if c == minimum || c == maximum { return c }
        return clamp(Self.roundGB(c))
    }

    public enum Limit: Sendable { case macOSReserve, rootGrowCap, siliconForestMinimum, none }
    /// Which limit a requested size runs into (for the one-line explanation at the hard stop).
    public func limit(for requested: Int64) -> Limit {
        if requested > maximum { return isCappedByRootGrow ? .rootGrowCap : .macOSReserve }
        if requested < minimum { return .siliconForestMinimum }
        return .none
    }

    public struct Preset: Sendable, Hashable, Identifiable {
        public var id: String
        public var size: Int64
    }

    /// Recommended, Half, Minimum, Maximum (UX-FLOW §4), dropping duplicates on small disks.
    public var presets: [Preset] {
        guard isFeasible, !rootLocked else { return [] }
        // Recommended, Minimum and Maximum always appear; Half only when it's a distinct size.
        let half = snap(pool / 2)
        var list = [Preset(id: "recommended", size: recommended)]
        if ![recommended, minimum, maximum].contains(where: { $0 / Bytes.gb == half / Bytes.gb }) { list.append(Preset(id: "half", size: half)) }
        list.append(Preset(id: "minimum", size: minimum))
        if maximum / Bytes.gb != recommended / Bytes.gb { list.append(Preset(id: "maximum", size: maximum)) }
        return list
    }
}
