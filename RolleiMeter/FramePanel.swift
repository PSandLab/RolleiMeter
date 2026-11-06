import SwiftUI
import UIKit

// MARK: - Frame counter

struct FramePanel: View {
    let frame: Int
    let rollLength: Int
    var isUnloaded: Bool = false
    var loggedCount: Int = 0
    let k: CGFloat
    let onTap: () -> Void

    private var isBonus: Bool { !isUnloaded && frame > rollLength }

    var body: some View {
        ZStack(alignment: .top) {
            PanelTitle(text: "FRAME", k: k)

            if loggedCount > 0 {
                HStack {
                    Spacer()
                    Text("\(loggedCount) LOG")
                        .font(AppTypography.numeral(size: 16 * k, weight: .bold))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 9 * k)
                        .padding(.vertical, 4 * k)
                        .background(
                            Capsule()
                                .fill(Palette.accent.opacity(0.15))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Palette.accent.opacity(0.45), lineWidth: 1)
                                )
                        )
                        .padding(.top, 12 * k)
                        .padding(.trailing, 14 * k)
                }
            }

            // Recessed mechanical counter window
            ZStack {
                RoundedRectangle(cornerRadius: 15 * k, style: .continuous)
                    .fill(Palette.panelInset)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15 * k, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                    )

                if isUnloaded {
                    HStack(alignment: .firstTextBaseline, spacing: 8 * k) {
                        Text("--")
                            .font(AppTypography.numeral(size: 68 * k, weight: .bold))
                            .foregroundStyle(Palette.dim)
                        Text("/ --")
                            .font(AppTypography.numeral(size: 32 * k, weight: .medium))
                            .foregroundStyle(Palette.faint)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8 * k) {
                        Text(isBonus ? "+\(frame)" : String(format: "%02d", frame))
                            .font(AppTypography.numeral(size: 74 * k, weight: .bold))
                            .foregroundStyle(isBonus ? Palette.good : Palette.text)
                            .contentTransition(.numericText())
                        Text("/ \(rollLength)")
                            .font(AppTypography.numeral(size: 32 * k, weight: .semibold))
                            .foregroundStyle(Palette.textDim)
                    }
                    .animation(.smooth(duration: 0.2), value: frame)
                }
            }
            .padding(.horizontal, 16 * k)
            .padding(.top, 54 * k)
            .padding(.bottom, 16 * k)
        }
        .instrumentBay(k: k)
        .contentShape(Rectangle())
        .onTapGesture {
            UISelectionFeedbackGenerator().selectionChanged()
            onTap()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isUnloaded ? "No film roll loaded" : "Frame \(frame) of \(rollLength)")
    }
}
