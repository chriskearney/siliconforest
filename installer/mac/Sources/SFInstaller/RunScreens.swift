import SwiftUI
import SFInstallKit
import SFCopy
import SFDesign
import SFFlow

// MARK: 8. Preparing

struct PreparingScreen: View {
    @ObservedObject var s: Session
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHead(title: Copy.Preparing.title, lead: Copy.Preparing.lead)
            if let plan = s.plan {
                let fetch = plan.steps.firstIndex { $0.id == .fetch }
                let verify = plan.steps.firstIndex { $0.id == .verifyDownloads }
                let f = fetch.map { s.stepFraction[$0] } ?? 0
                let relShare = Double(plan.downloadReleaseBytes) / Double(max(1, plan.downloadReleaseBytes + plan.downloadAppleBytes))
                let relDone = min(1, f / relShare)
                let appleDone = max(0, (f - relShare) / (1 - relShare))
                VStack(spacing: 0) {
                    PhaseRow(Copy.Preparing.release(plan.releaseVersion), state: relDone >= 1 ? .pass : (f > 0 ? .working : .waiting),
                             trailing: relDone >= 1 ? "\(Bytes.format(plan.downloadReleaseBytes))   \(Copy.Preparing.verified)" : Copy.Preparing.progress(Int64(Double(plan.downloadReleaseBytes) * relDone), plan.downloadReleaseBytes))
                    PhaseRow(Copy.Preparing.apple, state: appleDone >= 1 ? .pass : (relDone >= 1 ? .working : .waiting),
                             trailing: relDone >= 1 ? Copy.Preparing.progress(Int64(Double(plan.downloadAppleBytes) * appleDone), plan.downloadAppleBytes) + (appleDone < 1 ? "   \(s.remainingText)" : "") : nil)
                    PhaseRow(Copy.Preparing.checking, state: verify.map { s.stepStates[$0] } ?? .waiting)
                }
                .frame(maxWidth: 680)
                ProgressLine(value: min(1, f * 0.9 + (verify.map { s.stepFraction[$0] } ?? 0) * 0.1)).frame(maxWidth: 680).padding(.top, 22)
            }
        }
    }
}

// MARK: 9. Installing / U3. Removing

struct RunScreen: View {
    @ObservedObject var s: Session
    @Environment(\.theme) private var theme
    var body: some View {
        let removing = s.plan?.kind == .uninstall
        VStack(alignment: .leading, spacing: 0) {
            ScreenHead(title: removing ? Copy.Remove.removingTitle : Copy.Installing.title, lead: removing ? Copy.Remove.removingLead : Copy.Installing.lead)
            if let plan = s.plan {
                let phases = plan.phases.filter { !$0.isPreparing }
                VStack(spacing: 0) {
                    ForEach(phases, id: \.self) { ph in
                        let st = s.phaseState(ph)
                        PhaseRow(Copy.Installing.phase(ph), state: st, trailing: trailing(ph, st))
                    }
                }
                .frame(maxWidth: 680)
                HStack {
                    ProgressLine(value: removing ? s.overallProgress : s.installProgress)
                    Spacer(minLength: 24)
                    Text(s.remainingText).font(SFType.label).foregroundStyle(theme.textSecondary)
                }
                .frame(maxWidth: 680).padding(.top, 22)
                if let i = s.currentStep, plan.steps.indices.contains(i), plan.steps[i].id == .resize {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "hourglass").font(.system(size: 12)).foregroundStyle(theme.textSecondary)
                        Text(Copy.Installing.stall).font(SFType.label).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: 620, alignment: .leading).padding(.top, 16)
                }
            }
        }
    }

    private func trailing(_ ph: Phase, _ st: RowState) -> String? {
        switch st {
        case .pass: return Copy.Installing.doneIn(s.phaseDuration(ph))
        case .working:
            if !s.stepDetail.isEmpty, s.stepDetail.contains(" of ") { return s.stepDetail.components(separatedBy: " · ").first }
            return "\(Int(s.phaseFraction(ph) * 100))%"
        default: return nil
        }
    }
}

// MARK: 10. Get ready for Recovery

