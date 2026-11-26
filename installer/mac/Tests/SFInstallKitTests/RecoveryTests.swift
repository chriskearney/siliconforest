import Foundation
import Testing
@testable import SFRecoveryKit
import SFEngine
import SFCopy
import SFInstallKit

/// Fake bputil, kmutil, bless, diskutil and reboot, written as shell scripts into a temporary
/// directory. The real tools are never invoked by any test.
struct FakeTools {
    let dir: URL
    let calls: URL
    let password = "correct horse battery"
    var tools: RecoveryTools {
        RecoveryTools(bputil: dir.appendingPathComponent("fake-bputil").path, kmutil: dir.appendingPathComponent("fake-kmutil").path,
                      bless: dir.appendingPathComponent("fake-bless").path, diskutil: dir.appendingPathComponent("fake-diskutil").path,
                      reboot: dir.appendingPathComponent("fake-reboot").path, shutdown: dir.appendingPathComponent("fake-shutdown").path)
    }

    /// `policy`: what `bputil -d` prints before `-nc`. `echoOff: false` makes the password prompt
    /// leave echo on (the driver must then refuse to type the password).
    /// `owner`: the tools first ask "Enter the username:" and accept only that short name (preview13).
    /// `vgPolicy`: what `bputil -d -v <group>` prints, when it differs from the running recovery's `-d`.
    init(policy: String = "Paired: Yes\nBooted from one true recoveryOS\nSecurity Mode: Full", echoOff: Bool = true, kmutilFails: Bool = false, owner: String? = nil, vgPolicy: String? = nil) throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sf-fake-tools-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        calls = dir.appendingPathComponent("calls.log")
        FileManager.default.createFile(atPath: calls.path, contents: nil)
        let d = dir.path, log = calls.path
        let noEcho = echoOff ? "stty -echo 2>/dev/null" : ":"
        let restore = echoOff ? "stty echo 2>/dev/null" : ":"
        func askUser(_ tool: String) -> String {
            guard let owner else { return "" }
            return """
                printf 'Enter the username: '
                read u; printf '%s' "$u" > '\(d)/\(tool)-user'
                [ "$u" = '\(owner)' ] || { echo 'Unknown user'; exit 1; }

                """
        }
        let vgBranch = vgPolicy.map { "if [ \"$2\" = -v ]; then printf '%b\\n' '\($0.replacingOccurrences(of: "\n", with: "\\\\n"))'; exit 0; fi; " } ?? ""
        func write(_ name: String, _ body: String) throws {
            let u = dir.appendingPathComponent(name)
            try ("#!/bin/sh\n# test fake: never the real \(name.dropFirst(5))\necho \"\(name) $*\" >> '\(log)'\n" + body).write(to: u, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path)
        }
        try write("fake-bputil", """
            case "$1" in
              -d) \(vgBranch)if [ -f '\(d)/permissive' ]; then printf 'Paired: Yes\\nBooted from one true recoveryOS\\nSecurity Mode: Permissive\\n'; else printf '%b\\n' '\(policy.replacingOccurrences(of: "\n", with: "\\\\n"))'; fi; exit 0 ;;
              -nc)
                \(askUser("bputil"))printf 'Enter password for user chris: '
                \(noEcho); read pw; \(restore); echo
                printf '%s' "$pw" > '\(d)/bputil-received'
                [ "$pw" = '\(password)' ] || { echo 'Incorrect password'; exit 1; }
                printf 'This will reduce the security of this volume group. Continue? (y/n) '
                read ans
                [ "$ans" = y ] || { echo 'Cancelled'; exit 1; }
                : > '\(d)/permissive'; echo 'Policy updated.'; exit 0 ;;
            esac
            exit 2
            """)
        try write("fake-kmutil", """
            \(askUser("kmutil"))printf 'Enter password for user chris: '
            \(noEcho); read pw; \(restore); echo
            [ "$pw" = '\(password)' ] || { echo 'Incorrect password'; exit 1; }
            \(kmutilFails ? "echo 'Error: configure-boot failed (simulated)'; exit 3" : "echo 'Boot object installed.'; exit 0")
            """)
        try write("fake-bless", "exit 0\n")
        try write("fake-diskutil", """
            printf '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>APFSVolumeGroupID</key><string>11111111-2222-3333-4444-555555555555</string></dict></plist>\\n'
            """)
        try write("fake-reboot", ": > '\(d)/rebooted'\n")
        try write("fake-shutdown", "exit 0\n")
    }

    var log: [String] { ((try? String(contentsOf: calls, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }

    /// A stub System volume as the helper stages it (S55, S60, S68).
    func makeVolume() throws -> URL {
        let v = dir.appendingPathComponent("StubSystem", isDirectory: true)
        let fm = FileManager.default
        let app = v.appendingPathComponent("SiliconForest Setup.app/Contents")
        try fm.createDirectory(at: app.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        try fm.createDirectory(at: app.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try Data("stage1".utf8).write(to: app.appendingPathComponent("Resources/boot.bin"))
        try fm.createDirectory(at: v.appendingPathComponent("SFInstall/state"), withIntermediateDirectories: true)
        try #"{"job":"j","installID":"a1b2c3d4","stub":"S","boot":"B","root":"R","planDigest":"d"}"#.write(to: v.appendingPathComponent("SFInstall/plan.json"), atomically: true, encoding: .utf8)
        try "AppName".write(to: v.appendingPathComponent(".IAPhysicalMedia"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: v.appendingPathComponent("System/Library/CoreServices"), withIntermediateDirectories: true)
        try "plist".write(to: v.appendingPathComponent("System/Library/CoreServices/SystemVersion.plist.sf-hidden"), atomically: true, encoding: .utf8)
        // The payload scripts, as S60 stages them.
        for (rel, data, exec) in RecoveryPayload.files() {
            let u = app.appendingPathComponent(rel)
            try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: u)
            if exec { try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path) }
        }
        return v
    }

    func cleanUp() { try? FileManager.default.removeItem(at: dir) }
}

@Suite("Recovery: PTY driver")
struct PTYDriverTests {
    let rules: [PTYDriver.Rule] = [.init("password", .password), .init("(y/n)", .text("y"))]

    @Test func sendsThePasswordOnlyWithEchoOffAndNeverShowsIt() throws {
        let f = try FakeTools(); defer { f.cleanUp() }
        let out = try PTYDriver(argv: [f.tools.bputil, "-nc", "-v", "VG"], rules: rules, timeout: 20).run(password: Data(f.password.utf8))
        #expect(out.status == 0 && out.passwordSent)
        #expect(out.transcript.contains("Continue? (y/n)") && out.transcript.contains("Policy updated."))
        #expect(!out.transcript.contains(f.password))
        #expect(!f.log.joined().contains(f.password), "never in argv")
    }

    @Test func refusesToTypeWhenEchoIsOn() throws {
        let f = try FakeTools(echoOff: false); defer { f.cleanUp() }
        #expect(throws: PTYDriver.Failure.echoOn) {
            try PTYDriver(argv: [f.tools.bputil, "-nc", "-v", "VG"], rules: rules, timeout: 20).run(password: Data(f.password.utf8))
        }
        let got = (try? String(contentsOf: f.dir.appendingPathComponent("bputil-received"), encoding: .utf8)) ?? ""
        #expect(!got.contains(f.password))
    }

    @Test func aWrongPasswordFailsAndIsExplained() throws {
        let f = try FakeTools(); defer { f.cleanUp() }
        let out = try PTYDriver(argv: [f.tools.bputil, "-nc", "-v", "VG"], rules: rules, timeout: 20).run(password: Data("wrong".utf8))
        #expect(out.status == 1 && out.transcript.contains("Incorrect password"))
        #expect(RecoverySetup.explain(out.transcript, tool: "bputil").contains("didn't work"))
    }

    @Test func aToolThatNeverAnswersTimesOut() throws {
        #expect(throws: PTYDriver.Failure.self) { try PTYDriver(argv: ["/bin/sleep", "5"], rules: rules, timeout: 0.5).run(password: Data("x".utf8)) }
    }
}

@Suite("Recovery: setup steps with fake tools")
struct RecoverySetupTests {
    @Test func runsEveryStepInOrderAndResumes() throws {
        let f = try FakeTools(); defer { f.cleanUp() }
        let vol = try f.makeVolume()
        #expect(f.tools != RecoveryTools.system)
        let s = RecoverySetup(volume: vol, tools: f.tools, requireRecoveryOS: false)
        _ = try s.gate()
        #expect(s.vgid == "11111111-2222-3333-4444-555555555555")
        try s.finish(password: Data(f.password.utf8))
        let log = f.log
        #expect(log.contains("fake-bputil -nc -v 11111111-2222-3333-4444-555555555555"))
        let km = try #require(log.first { $0.hasPrefix("fake-kmutil") })
        #expect(km.contains("configure-boot -c \(vol.path)/SiliconForest Setup.app/Contents/Resources/boot.bin --raw --entry-point 2048 --lowest-virtual-address 0 -v \(vol.path)"))
        #expect(log.contains("fake-bless --mount \(vol.path) --setBoot --nextonly"))
        #expect(FileManager.default.fileExists(atPath: vol.appendingPathComponent("IAPhysicalMedia-disabled.plist").path))
        #expect(FileManager.default.fileExists(atPath: vol.appendingPathComponent("System/Library/CoreServices/SystemVersion.plist").path))
        #expect(RecoverySetup.Step.allCases.allSatisfy(s.isDone))
        #expect(!s.log.joined().contains(f.password))
        // Re-entering recovery: nothing runs twice.
        let again = RecoverySetup(volume: vol, tools: f.tools, requireRecoveryOS: false)
        _ = try again.gate()
        try again.finish(password: Data(f.password.utf8))
        #expect(f.log.filter { $0.hasPrefix("fake-bputil -nc") }.count == 1 && f.log.filter { $0.hasPrefix("fake-kmutil") }.count == 1)
    }

    @Test func theGateFailsClosedOnTheWrongRecovery() throws {
        let f = try FakeTools(policy: "Paired: Yes\nBooted from macOS recoveryOS"); defer { f.cleanUp() }
        let s = RecoverySetup(volume: try f.makeVolume(), tools: f.tools, requireRecoveryOS: false)
        #expect(throws: RecoverySetup.Failure.self) { try s.gate() }
        #expect(!f.log.contains { $0.contains("-nc") })
        // And with the real checks on (this Mac is not in recoveryOS): refused before any tool runs.
        let real = RecoverySetup(volume: try f.makeVolume(), tools: f.tools, requireRecoveryOS: true)
        #expect(throws: RecoverySetup.Failure.self) { try real.gate() }
    }

    @Test func aKmutilFailureStopsAfterThePolicyStep() throws {
        let f = try FakeTools(kmutilFails: true); defer { f.cleanUp() }
        let s = RecoverySetup(volume: try f.makeVolume(), tools: f.tools, requireRecoveryOS: false)
        _ = try s.gate()
        #expect(throws: RecoverySetup.Failure.self) { try s.finish(password: Data(f.password.utf8)) }
        #expect(s.isDone(.R20) && !s.isDone(.R30) && !s.isDone(.R40))
    }
}

/// Preview13: macOS's Recovery vs the stub's own, the owners, and the username prompt. Fake tools only.
@Suite("Recovery: macOS Recovery detection, owners and the username prompt")
struct RecoveryPreview13Tests {
    @Test func macOSRecoveryIsNamedBeforeAnyToolRuns() throws {
        // `bputil -d` for the running recovery: an ordinary recovery OS, not paired (what Options boots).
        let f = try FakeTools(policy: "Paired: No\nBooted from ordinary recovery OS\nNot Paired"); defer { f.cleanUp() }
        let s = RecoverySetup(volume: try f.makeVolume(), tools: f.tools, requireRecoveryOS: false, detectMacOSRecovery: true)
        do { _ = try s.gate(); Issue.record("expected the gate to refuse") } catch let e as RecoverySetup.Failure {
            #expect(e.kind == .macOSRecovery && e.message.hasPrefix("This is macOS Recovery, not SiliconForest's."))
            #expect(e.message.contains("Loading startup options") && e.message.contains("not Options"))
        }
        #expect(!f.log.contains { $0.contains("-nc") || $0.hasPrefix("fake-kmutil") }, "nothing was changed")
    }

    @Test func theStubsOwnRecoveryPassesTheDetector() throws {
        let f = try FakeTools(); defer { f.cleanUp() }
        let s = RecoverySetup(volume: try f.makeVolume(), tools: f.tools, requireRecoveryOS: false, detectMacOSRecovery: true)
        _ = try s.gate()
        #expect(f.log.contains("fake-bputil -d") && f.log.contains("fake-bputil -d -v 11111111-2222-3333-4444-555555555555"))
    }

    @Test func aRunningRecoveryThatIsTheStubsButAGroupWithoutOneTrueRecoveryIsMacOSRecoveryToo() throws {
        let f = try FakeTools(vgPolicy: "Paired: Yes\nBooted from macOS recoveryOS"); defer { f.cleanUp() }
        let s = RecoverySetup(volume: try f.makeVolume(), tools: f.tools, requireRecoveryOS: false, detectMacOSRecovery: true)
        #expect(throws: RecoverySetup.Failure.self) { try s.gate() }
    }

    @Test func theDetectorsSignals() {
        #expect(RecoverySetup.isMacOSRecovery(running: "Not Paired\nordinary recovery OS", volumePath: "/Volumes/SiliconForest"))
        #expect(RecoverySetup.isMacOSRecovery(running: "Paired: Yes\nBooted from one true recoveryOS\nNot Paired", volumePath: "/x"))
        #expect(!RecoverySetup.isMacOSRecovery(running: "Paired: Yes\nBooted from one true recoveryOS", volumePath: "/Volumes/SiliconForest"))
        #expect(RecoverySetup.isMacOSRecovery(running: "", volumePath: "/Volumes/SiliconForest"), "bputil silent: mounted under /Volumes is macOS Recovery's way")
        #expect(!RecoverySetup.isMacOSRecovery(running: "", volumePath: "/System/Volumes/SiliconForest"))
    }

    @Test func theNamedScreenIsTemplatedInTheSharedCopy() {
        #expect(StartupOptionsCopy.macOSRecoveryTitle == "This is macOS Recovery, not SiliconForest's.")
        let steps = StartupOptionsCopy.macOSRecoverySteps("SiliconForest")
        #expect(steps.count == 3 && steps[0].contains("Shut Down") && steps[1].contains("Loading startup options") && steps[2] == "Choose SiliconForest, not Options.")
        #expect(Copy.InRecovery.macOSRecoveryTitle == StartupOptionsCopy.macOSRecoveryTitle && Copy.InRecovery.shutDown == "Shut Down")
    }

    @Test func ownersComeFromThePlanThenFromAdminUserRecoveryInfo() throws {
        let f = try FakeTools(); defer { f.cleanUp() }
        let vol = try f.makeVolume()
        let s = RecoverySetup(volume: vol, tools: f.tools, requireRecoveryOS: false)
        let plain = try s.gate()
        #expect(plain.owners == nil && s.owners(plan: plain, preboot: []).isEmpty, "no owners anywhere: the generic copy")
        // From the plan.
        let planned = RecoverySetup.Plan(job: "j", installID: "i", stub: "S", boot: "B", root: "R", planDigest: "d",
                                         owners: [.init(short: "chris", full: "Chris Kearney"), .init(short: "cat", full: "")], owner: "cat")
        let o = s.owners(plan: planned)
        #expect(o.map(\.short) == ["chris", "cat"] && o[0].display == "Chris Kearney" && o[1].display == "cat")
        // From the stub's Preboot (layout undocumented: read tolerantly).
        let info = ["accounts": [["username": "connor", "fullName": "Connor K"], ["shortName": "guest.x", "RealName": "Guest"], ["username": "-bad"]]] as [String: Any]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        let file = f.dir.appendingPathComponent("AdminUserRecoveryInfo.plist"); try data.write(to: file)
        let found = s.owners(plan: plain, preboot: [file])
        #expect(found.map(\.short) == ["connor", "guest.x"] && found.first?.full == "Connor K")
        #expect(RecoverySetup.parseAdminUserRecoveryInfo(Data("not a plist".utf8)).isEmpty)
    }

    @Test func thePlanRoundTripsWithOwnersAndOldPlansStillDecode() throws {
        let p = RecoverySetup.Plan(job: "j", installID: "i", stub: "S", boot: "B", root: "R", planDigest: "d", owners: [.init(short: "chris", full: "Chris K")], owner: "chris")
        let back = try JSONDecoder().decode(RecoverySetup.Plan.self, from: JSONEncoder().encode(p))
        #expect(back.owners == [.init(short: "chris", full: "Chris K")] && back.owner == "chris")
        let old = try JSONDecoder().decode(RecoverySetup.Plan.self, from: Data(#"{"job":"j","installID":"a","stub":"S","boot":"B","root":"R","planDigest":"d"}"#.utf8))
        #expect(old.owners == nil && old.owner == nil)
    }

    @Test func aUsernamePromptIsAnsweredWithTheOwnersShortNameAndTheRedactionHolds() throws {
        let f = try FakeTools(owner: "chris.k"); defer { f.cleanUp() }
        let vol = try f.makeVolume()
        let s = RecoverySetup(volume: vol, tools: f.tools, requireRecoveryOS: false)
        _ = try s.gate()
        try s.finish(password: Data(f.password.utf8), owner: "chris.k")
        #expect((try? String(contentsOf: f.dir.appendingPathComponent("bputil-user"), encoding: .utf8)) == "chris.k")
        #expect((try? String(contentsOf: f.dir.appendingPathComponent("kmutil-user"), encoding: .utf8)) == "chris.k")
        #expect(RecoverySetup.Step.allCases.allSatisfy(s.isDone))
        #expect(!s.log.joined().contains(f.password) && !f.log.joined().contains(f.password), "redacted and never in argv")
        #expect(!f.log.joined().contains("chris.k"), "the name is typed on the terminal, not passed as an argument")
    }

    @Test func theUsernameRuleNeverAnswersAPasswordPromptAndNeedsAnOwner() throws {
        #expect(RecoverySetup.rules(owner: nil).allSatisfy { if case .text(let t) = $0.reply { return t == "y" } else { return true } })
        let rules = RecoverySetup.rules(owner: "chris")
        let user = rules.filter { if case .text(let t) = $0.reply { return t == "chris" } else { return false } }
        #expect(!user.isEmpty && user.allSatisfy { $0.unless == "password" })
        #expect(RecoverySetup.rules(owner: "-x").count == RecoverySetup.rules(owner: nil).count, "an owner that isn't a plain account name is dropped")
        // The user-name tool answered with the password-prompting variant: "Enter the password for user chris" is a password prompt.
        let f = try FakeTools(); defer { f.cleanUp() }
        let out = try PTYDriver(argv: [f.tools.bputil, "-nc", "-v", "VG"], rules: rules, timeout: 20).run(password: Data(f.password.utf8))
        #expect(out.status == 0 && out.passwordSent, "'for user chris' alone doesn't trigger the username rule")
    }
}

@Suite("Recovery: sf-launcher and sf-step2.sh")
struct RecoveryScriptTests {
    func runLauncher(app status: Int32?, fakeExecutable: Bool = true) throws -> (Int32, Bool, String) {
        let f = try FakeTools(); defer { f.cleanUp() }
        let vol = try f.makeVolume()
        let macos = vol.appendingPathComponent("SiliconForest Setup.app/Contents/MacOS")
        let bin = macos.appendingPathComponent("SFRecovery")
        if let status {
            try "#!/bin/sh\nexit \(status)\n".write(to: bin, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: fakeExecutable ? 0o755 : 0o644], ofItemAtPath: bin.path)
        }
        let terminal = f.dir.appendingPathComponent("fake-terminal")
        try "#!/bin/sh\necho \"$@\" > '\(f.dir.path)/terminal-args'\nexit 0\n".write(to: terminal, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: terminal.path)
        let p = Process()
        p.executableURL = macos.appendingPathComponent("sf-launcher")
        p.environment = ["SF_TERMINAL": terminal.path, "PATH": "/usr/bin:/bin"]
        p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        let args = try? String(contentsOf: f.dir.appendingPathComponent("terminal-args"), encoding: .utf8)
        return (p.terminationStatus, args != nil, args ?? "")
    }

    @Test(arguments: [(0, false), (75, false), (1, true), (70, true), (134, true)])
    func launcherFallsBackToTerminalUnlessFinishedOrShutDown(status: Int32, fallsBack: Bool) throws {
        let (code, opened, args) = try runLauncher(app: status)
        #expect(code == 0)
        #expect(opened == fallsBack)
        if fallsBack { #expect(args.contains("Resources/sf-step2.sh")) }
    }

    @Test func aMissingOrBrokenAppAlsoFallsBack() throws {
        #expect(try runLauncher(app: nil).1, "missing binary")
        #expect(try runLauncher(app: 0, fakeExecutable: false).1, "not executable")
    }

    @Test func step2RunsTheSameStepsWithFakesAndResumes() throws {
        let f = try FakeTools(); defer { f.cleanUp() }
        let vol = try f.makeVolume()
        let script = vol.appendingPathComponent("SiliconForest Setup.app/Contents/Resources/sf-step2.sh")
        func run() throws -> Int32 {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = [script.path]
            var env = ["SF_TEST_MODE": "1", "PATH": "/usr/bin:/bin"]
            let t = f.tools
            env["SF_BPUTIL"] = t.bputil; env["SF_KMUTIL"] = t.kmutil; env["SF_BLESS"] = t.bless; env["SF_DISKUTIL"] = t.diskutil; env["SF_REBOOT"] = t.reboot
            p.environment = env
            let input = Pipe(); p.standardInput = input
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try p.run()
            input.fileHandleForWriting.write(Data("\(f.password)\ny\n\(f.password)\n\n".utf8)); try input.fileHandleForWriting.close()
            p.waitUntilExit()
            return p.terminationStatus
        }
        #expect(try run() == 0)
        let log = f.log
        #expect(log.contains("fake-bputil -nc -v 11111111-2222-3333-4444-555555555555"))
        #expect(log.contains { $0.hasPrefix("fake-kmutil configure-boot -c") && $0.contains("--raw --entry-point 2048 --lowest-virtual-address 0") })
        #expect(log.contains { $0.hasPrefix("fake-bless --mount") && $0.hasSuffix("--setBoot --nextonly") })
        #expect(FileManager.default.fileExists(atPath: f.dir.appendingPathComponent("rebooted").path))
        #expect(FileManager.default.fileExists(atPath: vol.appendingPathComponent("System/Library/CoreServices/SystemVersion.plist").path))
        // Shares state with SFRecovery: the app sees every step done.
        #expect(RecoverySetup(volume: vol, tools: f.tools, requireRecoveryOS: false).nextStep == nil)
        // Running it again changes nothing.
        #expect(try run() == 0)
        #expect(f.log.filter { $0.hasPrefix("fake-bputil -nc") }.count == 1)
    }

    @Test func step2IgnoresToolOverridesOutsideTestMode() throws {
        let text = try String(contentsOf: RecoveryPayload.directory.appendingPathComponent("sf-step2.sh"), encoding: .utf8)
        #expect(text.contains("BPUTIL=/usr/bin/bputil; KMUTIL=/usr/bin/kmutil"))
        #expect(text.contains("if [ \"${SF_TEST_MODE:-0}\" = 1 ]"))
    }
}
