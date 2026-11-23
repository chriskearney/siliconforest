import SwiftUI
import SFInstallKit
import SFCopy
import SFDesign
import SFFlow

/// One action in the bottom bar.
struct BarAction {
    enum Style { case primary, text, destructive }
    var title: String
    var style: Style = .text
    var enabled = true
    /// Return triggers it. Never set for destructive or irreversible actions (VISUAL §9).
    var isDefault = false
    var action: () -> Void
}

struct Footer {
    var leading: [BarAction] = []
    var trailing: [BarAction] = []
}

/// Where the content column sits. Centred, at most 880 pt wide, with at least 72 pt on each side.
enum RootLayout {
    static let maxColumn: CGFloat = 880
    static func column(width w: CGFloat) -> CGFloat { min(maxColumn, max(320, w - 144)) }
    static func leading(width w: CGFloat) -> CGFloat { (w - column(width: w)) / 2 }
}

/// The frame every screen shares (UX-FLOW "Layout of every screen"): top bar 72 pt, bottom bar 88 pt,
/// a fixed content column, the Grove behind. Bars never move between screens.
struct RootView: View {
    @ObservedObject var s: Session
    @Environment(\.theme) private var theme
    @Environment(\.screenSize) private var screen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let w = screen.width, h = screen.height
        // One centred content column with a maximum width, on every display: the 13-inch panel and a
        // 2560-point external screen get the same balanced composition, the Grove filling both sides.
        let column = RootLayout.column(width: w)
        let x = RootLayout.leading(width: w)
        // Panels always use the token set matching the appearance (VISUAL §9). In dark mode the
        // Finish screen is the same morning seen from the night side (GrovePalette's sunrise).
        let ui = theme
        ZStack(alignment: .topLeading) {
            Grove(camera: s.screen.camera, dawn: s.dawn)
                .animation(reduceMotion ? .easeInOut(duration: 0.15) : .easeInOut(duration: 1.6), value: s.screen)
                .animation(.linear(duration: 1.2), value: s.dawn)
            // A quiet, feathered band under the content column keeps text at 4.5:1 wherever trees,
            // traces or the morning light pass behind it.
            Rectangle().fill(ui.scrim.opacity(ui.isDark ? 0.34 : 0.58))
                .frame(width: column + 280, height: h)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                             .init(color: .black, location: 0.88), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
                .mask(LinearGradient(stops: [.init(color: .black.opacity(0.5), location: 0), .init(color: .black, location: 0.3),
                                             .init(color: .black, location: 0.75), .init(color: .black.opacity(0.4), location: 1)], startPoint: .top, endPoint: .bottom))
                .offset(x: x - 140)
                .allowsHitTesting(false)
            // The bars sit on a soft band so their text reads over trees, traces and the morning ground.
            VStack(spacing: 0) {
                LinearGradient(colors: [ui.scrim.opacity(ui.isDark ? 0.5 : 0.6), ui.scrim.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 110)
                Spacer()
                LinearGradient(colors: [ui.scrim.opacity(0), ui.scrim.opacity(ui.isDark ? 0.62 : 0.72)], startPoint: .top, endPoint: .bottom).frame(height: 150)
            }
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                TopBar(s: s).frame(height: 72)
                ZStack(alignment: .topLeading) {
                    content
                        .id(contentID)
                        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .offset(y: 16).combined(with: .opacity),
                                                                           removal: .offset(y: -12).combined(with: .opacity)))
                }
                .frame(width: column, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .center)
                BottomBar(footer: footer, s: s, column: column, x: x).frame(height: 88)
            }
            .environment(\.theme, ui)

            if s.showDetails { DetailsDrawer(s: s).environment(\.theme, ui).transition(.move(edge: .bottom).combined(with: .opacity)) }
            if s.showCommands { Sheet(width: 720, onDismiss: { s.showCommands = false }) { CommandsSheet(s: s) }.environment(\.theme, ui) }
            if s.showWhatIs { Sheet(onDismiss: { s.showWhatIs = false }) { WhatIsSheet(s: s) }.environment(\.theme, ui) }
            if s.showDiagnostics { Sheet(onDismiss: { s.showDiagnostics = false }) { DiagnosticsSheet(s: s) }.environment(\.theme, ui) }
            if s.showWhyNoStop { Sheet(onDismiss: { s.showWhyNoStop = false }) { WhyNoStopSheet(s: s) }.environment(\.theme, ui) }
            if s.showQuitConfirm { Sheet(onDismiss: { s.showQuitConfirm = false }) { QuitSheet(s: s) }.environment(\.theme, ui) }
        }
        .frame(width: w, height: h)
        .background(theme.isDark ? Color.black : Color(hex: 0xC9DCD6))
    }

    private var contentID: String {
        switch s.screen {
        case .inRecovery(let st): return "inRecovery.\(st)"
        case .finish(let o): return "finish.\(o)"
        default: return "\(s.screen)"
        }
    }

    @ViewBuilder private var content: some View {
        switch s.screen {
        case .welcome: WelcomeScreen(s: s)
        case .check: CheckScreen(s: s)
        case .prepare: PrepareScreen(s: s)
        case .space: SpaceScreen(s: s)
        case .options: OptionsScreen(s: s)
        case .review: ReviewScreen(s: s)
        case .approve: ApproveScreen(s: s)
        case .preparing: PreparingScreen(s: s)
        case .installing, .removing: RunScreen(s: s)
        case .recovery: RecoveryScreen(s: s)
        case .inRecovery(let stage): InRecoveryScreen(s: s, stage: stage)
        case .finish(let o): FinishScreen(s: s, outcome: o)
        case .removeWhat: RemoveWhatScreen(s: s)
        case .removeConfirm: RemoveConfirmScreen(s: s)
        case .removed: RemovedScreen(s: s)
        case .failure: FailureScreen(s: s)
        }
    }

    private var footer: Footer {
        let back = BarAction(title: Copy.Common.back) { s.back() }
        let details = BarAction(title: s.showDetails ? Copy.Common.hideDetails : Copy.Common.details) {
            withAnimation(SFMotion.screen) { s.showDetails.toggle() }
        }
        switch s.screen {
        case .welcome:
            var lead = [BarAction(title: Copy.Welcome.whatIs) { s.showWhatIs = true }]
            if s.ownedInstall != nil { lead.append(BarAction(title: Copy.Welcome.remove) { s.go(.removeWhat) }) }
            return Footer(leading: lead, trailing: [BarAction(title: Copy.Welcome.primary, style: .primary, enabled: s.snapshot != nil, isDefault: true) { s.go(.check) }])
        case .check:
            if s.checksDone, let e = Copy.Check.entry(s.entry) {
                var acts: [BarAction] = [back]
                switch s.entry {
                case .installed:
                    acts += [BarAction(title: "Update", enabled: false) {}, BarAction(title: "Remove…") { s.go(.removeWhat) },
                             BarAction(title: Copy.Common.quit, style: .primary) { s.requestQuit() }]
                default:
                    acts += e.actions.dropLast().map { t in BarAction(title: t) {} }
                    acts.append(BarAction(title: e.actions.last ?? Copy.Common.quit, style: .primary) { s.requestQuit() })
                }
                return Footer(leading: [details], trailing: acts)
            }
            if s.checksDone, let b = s.blocker.flatMap({ Copy.Check.blocked($0) }) {
                var acts: [BarAction] = [back]
                acts += b.actions.dropLast().map { t in BarAction(title: t) {} }
                let last = b.actions.last ?? Copy.Common.checkAgain
                acts.append(BarAction(title: last, style: .primary) { last == Copy.Common.quit ? s.requestQuit() : s.runChecks() })
                return Footer(leading: [details], trailing: acts)
            }
            return Footer(leading: [details], trailing: [back, BarAction(title: Copy.Common.continue, style: .primary, enabled: s.canContinueFromChecks, isDefault: true) { s.go(.prepare) }])
        case .prepare:
            return Footer(leading: [details], trailing: [back, BarAction(title: Copy.Common.continue, style: .primary, enabled: s.backupConfirmed, isDefault: true) { s.go(.space) }])
        case .space:
            return Footer(leading: [details], trailing: [back, BarAction(title: Copy.Common.continue, style: .primary, enabled: s.constraints?.isFeasible ?? false, isDefault: true) { s.go(.options) }])
        case .options:
            return Footer(leading: [details], trailing: [back, BarAction(title: Copy.Common.continue, style: .primary, enabled: s.nameError == nil, isDefault: true) { s.go(.review) }])
        case .review:
            // The point of no return: no default key; Return does nothing.
            return Footer(leading: [details], trailing: [back, BarAction(title: Copy.Review.primary, style: .primary, enabled: s.mode == .dryRun) { s.startInstall() }])
        case .approve:
            return Footer(leading: [details], trailing: [BarAction(title: Copy.Common.cancel) { s.go(.review) }, BarAction(title: Copy.Approve.open, style: .primary) {}])
        case .preparing:
            return Footer(leading: [details], trailing: [BarAction(title: Copy.Common.cancel) { s.cancelPreparing() }])
        case .installing, .removing:
            var t: [BarAction] = []
            if s.screen == .installing {
                t.append(s.canStopNow ? BarAction(title: Copy.Installing.stop) { s.requestQuit() }
                                      : BarAction(title: Copy.Installing.whyNoStop) { s.showWhyNoStop = true })
            }
            return Footer(leading: [details], trailing: t)
        case .recovery:
            return Footer(leading: [details, BarAction(title: Copy.Recovery.save) {}],
                          trailing: [BarAction(title: Copy.Recovery.notNow) { s.go(.welcome) },
                                     BarAction(title: s.isDryRun ? Copy.Recovery.dryRunPrimary : Copy.Recovery.primary, style: .primary) { s.shutDownForRecovery() }])
        case .inRecovery(let st):
            switch st {
            case .password: return Footer(leading: [details], trailing: [BarAction(title: Copy.InRecovery.allow, style: .primary, isDefault: true) { s.allowInRecovery() }])
            case .working: return Footer(leading: [details])
            case .ready: return Footer(leading: [details], trailing: [BarAction(title: Copy.InRecovery.wait) {},
                                                                      BarAction(title: Copy.InRecovery.restart, style: .primary, isDefault: true) { s.restartIntoSiliconForest() }])
            }
        case .finish(let o):
            switch o {
            case .verifying: return Footer()
            case .installed: return Footer(leading: [details], trailing: [BarAction(title: Copy.Finish.makeDefault) {},
                                                                          BarAction(title: Copy.Common.done, style: .primary, isDefault: true) { s.terminate() }])
            case .partial, .didNotStart:
                return Footer(leading: [details], trailing: [BarAction(title: Copy.Common.exportDiagnostics) { s.showDiagnostics = true },
                                                             BarAction(title: Copy.Welcome.remove) { s.go(.removeWhat) },
                                                             BarAction(title: Copy.Common.tryAgain, style: .primary) {}])
            }
        case .removeWhat:
            return Footer(leading: [details], trailing: [back, BarAction(title: Copy.Common.continue, style: .primary, isDefault: true) { s.go(.removeConfirm) }])
        case .removeConfirm:
            return Footer(leading: [details], trailing: [BarAction(title: Copy.Common.cancel) { s.go(.welcome) },
                                                         BarAction(title: Copy.Remove.primary, style: .destructive, enabled: s.removeConfirmText == Copy.Remove.confirmWord) { s.startRemoval() }])
        case .removed:
            return Footer(leading: [details], trailing: [BarAction(title: Copy.Common.done, style: .primary, isDefault: true) { s.terminate() }])
        case .failure:
            switch s.failureKind ?? .nothingChanged {
            case .nothingChanged: return Footer(leading: [details], trailing: [BarAction(title: Copy.Common.quit) { s.terminate() },
                                                                               BarAction(title: Copy.Common.tryAgain, style: .primary) { s.go(.review) }])
            case .canUndo: return Footer(leading: [details, BarAction(title: Copy.Common.exportDiagnostics) { s.showDiagnostics = true }],
                                         trailing: [BarAction(title: Copy.Common.tryAgain) { s.go(.review) },
                                                    BarAction(title: Copy.Failure.undoChanges, style: .primary) { s.undoChanges() }])
            case .undoing: return Footer(leading: [details])
            case .undone: return Footer(leading: [details], trailing: [BarAction(title: Copy.Common.done, style: .primary, isDefault: true) { s.go(.welcome) }])
            case .needsAttention, .removalStopped:
                return Footer(leading: [details], trailing: [BarAction(title: Copy.Common.exportDiagnostics, style: .primary) { s.showDiagnostics = true }])
            case .notOurs: return Footer(leading: [details], trailing: [BarAction(title: Copy.Common.learnMore, style: .primary) {}])
            }
        }
    }
}

