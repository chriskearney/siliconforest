// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// Reading one ext4 filesystem and deciding whether the grower may touch it. Everything here is
// read-only. `preflight()` is the full list of refusals; the grower runs it before planning and
// again on the result.

import Foundation

public final class Ext4Volume {
    public let device: BlockDevice
    public let sb: Superblock
    public let blockSize: Int
    public let geo: Geometry
    public let descs: [GroupDesc]
    public let seed: UInt32
    public let inodeSize: Int
    public let inodeTableBlocks: Int

    public static let resizeIno: UInt32 = 7
    public static let journalIno: UInt32 = 8
    static let extentsFlag: UInt32 = 0x80000

    public init(device: BlockDevice) throws {
        self.device = device
        let block0 = try device.read(offset: 0, count: 4096)
        let sb = Superblock(raw: Array(block0[1024..<2048]))
        guard sb.magic == Superblock.magicValue else { throw Ext4Error("not-ext4", "no ext4 superblock at byte 1024") }
        guard sb.revLevel >= 1 else { throw Ext4Error("unsupported-layout", "revision 0 filesystems are not supported") }
        guard sb.blockSize == 4096 else { throw Ext4Error("unsupported-layout", "block size \(sb.blockSize); only 4096 is supported") }
        guard sb.firstDataBlock == 0 else { throw Ext4Error("unsupported-layout", "first data block is not 0") }
        guard sb.logClusterSize == sb.logBlockSize, sb.clustersPerGroup == sb.blocksPerGroup else {
            throw Ext4Error("unsupported-feature", "clusters differ from blocks (bigalloc)")
        }
        let bpg = Int(sb.blocksPerGroup)
        guard bpg > 0, bpg % 8 == 0, bpg <= sb.blockSize * 8 else { throw Ext4Error("unsupported-layout", "blocks per group \(bpg)") }
        let ipg = Int(sb.inodesPerGroup)
        let isz = Int(sb.inodeSize)
        guard ipg > 0, ipg % 8 == 0, ipg <= sb.blockSize * 8 else { throw Ext4Error("unsupported-layout", "inodes per group \(ipg)") }
        guard isz >= 128, isz <= sb.blockSize, isz & (isz - 1) == 0, (ipg * isz) % sb.blockSize == 0 else {
            throw Ext4Error("unsupported-layout", "inode size \(isz)")
        }
        guard sb.featureIncompat & Feature.is64bit != 0, sb.descSize == 64 else {
            throw Ext4Error("unsupported-layout", "only 64bit filesystems with 64-byte group descriptors are supported")
        }
        self.sb = sb
        blockSize = sb.blockSize
        inodeSize = isz
        inodeTableBlocks = ipg * isz / sb.blockSize
        seed = sb.csumSeed
        let descPerBlock = sb.blockSize / 64
        let groups = Int((sb.blocksCount + UInt64(bpg) - 1) / UInt64(bpg))
        let gdtBlocks = (groups + descPerBlock - 1) / descPerBlock
        geo = Geometry(blocks: sb.blocksCount, blockSize: sb.blockSize, blocksPerGroup: UInt64(bpg), inodesPerGroup: sb.inodesPerGroup,
                       descPerBlock: descPerBlock, gdtPlusReserved: gdtBlocks + Int(sb.reservedGdtBlocks))
        guard device.byteSize >= sb.blocksCount * UInt64(sb.blockSize) else {
            throw Ext4Error("target-too-small", "the filesystem (\(sb.blocksCount) blocks) is larger than \(device.path)")
        }
        let gdt = try device.read(offset: UInt64(sb.blockSize), count: gdtBlocks * sb.blockSize)
        descs = (0..<groups).map { GroupDesc(raw: Array(gdt[($0 * 64)..<($0 * 64 + 64)])) }
    }

    public func block(_ b: UInt64) throws -> [UInt8] {
        try device.read(offset: b * UInt64(blockSize), count: blockSize)
    }

    // MARK: inodes

    public struct InodeLocation { public let block: UInt64; public let offset: Int }

    public func inodeLocation(_ ino: UInt32, descs: [GroupDesc]? = nil) -> InodeLocation {
        let idx = Int(ino - 1)
        let g = idx / Int(sb.inodesPerGroup)
        let within = (idx % Int(sb.inodesPerGroup)) * inodeSize
        let d = (descs ?? self.descs)[g]
        return InodeLocation(block: d.inodeTable + UInt64(within / blockSize), offset: within % blockSize)
    }

    public func readInode(_ ino: UInt32) throws -> [UInt8] {
        let loc = inodeLocation(ino)
        let b = try block(loc.block)
        return Array(b[loc.offset..<(loc.offset + inodeSize)])
    }

