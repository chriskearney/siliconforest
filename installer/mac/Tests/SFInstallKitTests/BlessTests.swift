import Foundation
import Testing
@testable import SFEngine
@testable import SFHelperKit
import SFInstallKit
import SFAppEngine

/// Preview7: the one-time next boot. Nothing here runs bless: argument building, volume validation and
/// the runner's allow-list are pure; the engine path uses a recording runner.
@Suite("Bless: one-time next boot, argument building and validation")
struct BlessTests {
    static func partition(system id: String, uuid: String = "AAAA") -> ImagePartition {
        let vols = [ImageVolume(identifier: "\(id)", uuid: "V1", name: "SiliconForest", roles: ["System"]),
                    ImageVolume(identifier: "\(id.dropLast())2", uuid: "V2", name: "Data", roles: ["Data"])]
        return ImagePartition(uuid: uuid, identifier: "disk9s2", content: "Apple_APFS", offset: 0, size: 1,
                              volumeName: nil, filesystem: nil,
                              apfs: ImageAPFS(reference: "disk10", uuid: "C", capacityCeiling: 1, capacityFree: 1, volumes: vols))
    }

    @Test func buildsTheOneTimeSelectionOnly() throws {
        let stub = Self.partition(system: "disk10s1")
        let argv = try BlessGuard.setNextBoot(mount: URL(fileURLWithPath: "/Volumes/SiliconForest"), stub: stub) { _ in "/dev/disk10s1" }
        #expect(argv == ["/usr/sbin/bless", "--mount", "/Volumes/SiliconForest", "--setBoot", "--nextonly"])
        #expect(BlessGuard.isAllowed(argv))
        // The sealed snapshot of the stub's volume is still the stub's volume.
        let snap = try BlessGuard.setNextBoot(mount: URL(fileURLWithPath: "/Volumes/SiliconForest"), stub: stub) { _ in "/dev/disk10s1s1" }
        #expect(snap == argv)
    }

    @Test func refusesAnyOtherVolume() {
        let stub = Self.partition(system: "disk10s1")
        func refused(_ mount: String, _ dev: String?) -> Bool {
            (try? BlessGuard.setNextBoot(mount: URL(fileURLWithPath: mount), stub: stub) { _ in dev }) == nil
        }
        #expect(refused("/Volumes/Macintosh HD", "/dev/disk3s1s1"), "macOS's own volume")
        #expect(refused("/", "/dev/disk10s1"), "the running system, even if the device matched")
        #expect(refused("/Volumes/SiliconForest", "/dev/disk10s2"), "the stub's Data volume")
        #expect(refused("/Volumes/SiliconForest", nil), "an unmounted path")
        #expect(refused("/Volumes/../Volumes/x", "/dev/disk10s1"))
        #expect(refused("/tmp/x", "/dev/disk10s1"))
        #expect(refused("/Volumes/", "/dev/disk10s1"))
        #expect(refused("/Volumes/SiliconForest", "/dev/sda1"), "not an APFS volume device")
        #expect((try? BlessGuard.setNextBoot(mount: URL(fileURLWithPath: "/Volumes/x"), stub: ImagePartition(uuid: "u", identifier: "disk9s2", content: "Apple_APFS", offset: 0, size: 1, volumeName: nil, filesystem: nil, apfs: nil)) { _ in "/dev/disk10s1" }) == nil, "a stub with no System volume")
    }

    @Test func restoreBuildsThePersistentSelectionForMacOSOnly() throws {
        let mac = Self.partition(system: "disk3s1", uuid: "MAC")
        #expect(try BlessGuard.restoreBoot(mount: "/", macOS: mac) { _ in "/dev/disk3s1s1" } == ["/usr/sbin/bless", "--mount", "/", "--setBoot"])
        #expect(try BlessGuard.restoreBoot(mount: "/Volumes/Macintosh HD", macOS: mac) { _ in "/dev/disk3s1" }.last == "--setBoot")
        #expect((try? BlessGuard.restoreBoot(mount: "/", macOS: mac) { _ in "/dev/disk10s1" }) == nil, "the stub is not macOS")
        #expect((try? BlessGuard.restoreBoot(mount: "/private", macOS: mac) { _ in "/dev/disk3s1" }) == nil)
    }

