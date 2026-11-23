import Foundation
import SFInstallKit

/// What each step does, how it proves it is done, and how a resumed engine finds out.
extension InstallEngine {

    func perform(_ code: StepCode, plan: EnginePlan, gate: inout Gate) throws {
        let c = code.rawValue
        switch code {
        case .S00:
            let t = try backend.topology()
            let l = try backend.limits(store: plan.macOS.store)
            try journal.append(.intent, step: c)
            try journal.append(.evidence, step: c, result: ["layout_digest": .s(t.layoutDigest), "min_preferred": .i(l.minimumPreferred),
                                                            "partitions": .i(Int64(t.partitions.count))])
        case .S05:
            try journal.append(.intent, step: c)
            try journal.append(.evidence, step: c, result: ["plan_digest": .s(plan.digest)])
        case .S08:
            // In-process here (tests, rehearsal); SMAppService registration in the app.
            try journal.append(.intent, step: c)
            try journal.append(.evidence, step: c, result: ["helper": .s("in-process")])

        case .S10:
            guard let release, let src = releaseSource else { throw EngineError(.internalError, "no release to fetch") }
            try journal.append(.intent, step: c, args: ["from": .s(src.path), "files": .i(Int64(release.artifacts.count))])
            try FileManager.default.ensureDirectory(workDir)
            for a in release.artifacts {
                let dst = work(a.name)
                if let size = try? FileManager.default.attributesOfItem(atPath: dst.path)[.size] as? Int64, size == a.bytes { continue }
                try FileManager.default.ensureDirectory(dst.deletingLastPathComponent())
                try? FileManager.default.removeItem(at: dst)
                try FileManager.default.copyItem(at: src.appendingPathComponent(a.name), to: dst)
            }
            try afterCommand(code)
            try journal.append(.evidence, step: c, result: ["bytes": .i(release.artifacts.reduce(0) { $0 + $1.bytes })])
        case .S15:
            guard let release else { throw EngineError(.internalError, "no release") }
            try journal.append(.intent, step: c)
            for a in release.artifacts {
                let h = try SHA256Hasher.file(work(a.name))
                guard h == a.sha256 else {
                    try? FileManager.default.removeItem(at: work(a.name))
                    throw EngineError(.transient, "\(a.name) didn't match its checksum; it will be downloaded again")
                }
            }
            try journal.append(.evidence, step: c, result: ["verified": .i(Int64(release.artifacts.count))])

        case .S20:
            // `diskutil apfs updatePreboot` writes macOS's Preboot: needs root and a live macOS volume
            // group. Recorded for Chris's approval and simulated; it is never run on an image.
            try simulate(code, command: ["/usr/sbin/diskutil", "apfs", "updatePreboot", "<macOS System volume>"],
                         reason: "needs root and a real macOS volume group; on the Mac it runs only when the admin list is stale")

        case .S25:
            try journal.append(.intent, step: c, args: ["store": .s(plan.macOS.store), "from": .i(plan.macOS.from), "to": .i(plan.macOS.to)])
            // A resize that survived a helper restart is reattached, not started again (ENGINE §8.7).
            if try backend.freshTopology().partition(uuid: plan.macOS.store)?.size != plan.macOS.to || resizeStillRunning(code) {
                if !resizeStillRunning(code) { try gate.admit(.resize(store: plan.macOS.store, to: plan.macOS.to), now: try backend.topology()) }
                let out = try resize(plan: plan, to: plan.macOS.to, code: code)
                guard out == .completed else { throw Self.resizeError(out) }
            }
            try afterCommand(code)
            try gate.verifyAfter(try backend.freshTopology())
            try journal.append(.evidence, step: c, result: ["size": .i(plan.macOS.to)])

        case .S30, .S40, .S45:
            let role = code == .S30 ? "stub" : code == .S40 ? "boot" : "root"
            guard let np = plan.partition(role) else { throw EngineError(.internalError, "plan has no \(role)") }
            let after = np.after == "@macos" ? plan.macOS.store : gate.created[String(np.after.dropFirst())]
            guard let after else { throw EngineError(.inconsistent, "\(np.after) doesn't exist yet") }
            let verb = DiskVerb.addPartition(role: role, after: after, content: np.content, label: np.label, bytes: np.bytes)
            try gate.admit(verb, now: try backend.topology())
            try journal.append(.intent, step: c, args: ["role": .s(role), "after": .s(after), "bytes": .i(np.bytes), "content": .s(np.content)])
            let uuid = try backend.addPartition(after: after, content: np.content, label: np.label, bytes: np.bytes)
            gate.created[role] = uuid
            if role == "boot" {
                try gate.admit(.formatFAT32(partition: uuid, label: np.label), now: try backend.topology())
                try backend.formatFAT32(uuid, label: np.label)
            }
            // diskutil carves a 128 MiB Apple_Boot booter out of Linux-type partitions of about 1.5 GB
            // and up, directly after them. It is this job's object: recorded here, erased by S46.
            var ev: JArgs = [:]
            if role == "root", let b = Self.booter(after: uuid, in: try backend.topology(), original: gate.original) {
                gate.created["booter"] = b.uuid
                ev["booter"] = .s(b.uuid)
            }
            try afterCommand(code)
            try gate.verifyAfter(try backend.freshTopology())
            let p = try backend.topology().partition(uuid: uuid)!
            try journal.append(.evidence, step: c, result: ev.merging(["role": .s(role), "uuid": .s(uuid), "first": .i(p.offset), "len": .i(p.size)]) { a, _ in a })

        case .S46:
            try journal.append(.intent, step: c, args: ["booter": gate.created["booter"].map(JValue.s) ?? .null])
            if let b = gate.created["booter"], try backend.topology().partition(uuid: b) != nil {
                try gate.admit(.eraseToFree(partition: b), now: try backend.topology(), rollback: false)
                try backend.eraseToFree(b)
            }
            try afterCommand(code)
            try gate.verifyAfter(try backend.freshTopology())
            try journal.append(.evidence, step: c, result: ["booter": .s(gate.created["booter"] == nil ? "none" : "erased")])

        case .S32:
            guard let stub = gate.created["stub"] else { throw EngineError(.inconsistent, "no stub") }
            try journal.append(.intent, step: c, args: ["roles": .a(["S", "D", "B", "R"].map(JValue.s))])
            let name = plan.request?.installName ?? "SiliconForest"
            let have = Set(try backend.topology().partition(uuid: stub)?.apfs?.volumes.flatMap(\.roles) ?? [])
            for (role, full, suffix) in [("S", "System", ""), ("D", "Data", " - Data"), ("B", "Preboot", " - Preboot"), ("R", "Recovery", " - Recovery")]
                where !have.contains(full) {
                try gate.admit(.addVolume(store: stub, name: name + suffix, role: role), now: try backend.topology())
                try backend.addVolume(container: stub, name: name + suffix, role: role)
            }
            try afterCommand(code)
            guard case .done(let ev) = try check(code, plan: plan, gate: gate) else { throw EngineError(.appleTool, "the stub's volumes are incomplete") }
            try journal.append(.evidence, step: c, result: ev)

        case .S35:
            guard let release, let stub = gate.created["stub"] else { throw EngineError(.inconsistent, "no stub") }
            try gate.admit(.writeFiles(partition: stub, volumeRole: "System", files: release.stubFiles), now: try backend.topology())
            try journal.append(.intent, step: c, args: ["files": .i(Int64(release.stubFiles.count))])
            let vol = try backend.volumeURL(store: stub, role: "System")
            for f in release.stubFiles {
                try copy(work(f), to: vol.appendingPathComponent(String(f.dropFirst("stub/".count))))
            }
            try writeManifest(vol.appendingPathComponent(".sf/stub-manifest.txt"), files: release.stubFiles.map { (String($0.dropFirst(5)), release.artifact($0)!.sha256) })
            try afterCommand(code)
            guard case .done(let ev) = try check(code, plan: plan, gate: gate) else { throw EngineError(.appleTool, "read-back of the stub files failed") }
            try journal.append(.evidence, step: c, result: ev)

        case .S47:
            guard let release, let root = gate.created["root"] else { throw EngineError(.inconsistent, "no root partition") }
            try gate.admit(.writeRaw(partition: root, offset: 0, bytes: release.rootImageBytes), now: try backend.topology())
            try journal.append(.intent, step: c, args: ["image": .s(release.rootImage), "bytes": .i(release.rootImageBytes)])
            let w = try backend.writeImage(root, source: work(release.rootImage), compressed: release.rootImageCompressed)
            guard w.bytes == release.rootImageBytes, w.sha256 == release.rootImageSHA256 else {
                throw EngineError(.inconsistent, "the decompressed image isn't the release's (\(w.bytes) B)")
            }
            try afterCommand(code)
            // Full read-back: no partial is trusted.
            let back = try backend.hashRaw(root, bytes: release.rootImageBytes)
            guard back == release.rootImageSHA256 else { throw EngineError(.appleTool, "read-back of the root image doesn't match") }
            try journal.append(.evidence, step: c, result: ["sha256": .s(back)])

        case .S42:
            guard let release, let boot = gate.created["boot"], let root = gate.created["root"] else { throw EngineError(.inconsistent, "no SFBOOT or root") }
            try gate.admit(.writeFiles(partition: boot, volumeRole: nil, files: [release.stage2, release.kernel]), now: try backend.topology())
            try journal.append(.intent, step: c)
            let dir = try backend.fatURL(boot).appendingPathComponent("sf", isDirectory: true)
            try FileManager.default.ensureDirectory(dir)
            try copy(work(release.stage2), to: dir.appendingPathComponent("boot.bin"))
            try atomicWrite(try personalisedKernel(root: root), to: dir.appendingPathComponent("kernel.bin"))
            try atomicWrite(try installJSON(plan: plan, gate: gate), to: dir.appendingPathComponent("install.json"))
            try afterCommand(code)
            guard case .done(let ev) = try check(code, plan: plan, gate: gate) else { throw EngineError(.appleTool, "read-back of SFBOOT failed") }
            try journal.append(.evidence, step: c, result: ev)

        case .S50, .S52:
            guard let release, let root = gate.created["root"] else { throw EngineError(.inconsistent, "no root partition") }
            let (offset, data) = code == .S50 ? (release.firmwareSlotOffset, try firmwareSlot()) : (release.receiptSlotOffset, receiptHeader(plan))
            try gate.admit(.writeRaw(partition: root, offset: offset, bytes: Int64(data.count)), now: try backend.topology())
            try journal.append(.intent, step: c, args: ["offset": .i(offset), "bytes": .i(Int64(data.count))])
            try backend.writeRaw(root, offset: offset, data: data)
            try afterCommand(code)
            guard case .done(let ev) = try check(code, plan: plan, gate: gate) else { throw EngineError(.appleTool, "read-back of the slot failed") }
            try journal.append(.evidence, step: c, result: ev)

        case .S55, .S60, .S68:
            guard let stub = gate.created["stub"] else { throw EngineError(.inconsistent, "no stub") }
            try gate.admit(.writeFiles(partition: stub, volumeRole: "System", files: []), now: try backend.topology())
            try journal.append(.intent, step: c)
            breadcrumb = "mounting the stub's System volume"
            let vol = try backend.volumeURL(store: stub, role: "System")
            breadcrumb = nil
            switch code {
            case .S55: try atomicWrite(try bootObject(gate: gate), to: vol.appendingPathComponent(".sf/boot.bin"))
            case .S60: try stageRecovery(vol: vol, plan: plan, gate: gate)
            default: try hide(vol: vol)
            }
            try afterCommand(code)
            guard case .done(let ev) = try check(code, plan: plan, gate: gate) else { throw EngineError(.appleTool, "read-back on the stub failed") }
            try journal.append(.evidence, step: c, result: ev)

        case .S65:
            try simulate(code, command: ["/usr/sbin/bless", "--mount", "<stub System volume>", "--setBoot", "--nextonly"],
                         reason: "needs root and the owner's password; on an image there is no startup disk to change")
        case .S70:
            try journal.append(.intent, step: c)
            try journal.append(.evidence, step: c, result: ["awaiting": .s("recoveryOS")])

        // Removal (DESIGN §8.4)
        case .U10:
            try simulate(code, command: ["/usr/sbin/bless", "--mount", "<previous startup volume>", "--setBoot"],
                         reason: "needs root; restores the previous startup disk before anything is deleted")
        case .U20:
            guard let owned = plan.owned else { throw EngineError(.internalError, "removal without ownership") }
            try journal.append(.intent, step: c, args: ["delete": .a(owned.all.map(JValue.s))])
            for (role, uuid) in [("stub", owned.stub), ("boot", owned.boot), ("root", owned.root)] {
                guard let uuid, try backend.topology().partition(uuid: uuid) != nil else { continue }
                let verb: DiskVerb = role == "stub" ? .deleteContainer(partition: uuid) : .eraseToFree(partition: uuid)
                try gate.admit(verb, now: try backend.topology())
                if role == "stub" { try backend.deleteContainer(uuid) } else { try backend.eraseToFree(uuid) }
                try gate.verifyAfter(try backend.freshTopology())
            }
            try afterCommand(code)
            try journal.append(.evidence, step: c, result: ["deleted": .i(Int64(owned.all.count))])
        case .U30:
            let now = try backend.topology()
            try journal.append(.intent, step: c, args: ["store": .s(plan.macOS.store), "to": .i(plan.macOS.to)])
            if now.partition(uuid: plan.macOS.store)?.size != plan.macOS.to || resizeStillRunning(code) {
                if !resizeStillRunning(code) { try gate.admit(.grow(store: plan.macOS.store), now: now) }
                let out = try resize(plan: plan, to: 0, code: code, expect: plan.macOS.to)
                try afterCommand(code)
                guard out == .completed else { throw Self.resizeError(out) }
            }
            try gate.verifyAfter(try backend.freshTopology())
            try journal.append(.evidence, step: c, result: ["size": .i(plan.macOS.to)])
        case .U40:
            try journal.append(.intent, step: c)
            let now = try backend.topology()
            guard now.layoutDigest == plan.originalLayoutDigest else {
                throw EngineError(.inconsistent, "the partition table differs from the one saved before installing")
            }
            try journal.append(.evidence, step: c, result: ["layout_digest": .s(now.layoutDigest)])
        }
        try journal.append(.checkpoint, step: c)
    }

