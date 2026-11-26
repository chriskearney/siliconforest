// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// The real install's screens (preview6): getting the release, confirming the helper's plan, installing
// (live steps, elapsed time, diskutil, bytes, journal), stopped/resume, and the finish with the bless
// instructions. They show LiveRun; every action goes through it to the helper.

import SwiftUI
import SFInstallKit
import SFCopy
import SFDesign
import SFFlow
import SFHelperKit
import SFAppEngine

private func gb(_ b: Int64) -> String { String(format: "%.1f GB", Double(b) / 1e9) }
private func duration(_ t: TimeInterval) -> String {
    let s = Int(t); return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}

/// A scroll view that, offscreen (snapshots), is just its content: AppKit-backed scrolling doesn't render there.
struct SnapScroll<Content: View>: View {
    @Environment(\.isSnapshot) private var isSnapshot
    @ViewBuilder var content: Content
    var body: some View {
        if isSnapshot { content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) } else { ScrollView { content } }
    }
}

struct LiveWarning: View {
    @Environment(\.theme) private var theme
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.caution)
            Text("This preview writes to your Mac's internal disk and hasn't been tested on a real Mac yet. Back up first (Time Machine or another copy you have checked).")
                .font(SFType.label).foregroundStyle(theme.text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct LiveFetchScreen: View {
    @ObservedObject var s: Session
    @ObservedObject var live: LiveRun
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScreenHead(title: "Preparing the installation", lead: "The installer downloads and verifies the signed release, then its helper plans the changes for this Mac. Your disk isn't changed yet.")
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    PhaseRow("Turn on the installer's helper", state: state(for: 0))
                    PhaseRow("Download and verify the release", state: state(for: 1), trailing: downloadText)
                    if let f = downloadFraction {
                        ProgressLine(value: f).padding(.leading, 36)
                            .accessibilityLabel("Download progress")
                    }
                    PhaseRow("Hand it to the helper (verified again there)", state: state(for: 2))
                    PhaseRow("Read this Mac's disk and make the plan", state: state(for: 3))
                }
            }
            if case .waitingForHelperApproval = live.activity {
                Text(Copy.Privileges.approvalLine)
                    .font(SFType.body).foregroundStyle(theme.caution)
            }
            if case .failed(let m) = live.activity { LiveErrorBox(message: m, live: live) }
        }
    }
    private var stage: Int {
        if case .failed = live.activity, let d = live.failedDuring { return Self.stage(of: d, hasOffer: live.offer != nil) }
        return Self.stage(of: live.activity, hasOffer: live.offer != nil)
    }
    private static func stage(of a: LiveRun.Activity, hasOffer: Bool) -> Int {
        switch a {
        case .registering, .waitingForHelperApproval: return 0
        case .downloading: return 1
        case .importing: return 2
        case .planning: return 3
        default: return hasOffer ? 4 : 0
        }
    }
    private func state(for i: Int) -> RowState {
        if case .failed = live.activity { return i == stage ? .fail : (i < stage ? .pass : .waiting) }
        return i < stage ? .pass : (i == stage ? .working : .waiting)
    }
    /// Indeterminate (name and bytes only) until the file total is known; then "N of M files" and a bar.
    private var downloadText: String? {
        if case .downloading(let p) = live.activity { return Copy.Download.label(done: p.filesDone, total: p.filesTotal, bytes: p.bytes) }
        return nil
    }
    private var downloadFraction: Double? {
        if case .downloading(let p) = live.activity { return p.fraction }
        return nil
    }
}

struct LiveConfirmScreen: View {
    @ObservedObject var s: Session
    @ObservedObject var live: LiveRun
    @Environment(\.theme) private var theme
    var body: some View {
        SnapScroll {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHead(title: "Confirm the change", lead: "The helper made this plan from its own read of the disk. It does only what is listed here.")
                LiveWarning()
                if let o = live.offer {
                    ReviewSummary(offer: o, release: live.release, removal: false)
                    ConfirmField(live: live, prompt: Copy.Confirm.typeName(o.expected.diskName), volume: o.expected.diskName,
                                 note: Copy.Confirm.thenAdmin + " " + Copy.Confirm.installAfter)
                    StartupDiskLogin(live: live, volume: o.expected.diskName, optional: true)
                }
                if case .failed(let m) = live.activity { LiveErrorBox(message: m, note: "Nothing was written: the disk changes only after you click Install.", live: live) }
            }
        }
    }
}

