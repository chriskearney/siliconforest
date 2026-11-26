import Foundation
import Testing
@testable import SFHelperKit
import SFEngine
import SFLiveDisk
import SFAppEngine
import SFIdentity

/// Preview10: the up-front privilege check, opening System Settings only on a click, and the logs.
private final class FakeMac: @unchecked Sendable {
    let lock = NSLock()
    var status: HelperRegistrationState = .enabled
    var afterRegister: HelperRegistrationState = .requiresApproval
    var fda: [PrivilegeReport.FullDiskAccess] = [.granted]   // one per probe; the last one repeats
    var probeError: Error?
    var registers = 0, unregisters = 0, reconnects = 0, probes = 0, loginItemsOpens = 0, fdaOpens = 0
    var tracksBuild = false
    var currentBuild = "0.1.0-preview12/26"
    var storedBuild: String?
    /// Errors consumed in order by the probe; `probeError` is used when this is empty.
    var probeErrors: [Error] = []

    var hooks: PrivilegeGate.Hooks {
        PrivilegeGate.Hooks(
            register: { [self] in lock.lock(); defer { lock.unlock() }; registers += 1; status = afterRegister; return status },
            status: { [self] in lock.lock(); defer { lock.unlock() }; return status },
            probe: { [self] in
                lock.lock(); defer { lock.unlock() }
                probes += 1
                if !probeErrors.isEmpty { throw probeErrors.removeFirst() }
                if let probeError { throw probeError }
                let v = fda.count > 1 ? fda.removeFirst() : fda[0]
                return PrivilegeReport(fullDiskAccess: v, probe: "/dev/rdisk0", detail: v == .missing ? "Operation not permitted" : nil)
            },
            openLoginItems: { [self] in lock.lock(); loginItemsOpens += 1; lock.unlock() },
            openFullDiskAccess: { [self] in lock.lock(); fdaOpens += 1; lock.unlock() },
            unregister: { [self] in lock.lock(); defer { lock.unlock() }; unregisters += 1; status = .notRegistered; return status },
            reconnect: { [self] in lock.lock(); reconnects += 1; lock.unlock() },
            build: tracksBuild ? HelperBuildMemory(current: currentBuild, read: { [self] in lock.lock(); defer { lock.unlock() }; return storedBuild }, write: { [self] v in lock.lock(); storedBuild = v; lock.unlock() }) : nil)
    }
}

@Suite("Privileges: the up-front check")
struct PrivilegeGateTests {
    @Test func alreadyGrantedIsReadyAtOnce() {
        let mac = FakeMac()
        let g = PrivilegeGate(mac.hooks)
        #expect(g.check(byPerson: true) == .ready)
        #expect(mac.registers == 0, "an enabled helper isn't registered again")
        #expect(mac.loginItemsOpens == 0 && mac.fdaOpens == 0, "nothing opens System Settings by itself")
    }

    @Test func fullDiskAccessMissingThenGranted() {
        let mac = FakeMac()
        mac.fda = [.missing, .missing, .granted]
        let g = PrivilegeGate(mac.hooks)
        guard case .needsFullDiskAccess(let r) = g.check(byPerson: true) else { Issue.record("expected the Full Disk Access stage"); return }
        #expect(r.probe == "/dev/rdisk0" && r.detail == "Operation not permitted")
        #expect(g.stage.isWaiting)
        g.userOpensFullDiskAccess()
        #expect(g.check(byPerson: false) == g.stage)
        #expect(g.check(byPerson: false) == .ready)
        #expect(mac.fdaOpens == 1, "one click, one open")
        #expect(mac.loginItemsOpens == 0)
    }

    @Test func helperApprovalThenFullDiskAccessThenReady() {
        let mac = FakeMac()
        mac.status = .notRegistered
        mac.afterRegister = .requiresApproval
        mac.fda = [.missing, .granted]
        let g = PrivilegeGate(mac.hooks)
        #expect(g.check(byPerson: true) == .needsHelperApproval)
        #expect(mac.registers == 1)
        // The person approves in Login Items; the quiet poll sees it.
        mac.status = .enabled
        if case .needsFullDiskAccess = g.check(byPerson: false) {} else { Issue.record("expected Full Disk Access next") }
        #expect(g.check(byPerson: false) == .ready)
        #expect(mac.registers == 1, "the quiet checks never register again")
    }

