// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// Preview10: the up-front privilege check. Before any download or disk work the installer makes sure it
// has everything it needs, and asks for it cleanly:
//
//   1. The helper is registered and approved (SMAppService; System Settings → General → Login Items).
//   2. The helper has Full Disk Access (macOS asks even root for it to open the internal disk's raw device).
//
// The rule that fixes preview9: System Settings is opened only by a person's click, exactly once per click.
// Checking is quiet: `check(byPerson: false)` reads SMAppService.status and asks the helper's harmless probe,
// and never registers again or opens anything, so polling can't pull the app out of full screen.

import Foundation
import SFLiveDisk

public enum PrivilegeStage: Equatable, Sendable {
    case checking
    /// Waiting for the person to turn the helper on in Login Items.
    case needsHelperApproval
    /// The helper runs, but macOS hasn't given it Full Disk Access.
    case needsFullDiskAccess(PrivilegeReport)
    case ready
    /// Something the person can't fix here (not in /Applications, not our signature, the helper didn't answer).
    case failed(String)

    /// Keep checking quietly while the person is in System Settings.
    public var isWaiting: Bool {
        switch self {
        case .needsHelperApproval, .needsFullDiskAccess: return true
        default: return false
        }
    }
}

public final class PrivilegeGate: @unchecked Sendable {
    public struct Hooks: Sendable {
        public var register: @Sendable () throws -> HelperRegistrationState
        public var status: @Sendable () -> HelperRegistrationState
        public var probe: @Sendable () throws -> PrivilegeReport
        public var openLoginItems: @Sendable () -> Void
        public var openFullDiskAccess: @Sendable () -> Void
        public init(register: @escaping @Sendable () throws -> HelperRegistrationState,
                    status: @escaping @Sendable () -> HelperRegistrationState,
                    probe: @escaping @Sendable () throws -> PrivilegeReport,
                    openLoginItems: @escaping @Sendable () -> Void,
                    openFullDiskAccess: @escaping @Sendable () -> Void) {
            self.register = register; self.status = status; self.probe = probe
            self.openLoginItems = openLoginItems; self.openFullDiskAccess = openFullDiskAccess
        }
    }

    /// Where the person enables Full Disk Access (the first URL SystemLinks tries).
    public static let fullDiskAccessURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    /// SFHelper inside the app: what the person adds with "+" if it isn't in the Full Disk Access list.
    public static func helperPath(appBundle: URL) -> String {
        appBundle.appendingPathComponent("Contents/MacOS/SFHelper").path
    }

    private let hooks: Hooks
    private let lock = NSLock()
    private var _stage: PrivilegeStage = .checking
    private var _loginItemsOpened = 0, _fullDiskAccessOpened = 0, _registerCalls = 0
    public var log: (String) -> Void = { _ in }

    public init(_ hooks: Hooks) { self.hooks = hooks }

    public var stage: PrivilegeStage { lock.lock(); defer { lock.unlock() }; return _stage }
    public var loginItemsOpened: Int { lock.lock(); defer { lock.unlock() }; return _loginItemsOpened }
    public var fullDiskAccessOpened: Int { lock.lock(); defer { lock.unlock() }; return _fullDiskAccessOpened }
    public var registerCalls: Int { lock.lock(); defer { lock.unlock() }; return _registerCalls }

    /// One check. `byPerson` (Get Started, Check Again): registers the helper if macOS says it isn't
    /// registered. Otherwise (the quiet poll) it only reads the status and asks the helper's probe.
    /// Never opens System Settings.
    @discardableResult
    public func check(byPerson: Bool) -> PrivilegeStage {
        var st = hooks.status()
        if st == .notRegistered, byPerson {
            lock.lock(); _registerCalls += 1; lock.unlock()
            do { st = try hooks.register() } catch { st = .refused("macOS didn't register the installer's helper: \(error.localizedDescription)") }
        }
        let next: PrivilegeStage
        switch st {
        case .refused(let why): next = .failed(why)
        case .requiresApproval, .notRegistered: next = .needsHelperApproval
        case .enabled:
            do {
                let r = try hooks.probe()
                switch r.fullDiskAccess {
                case .granted: next = .ready
                case .missing: next = .needsFullDiskAccess(r)
                // The probe couldn't tell (no startup disk to open, no protected file): carry on; a real
                // denial later is still a typed Full Disk Access error that brings the person back here.
                case .unknown: next = .ready
                }
            } catch {
                let m = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
                let current = stage
                if !byPerson, current.isWaiting {
                    // A quiet check while the person is in System Settings: a helper that is restarting isn't a failure.
                    log("privileges: the helper didn't answer this time (\(m)); still waiting")
                    next = current
                } else {
                    next = .failed("The installer's helper didn't answer: \(m)")
                }
            }
        }
        lock.lock(); let changed = next != _stage; _stage = next; lock.unlock()
        if changed || byPerson { log("privileges: \(Self.describe(next))\(byPerson ? " (checked by the person)" : "")") }
        return next
    }

    /// "Open Login Items": exactly one System Settings open per click.
    public func userOpensLoginItems() {
        lock.lock(); _loginItemsOpened += 1; lock.unlock()
        log("privileges: opening Login Items (person's click)")
        hooks.openLoginItems()
    }

    /// "Open Full Disk Access Settings": exactly one System Settings open per click.
    public func userOpensFullDiskAccess() {
        lock.lock(); _fullDiskAccessOpened += 1; lock.unlock()
        log("privileges: opening Full Disk Access settings (person's click)")
        hooks.openFullDiskAccess()
    }

    /// The helper reported a Full Disk Access denial in the middle of something: back to the screen.
    public func noteDenied(path: String) {
        lock.lock(); _stage = .needsFullDiskAccess(PrivilegeReport(fullDiskAccess: .missing, probe: path)); lock.unlock()
        log("privileges: full disk access denied for \(path)")
    }

    public static func describe(_ s: PrivilegeStage) -> String {
        switch s {
        case .checking: return "checking"
        case .needsHelperApproval: return "waiting for Login Items approval"
        case .needsFullDiskAccess(let r): return "full disk access missing (\(r.probe)\(r.detail.map { ": \($0)" } ?? ""))"
        case .ready: return "ready"
        case .failed(let m): return "failed: \(m)"
        }
    }
}
