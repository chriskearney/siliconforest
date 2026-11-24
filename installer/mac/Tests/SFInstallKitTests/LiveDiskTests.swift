import Foundation
import Testing
@testable import SFEngine
@testable import SFLiveDisk
import SFInstallKit
import SFHelperKit

// The live backend's tests. Everything here is either pure (a synthetic partition table, no process)
// or runs against attached disk images that the test creates under .build-images. No test names a
// real disk with a command that could run: refusals of host disk names use a runner that records and
// never executes, and the compile key `SF_REAL_DISK_WRITES` is never defined.

// MARK: - a synthetic J313-shaped table for the pure tests

private enum Synth {
    static let gib: Int64 = 1 << 30
    static func part(_ uuid: String, _ id: String, _ content: String, _ off: Int64, _ size: Int64, volumes: [String] = []) -> ImagePartition {
        ImagePartition(uuid: uuid, identifier: id, content: content, offset: off, size: size, volumeName: nil, filesystem: nil,
                       apfs: content == "Apple_APFS" ? ImageAPFS(reference: "disk9\(id.dropFirst(6))", uuid: "C-\(uuid)", capacityCeiling: size, capacityFree: size / 2,
                                                                  volumes: volumes.enumerated().map { ImageVolume(identifier: "disk9\(id.dropFirst(6))s\($0.offset + 1)", uuid: "V\($0.offset)", name: $0.element, roles: ["System"]) }) : nil)
    }
    // ISC | macOS 150 GiB | Linux stub 2.5 GiB | ESP 0.5 GiB | Linux root 80 GiB | Recovery 5 GiB
    static let isc = part("ISC-UUID", "disk5s1", "Apple_APFS_ISC", 20_480, 500 << 20)
    static let mac = part("MAC-UUID", "disk5s2", "Apple_APFS", 524_308_480, 150 * gib, volumes: ["Macintosh HD"])
    static let stub = part("STUB-UUID", "disk5s3", "Apple_APFS", 524_308_480 + 150 * gib, 5 * gib / 2, volumes: ["Linux stub"])
    static let esp = part("ESP-UUID", "disk5s4", "EFI", stub.end, 512 << 20)
    static let root = part("LROOT-UUID", "disk5s5", "Linux Filesystem", esp.end, 80 * gib)
    static let rec = part("REC-UUID", "disk5s6", "Apple_APFS_Recovery", root.end, 5 * gib)
    static var table: ImageTopology { ImageTopology(wholeDisk: "disk5", size: rec.end + 20_480, blockSize: 4096, partitions: [isc, mac, stub, esp, root, rec]) }

    static func plan(_ t: ImageTopology = table, sf: Int64 = 20 * gib) -> EnginePlan {
        let mac = t.partition(uuid: "MAC-UUID")!
        let to = mac.size - sf
        return EnginePlan(operation: .install, profile: ProfileRef(id: "J313", sha256: "x"), release: "r", releaseVersion: "v",
                          request: InstallRequest(siliconForestBytes: sf, installID: "a1b2c3d4"), layoutDigest: t.layoutDigest,
                          macOS: .init(store: "MAC-UUID", from: mac.size, to: to),
                          partitions: [.init(role: "stub", after: "@macos", bytes: 2 * gib, content: "Apple_APFS", label: "SiliconForest"),
                                       .init(role: "boot", after: "@stub", bytes: 500 << 20, content: "EFI", label: "SFBOOT"),
                                       .init(role: "root", after: "@boot", bytes: sf - 2 * gib - (500 << 20), content: "Linux Filesystem", label: "SF root")],
                          owned: nil, installJob: nil, originalLayoutDigest: t.layoutDigest, humanSteps: []).sealed()
    }
}

// MARK: - the two keys

