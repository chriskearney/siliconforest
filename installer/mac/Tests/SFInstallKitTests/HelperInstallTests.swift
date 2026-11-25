import Foundation
import Testing
@testable import SFHelperKit
@testable import SFEngine
@testable import SFLiveDisk
import SFAppEngine
import SFIdentity
import SFInstallKit

// Preview6: the verbs the installer app drives the real install with (import, plan, confirm, progress),
// in process over a real NSXPCConnection, through the app's own LiveInstallController. No disk is touched:
// the target is none, and the end-to-end run on a disk image is sfappimage (scripts/app-image-e2e.sh).

private func tmp() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("sf-appinstall-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

private let repoSigners = SourceTree.installerRoot.appendingPathComponent("payload/release/allowed_signers")

private func helper(_ dir: URL, admin: AdminCheck = .never) -> (InProcessHelper, LiveInstallController) {
    var c = HelperConfig(target: .none, journalDirectory: dir.appendingPathComponent("journal"), workDirectory: dir.appendingPathComponent("work"),
                         profileID: "J313", release: nil, releaseSource: nil,
                         policy: ConnectionPolicy(clientRequirement: CodeIdentity.ownDesignatedRequirement() ?? "", minimumClientBuild: 0),
                         idleTimeout: 5, resizeTiming: .tests)
    c.releaseStore = dir.appendingPathComponent("releases")
    c.allowedSigners = repoSigners
    c.adminCheck = admin
    let h = InProcessHelper(c)
    return (h, LiveInstallController { h.client() })
}

private func sha(_ d: Data) -> String { SHA256Hasher.hex(d) }

/// A folder shaped like a release: files and a SHA256SUMS over them.
private func folder(_ files: [String: Data], extraSums: [String] = [], sig: Data? = Data("not a signature".utf8)) throws -> URL {
    let d = tmp()
    var lines: [String] = []
    for (n, data) in files.sorted(by: { $0.key < $1.key }) { try data.write(to: d.appendingPathComponent(n)); lines.append("\(sha(data))  \(n)") }
    lines += extraSums
    try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: d.appendingPathComponent("SHA256SUMS"))
    if let sig { try sig.write(to: d.appendingPathComponent("SHA256SUMS.sig")) }
    return d
}

private func refused(_ body: () throws -> Void) -> String? {
    do { try body(); return nil } catch { return "\(error)" }
}

@Suite("Helper: the app's install verbs (in process)")
struct HelperInstallVerbTests {
    @Test func importRefusesAnythingButASignedListedRelease() throws {
        let (_, app) = helper(tmp())
        // No signature at all.
        let unsigned = try folder(["install.json": Data("{}".utf8)], sig: nil)
        #expect(refused { _ = try app.importRelease(unsigned) } != nil)
        // Names that could escape the store or hide.
        for bad in ["\(String(repeating: "0", count: 64))  ../evil", "\(String(repeating: "0", count: 64))  .hidden", "\(String(repeating: "0", count: 64))  a/b"] {
            let f = try folder(["install.json": Data("{}".utf8)], extraSums: [bad])
            #expect(refused { _ = try app.importRelease(f) } != nil, "\(bad)")
        }
        // A listed file that is a symlink.
        let link = try folder(["install.json": Data("{}".utf8)])
        try FileManager.default.createSymbolicLink(atPath: link.appendingPathComponent("boot.bin").path, withDestinationPath: "/etc/hosts")
        var s = try String(contentsOf: link.appendingPathComponent("SHA256SUMS"), encoding: .utf8)
        s += "\(sha(try Data(contentsOf: URL(fileURLWithPath: "/etc/hosts"))))  boot.bin\n"
        try s.write(to: link.appendingPathComponent("SHA256SUMS"), atomically: true, encoding: .utf8)
        #expect(refused { _ = try app.importRelease(link) } != nil)
        // Signed, but by a key that isn't the release key (a throwaway key made here).
        let other = try folder(["install.json": Data("{}".utf8)], sig: nil)
        let key = tmp().appendingPathComponent("k")
        try run("/usr/bin/ssh-keygen", ["-q", "-t", "ed25519", "-N", "", "-C", "throwaway", "-f", key.path])
        try run("/usr/bin/ssh-keygen", ["-q", "-Y", "sign", "-f", key.path, "-n", "siliconforest-release", other.appendingPathComponent("SHA256SUMS").path])
        let why = refused { _ = try app.importRelease(other) }
        #expect(why != nil)
        // Nothing was imported, so nothing can be planned.
        #expect(refused { _ = try app.offer(bytes: nil, name: nil) } != nil)
    }

