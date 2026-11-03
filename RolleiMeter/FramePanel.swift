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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                PanelTitle(text: "Frame", k: k)
                    .padding(.top, 0)
                if loggedCount > 0 {
                    Text("\(loggedCount) logged")
                        .font(.system(size: 13 * k, weight: .medium))
                        .foregroundStyle(Palette.accent)
                        .lineLimit(1)
                        .padding(.trailing, 20 * k)
                        .padding(.top, 16 * k)
                }
            }

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 8 * k) {
                Text(isUnloaded ? "\u{2013}" : (isBonus ? "+\(frame)" : "\(frame)"))
                    .font(.system(size: 66 * k, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isBonus ? Palette.accent : Palette.text)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(isUnloaded ? "of \u{2013}" : "of \(rollLength)")
                    .font(.system(size: 17 * k, weight: .medium))
                    .foregroundStyle(Palette.textSub)
                    .lineLimit(1)
            }
            .padding(.horizontal, 20 * k)
            .animation(.smooth(duration: 0.2), value: frame)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            UISelectionFeedbackGenerator().selectionChanged()
            onTap()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isUnloaded ? "No film roll loaded" : "Frame \(frame) of \(rollLength)")
        .accessibilityHint("Opens the frame log")
    }
}
