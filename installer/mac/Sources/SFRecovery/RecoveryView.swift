import AppKit
import CoreText

/// SFRecovery's one screen (DESIGN §7.4): the Grove as a still, the mark, one title, the owner's
/// password, and two buttons. AppKit and Core Graphics only (§7.3: no SwiftUI in recoveryOS 13.5).
final class RecoveryView: NSView {
    enum Stage { case password, working(step: Int), failed(String), notRecovery }

    var stage: Stage = .password { didSet { rebuild() } }
    var ownerName = "Chris"
    var onContinue: ((Data) -> Void)?
    var onShutDown: (() -> Void)?

    private let title = NSTextField(labelWithString: "")
    private let lead = NSTextField(wrappingLabelWithString: "")
    private let passwordLabel = NSTextField(labelWithString: "")
    let password = NSSecureTextField()
    private let note = NSTextField(wrappingLabelWithString: "")
    private let primary = NSButton()
    private let secondary = NSButton()
    private var rows: [NSTextField] = []

    static let steps = ["Checking this recovery system", "Allowing SiliconForest to start", "Installing the startup software", "Finishing up"]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        Fonts.register()
        for v in [title, lead, passwordLabel, password, note, primary, secondary] as [NSView] { addSubview(v) }
        title.font = Fonts.inter(40, .semibold); title.textColor = Palette.text
        lead.font = Fonts.inter(17, .regular); lead.textColor = Palette.textSecondary
        passwordLabel.font = Fonts.inter(13, .semibold); passwordLabel.textColor = Palette.textSecondary
        note.font = Fonts.inter(13, .regular); note.textColor = Palette.textSecondary
        password.font = Fonts.inter(17, .regular); password.bezelStyle = .roundedBezel
        password.placeholderString = "Password"
        for b in [primary, secondary] { b.bezelStyle = .rounded; b.controlSize = .large; b.font = Fonts.inter(15, .semibold) }
        primary.keyEquivalent = "\r"
        primary.bezelColor = NSColor(srgbRed: 0xDD / 255, green: 0x8F / 255, blue: 0x55 / 255, alpha: 1)   // copper, VISUAL §3
        primary.target = self; primary.action = #selector(continuePressed)
        secondary.target = self; secondary.action = #selector(shutDownPressed)
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func rebuild() {
        rows.forEach { $0.removeFromSuperview() }; rows = []
        secondary.title = "Shut Down"
        switch stage {
        case .password:
            title.stringValue = "Finish installing SiliconForest"
            lead.stringValue = "Enter the password for \(ownerName) to allow SiliconForest to start on this Mac. This lowers security for SiliconForest only; macOS isn't affected."
            passwordLabel.stringValue = "PASSWORD FOR \(ownerName.uppercased())"
            note.stringValue = "Only this Mac's owner can approve a new operating system. Your password stays on this Mac."
            primary.title = "Allow SiliconForest"; primary.isHidden = false; primary.isEnabled = true
            password.isHidden = false; passwordLabel.isHidden = false
        case .working(let step):
            title.stringValue = "Setting up SiliconForest"
            lead.stringValue = "This takes about a minute. Your Mac restarts into SiliconForest when it's done."
            password.isHidden = true; passwordLabel.isHidden = true; primary.isHidden = true
            note.stringValue = ""
            for (i, s) in Self.steps.enumerated() {
                let mark = i < step ? "✓" : i == step ? "•" : "○"
                let f = NSTextField(labelWithString: "\(mark)  \(s)")
                f.font = Fonts.inter(17, i == step ? .semibold : .regular)
                f.textColor = i <= step ? Palette.text : Palette.textSecondary
                addSubview(f); rows.append(f)
            }
        case .failed(let message):
            title.stringValue = "SiliconForest isn't set up yet"
            lead.stringValue = message
            passwordLabel.stringValue = "PASSWORD FOR \(ownerName.uppercased())"
            note.stringValue = "Nothing else was changed. You can try again, or choose Utilities → Terminal to finish in Terminal."
            primary.title = "Try Again"; primary.isHidden = false
            password.isHidden = false; passwordLabel.isHidden = false
        case .notRecovery:
            title.stringValue = "Open this from recoveryOS"
            lead.stringValue = "SiliconForest Setup runs in SiliconForest's own recovery. Shut down, then hold the power button until you see startup options, and choose SiliconForest."
            password.isHidden = true; passwordLabel.isHidden = true; primary.isHidden = true
            note.stringValue = "Nothing was changed."
        }
        needsLayout = true; needsDisplay = true
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        let column = min(640, w - 96)
        let x = (w - column) / 2
        var y = max(64, h * 0.22)
        y += 96 + 28   // the mark (drawn) above the title
        title.frame = NSRect(x: x, y: y, width: column, height: 50); y += 62
        let leadH = lead.sizeThatFits(NSSize(width: column, height: 400)).height
        lead.frame = NSRect(x: x, y: y, width: column, height: leadH); y += leadH + 30
        if !password.isHidden {
            passwordLabel.frame = NSRect(x: x, y: y, width: column, height: 18); y += 24
            password.frame = NSRect(x: x, y: y, width: 360, height: 32); y += 52
        }
        for r in rows { r.frame = NSRect(x: x, y: y, width: column, height: 26); y += 34 }
        let noteH = note.sizeThatFits(NSSize(width: column, height: 200)).height
        note.frame = NSRect(x: x, y: y, width: column, height: noteH)
        let by = h - 88
        primary.sizeToFit(); secondary.sizeToFit()
        primary.frame = NSRect(x: w - 32 - max(180, primary.frame.width + 32), y: by, width: max(180, primary.frame.width + 32), height: 40)
        secondary.frame = NSRect(x: (primary.isHidden ? w - 32 : primary.frame.minX - 12) - (secondary.frame.width + 28), y: by,
                                 width: secondary.frame.width + 28, height: 40)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        Grove.drawStill(in: ctx, size: bounds.size)
        let w = bounds.width
        let column = min(640, w - 96)
        let markRect = NSRect(x: (w - column) / 2, y: max(64, bounds.height * 0.22), width: 84, height: 96)
        Mark.draw(in: ctx, rect: markRect, color: Palette.mark)
    }