/// Preview13: "What will change", one short block per partition, then the warning and a quiet footnote.
struct ReviewSummary: View {
    var offer: InstallOffer
    var release: ReleaseSummary?
    var removal: Bool
    @Environment(\.theme) private var theme
    var blocks: [Copy.Confirm.Block] {
        let p = offer.plan
        if removal {
            let roles = ["stub": p.owned?.stub, "boot": p.owned?.boot, "root": p.owned?.root].compactMap { $0.value == nil ? nil : $0.key }
            return Copy.Confirm.removeBlocks(volume: offer.expected.diskName, macOSFrom: p.macOS.from, macOSTo: p.macOS.to, roles: roles)
        }
        return Copy.Confirm.installBlocks(volume: offer.expected.diskName, macOSFrom: p.macOS.from, macOSTo: p.macOS.to,
                                         partitions: p.partitions.map { Copy.Confirm.Part(role: $0.role, bytes: $0.bytes) })
    }
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text(removal ? Copy.Confirm.removeHeader : Copy.Confirm.installHeader).font(SFType.bodyStrong).foregroundStyle(theme.text)
                ForEach(blocks) { b in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.name).font(SFType.bodyStrong).foregroundStyle(theme.text)
                        Text(b.change + (b.detail.map { " " + $0 } ?? "")).font(SFType.body).foregroundStyle(theme.text)
                    }
                    .accessibilityElement(children: .combine)
                }
                if removal { Text(Copy.Confirm.removeIfStartup).font(SFType.label).foregroundStyle(theme.textSecondary) }
                Label(Copy.Confirm.warning, systemImage: "exclamationmark.triangle.fill").font(SFType.bodyStrong).foregroundStyle(theme.caution)
                Text(Copy.Confirm.footnote(target: offer.target + (offer.diskUUID.map { " (GPT \($0.prefix(8))…)" } ?? ""), version: offer.releaseVersion,
                                          stage1: release.map { "\($0.stage1SHA256.prefix(8))…" }, plan: "\(offer.plan.digest.prefix(12))…", removal: removal))
                    .font(SFType.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One typed confirmation: the macOS volume's name (case and spacing forgiven), with a green check when it matches.
struct ConfirmField: View {
    @ObservedObject var live: LiveRun
    var prompt: String
    var volume: String
    var note: String?
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(prompt).font(SFType.body).foregroundStyle(theme.text)
            HStack(spacing: 10) {
                SFTextField(volume, text: $live.typedName, width: 420)
                if live.typedMatches {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.ok).font(.system(size: 20))
                        .accessibilityLabel("The name matches")
                }
            }
            if let note { Text(note).font(SFType.label).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// Preview13: the volume owner's login for `bless`. Plain words; never "root". The password is only typed here and
/// sent to the helper, which keeps it in memory for one use.
struct StartupDiskLogin: View {
    @ObservedObject var live: LiveRun
    var volume: String
    var optional: Bool
    var removal = false
    @Environment(\.theme) private var theme
    var body: some View {
        let owners = live.startupOwners?.owners ?? []
        VStack(alignment: .leading, spacing: 8) {
            Text(removal ? Copy.Startup.removeHeader : Copy.Startup.header).font(SFType.bodyStrong).foregroundStyle(theme.text)
            if owners.isEmpty && live.startupOwners != nil {
                Text(Copy.Startup.noAccounts).font(SFType.label).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(removal ? Copy.Startup.removeBody(volume: volume) : optional ? Copy.Startup.body(volume: volume) : Copy.Startup.finishNote).font(SFType.body).foregroundStyle(theme.text).fixedSize(horizontal: false, vertical: true)
                if owners.count > 1 {
                    Picker(Copy.Startup.account, selection: $live.startupOwner) { ForEach(owners, id: \.self) { Text($0).tag($0) } }
                        .pickerStyle(.menu).frame(width: 420, alignment: .leading)
                }
                SecureField(Copy.Startup.field(owner: live.startupOwner), text: $live.startupPassword)
                    .textFieldStyle(.roundedBorder).frame(width: 420)
                    .disabled(live.settingStartupDisk || owners.isEmpty)
                if optional { Text(Copy.Startup.optionalNote).font(SFType.label).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }
}

struct LiveInstallingScreen: View {
    @ObservedObject var s: Session
    @ObservedObject var live: LiveRun
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenHead(title: live.isRemoval ? "Removing SiliconForest" : "Installing SiliconForest", lead: "Keep your Mac connected to power. If you quit the installer, its helper keeps going; open the installer again to see progress.")
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel("Elapsed"); Text(duration(live.elapsed)).font(SFType.numerals).foregroundStyle(theme.text)
                }
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel("Overall"); Text("\(Int(live.overall * 100))%").font(SFType.numerals).foregroundStyle(theme.text)
                }
                Spacer()
            }
            ProgressLine(value: live.overall)
            if live.currentCode == "S47", live.bytesTotal > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(live.bytesPhase == "read-back" ? "Reading back" : "Writing") the root image: \(gb(live.bytesDone)) of \(gb(live.bytesTotal)) (\(Int(Double(live.bytesDone) / Double(live.bytesTotal) * 100))%)")
                        .font(SFType.label).foregroundStyle(theme.text)
                    ProgressLine(value: Double(live.bytesDone) / Double(live.bytesTotal), height: 3)
                }
            }
            // The diskutil line and the "still working" notice share one reserved block under the bars, so
            // nothing above or below moves when the shrink step starts or ends. The notice is only for that step.
            ResizeNotice(visible: live.currentCode == "S25",
                         line: "diskutil: \(live.diskutilPercent.map { "\($0)% · " } ?? "")\(live.diskutilLine)")
            if !live.detail.isEmpty { Text(live.detail).font(SFType.caption).foregroundStyle(theme.textSecondary).lineLimit(1) }
            StepList(rows: live.rows)
            LiveJournal(lines: live.journal)
        }
    }
}

