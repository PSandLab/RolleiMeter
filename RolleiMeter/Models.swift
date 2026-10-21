import Foundation

enum MeterMode: String, CaseIterable {
    case matrix, spot, highlight

    var title: String {
        switch self {
        case .matrix: return "Matrix"
        case .spot: return "Spot"
        case .highlight: return "Highlight"
        }
    }
}

/// Rollei 35 SE: Zeiss Sonnar 40mm f/2.8, f/2.8 to f/22, 1/2 to 1/500 s.
enum Rollei {
    static let stops: [(label: String, n: Double)] = [
        ("2.8", 2.828), ("4", 4.0), ("5.6", 5.657), ("8", 8.0),
        ("11", 11.314), ("16", 16.0), ("22", 22.627)
    ]

    static let fastest = 1.0 / 500.0
    static let slowest = 0.5

    /// Native Rollei 35 shutter speeds from 1/500 to 1/2, fastest first.
    /// The displayed denominator is the engraved dial marking (e.g. 125 for 1/125 s).
    static let speeds: [(label: String, t: Double)] = [
        ("500", 1.0 / 500), ("250", 1.0 / 250), ("125", 1.0 / 125),
        ("60", 1.0 / 60), ("30", 1.0 / 30), ("15", 1.0 / 15),
        ("8", 1.0 / 8), ("4", 1.0 / 4), ("2", 1.0 / 2)
    ]
}

enum ISOScale {
    static let values: [Int] = [
        25, 32, 40, 50, 64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640,
        800, 1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400
    ]

    static func label(_ iso: Int, din: Bool) -> String {
        if din {
            let d = Int((10 * log10(Double(iso)) + 1).rounded())
            return "\(d)°"
        }
        return "\(iso)"
    }
}

enum EVComp {
    /// -2 to +2 in 1/3 stops. Index 6 is zero.
    static let values: [Double] = (-6...6).map { Double($0) / 3.0 }
    static let zeroIndex = 6

    /// Same +⅓ / −⅔ style as the calibration value and the out-of-range shutter readings.
    static let labels: [String] = values.map { Fmt.stops($0) }
}

enum ShutterStatus { case ok, tooFast, tooSlow }

struct ShutterResult {
    let label: String
    /// Seconds. For out-of-range results this is the nearest limit.
    let t: Double
    let status: ShutterStatus
    /// Signed exposure error at the camera's nearest physical shutter limit, in stops.
    let deviation: Double?

    /// Slower than 1/60 s: too slow to hand-hold with confidence. Drives the red aperture.
    var isSlow: Bool { status == .tooSlow || t > 1.0 / 60.0 + 1e-6 }
}

enum Exposure {
    /// Shutter time in seconds that gives correct exposure at aperture `n`.
    static func idealShutter(ev100: Double, iso: Double, comp: Double, n: Double) -> Double {
        let evAtISO = ev100 + log2(iso / 100.0) - comp
        return n * n / pow(2.0, evAtISO)
    }

    static func result(for t: Double) -> ShutterResult {
        if t < Rollei.fastest {
            return ShutterResult(label: "500", t: Rollei.fastest, status: .tooFast,
                                 deviation: log2(Rollei.fastest / t))
        }
        if t > Rollei.slowest {
            return ShutterResult(label: "2", t: Rollei.slowest, status: .tooSlow,
                                 deviation: -log2(t / Rollei.slowest))
        }
        var best = Rollei.speeds[0]
        var bestDist = Double.greatestFiniteMagnitude
        for s in Rollei.speeds {
            let d = abs(log2(t / s.t))
            if d < bestDist {
                bestDist = d
                best = s
            }
        }
        return ShutterResult(label: best.label, t: best.t, status: .ok, deviation: nil)
    }
}

enum Fmt {
    /// Stop difference as +1⅓ / −⅔ / 0.
    static func stops(_ v: Double) -> String {
        let n = Int((abs(v) * 3).rounded())
        if n == 0 { return "0" }
        let whole = n / 3
        let rem = n % 3
        var s = whole > 0 ? "\(whole)" : ""
        if rem == 1 { s += "⅓" }
        if rem == 2 { s += "⅔" }
        return (v > 0 ? "+" : "−") + s
    }

    /// Signed exposure error in stops, quantized to the nearest third for a calm readout.
    static func exposureDeviation(_ stops: Double) -> String {
        exposureAmount(stops) + " EV"
    }

