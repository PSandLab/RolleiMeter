import SwiftUI
import UIKit

// MARK: - Frame counter (horizontal tape strip matching concept render)

struct FramePanel: View {
    let frame: Int
    let rollLength: Int
    var isUnloaded: Bool = false
    var loggedCount: Int = 0
    let k: CGFloat
    let onTap: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            PanelTitle(text: "FRAME", k: k)

            FrameTapeStrip(
                position: Double(frame),
                rollLength: rollLength,
                isUnloaded: isUnloaded,
                k: k
            )
        }
        .mattePanel(k: k)
        .contentShape(Rectangle())
        .onTapGesture {
            UISelectionFeedbackGenerator().selectionChanged()
            onTap()
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: frame)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isUnloaded ? "No film roll loaded" : "Frame \(frame) of \(rollLength)")
    }
}

private struct FrameTapeStrip: View, Animatable {
    var position: Double
    let rollLength: Int
    let isUnloaded: Bool
    let k: CGFloat

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let pitch = size.width * 0.24
            let yPos = 114 * k

            if isUnloaded {
                let dash = Text("—")
                    .font(AppTypography.numeral(size: 38 * k, weight: .medium))
                    .foregroundColor(Palette.dim)
                ctx.draw(ctx.resolve(dash), at: CGPoint(x: cx, y: yPos), anchor: .center)
                return
            }

            let centerFrame = Int(position.rounded())
            for offset in -3...3 {
                let candidate = centerFrame + offset
                if candidate < 1 { continue }
                let d = Double(candidate) - position
                let x = cx + CGFloat(d) * pitch
                if x < -pitch || x > size.width + pitch { continue }
                let ad = abs(d)
                let active = ad < 0.45
                let isBonus = candidate > rollLength
                let color: Color = active
                    ? (isBonus ? Palette.good : Palette.text)
                    : Palette.textSub.opacity(max(0.28, 0.72 - 0.22 * ad))

                let label = Text("\(candidate)")
                    .font(AppTypography.numeral(size: 38 * k, weight: active ? .semibold : .regular))
                    .foregroundColor(color)
                ctx.draw(ctx.resolve(label), at: CGPoint(x: x, y: yPos), anchor: .center)
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}
