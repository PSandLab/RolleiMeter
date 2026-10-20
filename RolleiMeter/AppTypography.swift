import CoreText
import SwiftUI

enum AppTypography {
    private static let monoResource = "AtkinsonHyperlegibleMono"
    private static let nextResource = "AtkinsonHyperlegibleNext"
    private static let monoPostScriptName = "AtkinsonHyperlegibleMono-ExtraLight"
    private static let nextPostScriptName = "AtkinsonHyperlegibleNext-Regular"

    static func registerBundledFonts() {
        let available = CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []
        for (resource, postScriptName) in [
            (monoResource, monoPostScriptName),
            (nextResource, nextPostScriptName)
        ] {
            guard !available.contains(postScriptName) else { continue }
            guard let url = Bundle.main.url(forResource: resource, withExtension: "ttf") else {
                assertionFailure("Missing bundled font: \(resource).ttf")
                continue
            }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }

    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(monoPostScriptName, size: size, relativeTo: .body).weight(weight)
    }

    static func next(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(nextPostScriptName, size: size, relativeTo: .body).weight(weight)
    }

    // Keep existing measurement styles monospaced; interface copy uses `next`.
    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        mono(size: size, weight: weight)
    }

    static func regular(size: CGFloat) -> Font { next(size: size) }
    static func bold(size: CGFloat) -> Font { mono(size: size, weight: .bold) }
}
