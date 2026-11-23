import Foundation

public struct ToolResult: Sendable, Equatable {
    public var status: Int32
    public var stdout: Data
    public var stderr: Data
    public init(status: Int32, stdout: Data = Data(), stderr: Data = Data()) { self.status = status; self.stdout = stdout; self.stderr = stderr }
    public var out: String { String(decoding: stdout, as: UTF8.self) }
    public var err: String { String(decoding: stderr, as: UTF8.self) }
    public var ok: Bool { status == 0 }
}

/// Runs one argv. Implementations never go through a shell.
public protocol ToolRunner: Sendable {
    func run(_ argv: [String], stdin: Data?) throws -> ToolResult
}

public extension ToolRunner {
    func run(_ argv: [String]) throws -> ToolResult { try run(argv, stdin: nil) }
}

/// Tools this build never runs, whatever the target (DESIGN §14.6, ENGINE §6). Checked on the
/// basename of argv[0] and on every argument, before a process is created.
public enum ForbiddenTools {
    public static let names: Set<String> = ["sudo", "su", "dd", "gpt", "bputil", "kmutil", "nvram", "csrutil", "bless", "fdisk", "pdisk", "asr", "systemsetup", "launchctl"]
    public static func check(_ argv: [String]) throws {
        guard let first = argv.first, first.hasPrefix("/") else { throw SafetyRefusal("argv[0] must be an absolute path: \(argv.first ?? "")") }
        for a in argv {
            let base = (a as NSString).lastPathComponent
            if names.contains(base) { throw SafetyRefusal("\(base) is never run by this build") }
        }
        if argv.contains(where: { $0 == "-c" }) && ["/bin/sh", "/bin/bash", "/bin/zsh"].contains(first) {
            throw SafetyRefusal("no shell command strings")
        }
    }
}

/// The real process runner. Reads stdout and stderr concurrently so neither pipe can fill and stall.
public struct ProcessToolRunner: ToolRunner {
    public init() {}
    public func run(_ argv: [String], stdin: Data?) throws -> ToolResult {
        try ForbiddenTools.check(argv)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0])
        p.arguments = Array(argv.dropFirst())
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        let inPipe = stdin.map { _ in Pipe() }
        p.standardInput = inPipe ?? FileHandle.nullDevice
        do { try p.run() } catch {
            let ns = error as NSError
            throw EngineError(.internalError, "couldn't start \(argv.prefix(3).joined(separator: " "))", detail: "\(ns.domain) \(ns.code): \(ns.localizedDescription)")
        }
        if let inPipe, let stdin {
            inPipe.fileHandleForWriting.write(stdin)
            try? inPipe.fileHandleForWriting.close()
        }
        let group = DispatchGroup()
        nonisolated(unsafe) var errData = Data()
        group.enter()
        DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()
        // Close every end explicitly: relying on Pipe deallocation leaked ~10 descriptors a second
        // until posix_spawn failed with EBADF (found by the fault-injection sweep).
        for h in [out.fileHandleForReading, out.fileHandleForWriting, err.fileHandleForReading, err.fileHandleForWriting] { try? h.close() }
        if let inPipe { try? inPipe.fileHandleForReading.close(); try? inPipe.fileHandleForWriting.close() }
        return ToolResult(status: p.terminationStatus, stdout: outData, stderr: errData)
    }
}

/// Records every argv it is asked to run (tests prove what did, and did not, run).
public final class RecordingRunner: ToolRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [[String]] = []
    public let inner: ToolRunner?
    public var respond: (@Sendable ([String]) -> ToolResult)?
    public init(inner: ToolRunner? = nil, respond: (@Sendable ([String]) -> ToolResult)? = nil) { self.inner = inner; self.respond = respond }
    public var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return _calls }
    public func run(_ argv: [String], stdin: Data?) throws -> ToolResult {
        lock.lock(); _calls.append(argv); lock.unlock()
        if let respond { return respond(argv) }
        if let inner { return try inner.run(argv, stdin: stdin) }
        return ToolResult(status: 0)
    }
}

/// Read-only queries the engine may run against any disk (they change nothing). Exact shapes only.
public enum Query {
    static let diskID = #"^disk[0-9]+(s[0-9]+)*$"#

    public static func isAllowed(_ argv: [String]) -> Bool {
        func id(_ s: String) -> Bool { s.range(of: diskID, options: .regularExpression) != nil }
        switch argv.count {
        case 3: return argv == ["/usr/bin/hdiutil", "info", "-plist"] || argv == ["/usr/sbin/diskutil", "list", "-plist"]
        case 4:
            if argv[0] == "/usr/sbin/diskutil", argv[1] == "info", argv[2] == "-plist" { return id(argv[3]) }
            if argv[0] == "/usr/sbin/diskutil", argv[1] == "list", argv[2] == "-plist" { return id(argv[3]) }
            if argv[0] == "/usr/sbin/diskutil", argv[1] == "apfs", argv[2] == "list", argv[3] == "-plist" { return true }
            return false
        case 5:
            if Array(argv.prefix(4)) == ["/usr/sbin/diskutil", "apfs", "list", "-plist"] { return id(argv[4]) }
            return false
        case 6:
            // `resizeContainer <store> limits -plist` only reports limits.
            return argv[0] == "/usr/sbin/diskutil" && argv[1] == "apfs" && argv[2] == "resizeContainer" && id(argv[3])
                && argv[4] == "limits" && argv[5] == "-plist"
        default: return false
        }
    }

    public static func plist(_ runner: ToolRunner, _ argv: [String]) throws -> Any {
        guard isAllowed(argv) else { throw SafetyRefusal("not a read-only query: \(argv.joined(separator: " "))") }
        let r = try runner.run(argv)
        guard r.ok else { throw EngineError(.appleTool, "\(argv.dropFirst().prefix(2).joined(separator: " ")) failed", detail: r.err.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return try PropertyListSerialization.propertyList(from: r.stdout, format: nil)
    }

    public static func dict(_ runner: ToolRunner, _ argv: [String]) throws -> [String: Any] {
        guard let d = try plist(runner, argv) as? [String: Any] else { throw EngineError(.internalError, "unexpected plist from \(argv[1])") }
        return d
    }
}
