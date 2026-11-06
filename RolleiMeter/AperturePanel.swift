import SwiftUI
import UIKit

// MARK: - Aperture wheel

enum AutoLampState {
    case off, good, slow, bad
}

struct AperturePanel: View {
    let index: Int
    var stops: [(label: String, n: Double)] = Rollei.stops
    let auto: Bool
    let lamp: AutoLampState
    let k: CGFloat
    let onPick: (Int) -> Void
    let onTap: () -> Void
    let onHome: () -> Void

    private var homeIndex: Int { min(3, max(0, stops.count - 1)) }

    @State private var position: Double = 0
    @State private var base: Double?
    @State private var moved = false
    @State private var longPressFired = false
    @State private var pressToken = 0
    @State private var lastDetent = -1

    private var stopCount: Int { max(1, stops.count) }
    private var nearest: Int { min(max(Int(position.rounded()), 0), stopCount - 1) }
    private var pitch: CGFloat { 92 * k }

    private var lampColor: Color {
        switch lamp {
        case .off: return Palette.text
        case .good: return Palette.good
        case .slow: return Palette.slow
        case .bad: return Palette.bad
        }
    }

    var body: some View {
        let activeTint = auto ? lampColor : Palette.text
        let pointerTint = auto ? lampColor : Palette.accent

        ZStack(alignment: .top) {
            ApertureWheel(
                position: position,
                labels: stops.map { $0.label },
                tint: activeTint,
                pointerTint: pointerTint,
                auto: auto,
                k: k
            )

            PanelTitle(text: "APERTURE", k: k)

            DialIndexPointer(k: k, color: pointerTint)
                .padding(.top, 46 * k)
        }
        .overlay(alignment: .topTrailing) {
            Text("A")
                .font(AppTypography.next(size: 18 * k, weight: .bold))
                .foregroundStyle(auto ? lampColor : Palette.dim)
                .padding(.horizontal, 10 * k)
                .padding(.vertical, 4 * k)
                .background(
                    Capsule()
                        .fill(auto ? lampColor.opacity(0.18) : Palette.panelInset.opacity(0.7))
                        .overlay(
                            Capsule()
                                .strokeBorder(auto ? lampColor.opacity(0.65) : Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .padding(.top, 12 * k)
                .padding(.trailing, 14 * k)
                .allowsHitTesting(false)
        }
        .instrumentBay(k: k)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onAppear {
            position = Double(index)
            lastDetent = index
        }
        .onChange(of: index) { _, newValue in
            guard base == nil else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                position = Double(newValue)
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if base == nil {
                    base = position
                    moved = false
                    longPressFired = false
                    scheduleHome()
                }
                guard !longPressFired else { return }
                if !moved && abs(value.translation.width) > 4 {
                    moved = true
                    pressToken += 1
                }
                guard moved, let start = base else { return }
                position = rubber(start - Double(value.translation.width / pitch))
                detent()
            }
            .onEnded { value in
                pressToken += 1
                let start = base ?? position
                let wasMoved = moved
                let fired = longPressFired
                base = nil
                moved = false
                longPressFired = false

                if fired { return }
                if !wasMoved {
                    onTap()
                    return
                }
                let predicted = start - Double(value.predictedEndTranslation.width / pitch)
                let target = Double(min(max(Int(rubber(predicted).rounded()), 0), stopCount - 1))
                withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) { position = target }
                detent()
                onPick(Int(target))
            }
    }

    private func rubber(_ v: Double) -> Double {
        let lo = 0.0
        let hi = Double(stopCount - 1)
        if v < lo { return max(lo - 0.35, lo - (lo - v) * 0.3) }
        if v > hi { return min(hi + 0.35, hi + (v - hi) * 0.3) }
        return v
    }

    private func detent() {
        let stop = nearest
        guard stop != lastDetent else { return }
        lastDetent = stop
        if stop == homeIndex {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
        } else {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func scheduleHome() {
        pressToken += 1
        let token = pressToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard token == pressToken, base != nil, !moved else { return }
            longPressFired = true
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                position = Double(homeIndex)
            }
            lastDetent = homeIndex
            onHome()
        }
    }
}

private struct ApertureWheel: View, Animatable {
    var position: Double
    let labels: [String]
    let tint: Color
    let pointerTint: Color
    let auto: Bool
    let k: CGFloat

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let pitch = 92 * k

            // Bottom knurled scale ticks
            let tickBaseY = size.height - 14 * k
            let subSteps = 3
            let minIdx = max(0, Int(floor(position)) - 3)
            let maxIdx = min(labels.count - 1, Int(ceil(position)) + 3)
            if minIdx <= maxIdx {
                for i in minIdx...maxIdx {
                    for s in 0..<subSteps {
                        if i == maxIdx && s > 0 { continue }
                        let tickPos = Double(i) + Double(s) / Double(subSteps)
                        let dTick = tickPos - position
                        let tx = cx + CGFloat(dTick) * pitch
                        if tx < 12 * k || tx > size.width - 12 * k { continue }
                        let isMajor = (s == 0)
                        let tickH: CGFloat = (isMajor ? 9 : 5) * k
                        let fade = max(0.0, 1.0 - abs(dTick) * 0.45)
                        var tickPath = Path()
                        tickPath.move(to: CGPoint(x: tx, y: tickBaseY - tickH))
                        tickPath.addLine(to: CGPoint(x: tx, y: tickBaseY))
                        ctx.stroke(
                            tickPath,
                            with: .color((isMajor && abs(dTick) < 0.25 ? pointerTint : Palette.textSub).opacity(fade * (isMajor ? 0.55 : 0.25))),
                            lineWidth: (isMajor ? 1.6 : 1.0) * k
                        )
                    }
                }
            }

            // Engraved f-stop numerals
            for i in labels.indices {
                let d = Double(i) - position
                let x = cx + CGFloat(d) * pitch
                if x < -pitch || x > size.width + pitch { continue }
                let ad = abs(d)
                let selected = ad < 0.45
                let color: Color = selected ? tint : Palette.textSub
                let fontSize: CGFloat = (selected ? 64 : 42) * k
                let opacity = selected ? 1.0 : max(0.18, 0.68 - 0.32 * ad)

                let text = Text(labels[i])
                    .font(AppTypography.numeral(size: fontSize, weight: selected ? .bold : .medium))
                    .foregroundColor(color.opacity(opacity))
                ctx.draw(ctx.resolve(text), at: CGPoint(x: x, y: 102 * k), anchor: .center)
            }

            // Active f-stop sub-label
            let idx = min(max(Int(position.rounded()), 0), max(0, labels.count - 1))
            let activeLabel = labels.isEmpty ? "" : "f/\(labels[idx])" + (auto ? " · AUTO" : "")
            let subText = Text(activeLabel)
                .font(AppTypography.numeral(size: 20 * k, weight: .semibold))
                .foregroundColor((auto ? tint : Palette.textSub).opacity(0.88))
            ctx.draw(ctx.resolve(subText), at: CGPoint(x: cx, y: 154 * k), anchor: .center)
        }
        .clipped()
        .allowsHitTesting(false)
    }
}
