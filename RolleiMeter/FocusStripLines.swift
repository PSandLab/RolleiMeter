import SwiftUI

// MARK: - Focus (Dual-Harmonic String Wave + Dock Zoom + Floating Apex Dot)

struct FocusStripLines: View, Animatable {
    var focusPosition: Double
    var scrollProgress: Double
    var rippleProgress: Double
    var rippleCenter: Double
    var manual: Bool
    var dofNear: Double
    var dofFar: Double
    var hasMeasurement: Bool
    var isTooClose: Bool
    let totalTicks: Int
    let k: CGFloat

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, AnimatablePair<Double, AnimatablePair<Double, AnimatablePair<Double, Double>>>>> {
        get {
            .init(focusPosition, .init(scrollProgress, .init(rippleProgress, .init(rippleCenter, .init(dofNear, dofFar)))))
        }
        set {
            focusPosition = newValue.first
            scrollProgress = newValue.second.first
            rippleProgress = newValue.second.second.first
            rippleCenter = newValue.second.second.second.first
            dofNear = newValue.second.second.second.second.first
            dofFar = newValue.second.second.second.second.second
        }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let lineMargin: CGFloat = 4 * k
            let linesWidth = max(w - lineMargin * 2, 1)
            let touchX = lineMargin + CGFloat(min(max(focusPosition, 0.0), 1.0)) * linesWidth
            let rippleX = lineMargin + CGFloat(min(max(rippleCenter, 0.0), 1.0)) * linesWidth
            let baseRibH = h - 24 * k
            let zoomRadius = 48 * k

            Canvas { ctx, size in
                for i in 0...totalTicks {
                    let fraction = CGFloat(i) / CGFloat(totalTicks)
                    let x = lineMargin + fraction * linesWidth
                    let d = abs(x - touchX)

                    // 1. Macro: Elastic dock magnification with harmonic shoulder
                    var boost: CGFloat = 0
                    var yShift: CGFloat = 0
                    if scrollProgress > 0 && d < zoomRadius {
                        let t = 1.0 - (d / zoomRadius)
                        let wCurve = t * t * (3 - 2 * t)
                        boost = 13 * k * CGFloat(scrollProgress) * wCurve
                        yShift = -2.5 * k * CGFloat(scrollProgress) * wCurve
                    }

                    // 2. Micro + Sub: Dual-harmonic interference shockwave + plucked string oscillation
                    if rippleProgress < 1.0 {
                        let dRipple = abs(x - rippleX)
                        let waveRadius = CGFloat(rippleProgress) * 115 * k
                        let waveWidth: CGFloat = 38 * k
                        let distToWave = abs(dRipple - waveRadius)
                        let decay = pow(1.0 - CGFloat(rippleProgress), 1.3)

                        if distToWave < waveWidth {
                            let waveT = 1.0 - (distToWave / waveWidth)
                            let waveCurve = waveT * waveT * (3 - 2 * waveT)
                            let primaryWave = 9.5 * k * decay * waveCurve
                            boost = max(boost, primaryWave)
                        }

                        // Sub-animation: High-frequency sympathetic string resonance
                        let phase = Double(dRipple / max(1, 9 * k)) - rippleProgress * 16.0
                        let envelope = exp(-Double(dRipple) / Double(max(1, 70 * k))) * Double(decay)
                        let harmonicOsc = CGFloat(sin(phase) * envelope) * 4.5 * k
                        yShift += harmonicOsc
                        boost += abs(harmonicOsc) * 0.6
                    }

                    let inDoF = fraction >= (dofNear - 0.015) && fraction <= (dofFar + 0.015)
                    let distToFocus = abs(Double(fraction) - focusPosition)
                    let focusPeak = max(0.0, 1.0 - distToFocus * 14.0)

                    // Subtle standing elevation for ticks inside the active DoF slice
                    let dofLift: CGFloat = (inDoF && (manual || hasMeasurement)) ? (2.5 * k * CGFloat(focusPeak)) : 0
                    let lineH = baseRibH + boost + dofLift
                    let topY = (h - 22 * k - lineH) / 2 + yShift
                    let botY = topY + lineH

                    var path = Path()
                    path.move(to: CGPoint(x: x, y: topY))
                    path.addLine(to: CGPoint(x: x, y: botY))

                    var r: Double = 0.92
                    var g: Double = 0.92
                    var b: Double = 0.94
                    var alpha: Double = 0.55
                    var lw = max(1.1, 1.5 * k) + (boost > 2 * k ? 0.55 * k : 0)

                    if manual {
                        if scrollProgress < 0.95 {
                            if inDoF {
                                let restingFactor = 1.0 - scrollProgress
                                r = 0.98
                                g = 1.0 - restingFactor * (1.0 - 0.22)
                                b = 1.0 - restingFactor * (1.0 - 0.22)
                                alpha = min(1.0, 0.78 + restingFactor * 0.22)
                                lw += CGFloat(focusPeak) * 0.6 * k
                            }
                        } else if d < zoomRadius {
                            let prox = Double(1.0 - d / zoomRadius)
                            alpha = 0.60 + 0.40 * prox
                        }
                    } else {
                        if isTooClose {
                            if fraction <= 0.14 {
                                r = 0.96; g = 0.23; b = 0.23; alpha = 1.0
                            }
                        } else if hasMeasurement {
                            if inDoF {
                                r = 0.20
                                g = 0.83 + 0.15 * focusPeak
                                b = 0.45
                                alpha = min(1.0, 0.88 + 0.12 * focusPeak)
                                lw += CGFloat(focusPeak) * 0.6 * k
                            }
                        }
                    }

                    ctx.stroke(
                        path,
                        with: .color(Color(red: r, green: g, blue: b, opacity: alpha)),
                        lineWidth: lw
                    )
                }

                // Sub-animation 3: Floating Apex Focus Bead riding the active focus position
                if hasMeasurement || manual {
                    let beadColor: Color = manual ? Palette.bad : (isTooClose ? Palette.bad : Palette.good)
                    let beadY = 3.5 * k - CGFloat(scrollProgress) * 2.5 * k
                    let beadR = (2.6 + 0.9 * CGFloat(scrollProgress)) * k
                    let beadRect = CGRect(x: touchX - beadR, y: beadY - beadR, width: beadR * 2, height: beadR * 2)
                    ctx.fill(Path(ellipseIn: beadRect), with: .color(beadColor))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
