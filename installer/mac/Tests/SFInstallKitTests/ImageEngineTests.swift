import Foundation
import Testing
@testable import SFEngine
@testable import SFHelperKit
import SFInstallKit

/// Real `hdiutil`/`diskutil` against disk images only (every mutating call passes the chokepoint).
@Suite("Engine on disk images", .serialized, .enabled(if: ImageLab.enabled))
struct ImageEngineTests {

    /// Everything a finished install must show on the disk, checked directly on the image.
    static func expectInstalled(_ c: ImageLab.Case, journal: ChainJournal, plan: EnginePlan) throws {
        let (release, _) = try ImageLab.release()
        let st = JobState(journal.records)
        #expect(st.end == .handedOff)
        let t = try c.backend.topology()
        let mac = try #require(t.partition(uuid: plan.macOS.store))
        #expect(mac.size == plan.macOS.to)
        let stubU = try #require(st.created["stub"])
        let stub = try #require(t.partition(uuid: stubU))
        let bootU = try #require(st.created["boot"])
        let boot = try #require(t.partition(uuid: bootU))
        let rootU = try #require(st.created["root"])
        let root = try #require(t.partition(uuid: rootU))
        #expect(stub.offset == mac.end && boot.offset == stub.end && root.offset == boot.end)
        #expect(stub.size == plan.partition("stub")!.bytes && boot.size == plan.partition("boot")!.bytes)
        // diskutil carves its 128 MiB Apple_Boot booter out of the root's span; S46 erases the booter.
        #expect([plan.partition("root")!.bytes, plan.partition("root")!.bytes - InstallEngine.booterBytes].contains(root.size))
        #expect(!t.partitions.contains { $0.content == "Apple_Boot" })
        #expect(stub.content == "Apple_APFS" && boot.content == "EFI" && boot.filesystem == "msdos" && root.content == "Linux Filesystem")
        let roles = Set(stub.apfs?.volumes.flatMap(\.roles) ?? [])
        #expect(roles.isSuperset(of: ["System", "Data", "Preboot", "Recovery"]))
        expectAsahiStubVolumes(stub.apfs?.volumes ?? [])
        // The image up to the firmware slot is the release's (S50/S52 then write their slots inside it).
        let head = try c.backend.readRaw(root.uuid, offset: 0, count: 8)
        #expect(String(decoding: head, as: UTF8.self) == "SFROOT1 ")
        let receipt = try c.backend.readRaw(root.uuid, offset: release.receiptSlotOffset, count: 32)
        #expect(String(decoding: receipt.prefix(24), as: UTF8.self).hasPrefix("SFRCPT1\ninstall=a1b2c3d4"))
        let fw = try c.backend.readRaw(root.uuid, offset: release.firmwareSlotOffset, count: 10)
        #expect(String(decoding: fw, as: UTF8.self) == "SFFWSLOT1\n")
        let fat = try c.backend.fatURL(boot.uuid)
        // sf/kernel.bin: PDSF records, the collection S17 linked and checked, personalised for this root.
        let recs = try PDSF.records(try Data(contentsOf: fat.appendingPathComponent("sf/kernel.bin")))
        let config = String(decoding: recs[0].1, as: UTF8.self)
        #expect(config.contains("sfnvme_part=\(root.uuid.lowercased())") && !config.contains("@") && !config.contains("#"))
        let bs = try c.backend.topology().blockSize
        #expect(config.contains("sfnvme_part_lba=\(root.offset / bs) ") && config.contains("sfnvme_part_blocks=\(root.size / bs) "))
        #expect(SHA256Hasher.hex(recs[1].1) == release.kernelCollection?.collectionSHA256)
        let sys = try c.backend.volumeURL(store: stub.uuid, role: "System")
        let app = sys.appendingPathComponent("SiliconForest Setup.app/Contents")
        for f in ["MacOS/sf-launcher", "MacOS/SFRecovery", "Resources/sf-step2.sh", "Resources/boot.bin", "Info.plist"] {
            #expect(FileManager.default.fileExists(atPath: app.appendingPathComponent(f).path), "\(f)")
        }
        #expect(FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("MacOS/sf-launcher").path))
        #expect(FileManager.default.fileExists(atPath: sys.appendingPathComponent(".IAPhysicalMedia").path))
        #expect(FileManager.default.fileExists(atPath: sys.appendingPathComponent("System/Library/CoreServices/SystemVersion.plist.sf-hidden").path))
        #expect(st.approvals.map(\.step) == ["S20", "S65"])
    }