    // MARK: idempotent checks (ENGINE §7 column 4)

    func check(_ code: StepCode, plan: EnginePlan, gate: Gate) throws -> CheckResult {
        let t = try backend.freshTopology()
        switch code {
        case .S00, .S05, .S08, .S70, .S20, .S65, .U10:
            return .notDone   // reads or records only: rerun
        case .S10:
            guard let release else { return .notDone }
            let ok = release.artifacts.allSatisfy { (try? FileManager.default.attributesOfItem(atPath: work($0.name).path)[.size] as? Int64) == $0.bytes }
            return ok ? .done(["bytes": .i(release.artifacts.reduce(0) { $0 + $1.bytes })]) : .notDone
        case .S15:
            return .notDone
        case .S25:
            guard let mac = t.partition(uuid: plan.macOS.store) else { return .cannotTell("the macOS container is missing") }
            let c = mac.apfs?.capacityCeiling ?? mac.size
            if mac.size == plan.macOS.to && c <= plan.macOS.to { return .done(["size": .i(mac.size)]) }
            // A resize still running (the helper died mid-resize) is not done: S25 reattaches to it.
            if resizeStillRunning(code) { return .notDone }
            if mac.size == plan.macOS.from && c == plan.macOS.from { return .notDone }
            return .cannotTell("macOS is \(mac.size) B (container \(c) B), neither \(plan.macOS.from) nor \(plan.macOS.to)")
        case .S30, .S40, .S45:
            let role = code == .S30 ? "stub" : code == .S40 ? "boot" : "root"
            guard let np = plan.partition(role) else { return .cannotTell("no \(role) in the plan") }
            let afterUUID = np.after == "@macos" ? plan.macOS.store : gate.created[String(np.after.dropFirst())]
            guard let afterUUID, let prev = t.partition(uuid: afterUUID) else { return .notDone }
            let known = Set(gate.original.partitions.map(\.uuid))
            guard let next = t.next(after: afterUUID), next.offset == prev.end, !known.contains(next.uuid) else { return .notDone }
            // Found by span: directly after its predecessor, the planned length and type, and not a
            // partition that existed before the job began.
            let sizes: Set<Int64> = role == "root" ? [np.bytes, np.bytes - Self.booterBytes] : [np.bytes]
            guard sizes.contains(next.size), next.content == np.content else {
                return .cannotTell("a \(next.content) partition of \(next.size) B sits where the \(role) belongs")
            }
            if role == "boot" && next.filesystem != "msdos" {
                return .notDone   // partition made, format not finished: format again
            }
            var ev: JArgs = ["role": .s(role), "uuid": .s(next.uuid), "first": .i(next.offset), "len": .i(next.size), "found": .s("by span")]
            if role == "root", let b = Self.booter(after: next.uuid, in: t, original: gate.original) { ev["booter"] = .s(b.uuid) }
            return .done(ev)
        case .S46:
            guard let b = gate.created["booter"] else { return .done(["booter": .s("none")]) }
            return t.partition(uuid: b) == nil ? .done(["booter": .s("erased")]) : .notDone
        case .S32:
            guard let stub = gate.created["stub"], let a = t.partition(uuid: stub)?.apfs else { return .notDone }
            let roles = Set(a.volumes.flatMap(\.roles))
            return ["System", "Data", "Preboot", "Recovery"].allSatisfy(roles.contains) ? .done(["volumes": .i(Int64(a.volumes.count))]) : .notDone
        case .S35:
            guard let release, let stub = gate.created["stub"], let vol = try? backend.volumeURL(store: stub, role: "System") else { return .notDone }
            for f in release.stubFiles {
                guard (try? SHA256Hasher.file(vol.appendingPathComponent(String(f.dropFirst(5))))) == release.artifact(f)?.sha256 else { return .notDone }
            }
            return .done(["files": .i(Int64(release.stubFiles.count))])
        case .S47:
            guard let release, let root = gate.created["root"] else { return .notDone }
            return (try? backend.hashRaw(root, bytes: release.rootImageBytes)) == release.rootImageSHA256 ? .done(["sha256": .s(release.rootImageSHA256)]) : .notDone
        case .S42:
            guard let release, let boot = gate.created["boot"], let root = gate.created["root"], let fat = try? backend.fatURL(boot) else { return .notDone }
            let dir = fat.appendingPathComponent("sf")
            guard (try? SHA256Hasher.file(dir.appendingPathComponent("boot.bin"))) == release.artifact(release.stage2)?.sha256,
                  let k = try? Data(contentsOf: dir.appendingPathComponent("kernel.bin")), k == (try personalisedKernel(root: root)),
                  FileManager.default.fileExists(atPath: dir.appendingPathComponent("install.json").path) else { return .notDone }
            return .done(["kernel_sha256": .s(SHA256Hasher.hex(k))])
        case .S50, .S52:
            guard let release, let root = gate.created["root"] else { return .notDone }
            let (offset, want) = code == .S50 ? (release.firmwareSlotOffset, try firmwareSlot()) : (release.receiptSlotOffset, receiptHeader(plan))
            let got = try backend.readRaw(root, offset: offset, count: want.count)
            return got == want ? .done(["sha256": .s(SHA256Hasher.hex(got))]) : .notDone
        case .S55, .S60, .S68:
            guard let stub = gate.created["stub"], let vol = try? backend.volumeURL(store: stub, role: "System") else { return .notDone }
            switch code {
            case .S55:
                guard let d = try? Data(contentsOf: vol.appendingPathComponent(".sf/boot.bin")), d == (try bootObject(gate: gate)) else { return .notDone }
                return .done(["sha256": .s(SHA256Hasher.hex(d))])
            case .S60:
                let app = vol.appendingPathComponent("SiliconForest Setup.app/Contents")
                let need = ["MacOS/sf-launcher", "MacOS/SFRecovery", "Resources/sf-step2.sh", "Resources/boot.bin"]
                guard need.allSatisfy({ FileManager.default.fileExists(atPath: app.appendingPathComponent($0).path) }),
                      FileManager.default.fileExists(atPath: vol.appendingPathComponent("SFInstall/plan.json").path) else { return .notDone }
                return .done(["app": .s("SiliconForest Setup.app")])
            default:
                let core = vol.appendingPathComponent("System/Library/CoreServices")
                let hidden = FileManager.default.fileExists(atPath: core.appendingPathComponent("SystemVersion.plist.sf-hidden").path)
                    && !FileManager.default.fileExists(atPath: core.appendingPathComponent("SystemVersion.plist").path)
                let marker = FileManager.default.fileExists(atPath: vol.appendingPathComponent(".IAPhysicalMedia").path)
                return hidden && marker ? .done(["handoff": .b(true)]) : .notDone
            }
        case .U20:
            let gone = (plan.owned?.all ?? []).allSatisfy { t.partition(uuid: $0) == nil }
            return gone ? .done(["deleted": .i(Int64(plan.owned?.all.count ?? 0))]) : .notDone
        case .U30:
            guard let mac = t.partition(uuid: plan.macOS.store) else { return .cannotTell("macOS container missing") }
            if mac.size == plan.macOS.to && !resizeStillRunning(code) { return .done(["size": .i(mac.size)]) }
            return .notDone
        case .U40:
            return .notDone
        }
    }

