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
    private var pitch: CGFloat { 108 * k }

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

        ZStack(alignment: .top) {
            ApertureWheel(
                position: position,
                labels: stops.map { $0.label },
                tint: activeTint,
                auto: auto,
                k: k
            )
            PanelTitle(text: "APERTURE", k: k)
        }
        .overlay(alignment: .topTrailing) {
            if auto {
                Text("A")
                    .font(AppTypography.next(size: 18 * k, weight: .bold))
                    .foregroundStyle(lampColor)
                    .padding(.top, 15 * k)
                    .padding(.trailing, 18 * k)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
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
    let auto: Bool
    let k: CGFloat

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let pitch = 108 * k

            for i in labels.indices {
                let d = Double(i) - position
                let ad = abs(d)
                if ad > 1.45 { continue }
                let x = cx + CGFloat(d) * pitch
                let t = max(0.0, 1.0 - ad)
                let selected = ad < 0.45
                let color: Color = selected ? tint : Palette.textSub
                let fontSize: CGFloat = (28.0 + 20.0 * t) * k
                let opacity = selected ? 1.0 : max(0.0, 0.42 * (1.0 - (ad - 0.3) / 1.15))

                let displayStr = selected ? "f/\(labels[i])" : labels[i]
                let text = Text(displayStr)
                    .font(AppTypography.numeral(size: fontSize, weight: selected ? .semibold : .regular))
                    .foregroundColor(color.opacity(opacity))
                ctx.draw(ctx.resolve(text), at: CGPoint(x: x, y: 102 * k), anchor: .center)
            }

            let subLabel = auto ? "auto" : "f-stop"
            let subColor = auto ? tint : Palette.textDim
            let subText = Text(subLabel)
                .font(AppTypography.next(size: 18 * k, weight: auto ? .semibold : .medium))
                .foregroundColor(subColor.opacity(0.85))
            ctx.draw(ctx.resolve(subText), at: CGPoint(x: cx, y: 150 * k), anchor: .center)
        }
        .wheelEdgeMask()
        .clipped()
        .allowsHitTesting(false)
    }
}