    @objc private func continuePressed() {
        let pw = Data(password.stringValue.utf8)
        password.stringValue = ""
        onContinue?(pw)
    }
    @objc private func shutDownPressed() { onShutDown?() }
}

enum Palette {
    static let text = NSColor(srgbRed: 0xE6 / 255, green: 0xED / 255, blue: 0xE4 / 255, alpha: 1)
    static let textSecondary = NSColor(srgbRed: 0x9A / 255, green: 0xA8 / 255, blue: 0x9D / 255, alpha: 1)
    static let mark = NSColor(srgbRed: 0xA6 / 255, green: 0xF2 / 255, blue: 0xC8 / 255, alpha: 1)
}

/// The Grove as a still (DESIGN §7.4): night sky, a copper horizon, ridges, and conifers drawn from
/// the mark's chevron tiers. Our own artwork, drawn with Core Graphics.
enum Grove {
    static func drawStill(in ctx: CGContext, size: CGSize) {
        let w = size.width, h = size.height
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
            CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 0xff) / 255, CGFloat((hex >> 8) & 0xff) / 255, CGFloat(hex & 0xff) / 255, a])!
        }
        let horizon = h * 0.7
        let sky = CGGradient(colorsSpace: cs, colors: [c(0x020706), c(0x082220), c(0x1A3C38), c(0x8A6A4A)] as CFArray, locations: [0, 0.45, 0.85, 1])!
        ctx.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: horizon), options: [.drawsAfterEndLocation])
        let glow = CGGradient(colorsSpace: cs, colors: [c(0xF0A56A, 0.45), c(0xF0A56A, 0)] as CFArray, locations: [0, 1])!
        ctx.saveGState(); ctx.translateBy(x: w / 2, y: horizon); ctx.scaleBy(x: 1, y: 0.25)
        ctx.drawRadialGradient(glow, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: w * 0.5, options: [])
        ctx.restoreGState()
        // Stars
        var seed: UInt32 = 7
        func rnd() -> CGFloat { seed = seed &* 1_664_525 &+ 1_013_904_223; return CGFloat(seed >> 8) / CGFloat(1 << 24) }
        for _ in 0..<Int(w * h / 9000) {
            let p = CGPoint(x: rnd() * w, y: rnd() * horizon * 0.8), r = 0.5 + rnd() * 1.2
            ctx.setFillColor(c(0xE4FFF0, 0.25 + rnd() * 0.6)); ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        }
        // Ridges and ground
        ctx.setFillColor(c(0x0E2925))
        ctx.beginPath(); ctx.move(to: CGPoint(x: 0, y: horizon - h * 0.02))
        for i in 0...24 { let x = w * CGFloat(i) / 24; ctx.addLine(to: CGPoint(x: x, y: horizon - h * (0.02 + 0.025 * sin(CGFloat(i) * 0.9)))) }
        ctx.addLine(to: CGPoint(x: w, y: h)); ctx.addLine(to: CGPoint(x: 0, y: h)); ctx.fillPath()
        ctx.setFillColor(c(0x050E0C)); ctx.fill(CGRect(x: 0, y: horizon + h * 0.02, width: w, height: h))
        // Treeline and the framing trees
        for i in 0..<60 {
            let x = w * CGFloat(i) / 60 + rnd() * 12, th = h * (0.04 + rnd() * 0.05)
            Mark.tree(in: ctx, base: CGPoint(x: x, y: horizon + h * 0.025), height: th, color: c(0x0B201C))
        }
        for (u, f) in [(0.04, 1.0), (0.13, 0.72), (0.96, 0.95), (0.87, 0.66)] as [(CGFloat, CGFloat)] {
            Mark.tree(in: ctx, base: CGPoint(x: w * u, y: h * 1.02), height: h * 0.9 * f, color: c(0x020706))
        }
        // A scrim under the text column keeps it at 4.5:1.
        let scrim = CGGradient(colorsSpace: cs, colors: [c(0x030807, 0), c(0x030807, 0.45), c(0x030807, 0)] as CFArray, locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(scrim, start: CGPoint(x: w * 0.2, y: 0), end: CGPoint(x: w * 0.8, y: 0), options: [])
    }
}

