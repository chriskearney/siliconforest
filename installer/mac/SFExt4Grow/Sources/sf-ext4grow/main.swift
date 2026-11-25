// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// sf-ext4grow: grow an unmounted SiliconForest ext4 root in place, offline, from macOS (installer S48).
// Disk images and plain files only.

import Foundation
import SFExt4

let usage = """
usage: sf-ext4grow inspect TARGET
       sf-ext4grow plan   TARGET [--size BYTES | --blocks N] [--lazy-itables] [--protect OFFSET:LENGTH]... [--root-json FILE] [--verbose]
       sf-ext4grow grow   TARGET [--size BYTES | --blocks N] [--lazy-itables] [--protect OFFSET:LENGTH]... [--root-json FILE]
                                 [--undo-log FILE] [--keep-undo-log] [--unmount] [--write-map FILE] [--json]
       sf-ext4grow undo   TARGET --undo-log FILE

TARGET is a plain file or the /dev node of an attached disk image (checked with hdiutil info).
Without --size the filesystem grows to fill TARGET. The default undo log for a file is TARGET.sf-ext4grow-undo.
"""

func fail(_ msg: String, _ code: Int32 = 2) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(code)
}

var args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else { fail(usage, 64) }
let command = args.removeFirst()
let targetPath = args.removeFirst()
var opts = GrowOptions()
var undoLog: String?
var keepUndo = false, unmount = false, verbose = false, json = false
var writeMapPath: String?
var sizeBytes: UInt64?, sizeBlocks: UInt64?

while !args.isEmpty {
    let a = args.removeFirst()
    func value() -> String { guard !args.isEmpty else { fail("\(a) needs a value", 64) }; return args.removeFirst() }
    switch a {
    case "--size": guard let v = UInt64(value()) else { fail("bad --size", 64) }; sizeBytes = v
    case "--blocks": guard let v = UInt64(value()) else { fail("bad --blocks", 64) }; sizeBlocks = v
    case "--lazy-itables": opts.zeroInodeTables = false
    case "--protect":
        let p = value().split(separator: ":")
        guard p.count == 2, let o = UInt64(p[0]), let n = UInt64(p[1]), n > 0 else { fail("bad --protect (OFFSET:LENGTH)", 64) }
        opts.protectedRanges.append(o..<(o + n))
    case "--root-json":
        let path = value()
        guard let d = FileManager.default.contents(atPath: path),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { fail("cannot read \(path)", 64) }
        for key in ["firmware_slot", "receipt_slot"] {
            guard let s = j[key] as? [String: Any], let o = (s["offset"] as? NSNumber)?.uint64Value,
                  let n = (s["bytes"] as? NSNumber)?.uint64Value else { fail("\(path) has no \(key)", 64) }
            opts.protectedRanges.append(o..<(o + n))
        }
    case "--undo-log": undoLog = value()
    case "--keep-undo-log": keepUndo = true
    case "--unmount": unmount = true
    case "--write-map": writeMapPath = value()
    case "--verbose": verbose = true
    case "--json": json = true
    case "--test-stop-after":
        switch value() { case "fresh": opts.testStopAfter = .fresh; case "commit": opts.testStopAfter = .commit; default: fail("bad stage", 64) }
    default: fail("unknown option \(a)\n\(usage)", 64)
    }
}

func say(_ s: String) { if !json { print(s) } }

do {
    let target = try TargetGuard.resolve(targetPath, unmount: unmount)
    defer { target.release() }
    say("target: \(target.describe)")
    let writable = command == "grow" || command == "undo"
    let dev = try FileDevice(path: target.ioPath, writable: writable)
    if let b = sizeBytes { opts.targetBlocks = b / 4096 }
    if let b = sizeBlocks { opts.targetBlocks = b }

    switch command {
    case "inspect":
        let vol = try Ext4Volume(device: dev)
        say("filesystem: \"\(vol.sb.volumeName)\", \(vol.geo.blocks) blocks of \(vol.blockSize), \(vol.geo.groups) groups, \(vol.sb.inodesCount) inodes")
        say("GDT blocks \(vol.geo.gdtBlocks), reserved \(vol.geo.reservedGdt): grows to at most \(UInt64(vol.geo.maxGroups) * vol.geo.blocksPerGroup * 4096) bytes")
        say("device: \(dev.byteSize) bytes")
        let r = try vol.preflight()
        for l in r.lines { say(l) }
        say("preflight: OK")
    case "plan":
        guard let plan = try Grower.plan(device: dev, options: opts) else { say("already grown: nothing to do"); exit(0) }
        say("plan: \(plan.oldGeo.blocks) -> \(plan.newGeo.blocks) blocks, \(plan.oldGeo.groups) -> \(plan.newGeo.groups) groups, GDT \(plan.oldGeo.gdtBlocks) -> \(plan.newGeo.gdtBlocks), reserved \(plan.oldGeo.reservedGdt) -> \(plan.newGeo.reservedGdt)")
        for p in [WritePhase.fresh, .commit, .superblock] {
            say("  \(p): \(plan.writes.filter { $0.phase == p }.count) blocks")
        }
        say("  zeroed: \(plan.zeroRuns.reduce(0) { $0 + $1.count }) blocks; undo log: \(plan.undo.count) blocks; flex_bg layout: \(plan.canonicalPlacement ? "canonical" : "fallback used")")
        for n in plan.notes { say("  note: \(n)") }
        if verbose { for w in plan.writes { say("  \(w.phase) \(w.block) \(w.what)") }; for z in plan.zeroRuns { say("  zero \(z.start)+\(z.count) \(z.what)") } }
    case "grow":
        let log: String
        if let u = undoLog { log = u } else if case .file = target.kind { log = target.ioPath + ".sf-ext4grow-undo" } else {
            fail("--undo-log is required for a device target", 64)
        }
        let r = try Grower.grow(device: dev, options: opts, undoLogPath: log, keepUndoLog: keepUndo, log: { say("  " + $0) })
        if let wm = writeMapPath {
            let lines = r.writeMap.map { "\($0.0)\t\($0.1)\t\($0.2)\t\($0.3)" }.joined(separator: "\n") + "\n"
            try lines.write(toFile: wm, atomically: true, encoding: .utf8)
        }
        if json {
            let o: [String: Any] = ["already_grown": r.alreadyGrown, "old_blocks": r.oldBlocks, "new_blocks": r.newBlocks,
                                    "old_groups": r.oldGroups, "new_groups": r.newGroups, "blocks_written": r.blocksWritten,
                                    "blocks_zeroed": r.blocksZeroed, "bytes_written": r.bytesWritten,
                                    "canonical_flex_layout": r.canonicalPlacement, "notes": r.notes]
            print(String(data: try JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]), encoding: .utf8)!)
        } else if !r.alreadyGrown {
            say("grown: \(r.oldBlocks) -> \(r.newBlocks) blocks (\(r.oldGroups) -> \(r.newGroups) groups), \(r.blocksWritten) blocks written, \(r.blocksZeroed) zeroed")
            for n in r.notes { say("  note: \(n)") }
        }
    case "undo":
        guard let u = undoLog else { fail("undo needs --undo-log", 64) }
        try Grower.undo(device: dev, undoLogPath: u, log: { say($0) })
    default:
        fail(usage, 64)
    }
} catch let e as Ext4Error {
    fail("sf-ext4grow: refused: \(e)")
} catch {
    fail("sf-ext4grow: \(error)", 1)
}
