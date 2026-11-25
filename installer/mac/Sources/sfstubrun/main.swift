// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// sfstubrun: the supervised stub-only run (docs/installer/STUB-ONLY-RUN-J313.md, stage A). A lab tool, never in
// the app bundle. It builds the stub-only plan, then runs it through the engine with SFStub and the live backend
// (journal, resume, rollback, removal). Targets:
//   --target image:PATH   an attached disk image under the images directory (the M5 dress rehearsal)
//   --target disk:UUID    the internal disk by GPT UUID. `plan` only reads it. `run` and the rest need a build with
//                         the compile key SF_REAL_DISK_WRITES, root, and Chris's runtime authorization file for
//                         exactly this plan and disk (RealDiskGate); without them they refuse before any change.
// It never runs bless, bputil, kmutil, nvram, DFU or a firmware tool (S65's bless is simulated by the engine).
//
//   sfstubrun plan     --target T --release-dir D --stage1-sha256 H [--version V] [--name N] [--install-id ID] --out PLAN.json
//   sfstubrun run      --target T --release-dir D --stage1-sha256 H [--version V] --plan PLAN.json --journal DIR --work DIR
//                      --icon F --admin-users F [--ipsw URL|PATH] [--recovery-binary F] [--job UUID (resume)]
//   sfstubrun rollback (the run options) --job UUID
//   sfstubrun remove   --target T --journal DIR --work DIR --job UUID   (the stub-only job's removal: delete the stub, grow macOS)
//   sfstubrun status   --journal DIR --job UUID
//
// D holds sf-stage1.bin (installer/payload/boot/build_stage1.sh, or a verified release); H is its SHA-256 from the
// signed install.json.

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
        guard argv.count >= 2 else { throw StubError("usage: sfstubrun <plan|run|rollback|remove|status> ... (see the header of main.swift)") }
        cmd = argv[1]
        var i = 2
        while i < argv.count {
            guard argv[i].hasPrefix("--"), i + 1 < argv.count else { throw StubError("bad argument \(argv[i])") }
            kv[String(argv[i].dropFirst(2))] = argv[i + 1]; i += 2
        }
    }
    func req(_ k: String) throws -> String { guard let v = kv[k] else { throw StubError("missing --\(k)") }; return v }
    func url(_ k: String) throws -> URL { URL(fileURLWithPath: try req(k)) }
}

func target(_ a: Args) throws -> StubOnlyRun.Target {
    let t = try a.req("target")
    if t.hasPrefix("image:") { return .image(URL(fileURLWithPath: String(t.dropFirst(6)))) }
    if t.hasPrefix("disk:") { return .internalDisk(String(t.dropFirst(5))) }
    throw StubError("--target is image:PATH or disk:UUID")
}

func profile() throws -> (DeviceProfile, URL) {
    guard let p = ProfileStore.profile(id: "J313") else { throw StubError("profile J313 not found") }
    return (p, SourceTree.installerRoot.appendingPathComponent("profiles/J313.json"))
}

/// The release: sf-stage1.bin by the signed install.json's hash. Checked here and again by S15 and the backend.
func release(_ a: Args) throws -> (ReleaseManifest, URL) {
    let dir = try a.url("release-dir")
    let f = dir.appendingPathComponent("sf-stage1.bin")
    let sha = try a.req("stage1-sha256").lowercased()
    let size = (try FileManager.default.attributesOfItem(atPath: f.path)[.size] as? NSNumber)?.int64Value ?? 0
    guard try SHA256Hasher.file(f) == sha else { throw StubError("\(f.path) doesn't match --stage1-sha256") }
    return (ReleaseManifest.stubOnly(bytes: size, sha256: sha, version: a.kv["version"] ?? "stub-only"), dir)
}

func engine(_ a: Args, journal: ChainJournal, plan: EnginePlan, release: (ReleaseManifest, URL)) throws -> InstallEngine {
    let (p, purl) = try profile()
    let backend = LiveDiskBackend(authority: try StubOnlyRun.authority(try target(a), planDigest: plan.digest))
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
    guard plan.isSealed else { throw StubError("the plan's digest doesn't match its contents") }
    guard plan.isStubOnly else { throw StubError("not a stub-only plan") }
    return plan
}

