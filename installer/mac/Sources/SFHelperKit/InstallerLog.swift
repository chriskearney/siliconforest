// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// Preview10: one log for the app and one for the helper, each also sent to the unified log
// (subsystem org.siliconforest.installer), so a failure is never silent.
//
//   app     ~/Library/Logs/SiliconForest Installer/installer.log
//   helper  /Library/Logs/SiliconForest/helper.log            (root writes it; readable by everyone)
//
// Nothing secret is logged: the owner's password and the administrator authorization never reach a
// log call, and `redact` masks anything that looks like a password, token or authorization value.

import Foundation
import os

public final class InstallerLog: @unchecked Sendable {
    public static let subsystem = "org.siliconforest.installer"
    public static let helperLogURL = URL(fileURLWithPath: "/Library/Logs/SiliconForest/helper.log")
    public static func appLogURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Logs/SiliconForest Installer/installer.log")
    }

    /// The app's log (SFInstaller sets it at launch); a no-file logger until then.
    nonisolated(unsafe) public static var app = InstallerLog(file: nil, category: "app")

    public let file: URL?
    public let category: String
    private let logger: Logger
    private let lock = NSLock()
    public var clock: () -> Date = Date.init

    public init(file: URL?, category: String) {
        self.file = file
        self.category = category
        logger = Logger(subsystem: Self.subsystem, category: category)
    }

    public enum Level: String, Sendable { case info = "INFO", error = "ERROR" }

    public func info(_ message: String) { write(.info, message) }
    public func error(_ message: String) { write(.error, message) }

    /// Masks values after password/passphrase/token/secret/authorization keys (key=value, key: value).
    public static func redact(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"(?i)\b(password|passphrase|passwd|token|secret|authorization|auth)\b(\s*[:=]\s*)("[^"]*"|\S+)"#) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1$2<redacted>")
    }

    public static func line(time: Date, level: Level, category: String, message: String) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return "\(f.string(from: time)) \(level.rawValue) [\(category)] \(redact(message).replacingOccurrences(of: "\n", with: " ⏎ "))\n"
    }

    public func write(_ level: Level, _ message: String) {
        let clean = Self.redact(message)
        switch level {
        case .info: logger.info("\(clean, privacy: .public)")
        case .error: logger.error("\(clean, privacy: .public)")
        }
        guard let file else { return }
        let l = Self.line(time: clock(), level: level, category: category, message: clean)
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o755])
        if !fm.fileExists(atPath: file.path) { fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o644]) }
        guard let h = try? FileHandle(forWritingTo: file) else { return }
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: Data(l.utf8))
    }
}
