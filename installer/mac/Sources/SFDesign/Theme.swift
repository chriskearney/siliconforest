import SwiftUI
import CoreText
import SFInstallKit

public extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: alpha)
    }
}

/// Design tokens, unchanged from the desktop themes (VISUAL-DESIGN §3): Canopy (dark) and
/// Clearing (light). One accent per screen: copper at night, moss by day.
public struct Theme: Sendable {
    public let isDark: Bool
    public init(isDark: Bool) { self.isDark = isDark }

    public var surfaceRaised: Color { isDark ? Color(hex: 0x17221D) : Color(hex: 0xE9EDE5) }
    public var surfaceBase: Color { isDark ? Color(hex: 0x111A16) : Color(hex: 0xFBFCF9) }
    public var text: Color { isDark ? Color(hex: 0xE6EDE4) : Color(hex: 0x1F2A24) }
    public var textSecondary: Color { isDark ? Color(hex: 0x9AA89D) : Color(hex: 0x56625A) }
    public var textTertiary: Color { isDark ? Color(hex: 0x9AA89D, alpha: 0.7) : Color(hex: 0x56625A, alpha: 0.75) }
    public var hairline: Color { isDark ? Color(hex: 0x2E3D35) : Color(hex: 0xB9C3B8) }
    public var accent: Color { isDark ? Color(hex: 0xDD8F55) : Color(hex: 0x2C7A54) }
    public var onAccent: Color { isDark ? Color(hex: 0x1A120B) : .white }
    public var selection: Color { isDark ? Color(hex: 0x2B3D33) : Color(hex: 0xCFE6D8) }
    public var critical: Color { isDark ? Color(hex: 0xEC7C60) : Color(hex: 0xCF4A3A) }
    public var caution: Color { isDark ? Color(hex: 0xE2B65C) : Color(hex: 0xA87004) }
    public var ok: Color { isDark ? Color(hex: 0x82C98F) : Color(hex: 0x2F8A52) }
    public var mark: Color { isDark ? Color(hex: 0xA6F2C8) : Color(hex: 0x2C7A54) }

    // Disk bar segments (both appearances, with non-colour cues)
    public var barMacUsed: Color { isDark ? Color(hex: 0x9AA89D) : Color(hex: 0x56625A) }
    public var barSnapshots: Color { isDark ? Color(hex: 0xE2B65C) : Color(hex: 0xA87004) }
    public var barMacFree: Color { isDark ? Color(hex: 0x2E3D35) : Color(hex: 0xD8DED5) }
    public var barSiliconForest: Color { accent }
    public var barApple: Color { isDark ? Color(hex: 0x4A5A51) : Color(hex: 0xA4AEA3) }

    /// Dense content panels: surface.base at 88% with a hairline (VISUAL §5).
    public var panelFill: Color { surfaceBase.opacity(0.88) }
    public var shadow: Color { isDark ? Color(hex: 0x010403, alpha: 0.55) : Color(hex: 0x16241B, alpha: 0.14) }
    public var scrim: Color { isDark ? Color(hex: 0x030807) : Color(hex: 0xF4F6F1) }
}

public struct ThemeKey: EnvironmentKey { public static let defaultValue = Theme(isDark: true) }
public struct SnapshotKey: EnvironmentKey { public static let defaultValue = false }
public struct BackdropTimeKey: EnvironmentKey { public static let defaultValue: Double? = nil }
public struct ScreenSizeKey: EnvironmentKey { public static let defaultValue = CGSize(width: 1440, height: 900) }

public extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
    /// Rendering offscreen for `--snapshot`: AppKit-backed controls are swapped for SwiftUI
    /// equivalents that look the same.
    var isSnapshot: Bool {
        get { self[SnapshotKey.self] }
        set { self[SnapshotKey.self] = newValue }
    }
    /// A fixed backdrop time for snapshots; nil animates.
    var backdropTime: Double? {
        get { self[BackdropTimeKey.self] }
        set { self[BackdropTimeKey.self] = newValue }
    }
    var screenSize: CGSize {
        get { self[ScreenSizeKey.self] }
        set { self[ScreenSizeKey.self] = newValue }
    }
}

// MARK: - Type (VISUAL-DESIGN §4)

/// Inter for everything, Source Code Pro for logs. Falls back to SF Pro / SF Mono when the fonts
/// haven't been fetched (scripts/fetch-fonts.sh).
public enum SFType {
    private nonisolated(unsafe) static var registered: Set<String> = []

    /// Registers the bundled fonts for this process. Safe to call more than once.
    public static func registerFonts() {
        let dirs = [Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
                    SourceTree.packageRoot.appendingPathComponent("build/fonts")].compactMap { $0 }
        for dir in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for f in files where f.pathExtension == "ttf" {
                let stem = f.deletingPathExtension().lastPathComponent
                guard !registered.contains(stem) else { continue }
                CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil)
                registered.insert(stem)
            }
            if !registered.isEmpty { return }
        }
    }

    public static var hasInter: Bool { registered.contains("Inter-Regular") }

    public static func inter(_ size: CGFloat, _ weight: Font.Weight, display: Bool = false) -> Font {
        guard hasInter else { return .system(size: size, weight: weight) }
        let name: String
        switch weight {
        case .semibold, .bold, .heavy, .black: name = display ? "InterDisplay-SemiBold" : "Inter-SemiBold"
        case .medium: name = display ? "InterDisplay-Medium" : "Inter-Medium"
        default: name = "Inter-Regular"
        }
        return .custom(name, fixedSize: size)
    }

    public static let display = inter(72, .semibold, display: true)       // 72 / 76, −2.2%
    public static let title = inter(44, .semibold, display: true)         // 44 / 50, −1.8%
    public static let titleCompact = inter(38, .semibold, display: true)  // 13-inch at default scaling
    public static let lead = inter(20, .regular)                          // 20 / 30
    public static let body = inter(15, .regular)                          // 15 / 23
    public static let bodyStrong = inter(15, .semibold)
    public static let label = inter(13, .medium)                          // 13 / 18
    public static let labelStrong = inter(13, .semibold)
    public static let caption = inter(12, .regular)                       // 12 / 16
    public static let button = inter(15, .semibold)
    public static let numerals = inter(28, .semibold, display: true).monospacedDigit()  // 28 / 32
    public static let numeralsLarge = inter(56, .medium, display: true).monospacedDigit()
    public static let micro = inter(11, .semibold)

    public static var log: Font {
        hasInter && registered.contains("SourceCodePro-Regular") ? .custom("SourceCodePro-Regular", fixedSize: 12) : .system(size: 12, design: .monospaced)
    }
    public static func number(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { inter(size, weight, display: size >= 24).monospacedDigit() }

    public static let titleTracking: CGFloat = -0.8    // ≈ −1.8% at 44 pt
    public static let displayTracking: CGFloat = -1.6  // ≈ −2.2% at 72 pt
    public static let leadTracking: CGFloat = -0.08
}

// MARK: - Motion (VISUAL-DESIGN §6)

public enum SFMotion {
    /// Screen to screen: 420 ms ease-out quint.
    public static let screen = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.42)
    /// Shared disk bar: spring, no overshoot.
    public static let bar = Animation.spring(response: 0.52, dampingFraction: 1)
    /// Checklist row resolves: 240 ms ease-out cubic.
    public static let row = Animation.timingCurve(0.33, 1, 0.68, 1, duration: 0.24)
    public static let numbers = Animation.easeOut(duration: 0.2)
    public static let bump = Animation.spring(response: 0.18, dampingFraction: 1)
}
