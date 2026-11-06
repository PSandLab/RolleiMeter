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

// MARK: - Hold button

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
    @Namespace private var meterSlideNamespace
    @State private var isScrubbingMeter: Bool = false

    var body: some View {
        ZStack {
            if !frozen {
                HStack(spacing: 0) {
                    smoothMeterSelector
                        .padding(.leading, 14 * k)

                    Spacer(minLength: 0)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .leading)))
            }

            HStack {
                Spacer(minLength: 0)
                shutterOrMorphedActions
            }
            .padding(.trailing, 14 * k)
            .padding(.leading, frozen ? 14 * k : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .instrumentBay(k: k)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: frozen)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isSaved)
    }

    private var smoothMeterSelector: some View {
        let rowHeight: CGFloat = 48 * k
        let totalHeight: CGFloat = rowHeight * CGFloat(max(modes.count, 1))

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(modes.indices, id: \.self) { i in
                let selected = (i == meterIndex)
                ZStack(alignment: .leading) {
                    if selected {
                        Capsule()
                            .fill(Palette.accent.opacity(isScrubbingMeter ? 0.24 : 0.16))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Palette.accent.opacity(0.65), lineWidth: 1)
                            )
                            .matchedGeometryEffect(id: "meterModePill", in: meterSlideNamespace)
                    }

                    HStack(spacing: 9 * k) {
                        Circle()
                            .fill(selected ? Palette.accent : Palette.faint)
                            .frame(width: 7.5 * k, height: 7.5 * k)

                        Text(modes[i].title.uppercased())
                            .font(AppTypography.next(size: 21 * k, weight: selected ? .bold : .semibold))
                            .tracking(1.2 * k)
                            .foregroundStyle(selected ? Palette.text : Palette.textDim)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 14 * k)
                }
                .frame(width: 142 * k, height: rowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .padding(5 * k)
        .background(
            RoundedRectangle(cornerRadius: 24 * k, style: .continuous)
                .fill(Palette.panelInset)
                .overlay(
                    RoundedRectangle(cornerRadius: 24 * k, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
        .scaleEffect(isScrubbingMeter ? 1.03 : 1.0)
        .animation(.snappy(duration: 0.22, extraBounce: 0.0), value: meterIndex)
        .animation(.snappy(duration: 0.18, extraBounce: 0.0), value: isScrubbingMeter)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isScrubbingMeter {
                        isScrubbingMeter = true
                    }
                    let y = value.location.y - (5 * k)
                    let rawIdx = Int((y / max(rowHeight, 1)).rounded(.down))
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
        .frame(height: totalHeight + 10 * k)
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

    private var shutterOrMorphedActions: some View {
        GlassEffectContainer(spacing: 14 * k) {
            morphedButtonsContent()
        }
    }

    @ViewBuilder
    private func morphedButtonsContent() -> some View {
        if frozen {
            HStack(spacing: 14 * k) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onDiscardHold()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Palette.bad.opacity(0.20))
                            .overlay(
                                Circle()
                                    .strokeBorder(Palette.bad.opacity(0.65), lineWidth: 1.5)
                            )

                        Image(systemName: "xmark")
                            .font(.system(size: 34 * k, weight: .bold))
                            .foregroundStyle(Palette.bad)
                    }
                    .frame(width: 112 * k, height: 112 * k)
                    .contentShape(Circle())
                    .glassEffect(.regular.tint(Palette.bad.opacity(0.24)).interactive(), in: Circle())
                    .glassEffectID("holdDiscard", in: morphNamespace)
                }
                .buttonStyle(PressStyle(scale: 0.94))
                .accessibilityLabel("Discard reading")

                Button {
                    guard !isSaved else { return }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onConfirmLog()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Palette.panelInset)
                            .overlay(Circle().strokeBorder(Palette.good.opacity(0.55), lineWidth: 1.5))

                        Circle()
                            .fill(Palette.good)
                            .frame(width: 118 * k, height: 118 * k)

                        Image(systemName: "checkmark")
                            .font(.system(size: 44 * k, weight: .black))
                            .foregroundStyle(Palette.accentInk)
                    }
                    .frame(width: 152 * k, height: 152 * k)
                    .contentShape(Circle())
                    .glassEffect(.regular.tint(Palette.good.opacity(0.32)).interactive(), in: Circle())
                    .glassEffectID("holdPrimary", in: morphNamespace)
                }
                .buttonStyle(PressStyle(scale: 0.95))
                .accessibilityLabel("Log frame \(frameNumber)")
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Button(action: onHold) {
                ZStack {
                    // Machined outer shutter collar
                    Circle()
                        .fill(Palette.panelInset)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.28), Color.white.opacity(0.06)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2 * k
                                )
                        )

                    // Inner chrome ring
                    Circle()
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                        .frame(width: 136 * k, height: 136 * k)

                    // Tactile shutter release plunger
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white, Color(red: 0.86, green: 0.88, blue: 0.91)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 120 * k, height: 120 * k)
                }
                .frame(width: 162 * k, height: 162 * k)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: Circle())
                .glassEffectID("holdPrimary", in: morphNamespace)
            }
            .buttonStyle(PressStyle(scale: 0.96))
            .accessibilityLabel("Hold reading")
        }
    }
}

// MARK: - Viewfinder overlays

struct EVChip: View {
    @ObservedObject var damp: Damper
    let frozen: Bool
    let spot: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(frozen ? Palette.accent : (spot ? Palette.good : Palette.textSub))
                .frame(width: 6, height: 6)

            if frozen {
                Text("HOLD")
                    .fontWeight(.bold)
                    .foregroundStyle(Palette.accent)
            }
            if spot {
                Text("SPOT")
                    .fontWeight(.bold)
                    .foregroundStyle(Palette.lensLight)
            }
            Text("EV " + String(format: "%.1f", damp.values[0]))
                .monospacedDigit()
                .fontWeight(.semibold)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Palette.text)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: frozen)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: spot)
    }
}

// MARK: - LiDAR marker

private struct FocusPing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    let tooClose: Bool

    var body: some View {
        Circle()
            .stroke(tooClose ? Palette.bad : Palette.lensLight, lineWidth: 1.2)
            .frame(width: 26, height: 26)
            .scaleEffect(expanded ? 1.7 : 0.5)
            .opacity(expanded ? 0 : 0.65)
            .onAppear {
                if reduceMotion {
                    expanded = true
                } else {
                    withAnimation(.easeOut(duration: 0.48)) { expanded = true }
                }
            }
            .accessibilityHidden(true)
    }
}

struct FocusMarker: View {
    let tooClose: Bool
    var pulseID: Int = 0

    var body: some View {
        ZStack {
            if pulseID > 0 {
                FocusPing(tooClose: tooClose).id(pulseID)
            }
            Circle()
                .stroke(tooClose ? Palette.bad : Palette.lensLight.opacity(0.95),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(width: 26, height: 26)
                .scaleEffect(tooClose ? 0.86 : 1)
            Circle()
                .fill(tooClose ? Palette.bad : Palette.lensLight)
                .frame(width: 3, height: 3)
        }
        .frame(width: 30, height: 30)
        .shadow(color: Color.black.opacity(0.75), radius: 2, x: 0, y: 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.64), value: tooClose)
        .allowsHitTesting(false)
    }
}
