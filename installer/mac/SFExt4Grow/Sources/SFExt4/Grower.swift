// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// The ordered executor and its undo log.
//
// Order of writes, and why a crash at any point is recoverable:
//   0. Preflight and plan (read-only). Any refusal leaves the target byte-for-byte untouched.
//   1. The undo log (old contents of every existing block the grow rewrites) is written next to the
//      target, SHA-256 sealed and fsynced, with its directory, before the target is opened for writing.
//   2. "fresh" blocks: new groups' bitmaps, zeroed inode tables, new backup groups. All are free in the
//      old filesystem or past its end, so the old filesystem is still exactly what it was. F_FULLFSYNC.
//   3. "commit" blocks: GDT (including reserved blocks turned into GDT), backup GDTs and superblocks in
//      old groups, the resize inode, the old last group's bitmap. F_FULLFSYNC.
//   4. The primary superblock. F_FULLFSYNC.
//   5. The result is re-read and must pass the same preflight; protected ranges are re-hashed.
//   6. The undo log is removed.
// A crash in 1 or 2: the filesystem is unchanged (the log may exist; `undo` is harmless).
// A crash in 3 to 5: `sf-ext4grow undo` writes the old blocks back; the filesystem is then the old one,
// block for block in everything it uses. `grow` refuses to start while an undo log exists.

import CryptoKit
import Foundation

public enum UndoLog {
    static let magic = Array("SFEXT4GROW-UNDO1".utf8)

    public struct Contents {
        public let blockSize: Int
        public let oldBlocks: UInt64
        public let newBlocks: UInt64
        public let uuid: [UInt8]
        public let records: [(UInt64, [UInt8])]
        public init(blockSize: Int, oldBlocks: UInt64, newBlocks: UInt64, uuid: [UInt8], records: [(UInt64, [UInt8])]) {
            self.blockSize = blockSize; self.oldBlocks = oldBlocks; self.newBlocks = newBlocks; self.uuid = uuid; self.records = records
        }
    }

    public static func encode(_ c: Contents) -> [UInt8] {
        var out = magic
        var h = [UInt8](repeating: 0, count: 40)
        h.setLE32(0, UInt32(c.blockSize))
        h.setLE32(4, UInt32(c.records.count))
        h.setLE64(8, c.oldBlocks)
        h.setLE64(16, c.newBlocks)
        h.replaceSubrange(24..<40, with: c.uuid)
        out += h
        for (b, bytes) in c.records {
            var n = [UInt8](repeating: 0, count: 8)
            n.setLE64(0, b)
            out += n
            out += bytes
        }
        out += Array(SHA256.hash(data: out))
        return out
    }

    public static func decode(_ d: [UInt8]) throws -> Contents {
        guard d.count >= 16 + 40 + 32, Array(d[0..<16]) == magic else { throw Ext4Error("undo-log", "not an sf-ext4grow undo log") }
        let body = d[0..<(d.count - 32)]
        guard Array(SHA256.hash(data: body)) == Array(d[(d.count - 32)...]) else {
            throw Ext4Error("undo-log", "undo log is incomplete or damaged (SHA-256 mismatch)")
        }
        let h = Array(d[16..<56])
        let bs = Int(h.le32(0)), n = Int(h.le32(4))
        guard bs == 4096, d.count == 56 + n * (8 + bs) + 32 else { throw Ext4Error("undo-log", "undo log has the wrong length") }
        var recs: [(UInt64, [UInt8])] = []
        var o = 56
        for _ in 0..<n {
            let b = Array(d[o..<(o + 8)]).le64(0)
            recs.append((b, Array(d[(o + 8)..<(o + 8 + bs)])))
            o += 8 + bs
        }
        return Contents(blockSize: bs, oldBlocks: h.le64(8), newBlocks: h.le64(16), uuid: Array(h[24..<40]), records: recs)
    }
}

