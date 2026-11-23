import SwiftUI
import SFInstallKit

// MARK: - Review

struct ReviewScreen: View {
    @Bindable var model: InstallerModel
    var holdPreview: Double? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        PanelScaffold(symbol: "checklist", title: "Review and install",
                      subtitle: "Check the plan. Nothing changes until you press and hold Install.") {
            if let disk = model.disk, let c = model.constraints, let profile = model.profile {
                HStack(alignment: .top, spacing: 30) {
                    VStack(alignment: .leading, spacing: 18) {
                        BeforeAfter(label: "Now", disk: disk, constraints: nil, size: model.siliconForestSize, asIs: true)
                        BeforeAfter(label: "After", disk: disk, constraints: c, size: model.siliconForestSize, asIs: false,
                                    stub: profile.partitioning.stubContainerBytes, boot: profile.partitioning.bootPartition.bytes)
                        PartitionBreakdown(profile: profile, size: model.siliconForestSize, compact: true)
                        if model.isDryRun {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "testtube.2").foregroundStyle(theme.copper)
                                Text("Dry run: the installer goes through every step against a simulated copy of this disk. Your real disk is never touched.")
                                    .font(Typo.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.copper.opacity(0.08))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.copper.opacity(0.3), lineWidth: 1)))
                        }
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 0) {
                        SummaryRow(symbol: "laptopcomputer", title: "Mac", value: profile.marketingName, detail: "\(profile.id) · \(profile.soc.name)")
                        divider
                        SummaryRow(symbol: "arrow.down.right.and.arrow.up.left", title: "macOS", value: "\(Bytes.format(c.macOSPartition.size)) → \(Bytes.format(c.macOSSize(for: model.siliconForestSize)))", detail: "Shrinks. Your files and apps stay.")
                        divider
                        SummaryRow(symbol: "sf.mark", title: "SiliconForest", value: "“\(model.installName)” · \(Bytes.format(model.siliconForestSize))", detail: "Startup, boot (\(profile.partitioning.bootPartition.name)) and system partitions")
                        divider
                        SummaryRow(symbol: "power", title: "Default system", value: model.defaultBoot == .macOS ? "macOS" : model.installName, detail: "Hold the power button to choose at startup")
                        divider
                        SummaryRow(symbol: "clock", title: "Time", value: "About 15 minutes", detail: "Then about 2 minutes in recoveryOS")
                    }
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.card)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: 1)))
                    .frame(width: 430)
                }
            }
        } footer: {
            Button("Back") { model.back() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut("[", modifiers: .command)
            Spacer()
            Text("Press and hold to start").font(Typo.callout).foregroundStyle(theme.textTertiary).padding(.trailing, 6)
            HoldButton(title: "Hold to Install", holdingTitle: "Keep holding…", symbol: "arrow.down", previewProgress: holdPreview) {
                model.startInstall()
            }
        }
    }

    private var divider: some View { Rectangle().fill(theme.hairline).frame(height: 1).padding(.leading, 56) }
}

struct BeforeAfter: View {
    var label: String
    var disk: PhysicalDisk
    var constraints: SizingConstraints?
    var size: Int64
    var asIs: Bool
    var stub: Int64 = 2_500_000_000
    var boot: Int64 = 524_288_000
    var reclaim: SiliconForestInstall? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(label.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(theme.textTertiary)
                Spacer()
                Text(caption).font(Typo.number(12, weight: .medium)).foregroundStyle(theme.textSecondary)
            }
            PartitionBar(disk: disk, constraints: constraints, size: .constant(size), stub: stub, boot: boot,
                         editable: false, height: 58, asIs: asIs, reclaim: reclaim)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(caption)")
    }

    private var caption: String {
        if let reclaim, let mac = disk.macOSPartition {
            return "macOS \(Bytes.format(mac.size + reclaim.totalBytes + disk.freeAfter(reclaim.partitions.last?.identifier ?? "")))"
        }
        if asIs {
            let mac = disk.macOSPartition?.size ?? 0
            let sf = disk.partitions.filter { $0.isSiliconForestStub || $0.isSiliconForestBoot || $0.isSiliconForestRoot }.reduce(0) { $0 + $1.size }
            return sf > 0 ? "macOS \(Bytes.format(mac)) · SiliconForest \(Bytes.format(sf))" : "macOS \(Bytes.format(mac))"
        }
        guard let c = constraints else { return "" }
        return "macOS \(Bytes.format(c.macOSSize(for: size))) · SiliconForest \(Bytes.format(size))"
    }
}