struct TopBar: View {
    @ObservedObject var s: Session
    @Environment(\.theme) private var theme
    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                BrandMark.themed(theme, glow: false).frame(height: 22)
                Text(Copy.product).font(SFType.labelStrong).foregroundStyle(theme.text)
                Spacer()
                if let i = s.screen.dotIndex { StepDots(index: i).transition(.opacity) }
            }
            ModeBadge(dryRun: s.isDryRun)
        }
        .padding(.horizontal, 32)
        .accessibilityElement(children: .contain)
    }
}

struct BottomBar: View {
    var footer: Footer
    @ObservedObject var s: Session
    var column: CGFloat
    var x: CGFloat
    @Environment(\.theme) private var theme
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(footer.leading.enumerated()), id: \.offset) { _, a in button(a) }
            Spacer()
            ForEach(Array(footer.trailing.enumerated()), id: \.offset) { _, a in button(a) }
        }
        .padding(.horizontal, 22)
        .animation(SFMotion.screen, value: s.screen)
    }

    @ViewBuilder private func button(_ a: BarAction) -> some View {
        switch a.style {
        case .primary:
            if a.isDefault {
                Button(a.title, action: a.action).buttonStyle(SFPrimaryButtonStyle()).disabled(!a.enabled).keyboardShortcut(.defaultAction)
            } else {
                Button(a.title, action: a.action).buttonStyle(SFPrimaryButtonStyle()).disabled(!a.enabled)
            }
        case .text:
            if a.title == Copy.Common.back {
                Button(a.title, action: a.action).buttonStyle(SFTextButtonStyle()).disabled(!a.enabled).keyboardShortcut("[", modifiers: .command)
            } else {
                Button(a.title, action: a.action).buttonStyle(SFTextButtonStyle(color: footer.leading.contains { $0.title == a.title } ? theme.textSecondary : nil)).disabled(!a.enabled)
            }
        case .destructive:
            Button(a.title, action: a.action).buttonStyle(SFDestructiveButtonStyle()).disabled(!a.enabled)
        }
    }
}

