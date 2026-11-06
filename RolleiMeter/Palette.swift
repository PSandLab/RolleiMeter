import SwiftUI
import UIKit

/// Precision optical-instrument color tokens.
enum Palette {
    // Deep anodized camera chassis & recessed instrument bays
    static let background = Color(red: 0.043, green: 0.047, blue: 0.055)       // #0B0C0E
    static let bg = Color(red: 0.043, green: 0.047, blue: 0.055)
    static let panel = Color(red: 0.082, green: 0.090, blue: 0.106)            // #15171B
    static let panelRaised = Color(red: 0.118, green: 0.129, blue: 0.153)      // #1E2127
    static let panelInset = Color(red: 0.031, green: 0.035, blue: 0.043)       // #08090B
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let groupedCell = Color(uiColor: .secondarySystemGroupedBackground)

    // Engraved paint-fill typography hierarchy
    static let text = Color(red: 0.949, green: 0.961, blue: 0.976)             // #F2F5F9
    static let textSub = Color(red: 0.635, green: 0.671, blue: 0.725)          // #A2ABB9
    static let textDim = Color(red: 0.455, green: 0.490, blue: 0.549)          // #747D8C
    static let dim = Color(red: 0.455, green: 0.490, blue: 0.549)
    static let faint = Color(red: 0.235, green: 0.259, blue: 0.302)            // #3C424D
    static let border = Color.white.opacity(0.09)

    // Warm Rollei Amber accent & status lamps
    static let accent = Color(red: 0.961, green: 0.651, blue: 0.137)           // #F5A623
    static let accentInk = Color(red: 0.055, green: 0.059, blue: 0.067)
    static let onAccent = Color(red: 0.055, green: 0.059, blue: 0.067)

    static let good = Color(red: 0.204, green: 0.827, blue: 0.451)             // #34D373
    static let slow = Color(red: 0.984, green: 0.573, blue: 0.235)             // #FB923C
    static let bad = Color(red: 0.969, green: 0.271, blue: 0.271)              // #F74545

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
