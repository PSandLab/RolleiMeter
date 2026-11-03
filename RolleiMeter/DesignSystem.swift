import SwiftUI
import UIKit

// MARK: - Layout constants

enum Metrics {
    /// Concentric radius for content cards inside grouped lists.
    static let cardRadius: CGFloat = 20
    /// Radius for floating chrome tiles over the camera feed.
    static let tileRadius: CGFloat = 24
    /// Standard horizontal inset for content that is not a `List`.
    static let gutter: CGFloat = 16
    /// Minimum tappable size (HIG).
    static let minTap: CGFloat = 44
}

// MARK: - Type scale helpers

enum TypeScale {
    /// Fixed-size numeral used by the meter chrome. The meter grid is a
    /// precision instrument that scales with the viewfinder (`k`), so these
    /// sizes are intentionally absolute rather than Dynamic Type styles.
    static func readout(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }

    static func label(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - Surfaces

extension View {
    /// Floating chrome: Liquid Glass on iOS 26+, the system material below it.
    /// Use only for controls that hover over content — never for list rows.
    @ViewBuilder
    func floatingSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                if interactive {
                    self.glassEffect(.regular.tint(tint).interactive(), in: shape)
                } else {
                    self.glassEffect(.regular.tint(tint), in: shape)
                }
            } else if interactive {
                self.glassEffect(.regular.interactive(), in: shape)
            } else {
                self.glassEffect(.regular, in: shape)
            }
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }

    /// Content-plane card. Opaque system fill, no stroke, no shadow.
    func cardSurface(radius: CGFloat = Metrics.cardRadius,
                     fill: Color = Palette.groupedCell) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
        )
    }

    /// Hairline separator inset to the text, the way `List` draws them.
    func rowSeparator() -> some View {
        self.overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.border.opacity(0.6))
                .frame(height: 1 / UIScreen.main.scale)
                .padding(.leading, Metrics.gutter)
        }
    }
}

// MARK: - Buttons

/// Circular icon button for floating chrome. The circle *is* the enclosure,
/// so callers pass bare glyphs (`gearshape`, never `gearshape.circle`).
struct GlassCircleButton: View {
    let systemName: String
    var size: CGFloat = 44
    var tint: Color = Palette.text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .contentShape(Circle())
                .floatingSurface(Circle(), interactive: true)
        }
        .buttonStyle(.plain)
    }
}

/// Filled capsule used for the single affirmative action on a screen.
struct PrimaryActionButton: View {
    let title: String
    var systemImage: String? = nil
    var role: ButtonRole? = nil
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            Button(role: role, action: action) {
                label
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(role == .destructive ? Palette.bad : Palette.accent)
        } else {
            Button(role: role, action: action) {
                label
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(role == .destructive ? Palette.bad : Palette.accent)
        }
    }

    private var label: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .font(Geist.text(.body, .semibold))
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Rows & labels

/// SF Symbol in a rounded translucent tile — the standard `Settings`-style row glyph.
struct ListGlyph: View {
    let systemName: String
    var tint: Color = Palette.accent
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Small uppercase-free caption used above a value, e.g. "Shutter".
struct MetricCaption: View {
    let text: String
    var size: CGFloat = 13

    var body: some View {
        Text(text)
            .font(Geist.sans(size, .medium))
            .foregroundStyle(Palette.textSub)
            .lineLimit(1)
    }
}

/// A value with an optional trailing unit, the way Camera shows "1/125 s".
struct MetricValue: View {
    let text: String
    var unit: String? = nil
    var size: CGFloat = 40
    var tint: Color = Palette.text
    var animate = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.16) {
            Text(text)
                .font(Geist.mono(size, .semibold))
                .foregroundStyle(tint)
                .contentTransition(animate ? .numericText() : .identity)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            if let unit {
                Text(unit)
                    .font(Geist.sans(size * 0.42, .medium))
                    .foregroundStyle(Palette.textSub)
                    .lineLimit(1)
            }
        }
    }
}

/// Non-interactive status text. Deliberately plain type, never a filled pill,
/// so it can never be mistaken for a control.
struct StatusText: View {
    let text: String
    var tint: Color = Palette.textSub
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(text)
                .font(Geist.text(.caption, .medium))
        }
        .foregroundStyle(tint)
    }
}

// MARK: - Section scaffolding for non-List content

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Geist.text(.subheadline, .semibold))
                .foregroundStyle(Palette.text)
            if let subtitle {
                Text(subtitle)
                    .font(Geist.text(.footnote))
                    .foregroundStyle(Palette.textSub)
            }
        }
    }
}

/// Screen background for grouped content that is not a `List`.
struct GroupedScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Palette.groupedBackground.ignoresSafeArea())
    }
}

extension View {
    func groupedScreenBackground() -> some View {
        modifier(GroupedScreenBackground())
    }
}

// MARK: - Haptics (one place, consistent)

enum Haptics {
    static func tap() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func press() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func rigid() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
