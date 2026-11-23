import SwiftUI
import SFInstallKit

/// One drawn segment of the storage bar.
struct BarSegment: Identifiable {
    enum Role { case system, macOS, siliconForest, existingSiliconForest, free, other }
    var id: String
    var role: Role
    var size: Int64
    var label: String
    /// For macOS: bytes in use (drawn solid from the left).
    var used: Int64 = 0
    /// For macOS: headroom macOS keeps (drawn hatched after the used part).
    var reserve: Int64 = 0
}

/// Lays segments out across a width: tiny partitions get a minimum width so they stay visible,
/// everything else is proportional.
struct BarLayout {
    var frames: [String: ClosedRange<CGFloat>] = [:]
    var poolRange: ClosedRange<CGFloat> = 0...0

    init(segments: [BarSegment], width: CGFloat, minWidth: CGFloat = 9, gap: CGFloat = 3, poolIDs: Set<String> = []) {
        let total = Double(segments.reduce(0) { $0 + $1.size })
        guard total > 0 else { return }
        let available = width - gap * CGFloat(max(0, segments.count - 1))
        let tiny = segments.filter { CGFloat(Double($0.size) / total) * available < minWidth }
        let tinyBytes = Double(tiny.reduce(0) { $0 + $1.size })
        let rest = available - minWidth * CGFloat(tiny.count)
        var x: CGFloat = 0
        for s in segments {
            let isTiny = tiny.contains { $0.id == s.id }
            let w = isTiny ? minWidth : CGFloat(Double(s.size) / (total - tinyBytes)) * rest
            frames[s.id] = x...(x + w)
            x += w + gap
        }
        let pool = segments.filter { poolIDs.contains($0.id) }.compactMap { frames[$0.id] }
        if let lo = pool.map(\.lowerBound).min(), let hi = pool.map(\.upperBound).max() { poolRange = lo...hi }
    }
}

/// The storage bar of the internal disk, with SiliconForest's share drawn at the size being chosen and
/// an optional draggable divider between macOS and SiliconForest.
struct PartitionBar: View {
    var disk: PhysicalDisk
    var constraints: SizingConstraints?
    /// SiliconForest's total footprint; ignored when `constraints` is nil.
    @Binding var size: Int64
    var stub: Int64 = 2_500_000_000
    var boot: Int64 = 524_288_000
    var editable = true
    var height: CGFloat = 92
    /// Shows the floating size tag above the divider (always on while dragging).
    var showTag = false
    /// When set, draw this disk as-is (no new SiliconForest), e.g. "before" bars.
    var asIs = false
    /// Uninstall preview: this install's partitions are drawn as reclaimed by macOS.
    var reclaim: SiliconForestInstall? = nil

    @Environment(\.theme) private var theme
    @State private var dragging = false
    @State private var hovering = false
    @FocusState private var focused: Bool

