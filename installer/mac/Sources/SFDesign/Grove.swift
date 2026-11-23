import SwiftUI

/// The Grove: the installer's living background (VISUAL-DESIGN §1). A conifer forest seen from under
/// the trees; its trees are the mark's chevron tiers, its ground carries circuit traces with light
/// running along them. `dawn` runs from night (0) through first light and dawn breaking to the
/// Clearing in the morning (1); the installer ties it to real progress, so the background is also
/// the progress indicator. Pure SwiftUI Canvas so on-screen and `ImageRenderer` snapshots match.
public struct Grove: View {
    public var camera: Double
    public var dawn: Double
    @Environment(\.theme) private var theme
    @Environment(\.backdropTime) private var fixedTime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(camera: Double = 0, dawn: Double = 0) { self.camera = camera; self.dawn = dawn }

    public var body: some View {
        if let fixedTime {
            GroveCanvas(time: fixedTime, camera: camera, dawn: dawn, dark: theme.isDark)
        } else if reduceMotion {
            // Reduce Motion: no parallax, no travel; dawn steps between stills.
            GroveCanvas(time: 42, camera: 0, dawn: (dawn * 4).rounded() / 4, dark: theme.isDark)
        } else {
            // 30 fps is plenty for a scene that moves this slowly (VISUAL §6).
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { ctx in
                GroveCanvas(time: ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 86_400),
                            camera: camera, dawn: dawn, dark: theme.isDark)
            }
        }
    }
}

