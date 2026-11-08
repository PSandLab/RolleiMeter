import SwiftUI
import UIKit

// MARK: - Film speed (Solid Yellow Card + 3D Rubber-Band Cutout Kinematics)

struct FilmPanel: View {
    @Binding var isoIndex: Int
    let useDIN: Bool
    let filmName: String
    let boxISO: Int
    var isUnloaded: Bool = false
    var cameraBadge: String = ""
    let k: CGFloat
    let onTap: () -> Void

    @State private var dragBase: Int?
    @State private var dragOffset: CGFloat = 0
    @State private var isoPulse: Double = 0
    @State private var cardPressed: Bool = false

    private var safeIndex: Int { min(max(isoIndex, 0), ISOScale.values.count - 1) }
    private var currentISO: Int { ISOScale.values[safeIndex] }

    private var speedText: String {
        let value = ISOScale.label(currentISO, din: useDIN)
        return useDIN ? value : "ISO " + value
    }

    private var cleanStockName: String {
        let stripped = filmName.replacingOccurrences(
            of: "\\s+\(boxISO)$",
            with: "",
            options: .regularExpression
        )
        return stripped.isEmpty ? filmName : stripped
    }

    private var readout: String {
        if isUnloaded {
            return dragBase != nil ? speedText : "Load Film"
        }
        return "\(cleanStockName)  \u{2022}  \(speedText)"
    }

    var body: some View {
        let hasCam = !cameraBadge.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isPullOrPush = !isUnloaded && currentISO != boxISO

        ZStack(alignment: .top) {
            Color.clear
                .background(Palette.accent, in: .rect(cornerRadius: 22 * k, style: .continuous))

            PanelTitle(
                text: hasCam ? cameraBadge.uppercased() : "FILM",
                k: k,
                color: Palette.accentInk
            )
            .padding(.horizontal, 14 * k)
            .scaleEffect(1.0 + 0.03 * isoPulse)

            ZStack {
                RoundedRectangle(cornerRadius: 14 * k, style: .continuous)
                    .fill(Palette.accentInk)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14 * k, style: .continuous)
                            .strokeBorder(
                                Palette.accent.opacity(isPullOrPush ? (0.45 + 0.45 * isoPulse) : (0.35 * isoPulse)),
                                lineWidth: (1.0 + 1.2 * isoPulse) * k
                            )
                    )

                if isPullOrPush {
                    // Parallax Detent Scale along bottom inner edge
                    Canvas { ctx, size in
                        let midX = size.width * 0.5
                        let bottomY = size.height - 2 * k
                        let tickSpacing: CGFloat = 8 * k
                        for i in -7...7 {
                            let tx = midX + CGFloat(i) * tickSpacing - dragOffset * 0.65
                            guard tx >= 8 * k && tx <= size.width - 8 * k else { continue }
                            let isCenter = i == 0
                            let tickH: CGFloat = isCenter ? 4 * k : 2.2 * k
                            var p = Path()
                            p.move(to: CGPoint(x: tx, y: bottomY - tickH))
                            p.addLine(to: CGPoint(x: tx, y: bottomY))
                            ctx.stroke(p, with: .color(isCenter ? Palette.accent : Color.white.opacity(0.18)), lineWidth: 1.0 * k)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14 * k, style: .continuous))
                    .allowsHitTesting(false)
                }

                Text(readout)
                    .font(AppTypography.next(size: (isPullOrPush ? 23 : 27) * k, weight: .medium).monospacedDigit())
                    .foregroundStyle(isUnloaded || isPullOrPush ? Palette.accent : Palette.onInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .padding(.horizontal, 14 * k)
                    .scaleEffect(1.0 + 0.08 * isoPulse)
                    .offset(x: dragOffset * 0.35, y: isPullOrPush ? -7 * k : 0)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.24, dampingFraction: 0.62), value: readout)

                if isPullOrPush {
                    let evStops = log2(Double(currentISO) / Double(max(boxISO, 1)))
                    let formattedStops = String(format: "%+.1f", evStops).replacingOccurrences(of: ".0", with: "")
                    let pushPullTag = evStops > 0 ? "PUSH \(formattedStops)" : "PULL \(formattedStops)"

                    VStack(spacing: 0) {
                        Spacer()
                        HStack(spacing: 6 * k) {
                            // Struck-through original box ISO
                            Text("\(boxISO)")
                                .font(AppTypography.next(size: 11 * k, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Palette.onInk.opacity(0.55))
                                .strikethrough(true, color: Palette.accent)

                            // Push/Pull Stop Badge
                            Text(pushPullTag)
                                .font(.system(size: 9.5 * k, weight: .bold, design: .monospaced))
                                .foregroundStyle(Palette.accent)
                                .padding(.horizontal, 5 * k)
                                .padding(.vertical, 1.5 * k)
                                .background(Palette.accent.opacity(0.16), in: Capsule())
                        }
                        .offset(x: -dragOffset * 0.45)
                        .padding(.bottom, 3 * k)
                    }
                }
            }
            .offset(x: dragOffset)
            .rotation3DEffect(
                .degrees(Double(dragOffset / max(1, k)) * 0.45),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.6
            )
            .padding(.horizontal, 16 * k)
            .padding(.top, 60 * k)
            .padding(.bottom, 16 * k)
        }
        .scaleEffect(cardPressed ? 0.96 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.16, dampingFraction: 0.5)) { cardPressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.52)) { cardPressed = false }
            }
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            guard let box = ISOScale.values.firstIndex(of: boxISO), isoIndex != box else { return }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
            triggerISOPulse(strength: 1.3)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                isoIndex = box
            }
        }
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    if dragBase == nil { dragBase = safeIndex }
                    // Rubber-band displacement of the inner cutout
                    let rawDrag = value.translation.width
                    withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.7)) {
                        dragOffset = max(-14 * k, min(14 * k, rawDrag * 0.18))
                    }

                    let steps = Int((rawDrag / (26 * k)).rounded())
                    let target = min(max((dragBase ?? safeIndex) + steps, 0), ISOScale.values.count - 1)
                    guard target != isoIndex else { return }
                    isoIndex = target
                    triggerISOPulse(strength: ISOScale.values[target] == boxISO ? 1.25 : 0.85)
                    if ISOScale.values[target] == boxISO {
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
                    } else {
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                }
                .onEnded { _ in
                    dragBase = nil
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.52)) {
                        dragOffset = 0
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Film")
        .accessibilityValue(readout)
        .accessibilityHint("Tap to choose film, drag horizontally to rate ISO")
    }

    private func triggerISOPulse(strength: Double) {
        isoPulse = strength
        withAnimation(.spring(response: 0.36, dampingFraction: 0.45)) {
            isoPulse = 0.0
        }
    }
}