    func inodeHasChecksumHi(_ raw: [UInt8]) -> Bool { inodeSize > 128 && raw.le16(0x80) >= 4 }

    public func inodeChecksum(_ ino: UInt32, _ raw: [UInt8]) -> UInt32 {
        var c = raw
        c.setLE16(0x7C, 0)
        let hi = inodeHasChecksumHi(raw)
        if hi { c.setLE16(0x82, 0) }
        var crc = CRC32C.update(seed, le32: ino)
        crc = CRC32C.update(crc, le32: raw.le32(0x64))
        crc = CRC32C.update(crc, c)
        return hi ? crc : crc & 0xffff
    }

    public func storedInodeChecksum(_ raw: [UInt8]) -> UInt32 {
        UInt32(raw.le16(0x7C)) | (inodeHasChecksumHi(raw) ? UInt32(raw.le16(0x82)) << 16 : 0)
    }

    public func setInodeChecksum(_ ino: UInt32, _ raw: inout [UInt8]) {
        let c = inodeChecksum(ino, raw)
        raw.setLE16(0x7C, UInt16(c & 0xffff))
        if inodeHasChecksumHi(raw) { raw.setLE16(0x82, UInt16(c >> 16)) }
    }

    /// Physical block of logical block `logical` of an extent-mapped inode, or nil if unmapped.
    func extentLookup(_ inode: [UInt8], logical: UInt32) throws -> UInt64? {
        var node = Array(inode[0x28..<(0x28 + 60)])
        for _ in 0..<8 {
            guard node.le16(0) == 0xF30A else { throw Ext4Error("corrupt", "bad extent header") }
            let entries = Int(node.le16(2))
            let depth = node.le16(6)
            guard 12 + entries * 12 <= node.count else { throw Ext4Error("corrupt", "extent node overflows") }
            if depth == 0 {
                for i in 0..<entries {
                    let e = 12 + i * 12
                    let first = node.le32(e)
                    var len = UInt32(node.le16(e + 4))
                    if len > 32768 { len -= 32768 }
                    if logical >= first, logical < first + len {
                        let start = UInt64(node.le32(e + 8)) | UInt64(node.le16(e + 6)) << 32
                        return start + UInt64(logical - first)
                    }
                }
                return nil
            }
            var child: UInt64? = nil
            for i in 0..<entries {
                let e = 12 + i * 12
                if node.le32(e) <= logical { child = UInt64(node.le32(e + 4)) | UInt64(node.le16(e + 8)) << 32 }
            }
            guard let c = child else { return nil }
            node = try block(c)
        }
        throw Ext4Error("corrupt", "extent tree too deep")
    }

    // MARK: metadata the grower depends on

    /// Every metadata extent the descriptors name: (first block, count).
    func metadataExtents(_ ds: [GroupDesc]) -> [(UInt64, Int)] {
        ds.flatMap { [($0.blockBitmap, 1), ($0.inodeBitmap, 1), ($0.inodeTable, inodeTableBlocks)] }
    }

    /// The in-use map of the whole filesystem from its block bitmaps. A BLOCK_UNINIT group's map is
    /// derived (its backup area plus any metadata inside it). Checks each group's free count.
    func usedBlocks() throws -> BitSet {
        var map = BitSet(count: Int(geo.blocks))
        let meta = metadataExtents(descs)
        let bpg = Int(geo.blocksPerGroup)
        for (g, d) in descs.enumerated() {
            let start = Int(geo.groupStart(g))
            let n = geo.groupBlocks(g)
            if d.flags & BGFlag.blockUninit != 0 {
                map.set(start, geo.overhead(g))
                for (b, len) in meta {
                    let lo = Swift.max(Int(b), start), hi = Swift.min(Int(b) + len, start + n)
                    if lo < hi { map.set(lo, hi - lo) }
                }
            } else {
                let bm = try block(d.blockBitmap)
                for i in 0..<n where (bm[i >> 3] >> UInt8(i & 7)) & 1 != 0 { map.set(start + i) }
            }
            let used = map.countSet(start, n)
            if UInt32(n - used) != d.freeBlocks {
                throw Ext4Error("inconsistent", "group \(g): descriptor says \(d.freeBlocks) free blocks, bitmap says \(n - used)")
            }
            _ = bpg
        }
        return map
    }

