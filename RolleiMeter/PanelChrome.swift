import SwiftUI

struct PanelTitle: View {
    let text: String
    let k: CGFloat
    var color: Color = Palette.text

    var body: some View {
        Text(text)
            .font(AppTypography.label(21 * k, weight: .regular))
            .tracking(1.8 * k)
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.top, 18 * k)
            .accessibilityAddTraits(.isHeader)
    }
}

struct MattePanelModifier: ViewModifier {
    let k: CGFloat
    var glowColor: Color = .clear
    var glowIntensity: Double = 0.0

    func body(content: Content) -> some View {
        let radius = 22 * k
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Palette.panel)

                    if glowIntensity > 0.001 {
                        RadialGradient(
                            colors: [glowColor.opacity(0.22 * glowIntensity), .clear],
                            center: .center,
                            startRadius: 4 * k,
                            endRadius: 150 * k
                        )
                        .clipShape(.rect(cornerRadius: radius, style: .continuous))
                    }

                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.08 + 0.14 * glowIntensity),
                                    Color.white.opacity(0.02)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
            }
            .clipShape(.rect(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func mattePanel(k: CGFloat, glowColor: Color = .clear, glowIntensity: Double = 0.0) -> some View {
        modifier(MattePanelModifier(k: k, glowColor: glowColor, glowIntensity: glowIntensity))
    }
}

struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.90

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .rotationEffect(.degrees(configuration.isPressed ? -1.5 : 0.0))
            .brightness(configuration.isPressed ? 0.08 : 0.0)
            .animation(
                configuration.isPressed
                    ? .spring(response: 0.14, dampingFraction: 0.55)
                    : .spring(response: 0.32, dampingFraction: 0.48),
                value: configuration.isPressed
            )
    }
}