// MARK: - Screen scaffolding

/// One Title, one Lead, then the work (VISUAL §4). Left-aligned, measure capped at 62 characters.
struct ScreenHead: View {
    var title: String
    var lead: String?
    var tint: Color? = nil
    @Environment(\.theme) private var theme
    @Environment(\.screenSize) private var screen
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(screen.height < 860 ? SFType.titleCompact : SFType.title)
                .tracking(SFType.titleTracking)
                .foregroundStyle(tint ?? theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let lead {
                Text(lead).font(SFType.lead).tracking(SFType.leadTracking).foregroundStyle(theme.textSecondary)
                    .lineSpacing(6).frame(maxWidth: 640, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, screen.height < 860 ? 28 : 56)
        .padding(.bottom, screen.height < 860 ? 26 : 36)
    }
}

/// A centred modal card over a dimmed scene.
struct Sheet<Content: View>: View {
    var width: CGFloat = 520
    var onDismiss: () -> Void
    @ViewBuilder var content: Content
    @Environment(\.theme) private var theme
    var body: some View {
        ZStack {
            Color.black.opacity(theme.isDark ? 0.55 : 0.28).ignoresSafeArea().onTapGesture(perform: onDismiss)
            content
                .padding(28)
                .frame(width: width, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.surfaceBase)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1)))
                .shadow(color: theme.shadow, radius: 40, y: 18)
        }
        .transition(.opacity)
        .zIndex(20)
    }
}