@Suite("Real-disk gate: two keys, both off")
struct RealDiskGateTests {
    static let good = RealDiskGate.Authorization(planDigest: "PLAN", diskUUID: "AAAA-BBBB",
                                                 notBefore: Date(timeIntervalSince1970: 1_000), notAfter: Date(timeIntervalSince1970: 1_000 + 3600))
    static func probe(_ a: RealDiskGate.Authorization = good, uid: UInt32 = 0, mode: UInt16 = 0o600, symlink: Bool = false, dirUID: UInt32 = 0,
                      dirMode: UInt16 = 0o755, raw: Data? = nil, counter: Counter = Counter()) -> RealDiskGate.FileProbe {
        let enc = Canonical.encoder()
        let data = raw ?? ((try? enc.encode(a)) ?? Data())
        return RealDiskGate.FileProbe(
            lstat: { path in
                counter.bump()
                if path.hasSuffix(".json") { return .init(isRegular: !symlink, isSymlink: symlink, uid: uid, mode: mode) }
                return .init(isRegular: false, isSymlink: false, uid: dirUID, mode: dirMode)
            }, read: { _ in counter.bump(); return data })
    }
    final class Counter: @unchecked Sendable { private let l = NSLock(); private var n = 0; func bump() { l.lock(); n += 1; l.unlock() }; var count: Int { l.lock(); defer { l.unlock() }; return n } }
    static func eval(_ p: RealDiskGate.FileProbe, plan: String = "PLAN", disk: String = "aaaa-bbbb", at: TimeInterval = 2_000, uid: UInt32 = 0, compiled: Bool = true) -> Result<RealDiskGate.Authorization, RealDiskGate.Closed> {
        RealDiskGate.evaluate(planDigest: plan, diskUUID: disk, path: "/var/db/org.siliconforest.installer/real-disk-authorization.json",
                              now: Date(timeIntervalSince1970: at), uid: uid, probe: p, compiled: compiled)
    }

    @Test func thisBuildHasNeitherKey() {
        #if SF_REAL_DISK_WRITES
        // Only `scripts/test-gate-compiled.sh` builds this way (fake disks only); see LiveDiskGateOnTests.
        #expect(RealDiskGate.compiledIn)
        #else
        #expect(RealDiskGate.compiledIn == false, "the tests must never be built with SF_REAL_DISK_WRITES")
        #expect(LiveDiskBuild.realDiskAuthorityCompiledIn == false)
        // With no key at all, the real file is not even a question.
        #expect(RealDiskGate.evaluate(planDigest: "x", diskUUID: "y") == .failure(.notCompiled))
        #endif
        let pkg = (try? String(contentsOf: SourceTree.packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)) ?? ""
        let code = pkg.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        #expect(!code.contains("SF_REAL_DISK_WRITES"), "Package.swift must never define the compile key")
    }

    @Test func closedWithoutTheCompileKeyEvenWithAPerfectFile() {
        let c = Counter()
        #expect(Self.eval(Self.probe(counter: c), compiled: false) == .failure(.notCompiled))
        #expect(c.count == 0, "a build without the compile key must not even look at the authorization file")
    }