    @Test func confirmRefusesWhatWasNotOfferedAndBeginNeedsAConfirmation() throws {
        let (h, app) = helper(tmp(), admin: AdminCheck { $0 == Data("ok".utf8) })
        let t = TypedConfirmation(diskName: "Macintosh HD", phrase: "ERASE 30 GB")
        #expect(refused { _ = try app.confirm(planDigest: "0123", typed: t, authorization: Data("ok".utf8)) } != nil)
        let plan = try StubOnlyPlanTests.plan()
        do { _ = try h.client().begin(plan); Issue.record("begin without a confirmation") } catch let e as NSError {
            #expect(e.code == HelperErrorCode.refused.rawValue && e.localizedDescription.contains("confirmed"), "\(e)")
        }
        #expect(refused { _ = try app.progress(UUID().uuidString, after: 0) } != nil)
        #expect(try app.info().target == "none")
    }

    @Test func theTypedConfirmationIsExact() {
        let want = TypedConfirmation(diskName: "Macintosh HD", phrase: "ERASE 30 GB")
        #expect(TypedConfirmation(diskName: " Macintosh HD\n", phrase: "ERASE 30 GB ").matches(want))
        for wrong in [("macintosh hd", "ERASE 30 GB"), ("Macintosh HD", "erase 30 gb"), ("Macintosh HD", "ERASE 31 GB"), ("Macintosh  HD", "ERASE 30 GB"), ("", "")] {
            #expect(!TypedConfirmation(diskName: wrong.0, phrase: wrong.1).matches(want), "\(wrong)")
        }
        #expect(!TypedConfirmation(diskName: "", phrase: "ERASE 30 GB").matches(TypedConfirmation(diskName: "", phrase: "ERASE 30 GB")))
        var p = try! StubOnlyPlanTests.plan()
        #expect(TypedConfirmation.phrase(plan: p) == "ERASE 22 GB")   // 100 GiB → 80 GiB is 21.47 GB, rounded up
        p.operation = .remove
        #expect(TypedConfirmation.phrase(plan: p) == "REMOVE SILICONFOREST")
    }

    @Test func theAdministratorCheckFailsClosed() {
        #expect(!AdminCheck.never.verify(Data()))
        #expect(!AdminCheck.system.verify(Data()))
        #expect(!AdminCheck.system.verify(Data(count: 32)))   // not an AuthorizationExternalForm of a granted right
    }

