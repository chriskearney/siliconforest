import Foundation
import Testing
@testable import SFEngine
import SFInstallKit

/// The kernel collection linked on the Mac (PAYLOAD.md §13): S17's assembly, the release rules, PDSF
/// packing, and the whole install on a disk image. Real kc-builder and real inputs only with
/// SF_KC_RELEASE=<format-3 release directory> (the builder's rehearsal; nothing is committed).
@Suite("Kernel collection: linked on this Mac", .serialized)
struct KernelCollectionTests {
    static func scratch() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("sf-kc-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static func release(_ t: URL) throws -> ReleaseManifest { try RehearsalRelease.make(in: t.appendingPathComponent("release")) }

    @Test func assemblesToTheExpectedHashInAPrivateDirectory() throws {
        let t = try Self.scratch(); defer { try? FileManager.default.removeItem(at: t) }
        let m = try Self.release(t)
        let kc = try #require(m.kernelCollection)
        let r = try KernelCollectionAssembler.assemble(kc, release: m, source: { t.appendingPathComponent("release").appendingPathComponent($0) },
                                                       into: t.appendingPathComponent("kc"))
        #expect(r.sha256 == kc.collectionSHA256 && r.bytes == kc.collectionBytes)
        #expect(KernelCollectionAssembler.accepted(kc, in: t.appendingPathComponent("kc")) != nil)
        #expect(!FileManager.default.fileExists(atPath: t.appendingPathComponent("kc/inputs").path))
        let mode = try FileManager.default.attributesOfItem(atPath: t.appendingPathComponent("kc").path)[.posixPermissions] as? Int
        #expect(mode == 0o700)
    }

    @Test func refusesATamperedInputAndLeavesNoCollection() throws {
        let t = try Self.scratch(); defer { try? FileManager.default.removeItem(at: t) }
        let m = try Self.release(t)
        let kc = try #require(m.kernelCollection)
        let victim = t.appendingPathComponent("release").appendingPathComponent(kc.bundles[1].files[1].artifact)
        let h = try FileHandle(forWritingTo: victim); try h.seekToEnd(); try h.write(contentsOf: Data("x".utf8)); try h.close()
        #expect(throws: EngineError.self) {
            _ = try KernelCollectionAssembler.assemble(kc, release: m, source: { t.appendingPathComponent("release").appendingPathComponent($0) },
                                                       into: t.appendingPathComponent("kc"))
        }
        #expect(KernelCollectionAssembler.accepted(kc, in: t.appendingPathComponent("kc")) == nil)
        #expect(!FileManager.default.fileExists(atPath: t.appendingPathComponent("kc/collection").path))
    }

    @Test func refusesAnythingButTheExpectedBytes() throws {
        let t = try Self.scratch(); defer { try? FileManager.default.removeItem(at: t) }
        let m = try Self.release(t)
        var kc = try #require(m.kernelCollection)
        kc.collectionSHA256 = String(repeating: "0", count: 64)
        do {
            _ = try KernelCollectionAssembler.assemble(kc, release: m, source: { t.appendingPathComponent("release").appendingPathComponent($0) },
                                                       into: t.appendingPathComponent("kc"))
            Issue.record("should refuse")
        } catch let e as EngineError {
            #expect(e.message.contains("isn't the release's"))
        }
        #expect(!FileManager.default.fileExists(atPath: t.appendingPathComponent("kc/collection").path))
    }

    @Test func refusesAFailingOrHangingTool() throws {
        let t = try Self.scratch(); defer { try? FileManager.default.removeItem(at: t) }
        for (script, timeout, want) in [("#!/bin/sh\nexit 3\n", 600.0, "failed"), ("#!/bin/sh\nsleep 30\n", 1.0, "longer")] {
            let d = t.appendingPathComponent(UUID().uuidString)
            let rel = d.appendingPathComponent("release")
            var m = try RehearsalRelease.make(in: rel)
            let tool = rel.appendingPathComponent("kc-builder")
            try Data(script.utf8).write(to: tool)
            let i = try #require(m.artifacts.firstIndex { $0.name == "kc-builder" })
            m.artifacts[i].sha256 = try SHA256Hasher.file(tool)
            m.artifacts[i].bytes = Int64(script.utf8.count)
            do {
                _ = try KernelCollectionAssembler.assemble(m.kernelCollection!, release: m, source: { rel.appendingPathComponent($0) },
                                                           into: d.appendingPathComponent("kc"), timeout: timeout)
                Issue.record("should refuse")
            } catch let e as EngineError {
                #expect(e.message.contains(want), "\(e.message)")
            }
        }
    }

