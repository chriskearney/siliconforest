import SwiftUI
import AppKit
import SFInstallKit
import SFCopy

/// One drawn segment of the disk bar.
public struct BarSegment: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable { case apple, macOSUsed, snapshots, macOSFree, siliconForest, existing, foreign, free }
    public var id: String
    public var kind: Kind
    public var bytes: Int64
    public init(id: String, kind: Kind, bytes: Int64) { self.id = id; self.kind = kind; self.bytes = bytes }
}

/// Builds the segments for each use of the bar (Space, Review now/after, Remove now/after).
public enum DiskBarModel {
    /// The disk as it is.
    public static func current(_ disk: PhysicalDisk) -> [BarSegment] {
        let classes = disk.classify()
        var out: [BarSegment] = []
        for seg in disk.layout {
            switch seg {
            case .free(let o, let s): out.append(.init(id: "free\(o)", kind: .free, bytes: s))
            case .partition(let p):
                switch classes[p.identifier] ?? .unknown {
                case .macOSPrimary:
                    let used = p.container?.capacityUsed ?? p.size
                    out.append(.init(id: "\(p.identifier).used", kind: .macOSUsed, bytes: used))
                    out.append(.init(id: "\(p.identifier).free", kind: .macOSFree, bytes: p.size - used))
                case .sfOwned, .sfPartial, .sfUnproven:
                    if let last = out.last, last.kind == .existing { out[out.count - 1].bytes += p.size }
                    else { out.append(.init(id: p.identifier, kind: .existing, bytes: p.size)) }
                case .appleISC, .appleRecovery: out.append(.init(id: p.identifier, kind: .apple, bytes: p.size))
                default: out.append(.init(id: p.identifier, kind: .foreign, bytes: p.size))
                }
            }
        }
        return out
    }

    /// The disk after installing `siliconForest` bytes.
    public static func after(_ disk: PhysicalDisk, _ c: SizingConstraints, siliconForest: Int64) -> [BarSegment] {
        var out: [BarSegment] = []
        var skipFree = false
        for seg in current(disk) {
            if seg.kind == .free && skipFree { skipFree = false; continue }
            if seg.id == "\(c.macOSPartition.identifier).used" { out.append(seg); continue }
            if seg.id == "\(c.macOSPartition.identifier).free" {
                out.append(.init(id: seg.id, kind: .macOSFree, bytes: c.macOSFree(for: siliconForest)))
                out.append(.init(id: "sf.new", kind: .siliconForest, bytes: siliconForest))
                skipFree = c.freeAfterMacOS >= Bytes.mib
                continue
            }
            out.append(seg)
        }
        return out
    }

    /// The disk after removing an install (its space folded back into macOS when contiguous).
    public static func afterRemoving(_ disk: PhysicalDisk, _ install: SiliconForestInstall) -> [BarSegment] {
        var out: [BarSegment] = []
        let reclaim = install.reclaimableBytes(on: disk)
        var dropFree = false
        for seg in current(disk) {
            if seg.kind == .existing { dropFree = true; continue }
            if dropFree && seg.kind == .free { dropFree = false; continue }
            if seg.kind == .macOSFree { out.append(.init(id: seg.id, kind: .macOSFree, bytes: seg.bytes + reclaim)); continue }
            out.append(seg)
        }
        return out
    }
}

/// The signature control (VISUAL-DESIGN §5): 72 pt, 12 pt radius, real proportions with a 2 pt
/// minimum, a plated-via handle when editable.
public struct DiskBar: View {
    var segments: [BarSegment]
    var height: CGFloat
    /// Editable: the handle sits between macOS free space and SiliconForest's new space.
    var constraints: SizingConstraints?
    @Binding var size: Int64
    var forceActive: Bool
    var onLimit: (SizingConstraints.Limit) -> Void

    @Environment(\.theme) private var theme
    @State private var dragging = false
    @State private var bump: CGFloat = 0
    @FocusState private var focused: Bool

    public init(segments: [BarSegment], height: CGFloat = 72, constraints: SizingConstraints? = nil, size: Binding<Int64> = .constant(0),
                forceActive: Bool = false, onLimit: @escaping (SizingConstraints.Limit) -> Void = { _ in }) {
        self.segments = segments; self.height = height; self.constraints = constraints; self._size = size
        self.forceActive = forceActive; self.onLimit = onLimit
    }

