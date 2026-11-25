// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// The SiliconForest payload in the stub: SFPayload (DESIGN 7.1, PAYLOAD 9). Synthetic restore image, plain
// directories, no Apple bits, no disk. The real-image comparison against Asahi's baseline, with exactly the
// payload delta expected, is scripts/stub-differential.sh (SF_PAYLOAD) on the M5.

import Foundation
import SFEngine
import SFStub
import Testing

private let macDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let repoDir = macDir.deletingLastPathComponent().deletingLastPathComponent()
private let profileJ313 = repoDir.appendingPathComponent("installer/profiles/J313.json")
private let bootUUID = "5f8a2c10-1b2c-4d3e-8f40-0123456789ab"

private func planJSON(boot: String = bootUUID) -> Data {
    try! JSONSerialization.data(withJSONObject: ["job": "J", "installID": "I", "stub": "disk9", "boot": boot, "root": "R", "planDigest": "D"], options: [.sortedKeys])
}

private func sfInputs(_ dir: URL, profile: URL = profileJ313, plan: Data? = nil, uuid: String = bootUUID, sha: String?? = nil) throws -> SFPayload.Inputs {
    let fm = FileManager.default
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let rec = dir.appendingPathComponent("SFRecovery"); try bytes("sfrecovery", 5000).write(to: rec)
    let s1 = dir.appendingPathComponent("sf-stage1.bin"); let s1d = bytes("stage1", 8192); try s1d.write(to: s1)
    let icon = dir.appendingPathComponent("icon.icns"); try bytes("icon", 700).write(to: icon)
    let art = dir.appendingPathComponent("grove.png"); try bytes("grove", 300).write(to: art)
    return SFPayload.Inputs(profile: profile, launcher: macDir.appendingPathComponent("Recovery/sf-launcher"),
                            step2: macDir.appendingPathComponent("Recovery/sf-step2.sh"), recoveryBinary: rec, stage1: s1,
                            stage1SHA256: sha ?? SHA256Hex.hex(s1d), bootPartUUID: uuid, planJSON: plan ?? planJSON(boot: uuid),
                            volumeIcon: icon, resources: [("grove.png", art)])
}

@Suite("SFStub: the SiliconForest payload (synthetic image, no Apple bits)")
struct SFPayloadTests {

    @Test func variablesComeFromTheProfileAndPointAtSFBOOT() throws {
        for p in ["J313", "J293"] {
            let url = repoDir.appendingPathComponent("installer/profiles/\(p).json")
            let v = try SFPayload.variables(profile: url, bootPartUUID: bootUUID.uppercased())
            #expect(v == ["chosen.asahi,efi-system-partition=\(bootUUID)", "chainload=\(bootUUID);sf/boot.bin"])
        }
        #expect(throws: StubError.self) { _ = try SFPayload.variables(profile: profileJ313, bootPartUUID: "not-a-uuid") }
        #expect(throws: StubError.self) { _ = try SFPayload.variables(profile: profileJ313, bootPartUUID: "") }
    }

    @Test func pinsAndFormatsAgreeWithTheRestOfTheTree() throws {
        // G2 pins (the RAM-boot collection) and stage 1's revision.
        let pins = try JSONSerialization.jsonObject(with: Data(contentsOf: repoDir.appendingPathComponent("integrations/siliconforest/m1-j313-g2/g2-pins.json"))) as! [String: Any]
        #expect(pins["kernel_sha256"] as? String == SFPayload.ramBootCollectionSHA256)
        #expect(SFPayload.ramBootCollectionSHA256.hasPrefix("ff0238cc"))
        let prof = try JSONSerialization.jsonObject(with: Data(contentsOf: profileJ313)) as! [String: Any]
        let stage1 = (prof["boot"] as! [String: Any])["stage1"] as! [String: Any]
        let rev = stage1["source_revision"] as! String
        #expect(rev == "121fcbf35d4501814b58ca5347926a4173b6a512")
        #expect((pins["window_tag"] as! String).hasPrefix(rev))             // stage 1 and the G2 window build are the same m1n1
        #expect(((prof["boot"] as! [String: Any])["stage2"] as! [String: String])["path"] == "sf/boot.bin")
        // The formats are the ones the release builder writes.
        let sfrelease = try String(contentsOf: repoDir.appendingPathComponent("installer/payload/release/sfrelease.py"), encoding: .utf8)
        let kcrelease = try String(contentsOf: repoDir.appendingPathComponent("installer/payload/release/kc_release.py"), encoding: .utf8)
        #expect(sfrelease.contains("INSTALL_FORMAT = \"\(SFPayload.installFormat)\""))
        #expect(kcrelease.contains("KC_FORMAT = \"\(SFPayload.kcFormat)\""))
        #expect(SFPayload.installFormat == "siliconforest-install/3" && SFPayload.kcFormat == "siliconforest-kc/1")
    }

