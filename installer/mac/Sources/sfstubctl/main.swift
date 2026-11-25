// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// sfstubctl: drives SFStub against disk images only (CHL-41 M1). Every diskutil command names devices
// that ImageGuard has just proved (hdiutil info first, then diskutil) to be attached from a disk image
// under the images directory. It never touches a real disk, and runs no bless, bputil, kmutil or nvram.
//
//   sfstubctl inventory  --profile P [--ipsw URL|PATH]
//   sfstubctl stage      --profile P --work DIR [--ipsw URL|PATH]
//   sfstubctl make-image --path IMG.sparseimage --label NAME --bytes N     (creates + attaches; prints JSON)
//   sfstubctl build      --profile P --work DIR --store diskNsM --label NAME --admin-users F
//                        --icon F --app DIR --app-name NAME [--script-path P --script F --token K=vgid|preboot|literal:V ...]
//                        --physical-media F [--boot-object-path P --stage1 F --var V ...] [--ops F] [--ipsw URL|PATH]
//                        [--images-root DIR]
//   sfstubctl detach     --path IMG.sparseimage
//
// The SiliconForest payload (instead of --app/--script/--physical-media/--stage1/--var, which are the Asahi
// reference payload, used by the differential test's baseline):
//   --sf-launcher F --sf-step2 F --sf-recovery F --sf-stage1 F --sf-boot-partuuid U --sf-plan F --icon F
//   [--sf-install-json F] [--sf-stage1-sha256 H] [--sf-resource NAME=FILE ...] [--payload-manifest OUT.json]
//   sfstubctl payload    --profile P --work DIR  (the same --sf-* options; assembles and prints the manifest, no disk)

import Foundation
import SFEngine
import SFStub

setvbuf(stdout, nil, _IOLBF, 0)
umask(0o022)   // what launchd gives the helper, and what upstream ran under

struct Args {
    var cmd: String
    var single: [String: String] = [:]
    var multi: [String: [String]] = [:]
    init(_ argv: [String]) throws {
        guard argv.count >= 2 else { throw StubError("usage: sfstubctl <inventory|stage|make-image|build|payload|detach> ...") }
        cmd = argv[1]
        var i = 2
        while i < argv.count {
            let k = argv[i]
            guard k.hasPrefix("--"), i + 1 < argv.count else { throw StubError("bad argument \(k)") }
            let key = String(k.dropFirst(2))
            single[key] = argv[i + 1]
            multi[key, default: []].append(argv[i + 1])
            i += 2
        }
    }
    func req(_ k: String) throws -> String { guard let v = single[k] else { throw StubError("missing --\(k)") }; return v }
}

func openImage(_ a: Args, _ profile: StubProfile) throws -> ZipReader {
    let src = a.single["ipsw"] ?? profile.restore_image.url
    let base: RangeSource = src.hasPrefix("https://")
        ? try HTTPRangeSource(url: URL(string: src)!, expectedSize: profile.restore_image.bytes)
        : try FileRangeSource(path: src)
    return try ZipReader(BlockCache(base))
}

func json(_ o: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .prettyPrinted]), as: UTF8.self)
}

/// The SiliconForest payload from the --sf-* options.
func sfPayload(_ a: Args, work: URL) throws -> SFPayload.Assembled {
    func url(_ k: String) throws -> URL { URL(fileURLWithPath: try a.req(k)) }
    var sha = a.single["sf-stage1-sha256"]
    if let ij = a.single["sf-install-json"] {
        let facts = try SFPayload.checkRelease(installJSON: Data(contentsOf: URL(fileURLWithPath: ij)))
        if let s = sha, s != facts.stage1SHA256 { throw StubError("--sf-stage1-sha256 is not install.json's") }
        sha = facts.stage1SHA256
    }
    var res: [(String, URL)] = []
    for r in a.multi["sf-resource"] ?? [] {
        let kv = r.split(separator: "=", maxSplits: 1).map(String.init)
        guard kv.count == 2 else { throw StubError("bad --sf-resource \(r)") }
        res.append((kv[0], URL(fileURLWithPath: kv[1])))
    }
    let inputs = SFPayload.Inputs(profile: try url("profile"), launcher: try url("sf-launcher"), step2: try url("sf-step2"),
                                  recoveryBinary: try url("sf-recovery"), stage1: try url("sf-stage1"), stage1SHA256: sha,
                                  bootPartUUID: try a.req("sf-boot-partuuid"), planJSON: try Data(contentsOf: try url("sf-plan")),
                                  volumeIcon: try url("icon"), resources: res)
    let built = try SFPayload.assemble(inputs, into: work.appendingPathComponent("sf-payload"))
    if let out = a.single["payload-manifest"] {
        let m = built.manifest.map { ["path": $0.path, "type": $0.type, "mode": $0.mode, "size": $0.size, "sha256": $0.sha256] as [String: Any] }
        try json(["variables": built.variables, "entries": m]).write(toFile: out, atomically: true, encoding: .utf8)
    }
    return built
}

