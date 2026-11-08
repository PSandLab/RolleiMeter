import SwiftUI
import UIKit

// MARK: - Peaking overlay (Pure LiDAR DoF wash)

struct PeakingOverlay: View {
    @ObservedObject var feed: PeakingFeed

    var body: some View {
        ZStack {
            if let image = feed.image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Hold button (Stadium Card + Rotating Telemetry Bezel + Liquid Morphing)

struct HoldControl: View {
    let frozen: Bool
    var frameNumber: Int = 1
    var isSaved: Bool = false
    let k: CGFloat
    let modes: [MeterMode]
    let meterIndex: Int
    let onPickMeter: (Int) -> Void
    let onHold: () -> Void
    var onConfirmLog: () -> Void = {}
    var onDiscardHold: () -> Void = {}

    @Namespace private var morphNamespace
    @Namespace private var modePillNamespace
    @State private var isScrubbingMeter: Bool = false
    @State private var ringRotation: Double = 0.0
    @State private var ringKick: Double = 0.0
    @State private var shockwave: Double = 1.0
    @State private var dotPulse: Bool = false

    var body: some View {
        let stadiumShape = UnevenRoundedRectangle(
            topLeadingRadius: 22 * k,
            bottomLeadingRadius: 22 * k,
            bottomTrailingRadius: 105 * k,
            topTrailingRadius: 105 * k,
            style: .continuous
        )

        ZStack {
            stadiumShape
                .fill(Palette.panel)
                .overlay(
                    stadiumShape
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )

            if !frozen {
                HStack(spacing: 0) {
                    smoothMeterSelector
                        .padding(.leading, 14 * k)
                    Spacer(minLength: 0)
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.82, anchor: .leading).combined(with: .opacity),
                    removal: .scale(scale: 0.88, anchor: .leading).combined(with: .opacity)
                ))
            }

            HStack {
                Spacer(minLength: 0)
                GlassEffectContainer(spacing: 16 * k) {
                    shutterOrMorphedActions
                }
            }
            .padding(.trailing, 18 * k)
            .padding(.leading, frozen ? 18 * k : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(stadiumShape)
        .animation(.spring(response: 0.32, dampingFraction: 0.68), value: frozen)
        .animation(.spring(response: 0.28, dampingFraction: 0.65), value: isSaved)
        .onAppear {
            withAnimation(.linear(duration: 22).repeatForever(autoreverses: false)) {
                ringRotation = 360.0
            }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                dotPulse = true
            }
        }
        .onChange(of: meterIndex) { _, _ in
            withAnimation(.spring(response: 0.36, dampingFraction: 0.52)) {
                ringKick += 45.0
            }
        }
    }

    private var smoothMeterSelector: some View {
        let rowHeight: CGFloat = 46 * k
        let totalHeight: CGFloat = rowHeight * CGFloat(max(modes.count, 1))

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(modes.indices, id: \.self) { i in
                let selected = (i == meterIndex)
                ZStack(alignment: .leading) {
                    if selected {
                        Capsule()
                            .fill(Color.white.opacity(isScrubbingMeter ? 0.11 : 0.06))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Palette.accent.opacity(isScrubbingMeter ? 0.45 : 0.22), lineWidth: 1)
                            )
                            .scaleEffect(x: isScrubbingMeter ? 1.05 : 1.0, y: isScrubbingMeter ? 0.94 : 1.0)
                            .matchedGeometryEffect(id: "activeModePill", in: modePillNamespace)
                    }

                    HStack(spacing: 9 * k) {
                        ZStack {
                            if selected {
                                Circle()
                                    .fill(Palette.accent.opacity(dotPulse ? 0.38 : 0.10))
                                    .frame(width: 14 * k, height: 14 * k)
                                    .scaleEffect(dotPulse ? 1.35 : 0.85)
                            }
                            Circle()
                                .fill(selected ? Palette.accent : Palette.faint)
                                .frame(width: 6.5 * k, height: 6.5 * k)
                        }
                        .frame(width: 12 * k, height: 12 * k)

                        Text(modes[i].title.lowercased())
                            .font(AppTypography.next(size: 23 * k, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Palette.text : Palette.textDim)
                            .offset(x: selected && isScrubbingMeter ? 2 * k : 0)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12 * k)
                }
                .frame(width: 132 * k, height: rowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .scaleEffect(isScrubbingMeter ? 1.04 : 1.0)
        .animation(.spring(response: 0.26, dampingFraction: 0.62), value: meterIndex)
        .animation(.spring(response: 0.22, dampingFraction: 0.60), value: isScrubbingMeter)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isScrubbingMeter { isScrubbingMeter = true }
                    let rawIdx = Int((value.location.y / max(rowHeight, 1)).rounded(.down))
                    let clamped = min(max(rawIdx, 0), modes.count - 1)
                    if clamped != meterIndex {
                        UISelectionFeedbackGenerator().selectionChanged()
                        onPickMeter(clamped)
                    }
                }
                .onEnded { _ in
                    isScrubbingMeter = false
                }
        )
        .frame(height: totalHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Metering mode")
        .accessibilityValue(modes[min(max(meterIndex, 0), modes.count - 1)].title)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                let next = min(meterIndex + 1, modes.count - 1)
                if next != meterIndex { onPickMeter(next) }
            case .decrement:
                let prev = max(meterIndex - 1, 0)
                if prev != meterIndex { onPickMeter(prev) }
            @unknown default:
                break
            }
        }
    }