    /// The resize inode's indirect blocks for a geometry: the double-indirect block lists every
    /// reserved GDT block P at the index P has within the GDT area (P - first GDT block, modulo
    /// block size / 4; read from the 0.1.0 root with debugfs), and block P lists P's copy in each backup
    /// group in group order (group b's copy is block b * blocks_per_group + P).
    public static func resizeInodeLayout(_ geo: Geometry, gdtStart: UInt64 = 1) -> (dind: [UInt8], ind: [(UInt64, [UInt8])], blocks512: UInt64) {
        let apb = geo.addrPerBlock
        var dind = [UInt8](repeating: 0, count: geo.blockSize)
        var ind: [(UInt64, [UInt8])] = []
        let backups = geo.backupGroups
        for r in 0..<geo.reservedGdt {
            let p = gdtStart + UInt64(geo.gdtBlocks + r)
            dind.setLE32(Int((p - gdtStart) % UInt64(apb)) * 4, UInt32(p))
            var b = [UInt8](repeating: 0, count: geo.blockSize)
            for (j, grp) in backups.enumerated() { b.setLE32(j * 4, UInt32(geo.groupStart(grp) + p)) }
            ind.append((p, b))
        }
        let blocks = UInt64(1 + geo.reservedGdt * (1 + backups.count))
        return (dind, ind, blocks * UInt64(geo.blockSize / 512))
    }

    // MARK: preflight

    public struct Report {
        public var lines: [String] = []
        public var freeBlocksFromGroups: UInt64 = 0
        public var freeInodesFromGroups: UInt64 = 0
    }

