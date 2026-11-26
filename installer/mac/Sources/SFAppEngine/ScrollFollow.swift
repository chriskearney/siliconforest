// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// Preview13: the step list on the Installing screen follows the step that is in progress, without fighting
// the person. The rules (the view applies them; this struct holds the state so they can be tested):
//   - The list scrolls to the active row (centered, short animation) when the ACTIVE ROW CHANGES, never on
//     every progress tick, and at most once per `minInterval` (about four a second at the very most).
//   - If the active row leaves the visible area and we did not just scroll there ourselves, the person
//     scrolled away: auto-follow pauses.
//   - Follow resumes when the active row comes back into view (they scrolled back near it) or when a new
//     step starts (the active row changes).
//   - A scroll we caused is not mistaken for the person: rows scrolling out of view within `settle` seconds
//     after our own scroll are ignored.

import Foundation

public struct ScrollFollow: Equatable, Sendable {
    public var active: Int?
    public private(set) var paused = false
    private var lastFollow: Date?
    private var activeVisible = true
    public var minInterval: TimeInterval
    public var settle: TimeInterval

    public init(minInterval: TimeInterval = 0.25, settle: TimeInterval = 0.8) { self.minInterval = minInterval; self.settle = settle }

    /// The in-progress row changed (or was first seen). Returns true when the view should scroll to it now.
    public mutating func activeChanged(to index: Int?, now: Date = Date()) -> Bool {
        guard let index, index != active else { active = index ?? active; return false }
        active = index
        paused = false                       // a new step starts: follow again
        if let l = lastFollow, now.timeIntervalSince(l) < minInterval { return false }
        lastFollow = now
        return true
    }

    /// A row left the visible area.
    public mutating func rowDisappeared(_ index: Int, now: Date = Date()) {
        guard index == active else { return }
        activeVisible = false
        if let l = lastFollow, now.timeIntervalSince(l) < settle { return }   // our own scroll
        paused = true
    }

    /// A row came into view; the active row back in view resumes following.
    public mutating func rowAppeared(_ index: Int) {
        guard index == active else { return }
        activeVisible = true
        paused = false
    }
}