/// "macOS is still working on this…": quiet, under the progress, in a fixed-height block (faded, not removed).
struct ResizeNotice: View {
    var visible: Bool
    var line: String
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(line).font(SFType.caption).foregroundStyle(theme.textSecondary).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(theme.textSecondary)
                Text(Copy.Installing.stall).font(SFType.caption).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: 40, alignment: .topLeading)
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: visible)
        .accessibilityHidden(!visible)
    }
}

/// The steps, all visible in a scrolling list that follows the one in progress (see `ScrollFollow`).
struct StepList: View {
    var rows: [LiveRun.StepRow]
    @State private var follow = ScrollFollow()
    private var activeIndex: Int? { rows.lastIndex { $0.state == .working } }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Lazy, so a row's appear/disappear means visible/not visible. Ids are the row positions:
                // two steps can share a state code (S47 writes, then checks).
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                        PhaseRow("\(r.code)  \(r.title)", state: r.state, trailing: r.seconds.map { duration($0) } ?? (r.state == .working ? "…" : nil), emphasized: r.state == .working)
                            .id(i)
                            .onAppear { follow.rowAppeared(i) }
                            .onDisappear { follow.rowDisappeared(i) }
                    }
                }
            }
            .frame(maxHeight: 300)
            .onChange(of: activeIndex) { new in
                guard follow.activeChanged(to: new), let new else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(new, anchor: .center) }
            }
            .onAppear { if let a = activeIndex, follow.activeChanged(to: a) { proxy.scrollTo(a, anchor: .center) } }
        }
    }
}