    @Test(.enabled(if: ImageLab.long)) func j293InstallThenRemoveRestoresTheOriginalTable() throws {
        let c = try ImageLab.fresh(.j293); defer { c.finish() }
        let profile = try ImageLab.profile()
        let original = try c.backend.topology()
        let plan = try ImageLab.plan(c, profile: profile)
        let j = try ChainJournal(directory: c.journalDir)
        let e = try ImageLab.engine(c, journal: j, profile: profile)
        try e.begin(plan)
        #expect(try e.run() == .handedOff)
        try Self.expectInstalled(c, journal: j, plan: plan)
        // Every mutating command went through the chokepoint, against this image only.
        #expect(c.backend.chokepoint.records.allSatisfy { ImageGuard.resolve($0.image) == ImageGuard.resolve(c.image.path) })
        #expect(!c.backend.chokepoint.records.isEmpty)

        // Remove: exactly what the journal proves is ours, then regrow macOS.
        let proof = try InstallProofReader.proof(from: j)
        let removal = try EnginePlanner.removalPlan(topology: try c.backend.topology(), profile: profile, proof: proof)
        let rj = try ChainJournal(directory: c.journalDir)
        let re = try ImageLab.engine(c, journal: rj, profile: profile)
        re.proof = proof
        try re.begin(removal)
        #expect(try re.run() == .committed)
        let after = try c.backend.topology()
        #expect(after.digestForm == original.digestForm)
        #expect(JobState(rj.records).approvals.map(\.step) == ["U10"])
    }

