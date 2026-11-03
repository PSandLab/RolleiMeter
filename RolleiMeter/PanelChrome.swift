import SwiftUI

// MARK: - Meter tiles

/// Floating readout tile for the camera meter.
///
/// Apple reserves Liquid Glass for the control/navigation layer, so readouts
/// use the standard material the system supplies for chrome over live content.
/// Glass is kept for the shutter, the EV pill and the round buttons.
struct MeterTile: ViewModifier {
    let k: CGFloat

    func body(content: Content) -> some View {
        content.background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: Metrics.tileRadius * k, style: .continuous)
        )
    }
}

extension View {
    func meterTile(k: CGFloat) -> some View {
        modifier(MeterTile(k: k))
    }
}

/// Sentence-case caption that names a readout ("Shutter", "Aperture").
/// Secondary colour, leading aligned, no tracking — system-app typography.
struct PanelTitle: View {
    let text: String
    let k: CGFloat
    var color: Color = Palette.textSub

    var body: some View {
        Text(text)
            .font(.system(size: 15 * k, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 20 * k)
            .padding(.top, 16 * k)
            .accessibilityAddTraits(.isHeader)
    }
}
