import SwiftUI
import SFInstallKit

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var tint: LinearGradient? = nil
    var foreground: Color? = nil
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14.5, weight: .semibold))
            .foregroundStyle(foreground ?? theme.onAccent)
            .padding(.horizontal, 22)
            .frame(minWidth: 132, minHeight: 40)
            .background(
                Capsule(style: .continuous)
                    .fill(tint ?? theme.primaryGradient)
                    .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(theme.isDark ? 0.35 : 0.18), lineWidth: 0.75).blendMode(.overlay))
                    .overlay(Capsule(style: .continuous).fill(Color.black.opacity(configuration.isPressed ? 0.12 : 0)))
            )
            .shadow(color: theme.mint.opacity(enabled && theme.isDark ? 0.35 : 0.0), radius: 14, y: 4)
            .shadow(color: Color.black.opacity(theme.isDark ? 0.3 : 0.12), radius: 3, y: 1)
            .opacity(enabled ? 1 : 0.38)
            .saturation(enabled ? 1 : 0.2)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var destructive = false
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14.5, weight: .medium))
            .foregroundStyle(destructive ? theme.coral : theme.text)
            .padding(.horizontal, 20)
            .frame(minWidth: 104, minHeight: 40)
            .background(
                Capsule(style: .continuous)
                    .fill(theme.isDark ? Color.white.opacity(configuration.isPressed ? 0.13 : 0.075) : Color.white.opacity(configuration.isPressed ? 0.5 : 0.7))
                    .overlay(Capsule(style: .continuous).strokeBorder(destructive ? theme.coral.opacity(0.45) : theme.cardStroke, lineWidth: 1))
            )
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

struct LinkButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(theme.mint)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// Selectable pill (presets, choices).
struct Chip: View {
    var title: String
    var value: String? = nil
    var selected: Bool
    var action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let value {
                    Text(value).font(Typo.number(12.5, weight: .medium)).foregroundStyle(selected ? theme.text.opacity(0.85) : theme.textSecondary)
                }
            }
            .foregroundStyle(selected ? theme.text : theme.textSecondary)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? theme.mint.opacity(theme.isDark ? 0.18 : 0.14) : theme.card)
                    .overlay(Capsule(style: .continuous).strokeBorder(selected ? theme.mint.opacity(0.7) : theme.cardStroke, lineWidth: selected ? 1.2 : 1))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(value.map { "\(title), \($0)" } ?? title)
    }
}

// MARK: - Indicators