func status(_ j: ChainJournal) {
    let st = JobState(j.records)
    print("job \(j.jobID.uuidString): \(st.end?.rawValue ?? "unfinished"), \(j.records.count) records, created: \(st.created.keys.sorted().joined(separator: ", "))")
    for n in st.approvals { print("  needs Chris's approval: \(n.step) \(n.command.joined(separator: " ")) (\(n.reason))") }
}

func main() throws {
    let a = try Args(CommandLine.arguments)
    switch a.cmd {
    case "plan":
        let (p, _) = try profile()
        let rel = try release(a)
        let t = try target(a)
        let (topo, limits) = try StubOnlyRun.read(t)
        let id = a.kv["install-id"] ?? String(UUID().uuidString.prefix(8)).lowercased()
        let plan = try StubOnlyRun.plan(topology: topo, limits: limits, profile: p, release: rel.0, name: a.kv["name"] ?? "SiliconForest", installID: id)
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(plan).write(to: try a.url("out"))
        StubOnlyRun.summary(plan, release: rel.0).forEach { print($0) }
        if case .internalDisk(let uuid) = t {
            print("\nThe runtime authorization for this plan and disk (Chris checks it and writes it, root-owned, mode 0600, to")
            print("\(RealDiskGate.authorizationPath); this tool never does):")
            print(try StubOnlyRun.authorizationTemplate(plan: plan, diskUUID: uuid))
        }
    case "run":
        let plan = try loadPlan(a), rel = try release(a)
        let dir = try a.url("journal")
        let j = try a.kv["job"].map { id -> ChainJournal in
            guard let u = UUID(uuidString: id) else { throw StubError("bad --job") }
            return try ChainJournal(directory: dir, jobID: u)
        } ?? ChainJournal(directory: dir)
        let e = try engine(a, journal: j, plan: plan, release: rel)
        if j.records.isEmpty { try e.begin(plan); print("began job \(j.jobID.uuidString)") } else { print("resuming job \(j.jobID.uuidString)") }
        print("end: \(try e.run().rawValue)")
        status(try ChainJournal(directory: dir, jobID: j.jobID))
    case "rollback":
        let plan = try loadPlan(a), rel = try release(a)
        guard let u = UUID(uuidString: try a.req("job")) else { throw StubError("bad --job") }
        let j = try ChainJournal(directory: try a.url("journal"), jobID: u)
        print("end: \(try engine(a, journal: j, plan: plan, release: rel).rollback().rawValue)")
    case "remove":
        guard let u = UUID(uuidString: try a.req("job")) else { throw StubError("bad --job") }
        let dir = try a.url("journal")
        let proof = try InstallProofReader.proof(from: try ChainJournal(directory: dir, jobID: u))
        let (p, _) = try profile()
        let t = try target(a)
        let (topo, _) = try StubOnlyRun.read(t)
        let removal = try EnginePlanner.removalPlan(topology: topo, profile: p, proof: proof)
        print("removal plan \(removal.digest): delete \(proof.owned.all.joined(separator: ", ")), grow \(removal.macOS.store) to \(removal.macOS.to) B")
        if case .internalDisk(let uuid) = t {
            // The removal is its own plan: the runtime authorization must name its digest (deterministic: rerun after placing it).
            print(try StubOnlyRun.authorizationTemplate(plan: removal, diskUUID: uuid))
        }
        let backend = LiveDiskBackend(authority: try StubOnlyRun.authority(t, planDigest: removal.digest))
        let rjNew = try ChainJournal(directory: dir)
        let e = InstallEngine(backend: backend, journal: rjNew, profile: p, release: nil, releaseSource: nil,
                              workDir: try a.url("work").appendingPathComponent(rjNew.jobID.uuidString))
        e.proof = proof
        let rj = e.journal
        try e.begin(removal)
        print("removal job \(rj.jobID.uuidString) end: \(try e.run().rawValue)")
    case "status":
        guard let u = UUID(uuidString: try a.req("job")) else { throw StubError("bad --job") }
        status(try ChainJournal(directory: try a.url("journal"), jobID: u))
    default:
        throw StubError("unknown command \(a.cmd)")
    }
}

do { try main() } catch {
    FileHandle.standardError.write(Data("sfstubrun: \((error as? LocalizedError)?.errorDescription ?? "\(error)")\n".utf8))
    exit(1)
}
