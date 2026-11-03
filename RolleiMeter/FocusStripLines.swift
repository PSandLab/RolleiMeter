import SwiftUI

// MARK: - Focus ruler

/// The focus distance ruler. Drawn with the system accent for the in-focus
/// range, green when the LiDAR measurement is valid and red when the subject
/// is closer than the lens can focus.
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            let motion = !reduceMotion

            Canvas { ctx, size in
                for i in 0...totalTicks {
                    let fraction = CGFloat(i) / CGFloat(totalTicks)
                    let x = lineMargin + fraction * linesWidth
                    let d = abs(x - touchX)

                    // The ticks swell gently under the finger while you rack focus.
                    var boost: CGFloat = 0
                    if motion, scrollProgress > 0, d < zoomRadius {
                        let t = 1.0 - (d / zoomRadius)
                        let curve = t * t * (3 - 2 * t)
                        boost = 11 * k * CGFloat(scrollProgress) * curve
                    }

                    if motion, rippleProgress < 1.0 {
                        let dRipple = abs(x - rippleX)
                        let waveRadius = CGFloat(rippleProgress) * 95 * k
                        let waveWidth: CGFloat = 30 * k
                        let distToWave = abs(dRipple - waveRadius)
                        if distToWave < waveWidth {
                            let waveT = 1.0 - (distToWave / waveWidth)
                            let curve = waveT * waveT * (3 - 2 * waveT)
                            let decay = 1.0 - CGFloat(rippleProgress)
                            boost = max(boost, 7 * k * decay * curve)
                        }
                    }

                    let lineH = baseRibH + boost
                    let topY = (h - 22 * k - lineH) / 2
                    let botY = topY + lineH

                    var path = Path()
                    path.move(to: CGPoint(x: x, y: topY))
                    path.addLine(to: CGPoint(x: x, y: botY))

                    var color: Color = Palette.lensLight
                    var alpha: Double = 0.85
                    var lw = max(1.2, 1.8 * k) + (boost > 0 ? 0.6 * k : 0)

                    if manual {
                        if scrollProgress < 0.95 {
                            let inDoF = fraction >= (dofNear - 0.015) && fraction <= (dofFar + 0.015)
                            if inDoF {
                                let resting = 1.0 - scrollProgress
                                let distToFocus = abs(fraction - focusPosition)
                                let centerBonus = max(0.0, 1.0 - distToFocus / max(0.05, (dofFar - dofNear) * 0.5))
                                color = Palette.accent
                                alpha = min(1.0, 0.65 + resting * 0.35)
                                if centerBonus > 0.6 {
                                    lw += 0.4 * k
                                }
                            }
                        }
                    } else if isTooClose {
                        if fraction <= 0.12 {
                            color = Palette.bad
                            alpha = 1.0
                        }
                    } else if hasMeasurement {
                        let inDoF = fraction >= (dofNear - 0.015) && fraction <= (dofFar + 0.015)
                        if inDoF {
                            let distToFocus = abs(fraction - focusPosition)
                            let centerBonus = max(0.0, 1.0 - distToFocus / max(0.06, (dofFar - dofNear) * 0.5))
                            color = Palette.good
                            alpha = min(1.0, 0.88 + 0.12 * centerBonus)
                            if centerBonus > 0.5 {
                                lw += 0.4 * k
                            }
                        }
                    }

                    ctx.stroke(path, with: .color(color.opacity(alpha)), lineWidth: lw)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
