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
        return useDIN ? value : "ISO " + value
    }

    private var readout: String {
        if isUnloaded {
            return dragBase != nil ? speedText : "Load Film"
        }
        if useDIN {
            return "\(filmName) \u{00B7} \(ISOScale.label(currentISO, din: true))"
        }
        if currentISO != boxISO {
            return "\(filmName) @ \(currentISO)"
        }
        return filmName
    }

    var body: some View {
        let hasCam = !cameraBadge.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        ZStack(alignment: .top) {
            PanelTitle(
                text: hasCam ? cameraBadge.uppercased() : "FILM",
                k: k,
                color: hasCam ? Palette.accent : Palette.textDim
            )
            .padding(.horizontal, 12 * k)

            // Film box-end holder window
            HStack(spacing: 12 * k) {
                if !isUnloaded {
                    FilmCanisterArtwork(
                        brand: filmName,
                        familyName: filmName,
                        category: "Color",
                        iso: currentISO,
                        showLeader: false,
                        width: 42 * k,
                        height: 58 * k
                    )
                } else {
                    Image(systemName: "film")
                        .font(.system(size: 28 * k, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }

                VStack(alignment: .leading, spacing: 4 * k) {
                    Text(readout)
                        .font(AppTypography.next(size: 32 * k, weight: .bold).monospacedDigit())
                        .foregroundStyle(isUnloaded ? Palette.accent : Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.60)
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.15), value: readout)

                    Text(isUnloaded ? "TAP TO LOAD ROLL" : (currentISO != boxISO ? "RATED \(speedText) (BOX \(boxISO))" : speedText))
                        .font(AppTypography.numeral(size: 17 * k, weight: .semibold))
                        .tracking(1.0 * k)
                        .foregroundStyle(currentISO != boxISO && !isUnloaded ? Palette.accent : Palette.textSub)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16 * k)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 15 * k, style: .continuous)
                    .fill(Palette.panelInset)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15 * k, style: .continuous)
                            .strokeBorder(
                                isUnloaded ? Palette.accent.opacity(0.55) : Palette.accent.opacity(0.32),
                                lineWidth: 1.2
                            )
                    )
            )
            .padding(.horizontal, 16 * k)
            .padding(.top, 54 * k)
            .padding(.bottom, 16 * k)
        }
        .instrumentBay(k: k, accentBorder: Palette.accent.opacity(0.22))
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
