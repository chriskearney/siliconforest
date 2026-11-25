import Foundation
import Testing
@testable import SFEngine
@testable import SFLiveDisk
@testable import SFHelperKit
import SFInstallKit

/// The live backend on attached disk images: the same engine, the same real `diskutil`, `newfs_msdos`
/// and raw I/O as `ImageEngineTests`, but through `LiveDiskBackend`, its protection receipt and its
/// pre-write release checks. Every target here is an image the test made under .build-images.
enum LiveLab {
    /// The long live-backend repeats of suites CI already runs on the image backend (power loss after
    /// every step, the journal fork sweep). On by default; installer-mac.yml sets SF_LIVE_HEAVY=0 to fit
    /// its time limit, and the M5 runs them.
    static let heavy = ProcessInfo.processInfo.environment["SF_LIVE_HEAVY"] != "0"
    static func live(_ c: ImageLab.Case, runner: ToolRunner = ProcessToolRunner()) -> LiveDiskBackend {
        LiveDiskBackend(authority: ImageTargetAuthority(imagePath: c.image), runner: runner)
    }

    /// A private copy of the rehearsal release, so a test may damage it.
    static func privateRelease(_ c: ImageLab.Case) throws -> (ReleaseManifest, URL) {
        let dir = c.dir.appendingPathComponent("release", isDirectory: true)
        return (try RehearsalRelease.make(in: dir), dir)
    }

    static func plan(_ c: ImageLab.Case, profile: DeviceProfile, release: ReleaseManifest, sf: Int64 = 20 * Bytes.gb) throws -> EnginePlan {
        let t = try c.backend.topology()
        let mac = try #require(t.macOS)
        return try EnginePlanner.installPlan(topology: t, limits: try c.backend.limits(store: mac.uuid), profile: profile, release: release,
                                             request: InstallRequest(siliconForestBytes: sf, installName: "SiliconForest", installID: "a1b2c3d4"))
    }

    static func engine(_ c: ImageLab.Case, live: LiveDiskBackend, release: (ReleaseManifest, URL), journal: ChainJournal, profile: DeviceProfile,
                       faults: FaultPlan = FaultPlan(), launcher: ResizeLauncher = SpawnLauncher()) -> InstallEngine {
        InstallEngine(backend: live, journal: journal, profile: profile, release: release.0, releaseSource: release.1, workDir: c.workDir,
                      faults: faults, launcher: launcher, resizeTiming: .tests)
    }

    static func zeroHead(_ c: ImageLab.Case, _ root: String) throws -> Bool {
        let head = try c.backend.readRaw(root, offset: 0, count: 4096)
        return String(decoding: head.prefix(8), as: UTF8.self) != "SFROOT1 "
    }
}

@Suite("Live backend on disk images", .serialized, .enabled(if: ImageLab.enabled))
struct LiveBackendImageTests {

