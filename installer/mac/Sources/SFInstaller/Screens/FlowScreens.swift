import SwiftUI
import SFInstallKit

// MARK: - Welcome

struct WelcomeScreen: View {
    var model: InstallerModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            BrandMark.mint(theme)
                .frame(height: 128)
                .padding(.bottom, 34)
            Text("SiliconForest")
                .font(.system(size: 66, weight: .light))
                .tracking(-0.6)
                .foregroundStyle(theme.text)
                .accessibilityAddTraits(.isHeader)
            Text("Darwin, grown for Apple silicon.")
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(theme.textSecondary)
                .padding(.top, 6)
            Button { model.go(.compatibility) } label: {
                HStack(spacing: 8) {
                    Text("Get Started")
                    Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold))
                }
                .frame(minWidth: 170)
            }
            .buttonStyle(PrimaryButtonStyle())
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 46)
            .disabled(model.snapshot == nil)

            if !model.existingInstalls.isEmpty {
                Button {
                    model.selectedInstall = model.existingInstalls.first
                    model.go(.manage)
                } label: {
                    Label("Manage the existing installation", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(LinkButtonStyle())
                .padding(.top, 20)
            }

            Text(deviceLine)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 14).frame(height: 26)
                .background(Capsule().fill(theme.isDark ? Color.black.opacity(0.35) : Color.white.opacity(0.6)))
                .padding(.top, model.existingInstalls.isEmpty ? 30 : 18)
        }
        .padding(.bottom, 40)
    }

    private var deviceLine: String {
        if let p = model.profile, model.checks.first?.status != .fail { return "Installer 0.9  ·  for \(p.marketingName)" }
        if let f = model.facts { return "Installer 0.9  ·  this Mac: \(f.chipName ?? f.hwModel ?? "unknown")" }
        return "Installer 0.9"
    }
}

// MARK: - Compatibility

struct CompatibilityScreen: View {
    var model: InstallerModel
    @Environment(\.theme) private var theme

    var body: some View {
        PanelScaffold(symbol: "checkmark.shield", title: "Checking your Mac",
                      subtitle: "SiliconForest makes sure this Mac is ready. Nothing is changed.") {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    ForEach(Array(model.checks.enumerated()), id: \.element.id) { i, check in
                        CheckRow(check: check, state: i < model.checksRevealed ? .shown : (i == model.checksRevealed ? .checking : .waiting))
                        if i < model.checks.count - 1 { Rectangle().fill(theme.hairline).frame(height: 1).padding(.leading, 58) }
                    }
                }
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: 1)))
                verdict
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(model.checksRevealed >= model.checks.count ? 1 : 0)
            }
        } footer: {
            Button("Back") { model.back() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut("[", modifiers: .command)
            Spacer()
            if model.checksRevealed >= model.checks.count && !model.canContinueFromChecks {
                Button("Check Again") { model.runChecks() }.buttonStyle(SecondaryButtonStyle())
            }
            Button("Continue") { model.go(.beforeYouBegin) }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canContinueFromChecks)
        }
    }

    @ViewBuilder private var verdict: some View {
        if model.canContinueFromChecks {
            Label {
                Text("This Mac is ready for SiliconForest.").font(Typo.headline).foregroundStyle(theme.text)
            } icon: {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(theme.mint)
            }
        } else if model.checks.contains(where: { $0.status == .fail }) {
            Label {
                Text(model.mode == .readOnly ? "Read-only analysis: this Mac can’t take SiliconForest yet. The checks show why." : "Fix the items marked above, then check again.")
                    .font(Typo.headline).foregroundStyle(theme.text)
            } icon: {
                Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(theme.coral)
            }
        }
    }
}

