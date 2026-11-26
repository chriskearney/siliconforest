import Foundation
import SFIdentity
import SFInstallKit
import SFEngine
import SFLiveDisk

// Preview6: the verbs that let the installer app run a full install through the helper: import and
// verify the release, plan, confirm (typed + administrator, then the runtime authorization), and live
// progress. Everything that writes still goes through the engine, the live backend's protection
// receipt and, on the internal disk, the two-key gate.

public struct ReleaseSummary: Codable, Sendable, Hashable {
    public var version: String
    public var digest: String
    public var stage1SHA256: String
    public var rootImageBytes: Int64
    public var files: Int
    public var store: String
}

public struct InstallRequestBody: Codable, Sendable, Hashable {
    public var siliconForestBytes: Int64?
    public var installName: String?
    public init(siliconForestBytes: Int64? = nil, installName: String? = nil) { self.siliconForestBytes = siliconForestBytes; self.installName = installName }
}

public struct StepTitle: Codable, Sendable, Hashable {
    public var code: String
    public var title: String
    public var writesDisk: Bool
    public init(code: String, title: String, writesDisk: Bool) { self.code = code; self.title = title; self.writesDisk = writesDisk }
}

public struct InstallOffer: Codable, Sendable, Hashable {
    public var plan: EnginePlan
    /// What the person types: the macOS volume's name.
    public var expected: TypedConfirmation
    public var gigabytes: Int64
    public var target: String
    public var diskUUID: String?
    public var releaseVersion: String
    public var steps: [StepTitle]
    public init(plan: EnginePlan, expected: TypedConfirmation, gigabytes: Int64, target: String, diskUUID: String?, releaseVersion: String, steps: [StepTitle]) {
        self.plan = plan; self.expected = expected; self.gigabytes = gigabytes; self.target = target
        self.diskUUID = diskUUID; self.releaseVersion = releaseVersion; self.steps = steps
    }
}

public struct ConfirmReply: Codable, Sendable, Hashable {
    public var planDigest: String
    public var validUntil: String
    public var authorizationFileWritten: Bool
}

public struct LiveEvent: Codable, Sendable, Hashable {
    public var seq: UInt64
    public var time: Double
    public var step: String
    /// step, progress, bytes, resize, checked, rollback, simulated
    public var kind: String
    public var text: String
    public var done: Int64?
    public var total: Int64?
    public var percent: Int?
}

public struct LiveProgress: Codable, Sendable, Hashable {
    public var job: String
    public var running: Bool
    public var end: String?
    public var lastError: String?
    public var noChangesMade: Bool
    public var startedAt: String?
    public var records: Int
    public var steps: [StepTitle]
    public var completed: [String]
    public var failed: [String: String]
    public var approvals: [ApprovalNeeded]
    public var events: [LiveEvent]
    public var lastSeq: UInt64
    public var planDigest: String?
    public var installName: String?
    public var operation: String?
    public var confirmedUntil: String?
    /// What to type to confirm this job's plan again (only while it isn't running).
    public var expected: TypedConfirmation?
    /// What the startup-disk bless did (S65), once it has run.
    public var bless: BlessReport?
}

/// Preview7: the outcome of S65 for the finish screen.
public struct BlessReport: Codable, Sendable, Hashable {
    /// The startup disk is set (bless exited 0).
    public var set: Bool
    public var volumeName: String
    /// `bless --getBoot` named the stub (a persistent selection should be named).
    public var confirmed: Bool
    public var note: String
    /// What the person runs themselves if it wasn't set.
    public var manualCommand: String
    /// The helper can shut this Mac down for them now.
    public var canShutDown: Bool
    /// Preview13: a volume owner's login would let the helper set it (macOS asked for owner authentication, or none was given).
    public var needsPassword: Bool? = nil
    /// The helper can retry just the bless with a login.
    public var canRetry: Bool? = nil
}

public struct InstalledInstall: Codable, Sendable, Hashable {
    public var job: String
    public var installID: String
    public var releaseVersion: String
    public var name: String
    public var finished: String?
    public var removable: Bool
    public var note: String?
}

extension HelperService {
    static func isoString(_ d: Date) -> String { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f.string(from: d) }

    // MARK: release bookkeeping

    func releaseNote(_ j: ChainJournal) -> URL { config.journalDirectory.appendingPathComponent("\(j.jobID.uuidString).release.json") }

