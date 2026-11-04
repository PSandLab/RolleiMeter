import SwiftUI
import UIKit

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
    let k: CGFloat
    let onBegin: () -> Double
    let onSlide: (Double) -> Void
    let onEnd: () -> Void
    let onAuto: () -> Void
    let onUnits: () -> Void

    @State private var isDragging: Bool = false
    @State private var lastHapticTick: Int = -1
    @State private var rippleProgress: Double = 1.0
    @State private var rippleCenter: Double = 0.5

    private let totalTicks = 36
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
        ZStack(alignment: .top) {
            PanelTitle(text: "FOCUS", k: k)

            // Static Bed Dial Track (No box, no ball, lines span end to end)
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let lineMargin: CGFloat = 2 * k
                let usableWidth = max(w - lineMargin * 2, 1)
                let ribH = h - 22 * k
                let touchX = lineMargin + CGFloat(min(max(activePosition, 0.0), 1.0)) * usableWidth

                ZStack(alignment: .leading) {
                    // Atmospheric red gradient wash following finger directly
                    let glowWidth = max(w * 0.82, 110 * k)
                    Color.clear
                        .background(
                            LinearGradient(
                                stops: [
                                    .init(color: Palette.bad.opacity(0.0), location: 0.0),
                                    .init(color: Palette.bad.opacity(0.18), location: 0.20),
                                    .init(color: Palette.bad.opacity(0.60), location: 0.50),
                                    .init(color: Palette.bad.opacity(0.18), location: 0.80),
                                    .init(color: Palette.bad.opacity(0.0), location: 1.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: .rect(cornerRadius: 8 * k, style: .continuous)
                        )
                        .frame(width: glowWidth, height: ribH + 6 * k)
                        .position(x: touchX, y: ribH / 2)
                        .opacity(isScrolling && manual ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.25), value: isScrolling)
                        .allowsHitTesting(false)

                    // Lines with gentle dock zoom, release ripple & DoF coloring
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
                        totalTicks: totalTicks,
                        k: k
                    )
                    .animation(.easeInOut(duration: 0.22), value: activePosition)
                    .animation(.easeInOut(duration: 0.22), value: currentDoFRange.near)

                    // DoF boundary markers displayed under the lines on HOLD (shutter pressed)
                    if (isHeld || (manual && !isScrolling)), let markers = dofBoundaryMarkers {
                        let leftX = lineMargin + CGFloat(markers.near.pos) * usableWidth
                        let rightX = lineMargin + CGFloat(markers.far.pos) * usableWidth
                        let minGap: CGFloat = 34 * k
                        let actualGap = max(rightX - leftX, minGap)
                        let midX = (leftX + rightX) / 2
                        let adjLeftX = min(leftX, midX - actualGap / 2)
                        let adjRightX = max(rightX, midX + actualGap / 2)
                        let markerY = ribH + 11 * k

                        ZStack {
                            VStack(spacing: 2 * k) {
                                Rectangle()
                                    .fill(Palette.accent)
                                    .frame(width: 1.5 * k, height: 4 * k)
                                Text(markers.near.label)
                                    .font(AppTypography.numeral(size: 13 * k, weight: .bold))
                                    .foregroundStyle(Palette.accent)
                                    .lineLimit(1)
                            }
                            .position(x: adjLeftX, y: markerY)

                            VStack(spacing: 2 * k) {
                                Rectangle()
                                    .fill(Palette.accent)
                                    .frame(width: 1.5 * k, height: 4 * k)
                                Text(markers.far.label)
                                    .font(AppTypography.numeral(size: 13 * k, weight: .bold))
                                    .foregroundStyle(Palette.accent)
                                    .lineLimit(1)
                            }
                            .position(x: adjRightX, y: markerY)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        .animation(.easeInOut(duration: 0.22), value: markers.near.pos)
                        .animation(.easeInOut(duration: 0.22), value: markers.far.pos)
                        .animation(.easeInOut(duration: 0.22), value: aperture.n)
                        .animation(.easeInOut(duration: 0.25), value: isHeld)
                        .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .animation(.easeInOut(duration: 0.25), value: isScrolling)
                .animation(.easeInOut(duration: 0.25), value: manual)
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
            .padding(.top, 56 * k)
            .padding(.bottom, 10 * k)
            .padding(.horizontal, 14 * k)
        }
        .overlay(alignment: .topLeading) {
            Button {
                if manual {
                    stopHaptic.impactOccurred(intensity: 0.6)
                    withAnimation(.easeInOut(duration: 0.25)) {
                        onAuto()
                    }
                }
            } label: {
                Text(manual ? "MF" : "AF")
                    .font(AppTypography.next(size: 19 * k, weight: .bold))
                    .foregroundStyle(manual ? Palette.bad : Palette.good)
                    .padding(.top, 17 * k)
                    .padding(.leading, 18 * k)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(manual ? "Switch to autofocus" : "Autofocus active")
        }
        .overlay(alignment: .topTrailing) {
            let displayDistance = subject != nil ? Fmt.distance(subject, feet: feet) : (hasLiDAR ? "∞" : "—")
            Button(action: onUnits) {
                Text(displayDistance)
                    .font(AppTypography.numeral(size: 19 * k, weight: .semibold))
                    .foregroundStyle(manual ? Palette.text : (tooClose ? Palette.bad : Palette.good))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 17 * k)
                    .padding(.trailing, 18 * k)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Focus distance, \(displayDistance)")
        }
        .onAppear {
            tickHaptic.prepare()
        }
    }
}
