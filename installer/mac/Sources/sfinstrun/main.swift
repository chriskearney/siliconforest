// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// sfinstrun: the supervised full install (docs/installer/FIRST-INSTALL-J313.md, G6). A lab tool, not in
// the app bundle. It verifies the signed payload release, builds the full install plan (stub, SFBOOT and
// root), and runs it through the engine with SFStub and the live backend (journal, resume, rollback,
// removal). Targets:
//   --target image:PATH   an attached disk image under the images directory (image-only tests)
//   --target disk:UUID    the internal disk by GPT UUID. `plan` only reads it. `run` and the rest need a
//                         build with SF_REAL_DISK_WRITES, root, and Chris's runtime authorization file for
//                         exactly this plan and disk (RealDiskGate); without them they refuse before any
//                         change.
// It never runs bless, bputil, kmutil, nvram, DFU or a firmware tool (S65's bless is simulated).
//
//   sfinstrun plan     --target T --release-dir D [--size 80G] [--name N] [--install-id ID] --out PLAN.json
//   sfinstrun run      --target T --release-dir D --plan PLAN.json --journal DIR --work DIR
//                      --icon F --admin-users F [--ipsw URL|PATH] [--recovery-binary F] [--job UUID]
//   sfinstrun rollback (the run options) --job UUID
//   sfinstrun remove   --target T --journal DIR --work DIR --job UUID
//   sfinstrun status   --journal DIR --job UUID
//   sudo sfinstrun startup-disk   this Mac's startup disk and its GPT disk GUID (read-only: diskutil info
//                      and the GPT header; diskutil doesn't report a whole disk's GUID)
//
// D is a verified signed release (install.json, SHA256SUMS, SHA256SUMS.sig, ...). The signature is
// checked before the plan is made, and again by S15 and the live backend before any write.

import Foundation
import SFEngine
import SFInstallKit
import SFLiveDisk
import SFStub

setvbuf(stdout, nil, _IOLBF, 0)

struct Args {
    var cmd = ""
    var kv: [String: String] = [:]
    init(_ argv: [String]) throws {
        guard argv.count >= 2 else { throw RunError("usage: sfinstrun <plan|run|rollback|remove|status> ... (see the header of main.swift)") }
        cmd = argv[1]
        var i = 2
        while i < argv.count {
            guard argv[i].hasPrefix("--"), i + 1 < argv.count else { throw RunError("bad argument \(argv[i])") }
            kv[String(argv[i].dropFirst(2))] = argv[i + 1]; i += 2
        }
    }
    func req(_ k: String) throws -> String { guard let v = kv[k] else { throw RunError("missing --\(k)") }; return v }
    func url(_ k: String) throws -> URL { URL(fileURLWithPath: try req(k)) }
}

struct RunError: Error, LocalizedError { var errorDescription: String?; init(_ m: String) { errorDescription = m } }

func target(_ a: Args) throws -> StubOnlyRun.Target {
    let t = try a.req("target")
    if t.hasPrefix("image:") { return .image(URL(fileURLWithPath: String(t.dropFirst(6)))) }
    if t.hasPrefix("disk:") { return .internalDisk(String(t.dropFirst(5))) }
    throw RunError("--target is image:PATH or disk:UUID")
}

func profile() throws -> (DeviceProfile, URL) {
    guard let p = ProfileStore.profile(id: "J313") else { throw RunError("profile J313 not found") }
    return (p, SourceTree.installerRoot.appendingPathComponent("profiles/J313.json"))
}

func release(_ a: Args) throws -> (ReleaseManifest, URL) {
    let dir = try a.url("release-dir")
    let m = try SFRelease.verify(directory: dir, allowRehearsal: false)
    return (m, dir)
}

func sizeBytes(_ a: Args, profile: DeviceProfile, release: ReleaseManifest) throws -> Int64 {
    if let s = a.kv["size"] {
        guard let n = Bytes.parse(s) else { throw RunError("bad --size \(s)") }
        return n
    }
    return max(profile.recommendedFootprint, release.rootMinBytes + profile.partitioning.stubContainerBytes + profile.partitioning.bootPartition.bytes)
}

func engine(_ a: Args, journal: ChainJournal, plan: EnginePlan, release: (ReleaseManifest, URL)) throws -> InstallEngine {
    let (p, purl) = try profile()
    let backend = LiveDiskBackend(authority: try StubOnlyRun.authority(try target(a), planDigest: plan.digest))
    backend.expectRelease(release.0, in: release.1)
    let e = InstallEngine(backend: backend, journal: journal, profile: p, release: release.0, releaseSource: release.1,
                          workDir: try a.url("work").appendingPathComponent(journal.jobID.uuidString))
    e.stubSource = StubSource(profile: try StubProfile.load(profile: purl), restoreImage: a.kv["ipsw"], adminUsers: try a.url("admin-users"),
                              volumeIcon: try a.url("icon"), rootOnly: geteuid() == 0)
    e.recoveryBinary = a.kv["recovery-binary"].map { URL(fileURLWithPath: $0) }
    e.onEvent = { ev in
        switch ev {
        case .step(let c, let t): print("  \(c.rawValue)  \(t)")
        case .progress(let c, let t): print("     \(c.rawValue) \(t)")
        case .simulated(let n): print("     simulated (\(n.reason)): \(n.command.joined(separator: " "))")
        case .rollback(let c): print("  ↺ \(c.rawValue)")
        default: break
        }
    }
    return e
}

