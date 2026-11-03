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
            if isUnloaded {
                HStack(alignment: .firstTextBaseline, spacing: 8 * k) {
                    Text("--")
                        .font(AppTypography.next(size: 72 * k, weight: .bold))
                        .foregroundStyle(Palette.dim)
                    Text("/ --")
                        .font(AppTypography.next(size: 32 * k, weight: .medium))
                        .foregroundStyle(Palette.faint)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 40 * k)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10 * k) {
                    Text(isBonus ? "+\(frame)" : "\(frame)")
                        .font(AppTypography.next(size: 78 * k, weight: .bold))
                        .foregroundStyle(isBonus ? Palette.good : Palette.text)
                        .contentTransition(.numericText())
                    Text("/ \(rollLength)")
                        .font(AppTypography.next(size: 34 * k, weight: .medium))
                        .foregroundStyle(Palette.dim)
                }
                .animation(.smooth(duration: 0.2), value: frame)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 40 * k)
            }

            HStack {
                PanelTitle(text: "FRAME", k: k)
                if loggedCount > 0 {
                    Spacer()
                    Text("\(loggedCount) LOG")
                        .font(AppTypography.mono(size: 16 * k, weight: .bold))
                        .foregroundStyle(Palette.accent)
                        .padding(.top, 18 * k)
                        .padding(.trailing, 18 * k)
                }
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
