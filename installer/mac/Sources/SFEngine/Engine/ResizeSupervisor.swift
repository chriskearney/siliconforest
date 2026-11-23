import Foundation
import IOKit.pwr_mgt
import Darwin

/// A running (or finished) resize process.
public protocol ResizeProcess: AnyObject, Sendable {
    var pid: Int32 { get }
    /// Exit status once the process has exited and been reaped; nil while running, or when it
    /// exited in a previous helper whose status is lost.
    func exitStatus() -> Int32?
    func isRunning() -> Bool
}

/// Starts or finds resize processes. The supervisor asks the chokepoint to authorise the argv first.
public protocol ResizeLauncher: Sendable {
    func launch(_ argv: [String], log: URL) throws -> ResizeProcess
    func reattach(pid: Int32) -> ResizeProcess?
}

/// Children we spawned, with exit statuses once reaped, so a second supervisor in this process
/// (the "helper restarted" case in tests) still learns how its predecessor's child ended.
final class ChildRegistry: @unchecked Sendable {
    static let shared = ChildRegistry()
    private let lock = NSLock()
    private var exits: [Int32: Int32] = [:]
    private var children: Set<Int32> = []

    func add(_ pid: Int32) { lock.lock(); children.insert(pid); lock.unlock() }
    func isChild(_ pid: Int32) -> Bool { lock.lock(); defer { lock.unlock() }; return children.contains(pid) }

    /// Reaps without blocking. Returns the status if the child has exited.
    func poll(_ pid: Int32) -> Int32? {
        lock.lock(); defer { lock.unlock() }
        if let s = exits[pid] { return s }
        guard children.contains(pid) else { return nil }
        var status: Int32 = 0
        let r = waitpid(pid, &status, WNOHANG)
        if r == pid {
            let code: Int32 = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
            exits[pid] = code
            return code
        }
        return nil
    }
}

public enum ProcessProbe {
    /// True if `pid` exists and is not a zombie.
    public static func alive(_ pid: Int32) -> Bool {
        var info = proc_bsdinfo()
        let n = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard n == Int32(MemoryLayout<proc_bsdinfo>.size) else { return false }
        return info.pbi_status != UInt32(SZOMB)
    }

    public static func executablePath(_ pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(decoding: buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self) : nil
    }
}

final class SpawnedProcess: ResizeProcess, @unchecked Sendable {
    let pid: Int32
    init(pid: Int32) { self.pid = pid }
    func exitStatus() -> Int32? { ChildRegistry.shared.poll(pid) }
    func isRunning() -> Bool {
        if ChildRegistry.shared.isChild(pid) { return ChildRegistry.shared.poll(pid) == nil }
        return ProcessProbe.alive(pid)
    }
}

/// posix_spawn in its own process group (so a signal to the app's group never reaches it), with
/// stdout and stderr appended to a log file beside the journal.
public struct SpawnLauncher: ResizeLauncher {
    public init() {}

    public func launch(_ argv: [String], log: URL) throws -> ResizeProcess {
        try ForbiddenTools.check(argv)
        FileManager.default.createFile(atPath: log.path, contents: nil)
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attr, 0)
        var fa: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fa)
        defer { posix_spawn_file_actions_destroy(&fa) }
        posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&fa, 1, log.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        posix_spawn_file_actions_adddup2(&fa, 1, 2)
        var pid: pid_t = 0
        let cargs = argv.map { strdup($0) } + [nil]
        defer { cargs.forEach { free($0) } }
        let rc = posix_spawn(&pid, argv[0], &fa, &attr, cargs, environ)
        guard rc == 0 else { throw EngineError(.internalError, "couldn't start \(argv[0])", detail: String(cString: strerror(rc))) }
        ChildRegistry.shared.add(pid)
        return SpawnedProcess(pid: pid)
    }

    public func reattach(pid: Int32) -> ResizeProcess? {
        let p = SpawnedProcess(pid: pid)
        if ChildRegistry.shared.isChild(pid) { return p }
        guard ProcessProbe.alive(pid), ProcessProbe.executablePath(pid)?.hasSuffix("/diskutil") == true else { return nil }
        return p
    }
}

public enum ResizeEvent: Sendable, Equatable {
    case started(pid: Int32)
    case reattached(pid: Int32)
    case progress(percent: Int?, phase: String)
    case sampled(partition: Int64, container: Int64)
    /// No output for a long time. Reported, never acted on: a live resize is never killed (§14.7).
    case stalled(seconds: Double)
    /// The topology shows the target before the tool has exited (#391): treated as complete.
    case targetReached
    case exited(status: Int32?)
}

public enum ResizeOutcome: Sendable, Equatable {
    case completed
    /// Nothing changed: show the real error and its fix; Try Again.
    case unchanged(String)
    /// `-69606`, `49153`, "Storage system verify or repair failed": guided First Aid from recoveryOS.
    case needsFirstAid(String)
    /// Container smaller, partition unchanged (Omacom #210): reconcile, never refuse.
    case inconsistent(partition: Int64, container: Int64)
    /// Stop, keep the Mac on, Export Diagnostics.
    case unknown(String)
}

/// ENGINE §8. Watches one `diskutil apfs resizeContainer` from start to a classified outcome.
public final class ResizeSupervisor: @unchecked Sendable {
    public struct Timing: Sendable {
        public var poll: Double = 0.25
        public var sample: Double = 15
        public var stall: Double = 600
        public init(poll: Double = 0.25, sample: Double = 15, stall: Double = 600) { self.poll = poll; self.sample = sample; self.stall = stall }
        public static let tests = Timing(poll: 0.05, sample: 0.2, stall: 0.6)
    }

