import Foundation
import Testing
@testable import SFEngine
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
        // The image up to the firmware slot is the release's (S50/S52 then write their slots inside it).
        let head = try c.backend.readRaw(root.uuid, offset: 0, count: 8)
        #expect(String(decoding: head, as: UTF8.self) == "SFROOT1 ")
        let receipt = try c.backend.readRaw(root.uuid, offset: release.receiptSlotOffset, count: 32)
        #expect(String(decoding: receipt.prefix(24), as: UTF8.self).hasPrefix("SFRCPT1\ninstall=a1b2c3d4"))
        let fw = try c.backend.readRaw(root.uuid, offset: release.firmwareSlotOffset, count: 10)
        #expect(String(decoding: fw, as: UTF8.self) == "SFFWSLOT1\n")
        let fat = try c.backend.fatURL(boot.uuid)
        let kernel = try String(contentsOf: fat.appendingPathComponent("sf/kernel.bin"), encoding: .utf8)
        #expect(kernel.contains("sfnvme_part=\(root.uuid.lowercased())") && !kernel.contains("@SF_PARTUUID@"))
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

    @Test func j293InstallThenRemoveRestoresTheOriginalTable() throws {
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
}
