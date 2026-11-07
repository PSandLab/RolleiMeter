import SwiftUI

// MARK: - Shutter (3D cylindrical drum + detent kick + parallax vernier sub-ticks)

struct ShutterPanel: View {
    @ObservedObject var damp: Damper
    let iso: Double
    let comp: Double
    let aperture: (label: String, n: Double)
    var speeds: [(label: String, t: Double)] = Rollei.speeds
    let k: CGFloat

    private var labels: [String] { speeds.reversed().map { $0.label } }

    private var reading: ShutterResult {
        let t = Exposure.idealShutter(ev100: damp.values[0], iso: iso, comp: comp, n: aperture.n)
        return Exposure.result(for: t, speeds: speeds)
    }

    @State private var position: Double = 0
    @State private var detentKick: Double = 0
    @State private var unitBounce: Double = 0

    var body: some View {
        let r = reading
        let currentLabels = labels
        let index = currentLabels.firstIndex(of: r.label) ?? 0
        let tint: Color = r.deviation != nil ? Palette.bad : Palette.accent
        let sub: String = r.deviation.map { Fmt.exposureAmount($0) + " EV" } ?? (r.isSlow ? "slow" : "sec")

        ZStack(alignment: .top) {
            ShutterWheel(
                position: position,
                detentKick: detentKick,
                unitBounce: unitBounce,
                labels: currentLabels,
                tint: tint,
                sub: sub,
                k: k
            )
            PanelTitle(text: "SHUTTER", k: k)
                .scaleEffect(1.0 + 0.03 * detentKick)
        }
        .overlay(alignment: .bottomLeading) {
            BrassDialLimitPin(isEngaged: index == 0, scale: k)
                .padding(.leading, 14 * k)
                .padding(.bottom, 12 * k)
        }
        .overlay(alignment: .bottomTrailing) {
            BrassDialLimitPin(isEngaged: index == currentLabels.count - 1, scale: k)
                .padding(.trailing, 14 * k)
                .padding(.bottom, 12 * k)
        }
        .mattePanel(k: k, glowColor: tint, glowIntensity: detentKick)
        .onAppear { position = Double(index) }
        .onChange(of: index) { _, newIndex in
            // Macro: Underdamped spring drum rotation
            withAnimation(.spring(response: 0.28, dampingFraction: 0.64)) {
                position = Double(newIndex)
            }
            // Micro: Detent kick impulse
            detentKick = 1.0
            withAnimation(.spring(response: 0.36, dampingFraction: 0.45)) {
                detentKick = 0.0
            }
            // Sub: Staggered unit vertical bounce
            unitBounce = 1.0
            withAnimation(.spring(response: 0.42, dampingFraction: 0.42).delay(0.03)) {
                unitBounce = 0.0
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shutter speed")
        .accessibilityValue(r.deviation == nil ? (r.label.hasSuffix("\"") ? "\(r.label) seconds" : "1/\(r.label) second") : sub)
    }
}

private struct ShutterWheel: View, Animatable {
    var position: Double
    var detentKick: Double
    var unitBounce: Double
    let labels: [String]
    let tint: Color
    let sub: String
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
            let radius = size.width * 0.48
            let anglePerStop = 0.72 // radians per stop on virtual cylinder

            // Sub-animation 1: Dual-layer parallax vernier scale along bottom
            let tickBaseY = size.height - 10 * k
            let minStop = max(0, Int(floor(position)) - 3)
            let maxStop = min(labels.count - 1, Int(ceil(position)) + 3)
            if minStop <= maxStop {
                for i in minStop...maxStop {
                    for subTick in 0..<4 {
                        if i == maxStop && subTick > 0 { continue }
                        let tickIdx = Double(i) + Double(subTick) / 4.0
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

            // Macro + Micro: 3D cylindrical drum projection of shutter numerals
            for i in labels.indices {
                let d = Double(i) - position
                let theta = d * anglePerStop
                if abs(theta) >= .pi / 2.05 { continue }

                let sinT = sin(theta)
                let cosT = max(0.0, cos(theta))
                let x = cx + CGFloat(sinT) * radius
                let barrelDrop = CGFloat(1.0 - cosT) * 14 * k
                let ad = abs(d)
                let active = ad < 0.45

                // Micro scale pop on the active stop during detent kick
                let proximity = max(0.0, 1.0 - ad * 1.8)
                let scalePop = 1.0 + proximity * (0.08 + 0.14 * detentKick)
                let depthScale = CGFloat(0.76 + 0.24 * cosT) * CGFloat(scalePop)

                let color: Color = active ? tint : Palette.textSub.opacity(max(0.25, pow(cosT, 1.4) * 0.85))
                let rawLabel = labels[i]
                let displayStr = rawLabel.hasSuffix("\"") ? rawLabel : ("1/" + rawLabel)

                var numCtx = ctx
                numCtx.translateBy(x: x, y: 100 * k + barrelDrop)
                numCtx.scaleBy(x: depthScale, y: depthScale)
                let number = Text(displayStr)
                    .font(AppTypography.numeral(size: 38 * k, weight: active ? .semibold : .medium))
                    .foregroundColor(color)
                numCtx.draw(numCtx.resolve(number), at: .zero, anchor: .center)

                // Sub-animation 2: Staggered elastic bounce on the unit label
                var unitCtx = ctx
                let unitOffset = active ? CGFloat(unitBounce) * 5.5 * k : 0
                let unitScale = CGFloat(0.80 + 0.20 * cosT) * (active ? CGFloat(1.0 + 0.10 * unitBounce) : 1.0)
                unitCtx.translateBy(x: x, y: 142 * k + barrelDrop + unitOffset)
                unitCtx.scaleBy(x: unitScale, y: unitScale)
                let unit = Text(active ? sub : "sec")
                    .font(AppTypography.next(size: 22 * k, weight: active ? .medium : .regular))
                    .foregroundColor(color)
                unitCtx.draw(unitCtx.resolve(unit), at: .zero, anchor: .center)
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}