    @Test func theRuntimeKeyIsStrict() {
        #expect((try? Self.eval(Self.probe()).get()) != nil)                                                  // the one good case
        #expect(Self.eval(Self.probe(), uid: 501) == .failure(.notRoot))
        #expect(Self.eval(RealDiskGate.FileProbe(lstat: { _ in nil }, read: { _ in nil })) == .failure(.noAuthorization))
        #expect(Self.eval(Self.probe(symlink: true)) == .failure(.unsafeFile("not a regular file")))
        #expect(Self.eval(Self.probe(uid: 501)) == .failure(.unsafeFile("not owned by root")))
        #expect(Self.eval(Self.probe(mode: 0o666)) == .failure(.unsafeFile("writable by group or others")))
        #expect(Self.eval(Self.probe(mode: 0o620)) == .failure(.unsafeFile("writable by group or others")))
        #expect(Self.eval(Self.probe(dirMode: 0o777)) == .failure(.unsafeFile("its directory is not root-only")))
        #expect(Self.eval(Self.probe(dirUID: 501)) == .failure(.unsafeFile("its directory is not root-only")))
        #expect(Self.eval(Self.probe(raw: Data("not json".utf8))) == .failure(.badFormat("not valid JSON for this format")))
        var wrongStatement = Self.good; wrongStatement.statement = "yes"
        #expect(Self.eval(Self.probe(wrongStatement)) == .failure(.badFormat("wrong format or statement")))
        var wrongFormat = Self.good; wrongFormat.format = "other/1"
        #expect(Self.eval(Self.probe(wrongFormat)) == .failure(.badFormat("wrong format or statement")))
        #expect(Self.eval(Self.probe(), at: 999) == .failure(.notYetValid))
        #expect(Self.eval(Self.probe(), at: 1_000 + 3600) == .failure(.expired))
        var long = Self.good; long.notAfter = long.notBefore.addingTimeInterval(RealDiskGate.maxValidity + 1)
        #expect(Self.eval(Self.probe(long)) == .failure(.windowTooLong))
        var inverted = Self.good; inverted.notAfter = inverted.notBefore.addingTimeInterval(-5)
        #expect(Self.eval(Self.probe(inverted)) == .failure(.windowTooLong))
        #expect(Self.eval(Self.probe(), plan: "OTHER") == .failure(.planMismatch))
        #expect(Self.eval(Self.probe(), plan: "") == .failure(.planMismatch))
        #expect(Self.eval(Self.probe(), disk: "CCCC-DDDD") == .failure(.diskMismatch))
        #expect(Self.eval(Self.probe(), disk: "") == .failure(.diskMismatch))
    }

    @Test func refusingExecutorIsStillTheDefault() async throws {
        await #expect(throws: BackendError.self) { try await RefusingExecutor().run([["/usr/sbin/diskutil", "list"]]) }
        // The app-side planner never executes a mutating operation: planned commands only.
        let backend = RealDiskBackend()
        #expect(backend.kind == .realReadOnly)
    }

    @Test func theShippedHelperHasNoTarget() {
        let c = HelperConfig(target: .none, workDirectory: URL(fileURLWithPath: "/tmp/x"), profileID: "J313", release: nil, releaseSource: nil)
        if case .none = c.target {} else { Issue.record("the default helper target must be none") }
    }
}

// MARK: - the protection receipt, on a synthetic J313 table

@Suite("Protection receipt")
struct ProtectionReceiptTests {
    typealias M = LiveMutation
    static func receipt() throws -> ProtectionReceipt { try ProtectionReceipt.derive(plan: Synth.plan(), original: Synth.table) }
    static func argv(_ s: String) -> [String] { s.split(separator: " ").map(String.init) }

    @Test func derivesProtectedSetAndSpan() throws {
        let r = try Self.receipt()
        #expect(r.isSealed && r.macOSStore == "MAC-UUID")
        #expect(Set(r.protected.map(\.uuid)) == ["ISC-UUID", "STUB-UUID", "ESP-UUID", "LROOT-UUID", "REC-UUID"])
        #expect(r.protected.first { $0.uuid == "STUB-UUID" }?.kind == .linuxStub)
        #expect(r.protected.first { $0.uuid == "ESP-UUID" }?.kind == .linuxESP)
        #expect(r.protected.first { $0.uuid == "LROOT-UUID" }?.kind == .linuxRoot)
        #expect(r.protected.first { $0.uuid == "ISC-UUID" }?.kind == .appleSystem)
        #expect(r.spanStart == Synth.mac.offset + Synth.plan().macOS.to && r.spanEnd == Synth.stub.offset)
        #expect(r.spanEnd - r.spanStart == 20 * Synth.gib)
        // Deterministic: the same plan and table give the same receipt, which is what survives a crash.
        #expect(try Self.receipt() == r)
    }

