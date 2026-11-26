// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// The installer app's real install (preview6), without any UI: download the signed release (or take a
// local folder), verify it, hand it to the helper, plan, confirm, start, follow progress, resume. The
// Session drives exactly these calls; `sfappimage` drives the same calls against a disk image on the M5.

import Foundation
import ServiceManagement
import SFEngine
import SFInstallKit
import SFHelperKit
import SFLiveDisk

public struct LiveError: Error, LocalizedError, Sendable {
    public var message: String
    public init(_ m: String) { message = m }
    public var errorDescription: String? { message }
}

/// Where the app gets the release: the GitHub release for its own version, or a folder the person chose.
public enum ReleaseOrigin: Sendable, Equatable {
    case github(tag: String)
    case folder(URL)

    public static let repository = "chriskearney/siliconforest"
    public static func tag(forAppVersion v: String) -> String { "installer-v\(v)" }
}

/// Downloads (or copies) exactly the files SHA256SUMS lists into a cache folder, checking each hash as it
/// lands, then verifies the signature with the bundled allowed_signers. The helper verifies again after it
/// copies the files into its own store; the app's copy is never trusted on its own.
public final class ReleaseFetcher: @unchecked Sendable {
    public let cache: URL
    public var allowedSigners: URL?
    public var session: URLSession = .shared

    public init(cache: URL = ReleaseFetcher.defaultCache, allowedSigners: URL? = nil) { self.cache = cache; self.allowedSigners = allowedSigners }

    public static var defaultCache: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("org.siliconforest.installer/releases", isDirectory: true)
    }

    /// (file now being fetched, files finished, files in the release, bytes of finished files).
    /// The file total is the length of SHA256SUMS: fixed from the first call, never the loop index.
    public typealias Progress = @Sendable (String, Int64, Int64, Int64) -> Void

    public func fetch(_ origin: ReleaseOrigin, progress: Progress? = nil) async throws -> (dir: URL, manifest: ReleaseManifest) {
        let dir: URL
        switch origin {
        case .github(let tag): dir = cache.appendingPathComponent(tag, isDirectory: true)
        case .folder(let u): dir = cache.appendingPathComponent("local-" + SHA256Hasher.hex(Data(u.standardizedFileURL.path.utf8)).prefix(12), isDirectory: true)
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func get(_ name: String) async throws -> Data? {
            switch origin {
            case .github(let tag):
                let url = URL(string: "https://github.com/\(ReleaseOrigin.repository)/releases/download/\(tag)/\(name)")!
                let (tmp, resp) = try await session.download(from: url)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw LiveError("couldn't download \(name) (HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0))") }
                defer { try? FileManager.default.removeItem(at: tmp) }
                return try Data(contentsOf: tmp, options: .alwaysMapped)
            case .folder(let u):
                return FileManager.default.contents(atPath: u.appendingPathComponent(name).path)
            }
        }
        guard let sums = try await get("SHA256SUMS"), let sig = try await get("SHA256SUMS.sig") else { throw LiveError("the release has no SHA256SUMS and SHA256SUMS.sig") }
        let entries = try Self.parseSums(sums)
        // Remove anything in the cache that the sums don't list (the folder must hold only the release).
        let keep = Set(entries.map(\.name) + ["SHA256SUMS", "SHA256SUMS.sig"])
        for f in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where !keep.contains(f) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
        }
        try sums.write(to: dir.appendingPathComponent("SHA256SUMS"), options: .atomic)
        try sig.write(to: dir.appendingPathComponent("SHA256SUMS.sig"), options: .atomic)
        let total = Int64(entries.count)
        var bytes: Int64 = 0
        func size(_ u: URL) -> Int64 { ((try? FileManager.default.attributesOfItem(atPath: u.path)[.size]) as? NSNumber)?.int64Value ?? 0 }
        progress?("SHA256SUMS", 0, total, 0)
        for (i, e) in entries.enumerated() {
            let dest = dir.appendingPathComponent(e.name)
            if let h = try? FileHandle(forReadingFrom: dest), (try? SHA256Hasher.stream(h, limit: Int64.max)) == e.sha256 {
                try? h.close(); bytes += size(dest); progress?(e.name, Int64(i + 1), total, bytes); continue
            }
            progress?(e.name, Int64(i), total, bytes)
            switch origin {
            case .github(let tag):
                let url = URL(string: "https://github.com/\(ReleaseOrigin.repository)/releases/download/\(tag)/\(e.name)")!
                let base = bytes
                let (tmp, resp) = try await downloadWithBytes(url) { got in progress?(e.name, Int64(i), total, base + got) }
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { try? FileManager.default.removeItem(at: tmp); throw LiveError("couldn't download \(e.name)") }
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tmp, to: dest)
            case .folder(let u):
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: u.appendingPathComponent(e.name), to: dest)
            }
            let h = try FileHandle(forReadingFrom: dest); defer { try? h.close() }
            guard try SHA256Hasher.stream(h, limit: Int64.max) == e.sha256 else { throw LiveError("\(e.name) doesn't match SHA256SUMS") }
            bytes += size(dest)
            progress?(e.name, Int64(i + 1), total, bytes)
        }
        let m: ReleaseManifest
        do { m = try SFRelease.verify(directory: dir, allowedSigners: allowedSigners, allowRehearsal: false) }
        catch let r as SFRelease.Refusal { throw LiveError("the release doesn't verify: \(r.reason)") }
        try StagePin.check(m)
        return (dir, m)
    }

    /// A download that reports the bytes received so far (the 300 MB root image is one file). The file is moved
    /// out of the system's temporary location before the completion handler returns, as the system requires.
    func downloadWithBytes(_ url: URL, onBytes: @escaping @Sendable (Int64) -> Void) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { cont in
            let keep = FileManager.default.temporaryDirectory.appendingPathComponent("sf-fetch-\(UUID().uuidString)")
            let task = session.downloadTask(with: url) { tmp, resp, error in
                if let error { cont.resume(throwing: error); return }
                guard let tmp, let resp else { cont.resume(throwing: LiveError("the download returned nothing")); return }
                do { try FileManager.default.moveItem(at: tmp, to: keep); cont.resume(returning: (keep, resp)) }
                catch { cont.resume(throwing: error) }
            }
            // Foundation's Progress for the task is observable; its units are bytes once the length is known.
            let obs = task.progress.observe(\.completedUnitCount, options: [.new]) { p, _ in onBytes(p.completedUnitCount) }
            ObservationBox.hold(obs, for: task)
            task.resume()
        }
    }

    static func parseSums(_ d: Data) throws -> [(sha256: String, name: String)] {
        try String(decoding: d, as: UTF8.self).split(separator: "\n").map { line in
            let p = line.split(separator: " ", omittingEmptySubsequences: true)
            guard p.count == 2, p[0].count == 64, !p[1].contains("/"), !p[1].hasPrefix(".") else { throw LiveError("SHA256SUMS is malformed") }
            return (String(p[0]), String(p[1]))
        }
    }
}