    var segments: [BarSegment] {
        var out: [BarSegment] = []
        let layout = disk.layout
        var skipNextFree = false
        for seg in layout {
            switch seg {
            case .free(let o, let s):
                if skipNextFree { skipNextFree = false; continue }
                out.append(BarSegment(id: "free\(o)", role: .free, size: s, label: "Free"))
            case .partition(let p):
                if let reclaim, reclaim.partitions.contains(where: { $0.identifier == p.identifier }) {
                    // folded into macOS below
                    continue
                }
                if !asIs, reclaim == nil, let c = constraints, p.identifier == c.macOSPartition.identifier {
                    let mac = c.macOSSize(for: size)
                    out.append(BarSegment(id: "macos", role: .macOS, size: mac, label: "macOS", used: c.macOSUsed, reserve: c.macOSMinFree))
                    out.append(BarSegment(id: "sf", role: .siliconForest, size: size, label: "SiliconForest"))
                    skipNextFree = c.freeAfterMacOS >= Bytes.mib
                } else if p.content == .appleAPFS, let c = p.container, c.hasMacOSSystem, !p.isSiliconForestStub {
                    var grown = p.size
                    if let reclaim { grown += reclaim.totalBytes + disk.freeAfter(reclaim.partitions.last?.identifier ?? "") }
                    out.append(BarSegment(id: "macos", role: .macOS, size: grown, label: "macOS", used: c.capacityUsed, reserve: 0))
                    if reclaim != nil { skipNextFree = true }
                } else if p.isSiliconForestStub || p.isSiliconForestBoot || p.isSiliconForestRoot {
                    if let last = out.last, last.role == .existingSiliconForest {
                        out[out.count - 1].size += p.size
                    } else {
                        out.append(BarSegment(id: p.identifier, role: .existingSiliconForest, size: p.size, label: p.metadata["sf.installName"] ?? "SiliconForest"))
                    }
                } else {
                    out.append(BarSegment(id: p.identifier, role: .system, size: p.size,
                                          label: p.content == .appleAPFSRecovery ? "Recovery" : p.content == .appleAPFSISC ? "System" : (p.name ?? p.content.rawValue)))
                }
            }
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let segs = segments
            let layout = BarLayout(segments: segs, width: geo.size.width, poolIDs: ["macos", "sf"])
            let dividerX = layout.frames["macos"]?.upperBound ?? 0
            ZStack(alignment: .topLeading) {
                ForEach(segs) { seg in
                    if let f = layout.frames[seg.id] {
                        segmentView(seg, width: f.upperBound - f.lowerBound)
                            .frame(width: f.upperBound - f.lowerBound, height: height)
                            .offset(x: f.lowerBound)
                    }
                }
                if editable, constraints != nil, !asIs, reclaim == nil {
                    divider
                        .position(x: dividerX + 1.5, y: height / 2)
                        .gesture(dragGesture(layout: layout, width: geo.size.width))
                    if showTag || dragging || hovering || focused {
                        tag.position(x: min(max(dividerX, 120), geo.size.width - 120), y: -30)
                            .transition(.opacity.combined(with: .offset(y: 4)))
                    }
                }
            }
            .frame(height: height)
        }
        .frame(height: height)
        .modifier(AdjustableSize(enabled: editable && constraints != nil && !asIs, size: $size, constraints: constraints, focused: $focused))
    }

    // MARK: segments

