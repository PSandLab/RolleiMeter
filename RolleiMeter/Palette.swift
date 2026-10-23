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

/// One dark palette. Black body, near-black panels, white type, a single yellow accent.
/// Green / orange / red are reserved for exposure and focus state.
enum Palette {
    static let background = Color.black
    static let panel = Color(hex: 0x111111)
    static let panelRaised = Color(hex: 0x1A1A1A)

    static let text = Color.white
    static let dim = Color(hex: 0x6E6E6E)
    static let faint = Color(hex: 0x3A3A3A)

    /// The yellow on the active film card, the EV marker and the metered shutter speed.
    static let accent = Color(hex: 0xFFC800)
    /// Dark brown-black inset used inside the yellow film card.
    static let accentInk = Color(hex: 0x1C1608)

    static let good = Color(hex: 0x3DDC6B)
    static let slow = Color(hex: 0xFF9500)
    static let bad = Color(hex: 0xFF453A)

    /// Marks drawn over the live image.
    static let lensLight = Color(hex: 0xF1EEE6)
    static let lensDark = Color(hex: 0x262626)
}
