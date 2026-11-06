import SwiftUI

// MARK: - Shutter (read-out wheel)

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

    var body: some View {
        let r = reading
        let currentLabels = labels
        let index = currentLabels.firstIndex(of: r.label) ?? 0
        let tint: Color = r.deviation != nil ? Palette.bad : (r.isSlow ? Palette.slow : Palette.accent)
        let activeDisplay = r.label.hasSuffix("\"") ? "\(r.label) SEC" : "1/\(r.label) SEC"
        let sub: String = r.deviation.map { Fmt.exposureAmount($0) + " EV" } ?? (r.isSlow ? "SLOW · \(activeDisplay)" : activeDisplay)

        ZStack(alignment: .top) {
            ShutterWheel(position: position, labels: currentLabels, tint: tint, sub: sub, k: k)

            PanelTitle(text: "SHUTTER", k: k)

            DialIndexPointer(k: k, color: tint)
                .padding(.top, 46 * k)
        }
        .instrumentBay(k: k)
        .onAppear { position = Double(index) }
        .onChange(of: index) { _, newIndex in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                position = Double(newIndex)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shutter speed")
        .accessibilityValue(r.deviation == nil ? (r.label.hasSuffix("\"") ? "\(r.label) seconds" : "1/\(r.label) second") : sub)
    }
}

private struct ShutterWheel: View, Animatable {
    var position: Double
    let labels: [String]
    let tint: Color
    let sub: String
    let k: CGFloat

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let pitch = 92 * k

            // Bottom knurled scale ticks that rotate with the drum
            let tickBaseY = size.height - 14 * k
            let subSteps = 4
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
                            with: .color((isMajor && abs(dTick) < 0.25 ? tint : Palette.textSub).opacity(fade * (isMajor ? 0.55 : 0.25))),
                            lineWidth: (isMajor ? 1.6 : 1.0) * k
                        )
                    }
                }
            }

            // Engraved shutter speed numerals
            for i in labels.indices {
                let d = Double(i) - position
                let x = cx + CGFloat(d) * pitch
                if x < -pitch || x > size.width + pitch { continue }
                let ad = abs(d)
                let active = ad < 0.45
                let color: Color = active ? tint : Palette.textSub
                let fontSize: CGFloat = (active ? 64 : 42) * k
                let opacity = active ? 1.0 : max(0.18, 0.68 - 0.32 * ad)

                let number = Text(labels[i])
                    .font(AppTypography.numeral(size: fontSize, weight: active ? .bold : .medium))
                    .foregroundColor(color.opacity(opacity))
                ctx.draw(ctx.resolve(number), at: CGPoint(x: x, y: 102 * k), anchor: .center)
            }

            // Center active subtitle readout
            let subText = Text(sub)
                .font(AppTypography.numeral(size: 20 * k, weight: .semibold))
                .foregroundColor(tint.opacity(0.92))
            ctx.draw(ctx.resolve(subText), at: CGPoint(x: cx, y: 154 * k), anchor: .center)
        }
        .clipped()
        .allowsHitTesting(false)
    }
}