    @Test func releaseRulesRefuseOptionsAndPathsOutsideTheFormat() throws {
        let t = try Self.scratch(); defer { try? FileManager.default.removeItem(at: t) }
        let m = try Self.release(t)
        let good = try #require(m.kernelCollection)
        try good.validate(release: m)
        let mutations: [(inout KernelCollection) -> Void] = [
            { $0.linkArgs.insert(contentsOf: ["-classic", "x"], at: 0) },
            { $0.linkArgs += ["-aux-o", "x"] },
            { $0.linkArgs[$0.linkArgs.firstIndex(of: "-kernel")! + 1] = "/etc/passwd" },
            { $0.linkArgs[$0.linkArgs.firstIndex(of: "-kext")! + 1] = "kexts/../../x.kext" },
            { $0.linkArgs[$0.linkArgs.firstIndex(of: "-o")! + 1] = "/tmp/out" },
            { $0.bundles.reverse() },
            { $0.bundles[0].files[0].path = "../Info.plist" },
            { $0.bundles[0].files[0].artifact = "kc.kernel" },
            { $0.bundles[0].files[0].mode = 0o4755 },
            { $0.tool = "not-in-release" },
            { $0.collectionSHA256 = "" },
        ]
        for (i, mutate) in mutations.enumerated() {
            var kc = good
            mutate(&kc)
            #expect(throws: EngineError.self, "mutation \(i)") { try kc.validate(release: m) }
        }
    }

    @Test func pdsfRecordsRoundTrip() throws {
        var collection = Data(count: 3 << 20)
        for i in stride(from: 0, to: collection.count, by: 4096) { collection[i] = UInt8(truncatingIfNeeded: i >> 12) }
        let k = try PDSF.kernelBin(bootargs: "rd=uuid sfnvme_part=abc", collection: collection)
        let recs = try PDSF.records(k)
        #expect(recs.map(\.0) == [1, 2])
        #expect(String(decoding: recs[0].1, as: UTF8.self) == "bootargs=rd=uuid sfnvme_part=abc\n")
        #expect(recs[1].1 == collection)
        #expect(k.count % 16 == 0 && k.count < collection.count)
        #expect(try PDSF.kernelBin(bootargs: "rd=uuid sfnvme_part=abc", collection: collection) == k)   // deterministic: S42's read-back
        // SF_PDSF_OUT=<dir>: leave both files for the boot side's reader (pdsf_pack.py list / gunzip cross-check).
        if let out = ProcessInfo.processInfo.environment["SF_PDSF_OUT"] {
            try k.write(to: URL(fileURLWithPath: out).appendingPathComponent("kernel.bin"))
            try collection.write(to: URL(fileURLWithPath: out).appendingPathComponent("collection"))
        }
        #expect(throws: EngineError.self) { _ = try PDSF.kernelBin(bootargs: String(repeating: "a", count: 700), collection: collection) }
        #expect(throws: EngineError.self) { _ = try PDSF.kernelBin(bootargs: "tab\there", collection: collection) }
    }

    @Test func installJSONMapping() throws {
        let json = """
            {"boot": {"bootargs": "bootargs.template", "stage1": "sf-stage1.bin", "stage2": "boot.bin"},
             "root": {"fs_uuid": "11111111-2222-4333-8444-555555555555"},
             "kernel_collection": {"format": "siliconforest-kc/1", "kernel": "kc.kernel", "kc_base": "fffffe0006000000",
               "tool": {"artifact": "kc-builder", "signing": "ad-hoc", "license_artifact": "LICENSE.kc-tools"},
               "bundles": [{"dir": "kexts/A.kext", "files": [{"path": "Contents/Info.plist", "artifact": "kc.kexts.A.kext.Contents.Info.plist", "mode": 420}]}],
               "link_args": ["-kc-base", "fffffe0006000000", "-kernel", "kernel", "-kext", "kexts/A.kext", "-o", "@OUTPUT@"],
               "collection_sha256": "\(String(repeating: "ab", count: 32))", "collection_bytes": 33842862}}
            """
        let (kc, fs) = try KernelCollection.fromInstallJSON(Data(json.utf8))
        #expect(kc.tool == "kc-builder" && kc.toolSigning == "ad-hoc" && kc.bootargsTemplate == "bootargs.template")
        #expect(kc.collectionBytes == 33_842_862 && kc.bundles.first?.files.first?.mode == 0o644)
        #expect(fs == "11111111-2222-4333-8444-555555555555")
    }
}

