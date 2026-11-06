import SwiftUI

/// Clean proportional SF Pro instrument typography scaled by `k`.
enum AppTypography {
    static func next(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: max(9, size), weight: weight, design: .default)
    }

    static func label(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        Font.system(size: max(9, size), weight: weight, design: .default)
    }

    static func numeral(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: max(9, size), weight: weight, design: .default).monospacedDigit()
    }

    static func regular(size: CGFloat) -> Font { next(size: size, weight: .regular) }
    static func bold(size: CGFloat) -> Font { next(size: size, weight: .bold) }
}