    @ViewBuilder
    private func segmentView(_ seg: BarSegment, width: CGFloat) -> some View {
        let r: CGFloat = 14
        let shape = RoundedRectangle(cornerRadius: width < 24 ? 5 : r, style: .continuous)
        switch seg.role {
        case .macOS:
            ZStack(alignment: .leading) {
                shape.fill(LinearGradient(colors: [theme.macOS.opacity(theme.isDark ? 0.34 : 0.3), theme.macOS.opacity(theme.isDark ? 0.2 : 0.18)], startPoint: .top, endPoint: .bottom))
                // used, then the headroom macOS keeps
                GeometryReader { g in
                    let usedW = g.size.width * CGFloat(Double(seg.used) / Double(max(seg.size, 1)))
                    let resW = g.size.width * CGFloat(Double(seg.reserve) / Double(max(seg.size, 1)))
                    HStack(spacing: 0) {
                        Rectangle().fill(theme.macOSGradient).frame(width: min(g.size.width, usedW))
                        ZStack {
                            Rectangle().fill(theme.macOS.opacity(0.32))
                            Hatch(spacing: 6).stroke(theme.macOS.opacity(0.55), lineWidth: 1).clipped()
                        }
                        .frame(width: max(0, min(g.size.width - usedW, resW)))
                    }
                }
                .clipShape(shape)
                // sheen
                shape.fill(LinearGradient(colors: [Color.white.opacity(theme.isDark ? 0.14 : 0.3), .clear], startPoint: .top, endPoint: .center))
                if width > 150 {
                    segmentLabel(icon: "laptopcomputer", title: "Macintosh HD", value: Bytes.format(seg.size), dark: false)
                        .padding(.leading, 16)
                }
            }
            .overlay(shape.strokeBorder(theme.macOS.opacity(0.65), lineWidth: 1))
        case .siliconForest:
            ZStack(alignment: .leading) {
                shape.fill(theme.siliconForestGradient)
                // stub | boot | root separators
                GeometryReader { g in
                    let stubW = max(3, g.size.width * CGFloat(Double(stub) / Double(max(seg.size, 1))))
                    let bootW = max(3, g.size.width * CGFloat(Double(boot) / Double(max(seg.size, 1))))
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.white.opacity(0.28)).frame(width: stubW)
                        Rectangle().fill(Color.black.opacity(0.25)).frame(width: 1)
                        Rectangle().fill(Color.white.opacity(0.14)).frame(width: bootW)
                        Rectangle().fill(Color.black.opacity(0.25)).frame(width: 1)
                        Spacer(minLength: 0)
                    }
                }
                .clipShape(shape)
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center))
                if width > 150 {
                    HStack(spacing: 9) {
                        BrandMark(tiers: AnyShapeStyle(theme.isDark ? Color(hex: 0x04170F) : Color.white), traces: theme.isDark ? Color(hex: 0x04170F) : Color.white)
                            .frame(height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("SiliconForest").font(.system(size: 13, weight: .semibold))
                            Text(Bytes.format(seg.size)).font(Typo.number(12, weight: .medium)).opacity(0.75)
                        }
                    }
                    .foregroundStyle(theme.isDark ? Color(hex: 0x04170F) : .white)
                    .padding(.leading, 18)
                }
            }
            .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            .shadow(color: theme.mint.opacity(theme.isDark ? 0.45 : 0.2), radius: 14)
        case .existingSiliconForest:
            ZStack(alignment: .leading) {
                shape.fill(theme.mint.opacity(0.3))
                Hatch(spacing: 7).stroke(theme.mint.opacity(0.5), lineWidth: 1).clipShape(shape)
                if width > 120 { segmentLabel(icon: "sf.mark", title: seg.label, value: Bytes.format(seg.size), dark: false).padding(.leading, 14) }
            }
            .overlay(shape.strokeBorder(theme.mint.opacity(0.7), lineWidth: 1))
        case .free:
            shape.strokeBorder(theme.textTertiary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        case .system, .other:
            shape.fill(theme.system.opacity(theme.isDark ? 0.55 : 0.5))
                .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
    }

    private func segmentLabel(icon: String, title: String, value: String, dark: Bool) -> some View {
        HStack(spacing: 9) {
            Glyph(symbol: icon, size: 15, color: .white)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(value).font(Typo.number(12, weight: .medium)).opacity(0.8)
            }
        }
        .foregroundStyle(Color.white)
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }

    // MARK: divider

    private var divider: some View {
        let active = dragging || focused
        return ZStack {
            Capsule().fill(Color.white).frame(width: 3, height: height + 22)
                .shadow(color: .black.opacity(0.35), radius: 3)
            Circle().fill(Color.white).frame(width: 32, height: 32)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                .overlay(Circle().strokeBorder(theme.mint, lineWidth: active ? 3 : 0).padding(-4))
                .shadow(color: theme.mint.opacity(active ? 0.7 : 0), radius: 10)
            Image(systemName: "arrow.left.and.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(hex: 0x16241B))
        }
        .frame(width: 44, height: height + 30)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .accessibilityHidden(true)
    }

    private var tag: some View {
        let mac = constraints.map { $0.macOSSize(for: size) } ?? 0
        return HStack(spacing: 10) {
            HStack(spacing: 5) {
                Circle().fill(theme.macOS).frame(width: 7, height: 7)
                Text("macOS").foregroundStyle(theme.textSecondary)
                Text(Bytes.format(mac)).foregroundStyle(theme.text)
            }
            Rectangle().fill(theme.hairline).frame(width: 1, height: 14)
            HStack(spacing: 5) {
                Circle().fill(theme.mint).frame(width: 7, height: 7)
                Text("SiliconForest").foregroundStyle(theme.textSecondary)
                Text(Bytes.format(size)).foregroundStyle(theme.text)
            }
        }
        .font(Typo.number(12, weight: .semibold))
        .padding(.horizontal, 12).frame(height: 28)
        .background(Capsule().fill(theme.isDark ? Color(hex: 0x0E1B17) : .white).overlay(Capsule().strokeBorder(theme.cardStroke, lineWidth: 1)))
        .shadow(color: theme.shadow, radius: 8, y: 3)
        .fixedSize()
    }

    private func dragGesture(layout: BarLayout, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("partitionBar"))
            .onChanged { v in
                guard let c = constraints else { return }
                if !dragging { withAnimation(.easeOut(duration: 0.15)) { dragging = true } }
                let pool = layout.poolRange
                let frac = Double((v.location.x - pool.lowerBound) / max(1, pool.upperBound - pool.lowerBound))
                let macOS = Int64(Double(c.pool) * min(1, max(0, frac)))
                size = c.snap(c.pool - macOS)
            }
            .onEnded { _ in withAnimation(.easeOut(duration: 0.2)) { dragging = false } }
    }
}