/// Image-backed: S17 runs before the first disk write, and the whole install writes a PDSF kernel.bin
/// whose collection is the release's.
@Suite("Kernel collection on disk images", .serialized, .enabled(if: ImageLab.enabled))
struct KernelCollectionImageTests {
    static func engine(_ c: ImageLab.Case, release: ReleaseManifest, source: URL, journal: ChainJournal, profile: DeviceProfile) -> InstallEngine {
        InstallEngine(backend: c.backend, journal: journal, profile: profile, release: release, releaseSource: source,
                      workDir: c.workDir, faults: FaultPlan(), launcher: SpawnLauncher(), resizeTiming: .tests)
    }
    static func plan(_ c: ImageLab.Case, profile: DeviceProfile, release: ReleaseManifest) throws -> EnginePlan {
        let t = try c.backend.topology()
        let mac = try #require(t.macOS)
        return try EnginePlanner.installPlan(topology: t, limits: try c.backend.limits(store: mac.uuid), profile: profile, release: release,
                                             request: InstallRequest(siliconForestBytes: 20 * Bytes.gb, installName: "SiliconForest", installID: "a1b2c3d4"))
    }

    @Test func aCollectionThatDoesNotMatchStopsTheJobBeforeAnyWrite() throws {
        let c = try ImageLab.fresh(.j293); defer { c.finish() }
        let profile = try ImageLab.profile()
        let src = c.dir.appendingPathComponent("release")
        var release = try RehearsalRelease.make(in: src)
        release.kernelCollection!.collectionSHA256 = String(repeating: "0", count: 64)
        let original = try c.backend.topology()
        let plan = try Self.plan(c, profile: profile, release: release)
        let j = try ChainJournal(directory: c.journalDir)
        let e = Self.engine(c, release: release, source: src, journal: j, profile: profile)
        try e.begin(plan)
        #expect(throws: EngineError.self) { try e.run() }
        let st = JobState(j.records)
        #expect(st.noChangesMade)
        #expect(st.status[.S17] == .intent && st.status[.S20] == nil)
        #expect(try c.backend.topology().digestForm == original.digestForm)
        #expect(c.backend.chokepoint.records.isEmpty)
    }

    @Test func installWritesThePersonalisedPDSFKernel() throws {
        let c = try ImageLab.fresh(.j293); defer { c.finish() }
        let profile = try ImageLab.profile()
        let src = c.dir.appendingPathComponent("release")
        let real = ProcessInfo.processInfo.environment["SF_KC_RELEASE"].map { URL(fileURLWithPath: $0) }
        let release = try real.map { try RehearsalRelease.make(in: src, kernelCollectionFrom: $0) } ?? RehearsalRelease.make(in: src)
        let kc = try #require(release.kernelCollection)
        let plan = try Self.plan(c, profile: profile, release: release)
        let j = try ChainJournal(directory: c.journalDir)
        let e = Self.engine(c, release: release, source: src, journal: j, profile: profile)
        try e.begin(plan)
        #expect(try e.run() == .handedOff)
        let st = JobState(j.records)
        #expect(st.evidence[.S17]?["sha256"]?.string == kc.collectionSHA256)
        let t = try c.backend.topology()
        let rootU = try #require(st.created["root"])
        let bootU = try #require(st.created["boot"])
        let root = try #require(t.partition(uuid: rootU))
        let fat = try c.backend.fatURL(bootU)
        let fsUUID = try #require(release.rootFilesystemUUID)
        let recs = try PDSF.records(try Data(contentsOf: fat.appendingPathComponent("sf/kernel.bin")))
        let config = String(decoding: recs[0].1, as: UTF8.self)
        #expect(config.contains("sfnvme_part=\(root.uuid.lowercased())") && config.contains("sfnvme_part_lba=\(root.offset / t.blockSize)"))
        #expect(config.contains("boot-uuid=\(fsUUID.lowercased())") && !config.contains("@SF_"))
        #expect(recs[1].0 == 2 && SHA256Hasher.hex(recs[1].1) == kc.collectionSHA256 && Int64(recs[1].1.count) == kc.collectionBytes)
        #expect(c.backend.chokepoint.records.allSatisfy { ImageGuard.resolve($0.image) == ImageGuard.resolve(c.image.path) })
        if real != nil {
            print("SF_KC_RELEASE: collection \(kc.collectionSHA256) (\(kc.collectionBytes) B) linked in \(st.evidence[.S17]?["ms"]?.int ?? -1) ms; " +
                  "kernel.bin \(SHA256Hasher.hex(try Data(contentsOf: fat.appendingPathComponent("sf/kernel.bin"))))")
        }
    }
}
