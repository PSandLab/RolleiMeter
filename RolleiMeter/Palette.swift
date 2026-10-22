import SwiftUI
import UIKit

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

    // Classic Braun matte light gray/cream & dark anthracite
    static let paper = dynamic(0xF2EFE9, 0x1A1918)
    static let ink = dynamic(0x1F1F1F, 0xEBE7DF)
    static let mutedInk = dynamic(0x7D7A73, 0x949088)
    static let engraved = dynamic(0x2B2926, 0xD4CFC5)
    static let hairline = dynamic(0xD8D4CB, 0x33312D)
    static let accent = dynamic(0xB32631, 0xE2575F)
    static let green = dynamic(0x3B6846, 0x76A37F)
    static let amber = dynamic(0x9E681A, 0xD99E43)

    // The legendary Dieter Rams Braun Orange (ET66 equals button / T3 radio dial)
    static let braunOrange = dynamic(0xEB5528, 0xF06336)

    static let highlight = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.04)
            : UIColor(white: 1, alpha: 0.35)
    })

    // Clean, precision-molded industrial finishes
    static let bezelTop = dynamic(0xF7F4EE, 0x242320)
    static let bezelBottom = dynamic(0xEDE9E1, 0x171614)
    static let well = dynamic(0xE5E1D7, 0x121110)

    // Very soft, restrained contact shadows (no more heavy floaty shadows)
    static let cast = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0, alpha: 0.30)
            : UIColor(white: 0, alpha: 0.05)
    })

    static let recess = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0, alpha: 0.30)
            : UIColor(white: 0, alpha: 0.08)
    })

    static let lensLight = Color(red: Double(0xF1) / 255.0, green: Double(0xEE) / 255.0, blue: Double(0xE6) / 255.0)
    static let lensDark = Color(red: Double(0x26) / 255.0, green: Double(0x26) / 255.0, blue: Double(0x26) / 255.0)
}

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

struct PaperBackground: View {
    var body: some View {
        ZStack {
            Palette.paper
            Image(uiImage: PaperGrain.image)
                .resizable(resizingMode: .tile)
                .opacity(0.025)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