    @Test func theAuthorizationFileIsBoundRootShapedAndShort() throws {
        let dir = tmp().appendingPathComponent("gate")
        let path = dir.appendingPathComponent("real-disk-authorization.json").path
        let now = Date()
        let a = AuthorizationFile.authorization(planDigest: "PLAN", diskUUID: "abcd-1234", now: now, hours: 12)
        #expect(a.notAfter.timeIntervalSince(a.notBefore) <= RealDiskGate.maxValidity && a.diskUUID == "ABCD-1234")
        try AuthorizationFile.write(a, to: path)
        var st = stat()
        #expect(lstat(path, &st) == 0 && st.st_mode & 0o777 == 0o600)
        #expect(lstat(dir.path, &st) == 0 && st.st_mode & 0o777 == 0o700)
        // What the gate reads, as root would see it (owner faked to 0; everything else is the real file).
        let asRoot = RealDiskGate.FileProbe(lstat: { p in RealDiskGate.FileProbe.system.lstat(p).map { var s = $0; s.uid = 0; return s } },
                                            read: RealDiskGate.FileProbe.system.read)
        func gate(_ plan: String, _ disk: String, at t: Date = Date()) -> Bool {
            if case .success = RealDiskGate.evaluate(planDigest: plan, diskUUID: disk, path: path, now: t, uid: 0, probe: asRoot, compiled: true) { return true }
            return false
        }
        #expect(gate("PLAN", "ABCD-1234"))
        #expect(!gate("OTHER", "ABCD-1234") && !gate("PLAN", "FFFF") && !gate("PLAN", "ABCD-1234", at: now.addingTimeInterval(2 * 3600)))
        // Without the compile key the file is never even read.
        if case .failure(.notCompiled) = RealDiskGate.evaluate(planDigest: "PLAN", diskUUID: "ABCD-1234", path: path, uid: 0, probe: asRoot, compiled: false) {} else { Issue.record("compile key") }
        // A symlink in the file's place is refused, and a rewrite replaces the file.
        AuthorizationFile.remove(path)
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: "/etc/hosts")
        #expect(throws: (any Error).self) { try AuthorizationFile.write(a, to: path) }
    }

    /// `/` is mounted from the System volume's sealed snapshot (disk3s1s1 on the M5): the volume is disk3s1.
    /// Then, read-only on this Mac: the startup disk and the Preboot admin list the helper will use.
    @Test func theStartupVolumeIsFoundThroughItsSnapshot() throws {
        #expect(try StartupDisk.volume(mountedFrom: "/dev/disk3s1s1") == "disk3s1")
        #expect(try StartupDisk.volume(mountedFrom: "/dev/disk3s5") == "disk3s5")
        for bad in ["/dev/disk3s1s1s1", "map auto_home", "/dev/disk3s1;x", "disk"] {
            #expect(throws: (any Error).self, "\(bad)") { _ = try StartupDisk.volume(mountedFrom: bad) }
        }
        #expect(try StartupDisk.rootVolume().hasPrefix("disk"))
    }

    /// SF_READ_STARTUP_DISK=1, as root, on a real Mac (CI's virtual Macs have no internal physical disk):
    /// read-only diskutil info / list and the GPT header's two blocks; nothing is written.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SF_READ_STARTUP_DISK"] == "1" && geteuid() == 0))
    func theStartupDiskAndAdminListOfThisMac() throws {
        let d = try StartupDisk.find()
        #expect(UUID(uuidString: d.uuid) != nil && d.whole.hasPrefix("disk"))
        let admins = try HelperResources.adminUsersPlist()
        #expect(FileManager.default.fileExists(atPath: admins.path), "\(admins.path)")
    }

    @Test func onlyThePinnedStage1IsAccepted() throws {
        #expect(throws: Never.self) { try StagePin.check(ReleaseManifest.stubOnly(bytes: StagePin.stage1Bytes, sha256: StagePin.stage1SHA256, version: "v")) }
        #expect(throws: (any Error).self) { try StagePin.check(ReleaseManifest.stubOnly(bytes: StagePin.stage1Bytes, sha256: String(repeating: "b", count: 64), version: "v")) }
        #expect(throws: (any Error).self) { try StagePin.check(ReleaseManifest.stubOnly(bytes: 1, sha256: StagePin.stage1SHA256, version: "v")) }
    }

    /// SF_RELEASE_DIR=<a downloaded signed release> (the M5 keeps preview5's): the real import, then a copy with one
    /// byte changed in one listed file, which must be refused before anything is planned.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SF_RELEASE_DIR"] != nil))
    func aSignedReleaseImportsAndATamperedCopyDoesNot() throws {
        let src = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SF_RELEASE_DIR"]!)
        let dir = tmp()
        let (_, app) = helper(dir)
        let s = try app.importRelease(src)
        #expect(s.stage1SHA256 == StagePin.stage1SHA256 && s.files > 100)
        let copy = dir.appendingPathComponent("copy")
        try FileManager.default.copyItem(at: src, to: copy)   // APFS clones
        let t = copy.appendingPathComponent("bootargs.template")
        var d = try Data(contentsOf: t); d[d.count - 2] ^= 1
        try FileManager.default.removeItem(at: t); try d.write(to: t)
        // A helper with an empty store (the first one's store already holds the verified release under these
        // SHA256SUMS, which it re-verifies and uses instead of the folder) copies the tampered file and refuses it.
        let (_, fresh) = helper(tmp())
        #expect(refused { _ = try fresh.importRelease(copy) } != nil)
        #expect(try app.importRelease(copy).digest == s.digest)   // the store's verified copy, not the folder's file
    }
}

