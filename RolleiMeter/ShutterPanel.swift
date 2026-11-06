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
        let tint: Color = r.deviation != nil ? Palette.bad : Palette.accent
        let sub: String = r.deviation.map { Fmt.exposureAmount($0) + " EV" } ?? (r.isSlow ? "slow" : "sec")

        ZStack(alignment: .top) {
            ShutterWheel(position: position, labels: currentLabels, tint: tint, sub: sub, k: k)
            PanelTitle(text: "SHUTTER", k: k)
        }
        .mattePanel(k: k)
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
            let pitch = size.width * 0.42
            for i in labels.indices {
                let d = Double(i) - position
                let x = cx + CGFloat(d) * pitch
                if x < -pitch || x > size.width + pitch { continue }
                let ad = abs(d)
                let active = ad < 0.5
                let color: Color = active ? tint : Palette.textSub.opacity(max(0.35, 0.85 - 0.35 * ad))

                let rawLabel = labels[i]
                let displayStr = rawLabel.hasSuffix("\"") ? rawLabel : ("1/" + rawLabel)
                let number = Text(displayStr)
                    .font(AppTypography.numeral(size: 38 * k, weight: .medium))
                    .foregroundColor(color)
                ctx.draw(ctx.resolve(number), at: CGPoint(x: x, y: 104 * k), anchor: .center)

                let unit = Text(active ? sub : "sec")
                    .font(AppTypography.next(size: 22 * k, weight: .regular))
                    .foregroundColor(color)
                ctx.draw(ctx.resolve(unit), at: CGPoint(x: x, y: 144 * k), anchor: .center)
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}
