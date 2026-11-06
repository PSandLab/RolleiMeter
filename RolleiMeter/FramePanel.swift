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
                    Text("\(loggedCount)")
                        .font(AppTypography.numeral(size: 17 * k, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .padding(.top, 15 * k)
                        .padding(.trailing, 18 * k)
                }
            }

            if isUnloaded {
                HStack(alignment: .firstTextBaseline, spacing: 6 * k) {
                    Text("—")
                        .font(AppTypography.numeral(size: 52 * k, weight: .semibold))
                        .foregroundStyle(Palette.dim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 28 * k)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6 * k) {
                    Text(isBonus ? "+\(frame)" : "\(frame)")
                        .font(AppTypography.numeral(size: 56 * k, weight: .semibold))
                        .foregroundStyle(isBonus ? Palette.good : Palette.text)
                        .contentTransition(.numericText())
                    Text("/ \(rollLength)")
                        .font(AppTypography.numeral(size: 28 * k, weight: .regular))
                        .foregroundStyle(Palette.textDim)
                }
                .animation(.smooth(duration: 0.2), value: frame)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 28 * k)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            UISelectionFeedbackGenerator().selectionChanged()
            onTap()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isUnloaded ? "No film roll loaded" : "Frame \(frame) of \(rollLength)")
    }
}
