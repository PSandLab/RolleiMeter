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

// MARK: - Hold button (Asymmetric Stadium Card matching Concept Render)

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

    @State private var isScrubbingMeter: Bool = false

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

            if !frozen {
                HStack(spacing: 0) {
                    smoothMeterSelector
                        .padding(.leading, 18 * k)
                    Spacer(minLength: 0)
                }
                .transition(.opacity)
            }

            HStack {
                Spacer(minLength: 0)
                shutterOrMorphedActions
            }
            .padding(.trailing, 18 * k)
            .padding(.leading, frozen ? 18 * k : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(stadiumShape)
        .animation(.spring(response: 0.32, dampingFraction: 0.80), value: frozen)
        .animation(.spring(response: 0.28, dampingFraction: 0.80), value: isSaved)
    }

    private var smoothMeterSelector: some View {
        let rowHeight: CGFloat = 46 * k
        let totalHeight: CGFloat = rowHeight * CGFloat(max(modes.count, 1))

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(modes.indices, id: \.self) { i in
                let selected = (i == meterIndex)
                HStack(spacing: 8 * k) {
                    Circle()
                        .fill(selected ? Palette.accent : Palette.faint)
                        .frame(width: 6 * k, height: 6 * k)

                    Text(modes[i].title.lowercased())
                        .font(AppTypography.next(size: 24 * k, weight: selected ? .medium : .regular))
                        .foregroundStyle(selected ? Palette.text : Palette.textDim)
                        .lineLimit(1)
                }
                .frame(width: 130 * k, height: rowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
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
            HStack(spacing: 20 * k) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onDiscardHold()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Palette.bad.opacity(0.18))
                        Image(systemName: "xmark")
                            .font(.system(size: 30 * k, weight: .semibold))
                            .foregroundStyle(Palette.bad)
                    }
                    .frame(width: 110 * k, height: 110 * k)
                    .contentShape(Circle())
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
                            .strokeBorder(Palette.good.opacity(0.35), lineWidth: 1.5)
                            .frame(width: 156 * k, height: 156 * k)

                        Circle()
                            .fill(Palette.good)
                            .frame(width: 126 * k, height: 126 * k)

                        Image(systemName: "checkmark")
                            .font(.system(size: 38 * k, weight: .bold))
                            .foregroundStyle(Palette.accentInk)
                    }
                    .frame(width: 156 * k, height: 156 * k)
                    .contentShape(Circle())
                }
                .buttonStyle(PressStyle(scale: 0.95))
                .accessibilityLabel("Log frame \(frameNumber)")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            Button(action: onHold) {
                ZStack {
                    // Outer concentric ring from concept wireframe
                    Circle()
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1.2)
                        .frame(width: 162 * k, height: 162 * k)

                    // Inner dashed technical ring from concept wireframe
                    Circle()
                        .strokeBorder(
                            Color.white.opacity(0.16),
                            style: StrokeStyle(lineWidth: 1.0, dash: [5 * k, 5 * k])
                        )
                        .frame(width: 142 * k, height: 142 * k)

                    // Pure white shutter circle
                    Circle()
                        .fill(Color.white)
                        .frame(width: 124 * k, height: 124 * k)
                }
                .frame(width: 162 * k, height: 162 * k)
                .contentShape(Circle())
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
        .background(Color.black.opacity(0.55), in: .capsule)
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
