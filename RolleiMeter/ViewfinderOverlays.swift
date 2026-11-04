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

// MARK: - Hold button (Smooth Sliding Metering Selector + Morphs into Confirm Log + Cancel on Hold)

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
            .padding(.trailing, 7 * k)
            .padding(.leading, frozen ? 12 * k : 0)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: frozen)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isSaved)
    }

    // Smooth thumb-scrubbable & tappable iOS 26/27 sliding selector
    private var smoothMeterSelector: some View {
        let rowHeight: CGFloat = 50 * k
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
                                    .strokeBorder(Palette.accent.opacity(0.55), lineWidth: 1)
                            )
                            .matchedGeometryEffect(id: "meterModePill", in: meterSlideNamespace)
                    }

                    HStack(spacing: 8 * k) {
                        Circle()
                            .fill(selected ? Palette.accent : Color.white.opacity(0.22))
                            .frame(width: 7 * k, height: 7 * k)

                        Text(modes[i].title)
                            .font(AppTypography.next(size: 27 * k, weight: selected ? .semibold : .medium))
                            .foregroundStyle(selected ? Palette.accent : Palette.dim)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 14 * k)
                }
                .frame(width: 146 * k, height: rowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .padding(4 * k)
        .background(
            RoundedRectangle(cornerRadius: 24 * k, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 24 * k, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
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
                    let y = value.location.y - (4 * k)
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
        .frame(height: totalHeight + 8 * k)
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
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 14 * k) {
                morphedButtonsContent(useLiquidGlass: true)
            }
        } else {
            morphedButtonsContent(useLiquidGlass: false)
        }
    }

    @ViewBuilder
    private func morphedButtonsContent(useLiquidGlass: Bool) -> some View {
        if frozen {
            HStack(spacing: 14 * k) {
                // Cancel / Discard Hold Button (Red X)
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onDiscardHold()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Palette.bad.opacity(useLiquidGlass ? 0.24 : 0.20))
                            .overlay(
                                Circle()
                                    .strokeBorder(Palette.bad.opacity(0.65), lineWidth: 1.5)
                            )

                        Image(systemName: "xmark")
                            .font(.system(size: 38 * k, weight: .bold))
                            .foregroundStyle(Palette.bad)
                    }
                    .frame(width: 118 * k, height: 118 * k)
                    .contentShape(Circle())
                    .modifier(LiquidHoldGlassModifier(
                        enabled: useLiquidGlass,
                        tint: Palette.bad.opacity(0.28),
                        id: "holdDiscard",
                        namespace: morphNamespace
                    ))
                }
                .buttonStyle(PressStyle(scale: 0.94))
                .accessibilityLabel("Discard reading")

                // Confirm & log frame. The frame number already lives in the
                // top-left panel and the shutter press is obviously an addition,
                // so the button says one thing: log it.
                Button {
                    guard !isSaved else { return }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onConfirmLog()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hex: 0x070707))
                            .overlay(Circle().strokeBorder(Palette.good.opacity(0.45), lineWidth: 1.5))

                        Circle()
                            .fill(Palette.good)
                            .frame(width: 126 * k, height: 126 * k)

                        Image(systemName: "checkmark")
                            .font(.system(size: 52 * k, weight: .black))
                            .foregroundStyle(Color.black)
                    }
                    .frame(width: 162 * k, height: 162 * k)
                    .contentShape(Circle())
                    .modifier(LiquidHoldGlassModifier(
                        enabled: useLiquidGlass,
                        tint: Palette.good.opacity(0.35),
                        id: "holdPrimary",
                        namespace: morphNamespace
                    ))
                }
                .buttonStyle(PressStyle(scale: 0.95))
                .accessibilityLabel("Log frame \(frameNumber)")
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Button(action: onHold) {
                ZStack {
                    Circle()
                        .fill(Color(hex: 0x070707))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                    Circle()
                        .fill(Color.white)
                        .frame(width: 126 * k, height: 126 * k)
                }
                .frame(width: 175 * k, height: 175 * k)
                .contentShape(Circle())
                .modifier(LiquidHoldGlassModifier(
                    enabled: useLiquidGlass,
                    tint: nil,
                    id: "holdPrimary",
                    namespace: morphNamespace
                ))
            }
            .buttonStyle(PressStyle(scale: 0.97))
            .accessibilityLabel("Hold reading")
        }
    }
}

private struct LiquidHoldGlassModifier: ViewModifier {
    let enabled: Bool
    let tint: Color?
    let id: String
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), enabled {
            if let tint {
                content
                    .glassEffect(.regular.tint(tint).interactive(), in: Circle())
                    .glassEffectID(id, in: namespace)
            } else {
                content
                    .glassEffect(.regular.interactive(), in: Circle())
                    .glassEffectID(id, in: namespace)
            }
        } else {
            content
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