struct GroveCanvas: View, Animatable {
    var time: Double
    var camera: Double
    var dawn: Double
    var dark: Bool

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(camera, dawn) }
        set { camera = newValue.first; dawn = newValue.second }
    }

    var body: some View {
        Canvas(opaque: true) { ctx, size in
            ForestPainter(size: size, time: time, camera: camera, palette: GrovePalette.at(dawn: dawn, dark: dark)).paint(&ctx)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Palette: night → first light → dawn → Clearing

struct RGBA {
    var r, g, b, a: Double
    init(_ hex: UInt32, _ a: Double = 1) {
        r = Double((hex >> 16) & 0xff) / 255; g = Double((hex >> 8) & 0xff) / 255; b = Double(hex & 0xff) / 255; self.a = a
    }
    init(r: Double, g: Double, b: Double, a: Double) { self.r = r; self.g = g; self.b = b; self.a = a }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    func with(alpha: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: alpha) }
    static func lerp(_ x: RGBA, _ y: RGBA, _ t: Double) -> RGBA {
        RGBA(r: x.r + (y.r - x.r) * t, g: x.g + (y.g - x.g) * t, b: x.b + (y.b - x.b) * t, a: x.a + (y.a - x.a) * t)
    }
}

/// Every colour and strength in the scene, interpolable.
struct GroveSpec {
    var sky: [RGBA]          // 6 stops, top to horizon
    var glow: RGBA; var glowStrength: Double
    var upperGlow: RGBA; var upperGlowStrength: Double
    var star: RGBA; var starWarm: RGBA; var starAlpha: Double
    var constellation: RGBA; var constellationAlpha: Double
    var farRidge: RGBA; var nearRidge: RGBA; var ridgeRim: RGBA; var ridgeRimAlpha: Double
    var mist: RGBA; var mistAlpha: Double
    var farTrees: RGBA; var midTrees: RGBA; var nearTrees: RGBA
    var rim: RGBA; var rimAlpha: Double
    var ground: [RGBA]
    var trace: RGBA; var traceAlpha: Double
    var pulse: RGBA; var pulseWarm: RGBA
    var mote: RGBA; var moteWarm: RGBA; var moteAlpha: Double
    var vignette: RGBA; var vignetteAlpha: Double
    var sun: Double          // a soft sun disc on the horizon (morning only)

    static func lerp(_ x: GroveSpec, _ y: GroveSpec, _ t: Double) -> GroveSpec {
        func c(_ k: KeyPath<GroveSpec, RGBA>) -> RGBA { RGBA.lerp(x[keyPath: k], y[keyPath: k], t) }
        func d(_ k: KeyPath<GroveSpec, Double>) -> Double { x[keyPath: k] + (y[keyPath: k] - x[keyPath: k]) * t }
        return GroveSpec(sky: zip(x.sky, y.sky).map { RGBA.lerp($0, $1, t) },
                         glow: c(\.glow), glowStrength: d(\.glowStrength), upperGlow: c(\.upperGlow), upperGlowStrength: d(\.upperGlowStrength),
                         star: c(\.star), starWarm: c(\.starWarm), starAlpha: d(\.starAlpha),
                         constellation: c(\.constellation), constellationAlpha: d(\.constellationAlpha),
                         farRidge: c(\.farRidge), nearRidge: c(\.nearRidge), ridgeRim: c(\.ridgeRim), ridgeRimAlpha: d(\.ridgeRimAlpha),
                         mist: c(\.mist), mistAlpha: d(\.mistAlpha), farTrees: c(\.farTrees), midTrees: c(\.midTrees), nearTrees: c(\.nearTrees),
                         rim: c(\.rim), rimAlpha: d(\.rimAlpha), ground: zip(x.ground, y.ground).map { RGBA.lerp($0, $1, t) },
                         trace: c(\.trace), traceAlpha: d(\.traceAlpha), pulse: c(\.pulse), pulseWarm: c(\.pulseWarm),
                         mote: c(\.mote), moteWarm: c(\.moteWarm), moteAlpha: d(\.moteAlpha),
                         vignette: c(\.vignette), vignetteAlpha: d(\.vignetteAlpha), sun: d(\.sun))
    }

    /// Canopy: the forest at night.
    static let night = GroveSpec(
        sky: [RGBA(0x020706), RGBA(0x041210), RGBA(0x082220), RGBA(0x123431), RGBA(0x2E3528), RGBA(0x5A4230)],
        glow: RGBA(0xDD8F55), glowStrength: 0.34, upperGlow: RGBA(0x3FBF8A), upperGlowStrength: 0.05,
        star: RGBA(0xE4FFF0), starWarm: RGBA(0xFFD9B8), starAlpha: 1,
        constellation: RGBA(0xA6F2C8), constellationAlpha: 1,
        farRidge: RGBA(0x0E2925), nearRidge: RGBA(0x0A1C19), ridgeRim: RGBA(0xE7A774), ridgeRimAlpha: 0.12,
        mist: RGBA(0x9FD9C0), mistAlpha: 0.05,
        farTrees: RGBA(0x0B201C), midTrees: RGBA(0x061310), nearTrees: RGBA(0x020706),
        rim: RGBA(0xE49A62), rimAlpha: 0.10,
        ground: [RGBA(0x050E0C), RGBA(0x020504)],
        trace: RGBA(0x58CC97), traceAlpha: 0.15, pulse: RGBA(0xB6F5CF), pulseWarm: RGBA(0xF2B27E),
        mote: RGBA(0x9CF0C6), moteWarm: RGBA(0xF0B07A), moteAlpha: 0.8,
        vignette: RGBA(0x000000), vignetteAlpha: 0.55, sun: 0)

    /// Dawn breaking: the copper horizon has risen, the sky is lifting, stars nearly gone.
    static let dawnBreak = GroveSpec(
        sky: [RGBA(0x07191A), RGBA(0x0D2828), RGBA(0x1A3C38), RGBA(0x3A5148), RGBA(0x8A6A4A), RGBA(0xD08E5C)],
        glow: RGBA(0xF0A56A), glowStrength: 0.62, upperGlow: RGBA(0xF3C9A0), upperGlowStrength: 0.06,
        star: RGBA(0xE4FFF0), starWarm: RGBA(0xFFD9B8), starAlpha: 0.25,
        constellation: RGBA(0xA6F2C8), constellationAlpha: 0.45,
        farRidge: RGBA(0x29433D), nearRidge: RGBA(0x18302A), ridgeRim: RGBA(0xF6BE8A), ridgeRimAlpha: 0.32,
        mist: RGBA(0xF3D6B8), mistAlpha: 0.14,
        farTrees: RGBA(0x1D3832), midTrees: RGBA(0x0F241F), nearTrees: RGBA(0x06110E),
        rim: RGBA(0xF0A56A), rimAlpha: 0.22,
        ground: [RGBA(0x10221D), RGBA(0x07110E)],
        trace: RGBA(0x7FDDB0), traceAlpha: 0.2, pulse: RGBA(0xE8FFF2), pulseWarm: RGBA(0xFFCB98),
        mote: RGBA(0xFFE6C8), moteWarm: RGBA(0xF6B47E), moteAlpha: 0.6,
        vignette: RGBA(0x000000), vignetteAlpha: 0.42, sun: 0.15)

    /// Clearing: the same forest in the morning.
    static let clearing = GroveSpec(
        sky: [RGBA(0xBFD6D0), RGBA(0xD3E3DC), RGBA(0xE8EEE5), RGBA(0xF2EDE1), RGBA(0xF7E3C8), RGBA(0xF8D7B0)],
        glow: RGBA(0xF6B47E), glowStrength: 0.5, upperGlow: RGBA(0xFFFFFF), upperGlowStrength: 0.35,
        star: RGBA(0xFFFFFF), starWarm: RGBA(0xFFFFFF), starAlpha: 0,
        constellation: RGBA(0x2C7A54), constellationAlpha: 0,
        farRidge: RGBA(0xA9C3B7), nearRidge: RGBA(0x8DAE9F), ridgeRim: RGBA(0xFFF1DE), ridgeRimAlpha: 0.5,
        mist: RGBA(0xFFFFFF), mistAlpha: 0.42,
        farTrees: RGBA(0x86A797), midTrees: RGBA(0x557C6A), nearTrees: RGBA(0x24443A),
        rim: RGBA(0xF7C99C), rimAlpha: 0.4,
        ground: [RGBA(0x86A595), RGBA(0x587A69)],
        trace: RGBA(0xEAF7EF), traceAlpha: 0.4, pulse: RGBA(0xFFFFFF), pulseWarm: RGBA(0xFFE2C2),
        mote: RGBA(0xFFFFFF), moteWarm: RGBA(0xFFE3BF), moteAlpha: 0.55,
        vignette: RGBA(0x1E3A2E), vignetteAlpha: 0.14, sun: 0.7)

    /// Sunrise: the dark appearance's morning. The same Clearing geometry with the sun up and mist
    /// in the valley, seen from the night side, so the dark token set still reads at 4.5:1 over it.
    static let sunrise = GroveSpec(
        sky: [RGBA(0x0B2226), RGBA(0x143433), RGBA(0x24493F), RGBA(0x4C5E4A), RGBA(0xA9794C), RGBA(0xE9A866)],
        glow: RGBA(0xF6B47E), glowStrength: 0.7, upperGlow: RGBA(0xF8D9B4), upperGlowStrength: 0.12,
        star: RGBA(0xE4FFF0), starWarm: RGBA(0xFFD9B8), starAlpha: 0.04,
        constellation: RGBA(0xA6F2C8), constellationAlpha: 0.2,
        farRidge: RGBA(0x3A564B), nearRidge: RGBA(0x233D35), ridgeRim: RGBA(0xFFCF9C), ridgeRimAlpha: 0.45,
        mist: RGBA(0xF8DFC2), mistAlpha: 0.22,
        farTrees: RGBA(0x2A473D), midTrees: RGBA(0x15302A), nearTrees: RGBA(0x081612),
        rim: RGBA(0xF6B47E), rimAlpha: 0.34,
        ground: [RGBA(0x17302A), RGBA(0x0A1714)],
        trace: RGBA(0x9BE7C2), traceAlpha: 0.26, pulse: RGBA(0xF2FFF7), pulseWarm: RGBA(0xFFD3A3),
        mote: RGBA(0xFFE9CC), moteWarm: RGBA(0xF8BE88), moteAlpha: 0.55,
        vignette: RGBA(0x000000), vignetteAlpha: 0.34, sun: 0.6)

    /// Light appearance starts in pre-dawn mist and ends in the same Clearing (VISUAL §9).
    static let predawn = GroveSpec(
        sky: [RGBA(0x9FB4B3), RGBA(0xB3C5C1), RGBA(0xC8D4CD), RGBA(0xD8DDD4), RGBA(0xE4DCCB), RGBA(0xE9D2B9)],
        glow: RGBA(0xEDB894), glowStrength: 0.32, upperGlow: RGBA(0xFFFFFF), upperGlowStrength: 0.18,
        star: RGBA(0xFFFFFF), starWarm: RGBA(0xFFFFFF), starAlpha: 0,
        constellation: RGBA(0x2C7A54), constellationAlpha: 0.5,
        farRidge: RGBA(0x93AAA2), nearRidge: RGBA(0x7A968A), ridgeRim: RGBA(0xF4E4D2), ridgeRimAlpha: 0.35,
        mist: RGBA(0xFFFFFF), mistAlpha: 0.5,
        farTrees: RGBA(0x748F84), midTrees: RGBA(0x4B6A5D), nearTrees: RGBA(0x233F35),
        rim: RGBA(0xEFC7A4), rimAlpha: 0.3,
        ground: [RGBA(0x7B978A), RGBA(0x50705F)],
        trace: RGBA(0xE6F3EB), traceAlpha: 0.36, pulse: RGBA(0xFFFFFF), pulseWarm: RGBA(0xFFE2C2),
        mote: RGBA(0xFFFFFF), moteWarm: RGBA(0xFFE3BF), moteAlpha: 0.45,
        vignette: RGBA(0x1E3A2E), vignetteAlpha: 0.16, sun: 0)
}

struct ForestPalette {
    var spec: GroveSpec
    /// 1 at night, 0 in daylight: used to blend strengths that differ between the two.
    var night: Double
}

enum GrovePalette {
    static func at(dawn: Double, dark: Bool) -> ForestPalette {
        let t = min(1, max(0, dawn))
        if dark {
            // Night holds until first light, dawn breaks with progress, sunrise comes last (VISUAL §9:
            // "in dark mode the journey is Canopy → dawn"; light mode ends in the Clearing).
            if t < 0.6 { return ForestPalette(spec: .lerp(.night, .dawnBreak, smooth(t / 0.6)), night: 1 - t * 0.5) }
            let u = smooth((t - 0.6) / 0.4)
            return ForestPalette(spec: .lerp(.dawnBreak, .sunrise, u), night: 0.7 - 0.4 * u)
        }
        return ForestPalette(spec: .lerp(.predawn, .clearing, smooth(t)), night: 0)
    }
    static func smooth(_ x: Double) -> Double { let c = min(1, max(0, x)); return c * c * (3 - 2 * c) }
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

final class ForestScene: @unchecked Sendable {
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
        let P = palette.spec
        // Trees and mist: a slow parallax drift, 60 s period (VISUAL §6).
        let drift = 0.1 * sin(time * 2 * .pi / 60)
        let cam = CGFloat(camera + drift)
        let unit = w / 1440

        // Sky
        let stops = P.sky.enumerated().map { Gradient.Stop(color: $1.color, location: [0, 0.3, 0.58, 0.8, 0.95, 1][$0]) }
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(stops: stops), startPoint: .zero, endPoint: CGPoint(x: 0, y: scene.horizon + h * 0.02)))
        glow(&ctx, CGPoint(x: w * 0.72 - cam * 4 * unit, y: h * 0.12), w * 0.5, h * 0.3, P.upperGlow, P.upperGlowStrength)

        // Stars (fade as the sky lifts)
        if P.starAlpha > 0.01 {
            for s in scene.stars {
                let a = s.a * (0.62 + 0.38 * sin(time * s.tw + s.ph)) * P.starAlpha
                let pt = CGPoint(x: s.p.x - cam * 3 * unit, y: s.p.y)
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - s.r, y: pt.y - s.r, width: s.r * 2, height: s.r * 2)),
                         with: .color((s.warm ? P.starWarm : P.star).color.opacity(a)))
                if s.r > 1.5 { glow(&ctx, pt, s.r * 6, s.r * 6, P.star, a * 0.35) }
            }
        }
        if P.constellationAlpha > 0.01 { constellation(&ctx, scene, cam * 3 * unit) }

        // Horizon glow and, in the morning, a soft sun
        glow(&ctx, CGPoint(x: w * 0.5 - cam * 6 * unit, y: scene.horizon + h * 0.01), w * 0.62, h * 0.26, P.glow, P.glowStrength)
        glow(&ctx, CGPoint(x: w * 0.5 - cam * 6 * unit, y: scene.horizon + h * 0.005), w * 0.26, h * 0.07, P.glow, P.glowStrength * 0.8)
        if P.sun > 0.01 {
            let c = CGPoint(x: w * 0.56 - cam * 6 * unit, y: scene.horizon - h * 0.03)
            glow(&ctx, c, h * 0.16, h * 0.16, RGBA(0xFFF4E2), P.sun * 0.55)
            glow(&ctx, c, h * 0.035, h * 0.035, RGBA(0xFFFBF2), P.sun)
        }

        // Far ridge with a rim of horizon light
        var c = ctx
        c.translateBy(x: -cam * 8 * unit, y: 0)
        c.fill(scene.farRidge, with: .linearGradient(Gradient(colors: [P.farRidge.color.opacity(0.92), P.nearRidge.color]),
                                                      startPoint: CGPoint(x: 0, y: scene.horizon - h * 0.09), endPoint: CGPoint(x: 0, y: scene.horizon + h * 0.05)))
        c.stroke(scene.farRidgeLine, with: .color(P.ridgeRim.color.opacity(P.ridgeRimAlpha)), lineWidth: 1)

        // Mist between the ridges
        let mistY = scene.horizon - h * 0.02
        bands(&ctx, top: mistY - h * 0.05, bottom: mistY + h * 0.05, width: w,
              colors: [P.mist.with(alpha: 0), P.mist.with(alpha: P.mistAlpha * 1.3), P.mist.with(alpha: 0)])
        for i in 0..<4 {
            let speed = 6.0 + Double(i) * 3
            let span = Double(w) * 1.6
            let xx = CGFloat((time * speed + Double(i) * 520).truncatingRemainder(dividingBy: span)) - w * 0.3
            glow(&ctx, CGPoint(x: xx - cam * 10 * unit, y: mistY + CGFloat(i - 2) * h * 0.012), w * 0.22, h * 0.022, P.mist, P.mistAlpha)
        }

        // Near ridge + far trees
        c = ctx
        c.translateBy(x: -cam * 12 * unit, y: 0)
        c.fill(scene.nearRidge, with: .color(P.nearRidge.color))
        c.fill(scene.farTrees, with: .color(P.farTrees.color))

        // Ground, with low mist and the horizon's reflection
        bands(&ctx, top: scene.horizon + h * 0.012, bottom: h, width: w, colors: [P.nearRidge] + P.ground)
        bands(&ctx, top: scene.horizon, bottom: scene.horizon + h * 0.06, width: w,
              colors: [P.mist.with(alpha: P.mistAlpha * 1.1), P.mist.with(alpha: 0)])
        glow(&ctx, CGPoint(x: w * 0.5 - cam * 20 * unit, y: scene.horizon + h * 0.05), w * 0.34, h * 0.06, P.glow, P.glowStrength * 0.22)

        // Mid treeline
        c = ctx
        c.translateBy(x: -cam * 22 * unit, y: 0)
        c.fill(scene.midTrees, with: .color(P.midTrees.color))

        traces(&ctx, scene, cam * 34 * unit)

        // Near trees with a thin rim of horizon light on their inner edges
        c = ctx
        c.translateBy(x: -cam * 40 * unit, y: 0)
        var rimL = c, rimR = c
        rimL.clip(to: Path(CGRect(x: -w, y: 0, width: w * 1.5, height: h)))
        rimL.translateBy(x: 1.6 * unit + 0.6, y: 0.8)
        rimL.fill(scene.nearTrees, with: .color(P.rim.color.opacity(P.rimAlpha)))
        rimR.clip(to: Path(CGRect(x: w * 0.5, y: 0, width: w * 1.5, height: h)))
        rimR.translateBy(x: -1.6 * unit - 0.6, y: 0.8)
        rimR.fill(scene.nearTrees, with: .color(P.rim.color.opacity(P.rimAlpha)))
        c.fill(scene.nearTrees, with: .color(P.nearTrees.color))

        // Motes
        for m in scene.motes {
            let span = h + 60
            var y = m.y - CGFloat(time) * m.speed
            y = y.truncatingRemainder(dividingBy: span); if y < -30 { y += span }
            let x = m.x + m.sway * CGFloat(sin(time * m.freq * 6.28 + m.ph)) - cam * (m.front ? 60 : 26) * unit
            let fadeTop = min(1, max(0, Double(y / (h * 0.35))))
            let flicker = 0.55 + 0.45 * sin(time * (0.7 + m.freq * 4) + m.ph * 3)
            let a = fadeTop * flicker * P.moteAlpha
            let col = m.warm ? P.moteWarm : P.mote
            glow(&ctx, CGPoint(x: x, y: y), m.r * 5, m.r * 5, col, a * 0.35)
            ctx.fill(Path(ellipseIn: CGRect(x: x - m.r * 0.6, y: y - m.r * 0.6, width: m.r * 1.2, height: m.r * 1.2)), with: .color(col.color.opacity(a)))
        }

        // Vignette
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .radialGradient(Gradient(colors: [P.vignette.color.opacity(0), P.vignette.color.opacity(P.vignetteAlpha)]),
                                       center: CGPoint(x: w / 2, y: h * 0.45), startRadius: min(w, h) * 0.35, endRadius: max(w, h) * 0.75))
    }

    /// A vertical gradient across the full width drawn as thin solid bands interpolated through
    /// `colors` (alpha included), top to bottom. Linear-gradient fills of partial-height rects were
    /// mis-clipped in whole tiles when ImageRenderer rasterised a canvas wider than about 2048 pt
    /// (2560-point snapshots showed staircase blocks in the ground); solid fills are not.
    private func bands(_ ctx: inout GraphicsContext, top: CGFloat, bottom: CGFloat, width: CGFloat, colors: [RGBA]) {
        guard bottom > top, colors.count > 1 else { return }
        // Whole-point bands that abut exactly (translucent bands must not overlap, or seams show).
        let y0 = top.rounded(.down), y1 = bottom.rounded(.up)
        let step: CGFloat = 2
        var y = y0
        while y < y1 {
            let hgt = min(step, y1 - y)
            let t = Double((y + hgt / 2 - y0) / (y1 - y0)) * Double(colors.count - 1)
            let k = max(0, min(colors.count - 2, Int(t)))
            let col = RGBA.lerp(colors[k], colors[k + 1], min(1, max(0, t - Double(k))))
            if col.a > 0.001 { ctx.fill(Path(CGRect(x: 0, y: y, width: width, height: hgt)), with: .color(col.color)) }
            y += hgt
        }
    }

    /// A soft elliptical glow. Drawn with an elliptical gradient in the ellipse's own bounds rather
    /// than a radial gradient under a non-uniform scale: on canvases wider than about 2048 pt the
    /// scaled form rasterised in tiles with whole blocks wrong (2560-point snapshots, CHL-27).
    private func glow(_ ctx: inout GraphicsContext, _ center: CGPoint, _ rx: CGFloat, _ ry: CGFloat, _ color: RGBA, _ alpha: Double) {
        guard alpha > 0.002, rx > 0, ry > 0 else { return }
        let col = color.color
        let rect = CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2)
        let g = Gradient(stops: [.init(color: col.opacity(alpha), location: 0), .init(color: col.opacity(alpha * 0.45), location: 0.35),
                                 .init(color: col.opacity(0), location: 1)])
        ctx.fill(Path(ellipseIn: rect), with: .style(EllipticalGradient(gradient: g, center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)))
    }


    private func constellation(_ ctx: inout GraphicsContext, _ scene: ForestScene, _ cam: CGFloat) {
        let pts = scene.constellation.map { CGPoint(x: $0.x - cam, y: $0.y) }
        guard pts.count == 6 else { return }
        let P = palette.spec, k = P.constellationAlpha
        var lines = Path()
        for (a, b) in [(0, 1), (0, 2), (1, 3), (2, 4), (3, 4)] { lines.move(to: pts[a]); lines.addLine(to: pts[b]) }
        let baseMid = CGPoint(x: (pts[3].x + pts[4].x) / 2, y: (pts[3].y + pts[4].y) / 2)
        lines.move(to: baseMid); lines.addLine(to: pts[5])
        ctx.stroke(lines, with: .color(P.constellation.color.opacity(0.16 * k)), style: StrokeStyle(lineWidth: 0.8, dash: [3, 4]))
        let f = CGFloat((time / 14).truncatingRemainder(dividingBy: 1))
        var walk = Path(); walk.addLines([pts[5], baseMid, pts[3], pts[1], pts[0], pts[2], pts[4], baseMid])
        ctx.stroke(walk.trimmedPath(from: max(0, f - 0.06), to: f), with: .color(P.constellation.color.opacity(0.5 * k)), lineWidth: 1.2)
        for (i, p) in pts.enumerated() {
            let r: CGFloat = i == 0 ? 1.9 : 1.4
            let tw = 0.75 + 0.25 * sin(time * 0.9 + Double(i))
            glow(&ctx, p, r * 7, r * 7, P.star, 0.35 * tw * k)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(P.star.color.opacity(0.95 * tw * k)))
        }
    }

    private func traces(_ ctx: inout GraphicsContext, _ scene: ForestScene, _ cam: CGFloat) {
        var c = ctx
        c.translateBy(x: -cam, y: 0)
        let P = palette.spec
        for t in scene.traces {
            c.stroke(t.path, with: .color(P.trace.color.opacity(P.traceAlpha)), style: StrokeStyle(lineWidth: t.width, lineCap: .round, lineJoin: .round))
            for pad in t.pads {
                let r = 2.2 + t.width
                c.stroke(Path(ellipseIn: CGRect(x: pad.x - r, y: pad.y - r, width: r * 2, height: r * 2)), with: .color(P.trace.color.opacity(P.traceAlpha * 2)), lineWidth: 1)
            }
            guard t.speed > 0 else { continue }
            let f = CGFloat((time * t.speed / 900 + t.phase).truncatingRemainder(dividingBy: 1.35))
            if f <= 1.05 {
                let col = (t.warm ? P.pulseWarm : P.pulse).color
                c.stroke(t.path.trimmedPath(from: max(0, f - 0.16), to: min(1, f)), with: .color(col.opacity(0.12 + 0.12 * (1 - palette.night))),
                         style: StrokeStyle(lineWidth: t.width * 3, lineCap: .butt, lineJoin: .round))
                c.stroke(t.path.trimmedPath(from: max(0, f - 0.09), to: min(1, f)), with: .color(col.opacity(0.8)),
                         style: StrokeStyle(lineWidth: t.width * 1.2, lineCap: .round, lineJoin: .round))
                if f >= 0.98 { for pad in t.pads { glow(&c, pad, 16, 16, t.warm ? P.pulseWarm : P.pulse, 0.6) } }
            }
        }
    }
}