func loadPlan(_ a: Args) throws -> EnginePlan {
    let plan = try JSONDecoder().decode(EnginePlan.self, from: Data(contentsOf: try a.url("plan")))
    guard plan.isSealed else { throw RunError("the plan's digest doesn't match its contents") }
    guard !plan.isStubOnly else { throw RunError("this is a stub-only plan; use sfstubrun") }
    return plan
}

func status(_ j: ChainJournal) {
    let st = JobState(j.records)
    print("job \(j.jobID.uuidString): \(st.end?.rawValue ?? "unfinished"), \(j.records.count) records, created: \(st.created.keys.sorted().joined(separator: ", "))")
    for n in st.approvals { print("  needs Chris's approval: \(n.step) \(n.command.joined(separator: " ")) (\(n.reason))") }
}

func summary(_ plan: EnginePlan, release: ReleaseManifest) -> [String] {
    ["plan \(plan.digest)",
     "FULL INSTALL of \(release.version) (not stub-only)",
     "macOS container \(plan.macOS.store): \(plan.macOS.from) B → \(plan.macOS.to) B",
     "new: " + plan.partitions.map { "\($0.role) \($0.bytes) B \($0.content) “\($0.label)”" }.joined(separator: ", "),
     "stage 1: \(release.stage1) sha256 \(release.artifact(release.stage1)?.sha256 ?? "")",
     "stage 2: \(release.stage2)",
     "root: \(release.rootImageBytes) B (sha256 \(release.rootImageSHA256.prefix(16))…), parts \(release.effectiveRootParts.joined(separator: ", "))",
     "steps: " + StepCode.order(plan).map(\.rawValue).joined(separator: " ")]
}

func main() throws {
    let a = try Args(CommandLine.arguments)
    switch a.cmd {
    case "startup-disk":
        let d = try StartupDisk.find()
        print("startup disk \(d.whole), GPT disk GUID \(d.uuid)  (use --target disk:\(d.uuid))")
    case "plan":
        let (p, _) = try profile()
        let rel = try release(a)
        let t = try target(a)
        let (topo, limits) = try StubOnlyRun.read(t)
        let id = a.kv["install-id"] ?? String(UUID().uuidString.prefix(8)).lowercased()
        let req = InstallRequest(siliconForestBytes: try sizeBytes(a, profile: p, release: rel.0),
                                 installName: a.kv["name"] ?? "SiliconForest", installID: id)
        let plan = try EnginePlanner.installPlan(topology: topo, limits: limits, profile: p, release: rel.0, request: req)
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(plan).write(to: try a.url("out"))
        summary(plan, release: rel.0).forEach { print($0) }
        if case .internalDisk(let uuid) = t {
            print("\nThe runtime authorization for this plan and disk (Chris checks it and writes it, root-owned, mode 0600, to")
            print("\(RealDiskGate.authorizationPath); this tool never does):")
            print(try StubOnlyRun.authorizationTemplate(plan: plan, diskUUID: uuid))
        }
    case "run":
        let plan = try loadPlan(a), rel = try release(a)
        let dir = try a.url("journal")
        let j = try a.kv["job"].map { id -> ChainJournal in
            guard let u = UUID(uuidString: id) else { throw RunError("bad --job") }
            return try ChainJournal(directory: dir, jobID: u)
        } ?? ChainJournal(directory: dir)
        let e = try engine(a, journal: j, plan: plan, release: rel)
        if j.records.isEmpty { try e.begin(plan); print("began job \(j.jobID.uuidString)") } else { print("resuming job \(j.jobID.uuidString)") }
        print("end: \(try e.run().rawValue)")
        status(try ChainJournal(directory: dir, jobID: j.jobID))
    case "rollback":
        let plan = try loadPlan(a), rel = try release(a)
        guard let u = UUID(uuidString: try a.req("job")) else { throw RunError("bad --job") }
        let j = try ChainJournal(directory: try a.url("journal"), jobID: u)
        print("end: \(try engine(a, journal: j, plan: plan, release: rel).rollback().rawValue)")
    case "remove":
        guard let u = UUID(uuidString: try a.req("job")) else { throw RunError("bad --job") }
        let dir = try a.url("journal")
        let proof = try InstallProofReader.proof(from: try ChainJournal(directory: dir, jobID: u))
        let (p, _) = try profile()
        let t = try target(a)
        let (topo, _) = try StubOnlyRun.read(t)
        let removal = try EnginePlanner.removalPlan(topology: topo, profile: p, proof: proof)
        print("removal plan \(removal.digest): delete \(proof.owned.all.joined(separator: ", ")), grow \(removal.macOS.store) to \(removal.macOS.to) B")
        if case .internalDisk(let uuid) = t {
            print(try StubOnlyRun.authorizationTemplate(plan: removal, diskUUID: uuid))
        }
        let backend = LiveDiskBackend(authority: try StubOnlyRun.authority(t, planDigest: removal.digest))
        let rjNew = try ChainJournal(directory: dir)
        let e = InstallEngine(backend: backend, journal: rjNew, profile: p, release: nil, releaseSource: nil,
                              workDir: try a.url("work").appendingPathComponent(rjNew.jobID.uuidString))
        e.proof = proof
        try e.begin(removal)
        print("removal job \(e.journal.jobID.uuidString) end: \(try e.run().rawValue)")
    case "status":
        guard let u = UUID(uuidString: try a.req("job")) else { throw RunError("bad --job") }
        status(try ChainJournal(directory: try a.url("journal"), jobID: u))
    default:
        throw RunError("unknown command \(a.cmd)")
    }
}

do { try main() } catch {
    FileHandle.standardError.write(Data("sfinstrun: \((error as? LocalizedError)?.errorDescription ?? "\(error)")\n".utf8))
    exit(1)
}
