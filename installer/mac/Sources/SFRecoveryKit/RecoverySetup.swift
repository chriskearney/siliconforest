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
        public var step: Step
        public var message: String
        public var errorDescription: String? { message }
    }

    public struct Plan: Codable, Sendable { public var job: String; public var installID: String; public var stub: String; public var boot: String; public var root: String; public var planDigest: String }

    /// The stub's System volume (the app runs from inside it).
    public let volume: URL
    public let tools: RecoveryTools
    /// Fail-closed recoveryOS checks; off only in tests, which can't be in recoveryOS.
    public let requireRecoveryOS: Bool
    public var log: [String] = []
    public private(set) var vgid: String?

    public init(volume: URL, tools: RecoveryTools = .system, requireRecoveryOS: Bool = true) {
        self.volume = volume; self.tools = tools; self.requireRecoveryOS = requireRecoveryOS
    }

    /// The volume that holds `SiliconForest Setup.app` this executable is in.
    public static func volume(forExecutable url: URL) -> URL {
        url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
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
                throw Failure(step: .R10, message: "This isn't recoveryOS. Shut down, then hold the power button and choose SiliconForest.")
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
        let (_, policy) = try run([tools.bputil, "-d", "-v", group])
        guard policy.contains("one true recoveryOS") else {
            throw Failure(step: .R10, message: "This is not SiliconForest's own recovery. Shut down, hold the power button until you see startup options, and choose SiliconForest.")
        }
        guard policy.contains("Paired") else { throw Failure(step: .R10, message: "This recovery isn't paired with SiliconForest.") }
        try markDone(.R10)
        return plan
    }

    // MARK: R20, R30 (PTY, password)

    public func allowSiliconForest(password: Data) throws -> PTYDriver.Outcome? {
        guard !isDone(.R20) else { return nil }
        guard let vgid else { throw Failure(step: .R20, message: "Run the gate first.") }
        let d = PTYDriver(argv: [tools.bputil, "-nc", "-v", vgid],
                          rules: [.init("password", .password), .init("(y/n)", .text("y")), .init("[y/n]", .text("y"))])
        let out = try d.run(password: password)
        log.append("$ bputil -nc -v \(vgid)\n\(out.transcript)")
        guard out.status == 0 else { throw Failure(step: .R20, message: Self.explain(out.transcript, tool: "bputil")) }
        let (_, policy) = try run([tools.bputil, "-d", "-v", vgid])
        guard policy.contains("Permissive") else { throw Failure(step: .R20, message: "The security policy didn't change to Permissive.") }
        try markDone(.R20)
        return out
    }

    public func installBootObject(password: Data) throws -> PTYDriver.Outcome? {
        guard !isDone(.R30) else { return nil }
        let boot = volume.appendingPathComponent("SiliconForest Setup.app/Contents/Resources/boot.bin")
        let d = PTYDriver(argv: [tools.kmutil, "configure-boot", "-c", boot.path, "--raw", "--entry-point", "2048",
                                 "--lowest-virtual-address", "0", "-v", volume.path],
                          rules: [.init("password", .password), .init("(y/n)", .text("y")), .init("[y/n]", .text("y"))])
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

    public func setNextBoot() throws {
        guard !isDone(.R50) else { return }
        let (s, out) = try run([tools.bless, "--mount", volume.path, "--setBoot", "--nextonly"])
        guard s == 0 else { throw Failure(step: .R50, message: "Couldn't choose SiliconForest for the next startup. \(out.suffix(160))") }
        try markDone(.R50)
    }

    /// Everything after the gate, in order, skipping finished steps.
    public func finish(password: Data) throws {
        _ = try allowSiliconForest(password: password)
        _ = try installBootObject(password: password)
        try cleanUpMarkers()
        try setNextBoot()
    }

    static func explain(_ transcript: String, tool: String) -> String {
        let t = transcript.lowercased()
        if t.contains("user not found") { return "\(tool) couldn't find that user. Use the macOS owner's account." }
        if t.contains("incorrect") || t.contains("invalid password") || t.contains("authentication") { return "That password didn't work. Try again." }
        return "\(tool) failed: \(transcript.split(separator: "\n").suffix(2).joined(separator: " "))"
    }
}
