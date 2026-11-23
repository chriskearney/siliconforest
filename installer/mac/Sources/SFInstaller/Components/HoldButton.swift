import SwiftUI

/// Press-and-hold to confirm. Mouse/trackpad: hold the button. Keyboard: focus it and hold Return or
/// Space. VoiceOver: the default action confirms directly (holding isn't a VoiceOver gesture).
struct HoldButton: View {
    var title: String
    var holdingTitle: String
    var symbol: String
    var duration: Double = 1.6
    var destructive = false
    /// Fixed fill for snapshots.
    var previewProgress: Double? = nil
    var action: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var enabled
    @State private var progress: Double = 0
    @State private var pressing = false
    @State private var completed = false
    @FocusState private var focused: Bool

    var body: some View {
        let p = previewProgress ?? progress
        let shape = Capsule(style: .continuous)
        ZStack(alignment: .leading) {
            shape.fill(theme.isDark ? Color.white.opacity(0.07) : Color.white.opacity(0.7))
            GeometryReader { geo in
                shape.fill(fill)
                    .frame(width: max(0, geo.size.width * p))
                    .opacity(p > 0 ? 1 : 0)
            }
            .clipShape(shape)
            HStack(spacing: 11) {
                ZStack {
                    Circle().stroke(labelColor(p).opacity(0.25), lineWidth: 2.2)
                    Circle().trim(from: 0, to: p).stroke(labelColor(p), style: StrokeStyle(lineWidth: 2.2, lineCap: .round)).rotationEffect(.degrees(-90))
                    Image(systemName: symbol).font(.system(size: 10.5, weight: .bold)).foregroundStyle(labelColor(p))
                }
                .frame(width: 24, height: 24)
                Text(p > 0.001 ? holdingTitle : title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(labelColor(p))
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 264, height: 50)
        .overlay(shape.strokeBorder(accent.opacity(focused ? 0.95 : 0.55), lineWidth: focused ? 2 : 1.2))
        .shadow(color: accent.opacity(theme.isDark ? 0.25 + 0.35 * p : 0.12), radius: 10 + 10 * p, y: 3)
        .scaleEffect(pressing ? 0.985 : 1)
        .opacity(enabled ? 1 : 0.4)
        .contentShape(shape)
        .onLongPressGesture(minimumDuration: duration, maximumDistance: 40, perform: complete, onPressingChanged: pressChanged)
        .focusable(enabled)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.return, .space], phases: [.down, .up]) { press in
            pressChanged(press.phase == .down)
            if press.phase == .down {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                    if pressing && !completed { complete() }
                }
            }
            return .handled
        }
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityHint("Starts immediately with VoiceOver. Otherwise, press and hold.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { complete() }
    }

    private var accent: Color { destructive ? theme.coral : theme.mint }
    private var fill: LinearGradient {
        destructive
            ? LinearGradient(colors: [theme.copper, theme.coral], startPoint: .leading, endPoint: .trailing)
            : LinearGradient(colors: theme.isDark ? [theme.copper.opacity(0.9), theme.mint] : [theme.mintBright, theme.mint], startPoint: .leading, endPoint: .trailing)
    }
    private func labelColor(_ p: Double) -> Color { p > 0.55 ? theme.onAccent : theme.text }

    private func pressChanged(_ down: Bool) {
        guard enabled, !completed else { return }
        pressing = down
        if down {
            withAnimation(.linear(duration: duration)) { progress = 1 }
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { progress = 0 }
        }
    }

    private func complete() {
        guard enabled, !completed else { return }
        completed = true
        pressing = false
        progress = 1
        action()
    }
}
