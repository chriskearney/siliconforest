import SwiftUI
import SFInstallKit
import SFCopy

// MARK: - Buttons (VISUAL-DESIGN §5)

/// Primary: 44 pt tall, 12 pt radius, accent fill, on.accent text. One per screen.
public struct SFPrimaryButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var enabled
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SFType.button)
            .foregroundStyle(theme.onAccent)
            .padding(.horizontal, 22)
            .frame(minWidth: 120, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.accent)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [Color.white.opacity(0.16), .clear], startPoint: .top, endPoint: .center)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(configuration.isPressed ? 0.12 : 0)))
            )
            .shadow(color: theme.accent.opacity(enabled ? (theme.isDark ? 0.35 : 0.2) : 0), radius: 14, y: 4)
            .opacity(enabled ? 1 : 0.4)
            .saturation(enabled ? 1 : 0.3)
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Secondary: text only.
public struct SFTextButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var enabled
    var color: Color?
    public init(color: Color? = nil) { self.color = color }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SFType.button.weight(.medium))
            .foregroundStyle(color ?? theme.text)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .opacity(configuration.isPressed ? 0.55 : (enabled ? 1 : 0.35))
            .contentShape(Rectangle())
    }
}

/// Destructive: status.critical outline, filled only when armed.
public struct SFDestructiveButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var enabled
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SFType.button)
            .foregroundStyle(enabled ? (theme.isDark ? Color(hex: 0x1A0D09) : .white) : theme.critical)
            .padding(.horizontal, 22).frame(minWidth: 120, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(enabled ? theme.critical : .clear))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.critical.opacity(enabled ? 0 : 0.7), lineWidth: 1.2))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// A quiet bordered button for secondary actions that need more presence than text (Practice…).
public struct SFQuietButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SFType.label)
            .foregroundStyle(theme.text)
            .padding(.horizontal, 14).frame(minHeight: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.surfaceRaised.opacity(configuration.isPressed ? 1 : 0.7))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1)))
            .contentShape(Rectangle())
    }
}

// MARK: - Vias: circuit as structure

/// A plated via: a ring around a hole. `fill` 0…1 fills the hole (step dots, checklist rows).
public struct Via: View {
    var size: CGFloat
    var ring: Color
    var fill: Double
    var hole: Color
    var glow: Bool
    @Environment(\.theme) private var theme
    public init(size: CGFloat = 14, ring: Color, fill: Double = 0, hole: Color? = nil, glow: Bool = false) {
        self.size = size; self.ring = ring; self.fill = fill; self.hole = hole ?? .clear; self.glow = glow
    }
    public var body: some View {
        ZStack {
            Circle().fill(hole)
            Circle().strokeBorder(ring, lineWidth: max(1.5, size * 0.14))
            Circle().fill(ring).padding(size * 0.22).scaleEffect(fill).opacity(fill > 0 ? 1 : 0)
        }
        .frame(width: size, height: size)
        .shadow(color: glow ? ring.opacity(0.7) : .clear, radius: glow ? size * 0.6 : 0)
    }
}

