import SwiftUI

// MARK: - Brand Tone Colors

func resolveBrandToneColor(_ brand: String) -> Color {
    switch brand.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "Leica": return Color(red: 0.863, green: 0.149, blue: 0.149)
    case "Nikon": return Color(red: 0.984, green: 0.749, blue: 0.141)
    case "Fujifilm", "Fujica": return Color(red: 0.063, green: 0.725, blue: 0.506)
    case "Canon": return Color(red: 0.937, green: 0.267, blue: 0.267)
    case "Olympus": return Color(red: 0.231, green: 0.510, blue: 0.965)
    case "Pentax": return Color(red: 0.961, green: 0.620, blue: 0.043)
    case "Minolta": return Color(red: 0.055, green: 0.647, blue: 0.914)
    case "Contax", "Yashica": return Color(red: 0.851, green: 0.467, blue: 0.024)
    case "Hasselblad": return Color(red: 0.580, green: 0.639, blue: 0.722)
    case "Rollei": return Color(red: 0.984, green: 0.573, blue: 0.235)
    case "Mamiya", "Bronica": return Color(red: 0.376, green: 0.647, blue: 0.980)
    case "Ricoh", "Konica": return Color(red: 0.506, green: 0.549, blue: 0.973)
    case "Voigtländer", "Zeiss": return Color(red: 0.220, green: 0.741, blue: 0.973)
    case "Lomography", "Agfa": return Color(red: 0.957, green: 0.247, blue: 0.369)
    default: return Palette.accent
    }
}

// MARK: - Camera Brand Logo (Pure Geometric Emblems + Machined Enamel Medallion Finish)

struct CameraBrandLogo: View {
    let brand: String
    var size: CGFloat = 40

