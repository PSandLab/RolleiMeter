import SwiftUI

// MARK: - Focus Strip Lines (Calmed Inactive Ticks + Bright Green DoF Zone)

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
    var k: CGFloat = 1.0

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
            let lineMargin: CGFloat = 2
            let linesWidth = max(w - lineMargin * 2, 1)
            let touchX = lineMargin + CGFloat(min(max(focusPosition, 0.0), 1.0)) * linesWidth
            let rippleX = lineMargin + CGFloat(min(max(rippleCenter, 0.0), 1.0)) * linesWidth
            let baseRibH: CGFloat = max(18, h - 4)
            let zoomRadius: CGFloat = 44

            Canvas { ctx, size in
                for i in 0..<totalTicks {
                    let fraction = CGFloat(i) / CGFloat(max(totalTicks - 1, 1))
                    let x = lineMargin + fraction * linesWidth
                    let d = abs(x - touchX)

                    // 1. Gentle dock zoom magnification following finger
                    var boost: CGFloat = 0
                    if scrollProgress > 0 && d < zoomRadius {
                        let t = 1.0 - (d / zoomRadius)
                        let wCurve = t * t * (3 - 2 * t)
                        boost = 4 * CGFloat(scrollProgress) * wCurve
                    }

                    // 2. Gentle ripple wave expanding outward on release
                    if rippleProgress < 1.0 {
                        let dRipple = abs(x - rippleX)
                        let waveRadius = CGFloat(rippleProgress) * 95
                        let waveWidth: CGFloat = 30
                        let distToWave = abs(dRipple - waveRadius)
                        if distToWave < waveWidth {
                            let waveT = 1.0 - (distToWave / waveWidth)
                            let waveCurve = waveT * waveT * (3 - 2 * waveT)
                            let decay = 1.0 - CGFloat(rippleProgress)
                            let rippleBoost = 3 * decay * waveCurve
                            boost = max(boost, rippleBoost)
                        }
                    }

                    let inDoF = hasMeasurement && fraction >= (dofNear - 0.015) && fraction <= (dofFar + 0.015)
                    let tickH: CGFloat = (inDoF ? min(baseRibH + 4, h) : baseRibH) + boost
                    let topY = (h - tickH) / 2
                    let botY = topY + tickH

                    var path = Path()
                    path.move(to: CGPoint(x: x, y: topY))
                    path.addLine(to: CGPoint(x: x, y: botY))

                    let tickColor: Color
                    let lw: CGFloat

                    if isTooClose && !manual && fraction <= 0.12 {
                        tickColor = Color(red: 1.0, green: 0.27, blue: 0.23)
                        lw = 2.0
                    } else if inDoF {
                        // Bright #30D158 green for active Depth-of-Field zone
                        tickColor = Color(red: 0.19, green: 0.82, blue: 0.35)
                        lw = 2.0 + (boost > 0 ? 0.3 : 0)
                    } else {
                        // Calmed inactive ruler ticks (0.26 on major 4th ticks, 0.13 on minor ticks)
                        let inactiveAlpha: Double = (i % 4 == 0) ? 0.26 : 0.13
                        tickColor = Color.white.opacity(inactiveAlpha)
                        lw = 1.5
                    }

                    ctx.stroke(
                        path,
                        with: .color(tickColor),
                        lineWidth: lw
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}
