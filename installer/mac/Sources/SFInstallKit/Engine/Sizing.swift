import Foundation

/// How big SiliconForest can be on this disk, derived from the profile and the live layout.
public struct SizingConstraints: Sendable, Hashable {
    /// The macOS container being shrunk.
    public var macOSPartition: Partition
    /// Free, unpartitioned space directly after it (used before macOS is shrunk at all).
    public var freeAfterMacOS: Int64
    public var macOSUsed: Int64
    public var macOSMinFree: Int64
    /// Smallest and largest SiliconForest footprint (stub + boot + root).
    public var minimum: Int64
    public var maximum: Int64
    public var recommended: Int64
    public var step: Int64

    /// Space macOS and SiliconForest share: the container plus the free gap after it.
    public var pool: Int64 { macOSPartition.size + freeAfterMacOS }
    public var isFeasible: Bool { maximum >= minimum }

    public init?(profile: DeviceProfile, disk: PhysicalDisk) {
        guard let mac = disk.macOSPartition, let container = mac.container else { return nil }
        let align = max(profile.partitioning.alignmentBytes, 4096)
        macOSPartition = mac
        freeAfterMacOS = disk.freeAfter(mac.identifier)
        macOSUsed = container.capacityUsed
        macOSMinFree = profile.partitioning.macOSMinFreeBytes
        step = Bytes.gb
        minimum = profile.minimumFootprint
        // macOS may shrink to used + headroom; everything else in the pool can go to SiliconForest.
        let macOSFloor = macOSUsed + macOSMinFree
        maximum = Bytes.alignDown(max(0, mac.size + freeAfterMacOS - macOSFloor), to: align)
        // Whole GB looks right in the editor.
        maximum = (maximum / Bytes.gb) * Bytes.gb
        recommended = min(max(profile.recommendedFootprint, minimum), maximum)
    }

    /// Size of the macOS container once SiliconForest takes `siliconForest` bytes of the pool.
    public func macOSSize(for siliconForest: Int64) -> Int64 {
        min(macOSPartition.size, pool - siliconForest)
    }

    public func clamp(_ size: Int64) -> Int64 {
        guard isFeasible else { return minimum }
        return min(max(size, minimum), maximum)
    }

    /// Snaps to whole gigabytes, keeping the exact min/max reachable.
    public func snap(_ size: Int64) -> Int64 {
        let c = clamp(size)
        if c == minimum || c == maximum { return c }
        let snapped = ((c + step / 2) / step) * step
        return clamp(snapped)
    }

    public struct Preset: Sendable, Hashable, Identifiable {
        public var id: String
        public var title: String
        public var size: Int64
    }

    public var presets: [Preset] {
        guard isFeasible else { return [] }
        var list: [Preset] = [
            .init(id: "min", title: "Minimum", size: minimum),
            .init(id: "recommended", title: "Recommended", size: recommended),
            .init(id: "half", title: "Split evenly", size: snap(pool / 2)),
            .init(id: "max", title: "Maximum", size: maximum),
        ]
        // Drop presets that collapse onto a neighbour on small disks.
        var seen = Set<Int64>()
        list = list.filter { seen.insert($0.size / Bytes.gb).inserted }
        return list
    }
}
