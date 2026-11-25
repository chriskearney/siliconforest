// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// Framework-free checks of the pure parts (Command Line Tools Macs have no XCTest). The image tests,
// with e2fsprogs as the external oracle, are scripts/oracle-test.sh.

import Foundation
import SFExt4

var failures = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if ok { print("ok   \(what)") } else { print("FAIL \(what) (line \(line))"); failures += 1 }
}

// CRC32C: the standard check value for "123456789" is 0xE3069283 with ~0 in and ~ out.
check(~CRC32C.update(0xffff_ffff, Array("123456789".utf8)) == 0xE306_9283, "crc32c check value")
check(CRC32C.update(CRC32C.update(0xffff_ffff, [1, 2]), [3, 4]) == CRC32C.update(0xffff_ffff, [1, 2, 3, 4]), "crc32c is incremental")

// sparse_super backup groups.
let backups = (0..<800).filter { Geometry.hasBackup($0) }
check(backups == [0, 1, 3, 5, 7, 9, 25, 27, 49, 81, 125, 243, 343, 625, 729], "backup groups below 800: \(backups)")

// The real 0.1.0 root's geometry, and the 96 GiB target.
let g0 = Geometry(blocks: 530_524, blockSize: 4096, blocksPerGroup: 32768, inodesPerGroup: 6640, descPerBlock: 64, gdtPlusReserved: 260)
check(g0.groups == 17 && g0.gdtBlocks == 1 && g0.reservedGdt == 259, "0.1.0 root: 17 groups, 1 GDT block, 259 reserved")
check(UInt64(g0.maxGroups) * g0.blocksPerGroup * 4096 == 2_233_382_993_920, "growth limit equals root.json grow.max_bytes")
let g1 = g0.with(blocks: 25_165_824)
check(g1.groups == 768 && g1.gdtBlocks == 12 && g1.reservedGdt == 248, "96 GiB: 768 groups, 12 GDT blocks, 248 reserved")
check(g1.overhead(25) == 261 && g1.overhead(26) == 0, "backup area is 261 blocks")

// Resize inode layout for the 0.1.0 root, as read from it with debugfs: DIND[P - 1] = P, block 2 lists 32770, 98306, ...
let lay = Ext4Volume.resizeInodeLayout(g0)
check(lay.dind.le32(0) == 0 && lay.dind.le32(1 * 4) == 2 && lay.dind.le32(259 * 4) == 260 && lay.dind.le32(260 * 4) == 0, "DIND[i] = GDT-area block i + 1, for 2...260")
check(lay.ind.first!.0 == 2 && lay.ind.first!.1.le32(0) == 32770 && lay.ind.first!.1.le32(16) == 294_914 && lay.ind.first!.1.le32(20) == 0,
      "reserved block 2 lists its copies in groups 1, 3, 5, 7, 9")
check(lay.blocks512 == 12440, "resize inode i_blocks 12440 (debugfs Blockcount)")
check(Ext4Volume.resizeInodeLayout(g1).blocks512 == 29768, "after 96 GiB: 29768 (resize2fs result)")

// Undo log round trip and damage detection.
let rec: [(UInt64, [UInt8])] = [(0, [UInt8](repeating: 7, count: 4096)), (5, [UInt8](repeating: 9, count: 4096))]
var enc = UndoLog.encode(.init(blockSize: 4096, oldBlocks: 10, newBlocks: 20, uuid: [UInt8](repeating: 1, count: 16), records: rec))
let dec = try UndoLog.decode(enc)
check(dec.records.count == 2 && dec.records[1].0 == 5 && dec.records[1].1 == rec[1].1 && dec.newBlocks == 20, "undo log round trip")
enc[100] ^= 1
check((try? UndoLog.decode(enc)) == nil, "a damaged undo log is refused")
check((try? UndoLog.decode(Array(enc.prefix(enc.count - 10)))) == nil, "a truncated undo log is refused")

// Target names.
check(TargetGuard.parse("/dev/rdisk8s2")! == ("disk8", "disk8s2"), "parse /dev/rdisk8s2")
check(TargetGuard.parse("/dev/disk12")! == ("disk12", "disk12"), "parse /dev/disk12")
check(TargetGuard.parse("/dev/null") == nil && TargetGuard.parse("/dev/disk") == nil && TargetGuard.parse("/dev/disk3sx") == nil, "refuse non-disk names")

print(failures == 0 ? "selftest: all passed" : "selftest: \(failures) failed")
exit(failures == 0 ? 0 : 1)