    @Test func releaseChecks() throws {
        func install(_ edit: (inout [String: Any]) -> Void = { _ in }) -> Data {
            var o: [String: Any] = ["format": "siliconforest-install/3", "boot": ["stage1": "sf-stage1.bin"],
                                    "kernel_collection": ["format": "siliconforest-kc/1", "collection_sha256": String(repeating: "b3", count: 32)],
                                    "artifacts": [["name": "sf-stage1.bin", "sha256": String(repeating: "ab", count: 32)]]]
            edit(&o)
            return try! JSONSerialization.data(withJSONObject: o)
        }
        let ok = try SFPayload.checkRelease(installJSON: install())
        #expect(ok.stage1SHA256 == String(repeating: "ab", count: 32) && ok.collectionSHA256.hasPrefix("b3b3"))
        #expect(throws: StubError.self) { _ = try SFPayload.checkRelease(installJSON: install { $0["format"] = "siliconforest-install/2" }) }
        #expect(throws: StubError.self) { _ = try SFPayload.checkRelease(installJSON: install { $0["kernel_collection"] = ["format": "siliconforest-kc/2", "collection_sha256": String(repeating: "b3", count: 32)] }) }
        #expect(throws: StubError.self) { _ = try SFPayload.checkRelease(installJSON: install { $0["kernel_collection"] = ["format": "siliconforest-kc/1", "collection_sha256": SFPayload.ramBootCollectionSHA256] }) }
        #expect(throws: StubError.self) { _ = try SFPayload.checkRelease(installJSON: install { $0["boot"] = ["stage1": "other.bin"] }) }
        #expect(throws: StubError.self) { _ = try SFPayload.checkRelease(installJSON: install { $0["artifacts"] = [["name": "sf-stage1.bin", "sha256": "xyz"]] }) }
    }

