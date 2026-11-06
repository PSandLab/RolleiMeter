import SwiftUI
import UIKit

/// Industrial dark-mode palette matching the original concept render.
enum Palette {
    static let background = Color(red: 0.020, green: 0.020, blue: 0.024)       // #050506
    static let bg = Color(red: 0.020, green: 0.020, blue: 0.024)
    static let panel = Color(red: 0.078, green: 0.078, blue: 0.086)            // #141416
    static let panelRaised = Color(red: 0.118, green: 0.118, blue: 0.129)      // #1E1E21
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let groupedCell = Color(uiColor: .secondarySystemGroupedBackground)

    static let text = Color(red: 0.949, green: 0.949, blue: 0.961)             // #F2F2F5
    static let textSub = Color(red: 0.557, green: 0.557, blue: 0.576)          // #8E8E93
    static let textDim = Color(red: 0.420, green: 0.420, blue: 0.443)          // #6B6B71
    static let dim = Color(red: 0.420, green: 0.420, blue: 0.443)
    static let faint = Color(red: 0.220, green: 0.220, blue: 0.239)            // #38383D
    static let border = Color.white.opacity(0.06)

    // Signature Kodak/Rollei Yellow from the concept render
    static let accent = Color(red: 0.969, green: 0.776, blue: 0.000)           // #F7C600
    static let accentInk = Color(red: 0.078, green: 0.078, blue: 0.086)        // #141416
    static let onAccent = Color(red: 0.078, green: 0.078, blue: 0.086)

    static let good = Color(red: 0.204, green: 0.827, blue: 0.451)
    static let slow = Color(red: 0.969, green: 0.776, blue: 0.000)
    static let bad = Color(red: 0.961, green: 0.231, blue: 0.231)

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