    var releaseStore: URL { config.releaseStore ?? config.workDirectory.deletingLastPathComponent().appendingPathComponent("releases", isDirectory: true) }

    func rememberRelease(for j: ChainJournal) throws {
        lock.lock(); let imp = imported; lock.unlock()
        guard let imp else { return }
        try Canonical.data(["dir": imp.dir.path, "digest": imp.manifest.digest]).write(to: releaseNote(j), options: .atomic)
    }

    /// The release a job runs with: the one recorded at `begin` (re-verified after a helper restart),
    /// otherwise the configured one. Removal runs without a release.
    func release(for j: ChainJournal, plan: EnginePlan?, operation: EnginePlan.Operation? = nil) throws -> (manifest: ReleaseManifest?, dir: URL?) {
        if (operation ?? plan?.operation) == .remove { return (nil, nil) }
        let note = releaseNote(j)
        if let d = try? Data(contentsOf: note), let o = try? JSONSerialization.jsonObject(with: d) as? [String: String], let path = o["dir"] {
            let dir = URL(fileURLWithPath: path, isDirectory: true)
            lock.lock(); let imp = imported; lock.unlock()
            let m: ReleaseManifest
            if let imp, imp.dir.standardizedFileURL == dir.standardizedFileURL { m = imp.manifest }
            else {
                m = try SFRelease.verify(directory: dir, allowedSigners: config.allowedSigners, allowRehearsal: config.allowRehearsalRelease)
                try StagePin.check(m)
                lock.lock(); imported = (m, dir); lock.unlock()
            }
            if let plan, plan.release != m.digest { throw HelperError.make(.planMismatch, "the job's release isn't the one it was planned with") }
            return (m, dir)
        }
        if let r = config.release { return (r, config.releaseSource) }
        lock.lock(); let imp = imported; lock.unlock()
        return (imp?.manifest, imp?.dir)
    }

    func requireConfirmed(_ digest: String) throws {
        guard config.requireConfirmation else { return }
        lock.lock(); let until = confirmed[digest]; lock.unlock()
        guard let until, until > Date() else {
            throw HelperError.make(.refused, "this plan hasn't been confirmed: type the name of the macOS volume, then approve as an administrator")
        }
    }

    func offer(_ plan: EnginePlan, topology: ImageTopology, diskUUID: String?) {
        guard let exp = TypedConfirmation.expected(plan: plan, topology: topology) else { return }
        lock.lock(); offers[plan.digest] = (plan, exp, diskUUID); lock.unlock()
    }

    func record(_ job: UUID, _ ev: EngineEvent) {
        var e = LiveEvent(seq: 0, time: Date().timeIntervalSince1970, step: "", kind: "", text: "")
        switch ev {
        case .step(let c, let t): e.step = c.rawValue; e.kind = "step"; e.text = t
        case .progress(let c, let t): e.step = c.rawValue; e.kind = "progress"; e.text = t
            // "name 12/57" or "12/57 action": a fraction when there is one.
            if let m = t.range(of: #"(\d+)/(\d+)"#, options: .regularExpression) {
                let parts = t[m].split(separator: "/"); if parts.count == 2, let a = Int64(parts[0]), let b = Int64(parts[1]), b > 0 { e.done = a; e.total = b }
            }
        case .bytes(let c, let d, let t, let phase): e.step = c.rawValue; e.kind = "bytes"; e.text = phase; e.done = d; e.total = t
        case .resize(let r):
            e.step = StepCode.S25.rawValue; e.kind = "resize"
            switch r {
            case .progress(let pct, let phase): e.percent = pct; e.text = phase
            case .started(let pid): e.text = "diskutil started (pid \(pid))"
            case .reattached(let pid): e.text = "reattached to diskutil (pid \(pid))"
            case .sampled(let p, let c): e.text = "partition \(p) B, container \(c) B"; e.done = p
            case .stalled(let s): e.text = "no output from diskutil for \(Int(s)) s (still working; never killed)"
            case .targetReached: e.text = "the partition table shows the new size"
            case .exited(let st): e.text = "diskutil exited \(st.map(String.init) ?? "?")"
            }
        case .checked(let c, let r): e.step = c.rawValue; e.kind = "checked"; e.text = "\(r)"
        case .rollback(let c): e.step = c.rawValue; e.kind = "rollback"; e.text = "undo \(c.title)"
        case .simulated(let n): e.step = n.step; e.kind = "simulated"; e.text = n.command.joined(separator: " ")
        }
        if ["step", "rollback", "checked"].contains(e.kind) { config.log?.info("job \(job.uuidString) \(e.step) \(e.kind): \(e.text)") }
        lock.lock()
        liveSeq += 1; e.seq = liveSeq
        var list = live[job] ?? []
        list.append(e)
        if list.count > 4000 { list.removeFirst(list.count - 4000) }
        live[job] = list
        lock.unlock()
    }