/// Step dots: Check · Prepare · Space · Review · Install · Recovery · Finish. Upcoming is an empty
/// ring, current a filled via with a soft glow, done a filled via; a hairline trace joins them.
public struct StepDots: View {
    var index: Int
    @Environment(\.theme) private var theme
    public init(index: Int) { self.index = index }
    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Copy.stepDots.enumerated()), id: \.offset) { i, _ in
                Via(size: i == index ? 13 : 10, ring: i <= index ? theme.accent : theme.textTertiary, fill: i <= index ? 1 : 0,
                    hole: theme.isDark ? Color.black.opacity(0.4) : Color.white.opacity(0.6), glow: i == index)
                if i < Copy.stepDots.count - 1 {
                    Rectangle().fill(i < index ? theme.accent.opacity(0.7) : theme.hairline).frame(width: 22, height: 1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(index + 1) of \(Copy.stepDots.count): \(Copy.stepDots[min(index, Copy.stepDots.count - 1)])")
    }
}

// MARK: - Rows

public enum RowState: Equatable, Sendable { case waiting, working, pass, warning, fail, info, undone, skipped }

/// A via that fills, then a check draws through it (VISUAL §5).
public struct RowGlyph: View {
    var state: RowState
    var size: CGFloat
    @Environment(\.theme) private var theme
    public init(_ state: RowState, size: CGFloat = 22) { self.state = state; self.size = size }
    public var body: some View {
        ZStack {
            switch state {
            case .waiting:
                Via(size: size * 0.62, ring: theme.textTertiary.opacity(0.7))
            case .working:
                Spinner(size: size * 0.8, color: theme.accent)
            default:
                Circle().fill(color.opacity(theme.isDark ? 0.18 : 0.14))
                Circle().strokeBorder(color, lineWidth: 1.4)
                Image(systemName: symbol).font(.system(size: size * 0.46, weight: .bold)).foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(label)
    }
    var color: Color {
        switch state {
        case .pass: return theme.ok
        case .warning: return theme.caution
        case .fail: return theme.critical
        case .info: return theme.textSecondary
        case .undone: return theme.accent
        default: return theme.textTertiary
        }
    }
    var symbol: String {
        switch state {
        case .pass: return "checkmark"
        case .warning: return "exclamationmark"
        case .fail: return "xmark"
        case .info: return "info"
        case .undone: return "arrow.uturn.backward"
        default: return "minus"
        }
    }
    var label: String {
        switch state {
        case .waiting: return "Waiting"
        case .working: return "In progress"
        case .pass: return "Passed"
        case .warning: return "Warning"
        case .fail: return "Needs attention"
        case .info: return "Note"
        case .undone: return "Undone"
        case .skipped: return "Nothing to undo"
        }
    }
}

/// One line of a phase list: glyph, title, trailing detail.
public struct PhaseRow: View {
    var title: String
    var state: RowState
    var trailing: String?
    var emphasized: Bool
    @Environment(\.theme) private var theme
    public init(_ title: String, state: RowState, trailing: String? = nil, emphasized: Bool = false) {
        self.title = title; self.state = state; self.trailing = trailing; self.emphasized = emphasized
    }
    public var body: some View {
        HStack(spacing: 14) {
            RowGlyph(state, size: 22)
            Text(title)
                .font(state == .working || emphasized ? SFType.bodyStrong : SFType.body)
                .foregroundStyle(state == .waiting || state == .skipped ? theme.textTertiary : theme.text)
            Spacer(minLength: 16)
            if let trailing {
                Text(trailing).font(SFType.number(13, .medium))
                    .foregroundStyle(state == .working ? theme.accent : theme.textSecondary)
            }
        }
        .frame(height: 38)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Panels and small pieces

/// Dense content panel: surface.base at 88% opacity, 1 px hairline, 16 pt radius.
public struct Panel<Content: View>: View {
    var padding: CGFloat
    @ViewBuilder var content: Content
    @Environment(\.theme) private var theme
    public init(padding: CGFloat = 20, @ViewBuilder content: () -> Content) { self.padding = padding; self.content = content() }
    public var body: some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.panelFill)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1)))
            .shadow(color: theme.shadow.opacity(0.5), radius: 24, y: 10)
    }
}

/// The unmistakable-but-elegant dry-run badge.
public struct ModeBadge: View {
    var dryRun: Bool
    @Environment(\.theme) private var theme
    public init(dryRun: Bool) { self.dryRun = dryRun }
    public var body: some View {
        let tone = dryRun ? theme.caution : theme.textSecondary
        HStack(spacing: 9) {
            Image(systemName: dryRun ? "testtube.2" : "eye").font(.system(size: 11, weight: .semibold)).foregroundStyle(tone)
            VStack(alignment: .leading, spacing: 0) {
                Text((dryRun ? Copy.Common.dryRun : Copy.Common.readOnly).uppercased()).font(SFType.micro).tracking(1.4).foregroundStyle(tone)
                Text(dryRun ? Copy.Common.dryRunDetail : Copy.Common.readOnlyDetail).font(SFType.caption).foregroundStyle(theme.textSecondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(
            Capsule(style: .continuous).fill(theme.isDark ? Color.black.opacity(0.35) : Color.white.opacity(0.6))
                .overlay(Hatch(spacing: 5).stroke(tone.opacity(0.14), lineWidth: 1).clipShape(Capsule(style: .continuous)))
                .overlay(Capsule(style: .continuous).strokeBorder(tone.opacity(0.55), lineWidth: 1))
        )
        .accessibilityElement(children: .combine)
    }
}

public struct Hatch: Shape {
    var spacing: CGFloat
    public init(spacing: CGFloat = 6) { self.spacing = spacing }
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            p.move(to: CGPoint(x: x, y: rect.maxY)); p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY)); x += spacing
        }
        return p
    }
}

/// A spinner drawn in SwiftUI (ProgressView is AppKit-backed and doesn't render offscreen).
public struct Spinner: View {
    var size: CGFloat
    var color: Color
    @Environment(\.backdropTime) private var fixed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(size: CGFloat = 16, color: Color) { self.size = size; self.color = color }
    public var body: some View {
        Group {
            if let fixed { arc(fixed * 360) } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { ctx in
                    arc(reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360)
                }
            }
        }
        .frame(width: size, height: size)
    }
    private func arc(_ angle: Double) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: 2)
            Circle().trim(from: 0, to: 0.28).stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(angle))
        }
    }
}