    static let booterBytes: Int64 = 134_217_728

    /// An Apple_Boot partition diskutil made directly after `uuid` (never one that existed before).
    static func booter(after uuid: String, in t: ImageTopology, original: ImageTopology) -> ImagePartition? {
        guard let p = t.partition(uuid: uuid), let n = t.next(after: uuid), n.content == "Apple_Boot", n.offset == p.end,
              original.partition(uuid: n.uuid) == nil, n.size == booterBytes else { return nil }
        return n
    }

    // MARK: resize through the supervisor

    func resizeStillRunning(_ code: StepCode) -> Bool {
        guard let pid = lastResizePID(code) else { return false }
        return launcher.reattach(pid: pid)?.isRunning() == true
    }

    func lastResizePID(_ code: StepCode) -> Int32? {
        journal.records.last { $0.kind == .note && $0.step == code.rawValue && $0.args?["resize_pid"] != nil }?.args?["resize_pid"]?.int.map(Int32.init)
    }

    /// Reattaches to a surviving resize if there is one; otherwise starts it. Returns the classified outcome.
    func resize(plan: EnginePlan, to bytes: Int64, code: StepCode, expect: Int64? = nil) throws -> ResizeOutcome {
        let sup = ResizeSupervisor(backend: backend, launcher: launcher, timing: resizeTiming)
        sup.onEvent = { [weak self] e in self?.onEvent?(.resize(e)) }
        sup.dieAfter = faults.resizeDieAfter
        let from = try backend.topology().partition(uuid: plan.macOS.store)?.size ?? plan.macOS.from
        let target = expect ?? bytes
        if resizeStillRunning(code), let pid = lastResizePID(code),
           let out = try sup.reattach(pid: pid, store: plan.macOS.store, from: from, to: target, log: resizeLog) {
            try journal.append(.note, step: code.rawValue, result: ["reattached": .i(Int64(pid))], note: "reattached to a surviving resize")
            return out
        }
        let (started, proc) = try sup.start(store: plan.macOS.store, to: bytes, log: resizeLog)
        try journal.append(.note, step: code.rawValue, args: ["resize_pid": .i(Int64(started.pid)), "log": .s(started.log.path)])
        return try sup.watch(proc, store: plan.macOS.store, from: from, to: target, log: resizeLog)
    }