/// Keyboard and VoiceOver control of the size: ←/→ 1 GB, ⇧ 10 GB, Home/End min/max.
struct AdjustableSize: ViewModifier {
    var enabled: Bool
    @Binding var size: Int64
    var constraints: SizingConstraints?
    var focused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        if enabled, let c = constraints {
            content
                .coordinateSpace(name: "partitionBar")
                .focusable()
                .focused(focused)
                .focusEffectDisabled()
                .onKeyPress(keys: [.leftArrow, .rightArrow, .home, .end]) { press in
                    let step = press.modifiers.contains(.shift) ? 10 * Bytes.gb : Bytes.gb
                    withAnimation(.snappy(duration: 0.2)) {
                        switch press.key {
                        // the divider moves left → macOS shrinks → SiliconForest grows
                        case .leftArrow: size = c.snap(size + step)
                        case .rightArrow: size = c.snap(size - step)
                        case .home: size = c.maximum
                        case .end: size = c.minimum
                        default: break
                        }
                    }
                    return .handled
                }
                .accessibilityElement()
                .accessibilityLabel("SiliconForest size")
                .accessibilityValue("\(Bytes.format(size)). macOS keeps \(Bytes.format(c.macOSSize(for: size))).")
                .accessibilityHint("Adjust to choose how much space SiliconForest gets, between \(Bytes.format(c.minimum)) and \(Bytes.format(c.maximum)).")
                .accessibilityAdjustableAction { dir in
                    switch dir {
                    case .increment: size = c.snap(size + 5 * Bytes.gb)
                    case .decrement: size = c.snap(size - 5 * Bytes.gb)
                    @unknown default: break
                    }
                }
        } else {
            content.coordinateSpace(name: "partitionBar")
        }
    }
}

/// The three partitions SiliconForest creates, with their sizes and formats.
struct PartitionBreakdown: View {
    var profile: DeviceProfile
    var size: Int64
    var compact = false
    @Environment(\.theme) private var theme

    var body: some View {
        let p = profile.partitioning
        let root = size - p.stubContainerBytes - p.bootPartition.bytes
        HStack(spacing: compact ? 8 : 12) {
            tile(swatch: Color.white.opacity(0.55), title: "Startup", detail: "APFS · stub macOS + stage 1", value: p.stubContainerBytes)
            tile(swatch: Color.white.opacity(0.3), title: p.bootPartition.name, detail: "\(p.bootPartition.format.uppercased()) · kernel + firmware", value: p.bootPartition.bytes)
            tile(swatch: nil, title: "System", detail: "\(p.rootFilesystem) · SiliconForest + your files", value: root)
        }
        .accessibilityElement(children: .combine)
    }

    private func tile(swatch: Color?, title: String, detail: String, value: Int64) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(theme.siliconForestGradient)
                if let swatch { RoundedRectangle(cornerRadius: 4, style: .continuous).fill(swatch.opacity(0.6)) }
            }
            .frame(width: 6, height: compact ? 26 : 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: compact ? 12.5 : 13, weight: .semibold)).foregroundStyle(theme.text)
                    Text(Bytes.format(value)).font(Typo.number(compact ? 12 : 12.5, weight: .medium)).foregroundStyle(theme.mint)
                }
                if !compact {
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(theme.textTertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, compact ? 8 : 10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.card)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: 1)))
    }
}
