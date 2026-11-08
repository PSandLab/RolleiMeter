import SwiftUI
import UIKit

/// Adaptive palette: industrial dark and a warm paper-like light mode.
enum Palette {
    private static func dyn(_ l: (CGFloat, CGFloat, CGFloat), _ d: (CGFloat, CGFloat, CGFloat), lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { t in
            let c = t.userInterfaceStyle == .dark ? d : l
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: t.userInterfaceStyle == .dark ? darkAlpha : lightAlpha)
        })
    }

    static let background = dyn((0.925, 0.947, 0.985), (0.020, 0.020, 0.024))
    static let bg = background
    static let panel = dyn((0.975, 0.985, 1.0), (0.078, 0.078, 0.086))
    static let panelRaised = dyn((1, 1, 1), (0.118, 0.118, 0.129))
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let groupedCell = Color(uiColor: .secondarySystemGroupedBackground)

    static let text = dyn((0.059, 0.098, 0.169), (0.949, 0.949, 0.961))
    static let textSub = dyn((0.31, 0.38, 0.49), (0.557, 0.557, 0.576))
    static let textDim = dyn((0.42, 0.49, 0.59), (0.420, 0.420, 0.443))
    static let dim = textDim
    static let faint = dyn((0.77, 0.83, 0.92), (0.220, 0.220, 0.239))
    static let border = dyn((0.10, 0.25, 0.55), (1, 1, 1), lightAlpha: 0.14, darkAlpha: 0.06)

    // Signature Kodak/Rollei Yellow
    static let accent = dyn((0.10, 0.40, 0.88), (0.969, 0.776, 0.000))
    static let accentInk = Color(red: 0.078, green: 0.078, blue: 0.086)
    static let onAccent = dyn((1, 1, 1), (0.078, 0.078, 0.086))

    /// Text drawn on the fixed-dark readout windows (stays light in both modes).
    static let onInk = Color(red: 0.949, green: 0.949, blue: 0.961)

    /// Recessed wells/chambers: near-black in dark mode, soft grey in light mode.
    static let well = dyn((0.855, 0.895, 0.950), (0.035, 0.038, 0.045))
    static let wellDeep = dyn((0.78, 0.84, 0.92), (0.0, 0.0, 0.0), darkAlpha: 0.55)
    static let wellEdge = border

    /// Film readout window: whitish in light mode, near-black in dark mode.
    static let readout = dyn((0.965, 0.980, 1.0), (0.078, 0.078, 0.086))

    static let good = Color(red: 0.204, green: 0.827, blue: 0.451)
    static let slow = accent
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