struct CheckRow: View {
    enum RowState { case waiting, checking, shown }
    var check: CompatibilityCheck
    var state: RowState
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 16) {
            Group {
                switch state {
                case .waiting: StatusGlyph(kind: .pending, size: 26)
                case .checking: StatusGlyph(kind: .running, size: 26)
                case .shown: StatusGlyph(kind: glyph, size: 26)
                }
            }
            .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(state == .shown ? check.title : waitingTitle)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(state == .waiting ? theme.textTertiary : theme.text)
                Text(state == .shown ? check.detail : " ")
                    .font(Typo.callout).foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            if state == .shown {
                Text(check.value)
                    .font(Typo.number(13, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(Capsule().fill(theme.well))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .accessibilityElement(children: .combine)
    }

    private var waitingTitle: String {
        switch check.kind {
        case .model: return "Mac model"
        case .macOS: return "macOS version"
        case .fileVault: return "FileVault"
        case .freeSpace: return "Free space"
        case .startupSecurity: return "Startup security"
        case .power: return "Power"
        case .existingInstall: return "Existing installations"
        }
    }

    private var glyph: StatusGlyph.Kind {
        switch check.status {
        case .pass: return .pass
        case .warning: return .warning
        case .fail: return .fail
        case .info: return .info
        }
    }
}

// MARK: - Before you begin

struct BeforeYouBeginScreen: View {
    @Bindable var model: InstallerModel
    @Environment(\.theme) private var theme

    var body: some View {
        PanelScaffold(symbol: "list.bullet.clipboard", title: "Before you begin",
                      subtitle: "Three things to know. It takes about fifteen minutes, then two more in recoveryOS.") {
            VStack(spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    InfoCard(number: "1", symbol: "clock.arrow.circlepath", tint: theme.macOS, title: "Back up your Mac",
                             text: "Use Time Machine in System Settings → General → Time Machine. Resizing keeps your files, and a backup makes that certain.")
                    InfoCard(number: "2", symbol: "internaldrive", tint: theme.mint, title: "What the installer does",
                             bullets: ["Shrinks macOS. Your files stay put.", "Adds three partitions for SiliconForest", "Copies Wi-Fi firmware from this Mac", "Erases nothing"])
                    InfoCard(number: "3", symbol: "power", tint: theme.copper, title: "Finish in recoveryOS",
                             text: "At the end you shut down, hold the power button, and confirm SiliconForest’s startup security. You’ll need your password.")
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 28) {
                    fact("clock", "About 15 minutes", "plus 2 in recoveryOS")
                    fact("bolt", "Charger connected", "the whole time")
                    fact("wifi", "Internet connection", "downloads about 3.5 GB")
                    fact("person.badge.key", "An administrator", "password for recoveryOS")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)

                Button { withAnimation(.snappy) { model.backupConfirmed.toggle() } } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(model.backupConfirmed ? theme.mint : Color.clear)
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(model.backupConfirmed ? theme.mint : theme.textTertiary, lineWidth: 1.5))
                            if model.backupConfirmed {
                                Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(theme.onAccent)
                            }
                        }
                        .frame(width: 20, height: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("I have a current backup of this Mac").font(Typo.headline).foregroundStyle(theme.text)
                            Text("Or I accept that I could lose data if something goes wrong.").font(Typo.callout).foregroundStyle(theme.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(model.backupConfirmed ? theme.mint.opacity(0.08) : theme.card)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(model.backupConfirmed ? theme.mint.opacity(0.5) : theme.cardStroke, lineWidth: 1)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.backupConfirmed ? [.isSelected] : [])
            }
        } footer: {
            Button("Back") { model.back() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut("[", modifiers: .command)
            Spacer()
            Button("Continue") { model.go(.disk) }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!model.backupConfirmed)
        }
    }

    private func fact(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(theme.mint).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.text)
                Text(detail).font(.system(size: 12)).foregroundStyle(theme.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct InfoCard: View {
    var number: String
    var symbol: String
    var tint: Color
    var title: String
    var text: String? = nil
    var bullets: [String] = []
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HeaderIcon(symbol: symbol, tint: tint, size: 42)
                Spacer()
                Text(number).font(.system(size: 30, weight: .ultraLight)).foregroundStyle(theme.textTertiary)
            }
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.text)
            if let text {
                Text(text).font(Typo.callout).foregroundStyle(theme.textSecondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
            if !bullets.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(bullets, id: \.self) { b in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(tint).frame(width: 5, height: 5).offset(y: -2)
                            Text(b).font(Typo.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.card)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: 1)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Disk

struct DiskScreen: View {
    @Bindable var model: InstallerModel
    var showTag = false
    @Environment(\.theme) private var theme

    var body: some View {
        PanelScaffold(symbol: "externaldrive.badge.plus", title: "Make room for SiliconForest",
                      subtitle: "Drag the divider to share the disk. macOS keeps every file and at least \(Bytes.format(model.profile?.partitioning.macOSMinFreeBytes ?? 0)) free.") {
            if let disk = model.disk, let c = model.constraints, let profile = model.profile {
                let mac = c.macOSSize(for: model.siliconForestSize)
                VStack(spacing: 0) {
                    HStack(alignment: .bottom) {
                        Readout(dot: theme.macOS, title: "macOS", value: mac,
                                caption: "\(Bytes.format(c.macOSUsed)) used · \(Bytes.format(max(0, mac - c.macOSUsed))) free after resizing", alignment: .leading)
                        Spacer()
                        Readout(dot: theme.mint, title: "SiliconForest", value: model.siliconForestSize,
                                caption: "System \(Bytes.format(model.siliconForestSize - profile.partitioning.stubContainerBytes - profile.partitioning.bootPartition.bytes)) · Boot \(Bytes.format(profile.partitioning.bootPartition.bytes)) · Startup \(Bytes.format(profile.partitioning.stubContainerBytes))",
                                alignment: .trailing)
                    }
                    .padding(.bottom, 54)

                    PartitionBar(disk: disk, constraints: c, size: $model.siliconForestSize,
                                 stub: profile.partitioning.stubContainerBytes, boot: profile.partitioning.bootPartition.bytes,
                                 showTag: showTag)

                    RangeRuler(disk: disk, constraints: c)
                        .padding(.top, 14)

                    HStack(spacing: 10) {
                        ForEach(c.presets) { p in
                            Chip(title: p.title, value: Bytes.format(p.size), selected: p.size == model.siliconForestSize) {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { model.siliconForestSize = p.size }
                            }
                        }
                        Spacer()
                        Legend()
                    }
                    .padding(.top, 20)

                    PartitionBreakdown(profile: profile, size: model.siliconForestSize)
                        .padding(.top, 16)
                }
                .padding(.top, 4)
            }
        } footer: {
            Button("Back") { model.back() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut("[", modifiers: .command)
            Spacer()
            Button("Continue") { model.go(.options) }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!(model.constraints?.isFeasible ?? false))
        }
    }
}

struct Readout: View {
    var dot: Color
    var title: String
    var value: Int64
    var caption: String
    var alignment: HorizontalAlignment
    @Environment(\.theme) private var theme

    var body: some View {
        let parts = Bytes.split(value)
        VStack(alignment: alignment, spacing: 4) {
            HStack(spacing: 7) {
                Circle().fill(dot).frame(width: 9, height: 9).shadow(color: dot.opacity(0.7), radius: 4)
                Text(title.uppercased()).font(.system(size: 11.5, weight: .bold)).tracking(1.2).foregroundStyle(theme.textSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(parts.number).font(.system(size: 54, weight: .light).monospacedDigit()).foregroundStyle(theme.text)
                    .contentTransition(.numericText(value: Double(value)))
                Text(parts.unit).font(.system(size: 20, weight: .regular)).foregroundStyle(theme.textSecondary)
            }
            Text(caption).font(Typo.callout).foregroundStyle(theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Under the bar: where the divider may go, and the disk's scale.
struct RangeRuler: View {
    var disk: PhysicalDisk
    var constraints: SizingConstraints
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            let segs = PartitionBar(disk: disk, constraints: constraints, size: .constant(constraints.minimum)).segments
            let layout = BarLayout(segments: segs, width: geo.size.width, poolIDs: ["macos", "sf"])
            let pool = layout.poolRange
            let span = pool.upperBound - pool.lowerBound
            let x = { (sf: Int64) -> CGFloat in pool.lowerBound + span * CGFloat(Double(constraints.pool - sf) / Double(constraints.pool)) }
            let lo = x(constraints.maximum), hi = x(constraints.minimum)
            ZStack(alignment: .topLeading) {
                // allowed range
                Capsule().fill(theme.mint.opacity(0.5)).frame(width: max(2, hi - lo), height: 2).offset(x: lo, y: 5)
                tick.offset(x: lo - 1)
                tick.offset(x: hi - 1)
                Text("Largest SiliconForest").font(Typo.micro).foregroundStyle(theme.textTertiary).fixedSize()
                    .offset(x: lo - 2, y: 16)
                Text("Smallest").font(Typo.micro).foregroundStyle(theme.textTertiary).fixedSize()
                    .frame(width: 120, alignment: .trailing)
                    .offset(x: hi - 118, y: 16)
                Text("\(disk.mediaName.replacingOccurrences(of: "APPLE SSD ", with: "Internal SSD "))  ·  \(Bytes.format(disk.size))")
                    .font(Typo.micro).foregroundStyle(theme.textTertiary).fixedSize()
                    .offset(x: 0, y: 16)
                    .opacity(lo > 240 ? 1 : 0)
            }
        }
        .frame(height: 30)
        .accessibilityHidden(true)
    }

    private var tick: some View {
        Capsule().fill(theme.mint).frame(width: 2, height: 12)
    }
}

struct Legend: View {
    @Environment(\.theme) private var theme
    var body: some View {
        HStack(spacing: 14) {
            item(AnyView(RoundedRectangle(cornerRadius: 3).fill(theme.macOSGradient)), "Used")
            item(AnyView(ZStack { RoundedRectangle(cornerRadius: 3).fill(theme.macOS.opacity(0.32)); Hatch(spacing: 3).stroke(theme.macOS.opacity(0.6), lineWidth: 1).clipShape(RoundedRectangle(cornerRadius: 3)) }), "Kept free")
            item(AnyView(RoundedRectangle(cornerRadius: 3).fill(theme.macOS.opacity(0.22))), "Free")
            item(AnyView(RoundedRectangle(cornerRadius: 3).fill(theme.system.opacity(0.6))), "Apple")
        }
    }
    private func item(_ swatch: AnyView, _ label: String) -> some View {
        HStack(spacing: 6) {
            swatch.frame(width: 12, height: 12)
            Text(label).font(Typo.caption).foregroundStyle(theme.textSecondary)
        }
    }
}

// MARK: - Options

struct OptionsScreen: View {
    @Bindable var model: InstallerModel
    var nameFocused = false
    @Environment(\.theme) private var theme

    var body: some View {
        PanelScaffold(symbol: "slider.horizontal.3", title: "Name and startup",
                      subtitle: "How SiliconForest appears when you choose a system at startup.") {
            HStack(alignment: .top, spacing: 36) {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("Name")
                        SFTextField(title: "Install name", text: $model.installName, error: model.nameError, focused: nameFocused)
                        Text("Shown in the startup picker and in Startup Disk settings.").font(Typo.callout).foregroundStyle(theme.textSecondary)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("Default system")
                        HStack(spacing: 12) {
                            BootCard(title: "macOS", subtitle: "Recommended. SiliconForest when you choose it.", symbol: "laptopcomputer",
                                     selected: model.defaultBoot == .macOS) { withAnimation(.snappy) { model.defaultBoot = .macOS } }
                            BootCard(title: model.installName.isEmpty ? "SiliconForest" : model.installName, subtitle: "Start SiliconForest unless you choose macOS.", symbol: nil,
                                     selected: model.defaultBoot == .siliconForest) { withAnimation(.snappy) { model.defaultBoot = .siliconForest } }
                        }
                        Text("Either way, hold the power button at startup to pick a system.").font(Typo.callout).foregroundStyle(theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)

                StartupPickerPreview(name: model.installName.isEmpty ? "SiliconForest" : model.installName, defaultBoot: model.defaultBoot)
                    .frame(width: 330)
            }
        } footer: {
            Button("Back") { model.back() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut("[", modifiers: .command)
            Spacer()
            Button("Continue") { model.go(.review) }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(model.nameError != nil)
        }
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(theme.textTertiary)
    }
}

struct BootCard: View {
    var title: String
    var subtitle: String
    var symbol: String?
    var selected: Bool
    var action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Group {
                        if let symbol {
                            Image(systemName: symbol).font(.system(size: 20, weight: .regular)).foregroundStyle(theme.macOS)
                        } else {
                            BrandMark.mint(theme, glow: false).frame(height: 22)
                        }
                    }
                    .frame(height: 24)
                    Spacer()
                    ZStack {
                        Circle().strokeBorder(selected ? theme.mint : theme.textTertiary, lineWidth: 1.5)
                        if selected { Circle().fill(theme.mint).padding(4) }
                    }
                    .frame(width: 18, height: 18)
                }
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.text).lineLimit(1)
                Text(subtitle).font(Typo.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(selected ? theme.mint.opacity(0.09) : theme.card)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? theme.mint.opacity(0.75) : theme.cardStroke, lineWidth: selected ? 1.5 : 1)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityLabel("\(title) as the default system")
    }
}

/// A schematic of the startup picker (our own drawing, not Apple's artwork).
struct StartupPickerPreview: View {
    var name: String
    var defaultBoot: BootChoice
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 18) {
            Text("At startup").font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(Color.white.opacity(0.5))
            HStack(spacing: 26) {
                volume(title: "Macintosh HD", isDefault: defaultBoot == .macOS) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0x8AA6CC), Color(hex: 0x4E6B93)], startPoint: .top, endPoint: .bottom))
                        .overlay(Image(systemName: "internaldrive").font(.system(size: 26, weight: .light)).foregroundStyle(.white))
                }
                volume(title: name, isDefault: defaultBoot == .siliconForest) {
                    AppIconArt()
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "gearshape").font(.system(size: 10))
                Text("Options").font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Color.white.opacity(0.5))
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x0B1512), Color(hex: 0x030706)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        )
        .shadow(color: theme.shadow.opacity(0.6), radius: 18, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview: the startup picker shows Macintosh HD and \(name). Default: \(defaultBoot == .macOS ? "Macintosh HD" : name).")
    }

    private func volume<Icon: View>(title: String, isDefault: Bool, @ViewBuilder icon: () -> Icon) -> some View {
        VStack(spacing: 10) {
            icon()
                .frame(width: 74, height: 74)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(isDefault ? 0.12 : 0))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(isDefault ? 0.3 : 0), lineWidth: 1)))
            Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1).frame(maxWidth: 110)
            Text(isDefault ? "Default" : " ").font(.system(size: 10.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.55))
        }
    }
}
