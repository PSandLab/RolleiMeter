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
                    Spacer(minLength: 0)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .leading)))
            }

            HStack {
                Spacer(minLength: 0)
                shutterOrMorphedActions
            }
            .padding(.trailing, 4 * k)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: frozen)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isSaved)
    }

    private var smoothMeterSelector: some View {
        let rowHeight: CGFloat = 50 * k
        let totalHeight: CGFloat = rowHeight * CGFloat(max(modes.count, 1))

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(modes.indices, id: \.self) { i in
                let selected = (i == meterIndex)
                ZStack(alignment: .leading) {
                    if selected {
                        Capsule()
                            .fill(Color.white.opacity(isScrubbingMeter ? 0.18 : 0.12))
                            .matchedGeometryEffect(id: "meterModePill", in: meterSlideNamespace)
                    }

                    HStack(spacing: 9 * k) {
                        Circle()
                            .fill(selected ? Palette.accent : Palette.faint)
                            .frame(width: 7 * k, height: 7 * k)

                        Text(modes[i].title)
                            .font(AppTypography.next(size: 24 * k, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Palette.text : Palette.textDim)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 14 * k)
                }
                .frame(width: 144 * k, height: rowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .padding(5 * k)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22 * k, style: .continuous))
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
        GlassEffectContainer(spacing: 16 * k) {
            morphedButtonsContent()
        }
    }

    @ViewBuilder
    private func morphedButtonsContent() -> some View {
        if frozen {
            HStack(spacing: 16 * k) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onDiscardHold()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 32 * k, weight: .bold))
                        .foregroundStyle(Palette.bad)
                        .frame(width: 114 * k, height: 114 * k)
                        .contentShape(Circle())
                        .glassEffect(.regular.tint(Palette.bad.opacity(0.22)).interactive(), in: Circle())
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
                            .fill(Palette.good)
                            .frame(width: 118 * k, height: 118 * k)

                        Image(systemName: "checkmark")
                            .font(.system(size: 40 * k, weight: .bold))
                            .foregroundStyle(Palette.accentInk)
                    }
                    .frame(width: 152 * k, height: 152 * k)
                    .contentShape(Circle())
                    .glassEffect(.regular.tint(Palette.good.opacity(0.28)).interactive(), in: Circle())
                    .glassEffectID("holdPrimary", in: morphNamespace)
                }
                .buttonStyle(PressStyle(scale: 0.95))
                .accessibilityLabel("Log frame \(frameNumber)")
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Button(action: onHold) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 2 * k)
                        .frame(width: 146 * k, height: 146 * k)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 122 * k, height: 122 * k)
                }
                .frame(width: 166 * k, height: 166 * k)
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
            if frozen {
                Text("HOLD")
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.accent)
            }
            if spot {
                Text("SPOT")
                    .fontWeight(.semibold)
            }
            Text("EV " + String(format: "%.1f", damp.values[0]))
                .monospacedDigit()
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Palette.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
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
        .shadow(color: Color.black.opacity(0.65), radius: 2, x: 0, y: 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.64), value: tooClose)
        .allowsHitTesting(false)
    }
}