public struct GrowResult {
    public let alreadyGrown: Bool
    public let oldBlocks: UInt64
    public let newBlocks: UInt64
    public let oldGroups: Int
    public let newGroups: Int
    public let blocksWritten: Int
    public let blocksZeroed: Int
    public let bytesWritten: UInt64
    public let canonicalPlacement: Bool
    public let notes: [String]
    /// Every block the grow wrote, with its phase, for the differential and slot checks.
    public let writeMap: [(UInt64, Int, WritePhase, String)]
}

public enum Grower {
    static func fsyncDirectory(of path: String) {
        let dir = (path as NSString).deletingLastPathComponent
        let fd = open(dir.isEmpty ? "." : dir, O_RDONLY)
        if fd >= 0 { _ = fcntl(fd, F_FULLFSYNC); fsync(fd); close(fd) }
    }

    static func hashRanges(_ dev: BlockDevice, _ ranges: [Range<UInt64>]) throws -> [[UInt8]] {
        try ranges.map { r in
            var h = SHA256()
            var o = r.lowerBound
            while o < r.upperBound {
                let n = Int(Swift.min(UInt64(1 << 20), r.upperBound - o))
                h.update(data: try dev.read(offset: o, count: n))
                o += UInt64(n)
            }
            return Array(h.finalize())
        }
    }

    /// Plans without writing.
    public static func plan(device: BlockDevice, options: GrowOptions) throws -> GrowPlan? {
        try GrowPlanner.plan(Ext4Volume(device: device), options)
    }

    public static func grow(device: BlockDevice, options: GrowOptions, undoLogPath: String, keepUndoLog: Bool = false,
                            log: (String) -> Void = { _ in }) throws -> GrowResult {
        if FileManager.default.fileExists(atPath: undoLogPath) {
            throw Ext4Error("interrupted", "an undo log exists at \(undoLogPath): a previous grow did not finish. Run `sf-ext4grow undo` first")
        }
        let vol = try Ext4Volume(device: device)
        guard let plan = try GrowPlanner.plan(vol, options) else {
            log("already grown: \(vol.geo.blocks) blocks fill the target")
            return GrowResult(alreadyGrown: true, oldBlocks: vol.geo.blocks, newBlocks: vol.geo.blocks, oldGroups: vol.geo.groups,
                              newGroups: vol.geo.groups, blocksWritten: 0, blocksZeroed: 0, bytesWritten: 0, canonicalPlacement: true,
                              notes: [], writeMap: [])
        }
        let bs = UInt64(vol.blockSize)
        let protectedBefore = try hashRanges(device, options.protectedRanges)

        // 1. Undo log.
        let undo = UndoLog.encode(.init(blockSize: vol.blockSize, oldBlocks: plan.oldGeo.blocks, newBlocks: plan.newGeo.blocks,
                                        uuid: vol.sb.uuid, records: plan.undo))
        guard FileManager.default.createFile(atPath: undoLogPath, contents: Data(undo)) else {
            throw Ext4Error("undo-log", "cannot write the undo log at \(undoLogPath)")
        }
        let lfd = open(undoLogPath, O_RDONLY)
        if lfd >= 0 { _ = fcntl(lfd, F_FULLFSYNC); fsync(lfd); close(lfd) }
        fsyncDirectory(of: undoLogPath)
        log("undo log: \(plan.undo.count) blocks saved to \(undoLogPath)")

        // The target must not have changed since it was planned.
        guard try device.read(offset: 0, count: vol.blockSize) == plan.oldBlock0 else {
            try? FileManager.default.removeItem(atPath: undoLogPath)
            throw Ext4Error("changed", "the superblock changed while planning; nothing was written")
        }

        // 2. Fresh blocks.
        let zero = [UInt8](repeating: 0, count: 1 << 20)
        for z in plan.zeroRuns {
            var left = z.count * Int(bs)
            var off = z.start * bs
            while left > 0 {
                let n = Swift.min(left, zero.count)
                try device.write(offset: off, bytes: n == zero.count ? zero : Array(zero[0..<n]))
                off += UInt64(n); left -= n
            }
        }
        for w in plan.writes where w.phase == .fresh { try device.write(offset: w.block * bs, bytes: w.bytes) }
        try device.sync()
        if options.testStopAfter == .fresh { throw Ext4Error("test-stop", "stopped after the fresh phase (test)") }
        log("fresh: \(plan.writes.filter { $0.phase == .fresh }.count) blocks written, \(plan.zeroRuns.reduce(0) { $0 + $1.count }) zeroed")
        // 3. Commit blocks.
        for w in plan.writes where w.phase == .commit { try device.write(offset: w.block * bs, bytes: w.bytes) }
        try device.sync()
        if options.testStopAfter == .commit { throw Ext4Error("test-stop", "stopped after the commit phase (test)") }
        log("commit: \(plan.writes.filter { $0.phase == .commit }.count) metadata blocks written")
        // 4. Primary superblock.
        for w in plan.writes where w.phase == .superblock { try device.write(offset: w.block * bs, bytes: w.bytes) }
        try device.sync()
        log("superblock: \(plan.newGeo.blocks) blocks")

        // 5. Verify.
        let after = try Ext4Volume(device: device)
        try after.preflight()
        guard after.geo.blocks == plan.newGeo.blocks, after.descs == plan.newDescs else {
            throw Ext4Error("verify", "the filesystem read back is not the one planned; the undo log is kept at \(undoLogPath)")
        }
        guard try hashRanges(device, options.protectedRanges) == protectedBefore else {
            throw Ext4Error("verify", "a protected range changed; the undo log is kept at \(undoLogPath)")
        }
        log("verified: preflight passes on the result, protected ranges unchanged")
        // 6. Done.
        if !keepUndoLog { try? FileManager.default.removeItem(atPath: undoLogPath); fsyncDirectory(of: undoLogPath) }

        let map = plan.writes.map { ($0.block, 1, $0.phase, $0.what) } + plan.zeroRuns.map { ($0.start, $0.count, WritePhase.fresh, $0.what) }
        return GrowResult(alreadyGrown: false, oldBlocks: plan.oldGeo.blocks, newBlocks: plan.newGeo.blocks, oldGroups: plan.oldGeo.groups,
                          newGroups: plan.newGeo.groups, blocksWritten: plan.writes.count, blocksZeroed: plan.zeroRuns.reduce(0) { $0 + $1.count },
                          bytesWritten: plan.bytesWritten, canonicalPlacement: plan.canonicalPlacement, notes: plan.notes, writeMap: map)
    }

