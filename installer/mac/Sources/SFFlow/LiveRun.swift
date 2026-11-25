// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// The real install's half of the session (preview6): everything the live screens show and do, through
// LiveInstallController (the same calls sfappimage makes on a disk image).

import SwiftUI
import SFInstallKit
import SFEngine
import SFHelperKit
import SFLiveDisk
import SFAppEngine
import SFDesign

@MainActor
public final class LiveRun: ObservableObject {
    public struct StepRow: Identifiable, Sendable {
        public var code: String
        public var title: String
        public var writesDisk: Bool
        public var state: RowState
        public var started: Date?
        public var seconds: Double?
        public var id: String { code }
    }

    public enum Activity: Equatable, Sendable {
        case idle
        case registering
        case waitingForHelperApproval
        case downloading(file: String, done: Int64, total: Int64)
        case importing
        case planning
        case waitingForAdmin
        case starting
        case running
        case done
        case failed(String)
    }

    @Published public var activity: Activity = .idle
    @Published public var offer: InstallOffer?
    @Published public var typedName = ""
    @Published public var typedPhrase = ""
    @Published public var release: ReleaseSummary?
    @Published public var job: String?
    @Published public var rows: [StepRow] = []
    @Published public var currentCode: String?
    @Published public var detail = ""
    @Published public var bytesDone: Int64 = 0
    @Published public var bytesTotal: Int64 = 0
    @Published public var bytesPhase = ""
    @Published public var diskutilPercent: Int?
    @Published public var diskutilLine = ""
    @Published public var journal: [String] = []
    @Published public var startedAt: Date?
    @Published public var end: String?
    @Published public var lastError: String?
    @Published public var approvals: [ApprovalNeeded] = []
    @Published public var unfinished: [String] = []
    @Published public var installName = "SiliconForest"
    @Published public var noChangesMade = true
    @Published public var now = Date()
    /// For a resumed job: what to type to confirm its plan again.
    @Published public var resumeExpected: TypedConfirmation?

    public let controller: LiveInstallController
    @Published public var origin: ReleaseOrigin
    public weak var session: Session?
    private let register: (@Sendable () throws -> HelperRegistrationState)?
    private var following = false
    private var clock: Timer?

    public init(controller: LiveInstallController, origin: ReleaseOrigin, register: (@Sendable () throws -> HelperRegistrationState)?) {
        self.controller = controller; self.origin = origin; self.register = register
    }

    // MARK: derived

    public var elapsed: TimeInterval { startedAt.map { now.timeIntervalSince($0) } ?? 0 }
    public var overall: Double {
        guard !rows.isEmpty else { return 0 }
        let done = Double(rows.filter { $0.state == .pass || $0.state == .skipped }.count)
        var cur = 0.0
        if currentCode == "S47", bytesTotal > 0 { cur = Double(bytesDone) / Double(bytesTotal) * (bytesPhase == "read-back" ? 1 : 0.5) }
        if currentCode == "S25", let p = diskutilPercent { cur = Double(p) / 100 }
        return min(1, (done + cur) / Double(rows.count))
    }
    public var typedMatches: Bool {
        guard let e = offer?.expected ?? resumeExpected else { return false }
        return TypedConfirmation(diskName: typedName, phrase: typedPhrase).matches(e)
    }
    public var isWorking: Bool {
        switch activity { case .registering, .waitingForHelperApproval, .downloading, .importing, .planning, .waitingForAdmin, .starting: return true; default: return false }
    }

    // MARK: actions

