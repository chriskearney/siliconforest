// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// The grow planner. Given a clean, unmounted filesystem and a new size, it computes every block the
// grow writes, in memory, without writing anything. The method, derived from the format description:
//
//  1. New groups are appended. Their descriptors go into the next GDT blocks, which are the first
//     reserved GDT blocks (owned by the resize inode), so no existing block moves.
//  2. Each new group's bitmaps and inode table go where the flex_bg layout already puts its flex
//     group's metadata: block bitmaps at the flex group's base + i, inode bitmaps at base + flex + i,
//     inode tables after them. A block that is taken falls back to the first free run in the flex group.
//  3. New backup groups (sparse_super) get a superblock copy, a GDT copy and an empty reserved area.
//  4. The resize inode is rebuilt for the new geometry: one reserved GDT block fewer per GDT block
//     used, and every remaining reserved block lists its copies in the new backup groups as well.
//  5. The old last group's bitmap is widened, the superblock counts are updated, and every changed
//     structure gets its metadata_csum checksum.
//
// Writes come in three phases. "fresh" blocks are free in the old filesystem (or past its end), so
// writing them changes nothing the old filesystem sees. "commit" blocks are existing metadata; the
// executor saves them to the undo log first. "superblock" is the primary superblock, written last.

import Foundation

public struct GrowOptions {
    /// Filesystem size in blocks; nil fills the device.
    public var targetBlocks: UInt64?
    /// Zero the new groups' inode tables and mark them ITABLE_ZEROED (default). Off reproduces the
    /// lazy layout resize2fs leaves, for the differential test.
    public var zeroInodeTables: Bool
    /// Byte ranges no write may touch, such as the CHL-40 firmware and receipt slots.
    public var protectedRanges: [Range<UInt64>]
    public var now: UInt32
    /// Tests only: stop (as if the process died) after this phase's writes reach the disk.
    public var testStopAfter: WritePhase?

    public init(targetBlocks: UInt64? = nil, zeroInodeTables: Bool = true, protectedRanges: [Range<UInt64>] = [],
                now: UInt32 = UInt32(Date().timeIntervalSince1970)) {
        self.targetBlocks = targetBlocks
        self.zeroInodeTables = zeroInodeTables
        self.protectedRanges = protectedRanges
        self.now = now
    }
}

public enum WritePhase: Int, Comparable, Codable {
    case fresh = 0, commit = 1, superblock = 2
    public static func < (a: WritePhase, b: WritePhase) -> Bool { a.rawValue < b.rawValue }
}

public struct BlockWrite {
    public let block: UInt64
    public let bytes: [UInt8]
    public let phase: WritePhase
    public let what: String
}

public struct ZeroRun {
    public let start: UInt64
    public let count: Int
    public let what: String
}

public struct GrowPlan {
    public let oldGeo: Geometry
    public let newGeo: Geometry
    public let writes: [BlockWrite]
    public let zeroRuns: [ZeroRun]
    /// Old contents of every commit and superblock block, in write order.
    public let undo: [(UInt64, [UInt8])]
    public let newSuperblock: Superblock
    public let newDescs: [GroupDesc]
    public let oldBlock0: [UInt8]
    public let canonicalPlacement: Bool
    public let notes: [String]

    public var bytesWritten: UInt64 {
        UInt64(writes.count * oldGeo.blockSize) + zeroRuns.reduce(0) { $0 + UInt64($1.count * oldGeo.blockSize) }
    }
}

public enum GrowPlanner {
    /// Smallest last group kept: its backup area (if any) plus this many blocks; a smaller tail is left unused.
    public static let minLastGroupSpare = 50

