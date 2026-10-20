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

    /// Third-stop shutter speeds from 1/500 to 1/2, fastest first.
    static let speeds: [(label: String, t: Double)] = {
        let dens: [Double] = [500, 400, 320, 250, 200, 160, 125, 100, 80, 60, 50, 40, 30, 25, 20, 15, 13, 10, 8, 6, 5, 4, 3, 2.5, 2]
        var out: [(label: String, t: Double)] = []
        for d in dens {
            let label = d.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(d)) : String(format: "%.1f", d)
            out.append((label: label, t: 1.0 / d))
        }
        return out
    }()
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

    static let labels: [String] = values.map { v in
        abs(v) < 0.01 ? "0" : String(format: "%+.1f", v)
    }
}

enum ShutterStatus { case ok, tooFast, tooSlow }

struct ShutterResult {
    let label: String
    /// Seconds. For out-of-range results this is the nearest limit.
    let t: Double
    let status: ShutterStatus

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
        let third = pow(2.0, 1.0 / 6.0)   // half a third-stop, for rounding to the limits

        if t < Rollei.fastest / third {
            return ShutterResult(label: "500+", t: Rollei.fastest, status: .tooFast)
        }
        if t > Rollei.slowest * third {
            return ShutterResult(label: "<2", t: Rollei.slowest, status: .tooSlow)
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
        return ShutterResult(label: best.label, t: best.t, status: .ok)
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
        let sMM = s * 1000.0
        let h = f * f / (n * coc) + f
        let near = sMM * (h - f) / (h + sMM - 2 * f)
        let far = sMM >= h ? Double.infinity : sMM * (h - f) / (h - sMM)
        return (near / 1000.0, far / 1000.0)
    }
}