    // MARK: verbs

    public func importRelease(from folder: String, reply: @escaping (Data?, NSError?) -> Void) {
        do {
            let src = URL(fileURLWithPath: folder, isDirectory: true).standardizedFileURL
            func regular(_ u: URL) -> Bool { var st = stat(); return lstat(u.path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFREG }
            let sumsURL = src.appendingPathComponent("SHA256SUMS")
            guard regular(sumsURL), regular(src.appendingPathComponent("SHA256SUMS.sig")) else {
                throw HelperError.make(.refused, "the folder has no SHA256SUMS and SHA256SUMS.sig")
            }
            let sums = try Data(contentsOf: sumsURL)
            var names = ["SHA256SUMS", "SHA256SUMS.sig"]
            for line in String(decoding: sums, as: UTF8.self).split(separator: "\n") {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count == 2 else { throw HelperError.make(.refused, "SHA256SUMS is malformed") }
                let n = String(parts[1])
                guard !n.contains("/"), !n.hasPrefix("."), !n.isEmpty else { throw HelperError.make(.refused, "bad file name in SHA256SUMS: \(n)") }
                names.append(n)
            }
            let fm = FileManager.default
            try fm.createDirectory(at: releaseStore, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
            let dest = releaseStore.appendingPathComponent(String(SHA256Hasher.hex(sums).prefix(16)), isDirectory: true)
            var manifest: ReleaseManifest?
            if fm.fileExists(atPath: dest.path) {
                manifest = try? SFRelease.verify(directory: dest, allowedSigners: config.allowedSigners, allowRehearsal: config.allowRehearsalRelease)
                if manifest == nil { try fm.removeItem(at: dest) }
            }
            if manifest == nil {
                let tmp = releaseStore.appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: true)
                try fm.createDirectory(at: tmp, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
                do {
                    for n in names {
                        let from = src.appendingPathComponent(n)
                        guard regular(from) else { throw HelperError.make(.refused, "\(n) is missing or not a regular file") }
                        try fm.copyItem(at: from, to: tmp.appendingPathComponent(n))
                        chmod(tmp.appendingPathComponent(n).path, 0o644)
                    }
                    // Verified where the helper will read it, after the copy: the app's folder is never trusted.
                    manifest = try SFRelease.verify(directory: tmp, allowedSigners: config.allowedSigners, allowRehearsal: config.allowRehearsalRelease)
                    try fm.moveItem(at: tmp, to: dest)
                } catch { try? fm.removeItem(at: tmp); throw error }
                manifest = try SFRelease.verify(directory: dest, allowedSigners: config.allowedSigners, allowRehearsal: config.allowRehearsalRelease)
            }
            guard let m = manifest else { throw HelperError.make(.failed, "the release didn't verify") }
            try StagePin.check(m)
            lock.lock(); imported = (m, dest); lock.unlock()
            reply(try Canonical.data(ReleaseSummary(version: m.version, digest: m.digest, stage1SHA256: m.artifact(m.stage1)?.sha256 ?? "",
                                                     rootImageBytes: m.rootImageBytes, files: names.count, store: dest.path)), nil)
        } catch let r as SFRelease.Refusal {
            reply(nil, logged(HelperError.make(.refused, "the release doesn't verify: \(r.reason)")))
        } catch { reply(nil, logged(error)) }
    }

    public func planInstall(request: Data, reply: @escaping (Data?, NSError?) -> Void) {
        do {
            let body = try Canonical.decoder().decode(InstallRequestBody.self, from: request)
            lock.lock(); let imp = imported; lock.unlock()
            guard let rel = imp?.manifest ?? config.release else { throw HelperError.make(.refused, "import and verify the release first") }
            let p = try profile()
            let read = try readTarget()
            guard let limits = read.limits else { throw HelperError.make(.refused, "no macOS container on the target") }
            let size = body.siliconForestBytes
                ?? max(p.recommendedFootprint, rel.rootMinBytes + p.partitioning.stubContainerBytes + p.partitioning.bootPartition.bytes)
            let name = (body.installName?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? "SiliconForest"
            let id = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
            let plan = try EnginePlanner.installPlan(topology: read.topology, limits: limits, profile: p, release: rel,
                                                     request: InstallRequest(siliconForestBytes: size, installName: name, installID: id))
            offer(plan, topology: read.topology, diskUUID: read.diskUUID)
            guard let exp = TypedConfirmation.expected(plan: plan, topology: read.topology) else { throw HelperError.make(.failed, "the macOS volume has no name") }
            let label: String
            switch config.target {
            case .internalDisk: label = "this Mac's internal disk"
            case .image(let u): label = "disk image \(u.lastPathComponent)"
            case .live(let a): label = a.label
            case .none: label = "none"
            }
            reply(try Canonical.data(InstallOffer(plan: plan, expected: exp, gigabytes: TypedConfirmation.gigabytes(plan: plan), target: label,
                                                  diskUUID: read.diskUUID, releaseVersion: rel.version,
                                                  steps: StepCode.order(plan).map { StepTitle(code: $0.rawValue, title: $0.title, writesDisk: $0.writesDisk) })), nil)
        } catch { reply(nil, logged(error)) }
    }

    public func confirm(planDigest: String, typed: Data, authorization: Data, reply: @escaping (Data?, NSError?) -> Void) {
        do {
            lock.lock(); var entry = offers[planDigest]; lock.unlock()
            if entry == nil {
                // An unfinished job's plan (resume after a restart, or after the 2 hours ran out).
                for url in ChainJournal.unfinished(in: config.journalDirectory) {
                    guard let j = try? ChainJournal.open(url), let plan = JobState(j.records).plan, plan.digest == planDigest else { continue }
                    let read = try readTarget()
                    if let exp = TypedConfirmation.expected(plan: plan, topology: read.topology) { entry = (plan, exp, read.diskUUID) }
                }
            }
            guard let entry else { throw HelperError.make(.planMismatch, "the helper didn't offer this plan") }
            let t = try Canonical.decoder().decode(TypedConfirmation.self, from: typed)
            guard t.matches(entry.expected) else {
                throw HelperError.make(.refused, "what you typed doesn't match the name of the macOS volume (“\(entry.expected.diskName)”)")
            }
            guard config.adminCheck.verify(authorization) else { throw HelperError.make(.refused, "an administrator didn't approve this change") }
            let auth = AuthorizationFile.authorization(planDigest: planDigest, diskUUID: entry.diskUUID ?? "")
            var wrote = false
            if case .internalDisk = config.target {
                #if SF_REAL_DISK_WRITES
                guard geteuid() == 0 else { throw HelperError.make(.refused, "the internal disk needs the root helper") }
                let now = try StartupDisk.find()
                guard let want = entry.diskUUID, now.uuid == want.uppercased() else { throw HelperError.make(.planMismatch, "the startup disk isn't the one this plan was made for") }
                try AuthorizationFile.write(auth, to: config.authorizationPath)
                guard case .success = RealDiskGate.evaluate(planDigest: planDigest, diskUUID: want, path: config.authorizationPath) else {
                    AuthorizationFile.remove(config.authorizationPath)
                    throw HelperError.make(.failed, "the authorization the helper wrote doesn't open the gate")
                }
                wrote = true
                #else
                throw HelperError.make(.noTarget, "This build can't write to an internal disk (no SF_REAL_DISK_WRITES).")
                #endif
            }
            lock.lock(); confirmed[planDigest] = auth.notAfter; lock.unlock()
            reply(try Canonical.data(ConfirmReply(planDigest: planDigest, validUntil: Self.isoString(auth.notAfter), authorizationFileWritten: wrote)), nil)
        } catch { reply(nil, logged(error)) }
    }

    public func progress(job: String, after sequence: UInt64, reply: @escaping (Data?, NSError?) -> Void) {
        do {
            let j = try journal(job)
            let st = JobState(j.records)
            lock.lock()
            let isRunning = running.contains(j.jobID), err = lastError[j.jobID]
            let all = live[j.jobID] ?? []
            let until = st.plan.flatMap { confirmed[$0.digest] }
            lock.unlock()
            let events = all.filter { $0.seq > sequence }
            let steps = st.plan.map { p in StepCode.order(p).map { StepTitle(code: $0.rawValue, title: $0.title, writesDisk: $0.writesDisk) } } ?? []
            var expected: TypedConfirmation?
            if !isRunning, st.end == nil, let plan = st.plan, let t = try? readTarget().topology { expected = TypedConfirmation.expected(plan: plan, topology: t) }
            reply(try Canonical.data(LiveProgress(
                job: j.jobID.uuidString, running: isRunning, end: st.end?.rawValue, lastError: err, noChangesMade: st.noChangesMade,
                startedAt: j.records.first?.t, records: j.records.count, steps: steps,
                completed: StepCode.allCases.filter { st.done($0) }.map(\.rawValue),
                failed: Dictionary(uniqueKeysWithValues: st.failed.map { ($0.key.rawValue, $0.value) }),
                approvals: st.approvals, events: events, lastSeq: max(sequence, all.last?.seq ?? 0),
                planDigest: st.plan?.digest, installName: st.plan?.request?.installName, operation: st.plan?.operation.rawValue,
                confirmedUntil: until.map { Self.isoString($0) }, expected: expected, bless: blessReport(st))), nil)
        } catch { reply(nil, logged(error)) }
    }
}

extension HelperService {
    func blessReport(_ st: JobState) -> BlessReport? {
        guard st.plan?.operation == .install, let ev = st.evidence[.S65], let r = ev["blessed"]?.string else {
            if st.plan?.operation == .install, st.status[.S65] == .simulated {
                return BlessReport(set: false, volumeName: st.plan?.request?.installName ?? "SiliconForest", confirmed: false,
                                   note: "This build doesn't change the startup disk.", manualCommand: BlessGuard.manual(volumeName: st.plan?.request?.installName ?? "SiliconForest"), canShutDown: false)
            }
            return nil
        }
        let name = ev["name"]?.string ?? st.plan?.request?.installName ?? "SiliconForest"
        let set = r == "startup disk" || r == "next boot only"   // the second is what preview7 to 12 journals say
        return BlessReport(set: set, volumeName: name, confirmed: (ev["confirmed"]?.string ?? "").hasPrefix("getBoot names"),
                           note: set ? (ev["confirmed"]?.string ?? "") : (ev["why"]?.string ?? "bless didn't run"),
                           manualCommand: ev["manual"]?.string ?? BlessGuard.manual(volumeName: name),
                           canShutDown: set && config.shutdownAction != nil,
                           needsPassword: set ? false : (ev["needsPassword"]?.string == "yes"),
                           canRetry: !set && config.blessRunner is PasswordBlessRunner)
    }

    // MARK: Remove SiliconForest

    func finishedInstalls() -> [(job: String, journal: ChainJournal, state: JobState)] {
        let files = (try? FileManager.default.contentsOfDirectory(at: config.journalDirectory, includingPropertiesForKeys: nil)) ?? []
        var out: [(String, ChainJournal, JobState)] = []
        var removed = Set<UUID>()
        for u in files where u.pathExtension == "jsonl" {
            guard let j = try? ChainJournal.open(u) else { continue }
            let st = JobState(j.records)
            if st.plan?.operation == .remove, st.end == .committed, let id = st.plan?.installJob { removed.insert(id) }
            if st.plan?.operation == .install, st.end == .handedOff || st.end == .committed { out.append((j.jobID.uuidString, j, st)) }
        }
        return out.filter { !removed.contains($0.1.jobID) }.sorted { ($0.1.records.first?.t ?? "") > ($1.1.records.first?.t ?? "") }
    }

    public func listInstalls(reply: @escaping (Data?, NSError?) -> Void) {
        self.reply(reply) {
            let topology = try? readTarget().topology
            let list = finishedInstalls().map { (job, j, st) -> InstalledInstall in
                var removable = false, note: String?
                if let topology {
                    do {
                        let proof = try InstallProofReader.proof(from: j)
                        _ = try EnginePlanner.removalPlan(topology: topology, profile: try profile(), proof: proof)
                        removable = true
                    } catch { note = "\(error)" }
                } else { note = "this Mac's disk can't be read by the helper" }
                return InstalledInstall(job: job, installID: st.plan?.request?.installID ?? "", releaseVersion: st.plan?.releaseVersion ?? "",
                                        name: st.plan?.request?.installName ?? "SiliconForest", finished: j.records.last?.t, removable: removable, note: note)
            }
            return try Canonical.data(list)
        }
    }

    public func planRemoval(installJob: String, reply: @escaping (Data?, NSError?) -> Void) {
        self.reply(reply) {
            let proof = try InstallProofReader.proof(from: try journal(installJob))
            let read = try readTarget()
            let plan = try EnginePlanner.removalPlan(topology: read.topology, profile: try profile(), proof: proof)
            offer(plan, topology: read.topology, diskUUID: read.diskUUID)
            guard let exp = TypedConfirmation.expected(plan: plan, topology: read.topology) else { throw HelperError.make(.failed, "the macOS volume has no name") }
            let label: String
            switch config.target {
            case .internalDisk: label = "this Mac's internal disk"
            case .image(let u): label = "disk image \(u.lastPathComponent)"
            case .live(let a): label = a.label
            case .none: label = "none"
            }
            return try Canonical.data(InstallOffer(plan: plan, expected: exp, gigabytes: TypedConfirmation.gigabytes(plan: plan), target: label,
                                                   diskUUID: read.diskUUID, releaseVersion: plan.releaseVersion,
                                                   steps: StepCode.order(plan).map { StepTitle(code: $0.rawValue, title: $0.title, writesDisk: $0.writesDisk) }))
        }
    }

    public func startupOwners(reply: @escaping (Data?, NSError?) -> Void) {
        self.reply(reply) { try Canonical.data(config.startupOwners()) }
    }

    public func retryStartupSelection(job: String, owner: String, password: Data, reply: @escaping (Data?, NSError?) -> Void) {
        let secret = SecureBytes(password)
        defer { secret.wipe() }
        self.reply(reply) {
            let j = try journal(job)
            let st = JobState(j.records)
            guard let plan = st.plan, plan.operation == .install, st.end == .handedOff else { throw HelperError.make(.refused, "this job isn't a finished install") }
            guard finishedInstalls().contains(where: { $0.job == job }) else { throw HelperError.make(.refused, "that install has been removed") }
            guard config.blessRunner is PasswordBlessRunner else { throw HelperError.make(.refused, "this build doesn't change the startup disk") }
            try requireOwner(owner)
            let e = try engine(j, planDigest: plan.digest)
            let cred = BlessCredential(owner: owner, secret: secret)
            e.blessCredential = { cred }
            try e.retryStartupDisk()
            guard let report = blessReport(JobState(j.records)) else { throw HelperError.make(.failed, "the startup disk step left no record") }
            return try Canonical.data(report)
        }
    }

    public func retire(reply: @escaping (NSError?) -> Void) {
        lock.lock(); let busy = !running.isEmpty; lock.unlock()
        guard !busy else { reply(HelperError.make(.busy, "a job is running; the helper can't restart now")); return }
        guard let action = config.retireAction else { reply(HelperError.make(.refused, "this build doesn't restart the helper")); return }
        config.log?.info("retire: exiting so the next connection starts the current build")
        DispatchQueue.global().asyncAfter(deadline: .now() + config.retireDelay) { action() }
        reply(nil)
    }

    public func shutDownToFinishSetup(job: String, reply: @escaping (NSError?) -> Void) {
        do {
            let j = try journal(job)
            let st = JobState(j.records)
            guard let plan = st.plan, plan.operation == .install, st.end == .handedOff else { throw HelperError.make(.refused, "this job isn't a finished install") }
            guard let report = blessReport(st), report.set else { throw HelperError.make(.refused, "the startup disk wasn't set; shut down and choose SiliconForest from startup options instead") }
            // The in-memory confirmation may be gone (the helper exits when idle); the journal proves it: begin needed it.
            // Only a finished, not-yet-removed install, and only for a day after it finished.
            guard finishedInstalls().contains(where: { $0.job == job }) else { throw HelperError.make(.refused, "that install has been removed") }
            if let t = j.records.last?.t, let d = ISO8601DateFormatter().date(from: t), Date().timeIntervalSince(d) > 24 * 3600 {
                throw HelperError.make(.refused, "that install finished more than a day ago; shut down and choose SiliconForest from startup options instead")
            }
            guard let action = config.shutdownAction else { throw HelperError.make(.refused, "this build doesn't shut the Mac down") }
            let delay = config.shutdownDelay
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { action() }
            reply(nil)
        } catch { reply(logged(error)) }
    }
}