    @Test func assemblyIsTheCommittedSourcesPlusTheBootObject() throws {
        let dir = tempDir("sfp-assemble")
        let inp = try sfInputs(dir)
        let b = try SFPayload.assemble(inp, into: dir.appendingPathComponent("out"))
        func entry(_ p: String) throws -> SFPayload.ManifestEntry { try #require(b.manifest.first { $0.path == p }) }
        let app = "SiliconForest Setup.app"
        // the committed launcher and Terminal fallback are what is carried, byte for byte
        #expect(try entry("\(app)/Contents/MacOS/sf-launcher").sha256 == SHA256Hex.hex(Data(contentsOf: macDir.appendingPathComponent("Recovery/sf-launcher"))))
        #expect(try entry("\(app)/Contents/Resources/sf-step2.sh").sha256 == SHA256Hex.hex(Data(contentsOf: macDir.appendingPathComponent("Recovery/sf-step2.sh"))))
        #expect(try entry("\(app)/Contents/MacOS/sf-launcher").mode == 0o755 && entry("\(app)/Contents/MacOS/SFRecovery").mode == 0o755)
        #expect(try entry("\(app)/Contents/Info.plist").mode == 0o644)
        // stage 1 + the variables, one per line, four NULs
        let s1 = try Data(contentsOf: inp.stage1)
        var want = s1
        want.append(Data("chosen.asahi,efi-system-partition=\(bootUUID)\nchainload=\(bootUUID);sf/boot.bin\n".utf8))
        want.append(Data([0, 0, 0, 0]))
        #expect(b.bootObject == want)
        #expect(try entry("\(app)/Contents/Resources/boot.bin").sha256 == SHA256Hex.hex(want))
        // not in the assembled app directory: written by the boot-object action, as m1n1.build was
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("out/\(app)/Contents/Resources/boot.bin").path))
        #expect(b.payload.appName == app && b.payload.script == nil && b.payload.bootObject?.pathInApp == "Contents/Resources/boot.bin")
        #expect(try entry(".IAPhysicalMedia").sha256 == SHA256Hex.hex(Data(SFPayload.physicalMedia.utf8)))
        #expect(b.manifest.map(\.path) == b.manifest.map(\.path).sorted())
        // no Asahi payload name anywhere
        #expect(!b.manifest.contains { $0.path.contains("Finish Installation") || $0.path.contains("step2.sh") && !$0.path.contains("sf-step2.sh") })
    }

    @Test func theEngineAndThePayloadAgreeOnTheApp() throws {
        let engine = RecoveryPayload.files()
        let info = try #require(engine.first { $0.0 == "Info.plist" })
        #expect(info.1 == Data(SFPayload.infoPlist.utf8))
        #expect(engine.contains { $0.0 == "MacOS/sf-launcher" } && engine.contains { $0.0 == "Resources/sf-step2.sh" })
        // and Info.plist names the launcher the payload carries
        let d = try PropertyListSerialization.propertyList(from: Data(SFPayload.infoPlist.utf8), format: nil) as! [String: Any]
        #expect(d["CFBundleExecutable"] as? String == "sf-launcher")
        let m = try PropertyListSerialization.propertyList(from: Data(SFPayload.physicalMedia.utf8), format: nil) as! [String: Any]
        #expect(m["AppName"] as? String == SFPayload.appName)
    }

    @Test func refusals() throws {
        let dir = tempDir("sfp-refuse")
        func out(_ n: String) -> URL { dir.appendingPathComponent("o-\(n)") }
        let good = try sfInputs(dir.appendingPathComponent("g"))
        _ = try SFPayload.assemble(good, into: out("ok"))
        #expect(throws: StubError.self) { _ = try SFPayload.assemble(try sfInputs(dir.appendingPathComponent("a"), sha: .some(String(repeating: "0", count: 64))), into: out("a")) }
        #expect(throws: StubError.self) { _ = try SFPayload.assemble(try sfInputs(dir.appendingPathComponent("b"), uuid: "zzz"), into: out("b")) }
        #expect(throws: StubError.self) { _ = try SFPayload.assemble(try sfInputs(dir.appendingPathComponent("c"), plan: planJSON(boot: "00000000-0000-4000-8000-000000000000")), into: out("c")) }
        #expect(throws: StubError.self) { _ = try SFPayload.assemble(try sfInputs(dir.appendingPathComponent("d"), plan: Data("{\"job\":\"x\"}".utf8)), into: out("d")) }
        var i = try sfInputs(dir.appendingPathComponent("e")); i.resources = [("boot.bin", i.volumeIcon)]
        #expect(throws: StubError.self) { _ = try SFPayload.assemble(i, into: out("e")) }
        var j = try sfInputs(dir.appendingPathComponent("f")); j.launcher = j.volumeIcon
        #expect(throws: StubError.self) { _ = try SFPayload.assemble(j, into: out("f")) }
        // a profile whose variables don't chainload sf/boot.bin, or have an unknown token
        let prof = try JSONSerialization.jsonObject(with: Data(contentsOf: profileJ313)) as! [String: Any]
        func profile(_ vars: [String], _ name: String) throws -> URL {
            var p = prof; var boot = p["boot"] as! [String: Any]; var s1 = boot["stage1"] as! [String: Any]
            s1["variables"] = vars; boot["stage1"] = s1; p["boot"] = boot
            let u = dir.appendingPathComponent("\(name).json"); try JSONSerialization.data(withJSONObject: p).write(to: u); return u
        }
        #expect(throws: StubError.self) { _ = try SFPayload.variables(profile: try profile(["chosen.asahi,efi-system-partition=@SF_BOOT_PARTUUID@", "chainload=@SF_BOOT_PARTUUID@;other/boot.bin"], "p1"), bootPartUUID: bootUUID) }
        #expect(throws: StubError.self) { _ = try SFPayload.variables(profile: try profile(["chosen.asahi,efi-system-partition=@SF_BOOT_PARTUUID@", "chainload=@SF_BOOT_PARTUUID@;sf/boot.bin", "x=@SF_OTHER@"], "p2"), bootPartUUID: bootUUID) }
        #expect(throws: StubError.self) { _ = try SFPayload.variables(profile: try profile(["chosen.asahi,efi-system-partition=@SF_BOOT_PARTUUID@"], "p3"), bootPartUUID: bootUUID) }
    }

    /// Writes the whole stub (synthetic image) with the SiliconForest payload into plain directories.
    func land(_ dir: URL) throws -> (inp: SFPayload.Inputs, b: SFPayload.Assembled, t: StubTarget, plan: [StubAction], effects: [String]) {
        let (data, profile) = fixtureIPSW()
        let z = try ZipReader(MemorySource(data))
        let img = try RestoreImage(zip: z, profile: profile)
        let inp = try sfInputs(dir.appendingPathComponent("in"))
        let b = try SFPayload.assemble(inp, into: dir.appendingPathComponent("payload"))
        let admin = dir.appendingPathComponent("admin.plist"); try plistXML(["u": ["GeneratedUID": "X", "RealName": "U"]]).write(to: admin)
        let vgid = "11111111-2222-3333-4444-555555555555"
        let plan = try StubPlanner.plan(image: img, target: vgid, payload: b.payload, adminUsers: admin)
        let staged = try StubStager(zip: z, work: dir.appendingPathComponent("work")).stage(try StubPlanner.members(of: plan, in: z))
        var roots: [StubVolume: URL] = [:]
        for v in StubVolume.allCases { roots[v] = dir.appendingPathComponent("vol-\(v.rawValue)"); try FileManager.default.createDirectory(at: roots[v]!, withIntermediateDirectories: true) }
        let t = StubTarget(roots: roots, vgid: vgid, prebootVolumeUUID: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        var w = StubWriter(target: t, staged: staged)
        w.requireMountPoints = false
        var effects: [String] = []
        w.bootable = { _ in }
        w.systemFlags = { _, _ in }
        w.effect = { effects.append($0) }
        try w.run(plan)
        return (inp, b, t, plan, effects)
    }

    @Test func theSiliconForestPayloadIsWhatLandsOnTheSystemVolume() throws {
        let dir = tempDir("sfp-land")
        let (_, b, t, plan, effects) = try land(dir)
        let sys = t.roots[.system]!
        // every manifest entry is on the volume with that type, mode and content
        for e in b.manifest {
            let u = sys.appendingPathComponent(e.path)
            var st = stat()
            #expect(lstat(u.path, &st) == 0, "\(e.path) missing")
            if e.type == "dir" { #expect((st.st_mode & S_IFMT) == S_IFDIR && Int(st.st_mode & 0o7777) == e.mode, "\(e.path) dir mode") }
            else {
                #expect((st.st_mode & S_IFMT) == S_IFREG && Int(st.st_mode & 0o7777) == e.mode, "\(e.path) mode \(String(st.st_mode & 0o7777, radix: 8))")
                let d = try Data(contentsOf: u)
                #expect(d.count == e.size && SHA256Hex.hex(d) == e.sha256, "\(e.path) content")
            }
        }
        // nothing else of ours, and none of Asahi's: the System root holds the restore image's three, our four
        let top = Set(try FileManager.default.contentsOfDirectory(atPath: sys.path))
        #expect(top == [".VolumeIcon.icns", ".IAPhysicalMedia", "SiliconForest Setup.app", "SFInstall", "usr", "System", "Restore"])
        let tree = try FileManager.default.subpathsOfDirectory(atPath: sys.appendingPathComponent("SiliconForest Setup.app").path).sorted()
        #expect(tree == ["Contents", "Contents/Info.plist", "Contents/MacOS", "Contents/MacOS/SFRecovery", "Contents/MacOS/sf-launcher",
                         "Contents/Resources", "Contents/Resources/boot.bin", "Contents/Resources/grove.png", "Contents/Resources/sf-step2.sh"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: sys.appendingPathComponent("SFInstall/state").path).isEmpty)
        // the boot object points at the SFBOOT partition and ends with the variables block
        let boot = try Data(contentsOf: sys.appendingPathComponent("SiliconForest Setup.app/Contents/Resources/boot.bin"))
        #expect(boot.suffix(4) == Data([0, 0, 0, 0]))
        let text = String(decoding: boot.suffix(200).filter { $0 != 0 }, as: UTF8.self)
        #expect(text.hasSuffix("chosen.asahi,efi-system-partition=\(bootUUID)\nchainload=\(bootUUID);sf/boot.bin\n"))
        // plan.json is the engine's, unchanged
        #expect(try Data(contentsOf: sys.appendingPathComponent("SFInstall/plan.json")) == planJSON())
        // the volume's metadata did not change shape: bootable flag, FinderInfo, and the stub SystemVersion
        #expect(plan.map(\.description).contains("fsctl APFSIOC_VOL_BOOTABLE System"))
        #expect(plan.last.map(\.description) == "boot object (2 vars) -> System:/SiliconForest Setup.app/Contents/Resources/boot.bin")
        #expect(effects.contains { $0.hasPrefix("xattr -wx com.apple.FinderInfo") })
        // the copied app tree reported its flags, as upstream's copytree does
        #expect(effects.filter { $0.hasPrefix("os.chflags") && $0.contains("SiliconForest Setup.app") }.count == 9)
    }

    @Test func everythingButThePayloadIsTheSameAsWithAsahiShapedPayload() throws {
        let dir = tempDir("sfp-shape")
        let (_, _, _, sfPlan, _) = try land(dir.appendingPathComponent("sf"))
        let (data, profile) = fixtureIPSW()
        let z = try ZipReader(MemorySource(data))
        let img = try RestoreImage(zip: z, profile: profile)
        let base = dir.appendingPathComponent("base")
        let asahi = try fixturePayload(base)
        let basePlan = try StubPlanner.plan(image: img, target: "11111111-2222-3333-4444-555555555555", payload: asahi, adminUsers: base.appendingPathComponent("admin.plist"))
        // the payload's own actions: the icon, the app and its script, the media marker, the extras, the boot object
        func owned(_ d: String) -> Bool {
            d.contains("Setup.app") || d.contains(".VolumeIcon.icns") || d.contains(".IAPhysicalMedia") || d.contains("SFInstall") || d.contains("IAPhysicalMedia-disabled")
                || d.hasPrefix("boot object")
        }
        let a = basePlan.map(\.description), b = sfPlan.map(\.description)
        let ra = a.filter { !owned($0) }, rb = b.filter { !owned($0) }
        #expect(ra.count == rb.count, "\(ra.count) vs \(rb.count): only baseline \(Set(ra).subtracting(rb)), only SF \(Set(rb).subtracting(ra))")
        let firstDiff = zip(ra, rb).first { $0 != $1 }
        #expect(ra == rb, "first difference: \(String(describing: firstDiff))")
        // and the payload's actions sit at the same places in both (icon, app copy, marker, boot object last)
        func firstIndex(_ l: [String], _ s: String) -> Int { l.firstIndex { $0.contains(s) }! }
        #expect(firstIndex(a, ".VolumeIcon.icns") == firstIndex(b, ".VolumeIcon.icns"))
        #expect(firstIndex(a, "copytree") == firstIndex(b, "copytree"))
        #expect(a.last!.hasPrefix("boot object") && b.last!.hasPrefix("boot object"))
    }
}