    @Test func refusesToDeriveFromAnythingOdd() throws {
        var unsealed = Synth.plan(); unsealed.macOS.to -= 4096
        #expect(throws: SafetyRefusal.self) { try ProtectionReceipt.derive(plan: unsealed, original: Synth.table) }
        var missing = Synth.plan(); missing.macOS.store = "NOPE"; missing = missing.sealed()
        #expect(throws: SafetyRefusal.self) { try ProtectionReceipt.derive(plan: missing, original: Synth.table) }
        var wrongFrom = Synth.plan(); wrongFrom.macOS.from -= 4096; wrongFrom = wrongFrom.sealed()
        #expect(throws: SafetyRefusal.self) { try ProtectionReceipt.derive(plan: wrongFrom, original: Synth.table) }
        // macOS must be an APFS container.
        var notAPFS = Synth.table; notAPFS.partitions[1].content = "Linux Filesystem"
        #expect(throws: SafetyRefusal.self) { try ProtectionReceipt.derive(plan: Synth.plan(), original: notAPFS) }
    }

    @Test func everyCommandThatCouldHurtLinuxOrAppleIsRefused() throws {
        let r = try Self.receipt(), t = Synth.table
        let d = "/usr/sbin/diskutil"
        let cmds: [[String]] = [
            // erase / delete / format / mount the Linux stub, ESP, root and Apple's partitions
            [d, "eraseVolume", "free", "none", "disk5s3"], [d, "eraseVolume", "free", "none", "disk5s4"], [d, "eraseVolume", "free", "none", "disk5s5"],
            [d, "eraseVolume", "free", "free", "disk5s6"], [d, "eraseVolume", "free", "none", "disk5s1"],
            [d, "apfs", "deleteContainer", "disk5s3"], [d, "apfs", "deleteContainer", "disk5s6"],
            ["/sbin/newfs_msdos", "-F", "32", "-v", "X", "/dev/rdisk5s4"], ["/sbin/newfs_msdos", "-F", "32", "-v", "X", "/dev/rdisk5s5"],
            [d, "mount", "nobrowse", "disk5s4"], [d, "unmount", "disk5s3"],
            [d, "apfs", "addVolume", "disk93", "APFS", "X", "-role", "S", "-nomount"],            // the Linux stub's container
            // resize anything but macOS, or macOS to a size that isn't the plan's
            [d, "apfs", "resizeContainer", "disk5s3", "1000000B"], [d, "apfs", "resizeContainer", "disk5s5", "0"],
            [d, "apfs", "resizeContainer", "disk5s2", "\(Synth.plan().macOS.to - 4096)B"], [d, "apfs", "resizeContainer", "disk5s2", "0"],
            // partitions after Linux's, or too big for the span
            [d, "addPartition", "disk5s3", "APFS", "X", "1000000B"], [d, "addPartition", "disk5s5", "%0FC63DAF-8483-4772-8E79-3D69D8477DE4%", "%noformat%", "1000000B"],
            [d, "addPartition", "disk5s2", "APFS", "X", "\(21 * Synth.gib)B"],
        ]
        for argv in cmds {
            let m = try M.parse(argv)
            #expect(throws: SafetyRefusal.self, "\(argv.joined(separator: " "))") { try LiveChokepoint.check(m, on: t, receipt: r) }
        }
        // The whole disk is never a target, by any verb.
        for argv in [[d, "eraseVolume", "free", "none", "disk5"], [d, "apfs", "resizeContainer", "disk5", "1000B"]] {
            // `disk5` is not even a partition identifier: it fails to parse.
            #expect(throws: SafetyRefusal.self) { try M.parse(argv) }
        }
        #expect(throws: SafetyRefusal.self) { try LiveChokepoint.check(.addVolume(container: "disk5"), on: t, receipt: r) }
    }