    /// Returns nil when the filesystem already fills the target.
    public static func plan(_ vol: Ext4Volume, _ opt: GrowOptions) throws -> GrowPlan? {
        try vol.preflight()
        let old = vol.geo
        let bs = vol.blockSize
        let deviceBlocks = vol.device.byteSize / UInt64(bs)
        var target = opt.targetBlocks ?? deviceBlocks
        guard target <= deviceBlocks else {
            throw Ext4Error("target-too-small", "asked for \(target) blocks; \(vol.device.path) holds \(deviceBlocks)")
        }
        guard target >= old.blocks else {
            throw Ext4Error("shrink", "the filesystem has \(old.blocks) blocks and the target is \(target): shrinking is not supported")
        }
        var notes: [String] = []
        // Drop a last new group too small to be worth having.
        var newGeo = old.with(blocks: target)
        if newGeo.groups > old.groups {
            let last = newGeo.groups - 1
            let tail = newGeo.groupBlocks(last)
            // A last group must be able to hold its own backup area, bitmaps and inode table, plus
            // some data, even though flex_bg places its metadata elsewhere.
            if tail < newGeo.overhead(last) + vol.inodeTableBlocks + 2 + minLastGroupSpare {
                target -= UInt64(tail)
                notes.append("last group of \(tail) blocks dropped: too small to hold its metadata and data")
                newGeo = old.with(blocks: target)
            }
        }
        if target == old.blocks { return nil }
        guard newGeo.groups <= old.maxGroups else {
            throw Ext4Error("beyond-limit", "\(newGeo.groups) groups need more GDT blocks than the \(old.gdtPlusReserved) the filesystem reserved; the limit is \(UInt64(old.maxGroups) * old.blocksPerGroup) blocks")
        }
        guard UInt64(newGeo.groups) * UInt64(old.inodesPerGroup) <= UInt64(UInt32.max) else {
            throw Ext4Error("beyond-limit", "more than 2^32 inodes")
        }
        precondition(newGeo.gdtBlocks + newGeo.reservedGdt == old.gdtBlocks + old.reservedGdt)

        let oldMap = try vol.usedBlocks()
        var map = oldMap.extended(to: Int(target))
        let flex = 1 << Int(vol.sb.logGroupsPerFlex)
        let itb = vol.inodeTableBlocks
        let oldGroups = old.groups, newGroups = newGeo.groups

        // 3. Backup areas of new backup groups.
        for g in oldGroups..<newGroups where Geometry.hasBackup(g) {
            map.set(Int(newGeo.groupStart(g)), newGeo.overhead(g))
        }

        // 2. Place the new groups' bitmaps and inode tables.
        var descs = vol.descs
        var canonical = true
        var g = oldGroups
        while g < newGroups {
            let F = g / flex * flex
            let end = Swift.min(newGroups, F + flex)
            // A flex group that already exists keeps the spacing it was made with (mke2fs leaves room
            // for all `flex` groups); a new one is packed for the groups it has.
            let base: Int, spacing: Int, itBase: Int
            if F < oldGroups {
                base = Int(descs[F].blockBitmap)
                spacing = Int(descs[F].inodeBitmap) - base
                itBase = Int(descs[F].inodeTable)
            } else {
                base = Int(newGeo.groupStart(F)) + newGeo.overhead(F)
                // Packed for the groups it holds; a flex group of one keeps the full spacing
                // (both as resize2fs lays them out, observed with dumpe2fs).
                spacing = end - F == 1 ? flex : end - F
                itBase = base + 2 * spacing
            }
            let canonBB = { (h: Int) in base + (h - F) }
            let canonIB = { (h: Int) in base + spacing + (h - F) }
            let canonIT = { (h: Int) in itBase + (h - F) * itb }
            var useCanon = spacing >= end - F && (F..<Swift.max(F, Swift.min(oldGroups, F + flex))).allSatisfy { h in
                descs[h].blockBitmap == UInt64(canonBB(h)) && descs[h].inodeBitmap == UInt64(canonIB(h))
                    && descs[h].inodeTable == UInt64(canonIT(h))
            }
            for h in g..<end {
                func place(_ want: Int, _ len: Int, _ what: String) throws -> Int {
                    if useCanon, want + len <= Int(target), map.allClear(want, len) {
                        map.set(want, len); return want
                    }
                    useCanon = false
                    canonical = false
                    guard let at = map.firstClearRun(from: Int(newGeo.groupStart(F)), length: len, limit: Int(target)) else {
                        throw Ext4Error("no-space", "no room for group \(h)'s \(what)")
                    }
                    map.set(at, len)
                    return at
                }
                var d = GroupDesc()
                d.blockBitmap = UInt64(try place(canonBB(h), 1, "block bitmap"))
                d.inodeBitmap = UInt64(try place(canonIB(h), 1, "inode bitmap"))
                d.inodeTable = UInt64(try place(canonIT(h), itb, "inode table"))
                descs.append(d)
            }
            g = end
        }
        if !canonical { notes.append("some new metadata did not fit the flex_bg layout and went to the first free run") }

        // Group descriptors and bitmaps.
        var writes: [BlockWrite] = []
        var zeroRuns: [ZeroRun] = []
        let bpg = Int(old.blocksPerGroup)
        func bitmap(_ g: Int) -> [UInt8] {
            var b = [UInt8](repeating: 0, count: bs)
            let start = Int(newGeo.groupStart(g))
            let n = newGeo.groupBlocks(g)
            for i in 0..<(bs * 8) where i >= n || map.get(start + i) { b[i >> 3] |= 1 << UInt8(i & 7) }
            return b
        }
        for g in 0..<newGroups {
            let start = Int(newGeo.groupStart(g))
            let n = newGeo.groupBlocks(g)
            let used = map.countSet(start, n)
            if g < oldGroups {
                let widened = n != old.groupBlocks(g)
                let changed = widened || (0..<n).contains { oldMap.get(start + $0) != map.get(start + $0) }
                guard changed else { continue }
                if used == 0 && g != newGroups - 1 {
                    // Empty and no longer the last group: BLOCK_UNINIT, as resize2fs leaves it (the bitmap
                    // is then derived, so its block and checksum field are left as they were).
                    descs[g].flags |= BGFlag.blockUninit
                    descs[g].freeBlocks = UInt32(n)
                    continue
                }
                let bm = bitmap(g)
                descs[g].flags &= ~BGFlag.blockUninit
                descs[g].freeBlocks = UInt32(n - used)
                descs[g].blockBitmapCsum = CRC32C.update(vol.seed, bm[0..<(bpg / 8)])
                writes.append(BlockWrite(block: descs[g].blockBitmap, bytes: bm, phase: .commit, what: "block bitmap of group \(g)"))
            } else {
                var d = descs[g]
                d.freeBlocks = UInt32(n - used)
                d.freeInodes = old.inodesPerGroup
                d.itableUnused = old.inodesPerGroup
                d.flags = BGFlag.inodeUninit | (opt.zeroInodeTables ? BGFlag.itableZeroed : 0)
                if used == 0 && g != newGroups - 1 {
                    d.flags |= BGFlag.blockUninit
                } else {
                    let bm = bitmap(g)
                    d.blockBitmapCsum = CRC32C.update(vol.seed, bm[0..<(bpg / 8)])
                    writes.append(BlockWrite(block: d.blockBitmap, bytes: bm, phase: .fresh, what: "block bitmap of new group \(g)"))
                }
                if opt.zeroInodeTables {
                    zeroRuns.append(ZeroRun(start: d.inodeTable, count: itb, what: "inode table of new group \(g)"))
                }
                descs[g] = d
            }
        }
        for g in 0..<newGroups where g >= oldGroups || descs[g] != vol.descs[g] {
            descs[g].updateChecksum(seed: vol.seed, group: UInt32(g))
        }

        // The GDT image.
        var gdt = [UInt8](repeating: 0, count: newGeo.gdtBlocks * bs)
        for (g, d) in descs.enumerated() { gdt.replaceSubrange((g * 64)..<(g * 64 + 64), with: d.raw) }
        func gdtBlock(_ i: Int) -> [UInt8] { Array(gdt[(i * bs)..<((i + 1) * bs)]) }

        // 4. The resize inode.
        let riLoc = vol.inodeLocation(Ext4Volume.resizeIno)
        var ri = try vol.readInode(Ext4Volume.resizeIno)
        let dindBlock = UInt64(ri.le32(0x28 + 13 * 4))
        let layout = Ext4Volume.resizeInodeLayout(newGeo)
        ri.setLE32(0x1C, UInt32(layout.blocks512 & 0xffff_ffff))
        ri.setLE16(0x74, UInt16(layout.blocks512 >> 32))
        ri.setLE32(0x0C, opt.now)   // ctime
        ri.setLE32(0x10, opt.now)   // mtime
        let extra = vol.inodeSize > 128 ? Int(ri.le16(0x80)) : 0
        if extra >= 8 { ri.setLE32(0x84, 0) }
        if extra >= 12 { ri.setLE32(0x88, 0) }
        vol.setInodeChecksum(Ext4Volume.resizeIno, &ri)
        var itBlock = try vol.block(riLoc.block)
        itBlock.replaceSubrange(riLoc.offset..<(riLoc.offset + vol.inodeSize), with: ri)
        writes.append(BlockWrite(block: riLoc.block, bytes: itBlock, phase: .commit, what: "inode table block holding the resize inode"))
        writes.append(BlockWrite(block: dindBlock, bytes: layout.dind, phase: .commit, what: "resize inode double-indirect block"))
        for (p, b) in layout.ind {
            writes.append(BlockWrite(block: p, bytes: b, phase: .commit, what: "reserved GDT block \(p) (resize inode)"))
        }

        // 1. Primary GDT.
        for i in 0..<newGeo.gdtBlocks {
            writes.append(BlockWrite(block: 1 + UInt64(i), bytes: gdtBlock(i), phase: .commit, what: i < old.gdtBlocks ? "GDT block \(i)" : "GDT block \(i) (was reserved)"))
        }

        // 5. Superblock: counts, then the backups, then the primary.
        var nsb = vol.sb
        nsb.blocksCount = target
        let (hi, lo) = vol.sb.rBlocksCount.multipliedFullWidth(by: target)
        nsb.rBlocksCount = old.blocks.dividingFullWidth((high: hi, low: lo)).quotient
        nsb.freeBlocksCount = descs.reduce(0) { $0 + UInt64($1.freeBlocks) }
        nsb.inodesCount = UInt32(UInt64(newGroups) * UInt64(old.inodesPerGroup))
        nsb.freeInodesCount = UInt32(descs.reduce(0) { $0 + UInt64($1.freeInodes) })
        nsb.reservedGdtBlocks = UInt16(newGeo.reservedGdt)
        nsb.overheadClusters = 0
        nsb.wtime = opt.now

        // Backup groups: superblock copy, GDT copy, and (new groups only) an empty reserved area.
        var backupState = vol.sb.state
        if oldGroups > 1 {
            let b1 = try vol.block(old.groupStart(1))
            let s = Superblock(raw: Array(b1[0..<1024]))
            if s.magic == Superblock.magicValue { backupState = s.state }
        }
        var backupBlocks: [(Int, Bool)] = []   // (group, isNew)
        for g in newGeo.backupGroups {
            let gs = newGeo.groupStart(g)
            let isNew = g >= oldGroups
            backupBlocks.append((g, isNew))
            for i in 0..<newGeo.gdtBlocks {
                writes.append(BlockWrite(block: gs + 1 + UInt64(i), bytes: gdtBlock(i), phase: isNew ? .fresh : .commit, what: "GDT copy \(i) in group \(g)"))
            }
            if isNew {
                zeroRuns.append(ZeroRun(start: gs + 1 + UInt64(newGeo.gdtBlocks), count: newGeo.reservedGdt, what: "reserved GDT area of new group \(g)"))
            }
        }

        // kbytes_written covers everything this plan writes (each backup and the primary superblock included).
        let total = UInt64((writes.count + backupBlocks.count + 1) * bs) + zeroRuns.reduce(0) { $0 + UInt64($1.count * bs) }
        nsb.kbytesWritten = vol.sb.kbytesWritten + total / 1024
        var primary = nsb
        primary.updateChecksum()
        for (g, isNew) in backupBlocks {
            var s = nsb
            s.blockGroupNr = UInt16(g)
            s.state = backupState
            s.updateChecksum()
            let gs = newGeo.groupStart(g)
            var blk = isNew ? [UInt8](repeating: 0, count: bs) : try vol.block(gs)
            blk.replaceSubrange(0..<1024, with: s.raw)
            writes.append(BlockWrite(block: gs, bytes: blk, phase: isNew ? .fresh : .commit, what: "superblock copy in group \(g)"))
        }
        var block0 = try vol.block(0)
        let oldBlock0 = block0
        block0.replaceSubrange(1024..<2048, with: primary.raw)
        writes.append(BlockWrite(block: 0, bytes: block0, phase: .superblock, what: "primary superblock"))

        // Invariants, checked on the whole plan.
        var seen = Set<UInt64>()
        var undo: [(UInt64, [UInt8])] = []
        var kept: [BlockWrite] = []
        for w in writes.sorted(by: { ($0.phase, $0.block) < ($1.phase, $1.block) }) {
            guard seen.insert(w.block).inserted else { throw Ext4Error("plan-bug", "block \(w.block) written twice") }
            try checkWrite(w.block, 1, phase: w.phase, what: w.what, oldMap: oldMap, map: map, target: target, bs: bs, opt: opt)
            if w.phase != .fresh {
                let current = try vol.block(w.block)
                if current == w.bytes { continue }
                undo.append((w.block, current))
            }
            kept.append(w)
        }
        for z in zeroRuns {
            for b in z.start..<(z.start + UInt64(z.count)) where seen.contains(b) {
                throw Ext4Error("plan-bug", "block \(b) both written and zeroed")
            }
            try checkWrite(z.start, z.count, phase: .fresh, what: z.what, oldMap: oldMap, map: map, target: target, bs: bs, opt: opt)
        }
        return GrowPlan(oldGeo: old, newGeo: newGeo, writes: kept, zeroRuns: zeroRuns, undo: undo, newSuperblock: primary,
                        newDescs: descs, oldBlock0: oldBlock0, canonicalPlacement: canonical, notes: notes)
    }

    static func checkWrite(_ start: UInt64, _ n: Int, phase: WritePhase, what: String, oldMap: BitSet, map: BitSet,
                           target: UInt64, bs: Int, opt: GrowOptions) throws {
        let bytes = (start * UInt64(bs))..<((start + UInt64(n)) * UInt64(bs))
        for r in opt.protectedRanges where r.overlaps(bytes) {
            throw Ext4Error("protected-range", "\(what) would write bytes \(bytes) inside protected range \(r)")
        }
        for b in start..<(start + UInt64(n)) {
            guard b < target, map.get(Int(b)) else {
                throw Ext4Error("plan-bug", "\(what) writes block \(b), which the new filesystem does not use")
            }
            let wasUsed = b < UInt64(oldMap.count) && oldMap.get(Int(b))
            switch phase {
            case .fresh: guard !wasUsed else { throw Ext4Error("plan-bug", "\(what) would overwrite block \(b), in use before the grow") }
            case .commit, .superblock: guard wasUsed else { throw Ext4Error("plan-bug", "\(what) is not existing metadata (block \(b))") }
            }
        }
    }
}
