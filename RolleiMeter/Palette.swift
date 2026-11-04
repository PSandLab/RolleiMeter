import SwiftUI
import UIKit

/// Semantic color tokens mapping directly to system colors.
enum Palette {
    static let background = Color(uiColor: .systemBackground)
    static let bg = Color(uiColor: .systemBackground)
    static let panel = Color(uiColor: .secondarySystemBackground)
    static let panelRaised = Color(uiColor: .tertiarySystemBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let groupedCell = Color(uiColor: .secondarySystemGroupedBackground)

    static let text = Color(uiColor: .label)
    static let textSub = Color(uiColor: .secondaryLabel)
    static let textDim = Color(uiColor: .tertiaryLabel)
    static let dim = Color(uiColor: .tertiaryLabel)
    static let faint = Color(uiColor: .quaternaryLabel)
    static let border = Color(uiColor: .separator)

    static let accent = Color.accentColor
    static let accentInk = Color.black
    static let onAccent = Color.black

    static let good = Color(uiColor: .systemGreen)
    static let slow = Color(uiColor: .systemOrange)
    static let bad = Color(uiColor: .systemRed)

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
