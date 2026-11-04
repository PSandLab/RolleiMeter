import SwiftUI
import UIKit

// MARK: - Interactive LiDAR Focus Scrubber Card

struct FocusPanel: View {
    /// 0.0 (closest focus / 0.9m on Left) to 1.0 (infinity on Right)
    let position: Double
    let manual: Bool
    let touching: Bool
    let available: Bool
    let lidarDistance: Double?
    let hasLiDAR: Bool
    let tooClose: Bool
    let aperture: (label: String, n: Double)
    let feet: Bool
    var isHeld: Bool = false
    let onBegin: () -> Double
    let onSlide: (Double) -> Void
    let onEnd: () -> Void
    let onAuto: () -> Void
    let onUnits: () -> Void

    @State private var isDragging: Bool = false
    @State private var lastHapticTick: Int = -1
    @State private var rippleProgress: Double = 1.0
    @State private var rippleCenter: Double = 0.5

    private let totalTicks = 32
    private let tickHaptic = UISelectionFeedbackGenerator()
    private let stopHaptic = UIImpactFeedbackGenerator(style: .rigid)

    private var isScrolling: Bool {
        isDragging || touching
    }

    private var subject: Double? {
        if manual { return Focus.distance(at: position) }
        return lidarDistance
    }

    private var activePosition: Double {
        if manual { return position }
        if let d = lidarDistance { return Focus.position(d) }
        return 1.0
    }

    private var currentDoFRange: (near: Double, far: Double) {
        let s: Double? = manual ? Focus.distance(at: position) : lidarDistance
        if let dist = s, dist >= Focus.nearest - 0.001 {
            let r = DepthOfField.range(subject: dist, n: aperture.n)
            return (Focus.position(r.near), Focus.position(r.far))
        } else if !manual, let dist = s, dist < Focus.nearest {
            return (0.0, 0.08)
        } else if !manual && lidarDistance == nil {
            let r = DepthOfField.range(subject: .infinity, n: aperture.n)
            return (Focus.position(r.near), 1.0)
        }
        return (0.0, 0.0)
    }

    private var dofBoundaryMarkers: (near: (pos: Double, label: String), far: (pos: Double, label: String))? {
        guard let s = subject, s >= Focus.nearest - 0.001 else { return nil }
        let r = DepthOfField.range(subject: s, n: aperture.n)
        let marks = feet ? Focus.feetMarks : Focus.meterMarks

        let nearMark = marks.min(by: { abs($0.m - r.near) < abs($1.m - r.near) }) ?? marks[0]
        let farMark = marks.min(by: { abs($0.m - r.far) < abs($1.m - r.far) }) ?? marks[marks.count - 1]

        var nearLabel = nearMark.label
        var farLabel = farMark.label

        if nearLabel == farLabel {
            let lo = marks.last { $0.m <= s } ?? marks[0]
            let hi = marks.first { $0.m > s } ?? marks[marks.count - 1]
            nearLabel = lo.label
            farLabel = hi.label
        }

        return (
            near: (pos: Focus.position(r.near), label: nearLabel),
            far: (pos: Focus.position(r.far), label: farLabel)
        )
    }

    var body: some View {
        let greenColor = Color(red: 0.19, green: 0.82, blue: 0.35)
        let yellowColor = Color(red: 1.0, green: 0.84, blue: 0.04)
        let redColor = Color(red: 1.0, green: 0.27, blue: 0.23)
        let isAutoFocus = !manual

        VStack(spacing: 6) {
            // Header Row: AF Toggle + Focus Label + Live Distance Readout
            HStack {
                Button {
                    guard available else { return }
                    stopHaptic.impactOccurred(intensity: 0.6)
                    withAnimation(.spring(response: 0.25)) {
                        if manual {
                            onAuto()
                        } else {
                            _ = onBegin()
                            onEnd()
                        }
                    }
                } label: {
                    Text(isAutoFocus ? "AF" : "MF")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(isAutoFocus ? greenColor : yellowColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            (isAutoFocus ? greenColor : yellowColor).opacity(0.16),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(manual ? "Switch to autofocus" : "Autofocus active")

                Spacer()

                Text("FOCUS")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)

                Spacer()

                let displayDistance = subject != nil ? Fmt.distance(subject, feet: feet) : (hasLiDAR ? "∞" : "—")
                Button(action: onUnits) {
                    Text(displayDistance)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(isAutoFocus ? (tooClose ? redColor : greenColor) : yellowColor)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Focus distance, \(displayDistance)")
            }

            // Interactive Touch-Scrubbable LiDAR Focus Scale
            GeometryReader { geo in
                let w = geo.size.width
                let lineMargin: CGFloat = 2
                let usableWidth = max(w - lineMargin * 2, 1)
                let normalizedCenter = min(max(activePosition, 0.08), 0.92)

                VStack(spacing: 4) {
                    FocusStripLines(
                        focusPosition: activePosition,
                        scrollProgress: isScrolling ? 1.0 : 0.0,
                        rippleProgress: rippleProgress,
                        rippleCenter: rippleCenter,
                        manual: manual,
                        dofNear: currentDoFRange.near,
                        dofFar: currentDoFRange.far,
                        hasMeasurement: subject != nil || !manual,
                        isTooClose: tooClose,
                        totalTicks: totalTicks
                    )
                    .frame(height: 24)
                    .animation(.easeInOut(duration: 0.22), value: activePosition)
                    .animation(.easeInOut(duration: 0.22), value: currentDoFRange.near)

                    // Dynamic Near / Far Depth-of-Field Labels Positioned Under the Active Zone
                    ZStack(alignment: .leading) {
                        Color.clear.frame(height: 12)

                        if let markers = dofBoundaryMarkers {
                            HStack(spacing: 10) {
                                Text(markers.near.label)
                                Text(markers.far.label)
                            }
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(yellowColor)
                            .offset(x: max(0, min(w - 58, w * normalizedCenter - 26)))
                            .animation(.easeInOut(duration: 0.22), value: normalizedCenter)
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard available else { return }
                            if !isDragging {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isDragging = true
                                }
                                _ = onBegin()
                            }

                            let rawPos = Double((value.location.x - lineMargin) / usableWidth)
                            let newPos = min(max(rawPos, 0.0), 1.0)

                            let tickIndex = Int((newPos * Double(totalTicks)).rounded())
                            if tickIndex != lastHapticTick {
                                lastHapticTick = tickIndex
                                tickHaptic.selectionChanged()
                            }

                            if (newPos == 0.0 && position == 0.0) || (newPos == 1.0 && position == 1.0) {
                                stopHaptic.impactOccurred(intensity: 0.4)
                            }

                            onSlide(newPos)
                        }
                        .onEnded { _ in
                            rippleCenter = position
                            rippleProgress = 0.0
                            withAnimation(.easeOut(duration: 0.45)) {
                                rippleProgress = 1.0
                            }
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isDragging = false
                            }
                            onEnd()
                        }
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        guard available else { return }
                        stopHaptic.impactOccurred(intensity: 0.8)
                        withAnimation(.easeInOut(duration: 0.25)) {
                            onAuto()
                        }
                    }
                )
            }
            .frame(height: 40)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isScrolling ? yellowColor.opacity(0.6) : Color.white.opacity(0.12),
                    lineWidth: isScrolling ? 1.0 : 0.5
                )
        )
        .onAppear {
            tickHaptic.prepare()
        }
    }
}