    static func resizeError(_ o: ResizeOutcome) -> EngineError {
        switch o {
        case .completed: return EngineError(.internalError, "not an error")
        case .unchanged(let m): return EngineError(.appleTool, "macOS couldn't be resized; nothing changed", detail: m)
        case .needsFirstAid(let m): return EngineError(.appleTool, "macOS's container needs First Aid from recoveryOS; nothing changed", detail: m)
        case .inconsistent(let p, let c): return EngineError(.inconsistent, "the container (\(c) B) and its partition (\(p) B) disagree: reconcile", detail: "Omacom #210")
        case .unknown(let m): return EngineError(.inconsistent, "the resize ended in an unknown state; keep the Mac on and export diagnostics", detail: m)
        }
    }

    // MARK: simulated steps

    func simulate(_ code: StepCode, command: [String], reason: String) throws {
        let a = ApprovalNeeded(step: code.rawValue, command: command, reason: reason)
        onEvent?(.simulated(a))
        try journal.append(.simulated, step: code.rawValue, args: ["command": .a(command.map(JValue.s)), "reason": .s(reason),
                                                                     "approval": .s("needs Chris's approval")])
    }

    // MARK: contents

    func copy(_ src: URL, to dst: URL) throws {
        try FileManager.default.ensureDirectory(dst.deletingLastPathComponent())
        try atomicWrite(try Data(contentsOf: src), to: dst)
    }

