// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// The engine builds the stub's volumes the way SFStub (and upstream Asahi v0.9.2 stub.py prepare_volume) does.

import Foundation
import Testing
@testable import SFEngine
import SFInstallKit
import SFStub

private func vol(_ id: String, _ uuid: String, _ name: String, _ roles: [String]) -> ImageVolume {
    ImageVolume(identifier: id, uuid: uuid, name: name, roles: roles)
}

private func table(_ vols: [ImageVolume]) -> ImageTopology {
    let mac = ImagePartition(uuid: "MAC", identifier: "disk5s2", content: "Apple_APFS", offset: 1 << 20, size: 100 << 30, volumeName: nil, filesystem: nil,
                             apfs: ImageAPFS(reference: "disk6", uuid: "C-MAC", capacityCeiling: 100 << 30, capacityFree: 1 << 30,
                                             volumes: [vol("disk6s1", "MV", "Macintosh HD", ["System"]), vol("disk6s2", "MD", "Macintosh HD - Data", ["Data"])]))
    let stub = ImagePartition(uuid: "STUB", identifier: "disk5s3", content: "Apple_APFS", offset: mac.end, size: 2 << 30, volumeName: nil, filesystem: nil,
                              apfs: ImageAPFS(reference: "disk7", uuid: "C-STUB", capacityCeiling: 2 << 30, capacityFree: 2 << 30, volumes: vols))
    return ImageTopology(wholeDisk: "disk5", size: stub.end + (1 << 20), blockSize: 4096, partitions: [mac, stub])
}

/// What prepare_volume leaves: exactly these four volumes, Data and System in one group (checked by the image test).
func expectAsahiStubVolumes(_ vols: [ImageVolume], name: String = "SiliconForest") {
    let shape = vols.map { "\($0.roles.joined(separator: ","))=\($0.name)" }.sorted()
    #expect(shape == ["Data=\(name) - Data", "Preboot=Preboot", "Recovery=Recovery", "System=\(name)"])
}

@Suite("Engine: the stub's volumes, as SFStub and upstream prepare_volume make them")
struct StubVolumePlanTests {
    typealias E = InstallEngine

