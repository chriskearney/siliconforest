import SwiftUI

/// The installer's living backdrop: a conifer forest at night (Canopy) or dawn (Clearing), seen from
/// under the trees. Layered parallax treelines whose trees are the mark's chevron tiers, a sky of
/// stars with the mark's constellation, copper light on the horizon, circuit traces in the ground
/// with light running along them, and slow motes drifting up. Pure SwiftUI Canvas, so it renders
/// identically on screen and in `ImageRenderer` snapshots.
struct ForestBackdrop: View {
    /// Parallax position; animate it between steps for a slow camera move.
    var camera: Double = 0
    @Environment(\.theme) private var theme
    @Environment(\.backdropTime) private var fixedTime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let fixedTime {
            ForestCanvas(time: fixedTime, camera: camera, dark: theme.isDark, motion: true)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { ctx in
                // Reduce Motion: a still scene (time frozen at a pleasant moment).
                let t = reduceMotion ? 42 : ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 86_400)
                ForestCanvas(time: t, camera: camera, dark: theme.isDark, motion: !reduceMotion)
            }
        }
    }
}

struct ForestCanvas: View, Animatable {
    var time: Double
    var camera: Double
    var dark: Bool
    var motion: Bool

    var animatableData: Double {
        get { camera }
        set { camera = newValue }
    }