    @ViewBuilder
    private var shutterOrMorphedActions: some View {
        if frozen {
            HStack(spacing: 18 * k) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onDiscardHold()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Palette.bad.opacity(0.18))
                        Image(systemName: "xmark")
                            .font(.system(size: 30 * k, weight: .bold))
                            .foregroundStyle(Palette.bad)
                    }
                    .frame(width: 112 * k, height: 112 * k)
                    .contentShape(Circle())
                    .glassEffect(.regular.tint(Palette.bad.opacity(0.24)).interactive(), in: Circle())
                    .glassEffectID("holdDiscard", in: morphNamespace)
                }
                .buttonStyle(PressStyle(scale: 0.88))
                .accessibilityLabel("Discard reading")

                Button {
                    guard !isSaved else { return }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onConfirmLog()
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(
                                Palette.good.opacity(0.45),
                                style: StrokeStyle(lineWidth: 1.5, dash: [6 * k, 4 * k])
                            )
                            .frame(width: 156 * k, height: 156 * k)
                            .rotationEffect(.degrees(-ringRotation * 1.5))

                        Circle()
                            .fill(Palette.good)
                            .frame(width: 126 * k, height: 126 * k)
                            .scaleEffect(isSaved ? 1.08 : 1.0)

                        Image(systemName: "checkmark")
                            .font(.system(size: 38 * k, weight: .bold))
                            .foregroundStyle(Palette.accentInk)
                            .scaleEffect(isSaved ? 1.18 : 1.0)
                    }
                    .frame(width: 156 * k, height: 156 * k)
                    .contentShape(Circle())
                    .glassEffect(.regular.tint(Palette.good.opacity(0.28)).interactive(), in: Circle())
                    .glassEffectID("holdPrimary", in: morphNamespace)
                }
                .buttonStyle(PressStyle(scale: 0.90))
                .accessibilityLabel("Log frame \(frameNumber)")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            Button {
                shockwave = 0.0
                withAnimation(.easeOut(duration: 0.45)) {
                    shockwave = 1.0
                }
                onHold()
            } label: {
                ZStack {
                    // Expanding shutter shockwave ring on press
                    if shockwave < 1.0 {
                        Circle()
                            .stroke(Palette.accent.opacity(1.0 - shockwave), lineWidth: 2.5 * k)
                            .frame(width: 124 * k, height: 124 * k)
                            .scaleEffect(1.0 + 0.42 * shockwave)
                    }

                    // Outer concentric telemetry ring
                    Circle()
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1.2)
                        .frame(width: 162 * k, height: 162 * k)

                    // Continuously rotating dashed technical ring + mode kick
                    Circle()
                        .strokeBorder(
                            Color.white.opacity(0.24),
                            style: StrokeStyle(lineWidth: 1.2, dash: [5 * k, 5 * k])
                        )
                        .frame(width: 142 * k, height: 142 * k)
                        .rotationEffect(.degrees(ringRotation + ringKick))

                    // Pure white tactile shutter plunger
                    Circle()
                        .fill(Color.white)
                        .frame(width: 122 * k, height: 122 * k)
                }
                .frame(width: 162 * k, height: 162 * k)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: Circle())
                .glassEffectID("holdPrimary", in: morphNamespace)
            }
            .buttonStyle(PressStyle(scale: 0.91))
            .accessibilityLabel("Hold reading")
        }
    }
}

