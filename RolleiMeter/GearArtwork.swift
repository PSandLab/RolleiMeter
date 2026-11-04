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