    @Test func theVerbsAreUpstreamsInOrderAndResumeFromAnyPoint() throws {
        var vols = [vol("disk7s1", "V1", "SiliconForest", [])]
        var seen: [String] = []
        while let v = try E.nextStubVolumeVerb(stub: "STUB", name: "SiliconForest", in: table(vols)) {
            seen.append(v.summary)
            try Gate(plan: try Self.plan(), original: table([]), created: ["stub": "STUB"]).admit(v, now: table(vols))
            switch v {   // what diskutil does
            case .changeVolumeRole(_, let u, _): vols[vols.firstIndex { $0.uuid == u }!].roles = ["Data"]
            case .renameVolume(_, let u, let n): vols[vols.firstIndex { $0.uuid == u }!].name = n
            case .addVolume(_, let n, let r, _):
                let full = ["S": "System", "B": "Preboot", "R": "Recovery", "D": "Data"][r]!
                vols.append(vol("disk7s\(vols.count + 1)", "V\(vols.count + 1)", n, [full]))
            default: Issue.record("unexpected \(v)")
            }
            #expect(seen.count < 7)
        }
        #expect(seen == ["volume V1 becomes role D", "rename volume V1 to SiliconForest - Data", "add volume SiliconForest (S) grouped",
                         "add volume Preboot (B)", "add volume Recovery (R)"])
        expectAsahiStubVolumes(vols)
        // the group is with the Data volume
        if case .addVolume(_, _, _, let g)? = try E.nextStubVolumeVerb(stub: "STUB", name: "SiliconForest", in: table([vol("a", "D1", "SiliconForest - Data", ["Data"])])) {
            #expect(g == "D1")
        } else { Issue.record("no System verb") }
        // a container with no default volume gets a Data volume added (upstream's other branch)
        #expect(try E.nextStubVolumeVerb(stub: "STUB", name: "X", in: table([])) == .addVolume(store: "STUB", name: "X", role: "D"))
        // two Data volumes: never guessed at
        #expect(throws: EngineError.self) {
            _ = try E.nextStubVolumeVerb(stub: "STUB", name: "X", in: table([vol("a", "1", "a", ["Data"]), vol("b", "2", "b", ["Data"])]))
        }
    }

    @Test func theGateKeepsVolumeVerbsOnThisJobsStub() throws {
        let g = Gate(plan: try Self.plan(), original: table([]), created: ["stub": "STUB"])
        let t = table([vol("disk7s1", "V1", "SiliconForest", []), vol("disk7s2", "V2", "Other", ["System"])])
        try g.admit(.changeVolumeRole(store: "STUB", volume: "V1", role: "D"), now: t)
        try g.admit(.renameVolume(store: "STUB", volume: "V2", name: "x"), now: t)
        let refused: [DiskVerb] = [
            .changeVolumeRole(store: "MAC", volume: "MD", role: "D"),           // macOS's container
            .changeVolumeRole(store: "STUB", volume: "V1", role: "S"),          // only ever to Data
            .changeVolumeRole(store: "STUB", volume: "V2", role: "D"),          // a volume that already has a role
            .changeVolumeRole(store: "STUB", volume: "MD", role: "D"),          // not the stub's volume
            .renameVolume(store: "MAC", volume: "MD", name: "x"), .renameVolume(store: "STUB", volume: "MV", name: "x"),
            .addVolume(store: "MAC", name: "x", role: "B"),
            .addVolume(store: "STUB", name: "x", role: "S", groupWith: "MD"),   // grouped with macOS's Data
            .addVolume(store: "STUB", name: "x", role: "S", groupWith: "V2"),   // not a Data volume
        ]
        for v in refused { #expect(throws: SafetyRefusal.self, "\(v.summary)") { try g.admit(v, now: t) } }
    }

    static func table80() -> ImageTopology { table([]) }

    static func plan() throws -> EnginePlan {
        EnginePlan(operation: .install, profile: ProfileRef(id: "J313", sha256: "x"), release: "r", releaseVersion: "v",
                   request: InstallRequest(siliconForestBytes: 20 << 30, installID: "a1b2c3d4"), layoutDigest: "L",
                   macOS: .init(store: "MAC", from: 100 << 30, to: 80 << 30),
                   partitions: [.init(role: "stub", after: "@macos", bytes: 2 << 30, content: "Apple_APFS", label: "SiliconForest")],
                   owned: nil, installJob: nil, originalLayoutDigest: "L", humanSteps: []).sealed()
    }
}

