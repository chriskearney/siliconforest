// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// The two things the shipped helper may do to this Mac's startup settings (preview7), as injectable
// actions: the one-time bless, and the restart. SFHelper installs them only in a build with
// SF_REAL_DISK_WRITES; everything else (tests, lab tools, other builds) has none, and tests use recorders.

import Foundation
import SFEngine

extension SecureBytes: SecretBytesProvider {}

/// The only place a password is written: raw bytes and a newline to one file descriptor (the child's stdin).
public enum StdinFeed {
    public static func send(_ secret: any SecretBytesProvider, to fd: Int32) {
        secret.withBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n <= 0 { break }
                offset += n
            }
        }
        var nl: UInt8 = 10
        _ = write(fd, &nl, 1)
    }
}

/// Runs a read-only command and returns its standard output (nil when it can't run or exits non-zero). Never a shell.
public enum ProcessCapture {
    public static let run: @Sendable (String, [String]) -> Data? = { exe, args in
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? data : nil
    }
}

/// Runs `/usr/sbin/bless` for the engine, and only the shapes `BlessGuard.isAllowed` lists: `--getBoot`,
/// `--mount <volume> --setBoot [--nextonly]`, and (preview13) the same with `--user <owner> --stdinpass`, where
/// the password goes only to bless's standard input. Refuses unless root. Never a shell; a 30 s limit.
public struct ProcessBlessRunner: PasswordBlessRunner {
    public init() {}

    public func execute(_ argv: [String]) -> BlessResult { run(argv, password: nil) }

    public func execute(_ argv: [String], password: any SecretBytesProvider) -> BlessResult { run(argv, password: password) }

    private func run(_ argv: [String], password: (any SecretBytesProvider)?) -> BlessResult {
        guard BlessGuard.isAllowed(argv) else { return BlessResult(status: 126, output: "refused: not an allowed bless command") }
        guard geteuid() == 0 else { return BlessResult(status: 126, output: "refused: bless needs the root helper") }
        // A command that reads a password needs one, and a password is only ever sent to such a command.
        guard BlessGuard.usesPassword(argv) == (password != nil) else { return BlessResult(status: 126, output: "refused: the password and the command don't match") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0])
        p.arguments = Array(argv.dropFirst())
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        let input = Pipe()
        if password != nil { p.standardInput = input } else { p.standardInput = FileHandle.nullDevice }
        do { try p.run() } catch { return BlessResult(status: 127, output: "\(error)") }
        if let password {
            // The password and a newline, to the child's stdin only; then the pipe is closed.
            StdinFeed.send(password, to: input.fileHandleForWriting.fileDescriptor)
            try? input.fileHandleForWriting.close()
        }
        let deadline = Date().addingTimeInterval(30)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if p.isRunning { p.terminate(); return BlessResult(status: 124, output: "bless didn't finish in 30 s") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return BlessResult(status: p.terminationStatus, output: String(decoding: data.prefix(4096), as: UTF8.self))
    }
}

public enum SystemRestart {
    /// `/sbin/shutdown -r now`: the verb that calls it has checked the job and the confirmation.
    public static let action: @Sendable () -> Void = {
        guard geteuid() == 0 else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/sbin/shutdown")
        p.arguments = ["-r", "now"]
        try? p.run()
    }
}
