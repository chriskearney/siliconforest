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
// Preview12: if this app build is not the one that last registered the helper, and the helper is already
// enabled, unregister, register and reconnect before probing, so a leftover helper from an older preview
// is replaced. The same restart happens once if a probe fails because the connection was invalidated or
// the helper does not know the verb (a preview9 helper drops `checkPrivileges`).

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

    /// Keep checking quietly while the person is in System Settings.
    public var isWaiting: Bool {
        switch self {
        case .needsHelperApproval, .needsFullDiskAccess: return true
        default: return false
        }
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
        public var unregister: @Sendable () throws -> HelperRegistrationState
        public var reconnect: @Sendable () -> Void
        public var build: HelperBuildMemory?
        public init(register: @escaping @Sendable () throws -> HelperRegistrationState,
                    status: @escaping @Sendable () -> HelperRegistrationState,
                    probe: @escaping @Sendable () throws -> PrivilegeReport,
                    openLoginItems: @escaping @Sendable () -> Void,
                    openFullDiskAccess: @escaping @Sendable () -> Void,
                    unregister: @escaping @Sendable () throws -> HelperRegistrationState = { .notRegistered },
                    reconnect: @escaping @Sendable () -> Void = {},
                    build: HelperBuildMemory? = nil) {
            self.register = register; self.status = status; self.probe = probe
            self.openLoginItems = openLoginItems; self.openFullDiskAccess = openFullDiskAccess
            self.unregister = unregister; self.reconnect = reconnect; self.build = build
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
    private var _didBuildRefresh = false, _didStaleRefresh = false
    public var log: (String) -> Void = { _ in }

    public init(_ hooks: Hooks) { self.hooks = hooks }

    public var stage: PrivilegeStage { lock.lock(); defer { lock.unlock() }; return _stage }
    public var loginItemsOpened: Int { lock.lock(); defer { lock.unlock() }; return _loginItemsOpened }
    public var fullDiskAccessOpened: Int { lock.lock(); defer { lock.unlock() }; return _fullDiskAccessOpened }
    public var registerCalls: Int { lock.lock(); defer { lock.unlock() }; return _registerCalls }
    public var didBuildRefresh: Bool { lock.lock(); defer { lock.unlock() }; return _didBuildRefresh }
    public var didStaleRefresh: Bool { lock.lock(); defer { lock.unlock() }; return _didStaleRefresh }

    /// True when the next `check` will unregister and register the helper because this app build is
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
        if st == .notRegistered, byPerson {
            lock.lock(); _registerCalls += 1; lock.unlock()
            do { st = try hooks.register() } catch { st = .refused("macOS didn't register the installer's helper: \(error.localizedDescription)") }
            if st == .enabled { rememberBuild() }
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

    private func restartHelper(reason: String) {
        lock.lock(); _stage = .restartingHelper; lock.unlock()
        log("privileges: restarting the installer's helper (\(reason))")
        do { _ = try hooks.unregister() } catch { log("privileges: unregister failed: \(error.localizedDescription)") }
        do {
            let st = try hooks.register()
            hooks.reconnect()
            if st == .enabled { rememberBuild() }
        } catch {
            log("privileges: register after restart failed: \(error.localizedDescription)")
            hooks.reconnect()
        }
    }

    private func rememberBuild() {
        guard let build = hooks.build else { return }
        build.write(build.current)
    }
}
