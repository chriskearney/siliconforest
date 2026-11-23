import SwiftUI
import SFInstallKit
import SFCopy
import SFDesign
import SFFlow

// MARK: 1. Welcome

struct WelcomeScreen: View {
    @ObservedObject var s: Session
    @Environment(\.theme) private var theme
    @Environment(\.isSnapshot) private var isSnapshot
    @Environment(\.screenSize) private var screen
    @State private var drawn: Double = 0

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            Spacer(minLength: 0)
            BrandMark.themed(theme, progress: isSnapshot ? 1 : drawn)
                .frame(height: screen.height < 860 ? 96 : 118)
                .padding(.bottom, 34)
            Text(Copy.Welcome.title)
                .font(screen.height < 860 ? SFType.inter(64, .semibold) : SFType.display)
                .tracking(SFType.displayTracking)
                .foregroundStyle(theme.text)
                .accessibilityAddTraits(.isHeader)
            Text(Copy.Welcome.lead)
                .font(SFType.inter(24, .medium)).tracking(-0.3)
                .foregroundStyle(theme.text.opacity(0.92))
                .padding(.top, 14)
            Text(Copy.Welcome.body)
                .font(SFType.lead).foregroundStyle(theme.textSecondary).lineSpacing(6)
                .frame(maxWidth: 600)
                .padding(.top, 12)
            Text(footer)
                .font(SFType.label).foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 12).frame(height: 28)
                .background(Capsule().fill(theme.isDark ? Color.black.opacity(0.3) : Color.white.opacity(0.55)).overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1)))
                .padding(.top, 30)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onAppear { withAnimation(.easeInOut(duration: 1.4)) { drawn = 1 } }
    }

    private var footer: String {
        guard let f = s.facts else { return Copy.installer }
        let model = s.profile.flatMap { $0.matches(hwModel: f.hwModel, board: f.board) ? $0.marketingName : nil } ?? (f.chipName ?? f.hwModel ?? "This Mac")
        return Copy.Welcome.footer(model: model, macOS: f.macOSVersion ?? "?")
    }
}

// MARK: 2. Compatibility check

struct CheckScreen: View {
    @ObservedObject var s: Session
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHead(title: head.title, lead: head.lead)
            VStack(spacing: 0) {
                ForEach(Array(s.checks.enumerated()), id: \.element.id) { i, c in
                    row(c, state: i < s.checksRevealed ? glyph(c) : (i == s.checksRevealed && s.checksRunning ? .working : .waiting))
                    if i < s.checks.count - 1 { Rectangle().fill(theme.hairline.opacity(0.6)).frame(height: 1) }
                }
            }
            .frame(maxWidth: 680)
        }
    }

    private var head: (title: String, lead: String) {
        guard s.checksDone else { return (Copy.Check.title, Copy.Check.lead) }
        if let e = Copy.Check.entry(s.entry) { return (e.title, e.body) }
        if let b = s.blocker.flatMap({ Copy.Check.blocked($0) }) { return (b.title, b.body) }
        return (Copy.Check.ready, Copy.Check.readyLead)
    }

    private func glyph(_ c: CompatibilityCheck) -> RowState {
        switch c.status { case .pass: return .pass; case .warning: return .warning; case .fail: return .fail; case .info: return .info }
    }

    private func row(_ c: CompatibilityCheck, state: RowState) -> some View {
        HStack(spacing: 14) {
            RowGlyph(state, size: 20)
            Text(Copy.Check.label(c.kind)).font(SFType.label).foregroundStyle(theme.textSecondary).frame(width: 140, alignment: .leading)
            Text(state == .waiting || state == .working ? "" : Copy.Check.text(c.finding))
                .font(state == .fail ? SFType.bodyStrong : SFType.body)
                .foregroundStyle(state == .fail ? theme.critical : theme.text)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: 36)
        .opacity(state == .waiting ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }
}

// MARK: 3. Before you begin