struct LiveJournal: View {
    var lines: [String]
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel("Journal")
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(lines.suffix(200).enumerated()), id: \.offset) { i, l in
                            Text(l).font(SFType.log).foregroundStyle(theme.textSecondary).id(i).textSelection(.enabled)
                        }
                    }
                }
                .frame(height: 120)
                .onChange(of: lines.count) { _ in proxy.scrollTo(min(199, lines.count - 1), anchor: .bottom) }
            }
        }
    }
}

struct LiveStoppedScreen: View {
    @ObservedObject var s: Session
    @ObservedObject var live: LiveRun
    @Environment(\.theme) private var theme
    var body: some View {
        SnapScroll {
            VStack(alignment: .leading, spacing: 14) {
                if live.end == "rolled-back" {
                    ScreenHead(title: "Changes undone", lead: "The installer undid all of its changes. macOS has its space back.")
                } else {
                    ScreenHead(title: "The installer stopped", lead: live.noChangesMade
                               ? "Nothing on your disk was changed."
                               : "You can keep using your Mac. The journal records each completed step: continue from where it stopped, or undo everything.")
                    if let e = live.lastError { LiveErrorBox(message: e, note: nil, live: live) }
                    if let x = live.resumeExpected {
                        VStack(alignment: .leading, spacing: 8) {
                            ConfirmField(live: live, prompt: Copy.Confirm.typeNameAgain(x.diskName), volume: x.diskName, note: nil)
                        }
                    }
                    Text("Job \(live.job ?? "")").font(SFType.caption).foregroundStyle(theme.textTertiary).textSelection(.enabled)
                }
                LiveJournal(lines: live.journal)
            }
        }
    }
}

struct LiveResumeScreen: View {
    @ObservedObject var s: Session
    @ObservedObject var live: LiveRun
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenHead(title: "Continue installing SiliconForest?", lead: "An installation didn't finish (the installer quit, crashed or the Mac restarted). It can continue from the last completed step, or undo everything.")
            ForEach(live.unfinished, id: \.self) { j in Text("Job \(j)").font(SFType.label).foregroundStyle(theme.textSecondary).textSelection(.enabled) }
        }
    }
}