    var body: some View {
        let clean = brand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        Canvas { ctx, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let baseRect = CGRect(x: 0, y: 0, width: w, height: h)
            let baseRRect = Path(baseRect)

            if clean.contains("leica") {
                ctx.fill(baseRRect, with: .color(Color(red: 0.902, green: 0.000, blue: 0.071)))
                let wordmark = ctx.resolve(
                    Text("Leica")
                        .font(.caption2.weight(.semibold).italic())
                        .foregroundStyle(.white)
                )
                ctx.draw(wordmark, at: CGPoint(x: w * 0.5, y: h * 0.53))
            } else if clean.contains("nikon") || clean.contains("nikkormat") || clean.contains("nikkor") {
                ctx.fill(baseRRect, with: .color(Color(red: 1.000, green: 0.824, blue: 0.000)))
                for k in 0...3 {
                    let sx = w * (0.28 + CGFloat(k) * 0.14)
                    var stripe = Path()
                    stripe.move(to: CGPoint(x: sx, y: h * 0.22))
                    stripe.addLine(to: CGPoint(x: sx - w * 0.10, y: h * 0.78))
                    ctx.stroke(
                        stripe,
                        with: .color(Color(red: 0.067, green: 0.067, blue: 0.067)),
                        style: StrokeStyle(lineWidth: w * 0.06, lineCap: .round)
                    )
                }
            } else if clean.contains("canon") {
                ctx.fill(baseRRect, with: .color(Color(red: 0.800, green: 0.000, blue: 0.000)))
                // The C is a ring with a slice cut out of its right side. The old
                // version laid a square over a closed ring, so the letter read as
                // a box instead of an opening.
                let cx = w * 0.50
                let cy = h * 0.50
                let radius = h * 0.27
                var cPath = Path()
                let steps = 44
                let start = 0.055
                let end = 0.945
                for i in 0...steps {
                    let fraction = start + (end - start) * Double(i) / Double(steps)
                    let angle = fraction * 2 * Double.pi
                    let point = CGPoint(x: cx + radius * CGFloat(cos(angle)),
                                        y: cy + radius * CGFloat(sin(angle)))
                    if i == 0 { cPath.move(to: point) } else { cPath.addLine(to: point) }
                }
                ctx.stroke(cPath,
                           with: .color(.white),
                           style: StrokeStyle(lineWidth: w * 0.115, lineCap: .butt))
            } else if clean.contains("olympus") {
                ctx.fill(baseRRect, with: .color(Color(red: 0.000, green: 0.169, blue: 0.400)))
                let r = h * 0.20
                let ringRect = CGRect(x: w * 0.50 - r, y: h * 0.42 - r, width: r * 2, height: r * 2)
                ctx.stroke(Path(ellipseIn: ringRect), with: .color(.white), lineWidth: w * 0.08)
                let barRect = CGRect(x: w * 0.20, y: h * 0.72, width: w * 0.60, height: h * 0.12)
                ctx.fill(Path(roundedRect: barRect, cornerRadius: h * 0.06), with: .color(Color(red: 0.945, green: 0.769, blue: 0.059)))
            } else if clean.contains("minolta") {
                ctx.fill(baseRRect, with: .color(Color(red: 0.000, green: 0.220, blue: 0.659)))
                let cx = w * 0.50
                let cy = h * 0.50
                let rayCount = 8
                for k in 0..<rayCount {
                    let angle = (Double(k) / Double(rayCount)) * .pi
                    let c = CGFloat(cos(angle))
                    let s = CGFloat(sin(angle))
                    var ray = Path()
                    ray.move(to: CGPoint(x: cx - c * w * 0.30, y: cy - s * h * 0.30))
                    ray.addLine(to: CGPoint(x: cx + c * w * 0.30, y: cy + s * h * 0.30))
                    ctx.stroke(
                        ray,
                        with: .color(.white.opacity(0.85)),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                    )
                }
                let outerR = h * 0.18
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - outerR, y: cy - outerR, width: outerR * 2, height: outerR * 2)),
                    with: .color(Color(red: 0.000, green: 0.220, blue: 0.659))
                )
                let innerR = h * 0.13
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - innerR, y: cy - innerR, width: innerR * 2, height: innerR * 2)),
                    with: .color(.white)
                )
            } else if clean.contains("contax") {
                ctx.fill(baseRRect, with: .color(Color(red: 0.118, green: 0.125, blue: 0.141)))
                ctx.fill(
                    Path(CGRect(x: w * 0.15, y: h * 0.25, width: w * 0.70, height: h * 0.14)),
                    with: .color(Color(red: 0.000, green: 0.333, blue: 0.647))
                )
                ctx.fill(
                    Path(CGRect(x: w * 0.15, y: h * 0.45, width: w * 0.70, height: h * 0.30)),
                    with: .color(Color(red: 0.886, green: 0.910, blue: 0.941))
                )
            } else if clean.contains("hasselblad") {
                ctx.fill(baseRRect, with: .color(Color(red: 0.094, green: 0.102, blue: 0.118)))
                let sq = CGRect(x: w * 0.22, y: h * 0.22, width: w * 0.56, height: h * 0.56)
                ctx.stroke(Path(roundedRect: sq, cornerRadius: w * 0.08), with: .color(Color(red: 0.898, green: 0.659, blue: 0.137)), lineWidth: w * 0.08)
                var hMarks = Path()
                hMarks.move(to: CGPoint(x: w * 0.36, y: h * 0.34))
                hMarks.addLine(to: CGPoint(x: w * 0.36, y: h * 0.66))
                hMarks.move(to: CGPoint(x: w * 0.64, y: h * 0.34))
                hMarks.addLine(to: CGPoint(x: w * 0.64, y: h * 0.66))
                hMarks.move(to: CGPoint(x: w * 0.36, y: h * 0.50))
                hMarks.addLine(to: CGPoint(x: w * 0.64, y: h * 0.50))
                ctx.stroke(hMarks, with: .color(.white), style: StrokeStyle(lineWidth: w * 0.06, lineCap: .round))
            } else if clean.contains("pentax") {
                ctx.fill(baseRRect, with: .color(Color(red: 0.600, green: 0.106, blue: 0.106)))
                var peak = Path()
                peak.move(to: CGPoint(x: w * 0.50, y: h * 0.22))
                peak.addLine(to: CGPoint(x: w * 0.78, y: h * 0.55))
                peak.addLine(to: CGPoint(x: w * 0.66, y: h * 0.76))
                peak.addLine(to: CGPoint(x: w * 0.34, y: h * 0.76))
                peak.addLine(to: CGPoint(x: w * 0.22, y: h * 0.55))
                peak.closeSubpath()
                ctx.stroke(peak, with: .color(.white.opacity(0.9)), lineWidth: w * 0.08)
            } else if clean.contains("fujifilm") {
                ctx.fill(baseRRect, with: .color(Color(red: 0.000, green: 0.608, blue: 0.302)))
                var whiteRibbon = Path()
                whiteRibbon.move(to: CGPoint(x: w * 0.14, y: h * 0.74))
                whiteRibbon.addLine(to: CGPoint(x: w * 0.54, y: h * 0.18))
                whiteRibbon.addLine(to: CGPoint(x: w * 0.86, y: h * 0.18))
                whiteRibbon.addLine(to: CGPoint(x: w * 0.46, y: h * 0.74))
                whiteRibbon.closeSubpath()
                ctx.fill(whiteRibbon, with: .color(.white))
                var redSlash = Path()
                redSlash.move(to: CGPoint(x: w * 0.58, y: h * 0.18))
                redSlash.addLine(to: CGPoint(x: w * 0.86, y: h * 0.18))
                redSlash.addLine(to: CGPoint(x: w * 0.86, y: h * 0.58))
                redSlash.closeSubpath()
                ctx.fill(redSlash, with: .color(Color(red: 0.902, green: 0.000, blue: 0.071)))
            } else if clean.contains("fujica") {
                ctx.fill(baseRRect, with: .color(Color(red: 0.024, green: 0.306, blue: 0.231)))
                let r = h * 0.26
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: w * 0.50 - r, y: h * 0.50 - r, width: r * 2, height: r * 2)),
                    with: .color(Color(red: 0.796, green: 0.835, blue: 0.882)),
                    lineWidth: w * 0.08
                )
                var diamond = Path()
                diamond.move(to: CGPoint(x: w * 0.50, y: h * 0.34))
                diamond.addLine(to: CGPoint(x: w * 0.62, y: h * 0.50))
                diamond.addLine(to: CGPoint(x: w * 0.50, y: h * 0.66))
                diamond.addLine(to: CGPoint(x: w * 0.38, y: h * 0.50))
                diamond.closeSubpath()
                ctx.fill(diamond, with: .color(Color(red: 0.863, green: 0.149, blue: 0.149)))
            } else if clean.contains("rollei") {
                ctx.fill(baseRRect, with: .color(Color(red: 0.000, green: 0.302, blue: 0.251)))
                let r = h * 0.20
                let topLens = CGRect(x: w * 0.50 - r, y: h * 0.34 - r, width: r * 2, height: r * 2)
                let botLens = CGRect(x: w * 0.50 - r, y: h * 0.68 - r, width: r * 2, height: r * 2)
                ctx.stroke(Path(ellipseIn: topLens), with: .color(Color(red: 0.502, green: 0.796, blue: 0.769)), lineWidth: w * 0.07)
                ctx.stroke(Path(ellipseIn: botLens), with: .color(Color(red: 0.502, green: 0.796, blue: 0.769)), lineWidth: w * 0.07)
            } else if clean.contains("ricoh") {
                ctx.fill(baseRRect, with: .color(Color(red: 0.153, green: 0.153, blue: 0.165)))
                var bar = Path()
                bar.move(to: CGPoint(x: w * 0.22, y: h * 0.50))
                bar.addLine(to: CGPoint(x: w * 0.58, y: h * 0.50))
                ctx.stroke(bar, with: .color(.white), style: StrokeStyle(lineWidth: w * 0.08, lineCap: .round))
                let dotR = h * 0.18
                ctx.fill(
                    Path(ellipseIn: CGRect(x: w * 0.74 - dotR, y: h * 0.50 - dotR, width: dotR * 2, height: dotR * 2)),
                    with: .color(Color(red: 0.937, green: 0.267, blue: 0.267))
                )
            } else if clean.contains("mamiya") {
                ctx.fill(baseRRect, with: .color(Color(red: 0.094, green: 0.094, blue: 0.106)))
                let frame = CGRect(x: w * 0.16, y: h * 0.32, width: w * 0.68, height: h * 0.36)
                ctx.stroke(
                    Path(roundedRect: frame, cornerRadius: w * 0.06),
                    with: .color(Color(red: 0.961, green: 0.620, blue: 0.043)),
                    lineWidth: w * 0.07
                )
            } else if clean.contains("yashica") {
                ctx.fill(baseRRect, with: .color(Color(red: 0.863, green: 0.149, blue: 0.149)))
                let r1 = h * 0.22
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: w * 0.50 - r1, y: h * 0.50 - r1, width: r1 * 2, height: r1 * 2)),
                    with: .color(.white),
                    lineWidth: w * 0.08
                )
                let r2 = h * 0.10
                ctx.fill(
                    Path(ellipseIn: CGRect(x: w * 0.50 - r2, y: h * 0.50 - r2, width: r2 * 2, height: r2 * 2)),
                    with: .color(Color(red: 0.984, green: 0.749, blue: 0.141))
                )
            } else if clean.contains("voigt") {
                ctx.fill(baseRRect, with: .color(Color(red: 0.169, green: 0.094, blue: 0.063)))
                let r = h * 0.25
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: w * 0.50 - r, y: h * 0.50 - r, width: r * 2, height: r * 2)),
                    with: .color(Color(red: 0.831, green: 0.686, blue: 0.216)),
                    lineWidth: w * 0.08
                )
                var cross = Path()
                cross.move(to: CGPoint(x: w * 0.50, y: h * 0.18))
                cross.addLine(to: CGPoint(x: w * 0.50, y: h * 0.82))
                cross.move(to: CGPoint(x: w * 0.22, y: h * 0.50))
                cross.addLine(to: CGPoint(x: w * 0.78, y: h * 0.50))
                ctx.stroke(cross, with: .color(Color(red: 0.831, green: 0.686, blue: 0.216)), lineWidth: 1.2)
            } else if clean.contains("zeiss") {
                ctx.fill(baseRRect, with: .color(Color(red: 0.000, green: 0.294, blue: 0.529)))
                let r = h * 0.24
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: w * 0.50 - r, y: h * 0.50 - r, width: r * 2, height: r * 2)),
                    with: .color(.white),
                    lineWidth: w * 0.08
                )
                var bar = Path()
                bar.move(to: CGPoint(x: w * 0.28, y: h * 0.50))
                bar.addLine(to: CGPoint(x: w * 0.72, y: h * 0.50))
                ctx.stroke(bar, with: .color(.white), style: StrokeStyle(lineWidth: w * 0.07, lineCap: .round))
            } else if clean.contains("agfa") {
                ctx.fill(baseRRect, with: .color(Color(red: 0.918, green: 0.345, blue: 0.047)))
                var diamond = Path()
                diamond.move(to: CGPoint(x: w * 0.50, y: h * 0.18))
                diamond.addLine(to: CGPoint(x: w * 0.82, y: h * 0.50))
                diamond.addLine(to: CGPoint(x: w * 0.50, y: h * 0.82))
                diamond.addLine(to: CGPoint(x: w * 0.18, y: h * 0.50))
                diamond.closeSubpath()
                ctx.stroke(diamond, with: .color(.white), lineWidth: w * 0.08)
                let r = h * 0.10
                ctx.fill(Path(ellipseIn: CGRect(x: w * 0.50 - r, y: h * 0.50 - r, width: r * 2, height: r * 2)), with: .color(.white))
            } else if clean.contains("bronica") {
                ctx.fill(baseRRect, with: .color(Color(red: 0.118, green: 0.161, blue: 0.231)))
                let sq = CGRect(x: w * 0.20, y: h * 0.20, width: w * 0.60, height: h * 0.60)
                ctx.stroke(Path(roundedRect: sq, cornerRadius: w * 0.06), with: .color(Color(red: 0.580, green: 0.639, blue: 0.722)), lineWidth: w * 0.07)
                var stem = Path()
                stem.move(to: CGPoint(x: w * 0.38, y: h * 0.32))
                stem.addLine(to: CGPoint(x: w * 0.38, y: h * 0.68))
                ctx.stroke(stem, with: .color(Color(red: 0.220, green: 0.741, blue: 0.973)), style: StrokeStyle(lineWidth: w * 0.08, lineCap: .round))
                let r = h * 0.11
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: w * 0.54 - r, y: h * 0.41 - r, width: r * 2, height: r * 2)),
                    with: .color(Color(red: 0.220, green: 0.741, blue: 0.973)),
                    lineWidth: w * 0.06
                )
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: w * 0.54 - r, y: h * 0.59 - r, width: r * 2, height: r * 2)),
                    with: .color(Color(red: 0.220, green: 0.741, blue: 0.973)),
                    lineWidth: w * 0.06
                )
            } else if clean.contains("konica") {
                ctx.fill(baseRRect, with: .color(Color(red: 0.118, green: 0.251, blue: 0.686)))
                let r = h * 0.22
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: w * 0.50 - r, y: h * 0.50 - r, width: r * 2, height: r * 2)),
                    with: .color(.white),
                    lineWidth: w * 0.08
                )
                var ray = Path()
                ray.move(to: CGPoint(x: w * 0.16, y: h * 0.60))
                ray.addLine(to: CGPoint(x: w * 0.84, y: h * 0.40))
                ray.addLine(to: CGPoint(x: w * 0.84, y: h * 0.48))
                ray.addLine(to: CGPoint(x: w * 0.16, y: h * 0.68))
                ray.closeSubpath()
                ctx.fill(ray, with: .color(Color(red: 0.976, green: 0.451, blue: 0.086)))
            } else if clean.contains("lomograph") || clean == "lomo" {
                ctx.fill(baseRRect, with: .color(Color(red: 0.008, green: 0.518, blue: 0.780)))
                let r1 = h * 0.26
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: w * 0.50 - r1, y: h * 0.50 - r1, width: r1 * 2, height: r1 * 2)),
                    with: .color(Color(red: 0.984, green: 0.749, blue: 0.141)),
                    lineWidth: w * 0.08
                )
                let r2 = h * 0.14
                ctx.fill(
                    Path(ellipseIn: CGRect(x: w * 0.50 - r2, y: h * 0.50 - r2, width: r2 * 2, height: r2 * 2)),
                    with: .color(Color(red: 0.937, green: 0.267, blue: 0.267))
                )
            } else if clean.contains("plaubel") {
                ctx.fill(baseRRect, with: .color(Color(red: 0.078, green: 0.122, blue: 0.102)))
                let sq = CGRect(x: w * 0.18, y: h * 0.18, width: w * 0.64, height: h * 0.64)
                ctx.stroke(Path(roundedRect: sq, cornerRadius: w * 0.08), with: .color(Color(red: 0.918, green: 0.702, blue: 0.031)), lineWidth: w * 0.06)
                var mPath = Path()
                mPath.move(to: CGPoint(x: w * 0.30, y: h * 0.66))
                mPath.addLine(to: CGPoint(x: w * 0.30, y: h * 0.34))
                mPath.addLine(to: CGPoint(x: w * 0.50, y: h * 0.52))
                mPath.addLine(to: CGPoint(x: w * 0.70, y: h * 0.34))
                mPath.addLine(to: CGPoint(x: w * 0.70, y: h * 0.66))
                ctx.stroke(
                    mPath,
                    with: .color(Color(red: 0.937, green: 0.267, blue: 0.267)),
                    style: StrokeStyle(lineWidth: w * 0.08, lineCap: .round, lineJoin: .round)
                )
            } else if clean.contains("praktica") {
                ctx.fill(baseRRect, with: .color(Color(red: 0.200, green: 0.255, blue: 0.333)))
                var prism = Path()
                prism.move(to: CGPoint(x: w * 0.50, y: h * 0.22))
                prism.addLine(to: CGPoint(x: w * 0.76, y: h * 0.60))
                prism.addLine(to: CGPoint(x: w * 0.24, y: h * 0.60))
                prism.closeSubpath()
                ctx.fill(prism, with: .color(Color(red: 0.863, green: 0.149, blue: 0.149)))
                var baseBar = Path()
                baseBar.move(to: CGPoint(x: w * 0.24, y: h * 0.74))
                baseBar.addLine(to: CGPoint(x: w * 0.76, y: h * 0.74))
                ctx.stroke(baseBar, with: .color(Color(red: 0.796, green: 0.835, blue: 0.882)), style: StrokeStyle(lineWidth: w * 0.08, lineCap: .round))
            } else if clean.contains("fed") {
                ctx.fill(baseRRect, with: .color(Color(red: 0.216, green: 0.255, blue: 0.318)))
                var wing = Path()
                wing.move(to: CGPoint(x: w * 0.20, y: h * 0.38))
                wing.addLine(to: CGPoint(x: w * 0.50, y: h * 0.60))
                wing.addLine(to: CGPoint(x: w * 0.80, y: h * 0.38))
                wing.addLine(to: CGPoint(x: w * 0.50, y: h * 0.74))
                wing.closeSubpath()
                ctx.fill(wing, with: .color(Color(red: 0.863, green: 0.149, blue: 0.149)))
                let r = h * 0.12
                ctx.fill(Path(ellipseIn: CGRect(x: w * 0.50 - r, y: h * 0.44 - r, width: r * 2, height: r * 2)), with: .color(.white))
            } else if clean.contains("zenit") {
                ctx.fill(baseRRect, with: .color(Color(red: 0.122, green: 0.161, blue: 0.216)))
                var tri = Path()
                tri.move(to: CGPoint(x: w * 0.50, y: h * 0.20))
                tri.addLine(to: CGPoint(x: w * 0.78, y: h * 0.70))
                tri.addLine(to: CGPoint(x: w * 0.22, y: h * 0.70))
                tri.closeSubpath()
                ctx.stroke(tri, with: .color(Color(red: 0.886, green: 0.910, blue: 0.941)), lineWidth: w * 0.07)
                let r = h * 0.11
                ctx.fill(
                    Path(ellipseIn: CGRect(x: w * 0.50 - r, y: h * 0.52 - r, width: r * 2, height: r * 2)),
                    with: .color(Color(red: 0.937, green: 0.267, blue: 0.267))
                )
            } else if clean.contains("zorki") {
                ctx.fill(baseRRect, with: .color(Color(red: 0.118, green: 0.161, blue: 0.231)))
                let r = h * 0.24
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: w * 0.50 - r, y: h * 0.50 - r, width: r * 2, height: r * 2)),
                    with: .color(Color(red: 0.796, green: 0.835, blue: 0.882)),
                    lineWidth: w * 0.07
                )
                var zPath = Path()
                zPath.move(to: CGPoint(x: w * 0.34, y: h * 0.35))
                zPath.addLine(to: CGPoint(x: w * 0.66, y: h * 0.35))
                zPath.addLine(to: CGPoint(x: w * 0.34, y: h * 0.65))
                zPath.addLine(to: CGPoint(x: w * 0.66, y: h * 0.65))
                ctx.stroke(
                    zPath,
                    with: .color(Color(red: 0.882, green: 0.114, blue: 0.282)),
                    style: StrokeStyle(lineWidth: w * 0.08, lineCap: .round, lineJoin: .round)
                )
            } else if clean.contains("kodak") {
                ctx.fill(baseRRect, with: .color(Color(red: 1.000, green: 0.780, blue: 0.173)))
                var kPath = Path()
                kPath.move(to: CGPoint(x: w * 0.28, y: h * 0.24))
                kPath.addLine(to: CGPoint(x: w * 0.38, y: h * 0.24))
                kPath.addLine(to: CGPoint(x: w * 0.38, y: h * 0.76))
                kPath.addLine(to: CGPoint(x: w * 0.28, y: h * 0.76))
                kPath.closeSubpath()
                kPath.move(to: CGPoint(x: w * 0.68, y: h * 0.24))
                kPath.addLine(to: CGPoint(x: w * 0.40, y: h * 0.50))
                kPath.addLine(to: CGPoint(x: w * 0.70, y: h * 0.76))
                kPath.addLine(to: CGPoint(x: w * 0.54, y: h * 0.76))
                kPath.addLine(to: CGPoint(x: w * 0.36, y: h * 0.52))
                kPath.addLine(to: CGPoint(x: w * 0.54, y: h * 0.24))
                kPath.closeSubpath()
                ctx.fill(kPath, with: .color(Color(red: 0.851, green: 0.133, blue: 0.165)))
            } else {
                ctx.fill(baseRRect, with: .color(Color(red: 0.200, green: 0.255, blue: 0.333)))
                let r = h * 0.22
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: w * 0.50 - r, y: h * 0.50 - r, width: r * 2, height: r * 2)),
                    with: .color(Color(red: 0.580, green: 0.639, blue: 0.722)),
                    lineWidth: w * 0.08
                )
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Co-Axial Camera Mount Throat Canvas

