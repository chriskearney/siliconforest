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
//
// Preview12 unregistered and registered an approved helper when this app build was new. macOS then turned the
// helper off ("Job is not allowed to bootstrap") and the X never cleared (Job C, 26 November 2026).
// Preview13: an approved, enabled helper is NEVER unregistered. A stale one (a new app build, or a probe that
// fails because the connection was invalidated or the helper doesn't know the verb) is asked to exit with the
// `retire` verb (or idles out by itself, as preview12 and earlier do), our connection is dropped, and launchd
// starts the binary on disk at the next connection. Registering happens only for `.notRegistered`, once; a
// register that macOS answers with "not allowed" or error 1 means the switch is off, which is
// `.needsHelperApproval` (the person's toggle), not a failure. Every stage that is not `.ready`, `.failed`
// included, keeps being checked quietly, so a stale X clears by itself.

import Foundation
import SFLiveDisk

public enum PrivilegeStage: Equatable, Sendable {
    case checking
    /// The helper is being unregistered and registered again (a new app build, or a helper that did not answer).
    case restartingHelper
    /// Waiting for the person to turn the helper on in Login Items.
    case needsHelperApproval
    /// The helper runs, but macOS hasn't given it Full Disk Access.
    case needsFullDiskAccess(PrivilegeReport)
    case ready
    /// Something the person can't fix here (not in /Applications, not our signature, the helper didn't answer).
    case failed(String)

    /// Keep checking quietly: while the person is in System Settings, and after a failure (the cause may be gone
    /// by itself: a helper that was restarting, a switch turned on), so the X clears without a click.
    public var isWaiting: Bool {
        switch self {
        case .needsHelperApproval, .needsFullDiskAccess, .failed: return true
        default: return false
        }
    }

    /// The Full Disk Access row is a button whenever it is not passing (a failed check or an unapproved helper
    /// can hide missing access, so the pane is one click away).
    public var fullDiskAccessRowIsTappable: Bool {
        if case .ready = self { return false }
        return true
    }

    /// The failed message is about Full Disk Access (the footer should offer that settings pane).
    public var failedMentionsFullDiskAccess: Bool {
        if case .failed(let m) = self { return m.localizedCaseInsensitiveContains("full disk access") }
        return false
    }
}

/// The app version and build that last registered the helper, kept in UserDefaults so a later build
/// can tell that the running helper may be stale.
public struct HelperBuildMemory: Sendable {
    public static let defaultsKey = "org.siliconforest.installer.registeredHelperBuild"

    public var current: String
    public var read: @Sendable () -> String?
    public var write: @Sendable (String) -> Void

    public init(current: String, read: @escaping @Sendable () -> String?, write: @escaping @Sendable (String) -> Void) {
        self.current = current; self.read = read; self.write = write
    }

    /// `"<CFBundleShortVersionString>/<CFBundleVersion>"`, for example `0.1.0-preview12/26`.
    public static func stamp(bundle: Bundle = .main) -> String {
        let v = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let b = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v)/\(b)"
    }

    public static func app(bundle: Bundle = .main, defaults: UserDefaults = .standard) -> HelperBuildMemory {
        let current = stamp(bundle: bundle)
        nonisolated(unsafe) let defaults = defaults
        return HelperBuildMemory(
            current: current,
            read: { defaults.string(forKey: defaultsKey) },
            write: { defaults.set($0, forKey: defaultsKey) })
    }
}

