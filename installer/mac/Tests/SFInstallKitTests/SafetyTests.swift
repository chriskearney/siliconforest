import Foundation
import Testing
@testable import SFEngine
import SFInstallKit

/// A fake `hdiutil info -plist` / `diskutil info -plist` world for the guard.
private func fakeWorld(images: [(path: String, entities: [String], map: String?)], diskInfo: [String: [String: Any]] = [:]) -> RecordingRunner {
    let infos: [String: Data] = diskInfo.mapValues { try! PropertyListSerialization.data(fromPropertyList: $0, format: .xml, options: 0) }
    return RecordingRunner(respond: { argv in
        if argv == ["/usr/bin/hdiutil", "info", "-plist"] {
            let imgs: [[String: Any]] = images.map { i in
                ["image-path": i.path, "system-entities": i.entities.map { e -> [String: Any] in
                    var d: [String: Any] = ["dev-entry": "/dev/\(e)"]
                    if e == i.map { d["content-hint"] = "GUID_partition_scheme" }
                    return d
                }]
            }
            let data = try! PropertyListSerialization.data(fromPropertyList: ["images": imgs], format: .xml, options: 0)
            return ToolResult(status: 0, stdout: data)
        }
        if argv.count == 4, argv[0] == "/usr/sbin/diskutil", argv[1] == "info", let d = infos[argv[3]] {
            return ToolResult(status: 0, stdout: d)
        }
        return ToolResult(status: 1, stderr: Data("no such disk".utf8))
    })
}

private let root = URL(fileURLWithPath: "/tmp/sf-guard-root")
private let t3dmg = "/Users/someone/Downloads/Some-App.dmg"

@Suite("Image-only chokepoint")
struct ChokepointTests {
    @Test func refusesInternalDisksWithoutAskingDiskutil() throws {
        // The Mac's own disks: not attached from any image. Another user's dmg is attached as disk4.
        let world = fakeWorld(images: [(t3dmg, ["disk4", "disk4s1"], "disk4")])
        let mutating = RecordingRunner()
        let cp = ImageChokepoint(imageGuard: ImageGuard(allowedRoot: root, query: world), runner: mutating)
        for d in ["disk0", "disk1", "disk2", "disk3", "disk0s2", "disk3s5", "/dev/disk0", "/dev/rdisk3s1"] {
            #expect(throws: SafetyRefusal.self) { try cp.imageGuard.authorize(d) }
            #expect(throws: SafetyRefusal.self) { try cp.run(["/usr/sbin/diskutil", "eraseVolume", "free", "none", d]) }
            #expect(throws: SafetyRefusal.self) { try cp.openRaw(d, write: true) }
        }
        #expect(mutating.calls.isEmpty)
        #expect(!world.calls.contains { $0.first == "/usr/sbin/diskutil" }, "diskutil must never be asked about a non-image disk")
    }

    @Test func refusesTheRealMacsDisksOnThisMac() throws {
        // Live, read-only: the real `hdiutil info` on this Mac. disk0/1/3 are never image-backed here.
        let spy = RecordingRunner(inner: ProcessToolRunner())
        let mutating = RecordingRunner()
        let cp = ImageChokepoint(imageGuard: ImageGuard(allowedRoot: ImageGuard.defaultRoot, query: spy), runner: mutating)
        for d in ["disk0", "disk1", "disk2", "disk3", "disk0s1", "disk0s2", "disk3s1", "disk3s5"] {
            #expect(throws: SafetyRefusal.self) { try cp.run(["/usr/sbin/diskutil", "apfs", "resizeContainer", d, "10g"]) }
            #expect(throws: SafetyRefusal.self) { try cp.openRaw(d, write: false) }
        }
        #expect(mutating.calls.isEmpty)
        #expect(spy.calls.allSatisfy { $0 == ["/usr/bin/hdiutil", "info", "-plist"] }, "only hdiutil info ran: \(spy.calls)")
    }

    @Test func refusesImagesOutsideTheAllowedDirectory() throws {
        let world = fakeWorld(images: [(t3dmg, ["disk4", "disk4s1", "disk4s2"], "disk4")])
        let cp = ImageChokepoint(imageGuard: ImageGuard(allowedRoot: root, query: world), runner: RecordingRunner())
        #expect(throws: SafetyRefusal.self) { try cp.run(["/usr/sbin/diskutil", "eraseVolume", "free", "none", "disk4s2"]) }
        #expect(!world.calls.contains { $0.first == "/usr/sbin/diskutil" })
        // Path tricks are resolved before the prefix check.
        let g = ImageGuard(allowedRoot: root, query: world)
        #expect(!g.isUnderAllowedRoot("/tmp/sf-guard-root/../evil.sparseimage"))
        #expect(!g.isUnderAllowedRoot("/tmp/sf-guard-rootx/a.sparseimage"))
        #expect(!g.isUnderAllowedRoot("/tmp/sf-guard-root/a.txt"))
    }