struct SummaryRow: View {
    var symbol: String
    var title: String
    var value: String
    var detail: String
    var tint: Color? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Glyph(symbol: symbol, size: 14, color: tint ?? theme.mint)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(Typo.callout).foregroundStyle(theme.textSecondary)
                    Spacer()
                    Text(value).font(.system(size: 13.5, weight: .semibold).monospacedDigit()).foregroundStyle(theme.text).lineLimit(1)
                }
                Text(detail).font(.system(size: 12)).foregroundStyle(theme.textTertiary).lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Installing / uninstalling

struct RunScreen: View {
    @Bindable var model: InstallerModel
    @Environment(\.theme) private var theme
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        let plan = model.plan
        let isInstall = plan?.kind != .uninstall
        VStack(spacing: 0) {
            // Header: title, current activity, big percentage
            HStack(alignment: .bottom, spacing: 20) {
                HeaderIcon(symbol: isInstall ? "arrow.down.circle" : "trash", tint: isInstall ? theme.mint : theme.copper, size: 56)
                VStack(alignment: .leading, spacing: 6) {
                    Text(isInstall ? "Installing SiliconForest" : "Removing \(plan?.options.installName ?? "SiliconForest")")
                        .font(Typo.display).foregroundStyle(theme.text)
                    Text(currentTitle).font(Typo.subtitle).foregroundStyle(theme.textSecondary)
                        .contentTransition(.opacity)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(Int(model.overallProgress * 100))").font(.system(size: 50, weight: .light).monospacedDigit()).foregroundStyle(theme.text)
                            .contentTransition(.numericText(value: model.overallProgress))
                        Text("%").font(.system(size: 20, weight: .regular)).foregroundStyle(theme.textSecondary)
                    }
                    Text(model.etaText).font(Typo.callout).foregroundStyle(theme.textSecondary)
                }
            }
            .padding(.horizontal, 48).padding(.top, 40)

            ProgressTrack(value: model.overallProgress, height: 7)
                .padding(.horizontal, 48).padding(.top, 22)

            HStack(alignment: .top, spacing: 28) {
                // Steps
                VStack(alignment: .leading, spacing: 0) {
                    if let plan {
                        ForEach(Array(plan.steps.enumerated()), id: \.offset) { i, step in
                            StepRow(title: step.title, state: model.stepStates.indices.contains(i) ? model.stepStates[i] : .pending,
                                    fraction: i == model.currentStep ? model.stepFraction : nil)
                        }
                        if plan.kind == .uninstall, let disk = model.disk, let install = model.selectedInstall {
                            BeforeAfter(label: "When finished", disk: disk, constraints: nil, size: 0, asIs: false, reclaim: install)
                                .padding(.top, 22).padding(.horizontal, 10)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Now
                NowCard(model: model)
                    .frame(width: 400)
            }
            .padding(.horizontal, 48).padding(.top, 26)
            .frame(maxHeight: .infinity, alignment: .top)

            Rectangle().fill(theme.hairline).frame(height: 1)
            HStack(spacing: 12) {
                Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { model.logOpen.toggle() } } label: {
                    Label(model.logOpen ? "Hide Log" : "Show Log", systemImage: "text.alignleft")
                }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut("l", modifiers: .command)
                Text("Keep the lid open and the charger connected.").font(Typo.callout).foregroundStyle(theme.textTertiary).padding(.leading, 8)
                Spacer()
                Button("Stop…") { model.requestQuit() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(plan?.kind == .uninstall)
            }
            .padding(.horizontal, 32).frame(height: 76)
        }
        .overlay(alignment: .bottom) {
            if model.logOpen {
                LogDrawer(lines: model.log, journal: model.journalURL)
                    .padding(.bottom, 76)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var currentTitle: String {
        guard let plan = model.plan, let i = model.currentStep, plan.steps.indices.contains(i) else { return "Starting…" }
        return plan.steps[i].activeTitle
    }
}

struct StepRow: View {
    var title: String
    var state: StepRunState
    var fraction: Double?
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            StatusGlyph(kind: glyph, size: 20)
            Text(title)
                .font(.system(size: 13.5, weight: state == .running ? .semibold : .regular))
                .foregroundStyle(state == .pending || state == .skipped ? theme.textTertiary : theme.text)
            Spacer()
            if let fraction, state == .running {
                Text("\(Int(fraction * 100))%").font(Typo.number(12, weight: .medium)).foregroundStyle(theme.mint)
            } else if state == .undone {
                Text("undone").font(Typo.caption).foregroundStyle(theme.copper)
            } else if state == .failed {
                Text("stopped").font(Typo.caption).foregroundStyle(theme.coral)
            }
        }
        .frame(height: 29)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(state == .running ? theme.mint.opacity(0.08) : Color.clear))
        .accessibilityElement(children: .combine)
    }

    private var glyph: StatusGlyph.Kind {
        switch state {
        case .pending: return .pending
        case .running, .undoing: return .running
        case .done: return .pass
        case .failed, .undoFailed: return .fail
        case .undone: return .undone
        case .skipped: return .skipped
        }
    }
}

struct NowCard: View {
    var model: InstallerModel
    @Environment(\.theme) private var theme

