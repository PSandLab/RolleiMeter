import SwiftUI
import UIKit

// MARK: - Film speed (Solid Yellow Card with Dark Cutout matching Concept Render)

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
        return useDIN ? value : "ISO " + value
    }

    private var cleanStockName: String {
        // Strip trailing ISO digits from shortFilmBadge if present so we can format "Portra • ISO 400"
        let stripped = filmName.replacingOccurrences(
            of: "\\s+\(boxISO)$",
            with: "",
            options: .regularExpression
        )
        return stripped.isEmpty ? filmName : stripped
    }

    private var readout: String {
        if isUnloaded {
            return dragBase != nil ? speedText : "Load Film"
        }
        return "\(cleanStockName)  \u{2022}  \(speedText)"
    }

    var body: some View {
        let hasCam = !cameraBadge.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        ZStack(alignment: .top) {
            Color.clear
                .background(Palette.accent, in: .rect(cornerRadius: 22 * k, style: .continuous))

            PanelTitle(
                text: hasCam ? cameraBadge.uppercased() : "FILM",
                k: k,
                color: Palette.accentInk
            )
            .padding(.horizontal, 14 * k)

            Color.clear
                .background(Palette.accentInk, in: .rect(cornerRadius: 14 * k, style: .continuous))
                .overlay {
                    Text(readout)
                        .font(AppTypography.next(size: 27 * k, weight: .medium).monospacedDigit())
                        .foregroundStyle(isUnloaded ? Palette.accent : Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .padding(.horizontal, 14 * k)
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.15), value: readout)
                }
                .padding(.horizontal, 16 * k)
                .padding(.top, 60 * k)
                .padding(.bottom, 16 * k)
        }
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
        .accessibilityValue(readout)
        .accessibilityHint("Tap to choose film, drag horizontally to rate ISO")
    }
}