public final class PrivilegeGate: @unchecked Sendable {
    public struct Hooks: Sendable {
        public var register: @Sendable () throws -> HelperRegistrationState
        public var status: @Sendable () -> HelperRegistrationState
        public var probe: @Sendable () throws -> PrivilegeReport
        public var openLoginItems: @Sendable () -> Void
        public var openFullDiskAccess: @Sendable () -> Void
        /// Kept for callers that pass it; the gate no longer calls it (preview13).
        public var unregister: @Sendable () throws -> HelperRegistrationState
        /// Preview13: asks a stale helper process to exit (best effort), before reconnecting.
        public var retire: @Sendable () -> Void
        public var reconnect: @Sendable () -> Void
        public var build: HelperBuildMemory?
        public init(register: @escaping @Sendable () throws -> HelperRegistrationState,
                    status: @escaping @Sendable () -> HelperRegistrationState,
                    probe: @escaping @Sendable () throws -> PrivilegeReport,
                    openLoginItems: @escaping @Sendable () -> Void,
                    openFullDiskAccess: @escaping @Sendable () -> Void,
                    unregister: @escaping @Sendable () throws -> HelperRegistrationState = { .notRegistered },
                    reconnect: @escaping @Sendable () -> Void = {},
                    build: HelperBuildMemory? = nil,
                    retire: @escaping @Sendable () -> Void = {}) {
            self.register = register; self.status = status; self.probe = probe
            self.openLoginItems = openLoginItems; self.openFullDiskAccess = openFullDiskAccess
            self.unregister = unregister; self.reconnect = reconnect; self.build = build; self.retire = retire
        }
    }

    /// Where the person enables Full Disk Access (the first URL SystemLinks tries; the pane's list, not a specific app: macOS has no URL that adds or selects one).
    public static let fullDiskAccessURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")!

    /// SFHelper inside the app: what the person adds with "+" if it isn't in the Full Disk Access list.
    public static func helperPath(appBundle: URL) -> String {
        appBundle.appendingPathComponent("Contents/MacOS/SFHelper").path
    }

    private let hooks: Hooks
    private let lock = NSLock()
    private var _stage: PrivilegeStage = .checking
    private var _loginItemsOpened = 0, _fullDiskAccessOpened = 0, _registerCalls = 0
    private var _didBuildRefresh = false, _didStaleRefresh = false
    /// macOS lists the helper but it is off: it answered register with "not allowed" (or error 1). Registering again
    /// can't turn the switch on, so the quiet checks only wait for the person (the status turns to enabled).
    private var _approvalPending = false
    public var log: (String) -> Void = { _ in }

    public init(_ hooks: Hooks) { self.hooks = hooks }

    public var stage: PrivilegeStage { lock.lock(); defer { lock.unlock() }; return _stage }
    public var loginItemsOpened: Int { lock.lock(); defer { lock.unlock() }; return _loginItemsOpened }
    public var fullDiskAccessOpened: Int { lock.lock(); defer { lock.unlock() }; return _fullDiskAccessOpened }
    public var registerCalls: Int { lock.lock(); defer { lock.unlock() }; return _registerCalls }
    public var didBuildRefresh: Bool { lock.lock(); defer { lock.unlock() }; return _didBuildRefresh }
    public var didStaleRefresh: Bool { lock.lock(); defer { lock.unlock() }; return _didStaleRefresh }

    /// True when the next `check` will ask the running helper to restart because this app build is
    /// not the one that last registered it, and the helper is already enabled.
    public func willRefreshHelper() -> Bool {
        guard let build = hooks.build, !_didBuildRefresh, build.read() != build.current else { return false }
        return hooks.status() == .enabled
    }

