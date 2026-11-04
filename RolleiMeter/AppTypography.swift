import SwiftUI

/// System Dynamic Type ramp for meter readouts and labels.
enum AppTypography {
    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 50...: return .largeTitle
        case 34..<50: return .title
        case 26..<34: return .title2
        case 21..<26: return .title3
        case 17..<21: return .headline
        case 15..<17: return .subheadline
        case 13..<15: return .footnote
        case 11.5..<13: return .caption
        default: return .caption2
        }
    }

    static func next(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(textStyle(for: size)).weight(weight)
    }

    static func label(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        next(size: size, weight: weight)
    }

    static func numeral(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(textStyle(for: size)).weight(weight).monospacedDigit()
    }

    static func regular(size: CGFloat) -> Font { next(size: size) }
    static func bold(size: CGFloat) -> Font { next(size: size, weight: .bold) }
}
