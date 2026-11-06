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
        let sub: String = r.deviation.map { Fmt.exposureAmount($0) + " EV" } ?? (r.isSlow ? "slow" : "sec")

        ZStack(alignment: .top) {
            ShutterWheel(position: position, labels: currentLabels, tint: tint, sub: sub, k: k)
            PanelTitle(text: "SHUTTER", k: k)
        }
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
            let pitch = 118 * k

            for i in labels.indices {
                let d = Double(i) - position
                let ad = abs(d)
                if ad > 1.45 { continue }
                let x = cx + CGFloat(d) * pitch
                let t = max(0.0, 1.0 - ad)
                let active = ad < 0.45
                let color: Color = active ? tint : Palette.textSub
                let fontSize: CGFloat = (28.0 + 20.0 * t) * k
                let opacity = active ? 1.0 : max(0.0, 0.42 * (1.0 - (ad - 0.3) / 1.15))

                let rawLabel = labels[i]
                let displayStr = rawLabel.hasSuffix("\"") ? rawLabel : (active ? "1/\(rawLabel)" : rawLabel)
                let number = Text(displayStr)
                    .font(AppTypography.numeral(size: fontSize, weight: active ? .semibold : .regular))
                    .foregroundColor(color.opacity(opacity))
                ctx.draw(ctx.resolve(number), at: CGPoint(x: x, y: 102 * k), anchor: .center)
            }

            let subColor = (sub == "sec") ? Palette.textDim : tint
            let unit = Text(sub)
                .font(AppTypography.next(size: 18 * k, weight: sub == "sec" ? .medium : .semibold))
                .foregroundColor(subColor.opacity(0.85))
            ctx.draw(ctx.resolve(unit), at: CGPoint(x: cx, y: 150 * k), anchor: .center)
        }
        .wheelEdgeMask()
        .clipped()
        .allowsHitTesting(false)
    }
}