public struct ProgressLine: View {
    var value: Double
    var height: CGFloat
    @Environment(\.theme) private var theme
    public init(value: Double, height: CGFloat = 4) { self.value = value; self.height = height }
    public var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.hairline.opacity(0.8))
                Capsule().fill(theme.accent).frame(width: max(height, g.size.width * CGFloat(min(1, max(0, value)))))
                    .shadow(color: theme.accent.opacity(0.5), radius: 4)
            }
        }
        .frame(height: height)
        .accessibilityElement().accessibilityLabel("Progress").accessibilityValue("\(Int(value * 100)) percent")
    }
}

public struct SectionLabel: View {
    var text: String
    @Environment(\.theme) private var theme
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text.uppercased()).font(SFType.micro).tracking(1.2).foregroundStyle(theme.textTertiary)
    }
}

/// A checkbox row (SwiftUI-drawn, so it renders offscreen).
public struct CheckboxRow: View {
    var title: String
    var subtitle: String?
    @Binding var isOn: Bool
    @Environment(\.theme) private var theme
    public init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) { self.title = title; self.subtitle = subtitle; self._isOn = isOn }
    public var body: some View {
        Button { isOn.toggle() } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(isOn ? theme.accent : .clear)
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(isOn ? theme.accent : theme.textSecondary, lineWidth: 1.5))
                    if isOn { Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(theme.onAccent) }
                }
                .frame(width: 20, height: 20).padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(SFType.bodyStrong).foregroundStyle(theme.text)
                    if let subtitle { Text(subtitle).font(SFType.label).foregroundStyle(theme.textSecondary) }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

public struct RadioRow: View {
    var title: String
    var subtitle: String?
    var selected: Bool
    var action: () -> Void
    @Environment(\.theme) private var theme
    public init(_ title: String, subtitle: String? = nil, selected: Bool, action: @escaping () -> Void) {
        self.title = title; self.subtitle = subtitle; self.selected = selected; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Via(size: 18, ring: selected ? theme.accent : theme.textSecondary, fill: selected ? 1 : 0).padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(SFType.body).foregroundStyle(theme.text)
                    if let subtitle { Text(subtitle).font(SFType.label).foregroundStyle(theme.textSecondary) }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Disclosure line: chevron + title.
public struct DisclosureLine: View {
    var title: String
    var expanded: Bool
    var action: () -> Void
    @Environment(\.theme) private var theme
    public init(_ title: String, expanded: Bool, action: @escaping () -> Void) { self.title = title; self.expanded = expanded; self.action = action }
    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).rotationEffect(.degrees(expanded ? 90 : 0))
                Text(title).font(SFType.label)
            }
            .foregroundStyle(theme.textSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
    }
}

/// A text field with SiliconForest chrome. In snapshots the NSTextField is replaced by the same text
/// and caret drawn in SwiftUI.
public struct SFTextField: View {
    var placeholder: String
    @Binding var text: String
    var error: String?
    var showsCaret: Bool
    var monospacedDigits: Bool
    var trailing: String?
    var width: CGFloat?
    @Environment(\.theme) private var theme
    @Environment(\.isSnapshot) private var isSnapshot
    public init(_ placeholder: String, text: Binding<String>, error: String? = nil, showsCaret: Bool = false,
                monospacedDigits: Bool = false, trailing: String? = nil, width: CGFloat? = nil) {
        self.placeholder = placeholder; self._text = text; self.error = error; self.showsCaret = showsCaret
        self.monospacedDigits = monospacedDigits; self.trailing = trailing; self.width = width
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Group {
                    if isSnapshot {
                        HStack(spacing: 1) {
                            Text(text.isEmpty ? placeholder : text).foregroundStyle(text.isEmpty ? theme.textTertiary : theme.text)
                            if showsCaret { Rectangle().fill(theme.accent).frame(width: 1.6, height: 18) }
                            Spacer(minLength: 0)
                        }
                    } else {
                        TextField(placeholder, text: $text).textFieldStyle(.plain).foregroundStyle(theme.text)
                    }
                }
                .font(monospacedDigits ? SFType.number(16, .medium) : SFType.inter(16, .medium))
                if let trailing { Text(trailing).font(SFType.label).foregroundStyle(theme.textTertiary) }
            }
            .padding(.horizontal, 14)
            .frame(width: width, height: 44)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.surfaceBase.opacity(theme.isDark ? 0.7 : 0.9))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(error != nil ? theme.critical : (showsCaret ? theme.accent : theme.hairline), lineWidth: showsCaret ? 1.5 : 1)))
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill").font(SFType.label).foregroundStyle(theme.critical)
            }
        }
    }
}

public extension View {
    /// `focusEffectDisabled` exists from macOS 14; earlier systems draw their default ring.
    @ViewBuilder func sfFocusEffectDisabled() -> some View {
        if #available(macOS 14.0, *) { self.focusEffectDisabled() } else { self }
    }
}