struct PrepareScreen: View {
    @ObservedObject var s: Session
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHead(title: Copy.Prepare.title, lead: Copy.Prepare.lead)
            HStack(alignment: .top, spacing: 48) {
                column(Copy.Prepare.changesHeader, Copy.Prepare.changes, symbol: "arrow.triangle.branch", color: theme.accent)
                column(Copy.Prepare.keepsHeader, Copy.Prepare.keeps, symbol: "lock", color: theme.ok)
            }
            Rectangle().fill(theme.hairline.opacity(0.7)).frame(height: 1).padding(.vertical, 24)
            VStack(alignment: .leading, spacing: 8) {
                (Text(Copy.Prepare.backupTitle + " ").font(SFType.bodyStrong).foregroundColor(theme.text)
                    + Text(Copy.Prepare.backupBody).font(SFType.body).foregroundColor(theme.textSecondary))
                    .lineSpacing(5).frame(maxWidth: 660, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 12)).foregroundStyle(theme.textSecondary)
                    Text(Copy.Prepare.lastBackup(Copy.Prepare.sampleBackupTime, Copy.Prepare.sampleBackupDisk)).font(SFType.label).foregroundStyle(theme.textSecondary)
                }
            }
            CheckboxRow(Copy.Prepare.checkbox, isOn: $s.backupConfirmed).padding(.top, 20)
            DisclosureLine(Copy.Prepare.aboutSecurity, expanded: s.showSecurity) { withAnimation(SFMotion.screen) { s.showSecurity.toggle() } }
                .padding(.top, 22)
            if s.showSecurity {
                Text(Copy.Prepare.aboutSecurityBody).font(SFType.body).foregroundStyle(theme.textSecondary).lineSpacing(5)
                    .frame(maxWidth: 640, alignment: .leading).padding(.top, 10).padding(.leading, 20)
                    .transition(.opacity)
            }
        }
    }

    private func column(_ head: String, _ items: [String], symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(head)
            ForEach(items, id: \.self) { i in
                HStack(spacing: 12) {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(color).frame(width: 18)
                    Text(i).font(SFType.body).foregroundStyle(theme.text)
                }
            }
        }
        .frame(maxWidth: 380, alignment: .leading)
    }
}

// MARK: 4. Choose your space

