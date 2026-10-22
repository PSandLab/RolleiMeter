import SwiftUI
import UIKit

/// Colours for the "paper" look. Each one has a day and a night variant; the night variant
/// switches in automatically in dim scenes (see `ContentView.updateNight`).
enum Palette {
    private static func rgb(_ v: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255.0,
                green: CGFloat((v >> 8) & 0xFF) / 255.0,
                blue: CGFloat(v & 0xFF) / 255.0,
                alpha: alpha)
    }

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? rgb(dark) : rgb(light)
        })
    }

    static let paper = dynamic(0xF1EEE6, 0x1C1B19)
    static let ink = dynamic(0x262626, 0xE9E5DB)
    static let mutedInk = dynamic(0x8B8982, 0x8E8B83)
    /// Type inside a window. A shade off the body ink and a little warmer, so a column of numbers
    /// reads as print on paper rather than as a screen.
    static let engraved = dynamic(0x3A3833, 0xDCD7CD)
    static let hairline = dynamic(0xD4D0C7, 0x3B3935)
    static let accent = dynamic(0xB32631, 0xE2575F)
    static let green = dynamic(0x4C6B52, 0x86AE8D)
    /// Correct exposure, but too slow to hand-hold. Sits between green and red.
    static let amber = dynamic(0x8F5C15, 0xD8A24E)

    /// Soft top edge light on panels.
    static let highlight = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.06)
            : UIColor(white: 1, alpha: 0.42)
    })

    // MARK: - Depth

    /// A bezel standing proud of the plate: paper lit from the top left.
    static let bezelTop = dynamic(0xF8F5EC, 0x2F2E28)
    static let bezelBottom = dynamic(0xE7E3D7, 0x1E1D1A)
    /// The floor of a sunken window.
    static let well = dynamic(0xEDE9DF, 0x141311)
    /// Soft shadow cast by anything raised off the plate.
    static let cast = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0, alpha: 0.40)
            : UIColor(white: 0.20, alpha: 0.09)
    })

    /// The shadow under the top lip of a recess.
    static let recess = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0, alpha: 0.50)
            : UIColor(white: 0.18, alpha: 0.13)
    })

    /// Fixed colours for things drawn on top of the camera image. They never flip with the theme.
    static let lensLight = Color(red: Double(0xF1) / 255.0, green: Double(0xEE) / 255.0, blue: Double(0xE6) / 255.0)
    static let lensDark = Color(red: Double(0x26) / 255.0, green: Double(0x26) / 255.0, blue: Double(0x26) / 255.0)
}

/// A tiny tiling noise image, laid over the paper at low strength.
private enum PaperGrain {
    static let image: UIImage = {
        let side = 128
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        for i in 0..<(side * side) {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let v = UInt8(truncatingIfNeeded: state >> 56)
            bytes[i * 4] = v
            bytes[i * 4 + 1] = v
            bytes[i * 4 + 2] = v
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cg = CGImage(
                width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return UIImage() }
        return UIImage(cgImage: cg, scale: 3, orientation: .up)
    }()
}

/// Flat paper with a very faint grain (optimized for cooler GPU running).
struct PaperBackground: View {
    var body: some View {
        ZStack {
            Palette.paper
            Image(uiImage: PaperGrain.image)
                .resizable(resizingMode: .tile)
                .opacity(0.04)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}