    private func background<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { c in DispatchQueue.global(qos: .userInitiated).async { c.resume(with: Result { try work() }) } }
    }

    private func ensureHelper() async throws {
        guard let register else { return }
        activity = .registering
        var state = try await background(register)
        while state == .requiresApproval {
            activity = .waitingForHelperApproval
            HelperRegistration.openLoginItems()
            try await Task.sleep(nanoseconds: 2_000_000_000)
            state = try await background(register)
        }
        if case .refused(let why) = state { throw LiveError(why) }
    }

    /// At launch: an unfinished job (the app quit or crashed, or the Mac restarted) is offered for resume.
    public func lookForUnfinishedJobs() {
        Task {
            guard (try? await background({ [register] in try register?() ?? .enabled })) == .enabled else { return }
            if let jobs = try? await background({ [controller] in try controller.unfinishedJobs() }), !jobs.isEmpty {
                unfinished = jobs
                session?.go(.liveResume)
            }
        }
    }

    /// After Review: register the helper, fetch and verify the release, hand it to the helper, plan.
    public func prepare(bytes: Int64?, name: String) {
        session?.go(.liveFetch)
        lastError = nil
        Task {
            do {
                try await ensureHelper()
                activity = .downloading(file: "SHA256SUMS", done: 0, total: 0)
                let fetcher = ReleaseFetcher()
                let local = try await fetcher.fetch(origin) { [weak self] f, d, t in
                    Task { @MainActor in self?.activity = .downloading(file: f, done: d, total: t) }
                }
                activity = .importing
                let c = controller
                release = try await background { try c.importRelease(local.dir) }
                activity = .planning
                offer = try await background { try c.offer(bytes: bytes, name: name) }
                typedName = ""; typedPhrase = ""
                activity = .idle
                session?.go(.liveConfirm)
            } catch {
                fail(error)
            }
        }
    }

    /// The Install button: administrator approval, the helper's confirmation (it writes the runtime
    /// authorization for this plan and disk), then begin and start.
    public func install() {
        guard let offer, typedMatches else { return }
        let typed = TypedConfirmation(diskName: typedName, phrase: typedPhrase)
        Task {
            do {
                activity = .waitingForAdmin
                let c = controller
                let auth = try await background { try c.requestAdmin(prompt: "SiliconForest Installer wants to change your disk: \(offer.expected.phrase).") }
                _ = try await background { try c.confirm(planDigest: offer.plan.digest, typed: typed, authorization: auth) }
                activity = .starting
                let j = try await background { try c.begin(offer.plan) }
                job = j
                installName = offer.plan.request?.installName ?? "SiliconForest"
                rows = offer.steps.map { StepRow(code: $0.code, title: $0.title, writesDisk: $0.writesDisk, state: .waiting) }
                try await background { try c.start(j) }
                follow(j)
            } catch {
                fail(error)
            }
        }
    }

    /// Resume after a quit, crash or restart. If the helper restarted or the 2 hours ran out, the person
    /// confirms again (the same typed words and an administrator) before anything continues.
    public func resume(_ j: String) {
        job = j
        Task {
            do {
                try await ensureHelper()
                let c = controller
                let p = try await background { try c.progress(j, after: 0) }
                absorb(p, replaceRows: true)
                do { try await background { try c.start(j) } } catch {
                    let ns = error as NSError
                    guard ns.localizedDescription.contains("gate is closed") || ns.localizedDescription.contains("authorization") else { throw error }
                    lastError = "Confirm again to continue: \(ns.localizedDescription)"
                    activity = .failed(lastError!)
                    session?.go(.liveStopped)
                    return
                }
                follow(j)
            } catch {
                fail(error)
            }
        }
    }

    /// Re-confirm for an unfinished job (its own plan), then continue.
    public func reconfirmAndResume() {
        guard let j = job else { return }
        let typed = TypedConfirmation(diskName: typedName, phrase: typedPhrase)
        Task {
            do {
                let c = controller
                let p = try await background { try c.progress(j, after: 0) }
                guard let digest = p.planDigest else { throw LiveError("the job has no plan") }
                let auth = try await background { try c.requestAdmin(prompt: "SiliconForest Installer wants to continue changing your disk.") }
                _ = try await background { try c.confirm(planDigest: digest, typed: typed, authorization: auth) }
                try await background { try c.start(j) }
                follow(j)
            } catch { fail(error) }
        }
    }

    /// "Use a Folder…": a local copy of the signed release (every file SHA256SUMS lists, plus the sums and signature).
    public func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "Choose the folder with the signed SiliconForest release (SHA256SUMS, SHA256SUMS.sig and the files it lists)."
        guard panel.runModal() == .OK, let u = panel.url else { return }
        origin = .folder(u)
        session?.startInstall()
    }

    public func rollback() {
        guard let j = job else { return }
        Task {
            do {
                let c = controller
                try await background { try c.rollback(j) }
                follow(j)
            } catch { fail(error) }
        }
    }

    private func fail(_ error: Error) {
        let m = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
        lastError = m
        activity = .failed(m)
        session?.go(job == nil ? .liveFetch : .liveStopped)
    }

    private func follow(_ j: String) {
        guard !following else { return }
        following = true
        activity = .running
        session?.go(.liveInstalling)
        clock?.invalidate()
        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.now = Date() } }
        let c = controller
        Task.detached { [weak self] in
            let result = Result { try c.follow(j) { p in Task { @MainActor in self?.absorb(p, replaceRows: false) } } }
            await MainActor.run {
                guard let self else { return }
                self.following = false
                self.clock?.invalidate()
                switch result {
                case .success(let p):
                    self.absorb(p, replaceRows: false)
                    if p.end == "handed-off" { self.activity = .done; self.session?.go(.liveFinish) }
                    else if p.end == "rolled-back" { self.activity = .done; self.session?.go(.liveStopped) }
                    else { self.lastError = p.lastError ?? "the installer stopped"; self.activity = .failed(self.lastError!); self.session?.go(.liveStopped) }
                case .failure(let e): self.fail(e)
                }
            }
        }
    }

    func absorb(_ p: LiveProgress, replaceRows: Bool) {
        if replaceRows || rows.isEmpty {
            rows = p.steps.map { StepRow(code: $0.code, title: $0.title, writesDisk: $0.writesDisk, state: .waiting) }
        }
        if let s = p.startedAt, startedAt == nil {
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            startedAt = f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        }
        installName = p.installName ?? installName
        end = p.end; approvals = p.approvals; noChangesMade = p.noChangesMade
        if let x = p.expected { resumeExpected = x }
        if let e = p.lastError { lastError = e }
        for e in p.events {
            switch e.kind {
            case "step":
                if let cur = currentCode, cur != e.step, let i = rows.firstIndex(where: { $0.code == cur }), rows[i].state == .working {
                    rows[i].state = .pass
                    rows[i].seconds = rows[i].started.map { Date(timeIntervalSince1970: e.time).timeIntervalSince($0) }
                }
                currentCode = e.step; detail = ""; bytesDone = 0; bytesTotal = 0; diskutilPercent = nil
                if let i = rows.firstIndex(where: { $0.code == e.step }) { rows[i].state = .working; rows[i].started = Date(timeIntervalSince1970: e.time) }
            case "bytes": bytesDone = e.done ?? 0; bytesTotal = e.total ?? 0; bytesPhase = e.text
            case "resize": diskutilPercent = e.percent ?? diskutilPercent; diskutilLine = e.text
            case "progress": detail = e.text
            default: break
            }
            journal.append("\(Self.clockString(e.time))  \(e.step)  \(e.kind == "step" ? "" : e.kind + " ")\(e.text)")
        }
        if journal.count > 400 { journal.removeFirst(journal.count - 400) }
        // The journal is the truth: completed and failed steps from it, whatever the events said.
        for i in rows.indices {
            if p.completed.contains(rows[i].code) { rows[i].state = .pass }
            else if p.failed[rows[i].code] != nil { rows[i].state = .fail }
            else if !p.running, rows[i].state == .working { rows[i].state = .waiting }
        }
        if !p.running { currentCode = nil }
    }

    static func clockString(_ t: Double) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: Date(timeIntervalSince1970: t))
    }
}