struct SpaceScreen: View {
    @ObservedObject var s: Session
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHead(title: Copy.Space.title, lead: Copy.Space.lead)
            if let disk = s.disk, let c = s.constraints {
                let mac = c.macOSSize(for: s.siliconForestSize)
                HStack(alignment: .lastTextBaseline) {
                    number(Copy.Space.macOS, mac, align: .leading)
                    Spacer()
                    number(Copy.Space.siliconForest, s.siliconForestSize, align: .trailing, accent: true)
                }
                // Traces from the handle up to each size label.
                GeometryReader { g in
                    let frames = DiskBar.layout(DiskBarModel.after(disk, c, siliconForest: s.siliconForestSize), width: g.size.width)
                    let hx = frames["sf.new"]?.lowerBound ?? g.size.width / 2
                    LabelTraces(handleX: hx, width: g.size.width, active: s.snapshotHandleActive)
                }
                .frame(height: 26)
                DiskBar(segments: DiskBarModel.after(disk, c, siliconForest: s.siliconForestSize), constraints: c,
                        size: Binding(get: { s.siliconForestSize }, set: { s.setSize($0) }),
                        forceActive: s.snapshotHandleActive, onLimit: { s.limitHit = $0 })
                    .animation(SFMotion.numbers, value: s.siliconForestSize)
                underLabels(disk: disk, c: c)
                    .padding(.top, 10)
                HStack(alignment: .center, spacing: 14) {
                    Text(Copy.Space.keepsFree(c.macOSFree(for: s.siliconForestSize))).font(SFType.body).foregroundStyle(theme.textSecondary)
                    Spacer()
                    SFTextField("", text: $s.sizeText, monospacedDigits: true, trailing: Copy.Space.gb, width: 112)
                        .onSubmit { s.commitSizeText() }
                    stepper
                }
                .padding(.top, 22)
                HStack(spacing: 8) {
                    ForEach(c.presets) { p in
                        PresetChip(title: Copy.Space.preset(p.id), selected: p.size == s.siliconForestSize) { withAnimation(SFMotion.bar) { s.setSize(p.size) } }
                    }
                    Spacer()
                }
                .padding(.top, 16)
                limitLine(c).frame(height: 20).padding(.top, 14)
                DisclosureLine(s.showPartitionDetails ? Copy.Space.hideDetails : Copy.Space.showDetails, expanded: s.showPartitionDetails) {
                    withAnimation(SFMotion.screen) { s.showPartitionDetails.toggle() }
                }
                .padding(.top, 8)
                if s.showPartitionDetails, let p = s.profile { partitionTable(c, p).padding(.top, 10).transition(.opacity) }
            }
        }
    }

    private func number(_ label: String, _ bytes: Int64, align: HorizontalAlignment, accent: Bool = false) -> some View {
        VStack(alignment: align, spacing: 2) {
            Text(label).font(SFType.label).foregroundStyle(accent ? theme.accent : theme.textSecondary)
            Text(Bytes.format(bytes)).font(SFType.numerals).tracking(-0.3).foregroundStyle(theme.text)
        }
        .accessibilityElement(children: .combine)
    }

    private func underLabels(disk: PhysicalDisk, c: SizingConstraints) -> some View {
        HStack(spacing: 16) {
            legend(theme.barMacUsed, Copy.Space.used(c.macOSUsed), solid: true)
            legend(theme.barMacFree, Copy.Space.free(c.macOSFree(for: s.siliconForestSize)), solid: false)
            Spacer()
            legend(theme.accent, Copy.Space.new(s.siliconForestSize), solid: true)
        }
    }

    private func legend(_ color: Color, _ text: String, solid: Bool) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(solid ? color : color.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(solid ? .clear : theme.barMacUsed.opacity(0.6), lineWidth: 1))
                .frame(width: 10, height: 10)
            Text(text).font(SFType.label).foregroundStyle(theme.textSecondary)
        }
    }

    private var stepper: some View {
        HStack(spacing: 0) {
            Button { s.nudge(-1) } label: { Image(systemName: "minus").frame(width: 38, height: 44).contentShape(Rectangle()) }
            Rectangle().fill(theme.hairline).frame(width: 1, height: 22)
            Button { s.nudge(1) } label: { Image(systemName: "plus").frame(width: 38, height: 44).contentShape(Rectangle()) }
        }
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(theme.text)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.surfaceBase.opacity(theme.isDark ? 0.7 : 0.9))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1)))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func limitLine(_ c: SizingConstraints) -> some View {
        let text: String? = {
            if c.rootLocked { return Copy.Space.fixed(c.minimum) }
            switch s.limitHit {
            case .macOSReserve: return Copy.Space.limitReserve(c.reserve)
            case .siliconForestMinimum: return Copy.Space.limitMinimum(c.minimum)
            case .none: return s.siliconForestSize < c.lowSpaceNote ? Copy.Space.lowSpace : nil
            }
        }()
        if let text {
            HStack(spacing: 8) {
                Image(systemName: s.limitHit == .none ? "info.circle" : "hand.raised").font(.system(size: 12, weight: .semibold))
                Text(text).font(SFType.label)
            }
            .foregroundStyle(s.limitHit == .none ? theme.textSecondary : theme.caution)
            .transition(.opacity)
        }
    }

    private func partitionTable(_ c: SizingConstraints, _ p: DeviceProfile) -> some View {
        Panel(padding: 16) {
            VStack(spacing: 8) {
                tableRow(Copy.Space.partStub, Copy.Space.partDetail("stub"), c.stub)
                tableRow(Copy.Space.partBoot, Copy.Space.partDetail("boot"), c.boot)
                tableRow(Copy.Space.partRoot, Copy.Space.partDetail("root"), s.siliconForestSize - c.stub - c.boot)
                Rectangle().fill(theme.hairline).frame(height: 1)
                tableRow("macOS", "\(Bytes.format(c.macOSPartition.size)) now", c.macOSSize(for: s.siliconForestSize))
            }
        }
    }

    private func tableRow(_ a: String, _ b: String, _ size: Int64) -> some View {
        HStack {
            Text(a).font(SFType.labelStrong).foregroundStyle(theme.text).frame(width: 130, alignment: .leading)
            Text(b).font(SFType.label).foregroundStyle(theme.textSecondary)
            Spacer()
            Text(Bytes.format(size)).font(SFType.number(13, .medium)).foregroundStyle(theme.text)
        }
    }
}