/// diskutil through ImageGuard, recording each command with devices replaced by names the caller gives.
final class GuardedDiskutil {
    let guardian: ImageGuard
    let runner = ProcessToolRunner()
    var ops: [String] = []
    var names: [String: String] = [:]
    init(root: URL) { guardian = ImageGuard(allowedRoot: root) }

    static let verbs: Set<String> = ["mount", "rename"]
    static let apfsVerbs: Set<String> = ["addVolume", "changeVolumeRole", "resizeContainer"]

    func run(_ args: [String]) throws -> ToolResult {
        guard let v = args.first, Self.verbs.contains(v) || (v == "apfs" && args.count > 1 && Self.apfsVerbs.contains(args[1])) else {
            throw StubError("not an allowed stub disk command: \(args)")
        }
        let devs = args.filter { $0.range(of: #"^(/dev/)?r?disk[0-9]+(s[0-9]+)?$"#, options: .regularExpression) != nil }
        guard !devs.isEmpty else { throw StubError("a disk command must name its device") }
        let proofs = try devs.map { try guardian.authorize($0) }
        guard Set(proofs.map(\.imageWholeDisk)).count == 1 else { throw StubError("one command may touch only one image") }
        let r = try runner.run(["/usr/sbin/diskutil"] + args)
        ops.append((["diskutil"] + args.map { names[$0].map { "<\($0)>" } ?? $0 }).joined(separator: " "))
        return r
    }

    func query(_ args: [String]) throws -> [String: Any] {
        try Query.dict(guardian.query, ["/usr/sbin/diskutil"] + args)
    }
}

func containerInfo(_ d: GuardedDiskutil, store: String) throws -> [String: Any] {
    let info = try d.query(["info", "-plist", store])
    guard let ref = info["APFSContainerReference"] as? String else { throw StubError("\(store) is not an APFS physical store") }
    _ = try d.guardian.authorize(ref)
    let list = try d.query(["apfs", "list", "-plist", ref])
    guard let c = (list["Containers"] as? [[String: Any]])?.first else { throw StubError("no container for \(ref)") }
    return c
}

func volumes(_ c: [String: Any]) -> [[String: Any]] { c["Volumes"] as? [[String: Any]] ?? [] }
func roles(_ v: [String: Any]) -> [String] { v["Roles"] as? [String] ?? [] }

/// Port of upstream stub.py StubInstaller.prepare_volume (Asahi v0.9.2, MIT), first-install path, with the
/// "Multiple volumes" check fixed (upstream compared string keys against tuple keys, so it never fired) and the
/// " - Data" suffix removed as a suffix (upstream's rstrip removed characters).
func prepareVolumes(_ d: GuardedDiskutil, store: String, label: String) throws -> (ref: String, target: [StubVolume: String], vgid: String, preboot: String) {
    var c = try containerInfo(d, store: store)
    let ref = c["ContainerReference"] as! String
    d.names[ref] = "CONTAINER"
    var byRole: [[String]: [[String: Any]]] = [:]
    for v in volumes(c) { byRole[roles(v), default: []].append(v) }
    for r in ["Preboot", "Recovery", "Data", "System"] where (byRole[[r]]?.count ?? 0) > 1 { throw StubError("Multiple \(r) volumes") }
    var name = label
    if byRole[["Data"]] == nil {
        if let def = byRole[[]]?.first, let dev = def["DeviceIdentifier"] as? String {
            d.names[dev] = "DATA"
            _ = try checked(d.run(["apfs", "changeVolumeRole", dev, "D"]))
            _ = try checked(d.run(["rename", dev, label + " - Data"]))
        } else {
            _ = try checked(d.run(["apfs", "addVolume", ref, "apfs", label, "-role", "D"]))
        }
        c = try containerInfo(d, store: store)
    } else if name.hasSuffix(" - Data") { name = String(name.dropLast(7)) }
    guard let data = volumes(c).first(where: { roles($0) == ["Data"] })?["DeviceIdentifier"] as? String else { throw StubError("Could not find Data volume") }
    d.names[data] = "DATA"
    if !volumes(c).contains(where: { roles($0) == ["System"] }) { try addVolume(d, ["apfs", "addVolume", ref, "apfs", name, "-role", "S", "-groupWith", data]) }
    if !volumes(c).contains(where: { roles($0) == ["Preboot"] }) { try addVolume(d, ["apfs", "addVolume", ref, "apfs", "Preboot", "-role", "B"]) }
    if !volumes(c).contains(where: { roles($0) == ["Recovery"] }) { try addVolume(d, ["apfs", "addVolume", ref, "apfs", "Recovery", "-role", "R"]) }
    c = try containerInfo(d, store: store)

    // check_volume / collect_part: exactly one Preboot, one Recovery, one volume group with one System and one Data.
    var devs: [StubVolume: String] = [:]
    for (r, sv) in [("Preboot", StubVolume.preboot), ("Recovery", .recovery), ("System", .system), ("Data", .data)] {
        let vs = volumes(c).filter { roles($0) == [r] }
        guard vs.count == 1, let dev = vs[0]["DeviceIdentifier"] as? String else { throw StubError("Container is not ready for OS install (\(r))") }
        devs[sv] = dev
        d.names[dev] = r.uppercased()
    }
    // upstream (osenum.collect_part) takes the VGID from `diskutil apfs listVolumeGroups`: the group with one Data and one System.
    _ = try d.guardian.authorize(ref)
    let vgr = try d.runner.run(["/usr/sbin/diskutil", "apfs", "listVolumeGroups", ref, "-plist"])
    guard vgr.ok, let vgpl = try PropertyListSerialization.propertyList(from: vgr.stdout, format: nil) as? [String: Any],
          let groups = ((vgpl["Containers"] as? [[String: Any]])?.first?["VolumeGroups"]) as? [[String: Any]] else { throw StubError("listVolumeGroups failed") }
    let matching = groups.filter { g in
        let vs = g["Volumes"] as? [[String: Any]] ?? []
        return vs.filter { $0["Role"] as? String == "Data" }.map { $0["DeviceIdentifier"] as? String } == [devs[.data]]
            && vs.filter { $0["Role"] as? String == "System" }.map { $0["DeviceIdentifier"] as? String } == [devs[.system]]
    }
    guard matching.count == 1, let vgid = matching[0]["APFSVolumeGroupUUID"] as? String else { throw StubError("System and Data are not one volume group") }
    let preboot = volumes(c).first { roles($0) == ["Preboot"] }!["APFSVolumeUUID"] as! String
    return (ref, devs, vgid, preboot)
}

func addVolume(_ d: GuardedDiskutil, _ args: [String]) throws {
    let r = try d.run(args)
    // upstream squelches a spurious failure whose output says it was mounting
    if !r.ok && !(r.out + r.err).contains("Mounting APFS Volume") { throw StubError("diskutil \(args.joined(separator: " ")): \(r.err)\(r.out)") }
}

func checked(_ r: ToolResult) throws -> ToolResult {
    guard r.ok else { throw StubError("diskutil failed: \(r.err)\(r.out)") }
    return r
}

/// upstream DiskUtil.mount: `diskutil mount`, then the MountPoint from info.
func mount(_ d: GuardedDiskutil, _ dev: String) throws -> URL {
    _ = try checked(d.run(["mount", dev]))
    let info = try d.query(["info", "-plist", dev])
    guard let mp = info["MountPoint"] as? String, mp.hasPrefix("/Volumes/") else { throw StubError("\(dev) did not mount under /Volumes") }
    return URL(fileURLWithPath: mp)
}

func run() throws {
    let a = try Args(CommandLine.arguments)
    let imagesRoot = URL(fileURLWithPath: a.single["images-root"] ?? ImageGuard.defaultRoot.path)
    switch a.cmd {
    case "inventory", "stage":
        let profile = try StubProfile.load(profile: URL(fileURLWithPath: try a.req("profile")))
        let zip = try openImage(a, profile)
        let image = try RestoreImage(zip: zip, profile: profile)
        let dummy = URL(fileURLWithPath: "/nonexistent")
        let payload = StubPayload(volumeIcon: dummy, appSource: dummy, appName: "App.app", script: nil, physicalMedia: dummy, bootObject: nil)
        let plan = try StubPlanner.plan(image: image, target: "VGID", payload: payload, adminUsers: dummy)
        let members = try StubPlanner.members(of: plan, in: zip)
        let bytes = members.reduce(UInt64(0)) { $0 + $1.size }
        let compressed = members.reduce(UInt64(0)) { $0 + $1.compressedSize }
        print("identity: \(image.identity["Info"]?["BuildNumber"]?.string ?? "?") \(profile.identity.device_class) \(profile.identity.variant)")
        print("plan: \(plan.count) actions, \(members.count) members, \(bytes) bytes (\(compressed) compressed)")
        if a.cmd == "inventory" {
            for m in members { print("  \(m.name)\t\(m.size)\t\(String(format: "%08x", m.crc32))") }
        } else {
            let work = URL(fileURLWithPath: try a.req("work"))
            var last = Date.distantPast
            try StubStager(zip: zip, work: work).stage(members) { name, done, total in
                if Date().timeIntervalSince(last) > 5 || done == total { last = Date(); print("  \(name) \(done)/\(total)") }
            }
            print("staged; fetched \(zip.source.bytesFetched) bytes of \(zip.source.size)")
        }
    case "make-image":
        let path = try a.req("path"), label = try a.req("label")
        guard let bytes = UInt64(try a.req("bytes")) else { throw StubError("bad --bytes") }
        let d = GuardedDiskutil(root: imagesRoot)
        guard d.guardian.isUnderAllowedRoot(path) || !FileManager.default.fileExists(atPath: path) else { throw StubError("\(path) is outside \(imagesRoot.path)") }
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        let size = (bytes + (512 << 20)) / (1 << 20)   // GPTSPUD with APFS also makes a 200 MB EFI partition
        let cr = try ProcessToolRunner().run(["/usr/bin/hdiutil", "create", "-size", "\(size)m", "-type", "SPARSE", "-layout", "GPTSPUD",
                                              "-fs", "APFS", "-volname", label, path])
        guard cr.ok else { throw StubError("hdiutil create: \(cr.err)") }
        guard d.guardian.isUnderAllowedRoot(path) else { throw StubError("\(path) is outside \(imagesRoot.path)") }
        // Mounted, as upstream's container is after `diskutil addPartition` (diskutil rename needs it mounted).
        let at = try ProcessToolRunner().run(["/usr/bin/hdiutil", "attach", "-nobrowse", "-noverify", "-noautofsck", "-plist", path])
        guard at.ok else { throw StubError("hdiutil attach: \(at.err)") }
        let pl = try PropertyListSerialization.propertyList(from: at.stdout, format: nil) as? [String: Any] ?? [:]
        let ents = pl["system-entities"] as? [[String: Any]] ?? []
        guard let store = ents.first(where: { ($0["unmapped-content-hint"] as? String ?? $0["content-hint"] as? String) == "7C3457EF-0000-11AA-AA11-00306543ECAC" })?["dev-entry"] as? String else {
            throw StubError("no APFS partition in the new image")
        }
        let s = String(store.dropFirst(5))
        _ = try d.guardian.authorize(s)
        _ = try checked(d.run(["apfs", "resizeContainer", s, "\(bytes)"]))
        let info = try d.query(["info", "-plist", s])
        print(json(["store": s, "container": info["APFSContainerReference"] as? String ?? "", "bytes": info["Size"] as? Int ?? 0, "image": path]))
    case "payload":
        let work = URL(fileURLWithPath: try a.req("work"))
        let b = try sfPayload(a, work: work)
        print("payload assembled: \(b.manifest.count) entries; boot object \(b.bootObject.count) bytes; variables:")
        for v in b.variables { print("  \(v)") }
    case "detach":
        let path = try a.req("path")
        let d = GuardedDiskutil(root: imagesRoot)
        guard d.guardian.isUnderAllowedRoot(path) else { throw StubError("\(path) is outside \(imagesRoot.path)") }
        guard let img = try d.guardian.attachedImages().first(where: { ImageGuardResolve.real($0.imagePath) == ImageGuardResolve.real(path) }),
              let whole = img.partitionMapDisk else { print("not attached"); return }
        let r = try ProcessToolRunner().run(["/usr/bin/hdiutil", "detach", whole, "-force"])
        guard r.ok else { throw StubError("detach: \(r.err)") }
        print("detached \(whole)")
    case "build":
        let profile = try StubProfile.load(profile: URL(fileURLWithPath: try a.req("profile")))
        let zip = try openImage(a, profile)
        let image = try RestoreImage(zip: zip, profile: profile)
        let work = URL(fileURLWithPath: try a.req("work"))
        func url(_ k: String) throws -> URL { URL(fileURLWithPath: try a.req(k)) }
        var tokens: [String: StubToken] = [:]
        for t in a.multi["token"] ?? [] {
            let kv = t.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { throw StubError("bad --token \(t)") }
            tokens[kv[0]] = kv[1] == "vgid" ? .vgid : kv[1] == "preboot" ? .prebootVolumeUUID
                : kv[1].hasPrefix("literal:") ? .literal(String(kv[1].dropFirst(8))) : nil
            guard tokens[kv[0]] != nil else { throw StubError("bad --token \(t)") }
        }
        let payload: StubPayload
        if a.single["sf-launcher"] != nil {
            payload = try sfPayload(a, work: work).payload
        } else {
            payload = StubPayload(
                volumeIcon: try url("icon"), appSource: try url("app"), appName: try a.req("app-name"),
                script: a.single["script"] != nil ? (try a.req("script-path"), try url("script"), tokens) : nil,
                physicalMedia: try url("physical-media"),
                bootObject: a.single["stage1"] != nil ? (try a.req("boot-object-path"), try url("stage1"), a.multi["var"] ?? []) : nil)
        }

        // 1. Plan with a placeholder VGID to learn the members, and stage them all (no disk writes yet).
        let pre = try StubPlanner.plan(image: image, target: "VGID", payload: payload, adminUsers: try url("admin-users"))
        let members = try StubPlanner.members(of: pre, in: zip)
        print("staging \(members.count) members")
        let staged = try StubStager(zip: zip, work: work).stage(members)
        print("staged; fetched \(zip.source.bytesFetched) bytes of \(zip.source.size)")

        // 2. Volumes (first disk writes), through ImageGuard.
        let d = GuardedDiskutil(root: imagesRoot)
        let store = try a.req("store")
        _ = try d.guardian.authorize(store)
        let prep = try prepareVolumes(d, store: store, label: try a.req("label"))
        var roots: [StubVolume: URL] = [:]
        for v in [StubVolume.preboot, .recovery, .system, .data] { roots[v] = try mount(d, prep.target[v]!) }
        let target = StubTarget(roots: roots, vgid: prep.vgid, prebootVolumeUUID: prep.preboot)

        // 3. Content.
        let plan = try StubPlanner.plan(image: image, target: prep.vgid, payload: payload, adminUsers: try url("admin-users"))
        var writer = StubWriter(target: target, staged: staged)
        var actions: [String] = []
        writer.log = { actions.append($0); print("  \($0)") }
        writer.effect = { d.ops.append($0) }
        try writer.run(plan)
        if payload.bootObject != nil { d.ops.append("m1n1.build") }
        let out: [String: Any] = ["vgid": prep.vgid, "preboot_uuid": prep.preboot,
                                  "roots": Dictionary(uniqueKeysWithValues: roots.map { ($0.key.rawValue, $0.value.path) }),
                                  "devices": Dictionary(uniqueKeysWithValues: prep.target.map { ($0.key.rawValue, $0.value) })]
        if let ops = a.single["ops"] {
            try (d.ops.joined(separator: "\n") + "\n").write(toFile: ops, atomically: true, encoding: .utf8)
            try (actions.joined(separator: "\n") + "\n").write(toFile: ops + ".actions", atomically: true, encoding: .utf8)
        }
        if let o = a.single["out"] { try json(out).write(toFile: o, atomically: true, encoding: .utf8) }
        print(json(out))
    default:
        throw StubError("unknown command \(a.cmd)")
    }
}

enum ImageGuardResolve {
    static func real(_ p: String) -> String {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(p, &buf) != nil else { return p }
        return String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

do { try run() } catch {
    FileHandle.standardError.write(Data("sfstubctl: \(error)\n".utf8))
    exit(1)
}
