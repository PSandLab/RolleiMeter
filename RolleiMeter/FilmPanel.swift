import SwiftUI
import UIKit

// MARK: - Film speed

struct FilmPanel: View {
    @Binding var isoIndex: Int
    let useDIN: Bool
    let filmName: String
    let boxISO: Int
    var isUnloaded: Bool = false
    var evComp: Double = 0.0
    var gearBadge: String = ""
    let k: CGFloat
    let onTap: () -> Void

    @State private var dragBase: Int?

    private var safeIndex: Int { min(max(isoIndex, 0), ISOScale.values.count - 1) }

    private var speedText: String {
        let value = ISOScale.label(ISOScale.values[safeIndex], din: useDIN)
        return useDIN ? value + " DIN" : "ISO " + value
    }

    private var readout: String {
        if isUnloaded {
            return "LOAD FILM  \u{2022}  " + speedText
        }
        return filmName + "  \u{2022}  " + speedText
    }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 22 * k, style: .continuous)
                .fill(Palette.accent)

            HStack {
                PanelTitle(text: "FILM", k: k, color: Palette.accentInk)
                if abs(evComp) >= 0.05 {
                    Spacer()
                    Text(formatEvComp(evComp))
                        .font(AppTypography.mono(size: 18 * k, weight: .bold))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 8 * k)
                        .padding(.vertical, 3 * k)
                        .background(Palette.accentInk, in: Capsule())
                        .padding(.top, 14 * k)
                        .padding(.trailing, 16 * k)
                }
            }

            RoundedRectangle(cornerRadius: 14 * k, style: .continuous)
                .fill(Palette.accentInk)
                .overlay {
                    VStack(spacing: 2 * k) {
                        Text(readout)
                            .font(AppTypography.next(size: 32 * k, weight: .medium))
                            .foregroundStyle(isUnloaded ? Palette.accent : Palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                            .contentTransition(.numericText())
                            .animation(.smooth(duration: 0.15), value: readout)

                        if !gearBadge.isEmpty {
                            Text(gearBadge)
                                .font(AppTypography.next(size: 16 * k, weight: .medium))
                                .foregroundStyle(Palette.dim)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
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
