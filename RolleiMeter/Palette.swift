import SwiftUI

extension Color {
    /// 0xRRGGBB, sRGB.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue: Double(hex & 0xFF) / 255.0,
                  opacity: opacity)
    }
}

/// Semantic color tokens.
///
/// Everything maps to a system color so the app adapts to Dark Mode,
/// Increase Contrast and Reduce Transparency like a system app. The vintage
/// yellow survives as the single brand accent, declared in the asset catalog
/// (`AccentColor`) instead of being hard-coded in views.
enum Palette {
    // Surfaces
    static let background = Color(uiColor: .systemBackground)
    static let bg = Color(uiColor: .systemBackground)
    static let panel = Color(uiColor: .secondarySystemBackground)
    static let panelRaised = Color(uiColor: .tertiarySystemBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let groupedCell = Color(uiColor: .secondarySystemGroupedBackground)

    // Type
    static let text = Color(uiColor: .label)
    static let textSub = Color(uiColor: .secondaryLabel)
    static let textDim = Color(uiColor: .tertiaryLabel)
    static let dim = Color(uiColor: .tertiaryLabel)
    static let faint = Color(uiColor: .quaternaryLabel)
    static let border = Color(uiColor: .separator)

    /// Metered shutter speed, EV marker and selection states.
    static let accent = Color.accentColor
    /// Text drawn on top of the accent fill (only for high-emphasis buttons).
    static let accentInk = Color(uiColor: .label)
    /// Foreground for content sitting *on* the amber accent fill.
    static let onAccent = Color.black

    static let good = Color(uiColor: .systemGreen)
    static let slow = Color(uiColor: .systemOrange)
    static let bad = Color(uiColor: .systemRed)

    /// Marks drawn over the live camera image, which is always photographic.
    static let lensLight = Color.white
    static let lensDark = Color.black
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

enum Roman {
    private static let numerals = ["0", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
    static func zone(_ z: Int) -> String {
        let idx = z.clamped(to: 0...(numerals.count - 1))
        return numerals[idx]
    }
}