    @Test(.enabled(if: ImageLab.long)) func theWholeInstallAndRemovalRunThroughTheLiveBackend() throws {
        for layout in [ImageFixtures.Layout.j293, .j313] {
            let c = try ImageLab.fresh(layout); defer { c.finish() }
            let profile = try ImageLab.profile(layout == .j293 ? "J293" : "J313")
            let original = try c.backend.topology()
            let rel = try ImageLab.release()
            let plan = try ImageLab.plan(c, profile: profile)
            let live = LiveLab.live(c)
            let j = try ChainJournal(directory: c.journalDir)
            let e = LiveLab.engine(c, live: live, release: rel, journal: j, profile: profile)
            try e.begin(plan)
            #expect(try e.run() == .handedOff)
            try ImageEngineTests.expectInstalled(c, journal: j, plan: plan)
            if layout == .j313 { try FaultInjectionTests.expectLinuxUntouched(c, original: original) }
            // Every command went through the live chokepoint and parsed into one of the allowed shapes.
            let records = live.chokepoint.records
            #expect(!records.isEmpty && records.allSatisfy { $0.status == 0 || $0.argv.first == "<raw rw>" || $0.argv.first == "<raw ro>" })
            #expect(try records.filter { !$0.argv[0].hasPrefix("<") }.allSatisfy { _ = try LiveMutation.parse($0.argv); return true })
            let receipt = try #require(live.receipt)
            #expect(receipt == (try ProtectionReceipt.derive(plan: plan, original: original)))
            #expect(live.chokepoint.tripped == nil)

            let proof = try InstallProofReader.proof(from: j)
            let removal = try EnginePlanner.removalPlan(topology: try c.backend.topology(), profile: profile, proof: proof)
            let rj = try ChainJournal(directory: c.journalDir)
            let rlive = LiveLab.live(c)
            let re = LiveLab.engine(c, live: rlive, release: rel, journal: rj, profile: profile); re.proof = proof
            try re.begin(removal)
            #expect(try re.run() == .committed)
            #expect(try c.backend.topology().digestForm == original.digestForm)
            if layout == .j313 { try FaultInjectionTests.expectLinuxUntouched(c, original: original) }
            #expect(rlive.receipt?.operation == .remove)
        }
    }

