import SwiftUI
import UIKit

// MARK: - Quiet, Refined Frame Counter Card

struct FramePanel: View {
    let frame: Int
    let rollLength: Int
    var isUnloaded: Bool = false
    var loggedCount: Int = 0
    let onTap: () -> Void

    private var isBonus: Bool { !isUnloaded && frame > rollLength }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("FRAME")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)

                if loggedCount > 0 {
                    Spacer(minLength: 4)
                    Text("\(loggedCount) LOG")
                        .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.04))
                }
            }

            if isUnloaded {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("--")
                        .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("/ --")
                        .font(.system(size: 15, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(isBonus ? "+\(frame)" : "\(frame)")
                        .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(isBonus ? Color(red: 0.19, green: 0.82, blue: 0.35) : .white)
                        .contentTransition(.numericText())

                    Text("/ \(rollLength)")
                        .font(.system(size: 15, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .animation(.smooth(duration: 0.2), value: frame)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 68)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            UISelectionFeedbackGenerator().selectionChanged()
            onTap()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isUnloaded ? "No film roll loaded" : "Frame \(frame) of \(rollLength)")
    }
}
