import SwiftUI
import UIKit

// MARK: - Film speed

struct FilmPanel: View {
    @Binding var isoIndex: Int
    let useDIN: Bool
    let filmName: String
    let boxISO: Int
    let k: CGFloat
    let onTap: () -> Void

    @State private var dragBase: Int?

    private var safeIndex: Int { min(max(isoIndex, 0), ISOScale.values.count - 1) }

    private var speedText: String {
        let value = ISOScale.label(ISOScale.values[safeIndex], din: useDIN)
        return useDIN ? value + " DIN" : "ISO " + value
    }

    private var readout: String { filmName + "  \u{2022}  " + speedText }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 22 * k, style: .continuous)
                .fill(Palette.accent)

            PanelTitle(text: "FILM", k: k, color: Palette.accentInk)

            RoundedRectangle(cornerRadius: 14 * k, style: .continuous)
                .fill(Palette.accentInk)
                .overlay {
                    Text(readout)
                        .font(AppTypography.next(size: 34 * k, weight: .medium))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.15), value: readout)
                        .padding(.horizontal, 12 * k)
                }
                .padding(.horizontal, 14 * k)
                .padding(.top, 65 * k)
                .padding(.bottom, 14 * k)
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
        .accessibilityHint("Tap to choose film")
    }
}