    let backend: DiskImageBackend
    let launcher: ResizeLauncher
    public var timing: Timing
    public var onEvent: (@Sendable (ResizeEvent) -> Void)?
    /// Test hook: the supervisor "dies" (throws `SimulatedKill`) after this many seconds, leaving the
    /// resize running, as when the helper crashes mid-resize.
    public var dieAfter: Double?

    public init(backend: DiskImageBackend, launcher: ResizeLauncher = SpawnLauncher(), timing: Timing = Timing()) {
        self.backend = backend; self.launcher = launcher; self.timing = timing
    }

    public struct Started: Sendable { public var pid: Int32; public var log: URL }

    /// Authorises and starts the resize. Returns as soon as it is running.
    public func start(store uuid: String, to bytes: Int64, log: URL) throws -> (Started, ResizeProcess) {
        let id = try backend.identifier(uuid)
        let argv = ["/usr/sbin/diskutil", "apfs", "resizeContainer", id, bytes == 0 ? "0" : "\(bytes)B"]
        try backend.chokepoint.authorizeAll(argv)
        backend.chokepoint.invalidate()
        let p = try launcher.launch(argv, log: log)
        onEvent?(.started(pid: p.pid))
        return (Started(pid: p.pid, log: log), p)
    }

    /// Watches until the process exits, then classifies by re-reading the topology. Never kills.
    public func watch(_ p: ResizeProcess, store uuid: String, from: Int64, to: Int64, log: URL) throws -> ResizeOutcome {
        let assertion = Self.holdPowerAssertion()
        defer { if let a = assertion { IOPMAssertionRelease(a) } }
        let began = Date()
        var lastOutput = Date(), lastSample = Date.distantPast, lastSize: UInt64 = 0
        var stallReported = false, reached = false
        while true {
            if let d = dieAfter, Date().timeIntervalSince(began) >= d { throw SimulatedKill(at: "resize supervisor (resize left running)") }
            let size = (try? FileManager.default.attributesOfItem(atPath: log.path)[.size] as? UInt64) ?? 0
            if size != lastSize {
                lastSize = size; lastOutput = Date(); stallReported = false
                if let text = try? String(contentsOf: log, encoding: .utf8) {
                    let (pct, phase) = Self.parseProgress(text)
                    onEvent?(.progress(percent: pct, phase: phase))
                }
            } else if !stallReported, Date().timeIntervalSince(lastOutput) >= timing.stall {
                stallReported = true
                onEvent?(.stalled(seconds: Date().timeIntervalSince(lastOutput)))
            }
            if Date().timeIntervalSince(lastSample) >= timing.sample {
                lastSample = Date()
                if let t = try? backend.freshTopology(), let part = t.partition(uuid: uuid) {
                    let c = part.apfs?.capacityCeiling ?? part.size
                    onEvent?(.sampled(partition: part.size, container: c))
                    if !reached, part.size == to, c <= to { reached = true; onEvent?(.targetReached) }
                }
            }
            if !p.isRunning() { break }
            Thread.sleep(forTimeInterval: timing.poll)
        }
        let status = p.exitStatus()
        onEvent?(.exited(status: status))
        let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        let t = try backend.freshTopology()
        guard let part = t.partition(uuid: uuid) else { return .unknown("the macOS container is missing after the resize") }
        return Self.classify(from: from, to: to, partition: part.size, container: part.apfs?.capacityCeiling ?? part.size,
                             status: status, output: output)
    }

    /// Finds a surviving resize after a helper restart and watches it to the end (ENGINE §8.7).
    public func reattach(pid: Int32, store uuid: String, from: Int64, to: Int64, log: URL) throws -> ResizeOutcome? {
        guard let p = launcher.reattach(pid: pid) else { return nil }
        onEvent?(.reattached(pid: pid))
        return try watch(p, store: uuid, from: from, to: to, log: log)
    }

    public static func classify(from: Int64, to: Int64, partition: Int64, container: Int64, status: Int32?, output: String) -> ResizeOutcome {
        if partition == to && container <= to { return .completed }
        let tail = output.split(separator: "\n").suffix(4).joined(separator: " / ")
        if partition == from && container == from {
            for code in ["-69606", "49153", "Storage system verify or repair failed"] where output.contains(code) {
                return .needsFirstAid(tail)
            }
            return .unchanged(tail.isEmpty ? "diskutil exited with status \(status.map(String.init) ?? "unknown")" : tail)
        }
        if partition == from && container < from { return .inconsistent(partition: partition, container: container) }
        return .unknown("partition \(partition) B, container \(container) B; \(tail)")
    }

    /// diskutil prints phases ("Shrinking APFS data structures") and sometimes percentages.
    static func parseProgress(_ text: String) -> (Int?, String) {
        let lines = text.split(separator: "\n").map(String.init)
        let phase = lines.last { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        var pct: Int?
        var rest = text[...]
        while let r = rest.range(of: #"[0-9]{1,3}%"#, options: .regularExpression) {
            pct = Int(rest[r].dropLast())
            rest = rest[r.upperBound...]
        }
        return (pct, phase)
    }

    static func holdPowerAssertion() -> IOPMAssertionID? {
        var id = IOPMAssertionID(0)
        let r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                            "SiliconForest: resizing a container" as CFString, &id)
        return r == kIOReturnSuccess ? id : nil
    }
}

/// Thrown by fault injection to "kill" the engine at a precise point. Never caught as a failure:
/// nothing is journaled and nothing is rolled back, exactly as if the process had died.
public struct SimulatedKill: Error, Equatable, Sendable {
    public var at: String
    public init(at: String) { self.at = at }
}
