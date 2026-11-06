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
    @State private var unitPop: Double = 0.0

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
        let modeTint = manual ? Palette.bad : (tooClose ? Palette.bad : Palette.good)

        ZStack(alignment: .top) {
            PanelTitle(text: "FOCUS", k: k)

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let lineMargin: CGFloat = 4 * k
                let usableWidth = max(w - lineMargin * 2, 1)
                let ribH = h - 22 * k
                let touchX = lineMargin + CGFloat(min(max(activePosition, 0.0), 1.0)) * usableWidth

                ZStack(alignment: .leading) {
                    // Atmospheric red spotlight wash following finger in manual mode
                    let glowWidth = max(w * 0.78, 110 * k)
                    Color.clear
                        .background(
                            RadialGradient(
                                colors: [
                                    Palette.bad.opacity(0.62),
                                    Palette.bad.opacity(0.22),
                                    Palette.bad.opacity(0.0)
                                ],
                                center: .center,
                                startRadius: 4 * k,
                                endRadius: glowWidth * 0.52
                            ),
                            in: .rect(cornerRadius: 10 * k, style: .continuous)
                        )
                        .frame(width: glowWidth, height: ribH + 8 * k)
                        .position(x: touchX, y: ribH / 2)
                        .opacity(isScrolling && manual ? 1.0 : 0.0)
                        .scaleEffect(isScrolling && manual ? 1.0 : 0.75)
                        .animation(.spring(response: 0.24, dampingFraction: 0.65), value: isScrolling)
                        .allowsHitTesting(false)

                    // Multi-harmonic animated focus lines
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
                    .animation(.spring(response: 0.28, dampingFraction: 0.64), value: activePosition)
                    .animation(.spring(response: 0.28, dampingFraction: 0.64), value: currentDoFRange.near)
                    .animation(.spring(response: 0.28, dampingFraction: 0.64), value: currentDoFRange.far)

                    // Animated DoF Caliper Bracket & Markers
                    if (isHeld || (manual && !isScrolling)), let markers = dofBoundaryMarkers {
                        let leftX = lineMargin + CGFloat(markers.near.pos) * usableWidth
                        let rightX = lineMargin + CGFloat(markers.far.pos) * usableWidth
                        let minGap: CGFloat = 38 * k
                        let actualGap = max(rightX - leftX, minGap)
                        let midX = (leftX + rightX) / 2
                        let adjLeftX = min(leftX, midX - actualGap / 2)
                        let adjRightX = max(rightX, midX + actualGap / 2)
                        let markerY = ribH + 9 * k

                        ZStack {
                            Path { p in
                                p.move(to: CGPoint(x: leftX, y: ribH - 4 * k))
                                p.addLine(to: CGPoint(x: leftX, y: ribH))
                                p.addLine(to: CGPoint(x: rightX, y: ribH))
                                p.addLine(to: CGPoint(x: rightX, y: ribH - 4 * k))
                            }
                            .stroke(Palette.accent.opacity(0.65), style: StrokeStyle(lineWidth: 1.5 * k, lineCap: .round, lineJoin: .round))

                            Text(markers.near.label)
                                .font(AppTypography.numeral(size: 18 * k, weight: .bold))
                                .foregroundStyle(Palette.accent)
                                .lineLimit(1)
                                .position(x: adjLeftX, y: markerY)

                            Text(markers.far.label)
                                .font(AppTypography.numeral(size: 18 * k, weight: .bold))
                                .foregroundStyle(Palette.accent)
                                .lineLimit(1)
                                .position(x: adjRightX, y: markerY)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        .animation(.spring(response: 0.26, dampingFraction: 0.62), value: markers.near.pos)
                        .animation(.spring(response: 0.26, dampingFraction: 0.62), value: markers.far.pos)
                        .animation(.spring(response: 0.26, dampingFraction: 0.62), value: aperture.n)
                        .animation(.spring(response: 0.28, dampingFraction: 0.68), value: isHeld)
                        .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .animation(.spring(response: 0.24, dampingFraction: 0.65), value: isScrolling)
                .animation(.spring(response: 0.28, dampingFraction: 0.65), value: manual)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard available else { return }
                            if !isDragging {
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.62)) {
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
                            triggerHarmonicRipple(at: position)
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.64)) {
                                isDragging = false
                            }
                            onEnd()
                        }
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        guard available else { return }
                        stopHaptic.impactOccurred(intensity: 0.8)
                        triggerHarmonicRipple(at: 0.5)
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) {
                            onAuto()
                        }
                    }
                )
            }
            .padding(.top, 50 * k)
            .padding(.bottom, 12 * k)
            .padding(.horizontal, 18 * k)
        }
        .overlay(alignment: .topLeading) {
            Button {
                if manual {
                    stopHaptic.impactOccurred(intensity: 0.6)
                    triggerHarmonicRipple(at: activePosition)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) {
                        onAuto()
                    }
                }
            } label: {
                Text(manual ? "MF" : "AF")
                    .font(AppTypography.next(size: 18 * k, weight: .semibold))
                    .foregroundStyle(manual ? Palette.bad : Palette.good)
                    .contentTransition(.interpolate)
                    .padding(.top, 15 * k)
                    .padding(.leading, 18 * k)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.85))
            .accessibilityLabel(manual ? "Switch to autofocus" : "Autofocus active")
        }
        .overlay(alignment: .topTrailing) {
            let displayDistance = subject != nil ? Fmt.distance(subject, feet: feet) : (hasLiDAR ? "∞" : "—")
            Button {
                unitPop = 1.0
                withAnimation(.spring(response: 0.32, dampingFraction: 0.45)) {
                    unitPop = 0.0
                }
                onUnits()
            } label: {
                Text(displayDistance)
                    .font(AppTypography.numeral(size: 18 * k, weight: .semibold))
                    .foregroundStyle(manual ? Palette.text : (tooClose ? Palette.bad : Palette.good))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                    .scaleEffect(1.0 + 0.16 * unitPop)
                    .padding(.top, 15 * k)
                    .padding(.trailing, 18 * k)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Focus distance, \(displayDistance)")
        }
        .mattePanel(k: k, glowColor: modeTint, glowIntensity: isScrolling ? 0.65 : 0.0)
        .onAppear {
            tickHaptic.prepare()
        }
    }

    private func triggerHarmonicRipple(at center: Double) {
        rippleCenter = center
        rippleProgress = 0.0
        withAnimation(.easeOut(duration: 0.62)) {
            rippleProgress = 1.0
        }
    }
}
