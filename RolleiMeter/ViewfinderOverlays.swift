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

/// Metering mode picker plus the shutter-style hold button. When a reading is
/// held it morphs into Discard / Log frame.
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

    private var safeIndex: Int { min(max(meterIndex, 0), max(modes.count - 1, 0)) }
    private var currentMode: MeterMode { modes.isEmpty ? .matrix : modes[safeIndex] }

    var body: some View {
        HStack(spacing: 0) {
            if !frozen {
                meterMenu
                    .padding(.leading, 18 * k)
                    .transition(.opacity)
            }

            Spacer(minLength: 8 * k)

            if frozen {
                heldActions
            } else {
                holdButton
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.8), value: frozen)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isSaved)
    }

    // MARK: Metering

    private var meterMenu: some View {
        Menu {
            Picker("Metering", selection: Binding(
                get: { safeIndex },
                set: { newValue in
                    guard newValue != safeIndex else { return }
                    Haptics.tap()
                    onPickMeter(newValue)
                }
            )) {
                ForEach(modes.indices, id: \.self) { i in
                    Text(modes[i].title).tag(i)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 3 * k) {
                Text("Metering")
                    .font(.system(size: 13 * k, weight: .medium))
                    .foregroundStyle(Palette.textSub)

                HStack(spacing: 5 * k) {
                    Text(currentMode.title)
                        .font(.system(size: 19 * k, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11 * k, weight: .semibold))
                        .foregroundStyle(Palette.textDim)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Metering mode")
        .accessibilityValue(currentMode.title)
    }

    // MARK: Shutter

    private var holdButton: some View {
        Button(action: onHold) {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 116 * k, height: 116 * k)

                Circle()
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 3 * k)
                    .frame(width: 128 * k, height: 128 * k)
            }
            .frame(width: 150 * k, height: 150 * k)
            .contentShape(Circle())
            .floatingSurface(Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 14 * k)
        .accessibilityLabel("Hold reading")
        .accessibilityHint("Freezes the meter so you can log the frame")
    }

    private var heldActions: some View {
        HStack(spacing: 16 * k) {
            Button {
                Haptics.press()
                onDiscardHold()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 26 * k, weight: .semibold))
                    .foregroundStyle(Palette.bad)
                    .frame(width: 62 * k, height: 62 * k)
                    .contentShape(Circle())
                    .floatingSurface(Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Discard reading")

            Button {
                guard !isSaved else { return }
                Haptics.success()
                onConfirmLog()
            } label: {
                VStack(spacing: 2 * k) {
                    Image(systemName: isSaved ? "checkmark" : "checkmark")
                        .font(.system(size: 26 * k, weight: .semibold))
                    Text(isSaved ? "Saved" : String(format: "#%02d", frameNumber))
                        .font(.system(size: 13 * k, weight: .semibold).monospacedDigit())
                }
                .foregroundStyle(Palette.onAccent)
                .frame(width: 118 * k, height: 118 * k)
                .contentShape(Circle())
                .background(Circle().fill(Palette.accent))
            }
            .buttonStyle(PressStyle(scale: 0.96))
            .accessibilityLabel(isSaved ? "Frame saved" : "Log frame \(frameNumber)")
        }
        .padding(.trailing, 16 * k)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}

// MARK: - Viewfinder overlays

/// Quiet status line drawn on the viewfinder: EV, and whether a reading is held.
struct EVChip: View {
    @ObservedObject var damp: Damper
    let frozen: Bool
    let spot: Bool

    var body: some View {
        HStack(spacing: 6) {
            if frozen {
                Text("Hold")
                    .foregroundStyle(Palette.accent)
            }
            if spot {
                Text("Spot")
            }
            Text("EV " + String(format: "%.1f", damp.values[0]))
                .monospacedDigit()
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: frozen)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: spot)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - LiDAR marker

private struct FocusPing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    let tooClose: Bool

    var body: some View {
        Circle()
            .stroke(tooClose ? Palette.bad : Palette.lensLight, lineWidth: 1)
            .frame(width: 26, height: 26)
            .scaleEffect(expanded ? 1.7 : 0.5)
            .opacity(expanded ? 0 : 0.55)
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
                .stroke(tooClose ? Palette.bad : Palette.lensLight.opacity(0.92),
                        style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                .frame(width: 26, height: 26)
                .scaleEffect(tooClose ? 0.86 : 1)
            Circle()
                .fill(tooClose ? Palette.bad : Palette.lensLight)
                .frame(width: 2.5, height: 2.5)
        }
        .frame(width: 30, height: 30)
        .animation(.spring(response: 0.28, dampingFraction: 0.64), value: tooClose)
        .allowsHitTesting(false)
    }
}
