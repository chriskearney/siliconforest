import Foundation

/// Paths of the Apple tools SFRecovery drives. `system` is the only set the app uses; tests build
/// their own set pointing at fake scripts and the real tools are never invoked by them.
public struct RecoveryTools: Sendable, Equatable {
    public var bputil, kmutil, bless, diskutil, reboot, shutdown: String
    public init(bputil: String, kmutil: String, bless: String, diskutil: String, reboot: String, shutdown: String) {
        self.bputil = bputil; self.kmutil = kmutil; self.bless = bless; self.diskutil = diskutil; self.reboot = reboot; self.shutdown = shutdown
    }
    public static let system = RecoveryTools(bputil: "/usr/bin/bputil", kmutil: "/usr/bin/kmutil", bless: "/usr/sbin/bless",
                                             diskutil: "/usr/sbin/diskutil", reboot: "/sbin/reboot", shutdown: "/sbin/shutdown")
}

/// The recovery steps (DESIGN §7.2), shared with sf-step2.sh through the same state markers in
/// `SFInstall/state/`, so the app and the Terminal fallback resume each other's work.
public final class RecoverySetup {
    public enum Step: String, CaseIterable, Sendable { case R10, R20, R30, R40, R50 }

    public struct Failure: Error, LocalizedError, Equatable {
        /// What kind of "no" it is, so the app can show a named screen for the one that has a fix.
        public enum Kind: Sendable, Equatable { case other, notRecoveryOS, macOSRecovery }
        public var step: Step
        public var message: String
        public var kind: Kind = .other
        public var errorDescription: String? { message }
    }

    /// A Mac user who can authorise the change: the short name `bputil`/`kmutil` ask for, and the name people know.
    public struct Owner: Codable, Sendable, Equatable, Hashable {
        public var short: String
        public var full: String
        public init(short: String, full: String) { self.short = short; self.full = full }
        public var display: String { full.isEmpty ? short : full }
    }

    /// SFInstall/plan.json. Preview13: `owners` and `owner` are written at S60 from the volume owners the helper
    /// found (and the one whose login the person gave for bless, when they did); older plans have neither.
    public struct Plan: Codable, Sendable {
        public var job: String; public var installID: String; public var stub: String; public var boot: String; public var root: String; public var planDigest: String
        public var owners: [Owner]?
        public var owner: String?
    }

    /// The stub's System volume (the app runs from inside it).
    public let volume: URL
    public let tools: RecoveryTools
    /// Fail-closed recoveryOS checks; off only in tests, which can't be in recoveryOS.
    public let requireRecoveryOS: Bool
    /// Whether the gate tells macOS's Recovery from the stub's own (on with `requireRecoveryOS`; tests turn it on alone).
    public let detectMacOSRecovery: Bool
    public var log: [String] = []
    public private(set) var vgid: String?

    public init(volume: URL, tools: RecoveryTools = .system, requireRecoveryOS: Bool = true, detectMacOSRecovery: Bool? = nil) {
        self.volume = volume; self.tools = tools; self.requireRecoveryOS = requireRecoveryOS
        self.detectMacOSRecovery = detectMacOSRecovery ?? requireRecoveryOS
    }