struct RecoveryScreen: View {
    @ObservedObject var s: Session
    @Environment(\.theme) private var theme
    @State private var practicing = false
    var body: some View {
        let name = s.plan?.options.installName ?? s.installName
        VStack(alignment: .leading, spacing: 0) {
            ScreenHead(title: Copy.Recovery.title, lead: Copy.Recovery.lead)
            HStack(alignment: .top, spacing: 36) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(Copy.Recovery.steps(holdCopy: s.profile?.powerButtonCopy, name: name).enumerated()), id: \.offset) { i, t in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text("\(i + 1)").font(SFType.number(14)).foregroundStyle(i == 2 ? theme.onAccent : theme.text)
                                .frame(width: 26, height: 26).background(Circle().fill(i == 2 ? theme.accent : theme.surfaceRaised.opacity(0.8)))
                                .overlay(Circle().strokeBorder(theme.hairline, lineWidth: i == 2 ? 0 : 1))
                            Text(t).font(i == 2 ? SFType.bodyStrong : SFType.body).foregroundStyle(theme.text).lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(theme.textSecondary)
                        Text(Copy.Recovery.note).font(SFType.label).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: 470)
                Spacer(minLength: 0)
                VStack(spacing: 14) {
                    TouchIDKeyIllustration(holding: 0.62)
                    Button { practicing.toggle() } label: { Label(Copy.Recovery.practice, systemImage: "hand.tap") }
                        .buttonStyle(SFQuietButtonStyle())
                    Text(Copy.Recovery.practiceHint).font(SFType.caption).foregroundStyle(theme.textTertiary)
                }
                .frame(width: 300)
            }
        }
    }
}

/// Our drawing of the top-right of the keyboard: the Touch ID key held, with a timer ring.
struct TouchIDKeyIllustration: View {
    var holding: Double
    @Environment(\.theme) private var theme
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LinearGradient(colors: [Color(hex: 0x2A322E), Color(hex: 0x161C19)], startPoint: .top, endPoint: .bottom))
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in key(width: 46) }
                    ZStack {
                        key(width: 58, lit: true)
                        Circle().stroke(Color.white.opacity(0.12), lineWidth: 3).frame(width: 74, height: 74)
                        Circle().trim(from: 0, to: holding).stroke(theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90)).frame(width: 74, height: 74)
                            .shadow(color: theme.accent.opacity(0.7), radius: 6)
                    }
                }
                HStack(spacing: 8) { ForEach(0..<4, id: \.self) { _ in key(width: 46) }; key(width: 58) }
            }
            Text(Copy.Recovery.loadingStartupOptions).font(SFType.caption).foregroundStyle(Color.white.opacity(0.6))
                .offset(y: 82)
        }
        .frame(height: 196)
        .accessibilityLabel("Press and hold the Touch ID button")
    }
    private func key(width: CGFloat, lit: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(lit ? Color(hex: 0x3A443F) : Color(hex: 0x252D29))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(lit ? theme.accent.opacity(0.8) : Color.white.opacity(0.06), lineWidth: lit ? 1.5 : 1))
            .overlay(lit ? Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1).frame(width: 20, height: 20) : nil)
            .frame(width: width, height: 40)
    }
}

// MARK: Part 2. In recoveryOS (simulated)

struct InRecoveryScreen: View {
    @ObservedObject var s: Session
    var stage: RecoveryStage
    @Environment(\.theme) private var theme
    @State private var password = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "testtube.2").font(.system(size: 11)).foregroundStyle(theme.caution)
                Text(Copy.InRecovery.simulatedBanner).font(SFType.caption).foregroundStyle(theme.caution)
            }
            .padding(.top, 20)
            switch stage {
            case .password:
                ScreenHead(title: Copy.InRecovery.title, lead: Copy.InRecovery.lead(s.facts?.userFullName ?? "you"))
                Text(Copy.InRecovery.lowers).font(SFType.bodyStrong).foregroundStyle(theme.text).padding(.bottom, 22)
                SFTextField(Copy.InRecovery.password, text: .constant("••••••••••"), showsCaret: true, width: 360)
            case .working:
                ScreenHead(title: Copy.InRecovery.workingTitle, lead: nil)
                VStack(spacing: 0) {
                    ForEach(Array(Copy.InRecovery.working.enumerated()), id: \.offset) { i, t in
                        PhaseRow(t, state: i < s.recoveryWorking ? .pass : (i == s.recoveryWorking ? .working : .waiting))
                    }
                }
                .frame(maxWidth: 560)
            case .ready:
                ScreenHead(title: Copy.InRecovery.readyTitle, lead: Copy.InRecovery.readyBody(s.facts?.startupSystem ?? "macOS"))
                Text(Copy.InRecovery.countdown(s.recoveryCountdown)).font(SFType.number(15, .medium)).foregroundStyle(theme.textSecondary)
            }
        }
    }
}

// MARK: Part 3. Back in macOS