/// Fine traces from the handle up to the two size labels, ending in vias.
struct LabelTraces: View {
    var handleX: CGFloat
    var width: CGFloat
    var active: Bool
    @Environment(\.theme) private var theme
    var body: some View {
        Canvas { ctx, size in
            let y0 = size.height, ymid = size.height * 0.45
            var p = Path()
            p.move(to: CGPoint(x: handleX, y: y0)); p.addLine(to: CGPoint(x: handleX, y: ymid + 6))
            p.addLine(to: CGPoint(x: handleX - 6, y: ymid)); p.addLine(to: CGPoint(x: 6, y: ymid)); p.addLine(to: CGPoint(x: 6, y: 0))
            p.move(to: CGPoint(x: handleX, y: ymid + 6)); p.addLine(to: CGPoint(x: handleX + 6, y: ymid))
            p.addLine(to: CGPoint(x: size.width - 6, y: ymid)); p.addLine(to: CGPoint(x: size.width - 6, y: 0))
            ctx.stroke(p, with: .color(theme.accent.opacity(active ? 0.75 : 0.35)), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
            for x in [CGFloat(6), size.width - 6] {
                ctx.stroke(Path(ellipseIn: CGRect(x: x - 2.5, y: -2.5, width: 5, height: 5)), with: .color(theme.accent.opacity(active ? 0.9 : 0.5)), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }
}

struct PresetChip: View {
    var title: String
    var selected: Bool
    var action: () -> Void
    @Environment(\.theme) private var theme
    var body: some View {
        Button(action: action) {
            Text(title).font(SFType.label)
                .foregroundStyle(selected ? theme.text : theme.textSecondary)
                .padding(.horizontal, 14).frame(height: 32)
                .background(Capsule(style: .continuous).fill(selected ? theme.selection : Color.clear)
                    .overlay(Capsule(style: .continuous).strokeBorder(selected ? theme.accent : theme.hairline, lineWidth: selected ? 1.3 : 1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: 5. Options

struct OptionsScreen: View {
    @ObservedObject var s: Session
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHead(title: Copy.Options.title, lead: Copy.Options.lead)
            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(Copy.Options.nameLabel)
                        SFTextField(Copy.product, text: $s.installName, error: s.nameError, showsCaret: s.snapshotNameFocus, width: 360)
                        Text(Copy.Options.nameHelp).font(SFType.label).foregroundStyle(theme.textSecondary)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(Copy.Options.afterSetup)
                        RadioRow(Copy.Options.startOnce, subtitle: Copy.Options.startOnceHelp, selected: s.afterSetup == .startOnceKeepMacOS) { s.afterSetup = .startOnceKeepMacOS }
                        RadioRow(Copy.Options.makeDefault, selected: s.afterSetup == .makeDefaultAfterSuccess) { s.afterSetup = .makeDefaultAfterSuccess }
                    }
                    DisclosureLine(Copy.Options.advanced, expanded: s.showAdvanced) { withAnimation(SFMotion.screen) { s.showAdvanced.toggle() } }
                    if s.showAdvanced {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text(Copy.Options.channel).font(SFType.body).foregroundStyle(theme.text); Spacer(); Text(Copy.Options.stable).font(SFType.body).foregroundStyle(theme.textSecondary) }
                            CheckboxRow(Copy.Options.keepDownloads, isOn: $s.keepDownloads)
                            CheckboxRow(Copy.Options.localRelease, isOn: .constant(false)).opacity(0.45).disabled(true)
                        }
                        .frame(maxWidth: 440).padding(.leading, 20)
                    }
                }
                Spacer(minLength: 0)
                StartupPickerPreview(name: s.installName.isEmpty ? Copy.product : s.installName)
                    .frame(width: 300)
            }
        }
    }
}

/// A schematic of the startup picker (our own drawing, not Apple's artwork).
struct StartupPickerPreview: View {
    var name: String
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(spacing: 16) {
            Text(Copy.Options.atStartup.uppercased()).font(SFType.micro).tracking(1.2).foregroundStyle(Color.white.opacity(0.5))
            HStack(spacing: 22) {
                volume("Macintosh HD", isDefault: true) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0xB3BDB5), Color(hex: 0x7C877F)], startPoint: .top, endPoint: .bottom))
                        .overlay(Image(systemName: "internaldrive").font(.system(size: 24, weight: .light)).foregroundStyle(.white))
                }
                volume(name, isDefault: false) { AppIconArt() }
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LinearGradient(colors: [Color(hex: 0x0B1512), Color(hex: 0x030706)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1)))
        .shadow(color: theme.shadow, radius: 20, y: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview: the startup picker shows Macintosh HD and \(name).")
    }
    private func volume<I: View>(_ title: String, isDefault: Bool, @ViewBuilder icon: () -> I) -> some View {
        VStack(spacing: 8) {
            icon().frame(width: 64, height: 64).padding(8)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(isDefault ? 0.12 : 0)))
            Text(title).font(SFType.labelStrong).foregroundStyle(.white).lineLimit(1).frame(maxWidth: 110)
            Text(isDefault ? Copy.Options.defaultLabel : " ").font(SFType.caption).foregroundStyle(Color.white.opacity(0.55))
        }
    }
}

