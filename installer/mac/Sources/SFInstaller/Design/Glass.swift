import SwiftUI

/// Frosted glass that really blurs what's behind it: the backdrop is drawn again under the panel,
/// aligned to the screen, blurred and tinted. Pure SwiftUI (no NSVisualEffectView), so snapshots
/// match the app exactly.
struct GlassBackground: View {
    var cornerRadius: CGFloat = 30
    var camera: Double
    var blur: CGFloat = 34
    var tint: Color? = nil
    @Environment(\.theme) private var theme
    @Environment(\.screenSize) private var screen

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .named("screen"))
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            ZStack {
                ForestBackdrop(camera: camera)
                    .frame(width: screen.width, height: screen.height)
                    .position(x: screen.width / 2 - frame.minX, y: screen.height / 2 - frame.minY)
                    .blur(radius: blur, opaque: true)
                    .saturation(theme.isDark ? 1.15 : 1.05)
                shape.fill(tint ?? theme.glassTint)
                // top-lit sheen
                shape.fill(LinearGradient(colors: [Color.white.opacity(theme.isDark ? 0.06 : 0.25), .clear], startPoint: .top, endPoint: .center))
            }
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(LinearGradient(colors: [theme.glassStroke, theme.glassStroke.opacity(0.25)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .overlay(
                shape.inset(by: -0.5).stroke(theme.glassStrokeOuter, lineWidth: 0.5)
            )
        }
    }
}

struct GlassPanel<Content: View>: View {
    var camera: Double
    var cornerRadius: CGFloat = 30
    @ViewBuilder var content: Content
    @Environment(\.theme) private var theme

    var body: some View {
        content
            .background(GlassBackground(cornerRadius: cornerRadius, camera: camera))
            // The horizon's light caught on the top edge (Canopy's copper line).
            .overlay(alignment: .top) {
                LinearGradient(colors: [.clear, theme.copper.opacity(theme.isDark ? 0.75 : 0.5), theme.mint.opacity(theme.isDark ? 0.55 : 0.4), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1)
                    .padding(.horizontal, cornerRadius * 1.6)
            }
            .shadow(color: theme.shadow, radius: 50, y: 24)
    }
}

/// A quiet card inside a panel.
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    var radius: CGFloat = 16
    @ViewBuilder var content: Content
    @Environment(\.theme) private var theme

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(theme.card)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: 1))
            )
    }
}
