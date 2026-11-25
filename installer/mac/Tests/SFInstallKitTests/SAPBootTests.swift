import Foundation
import Testing
@testable import SFEngine

/// S42's A/B boot and SAP files (abboot, docs/sap/IMAGE.md).
@Suite("S42: A/B boot and SAP files on SFBOOT")
struct SAPBootTests {
    @Test func theTrustTokenLineJoinsTheArguments() throws {
        // make_release.py appends sf_trust= as its own line when it fits (docs/sap/IMAGE.md)
        let t = "# comment\n-v root-uuid=@SF_FSUUID@ part=@SF_PART_LBA@:@SF_PART_BLOCKS@\nsf_trust=1:AAAA\n"
        let a = try InstallEngine.bootArguments(template: t, rootFilesystemUUID: "37215AB4-0000-4000-8000-000000000001",
                                                partUUID: "P", firstBlock: 6, blocks: 7)
        #expect(a == "-v root-uuid=37215ab4-0000-4000-8000-000000000001 part=6:7 sf_trust=1:AAAA")
    }

    static func release(stage2B: String? = nil, bootState: String? = nil, trust: String? = nil) -> ReleaseManifest {
        var r = ReleaseManifest.stubOnly(bytes: 1, sha256: String(repeating: "0", count: 64), version: "t")
        r.stage2B = stage2B; r.bootState = bootState; r.trust = trust
        return r
    }

    @Test func extrasAreOptionalAndTheRecordComesLast() {
        #expect(InstallEngine.sfbootExtras(Self.release()).isEmpty)
        let all = InstallEngine.sfbootExtras(Self.release(stage2B: "boot-b.bin", bootState: "bootstate.bin", trust: "sf-trust.txt"))
        #expect(all.map { $0.1 } == ["b/boot.bin", "trust", "bootstate.bin"])
        #expect(all.map { $0.0 } == ["boot-b.bin", "sf-trust.txt", "bootstate.bin"])
        #expect(InstallEngine.sfbootExtras(Self.release(trust: "sf-trust.txt")).map { $0.1 } == ["trust"])
    }

    @Test func oldManifestsKeepTheirDigest() throws {
        // nil optional fields are not encoded: a release without them binds plans exactly as before
        let enc = String(decoding: try JSONEncoder().encode(Self.release()), as: UTF8.self)
        #expect(!enc.contains("stage2B") && !enc.contains("bootState") && !enc.contains("\"trust\""))
    }
}
