// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// The two things the shipped helper may do to this Mac's startup settings (preview7), as injectable
// actions: the one-time bless, and the restart. SFHelper installs them only in a build with
// SF_REAL_DISK_WRITES; everything else (tests, lab tools, other builds) has none, and tests use recorders.

import Foundation
import SFEngine

/// Runs `/usr/sbin/bless` for the engine, and only the shapes `BlessGuard.isAllowed` lists: `--getBoot`,
/// `--mount <volume> --setBoot [--nextonly]`. Refuses unless root. Never a shell; a 30 s limit.
public struct ProcessBlessRunner: BlessRunner {
    public init() {}

    public func execute(_ argv: [String]) -> BlessResult {
        guard BlessGuard.isAllowed(argv) else { return BlessResult(status: 126, output: "refused: not an allowed bless command") }
        guard geteuid() == 0 else { return BlessResult(status: 126, output: "refused: bless needs the root helper") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0])
        p.arguments = Array(argv.dropFirst())
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return BlessResult(status: 127, output: "\(error)") }
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