struct FinishScreen: View {
    @ObservedObject var s: Session
    var outcome: FinishOutcome
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch outcome {
            case .verifying:
                Spacer()
                HStack(spacing: 12) { Spinner(size: 18, color: theme.accent); Text(Copy.Finish.verifying).font(SFType.lead).foregroundStyle(theme.textSecondary) }
                Spacer()
            case .installed:
                // The hero screens (Welcome, Finish) are centred in the column; the working screens
                // keep the left-aligned measure.
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LitMark().frame(height: 112).padding(.bottom, 30)
                    Text(Copy.Finish.title).font(SFType.title).tracking(SFType.titleTracking).foregroundStyle(theme.text).accessibilityAddTraits(.isHeader)
                    Text(Copy.Finish.lead).font(SFType.lead).foregroundStyle(theme.textSecondary).padding(.top, 12)
                    (Text(Copy.Finish.switchLabel + " ").font(SFType.bodyStrong).foregroundColor(theme.text) + Text(Copy.Finish.switchBody).font(SFType.body).foregroundColor(theme.textSecondary))
                        .padding(.top, 22)
                    Text(Copy.Finish.removeAnyTime).font(SFType.label).foregroundStyle(theme.textSecondary).padding(.top, 26)
                    if s.isDryRun { Text(Copy.Common.dryRunComplete).font(SFType.label).foregroundStyle(theme.caution).padding(.top, 6) }
                    Spacer(minLength: 0); Spacer(minLength: 0)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            case .partial:
                ScreenHead(title: Copy.Finish.partialTitle, lead: Copy.Finish.partialLead("starting system services"))
            case .didNotStart:
                ScreenHead(title: Copy.Finish.failedTitle, lead: Copy.Finish.failedLead(s.facts?.startupSystem ?? "macOS"))
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The one celebration: vias light outward along the mark's traces, once.
struct LitMark: View {
    @Environment(\.theme) private var theme
    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle().strokeBorder(theme.accent.opacity(0.32 - Double(i) * 0.09), lineWidth: 1)
                    .frame(width: 150 + CGFloat(i) * 52, height: 150 + CGFloat(i) * 52)
            }
            BrandMark.themed(theme).frame(height: 112)
        }
        .frame(width: 112, height: 112)
    }
}

// MARK: Part 4. Remove

struct RemoveWhatScreen: View {
    @ObservedObject var s: Session
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHead(title: Copy.Remove.title, lead: Copy.Remove.lead)
            if let disk = s.disk, let install = s.selectedInstall ?? s.ownedInstall {
                VStack(alignment: .leading, spacing: 10) {
                    barRow(Copy.Review.now, DiskBarModel.current(disk))
                    barRow(Copy.Review.after, DiskBarModel.afterRemoving(disk, install))
                }
                HStack(alignment: .top, spacing: 48) {
                    list(Copy.Remove.removedHeader, Copy.Remove.removed(install.totalBytes), symbol: "trash", color: theme.critical)
                    list(Copy.Remove.keptHeader, Copy.Remove.kept, symbol: "lock", color: theme.ok)
                }
                .padding(.top, 26)
                let grow = (disk.macOSPartition?.size ?? 0) + install.reclaimableBytes(on: disk)
                Text(Copy.Remove.growsBack(grow)).font(SFType.bodyStrong).foregroundStyle(theme.text).padding(.top, 24)
            }
        }
    }
    private func barRow(_ label: String, _ segs: [BarSegment]) -> some View {
        HStack(spacing: 16) {
            Text(label).font(SFType.label).foregroundStyle(theme.textSecondary).frame(width: 44, alignment: .leading)
            DiskBar(segments: segs, height: 30)
        }
    }
    private func list(_ head: String, _ items: [String], symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(head)
            ForEach(Array(items.enumerated()), id: \.offset) { i, t in
                HStack(spacing: 12) {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(color).frame(width: 18)
                    Text(t).font(i == 1 && head == Copy.Remove.removedHeader ? SFType.bodyStrong : SFType.body).foregroundStyle(theme.text)
                }
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
    }
}

struct RemoveConfirmScreen: View {
    @ObservedObject var s: Session
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHead(title: Copy.Remove.title, lead: Copy.Remove.lead)
            (Text(Copy.Remove.typePrefix).foregroundColor(theme.text) + Text(Copy.Remove.confirmWord).foregroundColor(theme.critical).fontWeight(.semibold) + Text(Copy.Remove.typeSuffix).foregroundColor(theme.text))
                .font(SFType.inter(22, .medium))
                .padding(.bottom, 14)
            SFTextField(Copy.Remove.confirmWord, text: $s.removeConfirmText, showsCaret: true, width: 380)
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 12, weight: .semibold))
                Text(Copy.Remove.willBeDeleted).font(SFType.label)
            }
            .foregroundStyle(theme.critical).padding(.top, 16)
        }
    }
}

