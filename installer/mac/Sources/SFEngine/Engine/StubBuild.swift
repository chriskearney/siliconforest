// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// The engine builds the stub with SFStub (DESIGN 6.4, ENGINE 10): S10 stages the restore-image members, S32 makes
// the volumes as upstream prepare_volume does (Steps.swift), S35 runs StubPlanner/StubWriter with the
// SiliconForest app, S55 writes the boot object into the app, S60 writes SFInstall/. Each step's idempotent check
// reads the stub back against the same plan (StubVerifier), so a resumed job finds out what is done from the disk.

import Foundation
import SFInstallKit
import SFStub

/// Where the stub's Apple parts and the few local inputs come from. Nil on the engine: the older rehearsal path
/// (`release.stubFiles` copied as files), which the image sweeps written before SFStub still use.
public struct StubSource: Sendable {
    /// The profile's `stub` section (identity, version, build, restore-image URL and size).
    public var profile: StubProfile
    /// The restore image: the profile's `https://` URL, or a local copy (tests, the M5's cached image).
    public var restoreImage: String
    /// macOS's `AdminUserRecoveryInfo.plist` (upstream copy_admin_users); a stand-in on images.
    public var adminUsers: URL
    /// `.VolumeIcon.icns`.
    public var volumeIcon: URL
    /// Extra app resources (name, file).
    public var resources: [(String, URL)]
    /// Set the schg and APFS bootable flags (needs root: the helper). Off on images without root: each is journaled
    /// as simulated instead, with the command it stands for.
    public var rootOnly: Bool

    public init(profile: StubProfile, restoreImage: String? = nil, adminUsers: URL, volumeIcon: URL, resources: [(String, URL)] = [], rootOnly: Bool) {
        self.profile = profile; self.restoreImage = restoreImage ?? profile.restore_image.url; self.adminUsers = adminUsers
        self.volumeIcon = volumeIcon; self.resources = resources; self.rootOnly = rootOnly
    }
}

extension InstallEngine {
    struct StubContext {
        var zip: ZipReader
        var image: RestoreImage
        var staged: [String: URL]
    }

    var stubWork: URL { work("stub") }

    func openRestoreImage(_ src: StubSource) throws -> (ZipReader, RestoreImage) {
        let zip = try RestoreImageSource.open(src.restoreImage, expectedSize: src.restoreImage.hasPrefix("https://") ? src.profile.restore_image.bytes : nil)
        return (zip, try RestoreImage(zip: zip, profile: src.profile))
    }

    /// The app tree and payload for S35 (rebuilt in the work directory each time: it is small and ours).
    func stubAppPayload(_ src: StubSource) throws -> StubPayload {
        let srcDir = stubWork.appendingPathComponent("app-src", isDirectory: true)
        try FileManager.default.ensureDirectory(srcDir)
        var urls: [String: URL] = [:]
        for (rel, data, _) in RecoveryPayload.files() where rel != "Info.plist" {
            let u = srcDir.appendingPathComponent((rel as NSString).lastPathComponent)
            try data.write(to: u)
            urls[rel] = u
        }
        var rec = srcDir.appendingPathComponent("SFRecovery")
        if let recoveryBinary, FileManager.default.fileExists(atPath: recoveryBinary.path) { rec = recoveryBinary }
        else { try Data("SFRecovery placeholder: built by scripts/make-app.sh\n".utf8).write(to: rec) }
        let tree = try SFPayload.assembleApp(launcher: urls["MacOS/sf-launcher"]!, step2: urls["Resources/sf-step2.sh"]!, recoveryBinary: rec,
                                             resources: src.resources, into: stubWork.appendingPathComponent("app", isDirectory: true))
        return SFPayload.appPayload(tree, volumeIcon: src.volumeIcon)
    }

    func stubPlan(_ src: StubSource, image: RestoreImage, vgid: String) throws -> [StubAction] {
        try StubPlanner.plan(image: image, target: vgid, payload: try stubAppPayload(src), adminUsers: src.adminUsers)
    }

    /// S10: every member the stub needs, downloaded and CRC-checked before the first disk write (DESIGN D6).
    func stageStubMembers(_ src: StubSource) throws -> StubContext {
        let (zip, image) = try openRestoreImage(src)
        let members = try StubPlanner.members(of: try stubPlan(src, image: image, vgid: "VGID"), in: zip)
        var last = Date.distantPast
        let staged = try StubStager(zip: zip, work: stubWork).stage(members) { name, done, total in
            if Date().timeIntervalSince(last) > 1 || done == total { last = Date(); self.onEvent?(.progress(.S10, "\(name) \(done)/\(total)")) }
        }
        return StubContext(zip: zip, image: image, staged: staged)
    }

    /// The stub's mounted volumes and its group, as upstream's collect_part finds them.
    func stubTarget(stub: String) throws -> StubTarget {
        var roots: [StubVolume: URL] = [:]
        for v in StubVolume.allCases { roots[v] = try backend.volumeURL(store: stub, role: v.rawValue) }
        guard let a = try backend.topology().partition(uuid: stub)?.apfs,
              let preboot = a.volumes.first(where: { $0.roles == ["Preboot"] }) else { throw EngineError(.inconsistent, "the stub has no Preboot volume") }
        let vgid = try backend.volumeGroupID(container: stub)
        return StubTarget(roots: roots, vgid: vgid, prebootVolumeUUID: preboot.uuid)
    }

