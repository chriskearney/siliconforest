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
        public init(code: String, title: String, writesDisk: Bool, state: RowState, started: Date? = nil, seconds: Double? = nil) {
            self.code = code; self.title = title; self.writesDisk = writesDisk; self.state = state; self.started = started; self.seconds = seconds
        }
    }

    public enum Activity: Equatable, Sendable {
        case idle
        case registering
        case waitingForHelperApproval
        case downloading(FetchProgress)
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
    // Preview7
    /// Finished installs the helper has journals for (Remove SiliconForest).
    @Published public var installs: [InstalledInstall] = []
    @Published public var installsLoaded = false
    /// The current job (or the offer being confirmed) is a removal.
    @Published public var isRemoval = false
    /// What S65 did (the startup disk), once the install has finished.
    @Published public var blessReport: BlessReport?
    @Published public var shuttingDown = false
    @Published public var shutDownError: String?
    /// Preview13: the volume owner's login for `bless`. Typed on the Confirm screen (optional) or the finish screen.
    @Published public var startupOwners: StartupDiskOwners?
    @Published public var startupOwner = ""
    @Published public var startupPassword = ""
    @Published public var settingStartupDisk = false
    @Published public var startupDiskError: String?
    private var removalTarget: String?
    // Preview10: the up-front privilege check.
    /// Where the person goes once every privilege is in place.
    public enum PrivilegeNext: Equatable, Sendable { case check, removal, install(bytes: Int64?, name: String), resume(String) }
    @Published public var privileges: PrivilegeStage = .checking
    /// What the installer was doing when it failed (so the right row shows the failure).
    @Published public var failedDuring: Activity?
    public private(set) var privilegeNext: PrivilegeNext = .check
    private var failedPrivilegeMessage: String {
        if case .failed(let m) = privileges { return m }
        return lastError ?? ""
    }
    public let gate: PrivilegeGate
    private var pollTask: Task<Void, Never>?
    /// Seconds between the Privileges screen's quiet checks.
    public var pollInterval: Double = 2
    public let log: InstallerLog
    /// Where the app's and the helper's logs are (shown with every error).
    public var appLogPath: String { log.file?.path ?? InstallerLog.appLogURL().path }
    public var helperLogPath: String { InstallerLog.helperLogURL.path }
    /// The app bundle (for SFHelper's path in the Full Disk Access instructions).
    public var appBundle: URL = Bundle.main.bundleURL

    public let controller: LiveInstallController
    @Published public var origin: ReleaseOrigin
    public weak var session: Session?
    private let register: (@Sendable () throws -> HelperRegistrationState)?
    private let status: (@Sendable () -> HelperRegistrationState)?
    private var following = false
    private var clock: Timer?

    /// `register`/`status`: SMAppService (nil in tests and snapshots: the helper counts as approved).
    /// `hooks` replaces the whole privilege check (tests).
    private let unregister: (@Sendable () throws -> HelperRegistrationState)?

    public init(controller: LiveInstallController, origin: ReleaseOrigin, register: (@Sendable () throws -> HelperRegistrationState)?,
                status: (@Sendable () -> HelperRegistrationState)? = nil,
                unregister: (@Sendable () throws -> HelperRegistrationState)? = nil,
                hooks: PrivilegeGate.Hooks? = nil, log: InstallerLog = InstallerLog.app) {
        self.controller = controller; self.origin = origin; self.register = register; self.status = status
        self.unregister = unregister; self.log = log
        let reg = register, st = status, unreg = unregister
        gate = PrivilegeGate(hooks ?? PrivilegeGate.Hooks(
            register: { try reg?() ?? .enabled },
            status: { st?() ?? (reg == nil ? .enabled : .notRegistered) },
            probe: { [controller] in try controller.privileges() },
            openLoginItems: { DispatchQueue.main.async { if #available(macOS 13.0, *) { HelperRegistration.openLoginItems() } else { SystemLinks.open(.loginItems) } } },
            openFullDiskAccess: { DispatchQueue.main.async { SystemLinks.open(.fullDiskAccess) } },
            unregister: { try unreg?() ?? .notRegistered },
            reconnect: { [controller] in controller.reconnect() },
            // Tests and snapshots pass no registrar: don't touch UserDefaults or restart a helper.
            build: reg == nil ? nil : HelperBuildMemory.app(),
            retire: { [controller] in controller.retireHelper() }))
        gate.log = { [log] in log.info($0) }
        if reg != nil { HelperRegistrar.log = { [log] in log.error($0) } }
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
        return TypedConfirmation(diskName: typedName).matches(e)
    }
    public var isWorking: Bool {
        switch activity { case .registering, .waitingForHelperApproval, .downloading, .importing, .planning, .waitingForAdmin, .starting: return true; default: return false }
    }

    // MARK: actions

    private func background<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { c in DispatchQueue.global(qos: .userInitiated).async { c.resume(with: Result { try work() }) } }
    }

    // MARK: privileges (preview10)

    /// Get Started, Remove SiliconForest…, or helper work that found something missing: the Privileges
    /// screen. It registers the helper if needed (the person clicked), then checks quietly until everything
    /// is in place and continues to `next` by itself. System Settings opens only from its buttons.
    public func checkPrivileges(then next: PrivilegeNext) {
        privilegeNext = next
        lastError = nil
        log.info("privileges: checking before \(next)")
        if privileges != .ready { privileges = gate.willRefreshHelper() ? .restartingHelper : .checking }
        session?.go(.livePrivileges)
        runPrivilegeCheck(byPerson: true)
    }

    /// The Privileges screen's "Check Again".
    public func checkPrivilegesAgain() {
        if gate.willRefreshHelper() || PrivilegeGate.isStaleHelperMessage(failedPrivilegeMessage) {
            privileges = .restartingHelper
        }
        runPrivilegeCheck(byPerson: true)
    }
    /// "Open Login Items": one System Settings open for this click; then the quiet checks carry on.
    public func openLoginItems() { gate.userOpensLoginItems(); startPolling() }
    /// "Open Full Disk Access Settings": one System Settings open for this click.
    public func openFullDiskAccess() { gate.userOpensFullDiskAccess(); startPolling() }
    /// Preview13: the Full Disk Access pane opens, and SFHelper is selected in Finder so it can be dragged into the list.
    public func openFullDiskAccessAndRevealHelper() {
        openFullDiskAccess()
        revealHelper()
    }
    /// Shows SFHelper in a Finder window (no Settings open).
    public func revealHelper() {
        let path = helperPath
        if !HelperReveal.revealInFinder(path: path) { log.info("privileges: SFHelper not found at \(path); nothing to reveal") }
        else { log.info("privileges: revealed SFHelper in Finder") }
    }
    /// Copies the helper's path to the pasteboard.
    public func copyHelperPath() { HelperReveal.copyPath(helperPath); log.info("privileges: copied the SFHelper path") }
    public var helperPath: String { PrivilegeGate.helperPath(appBundle: appBundle) }

    private func runPrivilegeCheck(byPerson: Bool) {
        Task {
            let g = gate
            let st = await withCheckedContinuation { c in DispatchQueue.global(qos: .userInitiated).async { c.resume(returning: g.check(byPerson: byPerson)) } }
            absorbPrivileges(st)
        }
    }

    func absorbPrivileges(_ st: PrivilegeStage) {
        privileges = st
        switch st {
        case .ready:
            stopPolling()
            guard session?.screen == .livePrivileges else { return }
            continueAfterPrivileges()
        case .needsHelperApproval, .needsFullDiskAccess: startPolling()
        case .failed(let m): startPolling(); log.error("privileges: \(m)")
        case .checking, .restartingHelper: break
        }
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(nanoseconds: UInt64(self.pollInterval * 1_000_000_000))
                guard !Task.isCancelled, self.session?.screen == .livePrivileges, self.privileges.isWaiting else { break }
                let g = self.gate
                let st = await withCheckedContinuation { c in DispatchQueue.global(qos: .utility).async { c.resume(returning: g.check(byPerson: false)) } }
                guard !Task.isCancelled else { break }
                self.privileges = st
                if !st.isWaiting { self.pollTask = nil; self.absorbPrivileges(st); return }
            }
            self?.pollTask = nil
        }
    }

    private func stopPolling() { pollTask?.cancel(); pollTask = nil }

    private func continueAfterPrivileges() {
        log.info("privileges: ready; continuing to \(privilegeNext)")
        switch privilegeNext {
        case .check: session?.go(.check)
        case .removal: loadRemoval()
        case .install(let b, let n): fetchAndPlan(bytes: b, name: n)
        case .resume(let j): resume(j)
        }
    }

    /// Before helper work: a quiet re-check (no System Settings). If something is missing, the
    /// Privileges screen takes over and `next` continues once it is fixed.
    private func privilegesStillReady(_ next: PrivilegeNext) async -> Bool {
        if register == nil && status == nil { return true }
        let g = gate
        let st = await withCheckedContinuation { c in DispatchQueue.global(qos: .userInitiated).async { c.resume(returning: g.check(byPerson: true)) } }
        privileges = st
        if st == .ready { return true }
        privilegeNext = next
        session?.go(.livePrivileges)
        absorbPrivileges(st)
        return false
    }

    /// A Full Disk Access denial reported by the helper in the middle of something.
    private func isFullDiskAccessDenial(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == HelperError.domain && ns.code == HelperErrorCode.needsFullDiskAccess.rawValue
    }

    /// At launch: an unfinished job (the app quit or crashed, or the Mac restarted) is offered for resume.
    /// Preview10: reads SMAppService's status only (it no longer registers the helper at launch).
    public func lookForUnfinishedJobs() {
        Task {
            guard (try? await background({ [status, register] in status?() ?? (register == nil ? .enabled : .notRegistered) })) == .enabled else { return }
            if let jobs = try? await background({ [controller] in try controller.unfinishedJobs() }), !jobs.isEmpty {
                unfinished = jobs
                session?.go(.liveResume)
            }
        }
    }

    /// After Review: register the helper, fetch and verify the release, hand it to the helper, plan.
    public func prepare(bytes: Int64?, name: String) {
        lastBytes = bytes; lastName = name
        if (register != nil || status != nil) && privileges != .ready { checkPrivileges(then: .install(bytes: bytes, name: name)); return }
        fetchAndPlan(bytes: bytes, name: name)
    }
    private var lastBytes: Int64?
    private var lastName = "SiliconForest"

    private func fetchAndPlan(bytes: Int64?, name: String) {
        session?.go(.liveFetch)
        lastError = nil; failedDuring = nil
        Task {
            do {
                guard await privilegesStillReady(.install(bytes: bytes, name: name)) else { return }
                log.info("fetch: downloading the release (\(origin))")
                activity = .downloading(FetchProgress(file: "SHA256SUMS", filesDone: 0, filesTotal: 0, bytes: 0))
                let fetcher = ReleaseFetcher()
                let smoother = FetchProgressSmoother()
                let local = try await fetcher.fetch(origin) { [weak self] f, d, t, b in
                    guard let p = smoother.accept(file: f, done: d, total: t, bytes: b) else { return }
                    Task { @MainActor in
                        // Never let a late update replace a newer one, or the total change on screen.
                        if case .downloading(let old) = self?.activity, old.filesTotal > 0, p.filesTotal != old.filesTotal || p.filesDone < old.filesDone { return }
                        self?.activity = .downloading(p)
                    }
                }
                activity = .importing
                log.info("fetch: verified \(local.dir.lastPathComponent); handing it to the helper")
                let c = controller
                release = try await background { try c.importRelease(local.dir) }
                activity = .planning
                log.info("plan: asking the helper to read the disk and plan")
                offer = try await background { try c.offer(bytes: bytes, name: name) }
                log.info("plan: offered \(offer?.plan.digest.prefix(12) ?? "")")
                await loadStartupOwners()
                typedName = ""
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
        let typed = TypedConfirmation(diskName: typedName)
        Task {
            do {
                activity = .waitingForAdmin
                let c = controller
                let auth = try await background { try c.requestAdmin(prompt: "SiliconForest Installer \(offer.plan.operation == .remove ? "wants to remove SiliconForest from your disk." : "wants to take \(offer.gigabytes) GB from macOS to install SiliconForest.")") }
                _ = try await background { try c.confirm(planDigest: offer.plan.digest, typed: typed, authorization: auth) }
                activity = .starting
                let removeJob = removalTarget
                let removing = offer.plan.operation == .remove
                let j = try await background { removing ? try c.beginRemoval(installJob: removeJob ?? "", plan: offer.plan) : try c.begin(offer.plan) }
                job = j
                await passStartupLogin(job: j)
                isRemoval = removing
                startedAt = nil; journal = []; blessReport = nil
                installName = offer.plan.request?.installName ?? installName
                rows = offer.steps.map { StepRow(code: $0.code, title: $0.title, writesDisk: $0.writesDisk, state: .waiting) }
                try await background { try c.start(j) }
                follow(j)
            } catch {
                fail(error)
            }
        }
    }

    // MARK: Remove SiliconForest (preview7)

    /// Welcome → "Remove SiliconForest…": the installs the helper's journals prove.
    public func showRemoval() {
        if (register != nil || status != nil) && privileges != .ready { checkPrivileges(then: .removal); return }
        loadRemoval()
    }

    private func loadRemoval() {
        session?.go(.liveRemoveList)
        lastError = nil; installsLoaded = false; installs = []
        Task {
            do {
                guard await privilegesStillReady(.removal) else { return }
                let c = controller
                installs = try await background { try c.installs() }
                installsLoaded = true; activity = .idle
            } catch {
                if isFullDiskAccessDenial(error) { routeToPrivileges(error, next: .removal); return }
                installsLoaded = true; lastError = describe(error); activity = .idle
                log.error("remove: couldn't list installs: \(lastError ?? "")")
            }
        }
    }

    public func chooseRemoval(_ install: InstalledInstall) {
        lastError = nil; activity = .planning
        Task {
            do {
                let c = controller
                offer = try await background { try c.offerRemoval(install.job) }
                removalTarget = install.job
                installName = install.name
                isRemoval = true
                typedName = ""
                await loadStartupOwners()
                activity = .idle
                session?.go(.liveRemoveConfirm)
            } catch {
                if isFullDiskAccessDenial(error) { routeToPrivileges(error, next: .removal); return }
                lastError = describe(error); activity = .idle
                log.error("remove: couldn't plan the removal: \(lastError ?? "")")
            }
        }
    }

    // MARK: the startup disk's owner login (preview13)

    /// The accounts that can unlock the startup disk, for the picker. Never fatal: without them the install still runs.
    public func loadStartupOwners() async {
        if startupOwners != nil { return }
        let c = controller
        do {
            let o = try await background { try c.startupDiskOwners() }
            startupOwners = o
            if startupOwner.isEmpty || !o.owners.contains(startupOwner) { startupOwner = o.defaultOwner ?? "" }
            log.info("startup disk: \(o.owners.count) account(s) can unlock it\(o.defaultOwner.map { " (default \($0))" } ?? "")")
        } catch { log.error("startup disk: couldn't read the accounts that can unlock it: \(describe(error))") }
    }

    /// Before the job starts: hands the helper the login the person typed (if they did). It is cleared here at once.
    private func passStartupLogin(job j: String) async {
        guard !startupPassword.isEmpty, !startupOwner.isEmpty else { return }
        let owner = startupOwner
        let pw = Data(startupPassword.utf8)
        startupPassword = ""
        let c = controller
        do {
            try await background { try c.authorizeBless(job: j, owner: owner, password: pw) }
            log.info("startup disk: the helper holds the login for \(owner) (in memory only)")
        } catch {
            log.error("startup disk: the helper didn't take the login: \(describe(error)); the finish screen can set it")
        }
    }

    /// The finish screen's "Set Startup Disk": only the bless again, with the login typed there.
    public func setStartupDisk() {
        guard let j = job, !settingStartupDisk, !startupPassword.isEmpty, !startupOwner.isEmpty else { return }
        settingStartupDisk = true; startupDiskError = nil
        let owner = startupOwner
        let pw = Data(startupPassword.utf8)
        startupPassword = ""
        Task {
            do {
                let c = controller
                let r = try await background { try c.retryStartupSelection(job: j, owner: owner, password: pw) }
                blessReport = r
                if r.set { log.info("startup disk: set for the next start (as \(owner))") }
                else { startupDiskError = r.note; log.error("startup disk: bless failed (as \(owner)): \(r.note)") }
            } catch {
                startupDiskError = describe(error)
                let ns = error as NSError
                log.error("startup disk: \(describe(error)) [\(ns.domain) \(ns.code)]")
            }
            settingStartupDisk = false
        }
    }

    /// The finish screen's "Shut Down": the helper shuts the Mac down (the startup disk is set; SiliconForest is started from startup options).
    public func shutDown() {
        guard let j = job, !shuttingDown else { return }
        shuttingDown = true; shutDownError = nil
        Task {
            do { let c = controller; try await background { try c.shutDown(j) } }
            catch { shuttingDown = false; shutDownError = describe(error); log.error("shut down failed: \(shutDownError ?? "")") }
        }
    }

    /// Resume after a quit, crash or restart. If the helper restarted or the 2 hours ran out, the person
    /// confirms again (the same typed words and an administrator) before anything continues.
    public func resume(_ j: String) {
        job = j
        Task {
            do {
                guard await privilegesStillReady(.resume(j)) else { return }
                log.info("resume: job \(j)")
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
        let typed = TypedConfirmation(diskName: typedName)
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

    /// The person-facing text of an error, with the helper's detail when it gave one.
    func describe(_ error: Error) -> String {
        let ns = error as NSError
        let m = (error as? LocalizedError)?.errorDescription ?? ns.localizedDescription
        if ns.domain == HelperError.domain, let r = ns.localizedFailureReason, !r.isEmpty, !m.contains(r) { return "\(m) (\(r))" }
        return m
    }

    private func routeToPrivileges(_ error: Error, next: PrivilegeNext) {
        let path = (error as NSError).localizedFailureReason ?? "/dev/rdisk0"
        log.error("full disk access denied (\(path)): \(describe(error))")
        gate.noteDenied(path: path)
        privilegeNext = next
        activity = .idle
        session?.go(.livePrivileges)
        absorbPrivileges(gate.stage)
    }

    private func fail(_ error: Error) {
        if job == nil, isFullDiskAccessDenial(error) { routeToPrivileges(error, next: .install(bytes: lastBytes, name: lastName)); return }
        let m = describe(error)
        if case .failed = activity {} else { failedDuring = activity }
        log.error("failed\(job.map { " (job \($0))" } ?? ""): \(m) [\(String(describing: type(of: error)))]")
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
                    self.log.info("job \(j) ended: \(p.end ?? "?")\(p.lastError.map { " (\($0))" } ?? "")")
                    if p.end == "handed-off" { self.activity = .done; self.session?.go(.liveFinish) }
                    else if self.isRemoval, p.end == "committed" { self.activity = .done; self.session?.go(.liveRemoved) }
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
        if let op = p.operation { isRemoval = op == "remove" }
        blessReport = p.bless
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
            if e.kind == "step" || e.kind == "rollback" { log.info("job \(job ?? "?") \(e.step) \(e.kind): \(e.text)") }
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