struct SheetHead: View {
    var title: String
    var bodyText: String?
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(SFType.inter(24, .semibold)).foregroundStyle(theme.text)
            if let bodyText { Text(bodyText).font(SFType.body).foregroundStyle(theme.textSecondary).lineSpacing(5).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

struct QuitSheet: View {
    @ObservedObject var s: Session
    var body: some View {
        let c = s.quitCopy
        VStack(alignment: .leading, spacing: 22) {
            SheetHead(title: c.title, bodyText: c.body.isEmpty ? nil : c.body)
            HStack {
                Spacer()
                Button(c.cancel) { s.showQuitConfirm = false }.buttonStyle(SFTextButtonStyle()).keyboardShortcut(.cancelAction)
                Button(c.confirm) { s.confirmQuit() }.buttonStyle(SFPrimaryButtonStyle())
            }
        }
    }
}

struct WhatIsSheet: View {
    @ObservedObject var s: Session
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHead(title: Copy.Welcome.whatIsTitle, bodyText: Copy.Welcome.whatIsBody)
            HStack { Spacer(); Button(Copy.Common.done) { s.showWhatIs = false }.buttonStyle(SFPrimaryButtonStyle()).keyboardShortcut(.defaultAction) }
        }
    }
}

struct WhyNoStopSheet: View {
    @ObservedObject var s: Session
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHead(title: Copy.Installing.whyNoStop, bodyText: Copy.Installing.whyNoStopBody)
            HStack { Spacer(); Button(Copy.Common.done) { s.showWhyNoStop = false }.buttonStyle(SFPrimaryButtonStyle()).keyboardShortcut(.defaultAction) }
        }
    }
}