    @Test func refusesWhenDiskutilDisagrees() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = root.appendingPathComponent("x.sparseimage").path
        FileManager.default.createFile(atPath: path, contents: Data())
        defer { try? FileManager.default.removeItem(at: root) }
        let good: [String: Any] = ["BusProtocol": "Disk Image", "VirtualOrPhysical": "Virtual", "Internal": false, "ParentWholeDisk": "disk9", "WholeDisk": true]
        // 1. Image-listed, but diskutil says it's an internal fabric disk.
        var w = fakeWorld(images: [(path, ["disk9", "disk9s1"], "disk9")],
                          diskInfo: ["disk9s1": ["BusProtocol": "Apple Fabric", "VirtualOrPhysical": "Physical", "Internal": true, "ParentWholeDisk": "disk9"]])
        #expect(throws: SafetyRefusal.self) { try ImageGuard(allowedRoot: root, query: w).authorize("disk9s1") }
        // 2. A synthesised APFS disk whose physical store is on the internal disk (disk0s2).
        w = fakeWorld(images: [(path, ["disk9", "disk9s1", "disk10"], "disk9")],
                      diskInfo: ["disk10": ["BusProtocol": "Disk Image", "VirtualOrPhysical": "Virtual", "Internal": false, "ParentWholeDisk": "disk10",
                                            "APFSPhysicalStores": [["APFSPhysicalStore": "disk0s2"]]], "disk9": good])
        #expect(throws: SafetyRefusal.self) { try ImageGuard(allowedRoot: root, query: w).authorize("disk10") }
        // 3. A whole disk listed but whose parent differs.
        w = fakeWorld(images: [(path, ["disk9", "disk9s1"], "disk9")],
                      diskInfo: ["disk9s1": ["BusProtocol": "Disk Image", "VirtualOrPhysical": "Virtual", "Internal": false, "ParentWholeDisk": "disk3"]])
        #expect(throws: SafetyRefusal.self) { try ImageGuard(allowedRoot: root, query: w).authorize("disk9s1") }
        // 4. Everything agrees: allowed.
        w = fakeWorld(images: [(path, ["disk9", "disk9s1"], "disk9")],
                      diskInfo: ["disk9s1": ["BusProtocol": "Disk Image", "VirtualOrPhysical": "Virtual", "Internal": false, "ParentWholeDisk": "disk9"], "disk9": good])
        let ok = try ImageGuard(allowedRoot: root, query: w).authorize("/dev/rdisk9s1")
        #expect(ok.imageWholeDisk == "disk9")
    }

    @Test func forbiddenToolsAndShapesNeverRun() throws {
        for argv in [["/usr/bin/sudo", "diskutil", "list"], ["/bin/dd", "if=/dev/zero", "of=/dev/disk0"], ["/usr/sbin/gpt", "show", "disk0"],
                     ["/usr/bin/bputil", "-nc"], ["/usr/bin/kmutil", "configure-boot"], ["/usr/sbin/nvram", "boot-args=-v"],
                     ["/usr/sbin/bless", "--setBoot"], ["/usr/bin/csrutil", "disable"], ["/bin/sh", "-c", "diskutil list"], ["diskutil", "list"]] {
            #expect(throws: SafetyRefusal.self) { try ForbiddenTools.check(argv) }
            #expect(throws: SafetyRefusal.self) { try ProcessToolRunner().run(argv) }
        }
        let cp = ImageChokepoint(imageGuard: ImageGuard(allowedRoot: root, query: fakeWorld(images: [])), runner: RecordingRunner())
        #expect(throws: SafetyRefusal.self) { try cp.run(["/usr/sbin/diskutil", "eraseDisk", "APFS", "x", "disk5"]) }
        #expect(throws: SafetyRefusal.self) { try cp.run(["/usr/sbin/diskutil", "apfs", "updatePreboot", "disk5s1"]) }
        #expect(throws: SafetyRefusal.self) { try cp.run(["/usr/sbin/diskutil", "list"]) }   // no device named
        #expect(throws: SafetyRefusal.self) { try cp.run(["/usr/bin/hdiutil", "attach", "x.dmg"]) }
        #expect(cp.records.isEmpty)
    }

    @Test func queriesAreExactShapes() {
        #expect(Query.isAllowed(["/usr/sbin/diskutil", "apfs", "resizeContainer", "disk5s2", "limits", "-plist"]))
        #expect(!Query.isAllowed(["/usr/sbin/diskutil", "apfs", "resizeContainer", "disk5s2", "10g"]))
        #expect(!Query.isAllowed(["/usr/sbin/diskutil", "info", "-plist", "disk5; rm -rf /"]))
        #expect(Query.isAllowed(["/usr/bin/hdiutil", "info", "-plist"]))
        #expect(!Query.isAllowed(["/usr/bin/hdiutil", "detach", "disk5"]))
    }
}