struct RemovedScreen: View {
    @ObservedObject var s: Session
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHead(title: Copy.Remove.removedTitle, lead: Copy.Remove.removedLead(s.plan?.macOSSizeAfter ?? 0))
            if let disk = s.disk {
                HStack(spacing: 16) {
                    Text(Copy.Review.now).font(SFType.label).foregroundStyle(theme.textSecondary).frame(width: 44, alignment: .leading)
                    DiskBar(segments: DiskBarModel.current(disk), height: 30)
                }
            }
            if s.isDryRun { Text(Copy.Common.dryRunComplete).font(SFType.label).foregroundStyle(theme.caution).padding(.top, 22) }
        }
    }
}

// MARK: Part 5. Failure and rollback

struct FailureScreen: View {
    @ObservedObject var s: Session
    @Environment(\.theme) private var theme
    var body: some View {
        let kind = s.failureKind ?? .nothingChanged
        VStack(alignment: .leading, spacing: 0) {
            ScreenHead(title: title(kind), lead: lead(kind))
            if kind == .undoing || kind == .undone || kind == .needsAttention {
                VStack(spacing: 0) {
                    ForEach(Array(Copy.Failure.undoing.enumerated()), id: \.offset) { i, t in
                        PhaseRow(t, state: kind == .undone ? .pass : s.undoProgress[i])
                    }
                }
                .frame(maxWidth: 560).padding(.bottom, 20)
            }
            if kind != .undone, let m = s.failureMessage {
                Panel(padding: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let i = s.failedStep, let p = s.plan, p.steps.indices.contains(i) {
                            Text("\(p.steps[i].code) · \(p.steps[i].title)").font(SFType.labelStrong).foregroundStyle(theme.textSecondary)
                        }
                        Text(m).font(SFType.log).foregroundStyle(theme.critical).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: 620)
            }
            if kind == .canUndo, let plan = s.plan {
                let done = plan.steps.indices.filter { s.stepStates[$0] == .pass && plan.steps[$0].operations.contains(where: \.isMutating) }
                if !done.isEmpty {
                    SectionLabel(Copy.Failure.changesSoFar).padding(.top, 24).padding(.bottom, 4)
                    VStack(spacing: 0) {
                        ForEach(done, id: \.self) { i in PhaseRow(plan.steps[i].title, state: .pass, trailing: plan.steps[i].code) }
                    }
                    .frame(maxWidth: 620)
                }
                if let disk = s.disk {
                    HStack(spacing: 16) {
                        Text(Copy.Review.now).font(SFType.label).foregroundStyle(theme.textSecondary).frame(width: 44, alignment: .leading)
                        DiskBar(segments: DiskBarModel.current(disk), height: 30)
                    }
                    .padding(.top, 18)
                }
            }
            if kind == .needsAttention {
                Text(Copy.Failure.attentionAction).font(SFType.bodyStrong).foregroundStyle(theme.text).padding(.top, 18)
            }
            if kind == .undone, let disk = s.disk {
                HStack(spacing: 16) {
                    Text(Copy.Review.now).font(SFType.label).foregroundStyle(theme.textSecondary).frame(width: 44, alignment: .leading)
                    DiskBar(segments: DiskBarModel.current(disk), height: 30)
                }
            }
        }
    }

    private func title(_ k: FailureKind) -> String {
        switch k {
        case .nothingChanged, .canUndo: return Copy.Failure.stoppedTitle
        case .undoing: return Copy.Failure.undoingTitle
        case .undone: return Copy.Failure.undoneTitle
        case .needsAttention: return Copy.Failure.attentionTitle
        case .removalStopped: return Copy.Failure.removalStoppedTitle
        case .notOurs: return Copy.Remove.notOursTitle
        }
    }
    private func lead(_ k: FailureKind) -> String {
        switch k {
        case .nothingChanged: return Copy.Failure.nothingChanged
        case .canUndo, .undoing: return Copy.Failure.canUndo
        case .undone: return Copy.Failure.undoneLead
        case .needsAttention: return Copy.Failure.attentionLead
        case .removalStopped: return Copy.Failure.removalStoppedLead
        case .notOurs: return Copy.Remove.notOursBody
        }
    }
}