/// A spinner drawn in SwiftUI (ProgressView is AppKit-backed and doesn't render offscreen).
struct Spinner: View {
    var size: CGFloat = 16
    var lineWidth: CGFloat = 2
    var color: Color? = nil
    @Environment(\.theme) private var theme
    @Environment(\.backdropTime) private var fixed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let fixed {
                arc(angle: fixed * 360)
            } else {
                TimelineView(.animation(paused: reduceMotion)) { ctx in
                    arc(angle: reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("In progress")
    }

    private func arc(angle: Double) -> some View {
        ZStack {
            Circle().stroke((color ?? theme.mint).opacity(0.18), lineWidth: lineWidth)
            Circle().trim(from: 0, to: 0.28)
                .stroke(AngularGradient(colors: [(color ?? theme.mint).opacity(0), color ?? theme.mint], center: .center, startAngle: .degrees(0), endAngle: .degrees(100)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(angle))
        }
    }
}

struct ProgressTrack: View {
    var value: Double
    var height: CGFloat = 6
    var tint: LinearGradient? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            let w = max(height, geo.size.width * CGFloat(min(1, max(0, value))))
            ZStack(alignment: .leading) {
                Capsule().fill(theme.well)
                    .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 0.5))
                Capsule().fill(tint ?? theme.siliconForestGradient)
                    .frame(width: w)
                    .shadow(color: theme.mint.opacity(theme.isDark ? 0.6 : 0.25), radius: 6)
                // glowing head
                Circle().fill(Color.white.opacity(theme.isDark ? 0.9 : 0.8))
                    .frame(width: height * 0.6, height: height * 0.6)
                    .blur(radius: 1)
                    .offset(x: w - height * 0.8)
                    .opacity(value > 0.01 && value < 0.999 ? 1 : 0)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

/// Round status glyph for checklists and step lists.
struct StatusGlyph: View {
    enum Kind { case pass, warning, fail, info, running, pending, undone, skipped }
    var kind: Kind
    var size: CGFloat = 22
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            switch kind {
            case .running:
                Spinner(size: size * 0.82, lineWidth: 2)
            case .pending:
                Circle().strokeBorder(theme.textTertiary.opacity(0.55), lineWidth: 1.5).frame(width: size * 0.62, height: size * 0.62)
            default:
                Circle().fill(color.opacity(theme.isDark ? 0.17 : 0.14))
                Circle().strokeBorder(color.opacity(0.55), lineWidth: 1)
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(label)
    }

    private var color: Color {
        switch kind {
        case .pass: return theme.mint
        case .warning: return theme.gold
        case .fail: return theme.coral
        case .info: return theme.macOS
        case .undone: return theme.copper
        case .skipped: return theme.textTertiary
        default: return theme.textTertiary
        }
    }
    private var symbol: String {
        switch kind {
        case .pass: return "checkmark"
        case .warning: return "exclamationmark"
        case .fail: return "xmark"
        case .info: return "info"
        case .undone: return "arrow.uturn.backward"
        case .skipped: return "minus"
        default: return ""
        }
    }
    private var label: String {
        switch kind {
        case .pass: return "Passed"
        case .warning: return "Warning"
        case .fail: return "Failed"
        case .info: return "Note"
        case .running: return "In progress"
        case .pending: return "Waiting"
        case .undone: return "Undone"
        case .skipped: return "Nothing to undo"
        }
    }
}

/// The unmistakable-but-elegant mode badge.
struct ModeBadge: View {
    var mode: RunMode
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().fill(tone.opacity(0.18)).frame(width: 22, height: 22)
                Image(systemName: mode == .dryRun ? "testtube.2" : "eye")
                    .font(.system(size: 10.5, weight: .bold)).foregroundStyle(tone)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(mode == .dryRun ? "DRY RUN" : "READ-ONLY")
                    .font(.system(size: 10.5, weight: .bold)).tracking(1.3).foregroundStyle(tone)
                Text(mode == .dryRun ? "Simulated disk · nothing is written" : "Analysing this Mac · nothing is written")
                    .font(.system(size: 10.5, weight: .medium)).foregroundStyle(theme.textSecondary)
            }
        }
        .padding(.leading, 6).padding(.trailing, 14).padding(.vertical, 5)
        .background(
            Capsule(style: .continuous).fill(theme.isDark ? Color.black.opacity(0.35) : Color.white.opacity(0.6))
                .overlay(
                    // fine diagonal hatching: the "this isn't real" signal, kept quiet
                    Hatch(spacing: 5).stroke(tone.opacity(0.13), lineWidth: 1).clipShape(Capsule(style: .continuous))
                )
                .overlay(Capsule(style: .continuous).strokeBorder(tone.opacity(0.55), lineWidth: 1))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(mode == .dryRun ? "Dry run. The disk is simulated; nothing is written." : "Read-only analysis. Nothing is written.")
    }

    private var tone: Color { mode == .dryRun ? theme.copper : theme.macOS }
}

/// Diagonal hatch lines filling a rect.
struct Hatch: Shape {
    var spacing: CGFloat = 6
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return p
    }
}

/// Top-of-screen step indicator for the install flow.
struct FlowIndicator: View {
    var index: Int
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(Screen.flowTitles.enumerated()), id: \.offset) { i, title in
                HStack(spacing: 7) {
                    ZStack {
                        Circle().fill(i < index ? theme.mint : (i == index ? theme.mint.opacity(0.22) : Color.clear))
                        Circle().strokeBorder(i <= index ? theme.mint : theme.textTertiary.opacity(0.5), lineWidth: 1.2)
                        if i < index {
                            Image(systemName: "checkmark").font(.system(size: 7.5, weight: .heavy)).foregroundStyle(theme.onAccent)
                        } else if i == index {
                            Circle().fill(theme.mint).frame(width: 5, height: 5)
                        }
                    }
                    .frame(width: 15, height: 15)
                    Text(title)
                        .font(.system(size: 12, weight: i == index ? .semibold : .medium))
                        .foregroundStyle(i == index ? theme.text : (i < index ? theme.textSecondary : theme.textTertiary))
                }
                if i < Screen.flowTitles.count - 1 {
                    Capsule().fill(i < index ? theme.mint.opacity(0.6) : theme.hairline).frame(width: 18, height: 1.5)
                }
            }
        }
        .padding(.horizontal, 16).frame(height: 34)
        .background(Capsule(style: .continuous).fill(theme.isDark ? Color.black.opacity(0.28) : Color.white.opacity(0.5))
            .overlay(Capsule(style: .continuous).strokeBorder(theme.hairline, lineWidth: 1)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(index + 1) of \(Screen.flowTitles.count): \(Screen.flowTitles[min(index, Screen.flowTitles.count - 1)])")
    }
}