@Suite("Hash-chained journal")
struct ChainJournalTests {
    func dir() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("sf-journal-\(UUID().uuidString)") }

    @Test func chainsVerifiesAndReopens() throws {
        let d = dir(); defer { try? FileManager.default.removeItem(at: d) }
        let j = try ChainJournal(directory: d)
        try j.append(.begin, args: ["plan": .s("{}")])
        try j.append(.intent, step: "S30", args: ["bytes": .i(2_499_805_184)])
        try j.append(.evidence, step: "S30", result: ["role": .s("stub"), "uuid": .s("U-1")])
        let again = try ChainJournal(directory: d, jobID: j.jobID)
        #expect(again.records == j.records)
        #expect(again.records[1].prev == again.records[0].hash && again.records[2].prev == again.records[1].hash)
        #expect(JobState(again.records).created["stub"] == "U-1")
        #expect(!JobState(again.records).noChangesMade)
        #expect(ChainJournal.unfinished(in: d).count == 1)
    }

    @Test func noChangesIsProvedOnlyByTheAbsenceOfDiskIntents() throws {
        let d = dir(); defer { try? FileManager.default.removeItem(at: d) }
        let j = try ChainJournal(directory: d)
        try j.append(.begin); try j.append(.intent, step: "S10"); try j.append(.evidence, step: "S10")
        try j.append(.simulated, step: "S20", args: ["reason": .s("root")])
        #expect(JobState(j.records).noChangesMade)
        try j.append(.intent, step: "S25")
        #expect(!JobState(j.records).noChangesMade)
    }

    @Test func tornTailIsDroppedAndTamperingIsCaught() throws {
        let d = dir(); defer { try? FileManager.default.removeItem(at: d) }
        let j = try ChainJournal(directory: d)
        for i in 0..<4 { try j.append(.note, note: "n\(i)") }
        // Power lost mid-write: half a record, no newline.
        let h = try FileHandle(forWritingTo: j.url); try h.seekToEnd(); try h.write(contentsOf: Data(#"{"seq":5,"prev":"ab"#.utf8)); try h.close()
        let reopened = try ChainJournal(directory: d, jobID: j.jobID)
        #expect(reopened.records.count == 4 && reopened.recoveredTornTail)
        try reopened.append(.note, note: "after")
        #expect(try ChainJournal.load(reopened.url).0.count == 5)
        // Edit a middle record: the chain breaks.
        var lines = try String(contentsOf: reopened.url, encoding: .utf8).split(separator: "\n").map(String.init)
        lines[1] = lines[1].replacingOccurrences(of: "n1", with: "nX")
        try (lines.joined(separator: "\n") + "\n").write(to: reopened.url, atomically: true, encoding: .utf8)
        #expect(throws: JournalCorruption.self) { try ChainJournal.load(reopened.url) }
    }
}

@Suite("Resize supervisor classification")
struct ResizeClassificationTests {
    let from: Int64 = 494_384_795_648, to: Int64 = 390_000_000_000
    @Test func classifiesEveryOutcomeInTheTable() {
        #expect(ResizeSupervisor.classify(from: from, to: to, partition: to, container: to, status: 0, output: "") == .completed)
        // #391: the tool hasn't exited (status nil) but the topology shows the target: complete.
        #expect(ResizeSupervisor.classify(from: from, to: to, partition: to, container: to, status: nil, output: "") == .completed)
        if case .unchanged = ResizeSupervisor.classify(from: from, to: to, partition: from, container: from, status: 1, output: "Error: -69519") {} else { Issue.record("unchanged") }
        for out in ["Error: -69606: A problem occurred", "Error 49153", "Storage system verify or repair failed"] {
            if case .needsFirstAid = ResizeSupervisor.classify(from: from, to: to, partition: from, container: from, status: 1, output: out) {} else { Issue.record("first aid: \(out)") }
        }
        #expect(ResizeSupervisor.classify(from: from, to: to, partition: from, container: to, status: 1, output: "") == .inconsistent(partition: from, container: to))
        if case .unknown = ResizeSupervisor.classify(from: from, to: to, partition: 400_000_000_000, container: 400_000_000_000, status: 1, output: "") {} else { Issue.record("unknown") }
    }

    @Test func parsesProgress() {
        let (p, phase) = ResizeSupervisor.parseProgress("Started APFS operation\n[ - 0%..10%..20%..30% ]\nShrinking APFS data structures\n")
        #expect(p == 30 && phase == "Shrinking APFS data structures")
    }
}
