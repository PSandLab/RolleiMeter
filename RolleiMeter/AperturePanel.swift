import SwiftUI
import UIKit

// MARK: - Aperture wheel (3D cylindrical drum + detent kick + living auto lamp)

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
    @State private var detentKick: Double = 0
    @State private var unitBounce: Double = 0
    @State private var lampPulse: Bool = false

    private var stopCount: Int { max(1, stops.count) }
    private var nearest: Int { min(max(Int(position.rounded()), 0), stopCount - 1) }
    private var pitch: CGFloat { 92 * k }

    private var lampColor: Color {
        switch lamp {
        case .off: return Palette.accent
        case .good: return Palette.good
        case .slow: return Palette.slow
        case .bad: return Palette.bad
        }
    }

    var body: some View {
        let activeTint = auto ? lampColor : Palette.accent

        ZStack(alignment: .top) {
            ApertureWheel(
                position: position,
                detentKick: detentKick,
                unitBounce: unitBounce,
                labels: stops.map { $0.label },
                tint: activeTint,
                auto: auto,
                k: k
            )
            PanelTitle(text: "APERTURE", k: k)
                .scaleEffect(1.0 + 0.03 * detentKick)
        }
        .overlay(alignment: .topTrailing) {
            if auto {
                ZStack {
                    Circle()
                        .fill(lampColor.opacity(lampPulse ? 0.32 : 0.08))
                        .frame(width: 28 * k, height: 28 * k)
                        .scaleEffect(lampPulse ? 1.35 : 0.85)

                    Text("A")
                        .font(AppTypography.next(size: 19 * k, weight: .bold))
                        .foregroundStyle(lampColor)
                        .scaleEffect(1.0 + 0.12 * detentKick)
                }
                .padding(.top, 14 * k)
                .padding(.trailing, 16 * k)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
                .allowsHitTesting(false)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                        lampPulse = true
                    }
                }
            }
        }
        .mattePanel(k: k, glowColor: activeTint, glowIntensity: detentKick)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onAppear {
            position = Double(index)
            lastDetent = index
        }
        .onChange(of: index) { _, newValue in
            guard base == nil else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.64)) {
                position = Double(newValue)
            }
            triggerDetentImpulse()
        }
        .onChange(of: auto) { _, _ in
            triggerDetentImpulse()
        }
    }

    private func triggerDetentImpulse() {
        detentKick = 1.0
        withAnimation(.spring(response: 0.34, dampingFraction: 0.45)) {
            detentKick = 0.0
        }
        unitBounce = 1.0
        withAnimation(.spring(response: 0.40, dampingFraction: 0.42).delay(0.025)) {
            unitBounce = 0.0
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
                withAnimation(.spring(response: 0.28, dampingFraction: 0.66)) { position = target }
                detent()
                triggerDetentImpulse()
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
        triggerDetentImpulse()
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
            withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
                position = Double(homeIndex)
            }
            lastDetent = homeIndex
            triggerDetentImpulse()
            onHome()
        }
    }
}

private struct ApertureWheel: View, Animatable {
    var position: Double
    var detentKick: Double
    var unitBounce: Double
    let labels: [String]
    let tint: Color
    let auto: Bool
    let k: CGFloat

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { .init(position, .init(detentKick, unitBounce)) }
        set {
            position = newValue.first
            detentKick = newValue.second.first
            unitBounce = newValue.second.second
        }
    }

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let radius = size.width * 0.46
            let anglePerStop = 0.68

            // Sub-animation 1: Parallax vernier click-stop ticks along bottom
            let tickBaseY = size.height - 10 * k
            let minStop = max(0, Int(floor(position)) - 3)
            let maxStop = min(labels.count - 1, Int(ceil(position)) + 3)
            if minStop <= maxStop {
                for i in minStop...maxStop {
                    for subTick in 0..<3 {
                        if i == maxStop && subTick > 0 { continue }
                        let tickIdx = Double(i) + Double(subTick) / 3.0
                        let d = tickIdx - position
                        let theta = d * anglePerStop
                        if abs(theta) >= .pi / 2 { continue }
                        let tx = cx + CGFloat(sin(theta)) * radius
                        let cosT = max(0.0, cos(theta))
                        let isMajor = (subTick == 0)
                        let centerProximity = max(0.0, 1.0 - abs(d) * 2.2)
                        let tickH = ((isMajor ? 7.5 : 4.0) + centerProximity * (4.5 + 3.0 * detentKick)) * k * CGFloat(cosT)

                        var p = Path()
                        p.move(to: CGPoint(x: tx, y: tickBaseY - tickH))
                        p.addLine(to: CGPoint(x: tx, y: tickBaseY))
                        let tickColor = (isMajor && centerProximity > 0.5) ? tint : Palette.textSub
                        ctx.stroke(
                            p,
                            with: .color(tickColor.opacity(cosT * (isMajor ? 0.55 : 0.22))),
                            lineWidth: (isMajor ? 1.5 : 0.9) * k
                        )
                    }
                }
            }

            // Macro + Micro: 3D cylindrical drum projection of f-stops
            for i in labels.indices {
                let d = Double(i) - position
                let theta = d * anglePerStop
                if abs(theta) >= .pi / 2.05 { continue }

                let sinT = sin(theta)
                let cosT = max(0.0, cos(theta))
                let x = cx + CGFloat(sinT) * radius
                let barrelDrop = CGFloat(1.0 - cosT) * 14 * k
                let ad = abs(d)
                let selected = ad < 0.45

                let proximity = max(0.0, 1.0 - ad * 1.8)
                let scalePop = 1.0 + proximity * (0.08 + 0.14 * detentKick)
                let depthScale = CGFloat(0.76 + 0.24 * cosT) * CGFloat(scalePop)

                let color: Color = selected ? tint : Palette.textSub.opacity(max(0.25, pow(cosT, 1.4) * 0.85))

                var numCtx = ctx
                numCtx.translateBy(x: x, y: 100 * k + barrelDrop)
                numCtx.scaleBy(x: depthScale, y: depthScale)
                let text = Text(labels[i])
                    .font(AppTypography.numeral(size: 38 * k, weight: selected ? .semibold : .medium))
                    .foregroundColor(color)
                numCtx.draw(numCtx.resolve(text), at: .zero, anchor: .center)

                // Sub-animation 2: Staggered elastic bounce on unit label
                var unitCtx = ctx
                let unitOffset = selected ? CGFloat(unitBounce) * 5.5 * k : 0
                let unitScale = CGFloat(0.80 + 0.20 * cosT) * (selected ? CGFloat(1.0 + 0.10 * unitBounce) : 1.0)
                unitCtx.translateBy(x: x, y: 142 * k + barrelDrop + unitOffset)
                unitCtx.scaleBy(x: unitScale, y: unitScale)
                let unit = Text(selected && auto ? "auto" : "f/")
                    .font(AppTypography.next(size: 22 * k, weight: selected ? .medium : .regular))
                    .foregroundColor(color)
                unitCtx.draw(unitCtx.resolve(unit), at: .zero, anchor: .center)
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}
