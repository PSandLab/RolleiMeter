import SwiftUI

/// System Dynamic Type typography helpers.
enum SystemText {
    static func style(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        Font.system(style).weight(weight)
    }
}