    @Test func theAllowListIsExact() {
        let t = BlessGuard.tool
        #expect(BlessGuard.isAllowed([t, "--getBoot"]))
        #expect(BlessGuard.isAllowed([t, "--mount", "/", "--setBoot"]))
        #expect(BlessGuard.isAllowed([t, "--mount", "/Volumes/A B", "--setBoot", "--nextonly"]))
        #expect(!BlessGuard.isAllowed([t, "--mount", "/", "--setBoot", "--nextonly"]), "next-boot only ever targets a /Volumes mount, never the running system")
        #expect(!BlessGuard.isAllowed([t, "--mount", "/Volumes/A", "--setBoot", "--nextonly", "--legacy"]))
        #expect(!BlessGuard.isAllowed([t, "--mount", "/Volumes/A", "--bootefi", "x"]))
        #expect(!BlessGuard.isAllowed([t, "--mount", "/Volumes/A", "--setBoot", "--personalize"]))
        #expect(!BlessGuard.isAllowed(["/bin/sh", "--getBoot"]))
        #expect(!BlessGuard.isAllowed([t, "--folder", "/Volumes/A", "--setBoot"]))
        #expect(!BlessGuard.isAllowed([t, "--mount", "/Volumes/A/../..", "--setBoot"]))
        #expect(!BlessGuard.isAllowed([t, "--mount", "/Users/x", "--setBoot"]))
        #expect(!BlessGuard.isAllowed([]))
    }

    @Test func getBootOutputIsMatchedToTheVolume() {
        let v = ImageVolume(identifier: "disk10s1", uuid: "V", name: "SiliconForest", roles: ["System"])
        #expect(BlessGuard.names(getBootOutput: "/dev/disk10s1\n", volume: v, mount: nil))
        #expect(BlessGuard.names(getBootOutput: "/Volumes/SiliconForest/System/Library/CoreServices", volume: v, mount: "/Volumes/SiliconForest"))
        #expect(!BlessGuard.names(getBootOutput: "/dev/disk3s1\n", volume: v, mount: "/Volumes/SiliconForest"))
        #expect(!BlessGuard.names(getBootOutput: "/dev/disk10s11\n", volume: v, mount: nil), "a prefix of another volume's number is not a match")
        #expect(!BlessGuard.names(getBootOutput: "", volume: v, mount: nil))
        #expect(!BlessGuard.names(getBootOutput: "/System/Library", volume: v, mount: "/"))
    }

    @Test func theManualCommandIsTheSameShape() {
        let m = BlessGuard.manual(volumeName: "SiliconForest")
        #expect(m == "sudo /usr/sbin/bless --mount \"/Volumes/SiliconForest\" --setBoot --nextonly")
        #expect(AfterHandoff.blessCommand(installName: "SiliconForest") == m)
        #expect(!AfterHandoff.manualSteps(installName: "SiliconForest").isEmpty && AfterHandoff.fallback.contains("power button"))
    }