    var body: some View {
        let step = model.plan.flatMap { p in model.currentStep.flatMap { p.steps.indices.contains($0) ? p.steps[$0] : nil } }
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("NOW").font(.system(size: 11, weight: .bold)).tracking(1.3).foregroundStyle(theme.mint)
                Spacer()
                if let i = model.currentStep, let p = model.plan {
                    Text("Step \(i + 1) of \(p.steps.count)").font(Typo.caption).foregroundStyle(theme.textTertiary)
                }
            }
            Text(step?.title ?? "Preparing").font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.text)
            Text(step?.detail ?? "").font(Typo.callout).foregroundStyle(theme.textSecondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                ProgressTrack(value: model.stepFraction, height: 4)
                Text(model.stepDetail).font(Typo.number(12, weight: .medium)).foregroundStyle(theme.textSecondary).lineLimit(1)
            }
            .padding(.top, 4)
            if let cmd = model.log.last(where: { $0.level == .command }) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.isDryRun ? "SIMULATING" : "PLANNED, NOT RUN").font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(theme.copper)
                    Text("$ " + cmd.text).font(Typo.monoSmall).foregroundStyle(theme.textSecondary).lineLimit(2).truncationMode(.middle)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.well))
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.card)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: 1)))
    }
}

struct LogDrawer: View {
    var lines: [LogLine]
    var journal: URL?
    @Environment(\.theme) private var theme
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Capsule().fill(theme.textTertiary.opacity(0.5)).frame(width: 36, height: 4)
            }
            .frame(maxWidth: .infinity).padding(.top, 8)
            HStack {
                Text("Log").font(Typo.headline).foregroundStyle(theme.text)
                Spacer()
                if let journal {
                    Text(journal.lastPathComponent).font(Typo.monoSmall).foregroundStyle(theme.textTertiary).lineLimit(1).truncationMode(.middle)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 8)
            Group {
                if isSnapshot {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(lines.suffix(11)) { line in row(line) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .clipped()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 3) {
                                ForEach(lines) { line in row(line).id(line.id) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .onChange(of: lines.count) { _, _ in
                            if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 14)
        }
        .frame(height: 250)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous)
                .fill(theme.isDark ? Color(hex: 0x07100D) : Color(hex: 0xF7F8F4))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: 1))
        )
        .shadow(color: theme.shadow, radius: 20, y: -6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Installation log")
    }

    private func row(_ line: LogLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Self.time.string(from: line.time)).font(Typo.monoSmall).foregroundStyle(theme.textTertiary)
            Text(prefix(line.level) + line.text)
                .font(Typo.monoSmall)
                .foregroundStyle(color(line.level))
                .lineLimit(1).truncationMode(.middle)
        }
    }

    private func prefix(_ l: LogLine.Level) -> String {
        switch l {
        case .command: return "$ "
        case .planned: return "  "
        default: return ""
        }
    }

    private func color(_ l: LogLine.Level) -> Color {
        switch l {
        case .command: return theme.textSecondary
        case .success: return theme.mint
        case .warning, .planned: return theme.copper
        case .error: return theme.coral
        case .info: return theme.text
        }
    }

    static let time: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()
}

// MARK: - Recovery handoff

struct RecoveryScreen: View {
    var model: InstallerModel
    @Environment(\.theme) private var theme

    var body: some View {
        let name = model.plan?.options.installName ?? model.installName
        PanelScaffold(symbol: "power", title: "One last step, in recoveryOS",
                      subtitle: "Only recoveryOS can give \(name) its own startup security, and only with you at the keyboard.",
                      tint: theme.copper) {
            VStack(spacing: 22) {
                HStack(alignment: .top, spacing: 14) {
                    StepTile(n: 1, symbol: "power", title: "Shut down", text: "Choose Shut Down below. Wait until the screen is dark, then 10 more seconds.")
                    StepTile(n: 2, symbol: "hand.point.up.left", title: "Hold the power button", text: "Press and keep holding it until “Loading startup options…” appears.")
                    StepTile(n: 3, symbol: "cursorarrow.click.2", title: "Choose \(name)", text: "Select \(name), then click Continue. recoveryOS opens.")
                    StepTile(n: 4, symbol: "keyboard", title: "Confirm", text: "Enter your password when asked and type y. The Mac restarts into \(name).")
                }
                .fixedSize(horizontal: false, vertical: true)

                TerminalCard(name: name, user: model.facts?.userName ?? "you")
            }
        } footer: {
            Button { } label: { Label("Save Instructions", systemImage: "square.and.arrow.down") }
                .buttonStyle(SecondaryButtonStyle())
            Text("A copy is also on your Desktop.").font(Typo.callout).foregroundStyle(theme.textTertiary).padding(.leading, 6)
            Spacer()
            Button(model.isDryRun ? "Shut Down (simulated)" : "Shut Down…") { model.go(.done) }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
    }
}

struct StepTile: View {
    var n: Int
    var symbol: String
    var title: String
    var text: String
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("\(n)").font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundStyle(theme.onAccent)
                    .frame(width: 24, height: 24).background(Circle().fill(theme.copper))
                Spacer()
                Image(systemName: symbol).font(.system(size: 18, weight: .regular)).foregroundStyle(theme.copper)
            }
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.text).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Text(text).font(Typo.callout).foregroundStyle(theme.textSecondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.card)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: 1)))
        .accessibilityElement(children: .combine)
    }
}

