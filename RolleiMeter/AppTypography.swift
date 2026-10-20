import CoreText
import SwiftUI

enum AppTypography {
    private static let regularName = "AppleGaramond"
    private static let boldName = "AppleGaramond-Bold"

    static func registerBundledFonts() {
        let available = CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []
        for name in [regularName, boldName] {
            guard !available.contains(name) else { continue }
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                assertionFailure("Missing bundled font: \(name).ttf")
                continue
            }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let isBold = weight == .bold || weight == .semibold || weight == .heavy || weight == .black
        let name = isBold ? boldName : regularName
        return .custom(name, size: size, relativeTo: .body)
    }

    static func regular(size: CGFloat) -> Font { font(size: size) }
    static func bold(size: CGFloat) -> Font { font(size: size, weight: .bold) }
}