/// One installation's life through the helper. Every method is synchronous (call it off the main thread).
public final class LiveInstallController: @unchecked Sendable {
    private let connect: () throws -> HelperClient
    private var cached: HelperClient?
    private let lock = NSLock()
    /// Keeps the administrator approval alive until the helper has checked it.
    private var approval: AdminApproval?

    public init(connect: @escaping () throws -> HelperClient) { self.connect = connect }

    public func client() throws -> HelperClient {
        lock.lock(); defer { lock.unlock() }
        if let c = cached { return c }
        let c = try connect(); cached = c; return c
    }

    /// Drops the connection (the helper may have restarted).
    public func reconnect() { lock.lock(); cached = nil; lock.unlock() }

    private func call<T>(_ body: (HelperClient) throws -> T) throws -> T {
        do { return try body(try client()) } catch let e as NSError where e.domain == NSCocoaErrorDomain {
            reconnect(); return try body(try client())   // the connection broke: once more on a fresh one
        }
    }

    public func info() throws -> HelperInfo { try call { try $0.info() } }
    public func unfinishedJobs() throws -> [String] { try info().unfinishedJobs }

    public func importRelease(_ dir: URL) throws -> ReleaseSummary {
        try call { c in try Canonical.decoder().decode(ReleaseSummary.self, from: try c.call(timeout: 900) { $0.importRelease(from: dir.path, reply: $1) }) }
    }

    /// Preview10: the helper's harmless privilege probe (Full Disk Access). Opens nothing for writing.
    public func privileges() throws -> PrivilegeReport {
        try call { c in try Canonical.decoder().decode(PrivilegeReport.self, from: try c.call(timeout: 30) { $0.checkPrivileges(reply: $1) }) }
    }

    public func offer(bytes: Int64?, name: String?) throws -> InstallOffer {
        let body = try Canonical.data(InstallRequestBody(siliconForestBytes: bytes, installName: name))
        return try call { c in try Canonical.decoder().decode(InstallOffer.self, from: try c.call(timeout: 120) { $0.planInstall(request: body, reply: $1) }) }
    }

    /// The administrator prompt (system sheet). Throws if cancelled.
    public func requestAdmin(prompt: String) throws -> Data {
        let a = try AdminAuthorization.request(prompt: prompt)
        lock.lock(); approval = a; lock.unlock()
        return a.externalForm
    }

