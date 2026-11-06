import SwiftUI

struct PanelTitle: View {
    let text: String
    let k: CGFloat
    var color: Color = Palette.textDim

    var body: some View {
        Text(text)
            .font(AppTypography.label(20 * k, weight: .semibold))
            .tracking(3.2 * k)
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.top, 16 * k)
            .accessibilityAddTraits(.isHeader)
    }
}

struct DialIndexPointer: View {
    let k: CGFloat
    var color: Color = Palette.accent

    var body: some View {
        Canvas { ctx, size in
            let midX = size.width / 2
            var triangle = Path()
            triangle.move(to: CGPoint(x: midX - 5.5 * k, y: 0))
            triangle.addLine(to: CGPoint(x: midX + 5.5 * k, y: 0))
            triangle.addLine(to: CGPoint(x: midX, y: 7.5 * k))
            triangle.closeSubpath()
            ctx.fill(triangle, with: .color(color))
        }
        .frame(width: 14 * k, height: 8 * k)
        .allowsHitTesting(false)
    }
}

struct InstrumentBayModifier: ViewModifier {
    let k: CGFloat
    var accentBorder: Color? = nil

    func body(content: Content) -> some View {
        let radius = 22 * k
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Palette.panelRaised.opacity(0.55), Palette.panel],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    accentBorder ?? Color.white.opacity(0.13),
                                    (accentBorder ?? Color.white).opacity(0.03)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
            )
            .clipShape(.rect(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func instrumentBay(k: CGFloat, accentBorder: Color? = nil) -> some View {
        modifier(InstrumentBayModifier(k: k, accentBorder: accentBorder))
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