struct LiveFinishScreen: View {
    @ObservedObject var s: Session
    @ObservedObject var live: LiveRun
    @Environment(\.theme) private var theme
    var body: some View {
        let b = live.blessReport
        SnapScroll {
            VStack(alignment: .leading, spacing: 14) {
                if b?.set == true {
                    ScreenHead(title: Copy.StartupFinish.title, lead: Copy.StartupFinish.lead)
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Copy.StartupFinish.stepsHeader).font(SFType.bodyStrong).foregroundStyle(theme.text)
                            ForEach(Array(Copy.StartupFinish.steps(live.installName).enumerated()), id: \.offset) { i, t in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(i + 1)").font(SFType.bodyStrong).foregroundStyle(theme.accent).frame(width: 18)
                                    Text(t).font(SFType.body).foregroundStyle(theme.text).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Text(Copy.StartupFinish.expected).font(SFType.label).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                            Text(b?.confirmed == true ? Copy.StartupFinish.confirmed : Copy.StartupFinish.notConfirmed)
                                .font(SFType.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let e = live.shutDownError {
                        Label(Copy.StartupFinish.shutDownFailed(e), systemImage: "exclamationmark.triangle.fill").font(SFType.body).foregroundStyle(theme.caution).fixedSize(horizontal: false, vertical: true)
                    }
                    if live.shuttingDown { Text(Copy.StartupFinish.shuttingDown).font(SFType.body).foregroundStyle(theme.text) }
                } else {
                    ScreenHead(title: "One last step", lead: "SiliconForest is on your disk and checked, but your Mac isn't set to start it yet\(b.map { $0.note.isEmpty ? "" : " (\($0.note))" } ?? ""). Set it here, or do it yourself below.")
                    if b?.canRetry != false {
                        Panel {
                            VStack(alignment: .leading, spacing: 10) {
                                StartupDiskLogin(live: live, volume: "your Mac's startup disk", optional: false)
                                if live.settingStartupDisk { Text(Copy.Startup.setting).font(SFType.body).foregroundStyle(theme.text) }
                                if let e = live.startupDiskError {
                                    Label(Copy.Startup.failed(e), systemImage: "exclamationmark.triangle.fill").font(SFType.body).foregroundStyle(theme.caution).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .task { await live.loadStartupOwners() }
                    }
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(AfterHandoff.manualSteps(installName: live.installName, command: b?.manualCommand).enumerated()), id: \.offset) { i, t in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(i + 1)").font(SFType.bodyStrong).foregroundStyle(theme.accent).frame(width: 18)
                                    Text(t).font(SFType.body).foregroundStyle(theme.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    Button("Copy the bless command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(b?.manualCommand ?? AfterHandoff.blessCommand(installName: live.installName), forType: .string)
                    }.buttonStyle(SFTextButtonStyle())
                }
                Text("Job \(live.job ?? ""), \(duration(live.elapsed)).").font(SFType.caption).foregroundStyle(theme.textTertiary)
            }
        }
    }
}

struct LiveRemoveListScreen: View {
    @ObservedObject var s: Session
    @ObservedObject var live: LiveRun
    @Environment(\.theme) private var theme
    var body: some View {
        SnapScroll {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHead(title: "Remove SiliconForest", lead: "This removes everything an install created on this Mac's disk (the SiliconForest stub, its boot partition, the root partition and the recovery setup it added), gives the space back to macOS, and sets the startup disk back to macOS if it points at SiliconForest. Back up first.")
                LiveWarning()
                if live.isWorking { Text("Preparing…").font(SFType.body).foregroundStyle(theme.textSecondary) }
                if !live.installsLoaded { Text("Looking for installs…").font(SFType.body).foregroundStyle(theme.textSecondary) }
                else if live.installs.isEmpty {
                    Text("No SiliconForest install made by this installer was found on this Mac. The installer removes only partitions its own journal records as SiliconForest's.")
                        .font(SFType.body).foregroundStyle(theme.text).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(live.installs, id: \.job) { i in
                    Panel {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("“\(i.name)” · release \(i.releaseVersion) · install \(i.installID)").font(SFType.bodyStrong).foregroundStyle(theme.text)
                                Text(i.finished.map { "Finished \($0)" } ?? "").font(SFType.caption).foregroundStyle(theme.textTertiary)
                                if let n = i.note, !i.removable { Text("Can't remove it now: \(n)").font(SFType.label).foregroundStyle(theme.caution).fixedSize(horizontal: false, vertical: true) }
                            }
                            Spacer()
                            Button("Remove…") { live.chooseRemoval(i) }.buttonStyle(SFTextButtonStyle()).disabled(!i.removable || live.isWorking)
                        }
                    }
                }
                if let e = live.lastError { LiveErrorBox(message: e, live: live) }
            }
        }
    }
}

struct LiveRemoveConfirmScreen: View {
    @ObservedObject var s: Session
    @ObservedObject var live: LiveRun
    @Environment(\.theme) private var theme
    var body: some View {
        SnapScroll {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHead(title: "Confirm the removal", lead: "The helper made this plan from its own read of the disk and the install's journal. It deletes only the partitions that install created.")
                LiveWarning()
                if let o = live.offer {
                    ReviewSummary(offer: o, release: live.release, removal: true)
                    ConfirmField(live: live, prompt: Copy.Confirm.typeName(o.expected.diskName), volume: o.expected.diskName, note: Copy.Confirm.thenAdmin)
                    StartupDiskLogin(live: live, volume: o.expected.diskName, optional: true, removal: true)
                }
                if case .failed(let m) = live.activity { LiveErrorBox(message: m, note: "Nothing was removed.", live: live) }
            }
        }
    }
}

struct LiveRemovedScreen: View {
    @ObservedObject var s: Session
    @ObservedObject var live: LiveRun
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenHead(title: "SiliconForest has been removed", lead: "Its partitions are gone and macOS has its space back. The partition table was checked against the one saved before the install. Nothing else changed.")
            Text("Job \(live.job ?? ""), \(duration(live.elapsed)).").font(SFType.caption)
        }
    }
}
