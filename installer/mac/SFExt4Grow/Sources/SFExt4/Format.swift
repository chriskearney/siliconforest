// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// The parts of the ext4 on-disk format that the grower reads or writes, written from the published
// format description (the kernel's Documentation/filesystems/ext4 "Data Structures and Algorithms"
// pages). Field offsets are given in hex as that description lists them. No e2fsprogs or kernel
// code was used.

public enum Feature {
    // s_feature_compat
    public static let hasJournal: UInt32 = 0x4
    public static let extAttr: UInt32 = 0x8
    public static let resizeInode: UInt32 = 0x10
    public static let dirIndex: UInt32 = 0x20
    // s_feature_incompat
    public static let filetype: UInt32 = 0x2
    public static let recover: UInt32 = 0x4
    public static let extents: UInt32 = 0x40
    public static let is64bit: UInt32 = 0x80
    public static let flexBg: UInt32 = 0x200
    public static let csumSeed: UInt32 = 0x2000
    // s_feature_ro_compat
    public static let sparseSuper: UInt32 = 0x1
    public static let largeFile: UInt32 = 0x2
    public static let hugeFile: UInt32 = 0x8
    public static let dirNlink: UInt32 = 0x20
    public static let extraIsize: UInt32 = 0x40
    public static let metadataCsum: UInt32 = 0x400

    /// What the SiliconForest 0.1.0 root uses (dumpe2fs, 24 Nov 2026), and nothing else.
    public static let allowedCompat: UInt32 = hasJournal | extAttr | resizeInode | dirIndex
    public static let allowedIncompat: UInt32 = filetype | extents | is64bit | flexBg | csumSeed
    public static let allowedRoCompat: UInt32 = sparseSuper | largeFile | hugeFile | dirNlink | extraIsize | metadataCsum
    /// Required: the grower's layout logic assumes each of these.
    public static let requiredCompat: UInt32 = resizeInode
    public static let requiredIncompat: UInt32 = is64bit | flexBg
    public static let requiredRoCompat: UInt32 = sparseSuper | metadataCsum

    static let compatNames: [(UInt32, String)] = [(0x1, "dir_prealloc"), (0x2, "imagic_inodes"), (0x4, "has_journal"),
        (0x8, "ext_attr"), (0x10, "resize_inode"), (0x20, "dir_index"), (0x40, "lazy_bg"), (0x100, "exclude_bitmap"),
        (0x200, "sparse_super2"), (0x400, "fast_commit"), (0x800, "stable_inodes"), (0x1000, "orphan_file")]
    static let incompatNames: [(UInt32, String)] = [(0x1, "compression"), (0x2, "filetype"), (0x4, "needs_recovery"),
        (0x8, "journal_dev"), (0x10, "meta_bg"), (0x40, "extent"), (0x80, "64bit"), (0x100, "mmp"), (0x200, "flex_bg"),
        (0x400, "ea_inode"), (0x1000, "dirdata"), (0x2000, "metadata_csum_seed"), (0x4000, "large_dir"),
        (0x8000, "inline_data"), (0x10000, "encrypt"), (0x20000, "casefold")]
    static let roCompatNames: [(UInt32, String)] = [(0x1, "sparse_super"), (0x2, "large_file"), (0x4, "btree_dir"),
        (0x8, "huge_file"), (0x10, "uninit_bg"), (0x20, "dir_nlink"), (0x40, "extra_isize"), (0x80, "snapshot"),
        (0x100, "quota"), (0x200, "bigalloc"), (0x400, "metadata_csum"), (0x800, "replica"), (0x1000, "read-only"),
        (0x2000, "project"), (0x4000, "shared_blocks"), (0x8000, "verity"), (0x10000, "orphan_present")]

    static func names(_ bits: UInt32, _ table: [(UInt32, String)]) -> [String] {
        var out: [String] = []
        var rest = bits
        for (b, n) in table where bits & b != 0 { out.append(n); rest &= ~b }
        if rest != 0 { out.append(String(format: "unknown(0x%x)", rest)) }
        return out
    }
}

public enum BGFlag {
    public static let inodeUninit: UInt16 = 0x1
    public static let blockUninit: UInt16 = 0x2
    public static let itableZeroed: UInt16 = 0x4
    public static let known: UInt16 = 0x7
}

/// The 1024-byte superblock, kept as raw bytes so that every field we do not touch round-trips exactly.
public struct Superblock: Equatable {
    public static let size = 1024
    public static let magicValue: UInt16 = 0xEF53
    public static let stateValid: UInt16 = 0x1
    public static let stateError: UInt16 = 0x2

    public var raw: [UInt8]
    public init(raw: [UInt8]) { precondition(raw.count == Superblock.size); self.raw = raw }

