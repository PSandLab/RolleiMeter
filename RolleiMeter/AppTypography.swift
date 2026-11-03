import SwiftUI

/// The meter screen's type ramp. Sizes are multiplied by the grid's `k` by the
/// callers, so these stay fixed rather than scaling with Dynamic Type — the
/// instrument has to fit the same cells at every screen width.
enum AppTypography {
    /// Measurement numerals: Geist Mono.
    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Geist.mono(size, weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Geist.mono(size, weight)
    }

    /// Interface copy: Geist Sans.
    static func next(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Geist.sans(size, weight)
    }

    static func label(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Geist.sans(size, weight)
    }

    /// Readouts that have always been drawn in the mono face.
    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        mono(size: size, weight: weight)
    }

    static func regular(size: CGFloat) -> Font { next(size: size) }
    static func bold(size: CGFloat) -> Font { next(size: size, weight: .bold) }
}