    @Test(.enabled(if: ImageLab.long)) func refusesLinuxAppleAndEveryDiskThatIsNotTheTarget() throws {
        let c = try ImageLab.fresh(.j313); defer { c.finish() }
        let profile = try ImageLab.profile("J313")
        let original = try c.backend.topology()
        let rel = try LiveLab.privateRelease(c)
        let plan = try LiveLab.plan(c, profile: profile, release: rel.0)
        // This runner records and never executes: whatever slips past a check would show up as a call.
        let rec = RecordingRunner()
        let live = LiveLab.live(c, runner: rec)
        let d = "/usr/sbin/diskutil"
        let esp = try #require(original.partitions.first { $0.content == "EFI" })
        let linuxRoot = try #require(original.partitions.first { $0.content == "Linux Filesystem" })
        let linuxStub = try #require(original.partitions.first { $0.apfs?.volumes.contains { $0.name == "Linux stub" } ?? false })
        let mac = try #require(original.macOS)
        let first = try #require(original.partitions.first), last = try #require(original.partitions.last)

        // Not armed: nothing at all, not even a harmless-looking command on a free partition.
        #expect(throws: SafetyRefusal.self) { try live.chokepoint.run([d, "eraseVolume", "free", "none", esp.identifier]) }
        #expect(throws: SafetyRefusal.self) { try live.addPartition(after: mac.uuid, content: "Apple_APFS", label: "X", bytes: 1 << 30) }
        #expect(throws: SafetyRefusal.self) { try live.arm(plan: plan, original: ImageTopology(wholeDisk: original.wholeDisk, size: original.size, blockSize: original.blockSize, partitions: [])) }
        // Armed for this plan only.
        try live.arm(plan: plan, original: original)
        var other = plan; other.macOS.to -= 4096; other = other.sealed()
        #expect(throws: SafetyRefusal.self) { try live.arm(plan: other, original: original) }

        let ids = (esp: esp.identifier, root: linuxRoot.identifier, stub: linuxStub.identifier, mac: mac.identifier, isc: first.identifier, rec: last.identifier)
        var attempts: [[String]] = [
            [d, "eraseVolume", "free", "none", ids.esp], [d, "eraseVolume", "free", "none", ids.root], [d, "eraseVolume", "free", "free", ids.isc],
            [d, "eraseVolume", "free", "none", ids.rec], [d, "apfs", "deleteContainer", ids.stub], [d, "apfs", "deleteContainer", ids.mac],
            [d, "apfs", "deleteContainer", ids.rec],
            ["/sbin/newfs_msdos", "-F", "32", "-v", "X", "/dev/r\(ids.esp)"], ["/sbin/newfs_msdos", "-F", "32", "-v", "X", "/dev/r\(ids.root)"],
            ["/sbin/newfs_msdos", "-F", "32", "-v", "X", "/dev/r\(ids.mac)"],
            [d, "mount", "nobrowse", ids.esp], [d, "unmount", ids.root],
            [d, "apfs", "resizeContainer", ids.stub, "1000000000B"], [d, "apfs", "resizeContainer", ids.root, "0"],
            [d, "apfs", "resizeContainer", ids.mac, "\(plan.macOS.to - Bytes.gb)B"], [d, "apfs", "resizeContainer", ids.mac, "0"],
            [d, "addPartition", ids.stub, "APFS", "X", "100000000B"], [d, "addPartition", ids.root, "%0FC63DAF-8483-4772-8E79-3D69D8477DE4%", "%noformat%", "100000000B"],
            [d, "addPartition", ids.mac, "APFS", "X", "\(plan.macOS.from)B"],            // macOS isn't shrunk yet: nothing may follow it
            [d, "partitionDisk", original.wholeDisk, "GPT", "APFS", "X", "100%"], [d, "eraseDisk", "APFS", "X", original.wholeDisk],
            [d, "eraseVolume", "free", "none", original.wholeDisk],
            ["/bin/dd", "if=/dev/zero", "of=/dev/r\(ids.root)", "bs=1m"],
        ]
        // Another attached disk image (not this job's) and the host's own disks.
        let otherURL = c.dir.appendingPathComponent("other.dmg")
        #expect(try ProcessToolRunner().run(["/usr/bin/hdiutil", "create", "-quiet", "-size", "32m", "-layout", "GPTSPUD", otherURL.path]).ok)
        let otherImage = DiskImageBackend(imagePath: otherURL); try otherImage.attach()
        defer { try? otherImage.detach(force: true) }
        let otherWhole = try otherImage.wholeDisk()
        for suffix in ["s1", "s2"] { attempts.append([d, "eraseVolume", "free", "none", otherWhole + suffix]) }
        for host in ["disk0s1", "disk0s2", "disk0s3", "disk1s1", "disk3s1", "disk3s5"] {
            attempts.append([d, "eraseVolume", "free", "none", host]); attempts.append([d, "apfs", "resizeContainer", host, "\(plan.macOS.to)B"])
            attempts.append([d, "addPartition", host, "APFS", "X", "100000000B"])
        }
        func reason(_ body: () throws -> Void) -> String {
            do { try body(); return "NOT REFUSED" } catch let r as SafetyRefusal { return r.reason } catch { return "other error: \(error)" }
        }
        // Each refusal must come from the check meant to make it, not from some unrelated failure.
        let firstShapeRefusal = try #require(attempts.firstIndex { $0.contains("partitionDisk") })
        let protectedTargets = Set(attempts[..<firstShapeRefusal].map { $0.joined(separator: " ") })
        for a in attempts {
            let line = a.joined(separator: " ")
            let why = reason { _ = try live.chokepoint.run(a) }
            #expect(why != "NOT REFUSED" && !why.hasPrefix("other error"), "\(line): \(why)")
            if protectedTargets.contains(line) { #expect(why.hasPrefix("protection receipt:"), "\(line): \(why)") }
            let why2 = reason { try live.authorizeResize(a) }
            #expect(why2 != "NOT REFUSED" && !why2.hasPrefix("other error"), "supervisor path \(line): \(why2)")
        }
        // Raw access: never a write to a protected partition or a whole disk; host disks aren't even readable.
        for dev in [ids.esp, ids.root, ids.isc, ids.rec, ids.mac, original.wholeDisk, otherWhole + "s1", "disk0s2", "disk3s1"] {
            #expect(throws: (any Error).self, "raw write \(dev)") { _ = try live.chokepoint.openRaw(dev, write: true) }
        }
        for dev in ["disk0s2", "disk3s1", otherWhole + "s1"] { #expect(throws: (any Error).self, "raw read \(dev)") { _ = try live.chokepoint.openRaw(dev, write: false) } }
        // Nothing ran, nothing changed.
        #expect(rec.calls.isEmpty, "a refused command reached the runner: \(rec.calls)")
        #expect(try c.backend.freshTopology().digestForm == original.digestForm)
        try FaultInjectionTests.expectLinuxUntouched(c, original: original)
        #expect(live.chokepoint.tripped == nil)
    }

    @Test(.enabled(if: ImageLab.long)) func aProtectedPartitionChangingBehindOurBackTripsTheJob() throws {
        let c = try ImageLab.fresh(.j313); defer { c.finish() }
        let profile = try ImageLab.profile("J313")
        let original = try c.backend.topology()
        let rel = try LiveLab.privateRelease(c)
        let plan = try LiveLab.plan(c, profile: profile, release: rel.0)
        let live = LiveLab.live(c)
        try live.arm(plan: plan, original: original)
        try live.verifyProtected(content: true)
        // Someone else writes to the Linux root.
        let linuxRoot = try #require(original.partitions.first { $0.content == "Linux Filesystem" })
        try c.backend.writeRaw(linuxRoot.uuid, offset: 0, data: Data(repeating: 0xEE, count: 4096))
        #expect(throws: EngineError.self) { try live.verifyProtected(content: true) }
        #expect(live.chokepoint.tripped?.contains("protected partition") == true)
        // From now on nothing is run or written, even a command the receipt would otherwise allow.
        live.expectRelease(rel.0, in: rel.1)
        let mac = try #require(original.macOS)
        #expect(throws: SafetyRefusal.self) { try live.addPartition(after: mac.uuid, content: "Apple_APFS", label: "X", bytes: 1 << 30) }
        #expect(throws: SafetyRefusal.self) { try live.authorizeResize(["/usr/sbin/diskutil", "apfs", "resizeContainer", mac.identifier, "\(plan.macOS.to)B"]) }
        #expect(try c.backend.freshTopology().digestForm == original.digestForm)
    }

    @Test(.enabled(if: ImageLab.long)) func aReleaseDamagedAfterTheEngineCheckedItIsStillRefusedBeforeAnyWrite() throws {
        let c = try ImageLab.fresh(.j293); defer { c.finish() }
        let profile = try ImageLab.profile()
        let original = try c.backend.topology()
        let rel = try LiveLab.privateRelease(c)
        let plan = try LiveLab.plan(c, profile: profile, release: rel.0)
        let j = try ChainJournal(directory: c.journalDir)
        let e = LiveLab.engine(c, live: LiveLab.live(c), release: rel, journal: j, profile: profile)
        try e.begin(plan)
        // After S15 has verified the work copy, a file in it changes (bad disk, malware, a race).
        let victim = c.workDir.appendingPathComponent(rel.0.stubFiles[1])
        j.afterAppend = { rec in
            guard rec.step == "S15", rec.kind == .evidence else { return }
            var d = try Data(contentsOf: victim); d[7] ^= 0xFF; try d.write(to: victim)
        }
        #expect(throws: SafetyRefusal.self) { try e.run() }
        j.afterAppend = nil
        // Nothing was written: not the resize, not a partition. The journal proves it.
        #expect(try c.backend.freshTopology().digestForm == original.digestForm)
        let st = JobState(j.records)
        #expect(st.failed[.S25] != nil || st.failed[.S20] != nil)
        #expect(st.created.isEmpty)
        // The job can be rolled back, and it restores the table.
        #expect(try LiveLab.engine(c, live: LiveLab.live(c), release: rel, journal: try ChainJournal(directory: c.journalDir, jobID: j.jobID), profile: profile).rollback() == .rolledBack)
    }

    @Test(.enabled(if: ImageLab.long)) func aRootImageDamagedOrNotTheManifestsIsRefusedBeforeTheFirstByteIsWritten() throws {
        for mode in ["tamper-after-verify", "manifest-hash-differs", "manifest-length-differs"] {
            let c = try ImageLab.fresh(.j293); defer { c.finish() }
            let profile = try ImageLab.profile()
            let original = try c.backend.topology()
            var rel = try LiveLab.privateRelease(c)
            if mode == "manifest-hash-differs" { rel.0.rootImageSHA256 = String(repeating: "ab", count: 32) }
            if mode == "manifest-length-differs" { rel.0.rootImageBytes += 4096 }
            let plan = try LiveLab.plan(c, profile: profile, release: rel.0)
            let live = LiveLab.live(c)
            if mode == "tamper-after-verify" {
                live.faults.tamperBeforeWrite = { url in
                    // The engine and the backend have both verified every artifact; now the image changes.
                    if var d = try? Data(contentsOf: url) { d[d.count / 2] ^= 0x40; try? d.write(to: url) }
                }
            }
            let j = try ChainJournal(directory: c.journalDir)
            let e = LiveLab.engine(c, live: live, release: rel, journal: j, profile: profile)
            try e.begin(plan)
            #expect(throws: SafetyRefusal.self, "\(mode)") { try e.run() }
            let st = JobState(j.records)
            #expect(st.failed[.S47] != nil, "\(mode): fails at the image write, after S45 made the partition")
            let root = try #require(st.created["root"])
            #expect(try LiveLab.zeroHead(c, root), "\(mode): not one byte of the image reached the partition")
            #expect(live.chokepoint.records.allSatisfy { $0.argv.first != "<raw rw>" }, "\(mode): the root partition was never opened for writing")
            // Roll back: the original table returns.
            let rb = LiveLab.engine(c, live: LiveLab.live(c), release: rel, journal: try ChainJournal(directory: c.journalDir, jobID: j.jobID), profile: profile)
            #expect(try rb.rollback() == .rolledBack)
            #expect(try c.backend.topology().digestForm == original.digestForm)
        }
    }

    @Test(.enabled(if: ImageLab.long)) func nothingIsWrittenWithoutAReleaseOrFromOutsideIt() throws {
        let c = try ImageLab.fresh(.j293); defer { c.finish() }
        let profile = try ImageLab.profile()
        let original = try c.backend.topology()
        let rel = try LiveLab.privateRelease(c)
        let plan = try LiveLab.plan(c, profile: profile, release: rel.0)
        let live = LiveLab.live(c)
        try live.arm(plan: plan, original: original)
        let mac = try #require(original.macOS)
        // No release given: even an allowed shape is refused, and the resize the supervisor would launch too.
        #expect(throws: SafetyRefusal.self) { try live.addPartition(after: mac.uuid, content: "Apple_APFS", label: "X", bytes: 1 << 30) }
        #expect(throws: SafetyRefusal.self) { try live.authorizeResize(["/usr/sbin/diskutil", "apfs", "resizeContainer", mac.identifier, "\(plan.macOS.to)B"]) }
        // Growing back to the original size is a rollback's move and needs no release.
        try live.authorizeResize(["/usr/sbin/diskutil", "apfs", "resizeContainer", mac.identifier, "\(plan.macOS.from)B"])
        // A release that isn't on disk as the manifest says: refused.
        let missing = c.dir.appendingPathComponent("not-there", isDirectory: true)
        live.expectRelease(rel.0, in: missing)
        #expect(throws: SafetyRefusal.self) { try live.addPartition(after: mac.uuid, content: "Apple_APFS", label: "X", bytes: 1 << 30) }
        // With the release in place the image still has to come from inside that directory.
        live.expectRelease(rel.0, in: rel.1)
        let stray = c.dir.appendingPathComponent("elsewhere.xz")
        try FileManager.default.copyItem(at: rel.1.appendingPathComponent(rel.0.rootImage), to: stray)
        #expect(throws: SafetyRefusal.self) { _ = try live.writeImage(mac.uuid, source: stray, compressed: true, progress: nil) }
        #expect(throws: SafetyRefusal.self) { _ = try live.writeImage(mac.uuid, source: rel.1.appendingPathComponent(rel.0.rootImage), compressed: false, progress: nil) }
        // And never onto a protected partition: macOS's own.
        #expect(throws: SafetyRefusal.self) { _ = try live.writeImage(mac.uuid, source: rel.1.appendingPathComponent(rel.0.rootImage), compressed: true, progress: nil) }
        #expect(try c.backend.freshTopology().digestForm == original.digestForm)
    }

    @Test(.enabled(if: ImageLab.long)) func aHelperWithALiveTargetRunsAJobOverXPC() throws {
        let c = try ImageLab.fresh(.j313); defer { c.finish() }
        let rel = try ImageLab.release()
        let profile = try ImageLab.profile("J313")
        let original = try c.backend.topology()
        var cfg = HelperConfig(target: .live(ImageTargetAuthority(imagePath: c.image)), journalDirectory: c.journalDir, workDirectory: c.workDir, profileID: "J313",
                               release: rel.0, releaseSource: rel.1,
                               policy: ConnectionPolicy(clientRequirement: CodeIdentity.ownDesignatedRequirement() ?? "", minimumClientBuild: 0),
                               idleTimeout: 0.3, resizeTiming: .tests)
        cfg.workDirectory = c.workDir
        cfg.requireConfirmation = false   // the confirmation verbs are sfappimage's run on an image
        let h = InProcessHelper(cfg)
        let client = h.client()
        #expect(try client.info().target.hasPrefix("live "))
        #expect(try client.topology().layoutDigest == original.layoutDigest)
        let plan = try ImageLab.plan(c, profile: profile)
        let job = try client.begin(plan)
        try client.resume(job)
        let s = try client.wait(job)
        #expect(s.end == "handed-off" && s.lastError == nil, "\(s)")
        try ImageEngineTests.expectInstalled(c, journal: try ChainJournal(directory: c.journalDir, jobID: UUID(uuidString: job)!), plan: plan)
        try FaultInjectionTests.expectLinuxUntouched(c, original: original)
        let removal = try client.removalPlan(job)
        let rjob = try client.beginRemoval(job, digest: removal.digest)
        try client.resume(rjob)
        #expect(try client.wait(rjob).end == "committed")
        #expect(try c.backend.topology().digestForm == original.digestForm)
    }
}

@Suite("Live backend: fault injection on disk images", .serialized, .enabled(if: ImageLab.enabled))
struct LiveBackendFaultTests {

    @Test(.enabled(if: ImageLab.long)) func failingDiskutilStopsThenRollBackOrTryAgain() throws {
        let c = try ImageLab.fresh(.j293); defer { c.finish() }
        let profile = try ImageLab.profile()
        let original = try c.backend.topology()
        let rel = try ImageLab.release()
        let plan = try ImageLab.plan(c, profile: profile)
        let runner = FailingRunner(match: { $0.contains("addPartition") && $0.contains("%0FC63DAF-8483-4772-8E79-3D69D8477DE4%") },
                                   stderr: "Error: -69850: The disk is too small for the requested operation (simulated)")
        let j = try ChainJournal(directory: c.journalDir)
        let e = LiveLab.engine(c, live: LiveLab.live(c, runner: runner), release: rel, journal: j, profile: profile)
        try e.begin(plan)
        do { try e.run(); Issue.record("should have failed") } catch let err as EngineError {
            #expect(err.errorClass == .appleTool && (err.detail ?? "").contains("-69850"))
        }
        #expect(JobState(j.records).failed[.S45] != nil)
        let (fork, fj) = try ImageLab.fork(c, journal: j)
        defer { fork.finish() }
        #expect(try LiveLab.engine(fork, live: LiveLab.live(fork), release: rel, journal: fj, profile: profile).rollback() == .rolledBack)
        #expect(try fork.backend.topology().digestForm == original.digestForm)
        fork.finish()
        try c.backend.attach()
        let again = LiveLab.engine(c, live: LiveLab.live(c), release: rel, journal: try ChainJournal(directory: c.journalDir, jobID: j.jobID), profile: profile)
        #expect(try again.run() == .handedOff)
    }

    @Test(.enabled(if: ImageLab.long)) func aWriteThatFailsHalfwayOrWritesABadBitIsNeverTrusted() throws {
        for fault in ["short-write", "flipped-bit"] {
            let c = try ImageLab.fresh(.j293); defer { c.finish() }
            let profile = try ImageLab.profile()
            let rel = try ImageLab.release()
            let plan = try ImageLab.plan(c, profile: profile)
            let bad = LiveLab.live(c)
            if fault == "short-write" { bad.faults.shortWriteAfter = 4 << 20 } else { bad.faults.flipBitAtByte = 9 << 20 }
            let j = try ChainJournal(directory: c.journalDir)
            let e = LiveLab.engine(c, live: bad, release: rel, journal: j, profile: profile)
            try e.begin(plan)
            #expect(throws: EngineError.self, "\(fault)") { try e.run() }
            let st = JobState(j.records)
            #expect(st.failed[.S47] != nil && st.evidence[.S47] == nil, "\(fault): S47 has no evidence, so nothing trusts the partial image")
            // A fresh engine, with a healthy backend, restarts the image write and finishes.
            let again = LiveLab.engine(c, live: LiveLab.live(c), release: rel, journal: try ChainJournal(directory: c.journalDir, jobID: j.jobID), profile: profile)
            #expect(try again.run() == .handedOff, "\(fault)")
            try ImageEngineTests.expectInstalled(c, journal: try ChainJournal(directory: c.journalDir, jobID: j.jobID), plan: plan)
        }
    }

    @Test(.enabled(if: LiveLab.heavy), .enabled(if: ImageLab.long)) func powerLossAfterEachDiskStepResumesThroughTheLiveBackend() throws {
        let c = try ImageLab.fresh(.j313); defer { c.finish() }
        let profile = try ImageLab.profile("J313")
        let original = try c.backend.topology()
        let rel = try ImageLab.release()
        let plan = try ImageLab.plan(c, profile: profile)
        let j = try ChainJournal(directory: c.journalDir)
        try LiveLab.engine(c, live: LiveLab.live(c), release: rel, journal: j, profile: profile).begin(plan)
        for cut in [StepCode.S25, .S30, .S32, .S35, .S40, .S45, .S46, .S47, .S42, .S50, .S52, .S55, .S60, .S68] {
            let live = LiveLab.live(c)
            let e = LiveLab.engine(c, live: live, release: rel, journal: try ChainJournal(directory: c.journalDir, jobID: j.jobID), profile: profile,
                                   faults: FaultPlan(powerLossAfterCommand: cut))
            #expect(throws: SimulatedKill.self, "\(cut)") { try e.run() }
            #expect(!c.backend.isAttached(), "\(cut): the image is gone, as in a power cut")
            try live.attach()
            #expect(c.backend.isAttached())
        }
        let live = LiveLab.live(c)
        #expect(try LiveLab.engine(c, live: live, release: rel, journal: try ChainJournal(directory: c.journalDir, jobID: j.jobID), profile: profile).run() == .handedOff)
        try ImageEngineTests.expectInstalled(c, journal: try ChainJournal(directory: c.journalDir, jobID: j.jobID), plan: plan)
        try FaultInjectionTests.expectLinuxUntouched(c, original: original)
        #expect(live.chokepoint.tripped == nil)
    }

    @Test(.enabled(if: ImageLab.long)) func aFailedResizeIsReportedAndNothingElseRuns() throws {
        let c = try ImageLab.fresh(.j293); defer { c.finish() }
        let profile = try ImageLab.profile()
        let original = try c.backend.topology()
        let rel = try ImageLab.release()
        let plan = try ImageLab.plan(c, profile: profile)
        let j = try ChainJournal(directory: c.journalDir)
        let live = LiveLab.live(c)
        let e = LiveLab.engine(c, live: live, release: rel, journal: j, profile: profile,
                               launcher: FaultLauncher(.fail("Error: -69606: A problem occurred while verifying the container (simulated)")))
        try e.begin(plan)
        do { try e.run(); Issue.record("should fail") } catch let err as EngineError {
            #expect(err.message.contains("First Aid") && (err.detail ?? "").contains("-69606"))
        }
        #expect(try c.backend.topology().digestForm == original.digestForm)
        #expect(live.chokepoint.records.allSatisfy { $0.argv.first == "<raw ro>" }, "the resize was authorised and launched by the supervisor; no other command ran (only read-only opens)")
    }

    /// The fork sweep of `FaultInjectionTests`, through the live backend: after each sampled journal
    /// record the image and journal are forked as a crash would leave them; on the fork a fresh engine
    /// must resume to the end, and on a second fork roll back to the original table.
    @Test(.enabled(if: LiveLab.heavy), .enabled(if: ImageLab.long)) func everySampledJournalStateHasAWayForwardAndBackThroughTheLiveBackend() throws {
        let c = try ImageLab.fresh(.j313); defer { c.finish() }
        let profile = try ImageLab.profile("J313")
        let original = try c.backend.topology()
        let rel = try ImageLab.release()
        let plan = try ImageLab.plan(c, profile: profile)
        let j = try ChainJournal(directory: c.journalDir)
        let e = LiveLab.engine(c, live: LiveLab.live(c), release: rel, journal: j, profile: profile)
        try e.begin(plan)
        let sample: Set<UInt64> = ImageLab.sweepRecords ?? [2, 9, 16, 22, 35, 47, 60]
        nonisolated(unsafe) var forward = 0, back = 0
        nonisolated(unsafe) var failures: [String] = []
        j.afterAppend = { rec in
            guard ImageLab.fullSweep || sample.contains(rec.seq) else { return }
            do {
                defer { try? c.backend.attach() }
                let (a, aj) = try ImageLab.fork(c, journal: j)
                defer { a.finish() }
                let (b, bj) = try ImageLab.fork(a, journal: aj)
                if rec.kind != .end {
                    let blive = LiveLab.live(b)
                    if try LiveLab.engine(b, live: blive, release: rel, journal: bj, profile: profile).rollback() != .rolledBack { failures.append("record \(rec.seq): rollback didn't finish") }
                    if try b.backend.topology().digestForm != original.digestForm { failures.append("record \(rec.seq): table differs after rollback") }
                    if blive.chokepoint.tripped != nil { failures.append("record \(rec.seq): the rollback tripped the receipt") }
                    back += 1
                }
                b.finish()
                try a.backend.attach()
                let flive = LiveLab.live(a)
                if try LiveLab.engine(a, live: flive, release: rel, journal: aj, profile: profile).run() != .handedOff { failures.append("record \(rec.seq): forward didn't finish") }
                try ImageEngineTests.expectInstalled(a, journal: aj, plan: plan)
                try FaultInjectionTests.expectLinuxUntouched(a, original: original)
                if flive.chokepoint.tripped != nil { failures.append("record \(rec.seq): the resume tripped the receipt") }
                forward += 1
            } catch {
                failures.append("record \(rec.seq) (\(rec.kind.rawValue) \(rec.step ?? "")): \(error)")
            }
        }
        #expect(try e.run() == .handedOff)
        j.afterAppend = nil
        #expect(failures.isEmpty, "\(failures)")
        print("liveSweep: \(j.records.count) records, \(forward) forward resumes, \(back) rollbacks, full=\(ImageLab.fullSweep)")
        #expect(forward >= (ImageLab.fullSweep ? j.records.count - 1 : sample.count - 1))
    }
}