struct CoAxialCameraThroatCanvas: View {
    let cameraBrand: String
    let cameraModel: String
    let mount: String
    let isFixed: Bool
    let maxShutter: Double
    var isAdapter: Bool = false
    var lockPinProgress: CGFloat = 0.0     // 0.0 -> 1.0 when bayonet pin snaps into notch
    var mirrorFlipProgress: CGFloat = 0.0  // 0.0 -> 1.0 SLR 45-deg mirror flip-up during test-fire
    var shutterFlashProgress: CGFloat = 0.0// 0.0 -> 1.0 focal-plane / leaf shutter actuation flash

    private var isMediumFormat: Bool {
        let m = mount.lowercased()
        return m.contains("hasselblad") || m.contains("mamiya") || m.contains("bronica") || m.contains("67") || m.contains("645") || m.contains("sl66")
    }

    private var isRangefinder: Bool {
        let m = mount.lowercased()
        return m.contains("leica") || m.contains("ltm") || m.contains("m39") || m.contains("nikon s") || m.contains("contax g") || m.contains("xpan")
    }

    private var hasTitaniumHoneycombCurtain: Bool {
        maxShutter <= 0.00026 && !isRangefinder && !isFixed // 1/4000s or faster SLR (e.g. Nikon FM2 / FE2 / FA)
    }

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width * 0.5
            let cy = size.height * 0.5
            let outerR = min(size.width, size.height) * 0.44
            let throatR = outerR * 0.72

