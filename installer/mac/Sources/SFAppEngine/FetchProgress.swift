// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// Preview13: what the "Download and verify the release" row shows. Preview12 showed "0 of N" that flickered
// because the fetcher passed the loop index as the total while it counted. The row now has two states:
// indeterminate (the file total isn't known yet: "Downloading…" and the bytes so far) and determinate
// ("N of M files" and a bar). Once the total is set it never changes, the done count never goes back, and
// publishing is limited to a few updates a second.

import Foundation

public struct FetchProgress: Equatable, Sendable {
    public var file: String
    public var filesDone: Int64
    /// 0 until the release's file list is known; fixed after that.
    public var filesTotal: Int64
    public var bytes: Int64
    public init(file: String, filesDone: Int64, filesTotal: Int64, bytes: Int64) {
        self.file = file; self.filesDone = filesDone; self.filesTotal = filesTotal; self.bytes = bytes
    }
    public var isDeterminate: Bool { filesTotal > 0 }
    public var isFinished: Bool { filesTotal > 0 && filesDone >= filesTotal }
    /// 0...1, only when the total is known.
    public var fraction: Double? { filesTotal > 0 ? min(1, Double(filesDone) / Double(filesTotal)) : nil }
}

/// Makes a stream of raw fetcher events safe to show: monotonic, a fixed total, at most ~4 publishes a second.
public final class FetchProgressSmoother: @unchecked Sendable {
    private let lock = NSLock()
    private var current = FetchProgress(file: "", filesDone: 0, filesTotal: 0, bytes: 0)
    private var lastPublish: Date?
    private let interval: TimeInterval

    public init(interval: TimeInterval = 0.25) { self.interval = interval }

    /// Folds one event in. Returns the value to show, or nil when it is too soon (the next call carries it).
    public func accept(file: String, done: Int64, total: Int64, bytes: Int64, now: Date = Date()) -> FetchProgress? {
        lock.lock(); defer { lock.unlock() }
        if current.filesTotal == 0, total > 0 { current.filesTotal = total }   // set once, never changed
        current.file = file
        var d = max(current.filesDone, done)
        if current.filesTotal > 0 { d = min(d, current.filesTotal) }
        current.filesDone = d
        current.bytes = max(current.bytes, bytes)
        let first = lastPublish == nil
        if first || current.isFinished || now.timeIntervalSince(lastPublish!) >= interval {
            lastPublish = now
            return current
        }
        return nil
    }
}