    public func confirm(planDigest: String, typed: TypedConfirmation, authorization: Data) throws -> ConfirmReply {
        defer { lock.lock(); approval = nil; lock.unlock() }
        let t = try Canonical.data(typed)
        return try call { c in try Canonical.decoder().decode(ConfirmReply.self, from: try c.call { $0.confirm(planDigest: planDigest, typed: t, authorization: authorization, reply: $1) }) }
    }

    public func begin(_ plan: EnginePlan) throws -> String { try call { try $0.begin(plan) } }

    // Preview13: the volume owner's login for the one-time bless (owner authentication on Apple Silicon).
    /// The local accounts that can unlock this Mac's startup disk (read-only).
    public func startupDiskOwners() throws -> StartupDiskOwners {
        try call { c in try Canonical.decoder().decode(StartupDiskOwners.self, from: try c.call(timeout: 30) { $0.startupOwners(reply: $1) }) }
    }
    /// Hands the helper the owner's login for this job's bless. The helper keeps it in locked memory, uses it once, wipes it.
    public func authorizeBless(job: String, owner: String, password: Data) throws {
        try call { c in try c.callVoid { $0.authorizeBless(job: job, owner: owner, password: password, reply: $1) } }
    }
    /// The finish screen's "Set Startup Disk": only the bless again, with this login.
    public func retryStartupSelection(job: String, owner: String, password: Data) throws -> BlessReport {
        try call { c in try Canonical.decoder().decode(BlessReport.self, from: try c.call(timeout: 90) { $0.retryStartupSelection(job: job, owner: owner, password: password, reply: $1) }) }
    }

    // Preview7: Remove SiliconForest, and the restart after a one-time bless.
    public func installs() throws -> [InstalledInstall] {
        try call { c in try Canonical.decoder().decode([InstalledInstall].self, from: try c.call { $0.listInstalls(reply: $1) }) }
    }
    public func offerRemoval(_ installJob: String) throws -> InstallOffer {
        try call { c in try Canonical.decoder().decode(InstallOffer.self, from: try c.call(timeout: 120) { $0.planRemoval(installJob: installJob, reply: $1) }) }
    }
    public func beginRemoval(installJob: String, plan: EnginePlan) throws -> String { try call { try $0.beginRemoval(installJob, digest: plan.digest) } }
    /// Preview13: asks an older helper process to exit so launchd starts the current binary at the next connection.
    /// Best effort and never fatal: a helper that doesn't know the verb (preview12 and earlier) idles out by itself.
    public func retireHelper() {
        _ = try? call { c in try c.callVoid { $0.retire(reply: $1) } }
    }
    public func shutDown(_ job: String) throws { try call { c in try c.callVoid { $0.shutDownToFinishSetup(job: job, reply: $1) } } }
    public func start(_ job: String) throws { try call { try $0.resume(job) } }
    public func rollback(_ job: String) throws { try call { try $0.rollback(job) } }

    public func progress(_ job: String, after: UInt64) throws -> LiveProgress {
        try call { c in try Canonical.decoder().decode(LiveProgress.self, from: try c.call { $0.progress(job: job, after: after, reply: $1) }) }
    }

    /// Polls until the job stops running; `onProgress` sees every reply (its `events` are only the new ones).
    @discardableResult
    public func follow(_ job: String, interval: TimeInterval = 0.5, onProgress: (LiveProgress) -> Void) throws -> LiveProgress {
        var seq: UInt64 = 0
        var misses = 0
        while true {
            do {
                let p = try progress(job, after: seq)
                misses = 0
                seq = p.lastSeq
                onProgress(p)
                if !p.running { return p }
            } catch {
                // A helper restart (launchd) drops the connection: reconnect a few times before giving up.
                misses += 1; reconnect()
                if misses > 20 { throw error }
            }
            Thread.sleep(forTimeInterval: interval)
        }
    }
}

/// What the app tells the person after the hand-off. Preview13: the helper made the stub the startup disk (a
/// persistent selection), so the next step is to shut down and start SiliconForest from startup options; a normal
/// start opens macOS until Setup has run. If bless failed, the manual command is shown.
public enum AfterHandoff {
    public static func blessCommand(installName: String) -> String { BlessGuard.manual(volumeName: installName) }

    /// The fallback every outcome shows.
    public static var fallback: String { StartupOptionsCopy.fallback("SiliconForest") }

