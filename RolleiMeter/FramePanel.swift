import SwiftUI
import UIKit

// MARK: - Frame counter (3D cylindrical tape + scrolling 35mm sprocket perforations)

struct FramePanel: View {
    let frame: Int
    let rollLength: Int
    var isUnloaded: Bool = false
    var loggedCount: Int = 0
    let k: CGFloat
    let onTap: () -> Void

    @State private var advancePulse: Double = 0.0

    var body: some View {
        let rollFillRatio = min(max(Double(frame) / Double(max(rollLength, 1)), 0.0), 1.2)
        let dynamicResponse = 0.34 + (0.08 * rollFillRatio)       // 0.34s at Frame 1 -> 0.42s at Frame 36
        let dynamicDamping  = 0.42 + (0.22 * rollFillRatio)       // 0.42 at Frame 1  -> 0.64 at Frame 36

        ZStack(alignment: .top) {
            PanelTitle(text: "FRAME", k: k)
                .scaleEffect(1.0 + 0.03 * advancePulse)

            FrameTapeStrip(
                position: Double(frame),
                advancePulse: advancePulse,
                rollLength: rollLength,
                isUnloaded: isUnloaded,
                k: k
            )
        }
        .mattePanel(k: k, glowColor: Palette.text, glowIntensity: advancePulse * 0.7)
        .contentShape(Rectangle())
        .onTapGesture {
            UISelectionFeedbackGenerator().selectionChanged()
            advancePulse = 0.7
            withAnimation(.spring(response: dynamicResponse, dampingFraction: dynamicDamping)) {
                advancePulse = 0.0
            }
            onTap()
        }
        .onChange(of: frame) { _, _ in
            advancePulse = 1.0
            withAnimation(.spring(response: dynamicResponse, dampingFraction: dynamicDamping)) {
                advancePulse = 0.0
            }
        }
        .animation(.spring(response: dynamicResponse, dampingFraction: dynamicDamping), value: frame)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isUnloaded ? "No film roll loaded" : "Frame \(frame) of \(rollLength)")
    }
}

private struct FrameTapeStrip: View, Animatable {
    var position: Double
    var advancePulse: Double
    let rollLength: Int
    let isUnloaded: Bool
    let k: CGFloat

    var animatableData: AnimatablePair<Double, Double> {
        get { .init(position, advancePulse) }
        set {
            position = newValue.first
            advancePulse = newValue.second
        }
    }

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let pitch = size.width * 0.24
            let yPos = 112 * k

            // Sub-animation: Scrolling 35mm film sprocket holes along bottom edge
            let sprocketsPerFrame = 6
            let sprocketPitch = pitch / CGFloat(sprocketsPerFrame)
            let phase = (position * Double(sprocketsPerFrame)).truncatingRemainder(dividingBy: 1.0)
            let holeW: CGFloat = 7.5 * k
            let holeH: CGFloat = 4.5 * k
            let holeY: CGFloat = size.height - 13 * k
            let visibleHoles = Int(ceil(size.width / max(1, sprocketPitch))) + 4

            for hIdx in -visibleHoles/2 ... visibleHoles/2 {
                let hx = cx + (CGFloat(hIdx) - CGFloat(phase)) * sprocketPitch - holeW / 2
                let distFromCenter = abs((hx + holeW / 2) - cx) / (size.width * 0.5)
                if distFromCenter > 1.05 { continue }
                let fade = max(0.0, 1.0 - pow(distFromCenter, 1.6))
                let holeRect = CGRect(x: hx, y: holeY, width: holeW, height: holeH)
                ctx.fill(
                    Path(roundedRect: holeRect, cornerRadius: 1.2 * k),
                    with: .color(Palette.text.opacity((0.14 + 0.14 * advancePulse) * Double(fade)))
                )
            }

            if isUnloaded {
                let dash = Text("—")
                    .font(AppTypography.numeral(size: 38 * k, weight: .medium))
                    .foregroundColor(Palette.dim)
                ctx.draw(ctx.resolve(dash), at: CGPoint(x: cx, y: yPos), anchor: .center)
                return
            }

            // Macro + Micro: Cylindrical frame tape with advance pop
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

                let proximity = max(0.0, 1.0 - ad * 1.4)
                let popScale = CGFloat(1.0 + proximity * (0.10 + 0.18 * advancePulse))
                let depthScale = CGFloat(max(0.72, 1.0 - 0.10 * ad)) * popScale
                let barrelDrop = CGFloat(ad * ad) * 2.5 * k

                let color: Color = active
                    ? (isBonus ? Palette.good : Palette.text)
                    : Palette.textSub.opacity(max(0.24, 0.72 - 0.22 * ad))

                var numCtx = ctx
                numCtx.translateBy(x: x, y: yPos + barrelDrop)
                numCtx.scaleBy(x: depthScale, y: depthScale)
                let label = Text("\(candidate)")
                    .font(AppTypography.numeral(size: 38 * k, weight: active ? .semibold : .regular))
                    .foregroundColor(color)
                numCtx.draw(numCtx.resolve(label), at: .zero, anchor: .center)
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}
