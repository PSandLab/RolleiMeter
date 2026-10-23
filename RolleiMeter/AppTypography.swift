import SwiftUI

enum AppTypography {
    static func registerBundledFonts() {}

    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func next(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    // Measurement styles use SF Mono; interface copy uses SF Pro
    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        mono(size: size, weight: weight)
    }

    static func regular(size: CGFloat) -> Font { next(size: size) }
    static func bold(size: CGFloat) -> Font { next(size: size, weight: .bold) }
}
