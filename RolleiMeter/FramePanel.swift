import SwiftUI
import UIKit

// MARK: - Frame counter

struct FramePanel: View {
    let frame: Int
    let rollLength: Int
    let k: CGFloat
    let onTap: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .firstTextBaseline, spacing: 10 * k) {
                Text("\(frame)")
                    .font(AppTypography.next(size: 78 * k, weight: .bold))
                    .foregroundStyle(Palette.text)
                    .contentTransition(.numericText())
                Text("/ \(rollLength)")
                    .font(AppTypography.next(size: 34 * k, weight: .medium))
                    .foregroundStyle(Palette.dim)
            }
            .animation(.smooth(duration: 0.2), value: frame)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 40 * k)

            PanelTitle(text: "FRAME", k: k)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            UISelectionFeedbackGenerator().selectionChanged()
            onTap()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Frame \(frame) of \(rollLength)")
    }
}