    /// The volume that holds `SiliconForest Setup.app` this executable is in.
    public static func volume(forExecutable url: URL) -> URL {
        url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// The accounts that can authorise this change: the plan's owners (written at install), else any found in the
    /// stub's Preboot `AdminUserRecoveryInfo.plist`. Empty means "your Mac login password", with no name.
    public func owners(plan: Plan, preboot: [URL]? = nil) -> [Owner] {
        if let o = plan.owners, !o.isEmpty { return o }
        let candidates = preboot ?? vgid.map { g in
            ["/System/Volumes/Preboot", "/Volumes/Preboot"].map { URL(fileURLWithPath: $0).appendingPathComponent(g).appendingPathComponent("var/db/AdminUserRecoveryInfo.plist") }
        } ?? []
        for u in candidates { if let data = try? Data(contentsOf: u) { let found = Self.parseAdminUserRecoveryInfo(data); if !found.isEmpty { return found } } }
        return []
    }

    /// `AdminUserRecoveryInfo.plist`: read tolerantly (its layout isn't documented): every dictionary that has a
    /// short-name key and, optionally, a full-name key is an account.
    public static func parseAdminUserRecoveryInfo(_ data: Data) -> [Owner] {
        guard let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else { return [] }
        var out: [Owner] = []
        func walk(_ v: Any) {
            if let d = v as? [String: Any] {
                let short = ["username", "UserName", "shortName", "ShortName", "name", "Name"].compactMap { d[$0] as? String }.first
                let full = ["fullName", "FullName", "realName", "RealName", "longName", "LongName"].compactMap { d[$0] as? String }.first
                if let short, valid(short), !out.contains(where: { $0.short == short }) { out.append(Owner(short: short, full: full ?? "")) }
                for (_, x) in d { walk(x) }
            } else if let a = v as? [Any] { a.forEach(walk) }
        }
        walk(root)
        return out
    }

    /// A macOS short account name: nothing that could be an option or a path, and never a password-like string.
    static func valid(_ s: String) -> Bool {
        s.range(of: #"^[A-Za-z0-9._][A-Za-z0-9._-]{0,63}$"#, options: .regularExpression) != nil
    }

    /// The prompt rules for `bputil -nc` and `kmutil configure-boot`. They ask for a user name (when the tool
    /// does) and then the password. The user-name rule only fires when the prompt isn't also asking for a password.
    /// Wording as seen in Asahi's second-stage installer and bputil's own: "Enter the username …", "Enter the password …".
    /// With no owner known the user-name rule is left out and the tool's own default (or prompt) applies.
    static func rules(owner: String?) -> [PTYDriver.Rule] {
        var r: [PTYDriver.Rule] = []
        if let owner, valid(owner) {
            for key in ["username", "user name", "name of an administrator", "name of an admin"] { r.append(.init(key, .text(owner), unless: "password")) }
        }
        r += [.init("password", .password), .init("(y/n)", .text("y")), .init("[y/n]", .text("y"))]
        return r
    }

    var stateDir: URL { volume.appendingPathComponent("SFInstall/state", isDirectory: true) }
    public func isDone(_ s: Step) -> Bool { FileManager.default.fileExists(atPath: stateDir.appendingPathComponent("\(s.rawValue).done").path) }
    func markDone(_ s: Step) throws {
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: stateDir.appendingPathComponent("\(s.rawValue).done").path, contents: Data())
    }
    public var nextStep: Step? { Step.allCases.first { !isDone($0) } }

    func run(_ argv: [String]) throws -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0]); p.arguments = Array(argv.dropFirst())
        let out = Pipe(); p.standardOutput = out; p.standardError = out; p.standardInput = FileHandle.nullDevice
        try p.run()
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        try? out.fileHandleForReading.close(); try? out.fileHandleForWriting.close()
        let text = String(decoding: d, as: UTF8.self)
        log.append("$ \(argv.joined(separator: " "))\n\(text)")
        return (p.terminationStatus, text)
    }

    // MARK: R10 gate, fail closed

    public func gate() throws -> Plan {
        if requireRecoveryOS {
            guard FileManager.default.fileExists(atPath: "/System/Installation/CDIS") else {
                throw Failure(step: .R10, message: "This isn't recoveryOS. Shut down, then hold the power button until you see “Loading startup options”, and choose SiliconForest, not Options.", kind: .notRecoveryOS)
            }
            guard geteuid() == 0 else { throw Failure(step: .R10, message: "SiliconForest Setup must run as the recoveryOS user.") }
        }
        let planURL = volume.appendingPathComponent("SFInstall/plan.json")
        guard let data = try? Data(contentsOf: planURL), let plan = try? JSONDecoder().decode(Plan.self, from: data) else {
            throw Failure(step: .R10, message: "The installer's plan is missing from this volume.")
        }
        let (s1, info) = try run([tools.diskutil, "info", "-plist", volume.path])
        guard s1 == 0, let d = try? PropertyListSerialization.propertyList(from: Data(info.utf8), format: nil) as? [String: Any],
              let group = d["APFSVolumeGroupID"] as? String, !group.isEmpty else {
            throw Failure(step: .R10, message: "Couldn't find this volume's group.")
        }
        vgid = group
        // macOS's own Recovery (the person chose Options): `bputil -d` for the recovery that is running says
        // "ordinary recovery OS" and not paired, and the stub's group has no "one true recoveryOS". The stub is only
        // mounted under /Volumes there, and nothing reads its .IAPhysicalMedia, so Setup would never have launched
        // by itself; if it was opened by hand it must not run bputil/kmutil against the wrong recovery.
        if detectMacOSRecovery, Self.isMacOSRecovery(running: try run([tools.bputil, "-d"]).1, volumePath: volume.path) {
            throw Self.macOSRecoveryFailure
        }
        let (_, policy) = try run([tools.bputil, "-d", "-v", group])
        guard policy.contains("one true recoveryOS") else {
            if detectMacOSRecovery { throw Self.macOSRecoveryFailure }
            throw Failure(step: .R10, message: Self.notOwnRecoveryMessage)
        }
        guard policy.contains("Paired") else { throw Failure(step: .R10, message: "This recovery isn't paired with SiliconForest.") }
        try markDone(.R10)
        return plan
    }

    public static let notOwnRecoveryMessage = "This is macOS Recovery, not SiliconForest's. Shut down, hold the power button until you see “Loading startup options”, and choose SiliconForest, not Options."
    static var macOSRecoveryFailure: Failure { Failure(step: .R10, message: notOwnRecoveryMessage, kind: .macOSRecovery) }

    /// Whether the recovery that is running is macOS's own rather than the stub's. `running` is `bputil -d` (no
    /// `-v`: the booted group). Fails safe: when bputil says nothing at all, the stub mounted under /Volumes/
    /// (which is where macOS's Recovery mounts a volume it didn't boot from) is the signal.
    public static func isMacOSRecovery(running: String, volumePath: String) -> Bool {
        let t = running.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return volumePath.hasPrefix("/Volumes/") }
        return !(t.contains("one true recoveryOS") && !t.contains("Not Paired"))
    }

    // MARK: R20, R30 (PTY, password)

    public func allowSiliconForest(password: Data, owner: String? = nil) throws -> PTYDriver.Outcome? {
        guard !isDone(.R20) else { return nil }
        guard let vgid else { throw Failure(step: .R20, message: "Run the gate first.") }
        let d = PTYDriver(argv: [tools.bputil, "-nc", "-v", vgid], rules: Self.rules(owner: owner))
        let out = try d.run(password: password)
        log.append("$ bputil -nc -v \(vgid)\n\(out.transcript)")
        guard out.status == 0 else { throw Failure(step: .R20, message: Self.explain(out.transcript, tool: "bputil")) }
        let (_, policy) = try run([tools.bputil, "-d", "-v", vgid])
        guard policy.contains("Permissive") else { throw Failure(step: .R20, message: "The security policy didn't change to Permissive.") }
        try markDone(.R20)
        return out
    }

    public func installBootObject(password: Data, owner: String? = nil) throws -> PTYDriver.Outcome? {
        guard !isDone(.R30) else { return nil }
        let boot = volume.appendingPathComponent("SiliconForest Setup.app/Contents/Resources/boot.bin")
        let d = PTYDriver(argv: [tools.kmutil, "configure-boot", "-c", boot.path, "--raw", "--entry-point", "2048",
                                 "--lowest-virtual-address", "0", "-v", volume.path],
                          rules: Self.rules(owner: owner))
        let out = try d.run(password: password)
        log.append("$ kmutil configure-boot …\n\(out.transcript)")
        guard out.status == 0 else { throw Failure(step: .R30, message: Self.explain(out.transcript, tool: "kmutil")) }
        try markDone(.R30)
        return out
    }

    // MARK: R40, R50

    public func cleanUpMarkers() throws {
        guard !isDone(.R40) else { return }
        let fm = FileManager.default
        let marker = volume.appendingPathComponent(".IAPhysicalMedia")
        if fm.fileExists(atPath: marker.path) { try fm.moveItem(at: marker, to: volume.appendingPathComponent("IAPhysicalMedia-disabled.plist")) }
        let core = volume.appendingPathComponent("System/Library/CoreServices")
        let hidden = core.appendingPathComponent("SystemVersion.plist.sf-hidden")
        if fm.fileExists(atPath: hidden.path) { try fm.moveItem(at: hidden, to: core.appendingPathComponent("SystemVersion.plist")) }
        try markDone(.R40)
    }

    /// R50: after `kmutil configure-boot`, a ONE-TIME selection of the stub, run in recoveryOS with its own tools.
    /// (S65 in macOS made the stub the persistent startup disk; this is the only `--nextonly` bless left. It makes
    /// the restart that follows go to SiliconForest even if the person changed the startup disk in between.)
    /// It does not set the persistent default back: the startup disk stays on SiliconForest until Remove (U10)
    /// or the person chooses macOS in Startup Disk. See ENGINE.md, "R50 and the persistent startup disk".
    public func setNextBoot() throws {
        guard !isDone(.R50) else { return }
        let (s, out) = try run([tools.bless, "--mount", volume.path, "--setBoot", "--nextonly"])
        guard s == 0 else { throw Failure(step: .R50, message: "Couldn't choose SiliconForest for the next startup. \(out.suffix(160))") }
        try markDone(.R50)
    }

    /// Everything after the gate, in order, skipping finished steps.
    public func finish(password: Data, owner: String? = nil) throws {
        _ = try allowSiliconForest(password: password, owner: owner)
        _ = try installBootObject(password: password, owner: owner)
        try cleanUpMarkers()
        try setNextBoot()
    }

    static func explain(_ transcript: String, tool: String) -> String {
        let t = transcript.lowercased()
        if t.contains("user not found") || t.contains("unknown user") { return "\(tool) couldn't find that user. Use the macOS owner's account." }
        if t.contains("incorrect") || t.contains("invalid password") || t.contains("authentication") { return "That password didn't work. Try again." }
        return "\(tool) failed: \(transcript.split(separator: "\n").suffix(2).joined(separator: " "))"
    }
}
