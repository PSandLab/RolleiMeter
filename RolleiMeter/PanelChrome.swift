import SwiftUI

struct PanelTitle: View {
    let text: String
    let k: CGFloat
    var color: Color = Palette.textDim

    var body: some View {
        Text(text)
            .font(AppTypography.label(18 * k, weight: .semibold))
            .tracking(2.8 * k)
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.top, 16 * k)
            .accessibilityAddTraits(.isHeader)
    }
}

struct LiquidGlassCardModifier: ViewModifier {
    let k: CGFloat

    func body(content: Content) -> some View {
        let radius = 24 * k
        content
            .glassEffect(.regular, in: .rect(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func liquidGlassCard(k: CGFloat) -> some View {
        modifier(LiquidGlassCardModifier(k: k))
    }

    /// Soft horizontal optical vignette so wheel numbers fade smoothly before reaching the edges.
    func wheelEdgeMask() -> some View {
        mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black, location: 0.16),
                    .init(color: .black, location: 0.84),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
}

struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.20, dampingFraction: 0.70), value: configuration.isPressed)
    }
}