    /// `command`: the exact command the helper worked out (it names the volume's real mount point); default: by name.
    public static func manualSteps(installName: String, command: String? = nil) -> [String] {
        ["In Terminal (macOS), if the volume isn't mounted: diskutil mount \"\(installName)\"",
         "Then: \(command ?? blessCommand(installName: installName))   (your Mac password)",
         "Shut down. Wait for the screen to go dark, then 25 more seconds.",
         StartupOptionsCopy.hold,
         "\(StartupOptionsCopy.choose(installName)) Enter your Mac password when asked: SiliconForest Setup finishes in recoveryOS (bputil, kmutil configure-boot), then starts SiliconForest."]
    }
}

/// The helper daemon's registration (SMAppService), as the app sees it.
public enum HelperRegistrationState: Sendable, Equatable {
    case enabled
    /// The person must turn the helper on in System Settings → General → Login Items.
    case requiresApproval
    /// Preview10: not registered yet (only a person's action registers it).
    case notRegistered
    case refused(String)
}

public enum HelperRegistrar {
    /// Where register failures are logged with the NSError's domain and code (the app log).
    nonisolated(unsafe) public static var log: (@Sendable (String) -> Void)?

    /// Preview13. `register()` failed. If macOS lists the helper but it is off ("Operation not permitted", "Job is not
    /// allowed to bootstrap", SMAppService error 1: a disabled Background Task Management item), that is the person's
    /// switch, not a failure of ours: ask them to turn it on. Anything else is refused, with the domain and code.
    public static func stateAfterRegisterError(domain: String, code: Int, message: String, status: HelperRegistrationState) -> HelperRegistrationState {
        if status == .enabled { return .enabled }
        if status == .requiresApproval { return .requiresApproval }
        let m = message.lowercased()
        if m.contains("operation not permitted") || m.contains("not allowed to bootstrap") || m.contains("not permitted")
            || ((domain == "SMAppServiceErrorDomain" || domain == NSPOSIXErrorDomain) && code == 1) {
            return .requiresApproval
        }
        return .refused("macOS didn't register the installer's helper: \(message) [\(domain) \(code)]")
    }

    /// Preview10: the status only (SMAppService.status). Never registers, never opens System Settings;
    /// the Privileges screen polls this quietly while the person approves the helper.
    public static func status() -> HelperRegistrationState {
        if let r = HelperRegistration.preflight() {
            switch r {
            case .notInApplications: return .refused("Move SiliconForest Installer to the Applications folder, then open it again.")
            case .notDeveloperIDSigned: return .refused("This copy of the installer isn't signed by SiliconForest's Developer ID.")
            }
        }
        switch HelperRegistration.status() {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered, .notFound: return .notRegistered
        @unknown default: return .notRegistered
        }
    }

    /// Registers (or re-checks) the helper. Only a Developer ID build in /Applications can.
    public static func register() -> HelperRegistrationState {
        if let r = HelperRegistration.preflight() {
            switch r {
            case .notInApplications: return .refused("Move SiliconForest Installer to the Applications folder, then open it again.")
            case .notDeveloperIDSigned: return .refused("This copy of the installer isn't signed by SiliconForest's Developer ID.")
            }
        }
        do {
            switch try HelperRegistration.register() {
            case .enabled: return .enabled
            case .requiresApproval: return .requiresApproval
            case .notRegistered, .notFound: return .refused("macOS didn't register the installer's helper.")
            @unknown default: return .refused("macOS reported an unknown helper state.")
            }
        } catch {
            let ns = error as NSError
            log?("helper register failed: \(ns.localizedDescription) [\(ns.domain) \(ns.code)]")
            return stateAfterRegisterError(domain: ns.domain, code: ns.code, message: ns.localizedDescription, status: status())
        }
    }


    /// Drops the helper. Used when this app build is not the one that last registered it.
    public static func unregister() -> HelperRegistrationState {
        if let r = HelperRegistration.preflight() {
            switch r {
            case .notInApplications: return .refused("Move SiliconForest Installer to the Applications folder, then open it again.")
            case .notDeveloperIDSigned: return .refused("This copy of the installer isn't signed by SiliconForest's Developer ID.")
            }
        }
        do {
            try HelperRegistration.unregister()
            return .notRegistered
        } catch {
            return status()
        }
    }
}

/// Keeps a KVO observation alive for as long as its URLSession task, then drops it.
enum ObservationBox {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var held: [Int: NSKeyValueObservation] = [:]
    static func hold(_ o: NSKeyValueObservation, for task: URLSessionTask) {
        lock.lock(); held[task.taskIdentifier] = o; lock.unlock()
        // Released when the task is gone: poll cheaply instead of subclassing the session.
        DispatchQueue.global().async {
            while task.state == .running || task.state == .suspended { Thread.sleep(forTimeInterval: 0.5) }
            lock.lock(); held[task.taskIdentifier] = nil; lock.unlock()
        }
    }
}
