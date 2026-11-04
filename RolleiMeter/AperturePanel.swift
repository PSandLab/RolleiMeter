import SwiftUI
import UIKit

// MARK: - Aperture (Hero Wheel Card)

enum AutoLampState {
    case off, good, slow, bad
}

struct AperturePanel: View {
    let index: Int
    var stops: [(label: String, n: Double)] = Rollei.stops
    let auto: Bool
    let lamp: AutoLampState
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
    private var pitch: CGFloat { 56 }

    private var accentColor: Color {
        if auto {
            switch lamp {
            case .bad: return Color(red: 1.0, green: 0.27, blue: 0.23)
            case .slow: return .orange
            case .good, .off: return Color(red: 0.19, green: 0.82, blue: 0.35)
            }
        }
        return Color(red: 0.19, green: 0.82, blue: 0.35)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("APERTURE")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)

                Spacer()

                if auto {
                    Text("AUTO")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accentColor.opacity(0.16), in: Capsule())
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 11)
            .padding(.bottom, 7)

            Divider()
                .overlay(Color.white.opacity(0.07))

            Spacer(minLength: 0)

            ApertureWheel(
                position: position,
                labels: stops.map { $0.label },
                accentColor: accentColor,
                subtitleUnit: "f-stop"
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aperture")
        .accessibilityValue("f/\(stops[min(max(index, 0), max(0, stops.count - 1))].label)" + (auto ? ", Auto" : ""))
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
            let pitch: CGFloat = 56

            for i in labels.indices {
                let d = Double(i) - position
                let x = cx + CGFloat(d) * pitch
                if x < -pitch || x > size.width + pitch { continue }
                let ad = abs(d)
                let selected = ad < 0.5

                if selected {
                    let text = Text(labels[i])
                        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(accentColor)
                    ctx.draw(ctx.resolve(text), at: CGPoint(x: x, y: numberY), anchor: .center)

                    let unit = Text(subtitleUnit)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(accentColor.opacity(0.75))
                    ctx.draw(ctx.resolve(unit), at: CGPoint(x: x, y: unitY), anchor: .center)
                } else {
                    let neighborOpacity = max(0.18, 0.55 - 0.25 * (ad - 1.0))
                    let text = Text(labels[i])
                        .font(.system(size: 19, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundColor(Color.secondary.opacity(neighborOpacity))
                    ctx.draw(ctx.resolve(text), at: CGPoint(x: x, y: numberY), anchor: .center)
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}
