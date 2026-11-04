import SwiftUI

// MARK: - Shutter (Hero Read-Out Wheel Card)

struct ShutterPanel: View {
    @ObservedObject var damp: Damper
    let iso: Double
    let comp: Double
    let aperture: (label: String, n: Double)
    var speeds: [(label: String, t: Double)] = Rollei.speeds
    var isHeld: Bool = false

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
        let accentColor: Color = r.deviation != nil
            ? Color(red: 1.0, green: 0.27, blue: 0.23)
            : (r.isSlow ? .orange : Color(red: 1.0, green: 0.84, blue: 0.04))
        let subtitleUnit: String = r.deviation.map { Fmt.exposureAmount($0) + " EV" } ?? (r.isSlow ? "slow" : "sec")
        let badgeText: String? = r.deviation != nil ? "OVER/UNDER" : (isHeld ? "HOLD" : nil)

        VStack(spacing: 0) {
            // Header
            HStack {
                Text("SHUTTER")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)

                Spacer()

                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accentColor.opacity(0.16), in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 11)
            .padding(.bottom, 7)

            Divider()
                .overlay(Color.white.opacity(0.07))

            Spacer(minLength: 0)

            ShutterWheel(
                position: position,
                labels: currentLabels,
                accentColor: accentColor,
                subtitleUnit: subtitleUnit
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: 0.18),
                        .init(color: .black, location: 0.82),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

            Spacer(minLength: 0)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .onAppear { position = Double(index) }
        .onChange(of: index) { _, newIndex in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                position = Double(newIndex)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shutter speed")
        .accessibilityValue(r.deviation == nil ? (r.label.hasSuffix("\"") ? "\(r.label) seconds" : "1/\(r.label) second") : subtitleUnit)
    }
}

private struct ShutterWheel: View, Animatable {
    var position: Double
    let labels: [String]
    let accentColor: Color
    let subtitleUnit: String

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let numberY = size.height * 0.42
            let unitY = numberY + 22
            let pitch: CGFloat = 62

            for i in labels.indices {
                let d = Double(i) - position
                let x = cx + CGFloat(d) * pitch
                if x < -pitch || x > size.width + pitch { continue }
                let ad = abs(d)
                let active = ad < 0.5

                let rawLabel = labels[i]
                let displayStr = rawLabel.hasSuffix("\"") ? rawLabel : ("1/" + rawLabel)

                if active {
                    let number = Text(displayStr)
                        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(accentColor)
                    ctx.draw(ctx.resolve(number), at: CGPoint(x: x, y: numberY), anchor: .center)

                    let unit = Text(subtitleUnit)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(accentColor.opacity(0.75))
                    ctx.draw(ctx.resolve(unit), at: CGPoint(x: x, y: unitY), anchor: .center)
                } else {
                    let neighborOpacity = max(0.18, 0.55 - 0.25 * (ad - 1.0))
                    let number = Text(displayStr)
                        .font(.system(size: 19, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundColor(Color.secondary.opacity(neighborOpacity))
                    ctx.draw(ctx.resolve(number), at: CGPoint(x: x, y: numberY), anchor: .center)
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}