    public var body: some View {
        GeometryReader { geo in
            let frames = Self.layout(segments, width: geo.size.width)
            let handleX = frames["sf.new"]?.lowerBound
            ZStack(alignment: .topLeading) {
                ForEach(segments) { s in
                    if let f = frames[s.id] {
                        segment(s, width: f.upperBound - f.lowerBound)
                            .frame(width: max(0, f.upperBound - f.lowerBound), height: height)
                            .offset(x: f.lowerBound)
                    }
                }
                if let c = constraints, let x = handleX, !c.rootLocked {
                    handle
                        .position(x: x - 1 + bump, y: height / 2)
                        .gesture(drag(frames: frames, width: geo.size.width, c: c))
                }
            }
        }
        .frame(height: height)
        .modifier(BarAccessibility(constraints: constraints, size: $size, focused: $focused, onLimit: onLimit, bump: bumpAnimation))
    }

    /// Proportional layout, tiny segments at least 2 pt, 2 pt gaps.
    public static func layout(_ segs: [BarSegment], width: CGFloat, gap: CGFloat = 2, minWidth: CGFloat = 2) -> [String: ClosedRange<CGFloat>] {
        let total = Double(segs.reduce(0) { $0 + $1.bytes })
        guard total > 0 else { return [:] }
        let avail = width - gap * CGFloat(max(0, segs.count - 1))
        let tiny = Set(segs.filter { CGFloat(Double($0.bytes) / total) * avail < minWidth }.map(\.id))
        let tinyBytes = Double(segs.filter { tiny.contains($0.id) }.reduce(0) { $0 + $1.bytes })
        let rest = avail - minWidth * CGFloat(tiny.count)
        var x: CGFloat = 0
        var out: [String: ClosedRange<CGFloat>] = [:]
        for s in segs {
            let w = tiny.contains(s.id) ? minWidth : CGFloat(Double(s.bytes) / (total - tinyBytes)) * rest
            out[s.id] = x...(x + w)
            x += w + gap
        }
        return out
    }

