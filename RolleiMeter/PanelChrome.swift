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

    func body(content: Content) -> some View {
        let radius = 22 * k
        content
            .background(Palette.panel, in: .rect(cornerRadius: radius, style: .continuous))
            .clipShape(.rect(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func mattePanel(k: CGFloat) -> some View {
        modifier(MattePanelModifier(k: k))
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
