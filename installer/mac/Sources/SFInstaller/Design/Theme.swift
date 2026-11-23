import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: alpha)
    }
}

/// SiliconForest's installer palette. Dark is the Canopy theme (the forest at night, copper light on
/// the horizon); light is Clearing (the forest at dawn). Values follow docs/design/siliconforest-themes.md.
struct Theme {
    let isDark: Bool

    // Text
    var text: Color { isDark ? Color(hex: 0xEEF3EC) : Color(hex: 0x1C2721) }
    var textSecondary: Color { isDark ? Color(hex: 0xA3B3A8) : Color(hex: 0x4F5C54) }
    var textTertiary: Color { isDark ? Color(hex: 0x6E8176) : Color(hex: 0x7A867E) }

    // Brand
    /// The mark's mint.
    var mint: Color { isDark ? Color(hex: 0x6FDDAA) : Color(hex: 0x2C7A54) }
    var mintBright: Color { isDark ? Color(hex: 0xB6F5CF) : Color(hex: 0x3D9A6C) }
    var mintDeep: Color { isDark ? Color(hex: 0x3FBF8A) : Color(hex: 0x24664A) }
    /// Canopy's one accent: the copper of the horizon.
    var copper: Color { isDark ? Color(hex: 0xE39A62) : Color(hex: 0xB0612C) }
    var coral: Color { isDark ? Color(hex: 0xEF8468) : Color(hex: 0xC4452F) }
    var gold: Color { isDark ? Color(hex: 0xE2B65C) : Color(hex: 0x9A6A00) }

    // Disk colours
    var macOS: Color { isDark ? Color(hex: 0x7E9CC4) : Color(hex: 0x5B7DA8) }
    var macOSDeep: Color { isDark ? Color(hex: 0x4E6B93) : Color(hex: 0x3F5F88) }
    var system: Color { isDark ? Color(hex: 0x5F6B72) : Color(hex: 0x9AA5A0) }

    // Surfaces
    var glassTint: Color { isDark ? Color(hex: 0x0A1713, alpha: 0.58) : Color(hex: 0xFBFCF8, alpha: 0.62) }
    var glassStroke: Color { isDark ? Color.white.opacity(0.10) : Color.white.opacity(0.75) }
    var glassStrokeOuter: Color { isDark ? Color.black.opacity(0.35) : Color(hex: 0x1C2721, alpha: 0.10) }
    var card: Color { isDark ? Color.white.opacity(0.045) : Color.white.opacity(0.55) }
    var cardStroke: Color { isDark ? Color.white.opacity(0.08) : Color(hex: 0x1C2721, alpha: 0.08) }
    var hairline: Color { isDark ? Color.white.opacity(0.09) : Color(hex: 0x1C2721, alpha: 0.10) }
    var well: Color { isDark ? Color.black.opacity(0.28) : Color(hex: 0x1C2721, alpha: 0.05) }
    var shadow: Color { isDark ? Color(hex: 0x010403, alpha: 0.6) : Color(hex: 0x16241B, alpha: 0.18) }

    /// Text on the primary (mint) button.
    var onAccent: Color { isDark ? Color(hex: 0x04170F) : .white }

    var primaryGradient: LinearGradient {
        isDark
            ? LinearGradient(colors: [Color(hex: 0x9AF2C6), Color(hex: 0x4CC994)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(hex: 0x3E9E70), Color(hex: 0x2A7350)], startPoint: .top, endPoint: .bottom)
    }

    var siliconForestGradient: LinearGradient {
        isDark
            ? LinearGradient(colors: [Color(hex: 0x8DEDBE), Color(hex: 0x37B47F)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(hex: 0x4FB083), Color(hex: 0x2C7A54)], startPoint: .top, endPoint: .bottom)
    }

    var macOSGradient: LinearGradient {
        LinearGradient(colors: [macOS, macOSDeep], startPoint: .top, endPoint: .bottom)
    }
}

private struct ThemeKey: EnvironmentKey { static let defaultValue = Theme(isDark: true) }
private struct SnapshotKey: EnvironmentKey { static let defaultValue = false }
private struct BackdropTimeKey: EnvironmentKey { static let defaultValue: Double? = nil }
private struct ScreenSizeKey: EnvironmentKey { static let defaultValue = CGSize(width: 1440, height: 900) }

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
    /// True when rendering offscreen for `--snapshot`: native-backed controls are swapped for pure
    /// SwiftUI equivalents that look the same.
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

/// Type scale. SF Pro throughout; numbers use tabular figures.
enum Typo {
    static let hero = Font.system(size: 60, weight: .light)
    static let display = Font.system(size: 31, weight: .semibold)
    static let title = Font.system(size: 22, weight: .semibold)
    static let headline = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 14.5, weight: .regular)
    static let subtitle = Font.system(size: 15.5, weight: .regular)
    static let callout = Font.system(size: 13, weight: .regular)
    static let caption = Font.system(size: 12, weight: .medium)
    static let micro = Font.system(size: 10.5, weight: .semibold)
    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}
