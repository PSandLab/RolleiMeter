import SwiftUI
import UIKit

/// Refined dark optical palette designed for iOS Liquid Glass surfaces.
enum Palette {
    static let background = Color(red: 0.035, green: 0.039, blue: 0.047)       // #090A0C
    static let bg = Color(red: 0.035, green: 0.039, blue: 0.047)
    static let panel = Color(red: 0.090, green: 0.098, blue: 0.114)            // #17191D
    static let panelRaised = Color(red: 0.129, green: 0.141, blue: 0.165)      // #21242A
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let groupedCell = Color(uiColor: .secondarySystemGroupedBackground)

    static let text = Color(red: 0.957, green: 0.965, blue: 0.980)             // #F4F6FA
    static let textSub = Color(red: 0.620, green: 0.655, blue: 0.710)          // #9EA7B5
    static let textDim = Color(red: 0.435, green: 0.471, blue: 0.529)          // #6F7887
    static let dim = Color(red: 0.435, green: 0.471, blue: 0.529)
    static let faint = Color(red: 0.220, green: 0.243, blue: 0.282)            // #383E48
    static let border = Color.white.opacity(0.08)

    static let accent = Color(red: 0.961, green: 0.663, blue: 0.161)           // #F5A929
    static let accentInk = Color(red: 0.055, green: 0.059, blue: 0.067)
    static let onAccent = Color(red: 0.055, green: 0.059, blue: 0.067)

    static let good = Color(red: 0.220, green: 0.835, blue: 0.475)             // #38D579
    static let slow = Color(red: 0.980, green: 0.580, blue: 0.240)             // #FA943D
    static let bad = Color(red: 0.965, green: 0.290, blue: 0.290)              // #F64A4A

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
