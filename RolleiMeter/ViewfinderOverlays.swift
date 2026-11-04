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

// MARK: - Unboxed Confirm & Reject Glass Controls

struct HoldControl: View {
    let frozen: Bool
    var frameNumber: Int = 1
    var isSaved: Bool = false
    let onConfirmLog: () -> Void
    let onDiscardHold: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Reject / Reset Hold Button (Glass rounded-rect with clean red icon)
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onDiscardHold()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(red: 1.0, green: 0.36, blue: 0.36))
                    .frame(width: 58, height: 68)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                    )
            }
            .buttonStyle(PressStyle(scale: 0.94))
            .accessibilityLabel(frozen ? "Discard reading" : "Hold reading")

            // Confirm / Log Frame Button (Prominent Green Button)
            Button {
                guard !isSaved else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onConfirmLog()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 88, height: 68)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.24, green: 0.90, blue: 0.44),
                                Color(red: 0.16, green: 0.78, blue: 0.35)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
                    .shadow(color: Color.green.opacity(0.28), radius: 10, y: 4)
            }
            .buttonStyle(PressStyle(scale: 0.95))
            .accessibilityLabel("Log frame \(frameNumber)")
        }
    }
}

// MARK: - Viewfinder HUD Chips

struct EVChip: View {
    @ObservedObject var damp: Damper
    let frozen: Bool
    let spot: Bool
    var onTap: () -> Void = {}

    var body: some View {
        let yellowColor = Color(red: 1.0, green: 0.84, blue: 0.04)
        let greenColor = Color(red: 0.19, green: 0.82, blue: 0.35)

        Button(action: onTap) {
            HStack(spacing: 6) {
                Circle()
                    .fill(frozen ? yellowColor : greenColor)
                    .frame(width: 6, height: 6)

                Text(frozen ? "HOLD" : "LIVE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(frozen ? yellowColor : greenColor)

                if spot {
                    Text("SPOT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(yellowColor)
                }

                Text("EV \(String(format: "%.1f", damp.values[0]))")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25), value: frozen)
        .animation(.spring(response: 0.25), value: spot)
    }
}

struct LiDARPeakingBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(red: 1.0, green: 0.27, blue: 0.23))
                .frame(width: 6, height: 6)
            Text("LiDAR DEPTH")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
        )
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
                .stroke(tooClose ? Palette.bad : Color.white.opacity(0.85),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(width: 36, height: 36)
                .scaleEffect(tooClose ? 0.86 : 1)
            Circle()
                .fill(tooClose ? Palette.bad : Color.white)
                .frame(width: 4, height: 4)
        }
        .shadow(color: .black.opacity(0.35), radius: 4)
        .frame(width: 38, height: 38)
        .animation(.spring(response: 0.28, dampingFraction: 0.64), value: tooClose)
        .allowsHitTesting(false)
    }
}