    /// Signed stop amount without a unit, rounded in 1/3-stop steps.
    static func exposureAmount(_ stops: Double) -> String {
        guard stops != 0 else { return "0" }
        let thirds = max(1, Int((abs(stops) * 3).rounded()))
        let whole = thirds / 3
        let remainder = thirds % 3
        var amount = whole > 0 ? "\(whole)" : ""
        if remainder == 1 { amount += "⅓" }
        if remainder == 2 { amount += "⅔" }
        return (stops < 0 ? "−" : "+") + amount
    }

    /// LiDAR distance. `m` is metres; nil shows a dash.
    static func distance(_ m: Double?, feet: Bool) -> String {
        guard let m else { return "—" }
        if m.isInfinite { return "∞" }
        if feet {
            let f = m * 3.28084
            return f < 10 ? String(format: "%.1f ft", f) : String(format: "%.0f ft", f)
        }
        if m < 1 { return String(format: "%.2f m", m) }
        return m < 10 ? String(format: "%.1f m", m) : String(format: "%.0f m", m)
    }
}

// MARK: - Rollei 35 focus scale

enum Focus {
    static let focalMM = 40.0
    /// Closest focusing distance, metres.
    static let nearest = 0.9

    /// Labelled marks, in the order they sit on the lens. Positions are in metres.
    static let meterMarks: [(label: String, m: Double)] = [
        ("0.9", 0.9), ("1.2", 1.2), ("1.5", 1.5), ("2", 2.0), ("3", 3.0), ("6", 6.0), ("∞", .infinity)
    ]
    static let feetMarks: [(label: String, m: Double)] = [
        ("3", 0.9144), ("4", 1.2192), ("6", 1.8288), ("10", 3.048), ("20", 6.096), ("∞", .infinity)
    ]

    /// How far the lens must extend from infinity focus (mm) to focus at `d` metres.
    private static func extensionMM(_ d: Double) -> Double {
        let f = focalMM
        return f * f / (d * 1000.0 - f)
    }

    /// 0 at the closest focus, 1 at infinity. Spaced by lens extension, like the real focusing ring.
    static func position(_ d: Double) -> Double {
        if d.isInfinite { return 1 }
        let x0 = extensionMM(nearest)
        let x = extensionMM(max(d, nearest))
        return min(max(1 - x / x0, 0), 1)
    }
}

// MARK: - Depth of field

enum DepthOfField {
    /// Marked f-numbers, same order as `Rollei.stops`.
    static let apertures: [Double] = [2.8, 4, 5.6, 8, 11, 16, 22]
    /// Circle of confusion for 35mm film, mm.
    static let coc = 0.03

    /// Near and far limits of acceptable sharpness, metres. Far is infinity past the hyperfocal distance.
    static func range(subject s: Double, n: Double) -> (near: Double, far: Double) {
        let f = Focus.focalMM
        let h = f * f / (n * coc) + f
        // Focused at infinity: sharp from half the hyperfocal distance outwards.
        if s.isInfinite { return ((h - f) / 1000.0, Double.infinity) }
        let sMM = s * 1000.0
        let near = sMM * (h - f) / (h + sMM - 2 * f)
        let far = sMM >= h ? Double.infinity : sMM * (h - f) / (h - sMM)
        return (near / 1000.0, far / 1000.0)
    }
}

// MARK: - Focus advice

/// What to set on the lens for a measured distance.
struct FocusAdvice {
    /// Nearest mark on the lens, e.g. "2".
    let label: String
    /// True when the subject is still inside the depth of field with the lens set to that mark.
    let sharp: Bool
    /// When it isn't, the two marks to set between.
    let lo: String
    let hi: String
}

extension Focus {
    /// Nearest mark on the ring (by position, the way you'd eyeball it), then a check against the
    /// depth of field at `aperture`: if the subject is still sharp with the lens on that mark, say so,
    /// otherwise say which two marks to set between.
    static func advice(subject s: Double, aperture n: Double, feet: Bool) -> FocusAdvice {
        let marks = feet ? feetMarks : meterMarks
        let ps = position(s)

        var best = marks[0]
        var bestGap = Double.greatestFiniteMagnitude
        for m in marks {
            let gap = abs(position(m.m) - ps)
            if gap < bestGap {
                bestGap = gap
                best = m
            }
        }

        let r = DepthOfField.range(subject: best.m, n: n)
        let sharp = s >= r.near && s <= r.far

        let lo = marks.last { $0.m <= s } ?? marks[0]
        let hi = marks.first { $0.m > s } ?? marks[marks.count - 1]
        return FocusAdvice(label: best.label, sharp: sharp, lo: lo.label, hi: hi.label)
    }
}