struct DiagnosticsSheet: View {
    @ObservedObject var s: Session
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHead(title: Copy.Failure.diagnosticsTitle, bodyText: Copy.Failure.diagnosticsBody)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(["journal.jsonl", "plan.json", "layout-before.json", "layout-now.json", "installer.log"], id: \.self) { f in
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text").foregroundStyle(theme.textSecondary)
                        Text(f).font(SFType.log).foregroundStyle(theme.text)
                    }
                }
            }
            HStack {
                Spacer()
                Button(Copy.Common.cancel) { s.showDiagnostics = false }.buttonStyle(SFTextButtonStyle())
                Button(Copy.Failure.save) { s.showDiagnostics = false }.buttonStyle(SFPrimaryButtonStyle())
            }
        }
    }
}

struct CommandsSheet: View {
    @ObservedObject var s: Session
    @Environment(\.theme) private var theme
    @Environment(\.isSnapshot) private var isSnapshot
    var body: some View {
        let lines = (s.plan ?? previewPlan)?.allCommands.map(CommandRender.render) ?? []
        VStack(alignment: .leading, spacing: 16) {
            SheetHead(title: Copy.Review.commandsTitle, bodyText: Copy.Review.commandsLead)
            Group {
                if isSnapshot {
                    VStack(alignment: .leading, spacing: 4) { ForEach(lines.prefix(14), id: \.self) { commandLine($0) } }
                } else {
                    ScrollView { VStack(alignment: .leading, spacing: 4) { ForEach(lines, id: \.self) { commandLine($0) } }.textSelection(.enabled) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 300, alignment: .topLeading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(theme.surfaceRaised))
            HStack { Spacer(); Button(Copy.Common.done) { s.showCommands = false }.buttonStyle(SFPrimaryButtonStyle()).keyboardShortcut(.defaultAction) }
        }
    }
    private var previewPlan: InstallPlan? {
        guard let p = s.profile, let snap = s.snapshot else { return nil }
        return try? Planner.installPlan(profile: p, snapshot: snap, options: s.options, release: s.release)
    }
    private func commandLine(_ l: String) -> some View {
        Text(l).font(SFType.log).foregroundStyle(theme.textSecondary).lineLimit(1).truncationMode(.middle)
    }
}

struct DetailsDrawer: View {
    @ObservedObject var s: Session
    @Environment(\.theme) private var theme
    @Environment(\.isSnapshot) private var isSnapshot
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(Copy.Common.details).font(SFType.bodyStrong).foregroundStyle(theme.text)
                    Spacer()
                    if let j = s.journalURL { Text(j.lastPathComponent).font(SFType.log).foregroundStyle(theme.textTertiary) }
                }
                let lines = s.log.isEmpty ? factLines : s.log
                Group {
                    if isSnapshot {
                        VStack(alignment: .leading, spacing: 3) { ForEach(lines.suffix(10)) { row($0) } }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).clipped()
                    } else {
                        ScrollView { LazyVStack(alignment: .leading, spacing: 3) { ForEach(lines) { row($0) } }.textSelection(.enabled) }
                    }
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 18)
            .frame(height: 260)
            .background(Rectangle().fill(theme.surfaceBase.opacity(0.97)).overlay(Rectangle().fill(theme.hairline).frame(height: 1), alignment: .top))
            .padding(.bottom, 88)
        }
        .zIndex(10)
    }
    private var factLines: [LogLine] {
        var out: [LogLine] = []
        let t = Date(timeIntervalSince1970: 1_795_000_000)
        if let f = s.facts {
            out.append(LogLine(time: t, level: .info, text: "hw.model \(f.hwModel ?? "?") · target \(f.board ?? "?") · \(f.chipName ?? "?")"))
            out.append(LogLine(time: t, level: .info, text: "macOS \(f.macOSVersion ?? "?") (\(f.macOSBuild ?? "?")) · firmware \(f.systemFirmware ?? "?")"))
        }
        if let d = s.disk {
            let cls = d.classify()
            for p in d.partitions { out.append(LogLine(time: t, level: .command, text: "\(p.identifier)  \(p.content.rawValue)  \(Bytes.format(p.size))  [\(cls[p.identifier]?.rawValue ?? "?")]")) }
        }
        if let c = s.constraints {
            out.append(LogLine(time: t, level: .info, text: "macOS floor \(Bytes.format(c.macOSFloor)) = used \(Bytes.format(c.macOSUsed)) + reserve \(Bytes.format(c.reserve)) + downloads \(Bytes.format(c.downloads)) + drift \(Bytes.format(c.drift))"))
        }
        return out
    }
    private func row(_ l: LogLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Self.time.string(from: l.time)).font(SFType.log).foregroundStyle(theme.textTertiary)
            Text((l.level == .command ? "$ " : "") + l.text).font(SFType.log)
                .foregroundStyle(l.level == .error ? theme.critical : l.level == .success ? theme.ok : l.level == .command ? theme.textSecondary : theme.text)
                .lineLimit(1).truncationMode(.middle)
        }
    }
    static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f }()
}