    func atomicWrite(_ data: Data, to url: URL) throws {
        breadcrumb = "writing \(url.lastPathComponent)"
        defer { breadcrumb = nil }
        try FileManager.default.ensureDirectory(url.deletingLastPathComponent())
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).sf-tmp")
        try data.write(to: tmp)
        let h = try FileHandle(forUpdating: tmp); try h.synchronize(); try h.close()
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try FileManager.default.moveItem(at: tmp, to: url)
    }

    func writeManifest(_ url: URL, files: [(String, String)]) throws {
        try atomicWrite(Data(files.map { "\($0.1)  \($0.0)" }.joined(separator: "\n").utf8), to: url)
    }

    func personalisedKernel(root: String) throws -> Data {
        guard let release else { throw EngineError(.internalError, "no release") }
        let t = try backend.topology()
        guard let p = t.partition(uuid: root) else { throw EngineError(.inconsistent, "root partition missing") }
        var s = String(decoding: try Data(contentsOf: work(release.kernel)), as: UTF8.self)
        s = s.replacingOccurrences(of: "@SF_PARTUUID@", with: root.lowercased())
            .replacingOccurrences(of: "@SF_PART_LBA@", with: String(p.offset / t.blockSize))
            .replacingOccurrences(of: "@SF_FSUUID@", with: "<root filesystem UUID from the release>")
        return Data(s.utf8)
    }

    func installJSON(plan: EnginePlan, gate: Gate) throws -> Data {
        struct Install: Codable { var installID: String; var version: String; var job: String; var partitions: [String: String]; var plan: String }
        return try Canonical.data(Install(installID: plan.request?.installID ?? "", version: plan.releaseVersion, job: journal.jobID.uuidString,
                                          partitions: gate.created, plan: plan.digest))
    }

    func bootObject(gate: Gate) throws -> Data {
        guard let release, let boot = gate.created["boot"] else { throw EngineError(.inconsistent, "no SFBOOT") }
        var d = try Data(contentsOf: work(release.stage1))
        d.append(Data("\nchosen.asahi,efi-system-partition=\(boot.lowercased())\nchainload=\(boot.lowercased());sf/boot.bin\n".utf8))
        return d
    }

    func firmwareSlot() throws -> Data {
        guard let release else { throw EngineError(.internalError, "no release") }
        let fw = try Data(contentsOf: work(release.firmware))
        var d = Data("SFFWSLOT1\nsha256=\(SHA256Hasher.hex(fw))\nbytes=\(fw.count)\n".utf8)
        d.append(Data(count: 4096 - d.count))
        d.append(fw)
        return d
    }

    func receiptHeader(_ plan: EnginePlan) -> Data {
        var d = Data("SFRCPT1\ninstall=\(plan.request?.installID ?? "")\n".utf8)
        d.append(Data(count: 4096 - d.count))
        return d
    }

    func stageRecovery(vol: URL, plan: EnginePlan, gate: Gate) throws {
        let app = vol.appendingPathComponent("SiliconForest Setup.app/Contents")
        let payload = RecoveryPayload.files()
        for (rel, data, exec) in payload {
            try atomicWrite(data, to: app.appendingPathComponent(rel))
            if exec { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: app.appendingPathComponent(rel).path) }
        }
        let bin = app.appendingPathComponent("MacOS/SFRecovery")
        if let recoveryBinary, FileManager.default.fileExists(atPath: recoveryBinary.path) {
            try copy(recoveryBinary, to: bin)
        } else {
            try atomicWrite(Data("SFRecovery placeholder: built by scripts/make-app.sh\n".utf8), to: bin)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
        try copy(vol.appendingPathComponent(".sf/boot.bin"), to: app.appendingPathComponent("Resources/boot.bin"))
        struct RecoveryPlan: Codable { var job: String; var installID: String; var stub: String; var boot: String; var root: String; var planDigest: String }
        let rp = RecoveryPlan(job: journal.jobID.uuidString, installID: plan.request?.installID ?? "", stub: gate.created["stub"] ?? "",
                              boot: gate.created["boot"] ?? "", root: gate.created["root"] ?? "", planDigest: plan.digest)
        try atomicWrite(try Canonical.data(rp), to: vol.appendingPathComponent("SFInstall/plan.json"))
        try FileManager.default.ensureDirectory(vol.appendingPathComponent("SFInstall/state"))
    }

    func hide(vol: URL) throws {
        breadcrumb = "hiding SystemVersion.plist on \(vol.path)"
        let core = vol.appendingPathComponent("System/Library/CoreServices")
        let plist = core.appendingPathComponent("SystemVersion.plist"), hidden = core.appendingPathComponent("SystemVersion.plist.sf-hidden")
        if FileManager.default.fileExists(atPath: plist.path) {
            if FileManager.default.fileExists(atPath: hidden.path) { try FileManager.default.removeItem(at: hidden) }
            try FileManager.default.moveItem(at: plist, to: hidden)
        }
        let marker = """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict><key>AppName</key><string>SiliconForest Setup.app</string></dict></plist>

            """
        try atomicWrite(Data(marker.utf8), to: vol.appendingPathComponent(".IAPhysicalMedia"))
    }

    func unhide(stub: String) throws {
        let vol = try backend.volumeURL(store: stub, role: "System")
        let core = vol.appendingPathComponent("System/Library/CoreServices")
        let plist = core.appendingPathComponent("SystemVersion.plist"), hidden = core.appendingPathComponent("SystemVersion.plist.sf-hidden")
        if FileManager.default.fileExists(atPath: hidden.path) && !FileManager.default.fileExists(atPath: plist.path) {
            try FileManager.default.moveItem(at: hidden, to: plist)
        }
        try? FileManager.default.removeItem(at: vol.appendingPathComponent(".IAPhysicalMedia"))
    }
}

/// Builds an install proof from a finished install journal: only what its evidence names.
public enum InstallProofReader {
    public static func proof(from journal: ChainJournal) throws -> InstallProof {
        let st = JobState(journal.records)
        guard let plan = st.plan, plan.operation == .install, let original = st.original else { throw PlanRefusal(reason: "not an install journal") }
        guard st.end == .handedOff || st.end == .committed else { throw PlanRefusal(reason: "the install didn't finish (\(st.end?.rawValue ?? "unfinished"))") }
        guard let stub = st.created["stub"], let boot = st.created["boot"], let root = st.created["root"] else {
            throw PlanRefusal(reason: "the journal doesn't name all three partitions")
        }
        return InstallProof(job: journal.jobID, installID: plan.request?.installID ?? "", releaseVersion: plan.releaseVersion,
                            macOSStore: plan.macOS.store, macOSOriginalSize: plan.macOS.from, originalLayoutDigest: original.layoutDigest,
                            owned: .init(stub: stub, boot: boot, root: root))
    }
}
