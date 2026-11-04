import SwiftUI

struct PanelTitle: View {
    let text: String
    let k: CGFloat
    var color: Color = Palette.text

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .tracking(2.6 * k)
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.top, 17 * k)
            .accessibilityAddTraits(.isHeader)
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