            // 1. Anodized Camera Body Casting Silhouette Behind Flange
            let bodyW = size.width * 0.92
            let bodyH = size.height * 0.80
            let bodyRect = CGRect(x: cx - bodyW * 0.5, y: cy - bodyH * 0.5, width: bodyW, height: bodyH)
            ctx.fill(
                Path(roundedRect: bodyRect, cornerRadius: 14),
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.14, green: 0.15, blue: 0.18),
                        Color(red: 0.07, green: 0.08, blue: 0.10)
                    ]),
                    startPoint: CGPoint(x: bodyRect.minX, y: bodyRect.minY),
                    endPoint: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY)
                )
            )
            ctx.stroke(Path(roundedRect: bodyRect, cornerRadius: 14), with: .color(Color.white.opacity(0.08)), lineWidth: 1.0)

            // Leatherette Grip Texture Panels on Left & Right Wings
            let leftGrip = CGRect(x: bodyRect.minX + 5, y: bodyRect.minY + 10, width: 18, height: bodyH - 20)
            let rightGrip = CGRect(x: bodyRect.maxX - 23, y: bodyRect.minY + 10, width: 18, height: bodyH - 20)
            for grip in [leftGrip, rightGrip] {
                ctx.fill(Path(roundedRect: grip, cornerRadius: 4), with: .color(Color.black.opacity(0.55)))
            }

            // 2. Machined Chrome / Brass Bayonet Mount Flange Ring
            let flangeRect = CGRect(x: cx - outerR, y: cy - outerR, width: outerR * 2, height: outerR * 2)
            ctx.fill(
                Path(ellipseIn: flangeRect),
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.78, green: 0.82, blue: 0.88),
                        Color(red: 0.42, green: 0.46, blue: 0.52),
                        Color(red: 0.85, green: 0.88, blue: 0.92),
                        Color(red: 0.28, green: 0.31, blue: 0.36)
                    ]),
                    startPoint: CGPoint(x: flangeRect.minX, y: flangeRect.minY),
                    endPoint: CGPoint(x: flangeRect.maxX, y: flangeRect.maxY)
                )
            )

            // Optional Knurled Brass Adapter Ring when MountSetup == .adapter
            if isAdapter {
                let adapterR = outerR * 0.91
                let adapterRect = CGRect(x: cx - adapterR, y: cy - adapterR, width: adapterR * 2, height: adapterR * 2)
                ctx.stroke(
                    Path(ellipseIn: adapterRect),
                    with: .color(Color(red: 0.88, green: 0.68, blue: 0.32)),
                    style: StrokeStyle(lineWidth: 3.2, dash: [3.0, 2.0])
                )
            }

            // 3. Deep Velvet-Flocked Optical Throat Cavity
            let throatRect = CGRect(x: cx - throatR, y: cy - throatR, width: throatR * 2, height: throatR * 2)
            ctx.fill(Path(ellipseIn: throatRect), with: .color(Color(red: 0.03, green: 0.035, blue: 0.045)))

            // 4. Internal Camera Architecture (SLR Mirror vs Rangefinder Cam vs Medium Format Gate)
            var throatCtx = ctx
            throatCtx.clip(to: Path(ellipseIn: throatRect))

            if isMediumFormat {
                // Square 6x6 / 6x7 Baffle Gate + Auxiliary Barn-Door Flaps
                let gateS = throatR * 1.28
                let gateRect = CGRect(x: cx - gateS * 0.5, y: cy - gateS * 0.5, width: gateS, height: gateS)
                throatCtx.stroke(Path(roundedRect: gateRect, cornerRadius: 3), with: .color(Color.white.opacity(0.18)), lineWidth: 1.2)

                let barnOpen = shutterFlashProgress * (gateS * 0.42)
                let topBarn = CGRect(x: gateRect.minX, y: gateRect.minY, width: gateS, height: max(2, gateS * 0.48 - barnOpen))
                let botBarn = CGRect(x: gateRect.minX, y: gateRect.maxY - max(2, gateS * 0.48 - barnOpen), width: gateS, height: max(2, gateS * 0.48 - barnOpen))
                throatCtx.fill(Path(topBarn), with: .color(Color(red: 0.10, green: 0.11, blue: 0.13)))
                throatCtx.fill(Path(botBarn), with: .color(Color(red: 0.08, green: 0.09, blue: 0.11)))

            } else if isRangefinder {
                // Rubberized Cloth Focal-Plane Curtain + 12 O'Clock Brass Rangefinder Cam Roller
                let gateW = throatR * 1.45
                let gateH = throatR * 0.96
                let gateRect = CGRect(x: cx - gateW * 0.5, y: cy - gateH * 0.5, width: gateW, height: gateH)
                throatCtx.fill(Path(roundedRect: gateRect, cornerRadius: 2), with: .color(Color(red: 0.11, green: 0.12, blue: 0.14)))

                // Curtain Slit Sweep during Test-Fire
                if shutterFlashProgress > 0.01 {
                    let slitX = gateRect.minX + gateW * shutterFlashProgress
                    let slitRect = CGRect(x: slitX - 8, y: gateRect.minY, width: 16, height: gateH)
                    throatCtx.fill(Path(slitRect), with: .color(Color.white.opacity(0.55)))
                }

                // Brass Rangefinder Coupling Roller at 12 O'Clock
                let rollerRect = CGRect(x: cx - 4.5, y: cy - throatR + 1.5, width: 9.0, height: 5.5)
                throatCtx.fill(Path(roundedRect: rollerRect, cornerRadius: 2), with: .color(Color(red: 0.90, green: 0.72, blue: 0.34)))

            } else {
                // 35mm SLR: Curtain Plane Behind + 45-Degree Silvered Reflex Mirror
                let gateW = throatR * 1.42
                let gateH = throatR * 0.96
                let gateRect = CGRect(x: cx - gateW * 0.5, y: cy - gateH * 0.5, width: gateW, height: gateH)
                throatCtx.fill(Path(roundedRect: gateRect, cornerRadius: 2), with: .color(Color(red: 0.12, green: 0.13, blue: 0.16)))

                // Titanium Honeycomb Etching Pattern if maxShutter <= 1/4000s (Nikon FM2 / FE2)
                if hasTitaniumHoneycombCurtain {
                    for row in 0..<3 {
                        for col in 0..<5 {
                            let hx = gateRect.minX + 5 + CGFloat(col) * 9.5 + (row % 2 == 0 ? 0 : 4.5)
                            let hy = gateRect.minY + 4 + CGFloat(row) * 8.5
                            let hexRect = CGRect(x: hx, y: hy, width: 5.5, height: 5.5)
                            throatCtx.stroke(Path(roundedRect: hexRect, cornerRadius: 1.5), with: .color(Color.white.opacity(0.22)), lineWidth: 0.7)
                        }
                    }
                }

                // 45-Degree Silver Reflex Mirror (Flips upward as mirrorFlipProgress -> 1.0)
                let mirrorH = gateH * (1.0 - mirrorFlipProgress * 0.88)
                let mirrorRect = CGRect(x: cx - gateW * 0.46, y: cy - gateH * 0.46, width: gateW * 0.92, height: max(3.0, mirrorH))
                throatCtx.fill(
                    Path(roundedRect: mirrorRect, cornerRadius: 2.5),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.55, green: 0.62, blue: 0.70).opacity(0.85),
                            Color(red: 0.22, green: 0.26, blue: 0.32).opacity(0.90),
                            Color(red: 0.75, green: 0.80, blue: 0.88).opacity(0.75)
                        ]),
                        startPoint: CGPoint(x: mirrorRect.minX, y: mirrorRect.minY),
                        endPoint: CGPoint(x: mirrorRect.maxX, y: mirrorRect.maxY)
                    )
                )
                throatCtx.stroke(Path(roundedRect: mirrorRect, cornerRadius: 2.5), with: .color(Color.white.opacity(0.45)), lineWidth: 0.8)
            }

            // 5. Three Machined Bayonet Locking Lugs Around Throat Perimeter
            let lugAngles: [Double] = [-30.0, 90.0, 210.0]
            for deg in lugAngles {
                let rad = deg * .pi / 180.0
                var lugArc = Path()
                lugArc.addArc(
                    center: CGPoint(x: cx, y: cy),
                    radius: throatR + 2.0,
                    startAngle: .radians(rad - 0.32),
                    endAngle: .radians(rad + 0.32),
                    clockwise: false
                )
                ctx.stroke(lugArc, with: .color(Color(red: 0.86, green: 0.89, blue: 0.94)), lineWidth: 3.5)
            }

            // 6. Red Enamel Alignment Dot (#E60012) at 12 O'Clock & Spring Lock-Pin at 3 O'Clock
            let redDotR: CGFloat = 2.8
            let redDotCenter = CGPoint(x: cx, y: cy - outerR + 5.0)
            ctx.fill(
                Path(ellipseIn: CGRect(x: redDotCenter.x - redDotR, y: redDotCenter.y - redDotR, width: redDotR * 2, height: redDotR * 2)),
                with: .color(Color(red: 0.90, green: 0.0, blue: 0.07))
            )

            // Spring-Loaded Bayonet Lock Pin at 3 O'Clock (Shoots inward and turns gold when locked)
            let pinR: CGFloat = 2.6 + lockPinProgress * 0.8
            let pinX = cx + outerR - 5.5 - (lockPinProgress * 2.0)
            let pinRect = CGRect(x: pinX - pinR, y: cy - pinR, width: pinR * 2, height: pinR * 2)
            ctx.fill(
                Path(ellipseIn: pinRect),
                with: .color(lockPinProgress > 0.5 ? Palette.accent : Color(red: 0.82, green: 0.85, blue: 0.90))
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Procedural Co-Axial Lens Barrel, Multi-Coating & Iris Canvas

struct ProceduralLensBarrelCanvas: View {
    let lensBrand: String
    let lensName: String
    let mount: String
    let minAperture: Double
    let maxAperture: Double
    var variantLabel: String = ""
    var bayonetAngle: Double = 0.0         // 0 -> 65 -> 90 degrees during twist
    var irisStopDownProgress: CGFloat = 0.0// 0.0 (wide open) -> 1.0 (stopped down to f/16)
    var coatingFlareProgress: CGFloat = 0.0// 0.0 -> 1.0 test-fire dichroic ripple

    // Entrance pupil diameter scales authentically with widest f-stop (f/0.95 = 0.86, f/4.0 = 0.46)
    private var glassRatio: CGFloat {
        let clampedF = min(max(minAperture, 0.95), 5.6)
        return CGFloat(min(max(0.86 - (clampedF - 0.95) * 0.11, 0.44), 0.86))
    }

    // Sub-variant hardware detection
    private var isNikonPreAI: Bool {
        variantLabel.localizedCaseInsensitiveContains("pre-ai") || lensName.localizedCaseInsensitiveContains("pre-ai")
    }
    private var isNikonAIS: Bool {
        variantLabel.localizedCaseInsensitiveContains("ai-s") || lensName.localizedCaseInsensitiveContains("ai-s")
    }
    private var isCanonBreechLock: Bool {
        variantLabel.localizedCaseInsensitiveContains("breech") || lensName.localizedCaseInsensitiveContains("breech")
    }
    private var isRadioactiveThoriumTakumar: Bool {
        let combined = "\(lensBrand) \(lensName) \(variantLabel)".lowercased()
        return combined.contains("super-takumar") || (combined.contains("takumar") && !combined.contains("smc"))
    }
    private var isLeicaPreASPH: Bool {
        variantLabel.localizedCaseInsensitiveContains("pre-asph") || variantLabel.localizedCaseInsensitiveContains("classic")
    }
    private var isZeissNinjaStarAE: Bool {
        let b = "\(lensBrand) \(lensName)".lowercased()
        let v = variantLabel.lowercased()
        return (b.contains("zeiss") || b.contains("planar") || b.contains("distagon") || b.contains("sonnar")) && v.contains("ae")
    }

    // Authentic Thin-Film Interference Multi-Coating Colors by Optical House
    private var coatingColors: (primary: Color, secondary: Color) {
        let full = "\(lensBrand) \(lensName)".lowercased()
        if full.contains("zeiss") || full.contains("planar") || full.contains("distagon") || full.contains("biogon") || full.contains("sonnar") && !full.contains("rollei") {
            // Carl Zeiss T* Magenta & Cobalt Blue
            return (Color(red: 0.66, green: 0.33, blue: 0.97), Color(red: 0.15, green: 0.39, blue: 0.92))
        } else if full.contains("takumar") || full.contains("pentax") || full.contains("smc") {
            // Asahi Pentax SMC Amber & Emerald Green
            return (Color(red: 0.96, green: 0.62, blue: 0.04), Color(red: 0.06, green: 0.73, blue: 0.51))
        } else if full.contains("leica") || full.contains("summicron") || full.contains("summilux") || full.contains("noctilux") || full.contains("elmar") {
            // Leitz Wetzlar Cyan-Aqua & Champagne Gold
            return (Color(red: 0.02, green: 0.71, blue: 0.83), Color(red: 0.83, green: 0.69, blue: 0.22))
        } else if full.contains("rollei") || full.contains("hft") {
            // Rollei HFT Ruby Red & Deep Violet
            return (Color(red: 0.88, green: 0.11, blue: 0.28), Color(red: 0.43, green: 0.16, blue: 0.85))
        } else {
            // Nikon NIC / Canon S.S.C. Emerald Green & Crimson
            return (Color(red: 0.06, green: 0.73, blue: 0.51), Color(red: 0.88, green: 0.11, blue: 0.28))
        }
    }

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width * 0.5
            let cy = size.height * 0.5
            let barrelR = min(size.width, size.height) * 0.44
            let glassR = barrelR * glassRatio

            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: .degrees(bayonetAngle))
            ctx.translateBy(x: -cx, y: -cy)

            // 1. Sub-Variant: Leica Pre-ASPH Concave Crescent Focusing Tab at 7 O'Clock
            if isLeicaPreASPH {
                var tabPath = Path()
                let tabAngle = 135.0 * .pi / 180.0
                let tx = cx + cos(tabAngle) * (barrelR + 4.0)
                let ty = cy + sin(tabAngle) * (barrelR + 4.0)
                tabPath.addEllipse(in: CGRect(x: tx - 7, y: ty - 5, width: 14, height: 10))
                ctx.fill(tabPath, with: .color(Color(red: 0.22, green: 0.24, blue: 0.28)))
                ctx.stroke(tabPath, with: .color(Color.white.opacity(0.35)), lineWidth: 1.0)
            }

            // 2. Sub-Variant: Nikon Pre-AI Silver "Bunny Ears" Metering Prong at 12 O'Clock
            if isNikonPreAI {
                let prongRect = CGRect(x: cx - 8.0, y: cy - barrelR - 4.5, width: 16.0, height: 6.5)
                ctx.fill(Path(roundedRect: prongRect, cornerRadius: 2.0), with: .color(Color(red: 0.84, green: 0.87, blue: 0.92)))
                let notchRect = CGRect(x: cx - 2.2, y: cy - barrelR - 5.0, width: 4.4, height: 4.0)
                ctx.fill(Path(notchRect), with: .color(Color.black))
            }

            // 3. Outer Anodized Aluminum / Silver Breech-Lock Barrel Ring
            let outerRect = CGRect(x: cx - barrelR, y: cy - barrelR, width: barrelR * 2, height: barrelR * 2)
            if isCanonBreechLock {
                // Brushed Silver Knurled Breech-Lock Collar
                ctx.fill(
                    Path(ellipseIn: outerRect),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.80, green: 0.83, blue: 0.88),
                            Color(red: 0.45, green: 0.48, blue: 0.54),
                            Color(red: 0.72, green: 0.76, blue: 0.82)
                        ]),
                        startPoint: CGPoint(x: outerRect.minX, y: outerRect.minY),
                        endPoint: CGPoint(x: outerRect.maxX, y: outerRect.maxY)
                    )
                )
            } else {
                // Deep Anodized Black Machined Barrel
                ctx.fill(
                    Path(ellipseIn: outerRect),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.22, green: 0.24, blue: 0.28),
                            Color(red: 0.08, green: 0.09, blue: 0.11),
                            Color(red: 0.16, green: 0.18, blue: 0.21)
                        ]),
                        startPoint: CGPoint(x: outerRect.minX, y: outerRect.minY),
                        endPoint: CGPoint(x: outerRect.maxX, y: outerRect.maxY)
                    )
                )
            }

            // 4. Knurled Focus Grip Teeth Around Perimeter (24 Machined Ribs)
            let ribCount = 24
            for i in 0..<ribCount {
                let rad = (Double(i) / Double(ribCount)) * 2.0 * .pi
                let r1 = barrelR - 3.2
                let r2 = barrelR - 0.6
                var rib = Path()
                rib.move(to: CGPoint(x: cx + CGFloat(cos(rad)) * r1, y: cy + CGFloat(sin(rad)) * r1))
                rib.addLine(to: CGPoint(x: cx + CGFloat(cos(rad)) * r2, y: cy + CGFloat(sin(rad)) * r2))
                ctx.stroke(rib, with: .color(Color.white.opacity(isCanonBreechLock ? 0.45 : 0.18)), lineWidth: 1.3)
            }

            // 5. Stepped Matte-Black Anti-Reflection Baffle Ring & Aperture Detent Dots
            let baffleR = barrelR * 0.88
            let baffleRect = CGRect(x: cx - baffleR, y: cy - baffleR, width: baffleR * 2, height: baffleR * 2)
            ctx.fill(Path(ellipseIn: baffleRect), with: .color(Color(red: 0.06, green: 0.07, blue: 0.09)))
            ctx.stroke(Path(ellipseIn: baffleRect), with: .color(Color.white.opacity(0.14)), lineWidth: 0.8)

            // Engraved Aperture Scale Dots Along Top Arc (Orange minimum stop if Nikon AI-S!)
            let dotAngles: [Double] = [-125, -110, -95, -80, -65, -50]
            for (idx, deg) in dotAngles.enumerated() {
                let rad = deg * .pi / 180.0
                let dr = (baffleR + glassR) * 0.5
                let dx = cx + CGFloat(cos(rad)) * dr
                let dy = cy + CGFloat(sin(rad)) * dr
                let isLastStop = (idx == dotAngles.count - 1)
                let dotColor: Color = (isLastStop && isNikonAIS)
                    ? Color(red: 1.0, green: 0.43, blue: 0.0) // Nikon AI-S Orange
                    : (idx == 0 ? Palette.accent : Color.white.opacity(0.65))
                ctx.fill(Path(ellipseIn: CGRect(x: dx - 1.3, y: dy - 1.3, width: 2.6, height: 2.6)), with: .color(dotColor))
            }

            // 6. Optical Glass Element Base + Radioactive Thorium-232 Tint (if Super-Takumar)
            let glassRect = CGRect(x: cx - glassR, y: cy - glassR, width: glassR * 2, height: glassR * 2)
            ctx.fill(Path(ellipseIn: glassRect), with: .color(Color(red: 0.03, green: 0.04, blue: 0.06)))

            if isRadioactiveThoriumTakumar {
                ctx.fill(
                    Path(ellipseIn: glassRect),
                    with: .radialGradient(
                        Gradient(colors: [
                            Color(red: 0.85, green: 0.55, blue: 0.08).opacity(0.34),
                            Color(red: 0.65, green: 0.38, blue: 0.04).opacity(0.16)
                        ]),
                        center: CGPoint(x: cx, y: cy),
                        startRadius: 2,
                        endRadius: glassR
                    )
                )
            }

            // 7. LIVE STOPPING-DOWN MULTI-BLADE IRIS DIAPHRAGM (Including Zeiss AE Ninja-Star!)
            let minHoleRatio: CGFloat = 0.22
            let maxHoleRatio: CGFloat = 0.76
            let currentIrisRatio = maxHoleRatio - (maxHoleRatio - minHoleRatio) * irisStopDownProgress
            let irisOpenR = glassR * currentIrisRatio

            // Dark Iris Leaf Annulus
            var irisCtx = ctx
            irisCtx.clip(to: Path(ellipseIn: glassRect))

            // Draw 7-blade polygon opening (with sawtooth Ninja-Star cusps if Zeiss AE!)
            let bladeCount = isZeissNinjaStarAE ? 6 : 7
            var irisOpeningPath = Path()
            let totalVertices = bladeCount * 2
            for v in 0..<totalVertices {
                let angle = (Double(v) / Double(totalVertices)) * 2.0 * .pi + Double(irisStopDownProgress) * 0.45
                let isCusp = (v % 2 == 1)
                let rFactor: CGFloat = (isZeissNinjaStarAE && isCusp) ? (1.0 + 0.18 * (0.4 + irisStopDownProgress * 0.6)) : 1.0
                let r = irisOpenR * rFactor
                let px = cx + CGFloat(cos(angle)) * r
                let py = cy + CGFloat(sin(angle)) * r
                if v == 0 {
                    irisOpeningPath.move(to: CGPoint(x: px, y: py))
                } else {
                    irisOpeningPath.addLine(to: CGPoint(x: px, y: py))
                }
            }
            irisOpeningPath.closeSubpath()

            // Fill Iris Blades Outside the Polygon Opening
            var bladeMask = Path(ellipseIn: glassRect)
            bladeMask.addPath(irisOpeningPath)
            irisCtx.fill(bladeMask, with: .color(Color(red: 0.11, green: 0.12, blue: 0.15).opacity(0.94)), style: FillStyle(eoFill: true))
            irisCtx.stroke(irisOpeningPath, with: .color(Color.white.opacity(0.28)), lineWidth: 0.9)

            // Etched Blade Overlap Seam Lines
            for b in 0..<bladeCount {
                let a1 = (Double(b) / Double(bladeCount)) * 2.0 * .pi + Double(irisStopDownProgress) * 0.45
                let a2 = a1 + 0.68
                var seam = Path()
                seam.move(to: CGPoint(x: cx + CGFloat(cos(a1)) * irisOpenR, y: cy + CGFloat(sin(a1)) * irisOpenR))
                seam.addLine(to: CGPoint(x: cx + CGFloat(cos(a2)) * glassR, y: cy + CGFloat(sin(a2)) * glassR))
                irisCtx.stroke(seam, with: .color(Color.black.opacity(0.70)), lineWidth: 0.8)
            }

            // 8. Brand-Authentic Thin-Film Multi-Coating Reflections (Upper-Left & Lower-Right Crescents)
            let colors = coatingColors
            let upperGlowCenter = CGPoint(x: cx - glassR * 0.32, y: cy - glassR * 0.32)
            let lowerGlowCenter = CGPoint(x: cx + glassR * 0.34, y: cy + glassR * 0.34)

            irisCtx.fill(
                Path(ellipseIn: glassRect),
                with: .radialGradient(
                    Gradient(colors: [
                        colors.primary.opacity(0.46),
                        colors.primary.opacity(0.12),
                        Color.clear
                    ]),
                    center: upperGlowCenter,
                    startRadius: 1,
                    endRadius: glassR * 0.85
                )
            )

            irisCtx.fill(
                Path(ellipseIn: glassRect),
                with: .radialGradient(
                    Gradient(colors: [
                        colors.secondary.opacity(0.42),
                        colors.secondary.opacity(0.10),
                        Color.clear
                    ]),
                    center: lowerGlowCenter,
                    startRadius: 1,
                    endRadius: glassR * 0.78
                )
            )

            // Crisp Specular Glass Caustic Highlight Arc
            var causticArc = Path()
            causticArc.addArc(
                center: CGPoint(x: cx, y: cy),
                radius: glassR * 0.74,
                startAngle: .degrees(205),
                endAngle: .degrees(250),
                clockwise: false
            )
            irisCtx.stroke(causticArc, with: .color(Color.white.opacity(0.55)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

            // Stage 3 Test-Fire Dichroic Flare Ring Ripple
            if coatingFlareProgress > 0.01 {
                let flareR = glassR * (0.25 + 0.75 * coatingFlareProgress)
                let flareAlpha = Double(1.0 - coatingFlareProgress)
                let flareRect = CGRect(x: cx - flareR, y: cy - flareR, width: flareR * 2, height: flareR * 2)
                irisCtx.stroke(
                    Path(ellipseIn: flareRect),
                    with: .color(colors.primary.opacity(0.85 * flareAlpha)),
                    lineWidth: 2.8
                )
            }

            // Outer Glass Retaining Ring Bezel
            ctx.stroke(Path(ellipseIn: glassRect), with: .color(Color.white.opacity(0.25)), lineWidth: 1.1)

            // 9. Lens Red Alignment Dot at 12 O'Clock (Rotates into alignment with Camera Red Dot)
            let lensDotR: CGFloat = 2.6
            let lensDotCenter = CGPoint(x: cx, y: cy - barrelR + 4.5)
            ctx.fill(
                Path(ellipseIn: CGRect(x: lensDotCenter.x - lensDotR, y: lensDotCenter.y - lensDotR, width: lensDotR * 2, height: lensDotR * 2)),
                with: .color(Color(red: 0.90, green: 0.0, blue: 0.07))
            )
        }
        .allowsHitTesting(false)
    }
}