    @Test func theRealRunnerRefusesWhatIsNotAllowedAndNonRoot() {
        let r = ProcessBlessRunner()
        #expect(r.execute(["/usr/sbin/bless", "--folder", "/System"]).status == 126)
        #expect(r.execute(["/bin/echo", "x"]).status == 126)
        if geteuid() != 0 { #expect(r.execute(BlessGuard.getBoot).status == 126, "never runs bless unless root") }
    }

    @Test func verbsAreListedAndSelectorsStayClean() {
        for v in ["listInstallsWithReply:", "planRemovalWithInstallJob:reply:", "restartIntoInstalledSystemWithJob:reply:"] { #expect(HelperVerbs.expected.contains(v)) }
    }

    // MARK: preview13: the volume owner's login for bless (owner authentication on Apple Silicon)

    @Test func theOwnerFlagsAreWidenedNarrowlyAndOnlyTogether() throws {
        let stub = Self.partition(system: "disk10s1")
        let argv = try BlessGuard.setNextBoot(mount: URL(fileURLWithPath: "/Volumes/SiliconForest"), stub: stub, owner: "chris.k") { _ in "/dev/disk10s1" }
        #expect(argv == ["/usr/sbin/bless", "--mount", "/Volumes/SiliconForest", "--setBoot", "--nextonly", "--user", "chris.k", "--stdinpass"])
        #expect(BlessGuard.isAllowed(argv) && BlessGuard.usesPassword(argv))
        let base = Array(argv.prefix(5))
        for bad: [String] in [
            base + ["--user", "chris"],                                                  // no --stdinpass
            base + ["--stdinpass"],                                                      // a password with no account
            base + ["--stdinpass", "--user", "chris"],                                   // wrong order
            base + ["--user", "-x", "--stdinpass"],                                      // not an account name
            base + ["--user", "a b", "--stdinpass"], base + ["--user", "../root", "--stdinpass"], base + ["--user", "", "--stdinpass"],
            base + ["--user", "chris", "--stdinpass", "--passwd", "x"],                  // extra flags
            ["/usr/sbin/bless", "--mount", "/", "--setBoot", "--nextonly", "--user", "chris", "--stdinpass"],  // not a /Volumes mount
            ["/usr/sbin/bless", "--mount", "/Volumes/x", "--setBoot", "--user", "chris", "--stdinpass"],       // not one-time
            ["/usr/sbin/bless", "--mount", "/Volumes/x", "--setBoot", "--nextonly", "--user", "chris", "--password", "pw"],
        ] { #expect(!BlessGuard.isAllowed(bad), "\(bad)") }
        // The password is never an argument anywhere in what the guard builds.
        #expect(throws: BlessGuard.Refusal.self) {
            _ = try BlessGuard.setNextBoot(mount: URL(fileURLWithPath: "/Volumes/SiliconForest"), stub: stub, owner: "--evil") { _ in "/dev/disk10s1" }
        }
    }

    @Test func theRunnerRefusesAMismatchedPasswordAndTheStdinFeedIsExact() throws {
        let stub = Self.partition(system: "disk10s1")
        let withUser = try BlessGuard.setNextBoot(mount: URL(fileURLWithPath: "/Volumes/SiliconForest"), stub: stub, owner: "chris") { _ in "/dev/disk10s1" }
        let r = ProcessBlessRunner()
        // Not root in tests: refused before anything runs, and a password is never sent to a command without --stdinpass.
        #expect(r.execute(withUser).status == 126)
        let secret = SecureBytes(Data("correct horse".utf8))
        #expect(r.execute(BlessGuard.getBoot, password: secret).status == 126)
        #expect(!secret.isWiped, "the runner doesn't wipe; the engine does")
        // The bytes reach the descriptor, then a newline: nothing else.
        var fds: [Int32] = [0, 0]
        #expect(pipe(&fds) == 0)
        StdinFeed.send(secret, to: fds[1]); close(fds[1])
        var buf = [UInt8](repeating: 0, count: 64)
        let n = read(fds[0], &buf, 64); close(fds[0])
        #expect(String(decoding: buf.prefix(max(0, n)), as: UTF8.self) == "correct horse\n")
        secret.wipe()
        #expect(secret.isZeroed)
    }

    @Test func outputIsScrubbedAndAuthFailuresAreRecognised() {
        #expect(BlessGuard.scrub("bad: correct horse here", password: "correct horse") == "bad: ••• here")
        #expect(BlessGuard.scrub("unchanged", password: "") == "unchanged")
        #expect(BlessGuard.looksLikeOwnerAuthFailure("bless: owner authentication required"))
        #expect(!BlessGuard.looksLikeOwnerAuthFailure("simulated failure"))
        #expect(BlessGuard.validOwner("chris") && BlessGuard.validOwner("_svc") && BlessGuard.validOwner("a.b-c_1"))
        #expect(!BlessGuard.validOwner("") && !BlessGuard.validOwner("-a") && !BlessGuard.validOwner("a b") && !BlessGuard.validOwner(String(repeating: "a", count: 65)))
    }

    @Test func ownersAreTheLocalVolumeOwnersConsoleUserFirst() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>Users</key><array>
        <dict><key>APFSCryptoUserType</key><string>LocalOpenDirectory</string><key>APFSCryptoUserUUID</key><string>5375F0A7-328F-4639-861A-164784DFA657</string><key>VolumeOwner</key><true/></dict>
        <dict><key>APFSCryptoUserType</key><string>LocalOpenDirectory</string><key>APFSCryptoUserUUID</key><string>AAAAAAAA-0000-0000-0000-000000000001</string><key>VolumeOwner</key><true/></dict>
        <dict><key>APFSCryptoUserType</key><string>LocalOpenDirectory</string><key>APFSCryptoUserUUID</key><string>BBBBBBBB-0000-0000-0000-000000000002</string><key>VolumeOwner</key><false/></dict>
        <dict><key>APFSCryptoUserType</key><string>MDMRecovery</string><key>APFSCryptoUserUUID</key><string>2457711A-523C-4604-B75A-F48A571D5036</string><key>VolumeOwner</key><true/></dict>
        </array></dict></plist>
        """
        let dscl = """
        admin                    AAAAAAAA-0000-0000-0000-000000000001
        chriskearney             5375F0A7-328F-4639-861A-164784DFA657
        guest                    BBBBBBBB-0000-0000-0000-000000000002
        root                     FFFFEEEE-DDDD-CCCC-BBBB-AAAA00000000
        """
        let a = StartupDiskOwners.parse(listUsersPlist: Data(plist.utf8), accounts: dscl, console: "chriskearney")
        #expect(a.owners == ["chriskearney", "admin"] && a.defaultOwner == "chriskearney")
        let b = StartupDiskOwners.parse(listUsersPlist: Data(plist.utf8), accounts: dscl, console: "guest")
        #expect(b.owners == ["admin", "chriskearney"] && b.defaultOwner == "admin", "a console user who isn't an owner is not the default")
        let none = StartupDiskOwners.parse(listUsersPlist: Data("garbage".utf8), accounts: dscl, console: "admin")
        #expect(none.owners.isEmpty && none.defaultOwner == nil)
        let found = StartupDiskOwners.find(run: { exe, _ in exe.hasSuffix("diskutil") ? Data(plist.utf8) : Data(dscl.utf8) }, console: nil)
        #expect(found.owners.count == 2)
        #expect(StartupDiskOwners.find(run: { _, _ in nil }, console: "x").owners.isEmpty)
    }
}