    /// One check. `byPerson` (Get Started, Check Again): registers the helper if macOS says it isn't
    /// registered. Otherwise (the quiet poll) it only reads the status and asks the helper's probe.
    /// Never opens System Settings. If this app build is new and the helper is already enabled, or a
    /// probe fails because the helper did not answer, the helper is restarted once and the check is retried.
    @discardableResult
    public func check(byPerson: Bool) -> PrivilegeStage {
        refreshIfBuildChanged()
        return runCheck(byPerson: byPerson, allowStaleRefresh: true)
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
        case .restartingHelper: return "restarting the installer's helper"
        case .needsHelperApproval: return "waiting for Login Items approval"
        case .needsFullDiskAccess(let r): return "full disk access missing (\(r.probe)\(r.detail.map { ": \($0)" } ?? ""))"
        case .ready: return "ready"
        case .failed(let m): return "failed: \(m)"
        }
    }

    /// A connection that was invalidated or interrupted, or a helper that does not know the probe verb.
    public static func isStaleHelperError(_ error: Error) -> Bool {
        isStaleHelperMessage((error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription, code: (error as NSError).code, domain: (error as NSError).domain)
    }

    public static func isStaleHelperMessage(_ message: String, code: Int = 0, domain: String = "") -> Bool {
        if domain == NSCocoaErrorDomain && (code == 4097 || code == 4099) { return true }
        let s = message.lowercased()
        return s.contains("invalidat") || s.contains("interrupt")
            || s.contains("couldn't communicate") || s.contains("couldn’t communicate")
            || s.contains("not in the interface") || s.contains("unknown selector")
            || s.contains("the helper didn't answer") || s.contains("the helper didn’t answer")
    }

    private func refreshIfBuildChanged() {
        guard willRefreshHelper(), let build = hooks.build else { return }
        let previous = build.read() ?? "none"
        lock.lock(); _didBuildRefresh = true; lock.unlock()
        restartHelper(reason: "the installer was updated (\(previous) → \(build.current))")
    }

    private func runCheck(byPerson: Bool, allowStaleRefresh: Bool) -> PrivilegeStage {
        var st = hooks.status()
        if st == .enabled { lock.lock(); _approvalPending = false; lock.unlock() }
        lock.lock(); let pending = _approvalPending; lock.unlock()
        if st == .notRegistered, byPerson, !pending {
            lock.lock(); _registerCalls += 1; lock.unlock()
            do { st = try hooks.register() } catch {
                let ns = error as NSError
                log("privileges: register failed: \(ns.localizedDescription) [\(ns.domain) \(ns.code)]")
                st = HelperRegistrar.stateAfterRegisterError(domain: ns.domain, code: ns.code, message: ns.localizedDescription, status: hooks.status())
            }
            if st == .enabled { rememberBuild() }
            if st == .requiresApproval { lock.lock(); _approvalPending = true; lock.unlock() }
        }
        let next: PrivilegeStage
        switch st {
        case .refused(let why): next = .failed(why)
        case .requiresApproval, .notRegistered: next = .needsHelperApproval
        case .enabled:
            do {
                let r = try hooks.probe()
                switch r.fullDiskAccess {
                case .granted:
                    rememberBuild()
                    next = .ready
                case .missing: next = .needsFullDiskAccess(r)
                // The probe couldn't tell (no startup disk to open, no protected file): carry on; a real
                // denial later is still a typed Full Disk Access error that brings the person back here.
                case .unknown:
                    rememberBuild()
                    next = .ready
                }
            } catch {
                let m = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
                // Only restart on the path that would show .failed. A quiet check while the person
                // is already in System Settings keeps waiting (a helper that is restarting is not a failure).
                if allowStaleRefresh, Self.isStaleHelperError(error), byPerson || !stage.isWaiting {
                    lock.lock(); _didStaleRefresh = true; lock.unlock()
                    restartHelper(reason: "the helper didn't answer (\(m))")
                    return runCheck(byPerson: byPerson, allowStaleRefresh: false)
                }
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

    /// Replaces a stale helper process WITHOUT touching its registration: ask it to exit, drop our connection,
    /// and let launchd start the current binary at the next connection.
    private func restartHelper(reason: String) {
        lock.lock(); _stage = .restartingHelper; lock.unlock()
        log("privileges: restarting the installer's helper (\(reason)); it stays registered")
        hooks.retire()
        hooks.reconnect()
        if hooks.status() == .enabled { rememberBuild() }
    }

    private func rememberBuild() {
        guard let build = hooks.build else { return }
        build.write(build.current)
    }
}