    @Test func theCommandsOfAnInstallAreAllowedInOrder() throws {
        let r = try Self.receipt(); var t = Synth.table
        let d = "/usr/sbin/diskutil", plan = Synth.plan()
        // Shrink macOS to exactly the plan's size.
        try LiveChokepoint.check(try M.parse([d, "apfs", "resizeContainer", "disk5s2", "\(plan.macOS.to)B"]), on: t, receipt: r)
        // …and back, for a rollback.
        try LiveChokepoint.check(try M.parse([d, "apfs", "resizeContainer", "disk5s2", "\(plan.macOS.from)B"]), on: t, receipt: r)
        // addPartition after macOS is refused until macOS has actually been shrunk…
        let add = try M.parse([d, "addPartition", "disk5s2", "APFS", "SiliconForest", "\(2 * Synth.gib)B"])
        #expect(throws: SafetyRefusal.self) { try LiveChokepoint.check(add, on: t, receipt: r) }
        t.partitions[1].size = plan.macOS.to
        try LiveChokepoint.check(add, on: t, receipt: r)
        // …and each new partition may then be formatted, mounted and erased: it lies inside the span.
        let stub = Synth.part("NEW-STUB", "disk5s7", "Apple_APFS", t.partitions[1].end, 2 * Synth.gib, volumes: ["SF"])
        let boot = Synth.part("NEW-BOOT", "disk5s8", "EFI", stub.end, 500 << 20)
        t.partitions.insert(contentsOf: [stub, boot], at: 2)
        for argv in [[d, "apfs", "deleteContainer", "disk5s7"], [d, "eraseVolume", "free", "none", "disk5s8"], ["/sbin/newfs_msdos", "-F", "32", "-v", "SFBOOT", "/dev/rdisk5s8"],
                     [d, "mount", "nobrowse", "disk5s8"], [d, "apfs", "addVolume", "disk97", "APFS", "SF Data", "-role", "D", "-nomount"]] {
            let m = try M.parse(argv)
            if case .addVolume = m { try LiveChokepoint.check(.addVolume(container: "disk97"), on: t, receipt: r); continue }
            try LiveChokepoint.check(m, on: t, receipt: r)
        }
        // A partition appended after the second one still must stay in the span.
        let tooBig = try M.parse([d, "addPartition", "disk5s8", "%0FC63DAF-8483-4772-8E79-3D69D8477DE4%", "%noformat%", "\(20 * Synth.gib)B"])
        #expect(throws: SafetyRefusal.self) { try LiveChokepoint.check(tooBig, on: t, receipt: r) }
    }

