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
            Text("This installer writes to your Mac's internal disk. It is a preview that has not yet been run on a real Mac. Back up first (Time Machine or another copy you have checked).")
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
            ScreenHead(title: "Getting SiliconForest ready", lead: "The installer downloads the signed release, checks its signature and every file, and asks its helper to plan the change on this Mac. Nothing on your disk changes yet.")
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    PhaseRow("Turn on the installer's helper", state: state(for: 0))
                    PhaseRow("Download and verify the release", state: state(for: 1), trailing: downloadText)
                    PhaseRow("Hand it to the helper (verified again there)", state: state(for: 2))
                    PhaseRow("Read this Mac's disk and make the plan", state: state(for: 3))
                }
            }
            if case .waitingForHelperApproval = live.activity {
                Text("Turn on “SiliconForest Installer” in System Settings → General → Login Items. The installer continues by itself.")
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
    private var downloadText: String? {
        if case .downloading(_, let d, let t) = live.activity, t > 0 { return "\(d)/\(t) files" }
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
                ScreenHead(title: "Confirm the change", lead: "This is the plan the installer's helper made from its own read of the disk. It will do exactly this, and nothing else.")
                LiveWarning()
                if let o = live.offer {
                    Panel {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Target: \(o.target)\(o.diskUUID.map { " (GPT \($0.prefix(8))…)" } ?? "")").font(SFType.bodyStrong).foregroundStyle(theme.text)
                            Text("macOS (“\(o.expected.diskName)”) gives up \(o.gigabytes) GB: \(gb(o.plan.macOS.from)) → \(gb(o.plan.macOS.to)). Your files stay where they are.")
                                .font(SFType.body).foregroundStyle(theme.text)
                            ForEach(o.plan.partitions, id: \.role) { p in
                                Text("New \(p.role) partition: \(gb(p.bytes)), \(p.content) “\(p.label)”").font(SFType.label).foregroundStyle(theme.textSecondary)
                            }
                            Text("Release \(o.releaseVersion), signature verified; stage 1 \(live.release?.stage1SHA256.prefix(8) ?? "")… (pinned v2). Plan \(o.plan.digest.prefix(12))….")
                                .font(SFType.caption).foregroundStyle(theme.textTertiary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("To approve, type the name of the macOS volume: \(o.expected.diskName)").font(SFType.body).foregroundStyle(theme.text)
                        SFTextField(o.expected.diskName, text: $live.typedName, width: 420)
                        Text("and type: \(o.expected.phrase)").font(SFType.body).foregroundStyle(theme.text)
                        SFTextField(o.expected.phrase, text: $live.typedPhrase, width: 420)
                        Text("Then an administrator approves in the macOS dialog. The helper writes a short-lived authorization (2 hours) for exactly this plan and this disk.")
                            .font(SFType.label).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if case .failed(let m) = live.activity { LiveErrorBox(message: m, note: "Nothing was written: the disk changes only after you click Install.", live: live) }
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
            ScreenHead(title: live.isRemoval ? "Removing SiliconForest" : "Installing SiliconForest", lead: "Keep your Mac on power. You can quit the installer: its helper keeps going, and the installer reattaches when you open it again.")
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
            if live.currentCode == "S25" {
                Text("diskutil: \(live.diskutilPercent.map { "\($0)% · " } ?? "")\(live.diskutilLine). macOS is still working on this; it can take a long time and may look stuck. Don't shut down.")
                    .font(SFType.label).foregroundStyle(theme.caution).fixedSize(horizontal: false, vertical: true)
            }
            if !live.detail.isEmpty { Text(live.detail).font(SFType.caption).foregroundStyle(theme.textSecondary).lineLimit(1) }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(live.rows) { r in
                        PhaseRow("\(r.code)  \(r.title)", state: r.state, trailing: r.seconds.map { duration($0) } ?? (r.state == .working ? "…" : nil), emphasized: r.state == .working)
                    }
                }
            }
            .frame(maxHeight: 300)
            LiveJournal(lines: live.journal)
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
                    ScreenHead(title: "Your Mac is back as it was", lead: "The installer undid every change it had made. macOS has its space back.")
                } else {
                    ScreenHead(title: "The installer stopped", lead: live.noChangesMade
                               ? "Nothing on your disk was changed."
                               : "Your Mac is safe to use. The journal knows exactly what was done: continue from where it stopped, or undo everything.")
                    if let e = live.lastError { LiveErrorBox(message: e, note: nil, live: live) }
                    if let x = live.resumeExpected {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("To continue, confirm again: type \(x.diskName) and \(x.phrase).").font(SFType.body).foregroundStyle(theme.text)
                            SFTextField(x.diskName, text: $live.typedName, width: 420)
                            SFTextField(x.phrase, text: $live.typedPhrase, width: 420)
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
            ScreenHead(title: "Continue installing SiliconForest?", lead: "An installation didn't finish (the installer quit, crashed or the Mac restarted). Its journal records every step, so it can carry on from exactly where it stopped, or undo everything.")
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
                    ScreenHead(title: "SiliconForest is installed", lead: "Your Mac is set to start SiliconForest once, the next time it starts. Save your work in other apps, then restart. SiliconForest Setup finishes in recoveryOS (it asks for your Mac password), then restarts into SiliconForest.")
                    Panel {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Restart into SiliconForest").font(SFType.bodyStrong).foregroundStyle(theme.text)
                            Text(b?.confirmed == true ? "The installer confirmed the selection with bless." : "The selection is a one-time next boot; macOS doesn't always report it, so this couldn't be read back.")
                                .font(SFType.label).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let e = live.restartError {
                        Label("The installer couldn't restart your Mac: \(e)", systemImage: "exclamationmark.triangle.fill").font(SFType.body).foregroundStyle(theme.caution).fixedSize(horizontal: false, vertical: true)
                    }
                    if live.restarting { Text("Restarting…").font(SFType.body).foregroundStyle(theme.text) }
                    Text(AfterHandoff.fallback).font(SFType.label).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    ScreenHead(title: "One last step", lead: "SiliconForest is on your disk and checked, but the installer couldn't set your Mac to start it\(b.map { $0.note.isEmpty ? "" : " (\($0.note))" } ?? ""). Do this yourself:")
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
                ScreenHead(title: "Confirm the removal", lead: "The installer's helper made this plan from its own read of the disk and the install's journal. It deletes only the partitions that install created, and nothing else.")
                LiveWarning()
                if let o = live.offer {
                    Panel {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Target: \(o.target)\(o.diskUUID.map { " (GPT \($0.prefix(8))…)" } ?? "")").font(SFType.bodyStrong).foregroundStyle(theme.text)
                            Text("Deletes SiliconForest's stub, boot partition and root partition. macOS (“\(o.expected.diskName)”) grows back: \(gb(o.plan.macOS.from)) → \(gb(o.plan.macOS.to)). Your macOS files stay where they are.")
                                .font(SFType.body).foregroundStyle(theme.text).fixedSize(horizontal: false, vertical: true)
                            Text("If the startup disk points at SiliconForest it is set back to macOS first. Plan \(o.plan.digest.prefix(12))….").font(SFType.caption).foregroundStyle(theme.textTertiary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("To approve, type the name of the macOS volume: \(o.expected.diskName)").font(SFType.body).foregroundStyle(theme.text)
                        SFTextField(o.expected.diskName, text: $live.typedName, width: 420)
                        Text("and type: \(o.expected.phrase)").font(SFType.body).foregroundStyle(theme.text)
                        SFTextField(o.expected.phrase, text: $live.typedPhrase, width: 420)
                        Text("Then an administrator approves in the macOS dialog.").font(SFType.label).foregroundStyle(theme.textSecondary)
                    }
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