    public var inodesCount: UInt32 { get { raw.le32(0x0) } set { raw.setLE32(0x0, newValue) } }
    public var blocksCount: UInt64 {
        get { UInt64(raw.le32(0x4)) | UInt64(raw.le32(0x150)) << 32 }
        set { raw.setLE32(0x4, UInt32(newValue & 0xffff_ffff)); raw.setLE32(0x150, UInt32(newValue >> 32)) }
    }
    public var rBlocksCount: UInt64 {
        get { UInt64(raw.le32(0x8)) | UInt64(raw.le32(0x154)) << 32 }
        set { raw.setLE32(0x8, UInt32(newValue & 0xffff_ffff)); raw.setLE32(0x154, UInt32(newValue >> 32)) }
    }
    public var freeBlocksCount: UInt64 {
        get { UInt64(raw.le32(0xC)) | UInt64(raw.le32(0x158)) << 32 }
        set { raw.setLE32(0xC, UInt32(newValue & 0xffff_ffff)); raw.setLE32(0x158, UInt32(newValue >> 32)) }
    }
    public var freeInodesCount: UInt32 { get { raw.le32(0x10) } set { raw.setLE32(0x10, newValue) } }
    public var firstDataBlock: UInt32 { raw.le32(0x14) }
    public var logBlockSize: UInt32 { raw.le32(0x18) }
    public var logClusterSize: UInt32 { raw.le32(0x1C) }
    public var blocksPerGroup: UInt32 { raw.le32(0x20) }
    public var clustersPerGroup: UInt32 { raw.le32(0x24) }
    public var inodesPerGroup: UInt32 { raw.le32(0x28) }
    public var wtime: UInt32 { get { raw.le32(0x30) } set { raw.setLE32(0x30, newValue) } }
    public var magic: UInt16 { raw.le16(0x38) }
    public var state: UInt16 { get { raw.le16(0x3A) } set { raw.setLE16(0x3A, newValue) } }
    public var revLevel: UInt32 { raw.le32(0x4C) }
    public var firstIno: UInt32 { raw.le32(0x54) }
    public var inodeSize: UInt16 { raw.le16(0x58) }
    public var blockGroupNr: UInt16 { get { raw.le16(0x5A) } set { raw.setLE16(0x5A, newValue) } }
    public var featureCompat: UInt32 { raw.le32(0x5C) }
    public var featureIncompat: UInt32 { raw.le32(0x60) }
    public var featureRoCompat: UInt32 { raw.le32(0x64) }
    public var uuid: [UInt8] { Array(raw[0x68..<0x78]) }
    public var volumeName: String {
        String(decoding: raw[0x78..<0x88].prefix { $0 != 0 }, as: UTF8.self)
    }
    public var reservedGdtBlocks: UInt16 { get { raw.le16(0xCE) } set { raw.setLE16(0xCE, newValue) } }
    public var journalInum: UInt32 { raw.le32(0xE0) }
    public var journalDev: UInt32 { raw.le32(0xE4) }
    public var lastOrphan: UInt32 { raw.le32(0xE8) }
    public var descSize: UInt16 { raw.le16(0xFE) }
    public var firstMetaBg: UInt32 { raw.le32(0x104) }
    public var logGroupsPerFlex: UInt8 { raw[0x174] }
    public var checksumType: UInt8 { raw[0x175] }
    public var kbytesWritten: UInt64 { get { raw.le64(0x178) } set { raw.setLE64(0x178, newValue) } }
    public var snapshotInum: UInt32 { raw.le32(0x180) }
    public var errorCount: UInt32 { raw.le32(0x194) }
    public var overheadClusters: UInt32 { get { raw.le32(0x248) } set { raw.setLE32(0x248, newValue) } }
    public var checksumSeedField: UInt32 { raw.le32(0x270) }
    public var checksum: UInt32 { get { raw.le32(0x3FC) } set { raw.setLE32(0x3FC, newValue) } }

    public var blockSize: Int { 1024 << Int(logBlockSize) }
    public var hasMetadataCsum: Bool { featureRoCompat & Feature.metadataCsum != 0 }

    public func computedChecksum() -> UInt32 { CRC32C.update(0xffff_ffff, raw[0..<0x3FC]) }
    public mutating func updateChecksum() { checksum = computedChecksum() }

    /// The seed every other metadata checksum starts from.
    public var csumSeed: UInt32 {
        featureIncompat & Feature.csumSeed != 0 ? checksumSeedField : CRC32C.update(0xffff_ffff, uuid)
    }

    public var featureNames: [String] {
        Feature.names(featureCompat, Feature.compatNames) + Feature.names(featureIncompat, Feature.incompatNames)
            + Feature.names(featureRoCompat, Feature.roCompatNames)
    }
}

/// One 64-byte group descriptor (64bit feature).
public struct GroupDesc: Equatable {
    public static let size = 64
    public var raw: [UInt8]
    public init(raw: [UInt8]) { precondition(raw.count == GroupDesc.size); self.raw = raw }
    public init() { raw = [UInt8](repeating: 0, count: GroupDesc.size) }