@Suite("Engine: the stub's volumes on a disk image", .serialized, .enabled(if: ImageLab.enabled), .enabled(if: ImageLab.long))
struct StubVolumeImageTests {
    /// S32 runs upstream's commands (sf-payload-commands.txt lines 1-5, `diskutil mount nobrowse` aside) and a kill
    /// or power cut after any one of them resumes to the same four volumes.
    @Test(.timeLimit(.minutes(30))) func killOrPowerLossAfterEachVolumeCommandResumes() throws {
        let c = try ImageLab.fresh(.j293); defer { c.finish() }
        let profile = try ImageLab.profile()
        let plan = try ImageLab.plan(c, profile: profile)
        let j = try ChainJournal(directory: c.journalDir)
        try ImageLab.engine(c, journal: j, profile: profile).begin(plan)
        let points = ["data-role", "data-name", "system", "preboot", "recovery"]
        for (i, p) in points.enumerated() {
            let power = i % 2 == 1
            let f = power ? FaultPlan(powerLossAtPoint: "S32/\(p)") : FaultPlan(killAtPoint: "S32/\(p)")
            let e = try ImageLab.engine(c, journal: try ChainJournal(directory: c.journalDir, jobID: j.jobID), profile: profile, faults: f)
            #expect(throws: SimulatedKill.self) { try e.run() }
            if power { #expect(!c.backend.isAttached()); try c.backend.attach() }
        }
        let e = try ImageLab.engine(c, journal: try ChainJournal(directory: c.journalDir, jobID: j.jobID), profile: profile)
        #expect(try e.run() == .handedOff)
        let jj = try ChainJournal(directory: c.journalDir, jobID: j.jobID)
        try ImageEngineTests.expectInstalled(c, journal: jj, plan: plan)
        let stubUUID = try #require(JobState(jj.records).created["stub"])
        let stub = try #require(try c.backend.topology().partition(uuid: stubUUID))
        let vols = stub.apfs?.volumes ?? []
        expectAsahiStubVolumes(vols)
        // Each volume command ran exactly once, across five interrupted runs and the last one.
        let data = String(try #require(vols.first { $0.roles == ["Data"] }).uuid.prefix(8))
        let s32: [String] = jj.records.filter { $0.step == "S32" && $0.kind == .note }.compactMap { $0.result?["verb"]?.string }
        let want: [String] = ["volume \(data) becomes role D", "rename volume \(data) to SiliconForest - Data",
                              "add volume SiliconForest (S) grouped", "add volume Preboot (B)", "add volume Recovery (R)"]
        #expect(s32 == want)
    }
}

/// The synthetic restore image (StubTests' fixture, made-up bytes) and stand-ins for the local inputs.
func fixtureStubSource(_ dir: URL) throws -> StubSource {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let (zip, profile) = fixtureIPSW()
    let ipsw = dir.appendingPathComponent("fixture.ipsw"); try zip.write(to: ipsw)
    let admin = dir.appendingPathComponent("AdminUserRecoveryInfo.plist"); try plistXML(["users": ["fixture"]]).write(to: admin)
    let icon = dir.appendingPathComponent("sf.icns"); try bytes("icon", 700).write(to: icon)
    return StubSource(profile: profile, restoreImage: ipsw.path, adminUsers: admin, volumeIcon: icon, rootOnly: geteuid() == 0)
}

@Suite("Engine: the stub built with SFStub on a disk image", .serialized, .enabled(if: ImageLab.enabled), .enabled(if: ImageLab.long))
struct StubBuildEngineImageTests {
    static func engine(_ c: ImageLab.Case, _ j: ChainJournal, _ src: StubSource, faults: FaultPlan = FaultPlan()) throws -> InstallEngine {
        let e = try ImageLab.engine(c, journal: j, profile: try ImageLab.profile(), faults: faults)
        e.stubSource = src
        return e
    }

    static func expectSFStub(_ c: ImageLab.Case, _ j: ChainJournal, _ src: StubSource) throws {
        let st = JobState(j.records)
        let stub = try #require(st.created["stub"]), boot = try #require(st.created["boot"])
        let (release, _) = try ImageLab.release()
        let e = try engine(c, j, src)
        let sys = try c.backend.volumeURL(store: stub, role: "System")
        // The boot object, in the app, in m1n1.build's format, chainloading this job's SFBOOT.
        let s1 = try Data(contentsOf: c.workDir.appendingPathComponent(release.stage1))
        let bootBin = try Data(contentsOf: sys.appendingPathComponent("SiliconForest Setup.app/Contents/Resources/boot.bin"))
        #expect(bootBin == InstallEngine.bootObject(stage1: s1, bootPartUUID: boot))
        // SFInstall/plan.json names the same SFBOOT
        let pj = try JSONSerialization.jsonObject(with: Data(contentsOf: sys.appendingPathComponent("SFInstall/plan.json"))) as? [String: Any]
        #expect(pj?["boot"] as? String == boot)
        #expect(FileManager.default.fileExists(atPath: sys.appendingPathComponent("SFInstall/state").path))
        // The Apple parts: BaseSystem decmpfs-compressed on Recovery under the group's UUID, the Preboot restore bundle
        let target = try e.stubTarget(stub: stub)
        let bs = target.roots[.recovery]!.appendingPathComponent("\(target.vgid)/usr/standalone/firmware/arm64eBaseSystem.dmg")
        #expect(try Data(contentsOf: bs) == bytes("basesystem", 300_000))
        var sst = stat(); stat(bs.path, &sst)
        #expect(sst.st_flags & UInt32(UF_COMPRESSED) != 0)
        #expect(FileManager.default.fileExists(atPath: target.roots[.preboot]!.appendingPathComponent("\(target.vgid)/Restore/BuildManifest.plist").path))
        #expect(FileManager.default.fileExists(atPath: target.roots[.data]!.appendingPathComponent("private/var/db/dslocal").path))
        // Without root the schg and bootable flags are journaled as simulated, never silently skipped.
        if !src.rootOnly {
            let sim = j.records.filter { $0.kind == .note && $0.note == "simulated: needs root" }
            let tools: [String] = sim.compactMap { r in
                if case .a(let v)? = r.args?["command"] { return v.first?.string }
                return nil
            }
            #expect(tools.contains("fsctl") && tools.contains("chflags"))
        }
        // S55's and S60's own checks pass on the finished stub.
        var gate = Gate(plan: st.plan!, original: st.original!, created: st.created); gate.created = st.created
        #expect(e.checkStubTail(src, stub: stub, actions: [try e.stubBootAction(plan: st.plan!, gate: gate)]) != .notDone)
        #expect(e.checkStubTail(src, stub: stub, actions: try e.stubInstallActions(plan: st.plan!, gate: gate)) != .notDone)
    }

    @Test(.timeLimit(.minutes(30))) func theEngineBuildsTheStubWithSFStubAndResumesFromAnyAction() throws {
        let c = try ImageLab.fresh(.j293); defer { c.finish() }
        let src = try fixtureStubSource(c.dir.appendingPathComponent("stub-src"))
        let plan = try ImageLab.plan(c, profile: try ImageLab.profile())
        let j = try ChainJournal(directory: c.journalDir)
        try Self.engine(c, j, src).begin(plan)
        // Kill or cut the power inside S35: after the first action, in the middle (the Preboot restore bundle) and
        // after the BaseSystem compression; then after S55's and S60's commands.
        let points: [(FaultPlan, Bool)] = [
            (FaultPlan(killAtPoint: "S35/action-1"), false), (FaultPlan(powerLossAtPoint: "S35/action-20"), true),
            (FaultPlan(killAtPoint: "S35/action-40"), false), (FaultPlan(powerLossAfterCommand: .S35), true),
            (FaultPlan(killAfterCommand: .S55), false), (FaultPlan(powerLossAfterCommand: .S60), true),
        ]
        for (f, power) in points {
            let e = try Self.engine(c, try ChainJournal(directory: c.journalDir, jobID: j.jobID), src, faults: f)
            #expect(throws: SimulatedKill.self) { try e.run() }
            if power { #expect(!c.backend.isAttached()); try c.backend.attach() }
        }
        let e = try Self.engine(c, try ChainJournal(directory: c.journalDir, jobID: j.jobID), src)
        #expect(try e.run() == .handedOff)
        let jj = try ChainJournal(directory: c.journalDir, jobID: j.jobID)
        try ImageEngineTests.expectInstalled(c, journal: jj, plan: plan)
        try Self.expectSFStub(c, jj, src)
        // S35 was resumed by its check, not trusted from the journal
        #expect(jj.records.contains { $0.step == "S35" && $0.kind == .check })
    }
}

@Suite("Engine: the stub-only plan (STUB-ONLY-RUN-J313)")
struct StubOnlyPlanTests {
    static func plan(_ id: String = "a1b2c3d4") -> EnginePlan {
        var p = try! StubVolumePlanTests.plan()
        p.request = InstallRequest(siliconForestBytes: 2 << 30, installID: id, stubOnly: true)
        return p.sealed()
    }

    @Test func stepsAndTheAbsentStage2Partition() throws {
        let p = Self.plan()
        let full = try StubVolumePlanTests.plan()
        #expect(p.isStubOnly && !full.isStubOnly)
        #expect(StepCode.order(p) == [.S00, .S05, .S08, .S10, .S15, .S20, .S25, .S30, .S32, .S35, .S55, .S60, .S65, .S68, .S70])
        #expect(!StepCode.order(p).contains { [.S17, .S40, .S42, .S45, .S46, .S47, .S50, .S52].contains($0) })
        // The PARTUUID stage 1 names: a v4-shaped UUID, the same for the same install, different for another
        let u = p.absentBootPartUUID
        #expect(u.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#, options: .regularExpression) != nil, "\(u)")
        #expect(u == Self.plan().absentBootPartUUID && u != Self.plan("other").absentBootPartUUID)
        // and the profile's variables accept it (SFPayload checks they chainload sf/boot.bin on that partition)
        let profile = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("profiles/J313.json")
        #expect(try SFPayload.variables(profile: profile, bootPartUUID: u) == InstallEngine.bootVariables(bootPartUUID: u))
    }

    @Test func theGateLetsAStubOnlyJobCreateOnlyTheStub() throws {
        let p = Self.plan()
        let g = Gate(plan: p, original: StubVolumePlanTests.table80(), created: ["stub": "STUB"])
        #expect(throws: SafetyRefusal.self) { try g.admit(.addPartition(role: "boot", after: "STUB", content: "EFI", label: "SFBOOT", bytes: 500 << 20), now: StubVolumePlanTests.table80()) }
        #expect(throws: SafetyRefusal.self) { try g.admit(.addPartition(role: "root", after: "STUB", content: "Linux Filesystem", label: "SF root", bytes: 10 << 30), now: StubVolumePlanTests.table80()) }
    }
}

@Suite("Engine: a stub-only run on an Air with Omarchy removed (ISC, macOS, Recovery)", .serialized, .enabled(if: ImageLab.enabled), .enabled(if: ImageLab.long))
struct StubOnlyImageTests {
    @Test(.timeLimit(.minutes(30))) func aStubOnlyRunMakesOnlyTheStubResumesAndIsRemovedCleanly() throws {
        // The run's precondition is Omarchy removed and macOS full size: the j293 layout's shape, with J313's profile.
        let c = try ImageLab.fresh(.j293); defer { c.finish() }
        let profile = try ImageLab.profile("J313")
        let src = try fixtureStubSource(c.dir.appendingPathComponent("stub-src"))
        let original = try c.backend.topology()
        let (release, _) = try ImageLab.release()
        let mac = try #require(original.macOS)
        let request = InstallRequest(siliconForestBytes: profile.partitioning.stubContainerBytes, installName: "SiliconForest", installID: "a1b2c3d4", stubOnly: true)
        let plan = try EnginePlanner.installPlan(topology: original, limits: try c.backend.limits(store: mac.uuid), profile: profile, release: release, request: request)
        #expect(plan.partitions.map(\.role) == ["stub"] && plan.macOS.to == plan.macOS.from - profile.partitioning.stubContainerBytes)
        // the wrong size is refused
        var wrong = request; wrong.siliconForestBytes += 1 << 20
        #expect(throws: PlanRefusal.self) { _ = try EnginePlanner.installPlan(topology: original, limits: try c.backend.limits(store: mac.uuid), profile: profile, release: release, request: wrong) }
        let j = try ChainJournal(directory: c.journalDir)
        func engine(_ f: FaultPlan = FaultPlan()) throws -> InstallEngine {
            let e = try ImageLab.engine(c, journal: try ChainJournal(directory: c.journalDir, jobID: j.jobID), profile: profile, faults: f)
            e.stubSource = src
            return e
        }
        let first = try ImageLab.engine(c, journal: j, profile: profile)
        try first.begin(plan)
        #expect(throws: EngineError.self) { try first.run() }              // no stubSource: refused, nothing written
        #expect(try c.backend.freshTopology().digestForm == original.digestForm)
        for (f, power) in [(FaultPlan(powerLossAfterCommand: .S30), true), (FaultPlan(killAtPoint: "S32/system"), false),
                           (FaultPlan(killAtPoint: "S35/action-30"), false), (FaultPlan(powerLossAfterCommand: .S55), true)] {
            #expect(throws: SimulatedKill.self) { try engine(f).run() }
            if power { #expect(!c.backend.isAttached()); try c.backend.attach() }
        }
        #expect(try engine().run() == .handedOff)
        let jj = try ChainJournal(directory: c.journalDir, jobID: j.jobID)
        let st = JobState(jj.records)
        #expect(st.created.keys.sorted() == ["stub"])
        #expect(!jj.records.contains { ["S17", "S40", "S42", "S45", "S46", "S47", "S50", "S52"].contains($0.step ?? "") })
        // Only the stub was added, directly after macOS; Linux's partitions untouched.
        let t = try c.backend.topology()
        let stubUUID = try #require(st.created["stub"])
        let stub = try #require(t.partition(uuid: stubUUID))
        #expect(t.partitions.count == original.partitions.count + 1 && stub.offset == t.partition(uuid: mac.uuid)!.end)
        for p in original.partitions where p.uuid != mac.uuid {
            #expect(t.partition(uuid: p.uuid).map { [$0.offset, $0.size] } == [p.offset, p.size], "\(p.identifier) moved")
        }
        expectAsahiStubVolumes(stub.apfs?.volumes ?? [])
        // Stage 1 chainloads a partition that is on no disk: it will start, name it, and find no stage 2.
        let sys = try c.backend.volumeURL(store: stub.uuid, role: "System")
        let s1 = try Data(contentsOf: c.workDir.appendingPathComponent(release.stage1))
        let absent = plan.absentBootPartUUID
        #expect(try Data(contentsOf: sys.appendingPathComponent("SiliconForest Setup.app/Contents/Resources/boot.bin")) == InstallEngine.bootObject(stage1: s1, bootPartUUID: absent))
        #expect(!t.partitions.contains { $0.uuid.lowercased() == absent })
        let pj = try JSONSerialization.jsonObject(with: Data(contentsOf: sys.appendingPathComponent("SFInstall/plan.json"))) as? [String: Any]
        #expect(pj?["boot"] as? String == absent && pj?["root"] as? String == "none")
        // Removal deletes the stub container and grows macOS back: the original table.
        let proof = try InstallProofReader.proof(from: jj)
        #expect(proof.owned.all == [stub.uuid])
        let removal = try EnginePlanner.removalPlan(topology: t, profile: profile, proof: proof)
        let rj = try ChainJournal(directory: c.journalDir)
        let re = try ImageLab.engine(c, journal: rj, profile: profile)
        re.proof = proof
        try re.begin(removal)
        #expect(try re.run() == .committed)
        #expect(try c.backend.freshTopology().digestForm == original.digestForm)
    }

    @Test(.timeLimit(.minutes(20))) func aStubOnlyRunRollsBackFromTheMiddle() throws {
        let c = try ImageLab.fresh(.j293); defer { c.finish() }
        let profile = try ImageLab.profile("J313")
        let src = try fixtureStubSource(c.dir.appendingPathComponent("stub-src"))
        let original = try c.backend.topology()
        let (release, _) = try ImageLab.release()
        let mac = try #require(original.macOS)
        let request = InstallRequest(siliconForestBytes: profile.partitioning.stubContainerBytes, installID: "a1b2c3d4", stubOnly: true)
        let plan = try EnginePlanner.installPlan(topology: original, limits: try c.backend.limits(store: mac.uuid), profile: profile, release: release, request: request)
        let j = try ChainJournal(directory: c.journalDir)
        let e = try ImageLab.engine(c, journal: j, profile: profile, faults: FaultPlan(killAtPoint: "S35/action-20"))
        e.stubSource = src
        try e.begin(plan)
        #expect(throws: SimulatedKill.self) { try e.run() }
        let r = try ImageLab.engine(c, journal: try ChainJournal(directory: c.journalDir, jobID: j.jobID), profile: profile)
        r.stubSource = src
        #expect(try r.rollback() == .rolledBack)
        #expect(try c.backend.freshTopology().digestForm == original.digestForm)
    }
}