    /// Preview7: S65 runs the one-time bless through an injected runner (never the real tool), U10 resets only a
    /// selection that names the stub, and the removal still restores the original table.
    final class RecordingBlessRunner: BlessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [[String]] = []
        private var selection = "/dev/disk0s1\n"
        var failSet = false
        var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return _calls }
        func execute(_ argv: [String]) -> BlessResult {
            lock.lock(); defer { lock.unlock() }
            _calls.append(argv)
            guard BlessGuard.isAllowed(argv) else { return BlessResult(status: 126, output: "refused") }
            if argv == BlessGuard.getBoot { return BlessResult(status: 0, output: selection) }
            if failSet && argv.contains("--setBoot") { return BlessResult(status: 1, output: "simulated failure") }
            selection = (BlessGuard.systemMountedFrom(argv[2]) ?? "?") + "\n"
            return BlessResult(status: 0, output: "")
        }
    }

    @Test(.enabled(if: ImageLab.long)) func blessIsRunThroughTheRunnerThenRemovalResetsIt() throws {
        let c = try ImageLab.fresh(.j293); defer { c.finish() }
        let profile = try ImageLab.profile()
        let original = try c.backend.topology()
        let plan = try ImageLab.plan(c, profile: profile)
        let j = try ChainJournal(directory: c.journalDir)
        let e = try ImageLab.engine(c, journal: j, profile: profile)
        let runner = RecordingBlessRunner()
        e.bless = runner
        try e.begin(plan)
        #expect(try e.run() == .handedOff)
        let st = JobState(j.records)
        let ev = try #require(st.evidence[.S65])
        #expect(ev["blessed"]?.string == "startup disk" && ev["exit"]?.int == 0)
        #expect(ev["confirmed"]?.string == "getBoot names the stub")
        #expect(runner.calls.first?.contains("--setBoot") == true && runner.calls.first?.contains("--nextonly") == false, "persistent: the stub becomes the startup disk")
        #expect(runner.calls.allSatisfy { !$0.contains("--nextonly") }, "the helper never sets a one-time boot")
        #expect(runner.calls.allSatisfy { BlessGuard.isAllowed($0) })
        #expect(!st.approvals.map(\.step).contains("S65"), "a real bless is not left as a simulated approval")

        // Removal: the selection names the stub, so U10 sets macOS back, once; the table returns to the original.
        let proof = try InstallProofReader.proof(from: j)
        let removal = try EnginePlanner.removalPlan(topology: try c.backend.topology(), profile: profile, proof: proof)
        let rj = try ChainJournal(directory: c.journalDir)
        let re = try ImageLab.engine(c, journal: rj, profile: profile)
        re.proof = proof
        re.bless = runner
        try re.begin(removal)
        #expect(try re.run() == .committed)
        let u10 = try #require(JobState(rj.records).evidence[.U10])
        #expect(u10["reset"]?.string == "macOS" || (u10["reset"]?.string == "no" && u10["why"]?.string?.contains("isn't mounted") == true))
        // S65's persistent selection of the stub, then (because getBoot names the stub) U10's reset to macOS.
        #expect(runner.calls.filter { $0.contains("--setBoot") }.count == 1 + (u10["reset"]?.string == "macOS" ? 1 : 0))
        #expect(try c.backend.topology().digestForm == original.digestForm)
    }

    @Test(.enabled(if: ImageLab.long)) func aFailingBlessLeavesTheInstallDoneWithTheManualCommand() throws {
        let c = try ImageLab.fresh(.j293); defer { c.finish() }
        let profile = try ImageLab.profile()
        let plan = try ImageLab.plan(c, profile: profile)
        let j = try ChainJournal(directory: c.journalDir)
        let e = try ImageLab.engine(c, journal: j, profile: profile)
        let runner = RecordingBlessRunner(); runner.failSet = true
        e.bless = runner
        try e.begin(plan)
        #expect(try e.run() == .handedOff, "bless failing must not fail the install")
        let ev = try #require(JobState(j.records).evidence[.S65])
        #expect(ev["blessed"]?.string == "no" && ev["exit"]?.int == 1)
        #expect(ev["manual"]?.string?.hasPrefix("sudo /usr/sbin/bless --mount \"/Volumes/") == true)
    }

    /// Preview13: the volume owner's login. The fake sees the password only through the secret's bytes (its stdin),
    /// the journal never has it, it is wiped after the one use, and a retry after a failure uses a fresh login.
    final class PasswordBlessRunner: SFEngine.PasswordBlessRunner, @unchecked Sendable {
        private let lock = NSLock()
        var calls: [[String]] = [], passwords: [String] = [], failFirst = true
        private var selection = "/dev/disk0s1\n"
        func execute(_ argv: [String]) -> BlessResult {
            lock.lock(); defer { lock.unlock() }
            calls.append(argv)
            guard BlessGuard.isAllowed(argv) else { return BlessResult(status: 126, output: "refused") }
            if argv == BlessGuard.getBoot { return BlessResult(status: 0, output: selection) }
            return BlessResult(status: 1, output: "bless: owner authentication required")
        }
        func execute(_ argv: [String], password: any SecretBytesProvider) -> BlessResult {
            lock.lock(); defer { lock.unlock() }
            calls.append(argv)
            let pw = password.withBytes { String(decoding: $0, as: UTF8.self) }
            passwords.append(pw)
            if failFirst && passwords.count == 1 { failFirst = false; return BlessResult(status: 1, output: "bless: incorrect password \(pw)") }
            selection = (BlessGuard.systemMountedFrom(argv[2]) ?? "?") + "\n"
            return BlessResult(status: 0, output: "")
        }
    }

    @Test(.enabled(if: ImageLab.long)) func theOwnersLoginGoesOnlyToStdinAndIsNeverJournaled() throws {
        let c = try ImageLab.fresh(.j293); defer { c.finish() }
        let profile = try ImageLab.profile()
        let plan = try ImageLab.plan(c, profile: profile)
        let j = try ChainJournal(directory: c.journalDir)
        let e = try ImageLab.engine(c, journal: j, profile: profile)
        let runner = PasswordBlessRunner()
        e.bless = runner
        let secret = SecureBytes(Data("hunter2 hunter2".utf8))
        e.blessCredential = { BlessCredential(owner: "chris", secret: secret) }
        try e.begin(plan)
        #expect(try e.run() == .handedOff, "a bless that fails must not fail the install")
        #expect(runner.passwords == ["hunter2 hunter2"])
        let call = try #require(runner.calls.first)
        #expect(Array(call.suffix(3)) == ["--user", "chris", "--stdinpass"] && !call.joined(separator: " ").contains("hunter2"), "never an argument")
        #expect(secret.isWiped && secret.isZeroed, "wiped after the one use")
        let ev = try #require(JobState(j.records).evidence[.S65])
        #expect(ev["blessed"]?.string == "no" && ev["needsPassword"]?.string == "yes" && ev["as"]?.string == "chris")
        let text = try String(contentsOf: j.url, encoding: .utf8)
        #expect(!text.contains("hunter2"), "the password is scrubbed from what bless said and never journaled")

        // The finish screen's retry: only the bless, with a new login, on the finished job.
        let retry = SecureBytes(Data("second try".utf8))
        e.blessCredential = { BlessCredential(owner: "chris", secret: retry) }
        try e.retryStartupDisk()
        #expect(runner.passwords == ["hunter2 hunter2", "second try"] && retry.isWiped)
        let ev2 = try #require(JobState(j.records).evidence[.S65])
        #expect(ev2["blessed"]?.string == "startup disk" && ev2["as"]?.string == "chris")
        #expect(!(try String(contentsOf: j.url, encoding: .utf8)).contains("second try"))

        // Remove: the startup disk names the stub (persistent), so U10 puts macOS back, with the owner's login on stdin too.
        let proof = try InstallProofReader.proof(from: j)
        let removal = try EnginePlanner.removalPlan(topology: try c.backend.topology(), profile: profile, proof: proof)
        let rj = try ChainJournal(directory: c.journalDir)
        let re = try ImageLab.engine(c, journal: rj, profile: profile)
        re.proof = proof; re.bless = runner
        let third = SecureBytes(Data("third try".utf8))
        re.blessCredential = { BlessCredential(owner: "chris", secret: third) }
        try re.begin(removal)
        #expect(try re.run() == .committed)
        let u10 = try #require(JobState(rj.records).evidence[.U10])
        if u10["reset"]?.string == "macOS" {
            #expect(runner.passwords.last == "third try" && third.isWiped && u10["as"]?.string == "chris")
            #expect(runner.calls.last(where: { $0.contains("--setBoot") })?.suffix(3) == ["--user", "chris", "--stdinpass"])
        } else {
            #expect(u10["why"]?.string?.contains("isn't mounted") == true, "macOS's volume can't be mounted on an image rehearsal")
        }
        #expect(!(try String(contentsOf: rj.url, encoding: .utf8)).contains("third try"))
    }
}