// MARK: - Text field

/// A text field with SiliconForest chrome. In snapshots the editable NSTextField is replaced by the
/// same text and caret drawn in SwiftUI.
struct SFTextField: View {
    var title: String
    @Binding var text: String
    var error: String?
    var focused: Bool = false
    @Environment(\.theme) private var theme
    @Environment(\.isSnapshot) private var isSnapshot
    @FocusState private var hasFocus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: "character.cursor.ibeam").font(.system(size: 13, weight: .medium)).foregroundStyle(theme.textTertiary)
                if isSnapshot {
                    HStack(spacing: 1) {
                        Text(text).font(.system(size: 16, weight: .medium)).foregroundStyle(theme.text)
                        if focused { Rectangle().fill(theme.mint).frame(width: 1.6, height: 19) }
                        Spacer(minLength: 0)
                    }
                } else {
                    TextField(title, text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(theme.text)
                        .focused($hasFocus)
                        .accessibilityLabel(title)
                }
                Text("\(text.count)/28").font(Typo.number(11.5, weight: .medium)).foregroundStyle(theme.textTertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.well)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(error != nil ? theme.coral.opacity(0.8) : ((focused || hasFocus) ? theme.mint.opacity(0.85) : theme.cardStroke), lineWidth: (focused || hasFocus) ? 1.5 : 1))
            )
            .shadow(color: (focused || hasFocus) ? theme.mint.opacity(0.25) : .clear, radius: 8)
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill").font(Typo.caption).foregroundStyle(theme.coral)
            }
        }
    }
}

// MARK: - Layout helpers

/// Icon in a softly lit disc, used at the top of panel screens.
struct HeaderIcon: View {
    var symbol: String
    var tint: Color? = nil
    var size: CGFloat = 58
    @Environment(\.theme) private var theme

    var body: some View {
        let c = tint ?? theme.mint
        ZStack {
            Circle().fill(RadialGradient(colors: [c.opacity(theme.isDark ? 0.32 : 0.22), c.opacity(0.04)], center: .center, startRadius: 0, endRadius: size * 0.6))
            Circle().strokeBorder(LinearGradient(colors: [c.opacity(0.7), c.opacity(0.1)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            Image(systemName: symbol).font(.system(size: size * 0.4, weight: .medium)).foregroundStyle(c)
        }
        .frame(width: size, height: size)
        .shadow(color: c.opacity(theme.isDark ? 0.35 : 0.1), radius: 16)
        .accessibilityHidden(true)
    }
}

struct ScreenHeader: View {
    var symbol: String
    var title: String
    var subtitle: String
    var tint: Color? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            HeaderIcon(symbol: symbol, tint: tint, size: 56)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(Typo.display).foregroundStyle(theme.text).accessibilityAddTraits(.isHeader)
                Text(subtitle).font(Typo.subtitle).foregroundStyle(theme.textSecondary).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

struct KeyCap: View {
    var text: String
    @Environment(\.theme) private var theme
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 19)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(theme.card)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: 1)))
    }
}


/// An SF Symbol, or the SiliconForest mark for `"sf.mark"` (SF Symbols' "tree" is a broadleaf, not ours).
struct Glyph: View {
    var symbol: String
    var size: CGFloat
    var color: Color
    var body: some View {
        if symbol == "sf.mark" {
            BrandMark(tiers: AnyShapeStyle(color), traces: color).frame(height: size * 1.15)
        } else {
            Image(systemName: symbol).font(.system(size: size, weight: .medium)).foregroundStyle(color)
        }
    }
}