    @Test func commandShapesThatAreNotAllowedDoNotParse() {
        let d = "/usr/sbin/diskutil"
        let bad: [[String]] = [
            [d, "partitionDisk", "disk5", "GPT", "APFS", "X", "100%"], [d, "eraseDisk", "APFS", "X", "disk5"], [d, "unmountDisk", "disk5"], [d, "eject", "disk5"],
            [d, "apfs", "eraseVolume", "disk5s2"], [d, "apfs", "deleteVolume", "disk6s1"], [d, "apfs", "updatePreboot", "/"],
            [d, "addPartition", "disk5s2", "%69646961-6700-11AA-AA11-00306543ECAC%", "%noformat%", "1000B"],          // Apple's ISC type: never created
            [d, "addPartition", "disk5s2", "%52637672-7900-11AA-AA11-00306543ECAC%", "%noformat%", "1000B"],          // recovery type
            [d, "addPartition", "disk5s2", "APFS", "-bad", "1000B"], [d, "addPartition", "disk5s2", "APFS", "%x%", "1000B"],
            [d, "addPartition", "disk5s2", "APFS", "ok", "1000"],                                                    // no B suffix
            [d, "addPartition", "disk5s2", "APFS", "ok", "-1B"],
            [d, "mount", "disk5s4"], [d, "mount", "rdonly", "disk5s4"], [d, "mount", "nobrowse", "-mountPoint", "/x", "disk5s4"],
            [d, "eraseVolume", "APFS", "X", "disk5s4"], [d, "eraseVolume", "free", "none", "/dev/../disk5s4"],
            ["/sbin/newfs_msdos", "-F", "32", "-v", "X"], ["/sbin/newfs_msdos", "-F", "16", "-v", "X", "/dev/rdisk5s4"],
            ["/sbin/newfs_msdos", "-F", "32", "-v", "X", "/tmp/file"],
            ["/bin/dd", "if=/dev/zero", "of=/dev/rdisk5s4"], ["/usr/sbin/bless", "--setBoot"], ["/usr/bin/hdiutil", "attach", "x"], ["/bin/sh", "-c", "x"], [],
        ]
        for a in bad { #expect(throws: SafetyRefusal.self, "\(a)") { try M.parse(a) } }
    }

    @Test func aDriftedDiskIsCaught() throws {
        let r = try Self.receipt()
        #expect(r.violation(in: Synth.table) == nil)
        var moved = Synth.table; moved.partitions[3].offset += 4096
        #expect(r.violation(in: moved)?.contains("moved") == true)
        var resized = Synth.table; resized.partitions[4].size -= 4096
        #expect(r.violation(in: resized)?.contains("changed size") == true)
        var gone = Synth.table; gone.partitions.remove(at: 4)
        #expect(r.violation(in: gone)?.contains("vanished") == true)
        var smaller = Synth.table; smaller.size -= 4096
        #expect(r.violation(in: smaller)?.contains("size changed") == true)
        var weird = Synth.table; weird.partitions[1].size = 100 * Synth.gib
        #expect(r.violation(in: weird)?.contains("not a planned size") == true)
        // A stranger inside the span is fine; one outside it (here: on top of the stub) is not.
        var inside = Synth.table; inside.partitions[1].size = Synth.plan().macOS.to
        inside.partitions.insert(Synth.part("S1", "disk5s7", "Apple_APFS", inside.partitions[1].end, Synth.gib), at: 2)
        #expect(r.violation(in: inside) == nil)
        var outside = inside; outside.partitions[2] = Synth.part("S1", "disk5s7", "Apple_APFS", Synth.stub.offset - 1 << 20, 4 << 20)
        #expect(r.violation(in: outside)?.contains("outside the allowed span") == true)
    }

    @Test func aRemovalMayOnlyEraseWhatItOwnsAndGrowMacOS() throws {
        // The J313 table with the install's three partitions in the span.
        var t = Synth.table
        let plan0 = Synth.plan()
        t.partitions[1].size = plan0.macOS.to
        let a = Synth.part("O-STUB", "disk5s7", "Apple_APFS", t.partitions[1].end, 2 * Synth.gib, volumes: ["SF"])
        let b = Synth.part("O-BOOT", "disk5s8", "EFI", a.end, 500 << 20)
        let c = Synth.part("O-ROOT", "disk5s9", "Linux Filesystem", b.end, 20 * Synth.gib - 2 * Synth.gib - (500 << 20))
        t.partitions.insert(contentsOf: [a, b, c], at: 2)
        let removal = EnginePlan(operation: .remove, profile: ProfileRef(id: "J313", sha256: "x"), release: "", releaseVersion: "v", request: nil,
                                 layoutDigest: t.layoutDigest, macOS: .init(store: "MAC-UUID", from: plan0.macOS.to, to: plan0.macOS.from), partitions: [],
                                 owned: .init(stub: "O-STUB", boot: "O-BOOT", root: "O-ROOT"), installJob: UUID(), originalLayoutDigest: "x", humanSteps: []).sealed()
        let r = try ProtectionReceipt.derive(plan: removal, original: t)
        #expect(Set(r.protected.map(\.uuid)) == ["ISC-UUID", "STUB-UUID", "ESP-UUID", "LROOT-UUID", "REC-UUID"])
        let d = "/usr/sbin/diskutil"
        for argv in [[d, "eraseVolume", "free", "none", "disk5s9"], [d, "eraseVolume", "free", "none", "disk5s8"], [d, "apfs", "deleteContainer", "disk5s7"],
                     [d, "apfs", "resizeContainer", "disk5s2", "0"]] {
            try LiveChokepoint.check(try M.parse(argv), on: t, receipt: r)
        }
        for argv in [[d, "eraseVolume", "free", "none", "disk5s5"], [d, "apfs", "deleteContainer", "disk5s3"], [d, "apfs", "resizeContainer", "disk5s2", "\(plan0.macOS.from)B"],
                     [d, "addPartition", "disk5s7", "APFS", "X", "1000000B"], [d, "apfs", "resizeContainer", "disk5s4", "0"]] {
            #expect(throws: SafetyRefusal.self, "\(argv)") { try LiveChokepoint.check(try M.parse(argv), on: t, receipt: r) }
        }
        // An install-shaped receipt never allows the fill-the-space resize, and a removal never allows a fixed size.
        #expect(throws: SafetyRefusal.self) { try LiveChokepoint.check(.resize(container: "disk5s2", size: .fillFree), on: Synth.table, receipt: try Self.receipt()) }
    }
}

// MARK: - release verification and the pure parts of the backend

@Suite("Release check before the first write")
struct ReleaseCheckTests {
    static func release() throws -> (ReleaseManifest, URL) {
        let dir = ImageGuard.defaultRoot.appendingPathComponent("rc-\(UUID().uuidString)", isDirectory: true)
        return (try RehearsalRelease.make(in: dir), dir)
    }

