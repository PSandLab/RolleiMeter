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
    let k: CGFloat
    let modes: [MeterMode]
    let meterIndex: Int
    let onPickMeter: (Int) -> Void
    let action: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            VStack(alignment: .leading, spacing: 8 * k) {
                ForEach(modes.indices, id: \.self) { i in
                    Button {
                        guard i != meterIndex else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        onPickMeter(i)
                    } label: {
                        Text(modes[i].title)
                            .font(AppTypography.next(size: 31 * k, weight: i == meterIndex ? .semibold : .medium))
                            .foregroundStyle(i == meterIndex ? Palette.accent : Palette.dim)
                            .animation(.easeOut(duration: 0.18), value: meterIndex)
                            .frame(minWidth: 120 * k, minHeight: 44 * k, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(modes[i].title + " metering")
                    .accessibilityAddTraits(i == meterIndex ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 17 * k)

            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(Color(hex: 0x070707))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                    Circle()
                        .fill(frozen ? Palette.accent : Color.white)
                        .frame(width: 126 * k, height: 126 * k)
                        .scaleEffect(frozen ? 0.9 : 1.0)
                }
                .frame(width: 175 * k, height: 175 * k)
                .contentShape(Circle())
                .animation(.spring(response: 0.3, dampingFraction: 0.72), value: frozen)
            }
            .buttonStyle(PressStyle(scale: 0.97))
            .padding(.trailing, 7 * k)
            .accessibilityLabel(frozen ? "Release hold" : "Hold reading")
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
                Text("HOLD").foregroundStyle(Palette.accent)
            }
            if spot {
                Text("SPOT")
            }
            Text("EV " + String(format: "%.1f", damp.values[0]))
                .monospacedDigit()
        }
        .font(AppTypography.font(size: 11, weight: .medium))
        .foregroundStyle(Palette.text)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
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
        .shadow(color: Palette.lensDark.opacity(0.45), radius: 1.5)
        .animation(.spring(response: 0.28, dampingFraction: 0.64), value: tooClose)
        .allowsHitTesting(false)
    }
}
