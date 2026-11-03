import SwiftUI

/// Geist (Sans / Mono / Serif) — bundled OFL fonts.
///
/// The meter's fixed-size readouts use the `sans`/`mono`/`serif` helpers so the
/// instrument keeps its `k`-scaled proportions. Everything that lives in a list
/// or a form uses `text(_:_:)`, which scales with Dynamic Type.
enum Geist {
    // MARK: Family names

    private static func postScriptName(_ weight: Font.Weight, mono: Bool) -> String {
        let stem = mono ? "GeistMono" : "Geist"
        switch weight {
        case .ultraLight, .thin, .light:
            return "\(stem)-Regular"
        case .medium:
            return "\(stem)-Medium"
        case .semibold:
            return "\(stem)-SemiBold"
        case .bold, .heavy, .black:
            return "\(stem)-Bold"
        default:
            return "\(stem)-Regular"
        }
    }

    // MARK: Fixed sizes (meter chrome)

    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(postScriptName(weight, mono: false), fixedSize: size)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(postScriptName(weight, mono: true), fixedSize: size)
    }

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        // Geist Serif ships a single Regular cut.
        .custom("GeistSerif-Regular", fixedSize: size)
    }

    // MARK: Dynamic Type (content screens)

    static func text(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .custom(postScriptName(weight, mono: false),
                size: baseSize(style),
                relativeTo: style)
    }

    static func monoText(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .custom(postScriptName(weight, mono: true),
                size: baseSize(style),
                relativeTo: style)
    }

    static func serifText(_ style: Font.TextStyle) -> Font {
        .custom("GeistSerif-Regular", size: baseSize(style), relativeTo: style)
    }

    private static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline: return 17
        case .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }
}
