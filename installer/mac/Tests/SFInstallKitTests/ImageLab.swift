import Foundation
import Testing
@testable import SFEngine
import SFInstallKit

/// Shared scaffolding for the image-backed tests: template images built once per run, cloned per
/// test with clonefile, a rehearsal release, and cleanup that detaches and deletes everything.
enum ImageLab {
    static let root = ImageGuard.defaultRoot
    static let templates = root.appendingPathComponent("templates", isDirectory: true)
    static let runs = root.appendingPathComponent("runs", isDirectory: true)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var built: [ImageFixtures.Layout: URL] = [:]
    nonisolated(unsafe) private static var releaseCache: (ReleaseManifest, URL)?

    /// Image tests run unless SF_IMAGE_TESTS=0 (they need hdiutil and a few GB of free space).
    static var enabled: Bool { ProcessInfo.processInfo.environment["SF_IMAGE_TESTS"] != "0" }
    /// The every-record kill sweep runs in full with SF_FULL_SWEEP=1; otherwise a fixed sample.
    static var fullSweep: Bool { ProcessInfo.processInfo.environment["SF_FULL_SWEEP"] == "1" }
    /// SF_SWEEP_RECORDS=9,13 forks only at those records (debugging).
    static var sweepRecords: Set<UInt64>? {
        ProcessInfo.processInfo.environment["SF_SWEEP_RECORDS"].map { Set($0.split(separator: ",").compactMap { UInt64($0) }) }
    }

    static func template(_ layout: ImageFixtures.Layout) throws -> URL {
        lock.lock(); defer { lock.unlock() }
        if let u = built[layout], FileManager.default.fileExists(atPath: u.path) { return u }
        // Reused across runs while the fixture format is unchanged (SF_REBUILD_TEMPLATES=1 forces a rebuild).
        let name = "\(layout.rawValue)-v\(ImageFixtures.version)"
        let existing = templates.appendingPathComponent("\(name).sparseimage")
        if FileManager.default.fileExists(atPath: existing.path), ProcessInfo.processInfo.environment["SF_REBUILD_TEMPLATES"] != "1" {
            built[layout] = existing
            return existing
        }
        let u = try ImageFixtures.create(layout, in: templates, name: name)
        built[layout] = u
        return u
    }

    static func release() throws -> (ReleaseManifest, URL) {
        lock.lock(); defer { lock.unlock() }
        if let r = releaseCache { return r }
        let dir = root.appendingPathComponent("release", isDirectory: true)
        let m = try RehearsalRelease.make(in: dir)
        releaseCache = (m, dir)
        return (m, dir)
    }

    struct Case {
        var dir: URL
        var image: URL
        var backend: DiskImageBackend
        var journalDir: URL { dir.appendingPathComponent("journal", isDirectory: true) }
        var workDir: URL { dir.appendingPathComponent("work", isDirectory: true) }

        func finish() {
            try? backend.detach(force: true)
            // SF_KEEP=1 keeps the detached image and journal for inspection.
            if ProcessInfo.processInfo.environment["SF_KEEP"] != "1" { try? FileManager.default.removeItem(at: dir) }
        }
    }

    /// A fresh, attached copy of a template.
    static func fresh(_ layout: ImageFixtures.Layout, name: String = UUID().uuidString) throws -> Case {
        let t = try template(layout)
        let dir = runs.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let img = try ImageFixtures.clone(t, to: dir.appendingPathComponent("\(layout.rawValue).sparseimage"))
        let b = DiskImageBackend(imagePath: img)
        try b.attach()
        return Case(dir: dir, image: img, backend: b)
    }

    /// Detaches a case's image, clones its file and journal into a second case, and attaches only the
    /// copy. A clone carries the same partition and APFS UUIDs, so the two are never attached at the
    /// same time: the caller reattaches the original (`c.backend.attach()`) when it needs it again.
    static func fork(_ c: Case, journal: ChainJournal) throws -> (Case, ChainJournal) {
        // A helper never detaches under a live resize: let any we started finish first.
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline, journal.records.contains(where: { r in
            guard let pid = r.args?["resize_pid"]?.int else { return false }
            return SpawnLauncher().reattach(pid: Int32(pid))?.isRunning() == true
        }) { Thread.sleep(forTimeInterval: 0.1) }
        if c.backend.isAttached(), (try? c.backend.detach(force: false)) == nil { try c.backend.detach(force: true) }
        let dir = runs.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let img = try ImageFixtures.clone(c.image, to: dir.appendingPathComponent(c.image.lastPathComponent))
        let jdir = dir.appendingPathComponent("journal", isDirectory: true)
        try FileManager.default.createDirectory(at: jdir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: journal.url, to: jdir.appendingPathComponent(journal.url.lastPathComponent))
        if FileManager.default.fileExists(atPath: c.workDir.path) {
            try FileManager.default.copyItem(at: c.workDir, to: dir.appendingPathComponent("work"))
        }
        let b = DiskImageBackend(imagePath: img)
        try b.attach()
        let copy = Case(dir: dir, image: img, backend: b)
        return (copy, try ChainJournal(directory: jdir, jobID: journal.jobID))
    }

    static func profile(_ id: String = "J293") throws -> DeviceProfile { try #require(ProfileStore.profile(id: id)) }

    static func plan(_ c: Case, profile: DeviceProfile, sf: Int64 = 20 * Bytes.gb) throws -> EnginePlan {
        let (release, _) = try release()
        let t = try c.backend.topology()
        let mac = try #require(t.macOS)
        return try EnginePlanner.installPlan(topology: t, limits: try c.backend.limits(store: mac.uuid), profile: profile, release: release,
                                             request: InstallRequest(siliconForestBytes: sf, installName: "SiliconForest", installID: "a1b2c3d4"))
    }

    static func engine(_ c: Case, journal: ChainJournal, profile: DeviceProfile, faults: FaultPlan = FaultPlan(),
                       launcher: ResizeLauncher = SpawnLauncher()) throws -> InstallEngine {
        let (release, src) = try release()
        return InstallEngine(backend: c.backend, journal: journal, profile: profile, release: release, releaseSource: src,
                             workDir: c.workDir, faults: faults, launcher: launcher, resizeTiming: .tests)
    }

    static func cleanUpAll() { ImageFixtures.cleanUp(root) }
}