    var body: some View {
        Canvas(opaque: true) { ctx, size in
            ForestPainter(size: size, time: time, camera: camera, palette: dark ? .canopy : .clearing).paint(&ctx)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Palette

struct ForestPalette {
    var skyStops: [Gradient.Stop]
    var glow: Color
    var glowStrength: Double
    var upperGlow: Color
    var starColor: Color
    var starWarm: Color
    var starAlpha: Double
    var constellation: Color
    var farRidge: Color
    var nearRidge: Color
    var ridgeRim: Color
    var mist: Color
    var farTrees: Color
    var midTrees: Color
    var nearTrees: Color
    var rim: Color
    var ground: [Color]
    var trace: Color
    var pulse: Color
    var pulseWarm: Color
    var mote: Color
    var moteWarm: Color
    var vignette: Color

    static let canopy = ForestPalette(
        skyStops: [.init(color: Color(hex: 0x020706), location: 0), .init(color: Color(hex: 0x041210), location: 0.30),
                   .init(color: Color(hex: 0x082220), location: 0.58), .init(color: Color(hex: 0x123431), location: 0.80),
                   .init(color: Color(hex: 0x3A3A2C), location: 0.95), .init(color: Color(hex: 0x6A4A30), location: 1)],
        glow: Color(hex: 0xDD8F55), glowStrength: 0.46, upperGlow: Color(hex: 0x3FBF8A),
        starColor: Color(hex: 0xE4FFF0), starWarm: Color(hex: 0xFFD9B8), starAlpha: 1,
        constellation: Color(hex: 0x7FE3B4),
        farRidge: Color(hex: 0x0E2925), nearRidge: Color(hex: 0x0A1C19), ridgeRim: Color(hex: 0xE7A774),
        mist: Color(hex: 0x9FD9C0),
        farTrees: Color(hex: 0x0B201C), midTrees: Color(hex: 0x061310), nearTrees: Color(hex: 0x020706),
        rim: Color(hex: 0xE49A62),
        ground: [Color(hex: 0x050E0C), Color(hex: 0x020504)],
        trace: Color(hex: 0x58CC97), pulse: Color(hex: 0xB6F5CF), pulseWarm: Color(hex: 0xF2B27E),
        mote: Color(hex: 0x9CF0C6), moteWarm: Color(hex: 0xF0B07A),
        vignette: Color.black)

    static let clearing = ForestPalette(
        skyStops: [.init(color: Color(hex: 0xC9DCD6), location: 0), .init(color: Color(hex: 0xDCE7E0), location: 0.35),
                   .init(color: Color(hex: 0xEDEFE5), location: 0.68), .init(color: Color(hex: 0xF6E9D6), location: 0.88),
                   .init(color: Color(hex: 0xF7D9B6), location: 1)],
        glow: Color(hex: 0xF6B47E), glowStrength: 0.55, upperGlow: Color(hex: 0xFFFFFF),
        starColor: .white, starWarm: .white, starAlpha: 0,
        constellation: Color(hex: 0x2C7A54),
        farRidge: Color(hex: 0xA9C3B7), nearRidge: Color(hex: 0x8DAE9F), ridgeRim: Color(hex: 0xFFF1DE),
        mist: Color.white,
        farTrees: Color(hex: 0x86A797), midTrees: Color(hex: 0x557C6A), nearTrees: Color(hex: 0x24443A),
        rim: Color(hex: 0xF7C99C),
        ground: [Color(hex: 0x7E9F8F), Color(hex: 0x4E705F)],
        trace: Color(hex: 0xE6F5EC), pulse: Color(hex: 0xFFFFFF), pulseWarm: Color(hex: 0xFFE2C2),
        mote: Color(hex: 0xFFFFFF), moteWarm: Color(hex: 0xFFE3BF),
        vignette: Color(hex: 0x1E3A2E))
}

// MARK: - Scene geometry (built once per size)

struct SplitMix {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
}

final class ForestScene {
    struct Star { var p: CGPoint; var r: CGFloat; var a: Double; var tw: Double; var ph: Double; var warm: Bool }
    struct Mote { var x: CGFloat; var y: CGFloat; var speed: CGFloat; var sway: CGFloat; var freq: Double; var ph: Double; var r: CGFloat; var warm: Bool; var front: Bool }
    struct Trace { var path: Path; var speed: Double; var phase: Double; var warm: Bool; var width: CGFloat; var pads: [CGPoint] }

    let size: CGSize
    let horizon: CGFloat
    var stars: [Star] = []
    var constellation: [CGPoint] = []
    var farRidge = Path(), nearRidge = Path(), farRidgeLine = Path()
    var farTrees = Path(), midTrees = Path(), nearTrees = Path()
    var traces: [Trace] = []
    var motes: [Mote] = []

    private static var cache: [String: ForestScene] = [:]
    private static let lock = NSLock()

    static func scene(for size: CGSize) -> ForestScene {
        let key = "\(Int(size.width))x\(Int(size.height))"
        lock.lock(); defer { lock.unlock() }
        if let s = cache[key] { return s }
        let s = ForestScene(size: size)
        if cache.count > 8 { cache.removeAll() }
        cache[key] = s
        return s
    }

    init(size: CGSize) {
        self.size = size
        let w = size.width, h = size.height
        horizon = h * 0.705
        var rng = SplitMix(0x5F0E57)

        // Stars: denser high up, thinning toward the horizon glow.
        for _ in 0..<Int(w * h / 4200) {
            let y = pow(rng.next(), 1.6) * Double(horizon) * 0.9
            stars.append(Star(p: CGPoint(x: rng.next() * w, y: y), r: CGFloat(rng.range(0.35, 1.15)) * (rng.next() > 0.97 ? 1.8 : 1),
                              a: rng.range(0.25, 0.95) * (1 - y / Double(horizon)), tw: rng.range(0.4, 1.8), ph: rng.range(0, 6.28),
                              warm: rng.next() > 0.86))
        }
        // The mark's constellation, upper right: apex, two tier tips each side, trunk pad.
        let cx = w * 0.785, cy = h * 0.115, s = h * 0.105
        constellation = [CGPoint(x: cx, y: cy), CGPoint(x: cx - s * 0.30, y: cy + s * 0.50), CGPoint(x: cx + s * 0.31, y: cy + s * 0.48),
                         CGPoint(x: cx - s * 0.60, y: cy + s * 0.98), CGPoint(x: cx + s * 0.58, y: cy + s * 1.0), CGPoint(x: cx + s * 0.0, y: cy + s * 1.34)]

        // Ridges, built wider than the screen so parallax never shows an edge.
        func ridge(base: CGFloat, amp: CGFloat, seed: Double) -> (Path, Path) {
            var fill = Path(), line = Path()
            let x0 = -w * 0.1, x1 = w * 1.1
            var pts: [CGPoint] = []
            var x = x0
            while x <= x1 {
                let u = Double(x / w)
                let y = base - amp * CGFloat(0.55 * sin(u * 5.1 + seed) + 0.3 * sin(u * 11.7 + seed * 2.3) + 0.15 * sin(u * 23.0 + seed * 0.7))
                pts.append(CGPoint(x: x, y: y)); x += 6
            }
            line.addLines(pts)
            fill.addLines(pts); fill.addLine(to: CGPoint(x: x1, y: h)); fill.addLine(to: CGPoint(x: x0, y: h)); fill.closeSubpath()
            return (fill, line)
        }
        (farRidge, farRidgeLine) = ridge(base: horizon - h * 0.045, amp: h * 0.032, seed: 1.7)
        (nearRidge, _) = ridge(base: horizon - h * 0.006, amp: h * 0.014, seed: 4.2)

        func ridgeY(_ x: CGFloat, base: CGFloat, amp: CGFloat, seed: Double) -> CGFloat {
            let u = Double(x / w)
            return base - amp * CGFloat(0.55 * sin(u * 5.1 + seed) + 0.3 * sin(u * 11.7 + seed * 2.3) + 0.15 * sin(u * 23.0 + seed * 0.7))
        }

        // Far treeline on the near ridge.
        var x = -w * 0.08
        while x < w * 1.08 {
            let edge = abs(Double(x / w) - 0.5) * 2
            let th = h * CGFloat(rng.range(0.022, 0.05) * (0.8 + 0.6 * edge))
            let base = ridgeY(x, base: horizon - h * 0.006, amp: h * 0.014, seed: 4.2) + h * 0.006
            farTrees.addPath(Self.conifer(x: x, base: base, height: th, width: th * CGFloat(rng.range(0.42, 0.52)), tiers: 5, rng: &rng))
            x += CGFloat(rng.range(5, 13)) * w / 1440
        }
        // Mid treeline: bigger toward the edges, a clearing in the middle.
        x = -w * 0.08
        while x < w * 1.08 {
            let u = Double(x / w)
            let edge = min(1, abs(u - 0.5) * 2)
            if rng.next() > 0.18 + 0.62 * (1 - edge) * (1 - edge) || edge > 0.75 {
                let th = h * CGFloat(rng.range(0.07, 0.15) * (0.55 + 1.1 * pow(edge, 1.6)))
                let base = horizon + h * CGFloat(rng.range(0.018, 0.04))
                midTrees.addPath(Self.conifer(x: x, base: base, height: th, width: th * CGFloat(rng.range(0.38, 0.48)), tiers: 6 + Int(rng.next() * 3), rng: &rng))
            }
            x += CGFloat(rng.range(16, 34)) * w / 1440
        }
        // Near trees: the tallest at the rims, framing the gap of sky. The smaller ones stand on
        // the ground with their trunks visible; their trunks run on as circuit traces (the mark).
        let near: [(Double, Double)] = [(-0.03, 1.08), (0.06, 0.86), (0.14, 0.58), (0.205, 0.34),
                                        (1.035, 1.04), (0.95, 0.8), (0.868, 0.54), (0.80, 0.30)]
        var rootPoints: [(CGPoint, CGFloat)] = []
        for (u, hf) in near {
            let th = h * CGFloat(hf)
            let standing = hf < 0.6
            let base = standing ? h * CGFloat(0.9 + (0.6 - hf) * 0.1) : h * 1.05
            nearTrees.addPath(Self.conifer(x: w * CGFloat(u), base: base, height: th, width: th * CGFloat(rng.range(0.40, 0.45)),
                                           tiers: hf > 0.7 ? 11 : hf > 0.45 ? 9 : 7, rng: &rng))
            if standing { rootPoints.append((CGPoint(x: w * CGFloat(u), y: base), u < 0.5 ? 1 : -1)) }
        }

        let groundTop = horizon + h * 0.06
        func run(from start: CGPoint, dir: CGFloat, segments: Int, warm: Bool, firstJog: CGFloat) {
            var p = Path()
            var cur = start
            p.move(to: cur)
            // a 45° branch off the trunk, then alternate runs and jogs
            cur.x += dir * abs(firstJog); cur.y += abs(firstJog)
            p.addLine(to: cur)
            for i in 0..<segments {
                if i % 2 == 0 {
                    cur.x += dir * w * CGFloat(rng.range(0.05, 0.12))
                } else {
                    let dy = h * CGFloat(rng.range(-0.03, 0.025))
                    let ny = min(h * 0.985, max(groundTop, cur.y + dy))
                    cur.x += dir * abs(ny - cur.y)
                    cur.y = ny
                }
                p.addLine(to: cur)
            }
            traces.append(Trace(path: p, speed: rng.range(70, 130), phase: rng.next(), warm: warm,
                                width: 0.8 + CGFloat(Double(cur.y / h)) * 0.7, pads: [cur]))
        }
        for (root, dir) in rootPoints {
            // trunk continues straight down a little, then forks like the mark
            let fork = CGPoint(x: root.x, y: min(h * 0.99, root.y + h * 0.018))
            run(from: fork, dir: dir, segments: 5 + Int(rng.next() * 3), warm: rng.next() > 0.6, firstJog: h * 0.03)
            run(from: fork, dir: -dir, segments: 1, warm: false, firstJog: h * 0.016)
            var trunk = Path(); trunk.move(to: root); trunk.addLine(to: fork)
            traces.append(Trace(path: trunk, speed: 0, phase: 0, warm: false, width: 1.2, pads: []))
        }
        for _ in 0..<7 {
            let left = rng.next() > 0.5
            let start = CGPoint(x: left ? w * CGFloat(rng.range(0.12, 0.3)) : w * CGFloat(rng.range(0.7, 0.88)), y: h * CGFloat(rng.range(0.78, 0.95)))
            run(from: start, dir: left ? 1 : -1, segments: 3 + Int(rng.next() * 4), warm: rng.next() > 0.7, firstJog: h * 0.01)
        }

        // Motes
        for _ in 0..<Int(w * h / 26_000) {
            let front = rng.next() > 0.82
            motes.append(Mote(x: rng.next() * w, y: rng.next() * h, speed: CGFloat(rng.range(5, 16)) * (front ? 1.8 : 1), sway: CGFloat(rng.range(4, 18)),
                              freq: rng.range(0.05, 0.22), ph: rng.range(0, 6.28), r: CGFloat(rng.range(0.6, 1.8)) * (front ? 2.0 : 1),
                              warm: rng.next() > 0.72, front: front))
        }
    }

    /// A conifer drawn as stacked chevrons, like the mark's three tiers.
    static func conifer(x: CGFloat, base: CGFloat, height H: CGFloat, width W: CGFloat, tiers n: Int, rng: inout SplitMix) -> Path {
        var p = Path()
        let crownTop = base - H
        let crownH = H * 0.9
        let spacing = crownH / CGFloat(n + 1)
        let tierH = spacing * 2.0
        let lean = CGFloat(rng.range(-0.012, 0.012)) * H
        for i in 0..<n {
            let f1 = CGFloat(i + 1) / CGFloat(n)
            let top = crownTop + CGFloat(i) * spacing * 0.95 - (i == 0 ? H * 0.015 : 0)
            let bottom = top + tierH * (i == 0 ? 0.85 : 1)
            let hw = W / 2 * (0.2 + 0.8 * pow(f1, 0.9)) * CGFloat(rng.range(0.92, 1.06))
            let notch = bottom - tierH * CGFloat(rng.range(0.12, 0.16))
            let fx = CGFloat(i) / CGFloat(n)
            let cxTop = x + lean * (1 - fx)
            let cxBot = x + lean * (1 - f1)
            let droopL = hw * CGFloat(rng.range(0.03, 0.1)), droopR = hw * CGFloat(rng.range(0.03, 0.1))
            p.move(to: CGPoint(x: cxTop, y: top))
            p.addLine(to: CGPoint(x: cxBot + hw, y: bottom + droopR))
            p.addLine(to: CGPoint(x: cxBot + hw * 0.4, y: notch))
            p.addLine(to: CGPoint(x: cxBot - hw * 0.4, y: notch))
            p.addLine(to: CGPoint(x: cxBot - hw, y: bottom + droopL))
            p.closeSubpath()
        }
        let tw = max(1, W * 0.05)
        let trunkTop = crownTop + CGFloat(n - 1) * spacing * 0.95 + tierH * 0.8
        if base > trunkTop { p.addRect(CGRect(x: x - tw / 2, y: trunkTop, width: tw, height: base - trunkTop)) }
        return p
    }
}

// MARK: - Painter

struct ForestPainter {
    var size: CGSize
    var time: Double
    var camera: Double
    var palette: ForestPalette

    func paint(_ ctx: inout GraphicsContext) {
        let w = size.width, h = size.height
        guard w > 10, h > 10 else { return }
        let scene = ForestScene.scene(for: size)
        let P = palette
        let drift = 0.18 * sin(time / 47)               // a slow idle camera sway
        let cam = CGFloat(camera + drift)
        let unit = w / 1440

        // Sky
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(stops: P.skyStops), startPoint: .zero, endPoint: CGPoint(x: 0, y: scene.horizon + h * 0.02)))
        // A faint high glow (aurora-like in Canopy, haze in Clearing)
        drawGlow(&ctx, center: CGPoint(x: w * 0.72 - cam * 4 * unit, y: h * 0.12), rx: w * 0.5, ry: h * 0.3, color: P.upperGlow, alpha: palette.starAlpha > 0 ? 0.05 : 0.35)

        // Stars
        if P.starAlpha > 0 {
            for s in scene.stars {
                let a = s.a * (0.62 + 0.38 * sin(time * s.tw + s.ph))
                let pt = CGPoint(x: s.p.x - cam * 3 * unit, y: s.p.y)
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - s.r, y: pt.y - s.r, width: s.r * 2, height: s.r * 2)),
                         with: .color((s.warm ? P.starWarm : P.starColor).opacity(a)))
                if s.r > 1.5 {
                    drawGlow(&ctx, center: pt, rx: s.r * 6, ry: s.r * 6, color: P.starColor, alpha: a * 0.35)
                }
            }
        }
        drawConstellation(&ctx, scene: scene, cam: cam * 3 * unit)

        // Horizon glow (copper at night, peach at dawn)
        drawGlow(&ctx, center: CGPoint(x: w * 0.5 - cam * 6 * unit, y: scene.horizon + h * 0.01), rx: w * 0.62, ry: h * 0.26, color: P.glow, alpha: P.glowStrength)
        drawGlow(&ctx, center: CGPoint(x: w * 0.5 - cam * 6 * unit, y: scene.horizon + h * 0.005), rx: w * 0.26, ry: h * 0.07, color: P.glow, alpha: P.glowStrength * 0.8)

        // Far ridge with a rim of horizon light
        var c = ctx
        c.translateBy(x: -cam * 8 * unit, y: 0)
        c.fill(scene.farRidge, with: .linearGradient(Gradient(colors: [P.farRidge.opacity(0.92), P.nearRidge]), startPoint: CGPoint(x: 0, y: scene.horizon - h * 0.09), endPoint: CGPoint(x: 0, y: scene.horizon + h * 0.05)))
        c.stroke(scene.farRidgeLine, with: .color(P.ridgeRim.opacity(palette.starAlpha > 0 ? 0.16 : 0.5)), lineWidth: 1)

        // Mist between the ridges
        let mistY = scene.horizon - h * 0.02
        ctx.fill(Path(CGRect(x: 0, y: mistY - h * 0.05, width: w, height: h * 0.1)),
                 with: .linearGradient(Gradient(colors: [P.mist.opacity(0), P.mist.opacity(palette.starAlpha > 0 ? 0.07 : 0.4), P.mist.opacity(0)]),
                                       startPoint: CGPoint(x: 0, y: mistY - h * 0.05), endPoint: CGPoint(x: 0, y: mistY + h * 0.05)))
        for i in 0..<4 {
            let speed = 6.0 + Double(i) * 3
            let span = Double(w) * 1.6
            let xx = CGFloat((time * speed + Double(i) * 520).truncatingRemainder(dividingBy: span)) - w * 0.3
            drawGlow(&ctx, center: CGPoint(x: xx - cam * 10 * unit, y: mistY + CGFloat(i - 2) * h * 0.012), rx: w * 0.22, ry: h * 0.022,
                     color: P.mist, alpha: palette.starAlpha > 0 ? 0.05 : 0.3)
        }

        // Near ridge + far trees
        c = ctx
        c.translateBy(x: -cam * 12 * unit, y: 0)
        c.fill(scene.nearRidge, with: .color(P.nearRidge))
        c.fill(scene.farTrees, with: .color(P.farTrees))

        // Ground
        ctx.fill(Path(CGRect(x: 0, y: scene.horizon + h * 0.012, width: w, height: h)),
                 with: .linearGradient(Gradient(colors: [P.nearRidge] + P.ground), startPoint: CGPoint(x: 0, y: scene.horizon + h * 0.012), endPoint: CGPoint(x: 0, y: h)))
        // low mist over the ground
        ctx.fill(Path(CGRect(x: 0, y: scene.horizon, width: w, height: h * 0.06)),
                 with: .linearGradient(Gradient(colors: [P.mist.opacity(palette.starAlpha > 0 ? 0.06 : 0.25), P.mist.opacity(0)]),
                                       startPoint: CGPoint(x: 0, y: scene.horizon), endPoint: CGPoint(x: 0, y: scene.horizon + h * 0.06)))

        drawGlow(&ctx, center: CGPoint(x: w * 0.5 - cam * 20 * unit, y: scene.horizon + h * 0.05), rx: w * 0.34, ry: h * 0.06, color: P.glow, alpha: P.glowStrength * 0.22)
        // Mid treeline
        c = ctx
        c.translateBy(x: -cam * 22 * unit, y: 0)
        c.fill(scene.midTrees, with: .color(P.midTrees))

        // Circuit traces with running light
        drawTraces(&ctx, scene: scene, cam: cam * 34 * unit)

        // Near trees with a thin rim of horizon light on their inner edges
        c = ctx
        c.translateBy(x: -cam * 40 * unit, y: 0)
        var rimL = c, rimR = c
        rimL.clip(to: Path(CGRect(x: -w, y: 0, width: w * 1.5, height: h)))
        rimL.translateBy(x: 1.6 * unit + 0.6, y: 0.8)
        rimL.fill(scene.nearTrees, with: .color(P.rim.opacity(palette.starAlpha > 0 ? 0.13 : 0.4)))
        rimR.clip(to: Path(CGRect(x: w * 0.5, y: 0, width: w * 1.5, height: h)))
        rimR.translateBy(x: -1.6 * unit - 0.6, y: 0.8)
        rimR.fill(scene.nearTrees, with: .color(P.rim.opacity(palette.starAlpha > 0 ? 0.13 : 0.4)))
        c.fill(scene.nearTrees, with: .color(P.nearTrees))

        // Motes
        for m in scene.motes {
            let span = h + 60
            var y = m.y - CGFloat(time) * m.speed
            y = y.truncatingRemainder(dividingBy: span); if y < -30 { y += span }
            let x = m.x + m.sway * CGFloat(sin(time * m.freq * 6.28 + m.ph)) - cam * (m.front ? 60 : 26) * unit
            let fadeTop = min(1, max(0, Double(y / (h * 0.35))))
            let flicker = 0.55 + 0.45 * sin(time * (0.7 + m.freq * 4) + m.ph * 3)
            let a = fadeTop * flicker * (palette.starAlpha > 0 ? 0.85 : 0.7)
            let color = m.warm ? P.moteWarm : P.mote
            drawGlow(&ctx, center: CGPoint(x: x, y: y), rx: m.r * 5, ry: m.r * 5, color: color, alpha: a * 0.35)
            ctx.fill(Path(ellipseIn: CGRect(x: x - m.r * 0.6, y: y - m.r * 0.6, width: m.r * 1.2, height: m.r * 1.2)), with: .color(color.opacity(a)))
        }

        // Vignette
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .radialGradient(Gradient(colors: [P.vignette.opacity(0), P.vignette.opacity(palette.starAlpha > 0 ? 0.55 : 0.18)]),
                                       center: CGPoint(x: w / 2, y: h * 0.45), startRadius: min(w, h) * 0.35, endRadius: max(w, h) * 0.75))
    }

    private func drawGlow(_ ctx: inout GraphicsContext, center: CGPoint, rx: CGFloat, ry: CGFloat, color: Color, alpha: Double) {
        guard alpha > 0.002, rx > 0, ry > 0 else { return }
        var c = ctx
        c.translateBy(x: center.x, y: center.y)
        c.scaleBy(x: 1, y: ry / rx)
        c.fill(Path(ellipseIn: CGRect(x: -rx, y: -rx, width: rx * 2, height: rx * 2)),
               with: .radialGradient(Gradient(stops: [.init(color: color.opacity(alpha), location: 0),
                                                      .init(color: color.opacity(alpha * 0.45), location: 0.35),
                                                      .init(color: color.opacity(0), location: 1)]),
                                     center: .zero, startRadius: 0, endRadius: rx))
    }

    private func drawConstellation(_ ctx: inout GraphicsContext, scene: ForestScene, cam: CGFloat) {
        let pts = scene.constellation.map { CGPoint(x: $0.x - cam, y: $0.y) }
        guard pts.count == 6 else { return }
        let dark = palette.starAlpha > 0
        var lines = Path()
        for (a, b) in [(0, 1), (0, 2), (1, 3), (2, 4), (3, 4)] {
            lines.move(to: pts[a]); lines.addLine(to: pts[b])
        }
        let baseMid = CGPoint(x: (pts[3].x + pts[4].x) / 2, y: (pts[3].y + pts[4].y) / 2)
        lines.move(to: baseMid); lines.addLine(to: pts[5])
        ctx.stroke(lines, with: .color(palette.constellation.opacity(dark ? 0.16 : 0.18)), style: StrokeStyle(lineWidth: 0.8, dash: [3, 4]))
        // a pulse walking the figure
        let f = CGFloat((time / 14).truncatingRemainder(dividingBy: 1))
        var walk = Path(); walk.addLines([pts[5], baseMid, pts[3], pts[1], pts[0], pts[2], pts[4], baseMid])
        ctx.stroke(walk.trimmedPath(from: max(0, f - 0.06), to: f), with: .color(palette.constellation.opacity(dark ? 0.55 : 0.4)), lineWidth: 1.2)
        for (i, p) in pts.enumerated() {
            let r: CGFloat = i == 0 ? 1.9 : 1.4
            let tw = 0.75 + 0.25 * sin(time * 0.9 + Double(i))
            drawGlow(&ctx, center: p, rx: r * 7, ry: r * 7, color: dark ? palette.starColor : palette.constellation, alpha: (dark ? 0.35 : 0.2) * tw)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                     with: .color((dark ? palette.starColor : palette.constellation).opacity(0.95 * tw)))
        }
    }

    private func drawTraces(_ ctx: inout GraphicsContext, scene: ForestScene, cam: CGFloat) {
        var c = ctx
        c.translateBy(x: -cam, y: 0)
        let dark = palette.starAlpha > 0
        for t in scene.traces {
            c.stroke(t.path, with: .color(palette.trace.opacity(dark ? 0.17 : 0.4)), style: StrokeStyle(lineWidth: t.width, lineCap: .round, lineJoin: .round))
            for pad in t.pads {
                let r = 2.2 + t.width
                c.stroke(Path(ellipseIn: CGRect(x: pad.x - r, y: pad.y - r, width: r * 2, height: r * 2)), with: .color(palette.trace.opacity(dark ? 0.3 : 0.5)), lineWidth: 1)
            }
            guard t.speed > 0 else { continue }
            // light running along the trace toward its pad
            let f = CGFloat((time * t.speed / 900 + t.phase).truncatingRemainder(dividingBy: 1.35))
            if f <= 1.05 {
                let color = t.warm ? palette.pulseWarm : palette.pulse
                c.stroke(t.path.trimmedPath(from: max(0, f - 0.16), to: min(1, f)),
                         with: .color(color.opacity(dark ? 0.12 : 0.25)), style: StrokeStyle(lineWidth: t.width * 3, lineCap: .butt, lineJoin: .round))
                c.stroke(t.path.trimmedPath(from: max(0, f - 0.09), to: min(1, f)),
                         with: .color(color.opacity(dark ? 0.75 : 0.9)), style: StrokeStyle(lineWidth: t.width * 1.2, lineCap: .round, lineJoin: .round))
                if f >= 0.98 {
                    for pad in t.pads {
                        drawGlow(&c, center: pad, rx: 16, ry: 16, color: color, alpha: dark ? 0.6 : 0.6)
                    }
                }
            }
        }
    }
}
