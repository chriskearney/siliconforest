import SwiftUI

/// The SiliconForest mark, drawn from the same 512-grid paths as
/// integrations/siliconforest/branding/siliconforest-icon.svg: a conifer in three chevron tiers
/// whose trunk runs on as circuit traces ending in pads.
struct MarkTiers: Shape {
    func path(in rect: CGRect) -> Path {
        let t = MarkGrid(rect)
        var p = Path()
        p.addLines([t.pt(256, 56), t.pt(338, 168), t.pt(294, 168), t.pt(256, 118), t.pt(218, 168), t.pt(174, 168)]); p.closeSubpath()
        p.addLines([t.pt(256, 150), t.pt(366, 290), t.pt(318, 290), t.pt(256, 212), t.pt(194, 290), t.pt(146, 290)]); p.closeSubpath()
        p.addLines([t.pt(256, 250), t.pt(394, 420), t.pt(342, 420), t.pt(256, 314), t.pt(170, 420), t.pt(118, 420)]); p.closeSubpath()
        return p
    }
}

struct MarkTraces: Shape {
    func path(in rect: CGRect) -> Path {
        let t = MarkGrid(rect)
        var p = Path()
        p.move(to: t.pt(256, 350)); p.addLine(to: t.pt(256, 452))
        p.move(to: t.pt(256, 404)); p.addLine(to: t.pt(212, 448)); p.addLine(to: t.pt(176, 448))
        p.move(to: t.pt(256, 404)); p.addLine(to: t.pt(300, 448)); p.addLine(to: t.pt(336, 448))
        return p
    }
}

struct MarkPads: Shape {
    func path(in rect: CGRect) -> Path {
        let t = MarkGrid(rect)
        var p = Path()
        for (x, y) in [(256.0, 462.0), (166.0, 448.0), (346.0, 448.0)] {
            let c = t.pt(x, y), r = 13 * t.scale
            p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        }
        return p
    }
}

/// Maps the mark's 512 grid (content spans x 118…394, y 56…475) into a rect, centred.
struct MarkGrid {
    let scale: CGFloat
    let origin: CGPoint
    init(_ rect: CGRect) {
        let w: CGFloat = 300, h: CGFloat = 425   // x 106…406, y 52…477
        scale = min(rect.width / w, rect.height / h)
        origin = CGPoint(x: rect.midX - 256 * scale, y: rect.midY - 264.5 * scale)
    }
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * scale, y: origin.y + y * scale) }
}

struct BrandMark: View {
    var tiers: AnyShapeStyle
    var traces: Color
    var glow: Color? = nil

    var body: some View {
        GeometryReader { geo in
            let s = MarkGrid(CGRect(origin: .zero, size: geo.size)).scale
            ZStack {
                MarkTiers().fill(tiers)
                MarkTraces().stroke(traces, style: StrokeStyle(lineWidth: 14 * s, lineCap: .round, lineJoin: .round))
                MarkPads().fill(traces)
            }
            .shadow(color: glow ?? .clear, radius: glow == nil ? 0 : geo.size.height * 0.12)
        }
        .aspectRatio(300 / 425, contentMode: .fit)
        .accessibilityHidden(true)
    }

    static func mint(_ theme: Theme, glow: Bool = true) -> BrandMark {
        BrandMark(tiers: AnyShapeStyle(LinearGradient(colors: theme.isDark ? [Color(hex: 0xC4F8D8), Color(hex: 0x3FBF8A)] : [Color(hex: 0x4FB083), Color(hex: 0x1F6545)],
                                                      startPoint: .top, endPoint: .bottom)),
                  traces: theme.isDark ? Color(hex: 0x58CC97) : Color(hex: 0x2C7A54),
                  glow: glow ? (theme.isDark ? Color(hex: 0x58CC97, alpha: 0.45) : Color(hex: 0x2C7A54, alpha: 0.18)) : nil)
    }
}

/// The app icon: the mark on the dark-green rounded square, as in siliconforest-icon.svg, with a
/// little more depth for the Dock.
struct AppIconArt: View {
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let inset = side * 16 / 512
            let plate = side - inset * 2
            ZStack {
                RoundedRectangle(cornerRadius: plate * 108 / 480, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x17493A), Color(hex: 0x061510)], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: plate * 108 / 480, style: .continuous)
                            .fill(RadialGradient(colors: [Color(hex: 0xDD8F55, alpha: 0.35), .clear], center: UnitPoint(x: 0.5, y: 1.05),
                                                 startRadius: 0, endRadius: plate * 0.62))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: plate * 108 / 480, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom),
                                          lineWidth: max(1, plate * 0.006))
                    )
                    .frame(width: plate, height: plate)
                BrandMark(tiers: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xC4F8D8), Color(hex: 0x3FBF8A)], startPoint: .top, endPoint: .bottom)),
                          traces: Color(hex: 0x58CC97), glow: Color(hex: 0x58CC97, alpha: 0.35))
                    .frame(height: plate * 0.70)
                    .offset(y: plate * 0.01)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