    @Test func deniedOrRefusedFails() {
        let mac = FakeMac()
        mac.status = .refused("Move SiliconForest Installer to the Applications folder, then open it again.")
        let g = PrivilegeGate(mac.hooks)
        #expect(g.check(byPerson: true) == .failed("Move SiliconForest Installer to the Applications folder, then open it again."))
        #expect(!g.stage.isWaiting)
        #expect(mac.probes == 0)

        let mac2 = FakeMac()
        mac2.afterRegister = .enabled
        mac2.probeError = NSError(domain: NSCocoaErrorDomain, code: 4099, userInfo: [NSLocalizedDescriptionKey: "The connection was invalidated."])
        let g2 = PrivilegeGate(mac2.hooks)
        guard case .failed(let m) = g2.check(byPerson: true) else { Issue.record("expected failed"); return }
        #expect(m.contains("didn't answer") && m.contains("invalidated"))
        #expect(mac2.unregisters == 1 && mac2.registers == 1 && mac2.reconnects == 1, "one restart, then the same error is a failure")
        #expect(mac2.probes == 2)
    }

    @Test func fullDiskAccessStaysDeniedKeepsWaiting() {
        let mac = FakeMac()
        mac.fda = [.missing]
        let g = PrivilegeGate(mac.hooks)
        for _ in 0..<20 { _ = g.check(byPerson: false) }
        if case .needsFullDiskAccess = g.stage {} else { Issue.record("still waiting for Full Disk Access") }
        #expect(mac.fdaOpens == 0 && mac.loginItemsOpens == 0)
    }

    @Test func loginItemsOpensExactlyOncePerClick() {
        let mac = FakeMac()
        mac.status = .requiresApproval
        let g = PrivilegeGate(mac.hooks)
        #expect(g.check(byPerson: true) == .needsHelperApproval)
        for _ in 0..<50 { _ = g.check(byPerson: false) }    // 100 s of quiet polling
        #expect(mac.loginItemsOpens == 0, "polling never opens System Settings (preview9 reopened it every 2 s)")
        g.userOpensLoginItems()
        for _ in 0..<50 { _ = g.check(byPerson: false) }
        #expect(mac.loginItemsOpens == 1)
        g.userOpensLoginItems()
        #expect(mac.loginItemsOpens == 2 && g.loginItemsOpened == 2)
        #expect(mac.registers == 0, "requiresApproval is waited on, not re-registered")
    }

    @Test func aRestartingHelperDuringQuietChecksKeepsWaiting() {
        let mac = FakeMac()
        mac.fda = [.missing]
        let g = PrivilegeGate(mac.hooks)
        if case .needsFullDiskAccess = g.check(byPerson: true) {} else { Issue.record("expected Full Disk Access") }
        mac.probeError = NSError(domain: NSCocoaErrorDomain, code: 4097, userInfo: [NSLocalizedDescriptionKey: "connection interrupted"])
        if case .needsFullDiskAccess = g.check(byPerson: false) {} else { Issue.record("a quiet check keeps waiting") }
        mac.probeError = nil; mac.fda = [.granted]
        #expect(g.check(byPerson: false) == .ready)
    }

    @Test func unknownProbeDoesNotBlock() {
        let mac = FakeMac()
        mac.fda = [.unknown]
        #expect(PrivilegeGate(mac.hooks).check(byPerson: true) == .ready)
    }

    @Test func aStaleHelperIsRestartedOnceThenSucceeds() {
        let mac = FakeMac()
        mac.afterRegister = .enabled
        mac.probeErrors = [NSError(domain: NSCocoaErrorDomain, code: 4097, userInfo: [NSLocalizedDescriptionKey: "Couldn’t communicate with a helper application."])]
        let g = PrivilegeGate(mac.hooks)
        #expect(g.check(byPerson: true) == .ready)
        #expect(mac.unregisters == 1 && mac.registers == 1 && mac.reconnects == 1)
        #expect(mac.probes == 2)
        #expect(g.didStaleRefresh)
        #expect(g.check(byPerson: true) == .ready)
        #expect(mac.unregisters == 1, "the restart happens only once")
    }

    @Test func aNewAppBuildRestartsAnEnabledHelper() {
        let mac = FakeMac()
        mac.tracksBuild = true
        mac.storedBuild = "0.1.0-preview11/25"
        mac.afterRegister = .enabled
        let g = PrivilegeGate(mac.hooks)
        #expect(g.willRefreshHelper())
        #expect(g.check(byPerson: true) == .ready)
        #expect(mac.unregisters == 1 && mac.registers == 1 && mac.reconnects == 1)
        #expect(mac.storedBuild == "0.1.0-preview12/26")
        #expect(g.didBuildRefresh)
        #expect(!g.willRefreshHelper())
        #expect(g.check(byPerson: true) == .ready)
        #expect(mac.unregisters == 1, "the same build is not registered again")
    }