// MARK: - Viewfinder overlays

struct EVChip: View {
    @ObservedObject var damp: Damper
    let frozen: Bool
    let spot: Bool

    @State private var pulse = false

    var body: some View {
        let readingStr = String(format: "%.1f", damp.values[0])
        HStack(spacing: 6) {
            Circle()
                .fill(frozen ? Palette.accent : (spot ? Palette.good : Palette.textSub))
                .frame(width: 5.5, height: 5.5)
                .scaleEffect(pulse ? 1.3 : 0.85)

            if frozen {
                Text("HOLD")
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.accent)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
            if spot {
                Text("SPOT")
                    .fontWeight(.semibold)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
            Text("EV " + readingStr)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Palette.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Palette.panel.opacity(0.92), in: .capsule)
        .overlay(
            Capsule()
                .strokeBorder(frozen ? Palette.accent.opacity(0.45) : Palette.border, lineWidth: 0.75)
        )
        .animation(.spring(response: 0.30, dampingFraction: 0.68), value: frozen)
        .animation(.spring(response: 0.30, dampingFraction: 0.68), value: spot)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - LiDAR marker (Dual Staggered Sonar Pings + Locking Crosshair)

private struct FocusPing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded1 = false
    @State private var expanded2 = false
    let tooClose: Bool

    var body: some View {
        let color = tooClose ? Palette.bad : Palette.lensLight
        ZStack {
            Circle()
                .stroke(color, lineWidth: 1.4)
                .frame(width: 26, height: 26)
                .scaleEffect(expanded1 ? 2.1 : 0.5)
                .opacity(expanded1 ? 0 : 0.75)

            Circle()
                .stroke(color, lineWidth: 1.0)
                .frame(width: 26, height: 26)
                .scaleEffect(expanded2 ? 1.65 : 0.4)
                .opacity(expanded2 ? 0 : 0.55)
        }
        .onAppear {
            if reduceMotion {
                expanded1 = true
                expanded2 = true
            } else {
                withAnimation(.easeOut(duration: 0.52)) { expanded1 = true }
                withAnimation(.easeOut(duration: 0.48).delay(0.10)) { expanded2 = true }
            }
        }
        .accessibilityHidden(true)
    }
}

struct FocusMarker: View {
    let tooClose: Bool
    var pulseID: Int = 0

    @State private var lockAngle: Double = 0

    var body: some View {
        let color = tooClose ? Palette.bad : Palette.lensLight
        ZStack {
            if pulseID > 0 {
                FocusPing(tooClose: tooClose).id(pulseID)
            }

            // Outer ring + 4 locking rangefinder crosshair ticks
            ZStack {
                Circle()
                    .stroke(color.opacity(0.95), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 26, height: 26)

                ForEach(0..<4, id: \.self) { i in
                    Rectangle()
                        .fill(color.opacity(0.85))
                        .frame(width: 1.4, height: 4.5)
                        .offset(y: -13)
                        .rotationEffect(.degrees(Double(i) * 90.0))
                }
            }
            .rotationEffect(.degrees(lockAngle))
            .scaleEffect(tooClose ? 0.84 : 1.0)

            Circle()
                .fill(color)
                .frame(width: 3.5, height: 3.5)
        }
        .frame(width: 34, height: 34)
        .shadow(color: Color.black.opacity(0.65), radius: 2, x: 0, y: 1)
        .animation(.spring(response: 0.26, dampingFraction: 0.58), value: tooClose)
        .onChange(of: pulseID) { _, _ in
            withAnimation(.spring(response: 0.34, dampingFraction: 0.56)) {
                lockAngle += 90.0
            }
        }
        .allowsHitTesting(false)
    }
}
