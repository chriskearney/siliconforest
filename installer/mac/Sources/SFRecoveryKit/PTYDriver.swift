import Foundation
import Darwin

/// Drives an interactive tool (bputil, kmutil) through a pseudo-terminal, the way a person at a
/// Terminal would: wait for the password prompt, check the terminal has echo turned off, send the
/// password, answer yes/no prompts we expect, and keep a transcript with the password removed.
///
/// It never sends the password while echo is on (the tool would print it), and never puts it in
/// argv, the environment, a log or the transcript (DESIGN §7.2, §14.9).
public final class PTYDriver {
    public struct Rule: Sendable {
        /// Lowercased substring of the tool's output that triggers the rule.
        public var prompt: String
        public var reply: Reply
        public init(_ prompt: String, _ reply: Reply) { self.prompt = prompt; self.reply = reply }
    }
    public enum Reply: Sendable { case password, text(String) }

    public struct Outcome: Sendable {
        public var status: Int32
        /// Everything the tool printed, with the password (if it ever appeared) replaced by "••••".
        public var transcript: String
        public var passwordSent: Bool
    }

    public enum Failure: Error, Equatable, LocalizedError {
        case spawn(String)
        case echoOn
        case timedOut(String)
        public var errorDescription: String? {
            switch self {
            case .spawn(let m): return "couldn't start the tool: \(m)"
            case .echoOn: return "the tool asked for a password with echo on; it was not sent"
            case .timedOut(let t): return "the tool stopped responding (last output: \(t.suffix(120)))"
            }
        }
    }

    public let argv: [String]
    public var rules: [Rule]
    public var timeout: TimeInterval
    /// How long to wait for echo to go off after a password prompt appears.
    public var echoGrace: TimeInterval = 2

    public init(argv: [String], rules: [Rule], timeout: TimeInterval = 600) {
        self.argv = argv; self.rules = rules; self.timeout = timeout
    }

    public func run(password: Data?) throws -> Outcome {
        var master: Int32 = -1, slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else { throw Failure.spawn("openpty: \(String(cString: strerror(errno)))") }
        defer { close(master) }
        let slaveName = String(cString: ptsname(master))

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // A new session, so the pty becomes the child's controlling terminal when it opens it.
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
        var fa: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fa)
        defer { posix_spawn_file_actions_destroy(&fa) }
        posix_spawn_file_actions_addopen(&fa, 0, slaveName, O_RDWR, 0)
        posix_spawn_file_actions_adddup2(&fa, 0, 1)
        posix_spawn_file_actions_adddup2(&fa, 0, 2)
        posix_spawn_file_actions_addclose(&fa, master)
        posix_spawn_file_actions_addclose(&fa, slave)
        var pid: pid_t = 0
        let cargs: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) } + [nil]
        defer { cargs.forEach { free($0) } }
        let envStrings: [String] = ["PATH=/usr/bin:/bin:/usr/sbin:/sbin", "TERM=vt100", "LANG=en_US.UTF-8"]
        let env: [UnsafeMutablePointer<CChar>?] = envStrings.map { strdup($0) } + [nil]
        defer { env.forEach { free($0) } }
        let rc = posix_spawn(&pid, argv[0], &fa, &attr, cargs, env)
        close(slave)
        guard rc == 0 else { throw Failure.spawn(String(cString: strerror(rc))) }

        _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
        var raw = Data()
        var scanFrom = 0
        var sent = false
        var fired = Set<Int>()
        let deadline = Date().addingTimeInterval(timeout)
        var status: Int32?
        var buf = [UInt8](repeating: 0, count: 4096)

        func readAvailable() {
            while true {
                let n = read(master, &buf, buf.count)
                if n > 0 { raw.append(contentsOf: buf[0..<n]) } else { break }
            }
        }
        func echoOff() -> Bool {
            var t = termios()
            guard tcgetattr(master, &t) == 0 else { return false }
            return (t.c_lflag & tcflag_t(ECHO)) == 0
        }

        while status == nil {
            readAvailable()
            let text = String(decoding: raw[scanFrom...], as: UTF8.self).lowercased()
            for (i, r) in rules.enumerated() where !fired.contains(i) || r.prompt.hasSuffix("*") {
                let key = r.prompt.hasSuffix("*") ? String(r.prompt.dropLast()) : r.prompt
                guard text.contains(key) else { continue }
                switch r.reply {
                case .password:
                    guard let password else { continue }
                    // Wait for the tool to turn echo off before typing the secret.
                    let until = Date().addingTimeInterval(echoGrace)
                    while !echoOff() && Date() < until { usleep(20_000) }
                    guard echoOff() else { Self.terminate(pid); throw Failure.echoOn }
                    password.withUnsafeBytes { _ = write(master, $0.baseAddress, $0.count) }
                    _ = write(master, "\n", 1)
                    sent = true
                case .text(let s):
                    _ = s.withCString { write(master, $0, strlen($0)) }
                    _ = write(master, "\n", 1)
                }
                fired.insert(i)
                scanFrom = raw.count
                break
            }
            var st: Int32 = 0
            let w = waitpid(pid, &st, WNOHANG)
            if w == pid { status = (st & 0x7f) == 0 ? (st >> 8) & 0xff : 128 + (st & 0x7f); break }
            if Date() > deadline {
                Self.terminate(pid)
                throw Failure.timedOut(Self.redact(String(decoding: raw, as: UTF8.self), password))
            }
            usleep(10_000)
        }
        readAvailable()
        return Outcome(status: status ?? -1, transcript: Self.redact(String(decoding: raw, as: UTF8.self), password), passwordSent: sent)
    }

    /// SIGTERM, then SIGKILL if it hasn't gone within half a second (a shell blocked in `read` on a
    /// terminal may ignore SIGTERM), then reap.
    static func terminate(_ pid: pid_t) {
        kill(pid, SIGTERM)
        for _ in 0..<50 { if waitpid(pid, nil, WNOHANG) == pid { return }; usleep(10_000) }
        kill(pid, SIGKILL)
        _ = waitpid(pid, nil, 0)
    }

    static func redact(_ s: String, _ password: Data?) -> String {
        guard let password, !password.isEmpty else { return s }
        return s.replacingOccurrences(of: String(decoding: password, as: UTF8.self), with: "••••")
    }
}
