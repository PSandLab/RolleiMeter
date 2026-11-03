import SwiftUI
import UIKit

// MARK: - Film

/// The loaded stock, the speed you are rating it at, and the camera it lives in.
struct FilmPanel: View {
    @Binding var isoIndex: Int
    let useDIN: Bool
    let filmName: String
    let boxISO: Int
    var isUnloaded: Bool = false
    var cameraBadge: String = ""
    let k: CGFloat
    let onTap: () -> Void

    @State private var dragBase: Int?

    private var safeIndex: Int { min(max(isoIndex, 0), ISOScale.values.count - 1) }
    private var currentISO: Int { ISOScale.values[safeIndex] }

    private var speedText: String {
        let value = ISOScale.label(currentISO, din: useDIN)
        return useDIN ? value + "\u{00B0}" : "ISO " + value
    }

    private var title: String {
        if isUnloaded { return dragBase != nil ? speedText : "No film loaded" }
        return filmName
    }

    private var speedLine: String {
        if isUnloaded { return "Tap to choose a stock" }
        if useDIN { return "\(ISOScale.label(currentISO, din: true))\u{00B0}" }
        if currentISO != boxISO { return "\(speedText) \u{00B7} rated from \(boxISO)" }
        return speedText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelTitle(text: "Film", k: k)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4 * k) {
                HStack(spacing: 7 * k) {
                    if !isUnloaded {
                        Circle()
                            .fill(Palette.accent)
                            .frame(width: 8 * k, height: 8 * k)
                    }
                    Text(title)
                        .font(.system(size: 26 * k, weight: .semibold))
                        .foregroundStyle(isUnloaded ? Palette.textSub : Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                }

                Text(speedLine)
                    .font(.system(size: 15 * k, weight: .medium))
                    .foregroundStyle(Palette.textSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())

                if !cameraBadge.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(cameraBadge)
                        .font(.system(size: 13 * k, weight: .regular))
                        .foregroundStyle(Palette.textDim)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 20 * k)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.15), value: speedLine)
        .contentShape(Rectangle())
        .onTapGesture {
            UISelectionFeedbackGenerator().selectionChanged()
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            guard let box = ISOScale.values.firstIndex(of: boxISO), isoIndex != box else { return }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
            isoIndex = box
        }
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    if dragBase == nil { dragBase = safeIndex }
                    let steps = Int((value.translation.width / (26 * k)).rounded())
                    let target = min(max((dragBase ?? safeIndex) + steps, 0), ISOScale.values.count - 1)
                    guard target != isoIndex else { return }
                    isoIndex = target
                    if ISOScale.values[target] == boxISO {
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
                    } else {
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                }
                .onEnded { _ in dragBase = nil }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Film")
        .accessibilityValue(isUnloaded ? "No film loaded" : "\(filmName), \(speedLine)")
        .accessibilityHint("Tap to choose film. Drag horizontally to rate the ISO.")
    }
}