    @Test func theSameAppBuildDoesNotRestartTheHelper() {
        let mac = FakeMac()
        mac.tracksBuild = true
        mac.storedBuild = "0.1.0-preview12/26"
        let g = PrivilegeGate(mac.hooks)
        #expect(!g.willRefreshHelper())
        #expect(g.check(byPerson: true) == .ready)
        #expect(mac.unregisters == 0 && mac.registers == 0 && mac.reconnects == 0)
        #expect(mac.storedBuild == "0.1.0-preview12/26")
    }

    @Test func aBuildChangeDoesNotRestartAHelperThatIsNotEnabled() {
        let mac = FakeMac()
        mac.tracksBuild = true
        mac.storedBuild = "0.1.0-preview11/25"
        mac.status = .notRegistered
        mac.afterRegister = .enabled
        let g = PrivilegeGate(mac.hooks)
        #expect(!g.willRefreshHelper())
        #expect(g.check(byPerson: true) == .ready)
        #expect(mac.unregisters == 0 && mac.registers == 1 && mac.reconnects == 0, "a first-time register is not a restart")
        #expect(mac.storedBuild == "0.1.0-preview12/26")
    }

    @Test func staleHelperErrorsAreRecognised() {
        #expect(PrivilegeGate.isStaleHelperError(NSError(domain: NSCocoaErrorDomain, code: 4099, userInfo: [NSLocalizedDescriptionKey: "The connection was invalidated."])))
        #expect(PrivilegeGate.isStaleHelperError(NSError(domain: NSCocoaErrorDomain, code: 4097, userInfo: [NSLocalizedDescriptionKey: "Couldn’t communicate with a helper application."])))
        #expect(PrivilegeGate.isStaleHelperMessage("Exception: received a message that is not in the interface of the remote object"))
        #expect(!PrivilegeGate.isStaleHelperMessage("Move SiliconForest Installer to the Applications folder, then open it again."))
        #expect(PrivilegeStage.failed("The helper has Full Disk Access missing").failedMentionsFullDiskAccess)
        #expect(!PrivilegeStage.failed("The installer's helper didn't answer: The connection was invalidated.").failedMentionsFullDiskAccess)
        #expect(HelperBuildMemory(current: "0.1.0-preview12/26", read: { nil }, write: { _ in }).current == "0.1.0-preview12/26")
        #expect(HelperBuildMemory.stamp().contains("/"))
    }

    @Test func helperPathAndSettingsURL() {
        #expect(PrivilegeGate.helperPath(appBundle: URL(fileURLWithPath: "/Applications/SiliconForest Installer.app"))
                == "/Applications/SiliconForest Installer.app/Contents/MacOS/SFHelper")
        #expect(PrivilegeGate.fullDiskAccessURL.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        var tried: [String] = []
        _ = SystemLinks.open(.fullDiskAccess) { u in tried.append(u.absoluteString); return true }
        #expect(tried == ["x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"])
        #expect(HelperBundle.launchdPlist()["BundleProgram"] as? String == "Contents/MacOS/SFHelper")
    }
}

@Suite("Privileges: the helper's Full Disk Access probe")
struct FullDiskAccessProbeTests {
    @Test func grantedWhenTheRawDeviceOpens() {
        var opened: [(String, Int32)] = []
        let r = FullDiskAccessProbe.run(wholeDisk: { "disk0" }, opener: { p, f in opened.append((p, f)); return Darwin.open("/dev/null", O_RDONLY) }, euid: 0)
        #expect(r == PrivilegeReport(fullDiskAccess: .granted, probe: "/dev/rdisk0"))
        #expect(opened.count == 1 && opened[0].0 == "/dev/rdisk0" && opened[0].1 == O_RDONLY, "read-only, and nothing else")
    }

    @Test func missingWhenRootGetsEPERM() {
        let r = FullDiskAccessProbe.run(wholeDisk: { "disk0" }, opener: { _, _ in errno = EPERM; return -1 }, euid: 0)
        #expect(r.fullDiskAccess == .missing && r.probe == "/dev/rdisk0" && r.detail == String(cString: strerror(EPERM)))
    }

    @Test func fallsBackToAProtectedFileWithoutAStartupDisk() {
        var paths: [String] = []
        let r = FullDiskAccessProbe.run(wholeDisk: { nil }, opener: { p, _ in paths.append(p); errno = EPERM; return -1 }, euid: 0)
        #expect(paths == [FullDiskAccessProbe.protectedFile])
        #expect(r.fullDiskAccess == .missing)
    }

