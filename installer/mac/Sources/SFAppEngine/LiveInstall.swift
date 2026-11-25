// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// The installer app's real install (preview6), without any UI: download the signed release (or take a
// local folder), verify it, hand it to the helper, plan, confirm, start, follow progress, resume. The
// Session drives exactly these calls; `sfappimage` drives the same calls against a disk image on the M5.

import Foundation
import ServiceManagement
import SFEngine
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

    /// (file, bytes so far, total bytes of this file)
    public typealias Progress = @Sendable (String, Int64, Int64) -> Void

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
        for (i, e) in entries.enumerated() {
            let dest = dir.appendingPathComponent(e.name)
            if let h = try? FileHandle(forReadingFrom: dest), (try? SHA256Hasher.stream(h, limit: Int64.max)) == e.sha256 { try? h.close(); continue }
            progress?(e.name, 0, Int64(i))
            switch origin {
            case .github(let tag):
                let url = URL(string: "https://github.com/\(ReleaseOrigin.repository)/releases/download/\(tag)/\(e.name)")!
                let (tmp, resp) = try await session.download(from: url)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw LiveError("couldn't download \(e.name)") }
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tmp, to: dest)
            case .folder(let u):
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: u.appendingPathComponent(e.name), to: dest)
            }
            let h = try FileHandle(forReadingFrom: dest); defer { try? h.close() }
            guard try SHA256Hasher.stream(h, limit: Int64.max) == e.sha256 else { throw LiveError("\(e.name) doesn't match SHA256SUMS") }
            progress?(e.name, Int64(i + 1), Int64(entries.count))
        }
        let m: ReleaseManifest
        do { m = try SFRelease.verify(directory: dir, allowedSigners: allowedSigners, allowRehearsal: false) }
        catch let r as SFRelease.Refusal { throw LiveError("the release doesn't verify: \(r.reason)") }
        try StagePin.check(m)
        return (dir, m)
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

/// What the app tells the person to do after the hand-off. Bless stays a step the person runs (the
/// installer never runs bless, bputil, kmutil or nvram itself).
public enum AfterHandoff {
    public static func blessCommand(installName: String) -> String {
        "sudo /usr/sbin/bless --mount \"/Volumes/\(installName)\" --setBoot --nextonly"
    }
    public static func steps(installName: String) -> [String] {
        ["In Terminal (macOS), if the volume isn't mounted: diskutil mount \"\(installName)\"",
         "Then: \(blessCommand(installName: installName))   (your Mac password)",
         "Shut down. Wait for the screen to go dark, then 25 more seconds.",
         "Press and hold the power button until you see “Loading startup options”.",
         "Choose \(installName), then Continue. Enter your Mac password when asked: SiliconForest Setup finishes in recoveryOS (bputil, kmutil configure-boot), then restarts into SiliconForest."]
    }
}

/// The helper daemon's registration (SMAppService), as the app sees it.
public enum HelperRegistrationState: Sendable, Equatable {
    case enabled
    /// The person must turn the helper on in System Settings → General → Login Items.
    case requiresApproval
    case refused(String)
}

public enum HelperRegistrar {
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
            if HelperRegistration.status() == .requiresApproval { return .requiresApproval }
            if HelperRegistration.status() == .enabled { return .enabled }
            return .refused("macOS didn't register the installer's helper: \(error.localizedDescription)")
        }
    }
}