/// The mark: three chevron tiers on a trunk that forks like a trace.
enum Mark {
    static func tree(in ctx: CGContext, base: CGPoint, height H: CGFloat, color: CGColor) {
        ctx.setFillColor(color)
        let tiers = 5, W = H * 0.42
        for i in 0..<tiers {
            let f = CGFloat(i + 1) / CGFloat(tiers)
            let top = base.y - H + CGFloat(i) * H * 0.17
            let bottom = top + H * 0.3
            let hw = W / 2 * (0.25 + 0.75 * f)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: base.x, y: top))
            ctx.addLine(to: CGPoint(x: base.x + hw, y: bottom)); ctx.addLine(to: CGPoint(x: base.x + hw * 0.35, y: bottom - H * 0.04))
            ctx.addLine(to: CGPoint(x: base.x - hw * 0.35, y: bottom - H * 0.04)); ctx.addLine(to: CGPoint(x: base.x - hw, y: bottom))
            ctx.closePath(); ctx.fillPath()
        }
        ctx.fill(CGRect(x: base.x - max(1, W * 0.025), y: base.y - H * 0.15, width: max(2, W * 0.05), height: H * 0.15))
    }

    static func draw(in ctx: CGContext, rect: NSRect, color: NSColor) {
        let cg = color.cgColor
        ctx.setFillColor(cg)
        let cx = rect.midX, top = rect.minY, tierH = rect.height * 0.3
        for i in 0..<3 {
            let y = top + CGFloat(i) * tierH * 0.8
            let hw = rect.width / 2 * (0.5 + 0.25 * CGFloat(i))
            ctx.beginPath()
            ctx.move(to: CGPoint(x: cx, y: y)); ctx.addLine(to: CGPoint(x: cx + hw, y: y + tierH))
            ctx.addLine(to: CGPoint(x: cx + hw - tierH * 0.45, y: y + tierH)); ctx.addLine(to: CGPoint(x: cx, y: y + tierH * 0.45))
            ctx.addLine(to: CGPoint(x: cx - hw + tierH * 0.45, y: y + tierH)); ctx.addLine(to: CGPoint(x: cx - hw, y: y + tierH))
            ctx.closePath(); ctx.fillPath()
        }
        let trunkTop = top + tierH * 2.2, base = rect.maxY - 8
        ctx.setStrokeColor(cg); ctx.setLineWidth(3)
        ctx.move(to: CGPoint(x: cx, y: trunkTop)); ctx.addLine(to: CGPoint(x: cx, y: base))
        ctx.move(to: CGPoint(x: cx, y: base - 10)); ctx.addLine(to: CGPoint(x: cx - 18, y: base - 2))
        ctx.move(to: CGPoint(x: cx, y: base - 10)); ctx.addLine(to: CGPoint(x: cx + 18, y: base - 2))
        ctx.strokePath()
        for p in [CGPoint(x: cx - 20, y: base - 1), CGPoint(x: cx + 20, y: base - 1), CGPoint(x: cx, y: base + 2)] {
            ctx.fillEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
        }
    }
}

/// Inter from the recovery bundle's Resources (or the source tree's build/fonts when developing).
enum Fonts {
    nonisolated(unsafe) static var registered = false
    static func register() {
        guard !registered else { return }
        registered = true
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        var dirs = [exe.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")]
        dirs.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/fonts"))
        for d in dirs {
            for f in ["Inter-Regular.ttf", "Inter-SemiBold.ttf", "InterDisplay-SemiBold.ttf"] {
                let u = d.appendingPathComponent(f)
                if FileManager.default.fileExists(atPath: u.path) { CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil) }
            }
        }
    }
    static func inter(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let name = weight == .semibold ? (size >= 28 ? "InterDisplay-SemiBold" : "Inter-SemiBold") : "Inter-Regular"
        return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
    }
}