    /// Puts back every block an interrupted grow saved. Safe to run more than once.
    public static func undo(device: BlockDevice, undoLogPath: String, log: (String) -> Void = { _ in }) throws {
        guard let data = FileManager.default.contents(atPath: undoLogPath) else {
            throw Ext4Error("undo-log", "no undo log at \(undoLogPath)")
        }
        let c = try UndoLog.decode(Array(data))
        let block0 = try device.read(offset: 0, count: 4096)
        guard Array(block0[(1024 + 0x68)..<(1024 + 0x78)]) == c.uuid else {
            throw Ext4Error("undo-log", "the undo log belongs to another filesystem (UUID differs)")
        }
        // Superblock last, as in the grow.
        let ordered = c.records.filter { $0.0 != 0 } + c.records.filter { $0.0 == 0 }
        for (b, bytes) in ordered { try device.write(offset: b * UInt64(c.blockSize), bytes: bytes) }
        try device.sync()
        let vol = try Ext4Volume(device: device)
        try vol.preflight()
        guard vol.geo.blocks == c.oldBlocks else { throw Ext4Error("undo-log", "after undo the filesystem has \(vol.geo.blocks) blocks, expected \(c.oldBlocks)") }
        log("undo: \(c.records.count) blocks restored; the filesystem is back to \(c.oldBlocks) blocks and passes preflight")
        try FileManager.default.removeItem(atPath: undoLogPath)
        fsyncDirectory(of: undoLogPath)
    }
}
