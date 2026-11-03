import SwiftUI
import UIKit

// MARK: - Film speed

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

    private var readout: String {
        if isUnloaded {
            return dragBase != nil ? speedText : "Load Film"
        }
        if useDIN {
            return "\(filmName) \u{00B7} \(ISOScale.label(currentISO, din: true))\u{00B0}"
        }
        if currentISO != boxISO {
            return "\(filmName) @ \(currentISO)"
        }
        return filmName
    }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 22 * k, style: .continuous)
                .fill(Palette.accent)

            HStack(spacing: 8 * k) {
                PanelTitle(text: "FILM", k: k, color: Palette.accentInk)
                if !cameraBadge.isEmpty {
                    Spacer(minLength: 4 * k)
                    Text(cameraBadge.uppercased())
                        .font(AppTypography.next(size: 18 * k, weight: .semibold))
                        .tracking(1.2 * k)
                        .foregroundStyle(Palette.accentInk.opacity(0.72))
                        .lineLimit(1)
                        .padding(.top, 17 * k)
                        .padding(.trailing, 18 * k)
                }
            }

            RoundedRectangle(cornerRadius: 14 * k, style: .continuous)
                .fill(Palette.accentInk)
                .overlay {
                    Text(readout)
                        .font(AppTypography.next(size: 36 * k, weight: .semibold))
                        .foregroundStyle(isUnloaded ? Palette.accent : Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .padding(.horizontal, 14 * k)
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.15), value: readout)
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
        .accessibilityHint("Tap to choose film, drag horizontally to rate ISO")
    }
}