// MARK: 6. Review

struct ReviewScreen: View {
    @ObservedObject var s: Session
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHead(title: Copy.Review.title, lead: Copy.Review.lead)
            if let disk = s.disk, let c = s.constraints, let p = s.profile {
                VStack(alignment: .leading, spacing: 10) {
                    barRow(Copy.Review.now, DiskBarModel.current(disk))
                    barRow(Copy.Review.after, DiskBarModel.after(disk, c, siliconForest: s.siliconForestSize))
                }
                VStack(spacing: 0) {
                    row(Copy.Review.shrink, Copy.Review.shrinkValue(from: c.macOSPartition.size, to: c.macOSSize(for: s.siliconForestSize), free: c.macOSFree(for: s.siliconForestSize)))
                    row(Copy.Review.add, Copy.Review.addValue(s.siliconForestSize))
                    row(Copy.Review.download, Copy.Review.downloadValue(release: s.release.downloadBytes, apple: p.support.stubDownloadBytes ?? 720_000_000))
                    row(Copy.Review.time, Copy.Review.timeValue, last: true)
                }
                .padding(.top, 22)
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "person.badge.key").font(.system(size: 15)).foregroundStyle(theme.accent).padding(.top, 2)
                    (Text(Copy.Review.oneThingTitle + " ").font(SFType.bodyStrong).foregroundColor(theme.text)
                        + Text(Copy.Review.oneThingBody).font(SFType.body).foregroundColor(theme.textSecondary))
                        .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 20)
                Button { s.showCommands = true } label: {
                    HStack(spacing: 6) { Image(systemName: "terminal").font(.system(size: 11)); Text(Copy.Review.showWhatWouldHappen) }
                }
                .buttonStyle(SFTextButtonStyle(color: theme.accent)).padding(.leading, -14).padding(.top, 4)
            }
        }
    }

    private func barRow(_ label: String, _ segs: [BarSegment]) -> some View {
        HStack(spacing: 16) {
            Text(label).font(SFType.label).foregroundStyle(theme.textSecondary).frame(width: 44, alignment: .leading)
            DiskBar(segments: segs, height: 30)
        }
    }

    private func row(_ a: String, _ b: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(a).font(SFType.body).foregroundStyle(theme.textSecondary).frame(width: 190, alignment: .leading)
                Text(b).font(SFType.bodyStrong.monospacedDigit()).foregroundStyle(theme.text)
                Spacer()
            }
            .frame(height: 38)
            if !last { Rectangle().fill(theme.hairline.opacity(0.6)).frame(height: 1) }
        }
    }
}

// MARK: 7. Approve the installer

struct ApproveScreen: View {
    @ObservedObject var s: Session
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHead(title: Copy.Approve.title, lead: Copy.Approve.lead)
            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(Copy.Approve.steps.enumerated()), id: \.offset) { i, t in
                        HStack(spacing: 14) {
                            Text("\(i + 1)").font(SFType.number(14)).foregroundStyle(theme.onAccent).frame(width: 26, height: 26).background(Circle().fill(theme.accent))
                            Text(t).font(SFType.body).foregroundStyle(theme.text)
                        }
                    }
                    if s.isDryRun {
                        HStack(spacing: 8) {
                            Spinner(size: 14, color: theme.caution)
                            Text(Copy.Approve.dryRunNote).font(SFType.label).foregroundStyle(theme.caution)
                        }
                        .padding(.top, 10)
                    }
                }
                Spacer(minLength: 0)
                LoginItemIllustration().frame(width: 330)
            }
        }
    }
}

/// Our own drawing of a Login Items row with its toggle turning on.
struct LoginItemIllustration: View {
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Copy.Approve.allowInBackground).font(SFType.labelStrong).foregroundStyle(theme.textSecondary)
            HStack(spacing: 12) {
                AppIconArt().frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.installer).font(SFType.labelStrong).foregroundStyle(theme.text)
                    Text(Copy.Approve.developer).font(SFType.caption).foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Capsule().fill(theme.accent).frame(width: 38, height: 22)
                    .overlay(Circle().fill(.white).padding(2).frame(width: 22), alignment: .trailing)
                    .shadow(color: theme.accent.opacity(0.5), radius: 6)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceRaised.opacity(0.8)))
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.panelFill)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1)))
        .accessibilityHidden(true)
    }
}