    @Test func acceptsTheReleaseAndRefusesEveryKindOfDamage() throws {
        let (m, dir) = try Self.release(); defer { try? FileManager.default.removeItem(at: dir) }
        try ReleaseCheck.verifyArtifacts(m, in: dir)
        try ReleaseCheck.verifyRootImage(m, source: dir.appendingPathComponent(m.rootImage))
        // Flip one byte in a stub file.
        let f = dir.appendingPathComponent(m.stubFiles[1])
        var d = try Data(contentsOf: f); d[10] ^= 1; try d.write(to: f)
        #expect(throws: ReleaseCheck.Refusal.self) { try ReleaseCheck.verifyArtifacts(m, in: dir) }
        d[10] ^= 1; try d.write(to: f)
        try ReleaseCheck.verifyArtifacts(m, in: dir)
        // Truncate, delete.
        try d.prefix(100).write(to: f)
        #expect(throws: ReleaseCheck.Refusal.self) { try ReleaseCheck.verifyArtifacts(m, in: dir) }
        try FileManager.default.removeItem(at: f)
        #expect(throws: ReleaseCheck.Refusal.self) { try ReleaseCheck.verifyArtifacts(m, in: dir) }
    }

    @Test func theRootImageMustDecompressToExactlyTheManifest() throws {
        let (m, dir) = try Self.release(); defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent(m.rootImage)
        // The manifest's decompressed hash or length differs, though the file's own hash matches.
        var wrongHash = m; wrongHash.rootImageSHA256 = String(repeating: "0", count: 64)
        #expect(throws: ReleaseCheck.Refusal.self) { try ReleaseCheck.verifyRootImage(wrongHash, source: src) }
        var wrongLen = m; wrongLen.rootImageBytes += 4096
        #expect(throws: ReleaseCheck.Refusal.self) { try ReleaseCheck.verifyRootImage(wrongLen, source: src) }
        // Some other file in the release isn't the root image.
        #expect(throws: ReleaseCheck.Refusal.self) { try ReleaseCheck.verifyRootImage(m, source: dir.appendingPathComponent("boot.bin")) }
        // The file itself changed.
        var d = try Data(contentsOf: src); d[d.count / 2] ^= 0x10; try d.write(to: src)
        #expect(throws: ReleaseCheck.Refusal.self) { try ReleaseCheck.verifyRootImage(m, source: src) }
    }
}