private func run(_ tool: String, _ args: [String]) throws {
    let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
    p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
    try p.run(); p.waitUntilExit()
    guard p.terminationStatus == 0 else { throw NSError(domain: "test", code: Int(p.terminationStatus)) }
}

@Suite("Whole-disk identity: the GPT header's disk GUID")
struct GPTDiskGUIDTests {
    /// A primary header as diskutil / gpt write it, for GUID 2E32583B-C713-465E-ABB0-732A131E216C.
    static func header(guid: String = "2E32583B-C713-465E-ABB0-732A131E216C", lba: UInt64 = 1) -> [UInt8] {
        var h = [UInt8](repeating: 0, count: 512)
        h.replaceSubrange(0..<8, with: Array("EFI PART".utf8))
        func put32(_ o: Int, _ v: UInt32) { for i in 0..<4 { h[o + i] = UInt8((v >> (8 * UInt32(i))) & 0xff) } }
        func put64(_ o: Int, _ v: UInt64) { for i in 0..<8 { h[o + i] = UInt8((v >> (8 * UInt64(i))) & 0xff) } }
        put32(8, 0x0001_0000); put32(12, 92); put64(24, lba); put64(32, 999); put64(40, 34); put64(48, 966)
        let u = UUID(uuidString: guid)!.uuid
        let b = [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7, u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15]
        h.replaceSubrange(56..<72, with: [b[3], b[2], b[1], b[0], b[5], b[4], b[7], b[6]] + Array(b[8..<16]))
        put32(16, GPTHeader.crc32(Array(h[0..<92])))
        return h
    }

    @Test func theGUIDComesOutMixedEndianAndCheckedOrNotAtAll() throws {
        #expect(try GPTHeader.guid(header: Self.header()) == "2E32583B-C713-465E-ABB0-732A131E216C")
        var bad = Self.header(); bad[60] ^= 1
        #expect(throws: (any Error).self) { _ = try GPTHeader.guid(header: bad) }            // CRC
        #expect(throws: (any Error).self) { _ = try GPTHeader.guid(header: Self.header(lba: 999)) }   // the backup header
        var sig = Self.header(); sig[0] = 0x46
        #expect(throws: (any Error).self) { _ = try GPTHeader.guid(header: sig) }
        #expect(GPTHeader.crc32(Array("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test func diskutilsUUIDIsUsedWhenItGivesOneAndTheHeaderOtherwise() throws {
        #expect(try WholeDiskIdentity.uuid("disk9", info: ["DiskUUID": "abc"]) == "ABC")
        #expect(throws: (any Error).self) { _ = try WholeDiskIdentity.uuid("disk9s1", info: [:]) }
    }

    /// SF_GPT_IMAGE_DEVICE=diskN: an attached disk image of this run (readable without root): the header's
    /// GUID read raw; SF_GPT_IMAGE_GUID, when set, is the value read independently (scripts or Python).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SF_GPT_IMAGE_DEVICE"] != nil))
    func anAttachedImagesGUID() throws {
        let d = ProcessInfo.processInfo.environment["SF_GPT_IMAGE_DEVICE"]!
        let g = try WholeDiskIdentity.uuid(d, info: ["DeviceBlockSize": 512])
        #expect(UUID(uuidString: g) != nil)
        if let want = ProcessInfo.processInfo.environment["SF_GPT_IMAGE_GUID"] { #expect(g == want.uppercased()) }
    }
}