    @Test func notRootIsUnknownNotMissing() {
        let r = FullDiskAccessProbe.run(wholeDisk: { "disk0" }, opener: { _, _ in errno = EACCES; return -1 }, euid: 501)
        #expect(r.fullDiskAccess == .unknown)
    }

    @Test func rawOpenTypesTheDenial() {
        #expect(throws: FullDiskAccessDenied(path: "/dev/rdisk0", code: EPERM)) {
            _ = try RawAccess.open("/dev/rdisk0", O_RDONLY, opener: { _, _ in errno = EPERM; return -1 }, euid: 0)
        }
        #expect(FullDiskAccessDenied(path: "/dev/rdisk0", code: EPERM).errorDescription?.contains("Full Disk Access") == true)
        let ns = HelperService.nsError(FullDiskAccessDenied(path: "/dev/rdisk0", code: EPERM))
        #expect(ns.domain == HelperError.domain && ns.code == HelperErrorCode.needsFullDiskAccess.rawValue)
        #expect(ns.localizedFailureReason == "/dev/rdisk0")
    }

    @Test func theHelperVerbAnswersWithTheProbe() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sf-priv-\(UUID().uuidString)")
        var c = HelperConfig(target: .none, journalDirectory: dir, workDirectory: dir.appendingPathComponent("work"), profileID: "J293",
                             release: nil, releaseSource: nil,
                             policy: ConnectionPolicy(clientRequirement: "", minimumClientBuild: 0), idleTimeout: 60)
        c.privilegeProbe = { PrivilegeReport(fullDiskAccess: .missing, probe: "/dev/rdisk0", detail: "Operation not permitted") }
        let svc = HelperService(config: c, lifecycle: HelperLifecycle(idleTimeout: 60, onIdle: {}))
        var got: Data?
        svc.checkPrivileges { d, e in #expect(e == nil); got = d }
        let r = try Canonical.decoder().decode(PrivilegeReport.self, from: try #require(got))
        #expect(r.fullDiskAccess == .missing && r.probe == "/dev/rdisk0")
    }
}

@Suite("Logging: app and helper logs")
struct InstallerLogTests {
    @Test func paths() {
        #expect(InstallerLog.appLogURL(home: URL(fileURLWithPath: "/Users/connor")).path == "/Users/connor/Library/Logs/SiliconForest Installer/installer.log")
        #expect(InstallerLog.helperLogURL.path == "/Library/Logs/SiliconForest/helper.log")
        #expect(InstallerLog.subsystem == "org.siliconforest.installer")
    }

    @Test func writesLinesAndCreatesTheFolder() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sf-log-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let url = InstallerLog.appLogURL(home: home)
        let log = InstallerLog(file: url, category: "app")
        log.clock = { Date(timeIntervalSince1970: 1_800_000_000) }
        log.info("privileges: ready")
        log.error("plan failed: macOS denied SFHelper access to /dev/rdisk0\nsecond line")
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].hasSuffix("INFO [app] privileges: ready"))
        #expect(lines[1].contains("ERROR [app] plan failed") && lines[1].contains("⏎ second line"))
        #expect(lines[0].hasPrefix("2027-01-15T"))
    }

    @Test func neverLogsSecrets() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sf-log-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let log = InstallerLog(file: InstallerLog.appLogURL(home: home), category: "app")
        log.info("bless password=hunter2 token: abc123 Authorization=\"Bearer xyz\" ok")
        let text = try String(contentsOf: InstallerLog.appLogURL(home: home), encoding: .utf8)
        for secret in ["hunter2", "abc123", "Bearer xyz"] { #expect(!text.contains(secret), "\(secret) leaked") }
        #expect(text.contains("password=<redacted>") && text.contains("ok"))
    }

    @Test func helperVerbFailuresAreLogged() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sf-log-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent("helper.log")
        let dir = home.appendingPathComponent("j")
        var c = HelperConfig(target: .none, journalDirectory: dir, workDirectory: dir.appendingPathComponent("work"), profileID: "J293",
                             release: nil, releaseSource: nil,
                             policy: ConnectionPolicy(clientRequirement: "", minimumClientBuild: 0), idleTimeout: 60)
        c.log = InstallerLog(file: file, category: "helper")
        let svc = HelperService(config: c, lifecycle: HelperLifecycle(idleTimeout: 60, onIdle: {}))
        var err: NSError?
        svc.readTopology { _, e in err = e }
        #expect(err?.code == HelperErrorCode.noTarget.rawValue)
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("ERROR [helper] readTopology failed: This build of the helper has no disk target"))
    }
}
