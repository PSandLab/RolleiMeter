import SwiftUI

// MARK: - Focus (Static Bed Dial with Left-to-Right Knob)

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
            let lineMargin: CGFloat = 2 * k
            let linesWidth = max(w - lineMargin * 2, 1)
            let touchX = lineMargin + CGFloat(min(max(focusPosition, 0.0), 1.0)) * linesWidth
            let rippleX = lineMargin + CGFloat(min(max(rippleCenter, 0.0), 1.0)) * linesWidth
            let baseRibH = h - 22 * k
            let zoomRadius = 42 * k

            Canvas { ctx, size in
                for i in 0...totalTicks {
                    let fraction = CGFloat(i) / CGFloat(totalTicks)
                    let x = lineMargin + fraction * linesWidth
                    let d = abs(x - touchX)

                    // 1. Gentle macOS dock zoom magnification following finger
                    var boost: CGFloat = 0
                    if scrollProgress > 0 && d < zoomRadius {
                        let t = 1.0 - (d / zoomRadius)
                        let wCurve = t * t * (3 - 2 * t)
                        boost = 11 * k * CGFloat(scrollProgress) * wCurve
                    }

                    // 2. Gentle ripple wave expanding outward on release
                    if rippleProgress < 1.0 {
                        let dRipple = abs(x - rippleX)
                        let waveRadius = CGFloat(rippleProgress) * 95 * k
                        let waveWidth: CGFloat = 30 * k
                        let distToWave = abs(dRipple - waveRadius)
                        if distToWave < waveWidth {
                            let waveT = 1.0 - (distToWave / waveWidth)
                            let waveCurve = waveT * waveT * (3 - 2 * waveT)
                            let decay = 1.0 - CGFloat(rippleProgress)
                            let rippleBoost = 7 * k * decay * waveCurve
                            boost = max(boost, rippleBoost)
                        }
                    }

                    let lineH = baseRibH + boost
                    let topY = (h - 22 * k - lineH) / 2
                    let botY = topY + lineH

                    var path = Path()
                    path.move(to: CGPoint(x: x, y: topY))
                    path.addLine(to: CGPoint(x: x, y: botY))

                    var r: Double = 1.0
                    var g: Double = 1.0
                    var b: Double = 1.0
                    var alpha: Double = 0.85
                    var lw = max(1.2, 1.8 * k) + (boost > 0 ? 0.6 * k : 0)

                    if manual {
                        // Manual Mode: Lines inside depth-of-field turn RED when resting
                        if scrollProgress < 0.95 {
                            let inDoF = fraction >= (dofNear - 0.015) && fraction <= (dofFar + 0.015)
                            if inDoF {
                                let restingFactor = 1.0 - scrollProgress
                                let distToFocus = abs(fraction - focusPosition)
                                let centerBonus = max(0.0, 1.0 - distToFocus / max(0.05, (dofFar - dofNear) * 0.5))
                                r = 1.0
                                g = 1.0 - restingFactor * (1.0 - 0.23)
                                b = 1.0 - restingFactor * (1.0 - 0.19)
                                alpha = min(1.0, 0.85 + restingFactor * 0.15)
                                if centerBonus > 0.6 {
                                    lw += 0.4 * k
                                }
                            }
                        }
                    } else {
                        // Auto Mode: Green lines reflecting measurement and DoF in real time
                        if isTooClose {
                            if fraction <= 0.12 {
                                r = 1.0
                                g = 0.27
                                b = 0.23
                                alpha = 1.0
                            }
                        } else if hasMeasurement {
                            let inDoF = fraction >= (dofNear - 0.015) && fraction <= (dofFar + 0.015)
                            if inDoF {
                                let distToFocus = abs(fraction - focusPosition)
                                let centerBonus = max(0.0, 1.0 - distToFocus / max(0.06, (dofFar - dofNear) * 0.5))
                                r = 0.19
                                g = 0.82 + 0.14 * centerBonus
                                b = 0.35
                                alpha = min(1.0, 0.88 + 0.12 * centerBonus)
                                if centerBonus > 0.5 {
                                    lw += 0.4 * k
                                }
                            }
                        }
                    }

                    ctx.stroke(
                        path,
                        with: .color(Color(red: r, green: g, blue: b, opacity: alpha)),
                        lineWidth: lw
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}