    private func lohi32(_ lo: Int, _ hi: Int) -> UInt64 { UInt64(raw.le32(lo)) | UInt64(raw.le32(hi)) << 32 }
    private mutating func setLohi32(_ lo: Int, _ hi: Int, _ v: UInt64) {
        raw.setLE32(lo, UInt32(v & 0xffff_ffff)); raw.setLE32(hi, UInt32(v >> 32))
    }
    private func lohi16(_ lo: Int, _ hi: Int) -> UInt32 { UInt32(raw.le16(lo)) | UInt32(raw.le16(hi)) << 16 }
    private mutating func setLohi16(_ lo: Int, _ hi: Int, _ v: UInt32) {
        raw.setLE16(lo, UInt16(v & 0xffff)); raw.setLE16(hi, UInt16(v >> 16))
    }

    public var blockBitmap: UInt64 { get { lohi32(0x0, 0x20) } set { setLohi32(0x0, 0x20, newValue) } }
    public var inodeBitmap: UInt64 { get { lohi32(0x4, 0x24) } set { setLohi32(0x4, 0x24, newValue) } }
    public var inodeTable: UInt64 { get { lohi32(0x8, 0x28) } set { setLohi32(0x8, 0x28, newValue) } }
    public var freeBlocks: UInt32 { get { lohi16(0xC, 0x2C) } set { setLohi16(0xC, 0x2C, newValue) } }
    public var freeInodes: UInt32 { get { lohi16(0xE, 0x2E) } set { setLohi16(0xE, 0x2E, newValue) } }
    public var usedDirs: UInt32 { get { lohi16(0x10, 0x30) } set { setLohi16(0x10, 0x30, newValue) } }
    public var flags: UInt16 { get { raw.le16(0x12) } set { raw.setLE16(0x12, newValue) } }
    public var excludeBitmap: UInt64 { lohi32(0x14, 0x34) }
    public var blockBitmapCsum: UInt32 { get { lohi16(0x18, 0x38) } set { setLohi16(0x18, 0x38, newValue) } }
    public var inodeBitmapCsum: UInt32 { get { lohi16(0x1A, 0x3A) } set { setLohi16(0x1A, 0x3A, newValue) } }
    public var itableUnused: UInt32 { get { lohi16(0x1C, 0x32) } set { setLohi16(0x1C, 0x32, newValue) } }
    public var checksum: UInt16 { get { raw.le16(0x1E) } set { raw.setLE16(0x1E, newValue) } }

    public func computedChecksum(seed: UInt32, group: UInt32) -> UInt16 {
        var copy = raw
        copy.setLE16(0x1E, 0)
        return UInt16(CRC32C.update(CRC32C.update(seed, le32: group), copy) & 0xffff)
    }
    public mutating func updateChecksum(seed: UInt32, group: UInt32) {
        checksum = computedChecksum(seed: seed, group: group)
    }
}

/// Group arithmetic for one block count. Only first_data_block 0 and 4 KiB blocks are supported.
public struct Geometry: Equatable {
    public let blocks: UInt64
    public let blockSize: Int
    public let blocksPerGroup: UInt64
    public let inodesPerGroup: UInt32
    public let descPerBlock: Int
    public let gdtPlusReserved: Int   // constant across a grow: GDT blocks + reserved GDT blocks

    public init(blocks: UInt64, blockSize: Int, blocksPerGroup: UInt64, inodesPerGroup: UInt32, descPerBlock: Int, gdtPlusReserved: Int) {
        self.blocks = blocks; self.blockSize = blockSize; self.blocksPerGroup = blocksPerGroup
        self.inodesPerGroup = inodesPerGroup; self.descPerBlock = descPerBlock; self.gdtPlusReserved = gdtPlusReserved
    }

    public var groups: Int { Int((blocks + blocksPerGroup - 1) / blocksPerGroup) }
    public var gdtBlocks: Int { (groups + descPerBlock - 1) / descPerBlock }
    public var reservedGdt: Int { gdtPlusReserved - gdtBlocks }
    public var addrPerBlock: Int { blockSize / 4 }

    public func groupStart(_ g: Int) -> UInt64 { UInt64(g) * blocksPerGroup }
    public func groupBlocks(_ g: Int) -> Int {
        let start = groupStart(g)
        return Int(Swift.min(blocksPerGroup, blocks - start))
    }
    /// sparse_super: groups 0 and 1, and powers of 3, 5 and 7.
    public static func hasBackup(_ g: Int) -> Bool {
        if g <= 1 { return true }
        for base in [3, 5, 7] {
            var p = base
            while p < g { p *= base }
            if p == g { return true }
        }
        return false
    }
    public var backupGroups: [Int] { (1..<groups).filter { Geometry.hasBackup($0) } }
    /// Superblock + GDT + reserved GDT blocks at the start of a backup group.
    public func overhead(_ g: Int) -> Int { Geometry.hasBackup(g) ? 1 + gdtPlusReserved : 0 }

    /// The most groups the GDT plus its reserve can describe: the growth limit.
    public var maxGroups: Int { gdtPlusReserved * descPerBlock }

    public func with(blocks newBlocks: UInt64) -> Geometry {
        Geometry(blocks: newBlocks, blockSize: blockSize, blocksPerGroup: blocksPerGroup, inodesPerGroup: inodesPerGroup,
                 descPerBlock: descPerBlock, gdtPlusReserved: gdtPlusReserved)
    }
}