struct TerminalCard: View {
    var name: String
    var user: String
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1.2).frame(width: 10, height: 10) }
                Text("What you’ll see and type").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.white.opacity(0.55)).padding(.leading, 6)
                Spacer()
                Text("If nothing opens by itself: Utilities → Terminal, then type the first line")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.white.opacity(0.4))
            }
            .padding(.horizontal, 16).frame(height: 34)
            .background(Color.white.opacity(0.04))
            VStack(alignment: .leading, spacing: 7) {
                line(prompt: "-bash-3.2#", typed: "/Volumes/\(name)/step2.sh", note: nil)
                line(prompt: nil, typed: nil, note: "\(name): setting startup security for this system only. macOS is not changed.")
                line(prompt: "Password for \(user):", typed: "••••••••", note: nil)
                line(prompt: "Allow \(name) to start with Permissive Security? [y/N]", typed: "y", note: nil)
                line(prompt: nil, typed: nil, note: "Done. Restarting into \(name)…", success: true)
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x050A08))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1)))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("In recoveryOS Terminal, type slash Volumes slash \(name) slash step2.sh and press Return. Enter your password, then type y.")
    }

    private func line(prompt: String?, typed: String?, note: String?, success: Bool = false) -> some View {
        HStack(spacing: 8) {
            if let prompt { Text(prompt).foregroundStyle(Color.white.opacity(0.5)) }
            if let typed {
                Text(typed).foregroundStyle(Color(hex: 0xB6F5CF)).fontWeight(.semibold)
                Text("⏎").foregroundStyle(Color(hex: 0xE39A62))
            }
            if let note { Text(note).foregroundStyle(success ? Color(hex: 0x6FDDAA) : Color.white.opacity(0.6)) }
        }
        .font(.system(size: 12.5, weight: .regular, design: .monospaced))
    }
}

// MARK: - Done

struct DoneScreen: View {
    var model: InstallerModel
    @Environment(\.theme) private var theme

    var body: some View {
        let name = model.plan?.options.installName ?? model.installName
        VStack(spacing: 0) {
            ZStack {
                Circle().strokeBorder(theme.mint.opacity(0.25), lineWidth: 1).frame(width: 196, height: 196)
                Circle().strokeBorder(theme.mint.opacity(0.12), lineWidth: 1).frame(width: 250, height: 250)
                BrandMark.mint(theme).frame(height: 116)
            }
            .padding(.bottom, 30)
            Text("\(name) is installed")
                .font(.system(size: 50, weight: .light)).tracking(-0.4).foregroundStyle(theme.text)
                .accessibilityAddTraits(.isHeader)
            Text("Hold the power button as your Mac starts to choose a system.\n\(model.defaultBoot == .macOS ? "macOS stays the default." : "\(name) is the default.")")
                .multilineTextAlignment(.center)
                .font(.system(size: 18, weight: .regular)).foregroundStyle(theme.textSecondary).lineSpacing(4)
                .padding(.top, 10)
            HStack(spacing: 10) {
                pill("sf.mark", Bytes.format(model.plan?.siliconForestSize ?? model.siliconForestSize))
                pill("laptopcomputer", "macOS \(Bytes.format(model.plan?.macOSSizeAfter ?? 0))")
                pill("checkmark.shield", "Startup security set")
            }
            .padding(.top, 28)
            Button("Done") { model.terminate() }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .padding(.top, 38)
            if model.isDryRun {
                Text("Dry run complete. No disk was changed.").font(Typo.callout).foregroundStyle(theme.copper).padding(.top, 16)
            }
        }
        .padding(.bottom, 30)
    }

    private func pill(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 7) {
            Glyph(symbol: symbol, size: 12, color: theme.mint)
            Text(text).font(.system(size: 13, weight: .medium).monospacedDigit()).foregroundStyle(theme.text)
        }
        .padding(.horizontal, 14).frame(height: 32)
        .background(Capsule().fill(theme.isDark ? Color.black.opacity(0.3) : Color.white.opacity(0.6)).overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1)))
    }
}