    func stubWriter(_ src: StubSource, target: StubTarget, staged: [String: URL], code: StepCode) -> StubWriter {
        var w = StubWriter(target: target, staged: staged)
        w.replaceExisting = true
        if !src.rootOnly {
            let j = journal, c = code.rawValue
            w.bootable = { r in _ = try j.append(.note, step: c, args: ["command": .a([.s("fsctl"), .s("APFSIOC_VOL_BOOTABLE"), .s(r.lastPathComponent), .s("1")])],
                                                 note: "simulated: needs root") }
            w.systemFlags = { path, flags in _ = try j.append(.note, step: c, args: ["command": .a([.s("chflags"), .s(String(flags, radix: 16)), .s((path as NSString).lastPathComponent)])],
                                                             note: "simulated: needs root") }
        }
        return w
    }

    // MARK: S35

    func performStubContent(_ src: StubSource, stub: String) throws -> JArgs {
        let ctx = try stageStubMembers(src)   // already staged at S10: only checks the records
        let target = try stubTarget(stub: stub)
        let plan = try stubPlan(src, image: ctx.image, vgid: target.vgid)
        try journal.append(.intent, step: StepCode.S35.rawValue, args: ["actions": .i(Int64(plan.count)), "vgid": .s(target.vgid)])
        var w = stubWriter(src, target: target, staged: ctx.staged, code: .S35)
        let total = plan.count
        w.afterAction = { i, a in
            self.onEvent?(.progress(.S35, "\(i)/\(total) \(a.description)"))
            try self.faultPoint(.S35, "action-\(i)")
        }
        breadcrumb = "writing the stub's content"
        try w.run(plan)
        breadcrumb = nil
        return ["actions": .i(Int64(total)), "vgid": .s(target.vgid)]
    }

    func checkStubContent(_ src: StubSource, stub: String) throws -> CheckResult {
        guard let target = try? stubTarget(stub: stub) else { return .notDone }
        let ctx = try stageStubMembers(src)
        let plan = try stubPlan(src, image: ctx.image, vgid: target.vgid)
        let bad = StubVerifier.unmet(plan, target: target, staged: ctx.staged, rootOnly: src.rootOnly)
        return bad.isEmpty ? .done(["actions": .i(Int64(plan.count)), "vgid": .s(target.vgid)]) : .notDone
    }

    // MARK: S55, S60 (the parts that need SFBOOT's PARTUUID)

    static let appBootObjectPath = StubPath(.system, SFPayload.appName + "/" + SFPayload.bootObjectPath)

    /// The PARTUUID stage 1 chainloads: SFBOOT's, or in a stub-only run one that is on no disk.
    func stage2PartUUID(plan: EnginePlan, gate: Gate) throws -> String {
        if let boot = gate.created["boot"] { return boot }
        if plan.isStubOnly { return plan.absentBootPartUUID }
        throw EngineError(.inconsistent, "no SFBOOT")
    }

    func stubBootAction(plan: EnginePlan, gate: Gate) throws -> StubAction {
        guard let release else { throw EngineError(.internalError, "no release") }
        return .bootObject(work(release.stage1), Self.bootVariables(bootPartUUID: try stage2PartUUID(plan: plan, gate: gate)), Self.appBootObjectPath)
    }

    func stubInstallActions(plan: EnginePlan, gate: Gate) throws -> [StubAction] {
        try SFPayload.installActions(planJSON: try recoveryPlanJSON(plan: plan, gate: gate), bootPartUUID: try stage2PartUUID(plan: plan, gate: gate))
    }

    /// Writes S55's or S60's actions onto the stub's System volume.
    func performStubTail(_ src: StubSource, stub: String, actions: [StubAction], code: StepCode) throws {
        let target = try stubTarget(stub: stub)
        try stubWriter(src, target: target, staged: [:], code: code).run(actions)
    }

    func checkStubTail(_ src: StubSource, stub: String, actions: [StubAction]) -> CheckResult {
        guard let target = try? stubTarget(stub: stub) else { return .notDone }
        return StubVerifier.unmet(actions, target: target, staged: [:], rootOnly: src.rootOnly).isEmpty ? .done(["actions": .i(Int64(actions.count))]) : .notDone
    }
}

extension EngineBackend {
    /// The group of the stub's System and Data volumes (upstream osenum.collect_part, `diskutil apfs listVolumeGroups`).
    public func volumeGroupID(container storeUUID: String) throws -> String {
        guard let a = try topology().partition(uuid: storeUUID)?.apfs else { throw EngineError(.inconsistent, "no APFS container on \(storeUUID)") }
        let sys = a.volumes.filter { $0.roles == ["System"] }.map(\.identifier), data = a.volumes.filter { $0.roles == ["Data"] }.map(\.identifier)
        let r = try query.run(["/usr/sbin/diskutil", "apfs", "listVolumeGroups", a.reference, "-plist"], stdin: nil)
        guard r.ok, let pl = try PropertyListSerialization.propertyList(from: r.stdout, format: nil) as? [String: Any],
              let groups = ((pl["Containers"] as? [[String: Any]])?.first?["VolumeGroups"]) as? [[String: Any]] else {
            throw EngineError(.appleTool, "diskutil apfs listVolumeGroups failed", detail: r.err)
        }
        let matching = groups.filter { g in
            let vs = g["Volumes"] as? [[String: Any]] ?? []
            return vs.filter { $0["Role"] as? String == "Data" }.compactMap { $0["DeviceIdentifier"] as? String } == data
                && vs.filter { $0["Role"] as? String == "System" }.compactMap { $0["DeviceIdentifier"] as? String } == sys
        }
        guard sys.count == 1, data.count == 1, matching.count == 1, let id = matching[0]["APFSVolumeGroupUUID"] as? String else {
            throw EngineError(.inconsistent, "the stub's System and Data volumes are not one volume group")
        }
        return id
    }
}
