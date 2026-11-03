import SwiftUI

// MARK: - Panel chrome

struct LiquidPanel: ViewModifier {
    let radius: CGFloat
    var fill: Color = Palette.panel
    var edge: Bool = true
    var useGlass: Bool = true
    var interactive: Bool = true
    var glassTint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        if #available(iOS 26.0, *), useGlass {
            if let glassTint {
                content.glassEffect(.regular.tint(glassTint).interactive(), in: shape)
            } else if interactive {
                content.glassEffect(.regular.interactive(), in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        } else if useGlass {
            // Compatibility treatment for iOS 17–25, where native Liquid Glass isn't available.
            content
                .background { shape.fill(fill) }
                .overlay {
                    if edge {
                        shape
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.09), Color.white.opacity(0.02)],
                                    startPoint: .top, endPoint: .bottom),
                                lineWidth: 0.75)
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(shape)
        } else {
            // Standard material is appropriate for readouts; reserve Liquid Glass for the control layer.
            content.background(.regularMaterial, in: shape)
        }
    }
}

extension View {
    func liquidPanel(
        radius: CGFloat,
        fill: Color = Palette.panel,
        edge: Bool = true,
        useGlass: Bool = true,
        interactive: Bool = true,
        glassTint: Color? = nil
    ) -> some View {
        modifier(LiquidPanel(
            radius: radius,
            fill: fill,
            edge: edge,
            useGlass: useGlass,
            interactive: interactive,
            glassTint: glassTint
        ))
    }
}

struct PanelTitle: View {
    let text: String
    let k: CGFloat
    var color: Color = Palette.text

    var body: some View {
        Text(text)
            .font(AppTypography.next(size: 25 * k))
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