    @ViewBuilder private func segment(_ s: BarSegment, width: CGFloat) -> some View {
        let r: CGFloat = width < 20 ? min(4, width / 2) : 12
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        switch s.kind {
        case .macOSUsed:
            shape.fill(theme.barMacUsed)
                .overlay(shape.fill(LinearGradient(colors: [Color.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center)))
        case .snapshots:
            shape.fill(theme.barSnapshots.opacity(0.35)).overlay(Hatch(spacing: 5).stroke(theme.barSnapshots, lineWidth: 1.2).clipShape(shape))
        case .macOSFree:
            shape.fill(theme.barMacFree.opacity(theme.isDark ? 0.55 : 0.6)).overlay(shape.strokeBorder(theme.barMacUsed.opacity(0.6), lineWidth: 1))
        case .siliconForest:
            shape.fill(theme.barSiliconForest)
                .overlay(TracePattern().stroke(theme.onAccent.opacity(0.22), lineWidth: 1).clipShape(shape))
                .overlay(shape.fill(LinearGradient(colors: [Color.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center)))
                .shadow(color: theme.accent.opacity(theme.isDark ? 0.45 : 0.25), radius: 12)
        case .existing:
            shape.fill(theme.barSiliconForest.opacity(0.35))
                .overlay(TracePattern().stroke(theme.barSiliconForest.opacity(0.8), lineWidth: 1).clipShape(shape))
                .overlay(shape.strokeBorder(theme.barSiliconForest, lineWidth: 1))
        case .apple:
            shape.fill(theme.barApple)
        case .foreign:
            shape.fill(theme.barApple.opacity(0.6)).overlay(Hatch(spacing: 4).stroke(theme.textSecondary.opacity(0.4), lineWidth: 1).clipShape(shape))
        case .free:
            shape.strokeBorder(theme.textTertiary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }

    /// A 28 pt plated via: an accent ring around a dark hole, 44 pt hit target.
    private var handle: some View {
        let active = dragging || focused || forceActive
        return ZStack {
            Circle().fill(theme.isDark ? Color(hex: 0x0A120F) : Color(hex: 0x1F2A24))
            Circle().strokeBorder(active ? theme.accent.opacity(1) : theme.accent.opacity(0.9), lineWidth: active ? 5 : 4.5)
            Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75).padding(1)
            Circle().fill(Color.white.opacity(0.08)).padding(9)
        }
        .frame(width: 28, height: 28)
        .scaleEffect(active ? 1.08 : 1)
        .shadow(color: theme.accent.opacity(active ? 0.8 : 0.4), radius: active ? 12 : 6)
        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .onHover { h in if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
        .accessibilityHidden(true)
    }

    private func drag(frames: [String: ClosedRange<CGFloat>], width: CGFloat, c: SizingConstraints) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("diskbar"))
            .onChanged { v in
                if !dragging { withAnimation(.easeOut(duration: 0.15)) { dragging = true } }
                // Map x across the pool (macOS + adjacent free + new space) back to bytes.
                let poolIDs = ["\(c.macOSPartition.identifier).used", "\(c.macOSPartition.identifier).free", "sf.new"]
                let fs = poolIDs.compactMap { frames[$0] }
                guard let lo = fs.map(\.lowerBound).min(), let hi = fs.map(\.upperBound).max() else { return }
                let frac = Double((v.location.x - lo) / max(1, hi - lo))
                let requested = c.pool - Int64(Double(c.pool) * frac)
                let limit = c.limit(for: requested)
                size = c.snap(requested)
                onLimit(limit)
                if limit != .none { bumpAnimation(limit == .macOSReserve ? -1 : 1) }
            }
            .onEnded { _ in withAnimation(.easeOut(duration: 0.2)) { dragging = false } }
    }

    /// Hard stop: a critically damped bump (and a haptic on Force Touch trackpads).
    private func bumpAnimation(_ dir: CGFloat) {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        withAnimation(.easeOut(duration: 0.06)) { bump = 4 * dir }
        withAnimation(SFMotion.bump.delay(0.06)) { bump = 0 }
    }
}

/// Fine circuit-trace pattern for the SiliconForest segment (a non-colour cue).
struct TracePattern: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var y = rect.minY + 12
        var row = 0
        while y < rect.maxY - 6 {
            var x = rect.minX + CGFloat((row * 23) % 37) - 20
            while x < rect.maxX {
                p.move(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x + 18, y: y))
                p.addLine(to: CGPoint(x: x + 26, y: y - 8))
                p.addLine(to: CGPoint(x: x + 44, y: y - 8))
                p.addEllipse(in: CGRect(x: x + 44, y: y - 10.5, width: 5, height: 5))
                x += 64
            }
            y += 20; row += 1
        }
        return p
    }
}

/// Arrow keys (1 GB; Shift for 10 GB), Home/End, VoiceOver adjustable.
struct BarAccessibility: ViewModifier {
    var constraints: SizingConstraints?
    @Binding var size: Int64
    var focused: FocusState<Bool>.Binding
    var onLimit: (SizingConstraints.Limit) -> Void
    var bump: (CGFloat) -> Void

    func body(content: Content) -> some View {
        if let c = constraints, !c.rootLocked {
            content
                .coordinateSpace(name: "diskbar")
                .focusable()
                .focused(focused)
                .sfFocusEffectDisabled()
                .onMoveCommand { dir in
                    let step = NSEvent.modifierFlags.contains(.shift) ? 10 * Bytes.gb : Bytes.gb
                    // The handle moves left → macOS shrinks → SiliconForest grows.
                    let requested: Int64 = dir == .left ? size + step : dir == .right ? size - step : size
                    let limit = c.limit(for: requested)
                    withAnimation(SFMotion.numbers) { size = c.snap(requested) }
                    onLimit(limit)
                    if limit != .none { bump(limit == .macOSReserve ? -1 : 1) }
                }
                .accessibilityElement()
                .accessibilityLabel("SiliconForest size")
                .accessibilityValue(Copy.Space.voiceOver(sf: size, mac: c.macOSSize(for: size)))
                .accessibilityAdjustableAction { d in
                    withAnimation(SFMotion.numbers) { size = c.snap(size + (d == .increment ? 1 : -1) * 5 * Bytes.gb) }
                }
        } else {
            content.coordinateSpace(name: "diskbar")
        }
    }
}