    /// Every refusal the grower knows. Throws the first problem found; returns facts otherwise.
    @discardableResult
    public func preflight() throws -> Report {
        var r = Report()
        let unsupported = [
            (sb.featureCompat & ~Feature.allowedCompat, Feature.compatNames),
            (sb.featureIncompat & ~Feature.allowedIncompat & ~Feature.recover, Feature.incompatNames),
            (sb.featureRoCompat & ~Feature.allowedRoCompat, Feature.roCompatNames),
        ].flatMap { Feature.names($0.0, $0.1) }
        guard unsupported.isEmpty else {
            throw Ext4Error("unsupported-feature", "features outside the supported set: \(unsupported.joined(separator: ", "))")
        }
        guard sb.featureCompat & Feature.requiredCompat == Feature.requiredCompat,
              sb.featureIncompat & Feature.requiredIncompat == Feature.requiredIncompat,
              sb.featureRoCompat & Feature.requiredRoCompat == Feature.requiredRoCompat else {
            throw Ext4Error("unsupported-feature", "needs resize_inode, 64bit, flex_bg, sparse_super and metadata_csum")
        }
        guard sb.featureIncompat & Feature.recover == 0 else {
            throw Ext4Error("journal-dirty", "the journal needs recovery (needs_recovery is set); run e2fsck or mount it in its own OS first")
        }
        guard sb.checksumType == 1 else { throw Ext4Error("unsupported-feature", "checksum type \(sb.checksumType)") }
        guard sb.computedChecksum() == sb.checksum else { throw Ext4Error("checksum", "superblock checksum mismatch") }
        guard sb.state & Superblock.stateValid != 0, sb.state & Superblock.stateError == 0 else {
            throw Ext4Error("not-clean", "filesystem state is \(sb.state), not clean")
        }
        guard sb.errorCount == 0 else { throw Ext4Error("not-clean", "filesystem records \(sb.errorCount) errors") }
        guard sb.lastOrphan == 0 else { throw Ext4Error("not-clean", "orphan list is not empty") }
        guard sb.snapshotInum == 0, sb.journalDev == 0 else { throw Ext4Error("unsupported-feature", "snapshot or external journal") }
        guard sb.logGroupsPerFlex >= 1, sb.logGroupsPerFlex <= 16 else { throw Ext4Error("unsupported-layout", "flex group size") }
        guard sb.reservedGdtBlocks > 0 else { throw Ext4Error("no-reserve", "no reserved GDT blocks: the filesystem cannot grow in place") }
        guard UInt64(sb.inodesCount) == UInt64(geo.groups) * UInt64(sb.inodesPerGroup) else {
            throw Ext4Error("inconsistent", "inode count does not match groups x inodes per group")
        }
        r.lines.append("features: \(sb.featureNames.joined(separator: " "))")

        // Group descriptors and bitmaps.
        let maxBlock = geo.blocks
        for (g, d) in descs.enumerated() {
            guard d.computedChecksum(seed: seed, group: UInt32(g)) == d.checksum else {
                throw Ext4Error("checksum", "group \(g) descriptor checksum mismatch")
            }
            guard d.flags & ~BGFlag.known == 0 else { throw Ext4Error("unsupported-feature", "group \(g) has unknown flags \(d.flags)") }
            guard d.excludeBitmap == 0 else { throw Ext4Error("unsupported-feature", "group \(g) has an exclude bitmap") }
            guard d.blockBitmap < maxBlock, d.inodeBitmap < maxBlock, d.inodeTable + UInt64(inodeTableBlocks) <= maxBlock else {
                throw Ext4Error("corrupt", "group \(g) metadata lies outside the filesystem")
            }
            if d.flags & BGFlag.blockUninit == 0 {
                let bm = try block(d.blockBitmap)
                let c = CRC32C.update(seed, bm[0..<(Int(geo.blocksPerGroup) / 8)])
                guard c == d.blockBitmapCsum else { throw Ext4Error("checksum", "group \(g) block bitmap checksum mismatch") }
            }
            if d.flags & BGFlag.inodeUninit == 0 {
                let bm = try block(d.inodeBitmap)
                let c = CRC32C.update(seed, bm[0..<(Int(sb.inodesPerGroup) / 8)])
                guard c == d.inodeBitmapCsum else { throw Ext4Error("checksum", "group \(g) inode bitmap checksum mismatch") }
            }
            r.freeBlocksFromGroups += UInt64(d.freeBlocks)
            r.freeInodesFromGroups += UInt64(d.freeInodes)
        }
        _ = try usedBlocks()
        if r.freeBlocksFromGroups != sb.freeBlocksCount || r.freeInodesFromGroups != UInt64(sb.freeInodesCount) {
            r.lines.append("note: superblock free counts differ from the groups' sums; the groups are used")
        }

        // The resize inode, exactly as this geometry expects it.
        let ri = try readInode(Ext4Volume.resizeIno)
        guard inodeChecksum(Ext4Volume.resizeIno, ri) == storedInodeChecksum(ri) else {
            throw Ext4Error("checksum", "resize inode checksum mismatch")
        }
        try checkResizeInode(ri)

        // The journal: clean, and no errors recorded.
        if sb.featureCompat & Feature.hasJournal != 0 {
            guard sb.journalInum == Ext4Volume.journalIno else { throw Ext4Error("unsupported-layout", "journal is not inode 8") }
            let ji = try readInode(Ext4Volume.journalIno)
            guard inodeChecksum(Ext4Volume.journalIno, ji) == storedInodeChecksum(ji) else {
                throw Ext4Error("checksum", "journal inode checksum mismatch")
            }
            guard ji.le32(0x20) & Ext4Volume.extentsFlag != 0, let jb = try extentLookup(ji, logical: 0) else {
                throw Ext4Error("unsupported-layout", "journal is not extent-mapped")
            }
            let js = try block(jb)
            guard js.be32(0) == 0xC03B_3998, [3, 4].contains(js.be32(4)) else { throw Ext4Error("corrupt", "no journal superblock") }
            guard js.be32(0x1C) == 0 else { throw Ext4Error("journal-dirty", "the journal holds transactions (s_start is not 0)") }
            guard js.be32(0x20) == 0 else { throw Ext4Error("journal-dirty", "the journal records an error") }
            r.lines.append("journal: clean")
        }
        r.lines.append("checksums: superblock, \(descs.count) group descriptors, bitmaps, resize and journal inodes all match")
        return r
    }

    func checkResizeInode(_ ri: [UInt8]) throws {
        let mode = ri.le16(0x0)
        guard mode & 0xF000 == 0x8000, ri.le32(0x20) & Ext4Volume.extentsFlag == 0 else {
            throw Ext4Error("resize-inode", "resize inode is not a block-mapped regular file")
        }
        let iblock = (0..<15).map { ri.le32(0x28 + $0 * 4) }
        guard iblock[0..<13].allSatisfy({ $0 == 0 }), iblock[14] == 0, iblock[13] != 0 else {
            throw Ext4Error("resize-inode", "resize inode uses blocks other than its double-indirect block")
        }
        let layout = Ext4Volume.resizeInodeLayout(geo)
        guard try block(UInt64(iblock[13])) == layout.dind else {
            throw Ext4Error("resize-inode", "resize inode's double-indirect block is not in the expected layout")
        }
        for (p, want) in layout.ind {
            guard try block(p) == want else { throw Ext4Error("resize-inode", "reserved GDT block \(p) does not list its backups as expected") }
        }
        let blocks512 = UInt64(ri.le32(0x1C)) | UInt64(ri.le16(0x74)) << 32
        guard blocks512 == layout.blocks512 else { throw Ext4Error("resize-inode", "resize inode block count \(blocks512), expected \(layout.blocks512)") }
    }
}
