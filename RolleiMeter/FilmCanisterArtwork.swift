import SwiftUI

// MARK: - 35mm Film Canister Vector Artwork (With Spinning Spindle & Tension Physics)

struct FilmCanisterArtwork: View {
    var filmName: String = ""
    var brand: String = ""
    var familyName: String = ""
    var category: String = "Color"
    var iso: Int = 400
    var showLeader: Bool = true
    var leaderExtension: CGFloat = 1.0
    var spoolRotation: Double = 0.0
    var tension: CGFloat = 0.0
    var yearsExpired: Int = 0
    var width: CGFloat = 46
    var height: CGFloat = 42

    var body: some View {
        let effectiveFilm = (!filmName.isEmpty ? filmName : "\(brand) \(familyName)").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let b = (!brand.isEmpty ? brand : effectiveFilm).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let f = (!familyName.isEmpty ? familyName : effectiveFilm).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cat = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let ext = showLeader ? min(max(leaderExtension, 0.0), 1.0) : 0.0
            let clampedTension = min(max(tension, 0.0), 1.0)

            // 1. Curved 35mm film leader strip + white sprocket holes (when static leader is shown)
            if ext > 0.02 {
                let leaderColor: Color = {
                    if cat == "b&w" { return Color(red: 0.294, green: 0.333, blue: 0.388) }
                    if cat == "slide" { return Color(red: 0.192, green: 0.180, blue: 0.506) }
                    return Color(red: 0.553, green: 0.306, blue: 0.165)
                }()

                let baseX = w * 0.54
                let scaleX: (CGFloat) -> CGFloat = { x in
                    baseX + (x - baseX) * ext
                }

                var leaderPath = Path()
                leaderPath.move(to: CGPoint(x: baseX, y: h * 0.23))
                leaderPath.addLine(to: CGPoint(x: scaleX(w * 0.96), y: h * 0.23))
                leaderPath.addQuadCurve(
                    to: CGPoint(x: scaleX(w * 0.85), y: h * 0.54),
                    control: CGPoint(x: scaleX(w * 1.0), y: h * 0.42)
                )
                leaderPath.addQuadCurve(
                    to: CGPoint(x: scaleX(w * 0.94), y: h * 0.79),
                    control: CGPoint(x: scaleX(w * 0.75), y: h * 0.63)
                )
                leaderPath.addLine(to: CGPoint(x: baseX, y: h * 0.79))
                leaderPath.closeSubpath()
                ctx.fill(leaderPath, with: .color(leaderColor))

                let maxTip = scaleX(w * 0.92)
                for k in 0...2 {
                    let hx = baseX + (w * (0.07 + CGFloat(k) * 0.10)) * ext
                    let holeW = w * 0.055 * ext
                    if hx + holeW < maxTip {
                        ctx.fill(
                            Path(CGRect(x: hx, y: h * 0.265, width: holeW, height: h * 0.065)),
                            with: .color(.white.opacity(0.82))
                        )
                        ctx.fill(
                            Path(CGRect(x: hx, y: h * 0.695, width: holeW, height: h * 0.065)),
                            with: .color(.white.opacity(0.82))
                        )
                    }
                }
            }

            // 2. Top silver spool spindle with rotating drive flutes & top gear teeth
            let cylLeft = w * (showLeader ? 0.05 : 0.14)
            let cylTop = h * 0.15
            let cylW = w * (showLeader ? 0.52 : 0.72)
            let cylH = h * 0.77

            let spoolW = cylW * 0.48
            let spoolLeft = cylLeft + (cylW - spoolW) * 0.5
            let spoolTop = h * 0.02
            let spoolH = h * 0.14
            let spoolRect = CGRect(x: spoolLeft, y: spoolTop, width: spoolW, height: spoolH)
            let spoolPath = Path(roundedRect: spoolRect, cornerRadius: w * 0.04)

            ctx.fill(spoolPath, with: .color(Color(red: 0.52, green: 0.58, blue: 0.66)))

            var spoolCtx = ctx
            spoolCtx.clip(to: spoolPath)

            // Revolving vertical drive flutes & specular highlight driven by spoolRotation
            let fluteCount = 6
            let radPhase = spoolRotation * .pi / 180.0
            for idx in 0..<fluteCount {
                let angle = radPhase + Double(idx) * (2.0 * .pi / Double(fluteCount))
                let sinA = sin(angle)
                let cosA = cos(angle)
                guard cosA > -0.2 else { continue }
                let fx = spoolLeft + spoolW * 0.5 + CGFloat(sinA) * (spoolW * 0.46)
                let fluteW = max(1.0, spoolW * 0.13 * CGFloat(max(0.2, cosA)))
                let fluteRect = CGRect(x: fx - fluteW * 0.5, y: spoolTop + spoolH * 0.12, width: fluteW, height: spoolH * 0.78)
                let isHighlight = idx % 2 == 0
                spoolCtx.fill(
                    Path(fluteRect),
                    with: .color(
                        isHighlight
                            ? Color.white.opacity(0.45 * Double(max(0, cosA)))
                            : Color(red: 0.18, green: 0.22, blue: 0.28).opacity(0.65 * Double(max(0, cosA)))
                    )
                )
            }

            // Top spindle collar ring
            let collarRect = CGRect(x: spoolLeft - w * 0.015, y: spoolTop, width: spoolW + w * 0.03, height: spoolH * 0.26)
            ctx.fill(
                Path(roundedRect: collarRect, cornerRadius: w * 0.02),
                with: .color(Color(red: 0.76, green: 0.81, blue: 0.87))
            )

            // 3. Velvet Light-Trap Lip on the right side of the canister
            let lipW = w * 0.075
            let lipRect = CGRect(
                x: cylLeft + cylW - lipW * 0.35 + clampedTension * w * 0.015,
                y: cylTop + cylH * 0.08,
                width: lipW,
                height: cylH * 0.84
            )
            ctx.fill(
                Path(roundedRect: lipRect, cornerRadius: w * 0.02),
                with: .color(Color(red: 0.08, green: 0.09, blue: 0.11))
            )
            if clampedTension > 0.02 {
                ctx.stroke(
                    Path(roundedRect: lipRect, cornerRadius: w * 0.02),
                    with: .color(Palette.accent.opacity(Double(clampedTension) * 0.65)),
                    lineWidth: 1.0
                )
            }

            // 4. Cylindrical canister body
            let cylRect = CGRect(x: cylLeft, y: cylTop, width: cylW, height: cylH)
            let cylRRect = Path(roundedRect: cylRect, cornerRadius: w * 0.06)

            if b.contains("ilford") || f.contains("ilford") || f.contains("hp5") || f.contains("fp4") || f.contains("pan f") || f.contains("delta") || f.contains("xp2") {
                let isDelta = f.contains("delta")
                let upperBg = isDelta ? Color(red: 0.847, green: 0.871, blue: 0.914) : Color(red: 0.973, green: 0.980, blue: 0.988)
                let ilfordBandColor: Color = {
                    if f.contains("hp5") { return Color(red: 0.000, green: 0.529, blue: 0.318) }
                    if f.contains("fp4") { return Color(red: 0.000, green: 0.447, blue: 0.808) }
                    if f.contains("pan f") { return Color(red: 0.961, green: 0.620, blue: 0.043) }
                    if isDelta { return Color(red: 0.902, green: 0.290, blue: 0.098) }
                    if f.contains("xp2") { return Color(red: 0.416, green: 0.106, blue: 0.604) }
                    if f.contains("sfx") { return Color(red: 0.678, green: 0.078, blue: 0.341) }
                    return Color(red: 0.000, green: 0.529, blue: 0.318)
                }()

                ctx.fill(cylRRect, with: .color(upperBg))
                var bodyCtx = ctx
                bodyCtx.clip(to: cylRRect)

                let boxRect = CGRect(x: cylLeft + cylW * 0.12, y: cylTop + cylH * 0.13, width: cylW * 0.76, height: cylH * 0.24)
                bodyCtx.stroke(Path(boxRect), with: .color(Color(red: 0.078, green: 0.090, blue: 0.110)), lineWidth: w * 0.032)
                bodyCtx.fill(
                    Path(CGRect(x: cylLeft + cylW * 0.20, y: cylTop + cylH * 0.21, width: cylW * 0.60, height: cylH * 0.08)),
                    with: .color(Color(red: 0.078, green: 0.090, blue: 0.110))
                )
                bodyCtx.fill(
                    Path(CGRect(x: cylLeft, y: cylTop + cylH * 0.44, width: cylW, height: cylH * 0.27)),
                    with: .color(ilfordBandColor)
                )
                bodyCtx.fill(
                    Path(CGRect(x: cylLeft + cylW * 0.14, y: cylTop + cylH * 0.53, width: cylW * 0.46, height: cylH * 0.08)),
                    with: .color(.white.opacity(0.85))
                )
            } else if b.contains("fujifilm") || f.contains("fuji") || f.contains("velvia") || f.contains("provia") || f.contains("acros") || f.contains("superia") {
                let isSlide = f.contains("velvia") || f.contains("provia")
                let isAcros = f.contains("acros")
                let baseColor: Color = isSlide ? Color(red: 0.102, green: 0.118, blue: 0.141) : (isAcros ? Color(red: 0.855, green: 0.875, blue: 0.902) : Color(red: 0.000, green: 0.608, blue: 0.302))

                ctx.fill(cylRRect, with: .color(baseColor))
                var bodyCtx = ctx
                bodyCtx.clip(to: cylRRect)

                if isSlide {
                    bodyCtx.fill(
                        Path(CGRect(x: cylLeft, y: cylTop + cylH * 0.12, width: cylW, height: cylH * 0.18)),
                        with: .color(Color(red: 0.831, green: 0.686, blue: 0.216))
                    )
                    var slideSlash = Path()
                    slideSlash.move(to: CGPoint(x: cylLeft, y: cylTop + cylH * 0.56))
                    slideSlash.addLine(to: CGPoint(x: cylLeft + cylW, y: cylTop + cylH * 0.34))
                    slideSlash.addLine(to: CGPoint(x: cylLeft + cylW, y: cylTop + cylH * 0.54))
                    slideSlash.addLine(to: CGPoint(x: cylLeft, y: cylTop + cylH * 0.74))
                    slideSlash.closeSubpath()
                    bodyCtx.fill(slideSlash, with: .color(Color(red: 0.761, green: 0.094, blue: 0.357)))
                    bodyCtx.fill(
                        Path(CGRect(x: cylLeft, y: cylTop + cylH * 0.30, width: cylW * 0.55, height: cylH * 0.09)),
                        with: .color(Color(red: 0.000, green: 0.659, blue: 0.349))
                    )
                } else if isAcros {
                    bodyCtx.fill(
                        Path(CGRect(x: cylLeft, y: cylTop + cylH * 0.28, width: cylW, height: cylH * 0.38)),
                        with: .color(Color(red: 0.118, green: 0.161, blue: 0.231))
                    )
                    var acrosCorner = Path()
                    acrosCorner.move(to: CGPoint(x: cylLeft + cylW * 0.45, y: cylTop))
                    acrosCorner.addLine(to: CGPoint(x: cylLeft + cylW, y: cylTop))
                    acrosCorner.addLine(to: CGPoint(x: cylLeft + cylW, y: cylTop + cylH * 0.32))
                    acrosCorner.closeSubpath()
                    bodyCtx.fill(acrosCorner, with: .color(Color(red: 0.000, green: 0.608, blue: 0.302)))
                    bodyCtx.fill(
                        Path(CGRect(x: cylLeft + cylW * 0.12, y: cylTop + cylH * 0.41, width: cylW * 0.76, height: cylH * 0.10)),
                        with: .color(.white)
                    )
                } else {
                    var redCorner = Path()
                    redCorner.move(to: CGPoint(x: cylLeft + cylW * 0.48, y: cylTop))
                    redCorner.addLine(to: CGPoint(x: cylLeft + cylW, y: cylTop))
                    redCorner.addLine(to: CGPoint(x: cylLeft + cylW, y: cylTop + cylH * 0.36))
                    redCorner.closeSubpath()
                    bodyCtx.fill(redCorner, with: .color(Color(red: 0.902, green: 0.000, blue: 0.071)))

                    var whiteRibbon = Path()
                    whiteRibbon.move(to: CGPoint(x: cylLeft, y: cylTop + cylH * 0.52))
                    whiteRibbon.addLine(to: CGPoint(x: cylLeft + cylW, y: cylTop + cylH * 0.28))
                    whiteRibbon.addLine(to: CGPoint(x: cylLeft + cylW, y: cylTop + cylH * 0.46))
                    whiteRibbon.addLine(to: CGPoint(x: cylLeft, y: cylTop + cylH * 0.70))
                    whiteRibbon.closeSubpath()
                    bodyCtx.fill(whiteRibbon, with: .color(.white))

                    var redRibbon = Path()
                    redRibbon.move(to: CGPoint(x: cylLeft, y: cylTop + cylH * 0.64))
                    redRibbon.addLine(to: CGPoint(x: cylLeft + cylW, y: cylTop + cylH * 0.42))
                    redRibbon.addLine(to: CGPoint(x: cylLeft + cylW, y: cylTop + cylH * 0.52))
                    redRibbon.addLine(to: CGPoint(x: cylLeft, y: cylTop + cylH * 0.74))
                    redRibbon.closeSubpath()
                    bodyCtx.fill(redRibbon, with: .color(Color(red: 0.902, green: 0.000, blue: 0.071)))
                }
            } else if b.contains("cinestill") || f.contains("cinestill") || f.contains("800t") || f.contains("400d") || f.contains("50d") || f.contains("bwxx") {
                let is800T = f.contains("800t")
                let is400D = f.contains("400d")
                let is50D = f.contains("50d")

                let csBase: Color = is800T ? Color(red: 0.071, green: 0.082, blue: 0.118) : (is400D ? Color(red: 0.953, green: 0.898, blue: 0.784) : (is50D ? Color(red: 0.008, green: 0.533, blue: 0.820) : Color(red: 0.102, green: 0.114, blue: 0.141)))
                let csStripe: Color = is800T ? Color(red: 1.000, green: 0.231, blue: 0.188) : (is400D ? Color(red: 0.082, green: 0.396, blue: 0.753) : (is50D ? Color(red: 1.000, green: 0.835, blue: 0.310) : Color(red: 0.831, green: 0.686, blue: 0.216)))
                let csAccent: Color = is800T ? Color(red: 0.000, green: 0.898, blue: 1.000) : (is400D ? Color(red: 1.000, green: 0.427, blue: 0.000) : (is50D ? Color(red: 0.898, green: 0.224, blue: 0.208) : Color(red: 0.812, green: 0.847, blue: 0.863)))

                ctx.fill(cylRRect, with: .color(csBase))
                var bodyCtx = ctx
                bodyCtx.clip(to: cylRRect)

                bodyCtx.fill(
                    Path(CGRect(x: cylLeft, y: cylTop + cylH * 0.28, width: cylW, height: cylH * 0.36)),
                    with: .color(csStripe)
                )
                bodyCtx.fill(
                    Path(CGRect(x: cylLeft, y: cylTop + cylH * 0.64, width: cylW, height: cylH * 0.09)),
                    with: .color(csAccent)
                )
                let ringR = cylW * 0.25
                let ringCenter = CGPoint(x: cylLeft + cylW * 0.5, y: cylTop + cylH * 0.46)
                bodyCtx.stroke(
                    Path(ellipseIn: CGRect(x: ringCenter.x - ringR, y: ringCenter.y - ringR, width: ringR * 2, height: ringR * 2)),
                    with: .color(Color(red: 1.000, green: 0.839, blue: 0.000)),
                    lineWidth: w * 0.045
                )
            } else if b.contains("kodak") || f.contains("kodak") || f.contains("portra") || f.contains("ektar") || f.contains("ektachrome") || f.contains("vision3") || f.contains("t-max") || f.contains("tri-x") || f.contains("gold") || f.contains("ultramax") || f.contains("pro image") || f.contains("colorplus") {
                let isPortra = f.contains("portra")
                let isEktar = f.contains("ektar")
                let isEktachrome = f.contains("ektachrome")
                let isVision3 = f.contains("vision3")
                let isTMax = f.contains("t-max")
                let isTriX = f.contains("tri-x")
                let isProImage = f.contains("pro image") || f.contains("proimage")

                let bodyBg: Color = {
                    if isPortra { return Color(red: 0.953, green: 0.702, blue: 0.165) }
                    if isEktar { return Color(red: 0.086, green: 0.094, blue: 0.114) }
                    if isEktachrome { return Color(red: 0.078, green: 0.184, blue: 0.478) }
                    if isVision3 { return Color(red: 0.157, green: 0.173, blue: 0.204) }
                    if isTMax { return Color(red: 0.812, green: 0.847, blue: 0.863) }
                    if isProImage { return Color(red: 0.973, green: 0.980, blue: 0.988) }
                    return Color(red: 1.000, green: 0.780, blue: 0.000)
                }()
                let bandColor: Color = {
                    if isPortra { return Color(red: 0.545, green: 0.118, blue: 0.255) }
                    if isEktar { return Color(red: 0.851, green: 0.118, blue: 0.165) }
                    if isEktachrome { return Color(red: 1.000, green: 0.722, blue: 0.000) }
                    if isVision3 { return Color(red: 0.961, green: 0.620, blue: 0.043) }
                    if isTMax { return Color(red: 0.086, green: 0.094, blue: 0.114) }
                    if isTriX { return Color(red: 0.078, green: 0.086, blue: 0.098) }
                    if isProImage { return Color(red: 1.000, green: 0.780, blue: 0.000) }
                    return Color(red: 0.106, green: 0.310, blue: 0.612)
                }()
                let pinColor: Color = {
                    if isPortra { return Color(red: 1.000, green: 0.953, blue: 0.820) }
                    if isEktar { return Color(red: 1.000, green: 0.780, blue: 0.000) }
                    if isEktachrome { return Color(red: 0.000, green: 0.706, blue: 0.847) }
                    if isTMax { return Color(red: 1.000, green: 0.780, blue: 0.000) }
                    return Color(red: 0.890, green: 0.094, blue: 0.216)
                }()

                ctx.fill(cylRRect, with: .color(bodyBg))
                var bodyCtx = ctx
                bodyCtx.clip(to: cylRRect)

                var kodakCorner = Path()
                kodakCorner.move(to: CGPoint(x: cylLeft + cylW * 0.45, y: cylTop))
                kodakCorner.addLine(to: CGPoint(x: cylLeft + cylW, y: cylTop))
                kodakCorner.addLine(to: CGPoint(x: cylLeft + cylW, y: cylTop + cylH * 0.28))
                kodakCorner.closeSubpath()
                bodyCtx.fill(
                    kodakCorner,
                    with: .color((isEktar || isEktachrome || isVision3) ? Color(red: 1.000, green: 0.780, blue: 0.000) : Color(red: 0.890, green: 0.094, blue: 0.216))
                )
                bodyCtx.fill(
                    Path(CGRect(x: cylLeft, y: cylTop + cylH * 0.30, width: cylW, height: cylH * 0.33)),
                    with: .color(bandColor)
                )
                bodyCtx.fill(
                    Path(CGRect(x: cylLeft, y: cylTop + cylH * 0.63, width: cylW, height: cylH * 0.08)),
                    with: .color(pinColor)
                )
            } else if f.contains("phoenix") {
                ctx.fill(cylRRect, with: .color(Color(red: 1.000, green: 0.341, blue: 0.133)))
                var bodyCtx = ctx
                bodyCtx.clip(to: cylRRect)
                bodyCtx.fill(
                    Path(CGRect(x: cylLeft, y: cylTop + cylH * 0.32, width: cylW, height: cylH * 0.34)),
                    with: .color(Color(red: 0.718, green: 0.110, blue: 0.110))
                )
                let sunR = cylW * 0.22
                let sunC = CGPoint(x: cylLeft + cylW * 0.5, y: cylTop + cylH * 0.48)
                bodyCtx.fill(
                    Path(ellipseIn: CGRect(x: sunC.x - sunR, y: sunC.y - sunR, width: sunR * 2, height: sunR * 2)),
                    with: .color(Color(red: 1.000, green: 0.918, blue: 0.000))
                )
            } else if f.contains("kentmere") {
                ctx.fill(cylRRect, with: .color(Color(red: 0.973, green: 0.980, blue: 0.988)))
                var bodyCtx = ctx
                bodyCtx.clip(to: cylRRect)
                var navyDiag = Path()
                navyDiag.move(to: CGPoint(x: cylLeft, y: cylTop + cylH * 0.30))
                navyDiag.addLine(to: CGPoint(x: cylLeft + cylW, y: cylTop + cylH * 0.14))
                navyDiag.addLine(to: CGPoint(x: cylLeft + cylW, y: cylTop + cylH * 0.68))
                navyDiag.addLine(to: CGPoint(x: cylLeft, y: cylTop + cylH * 0.68))
                navyDiag.closeSubpath()
                bodyCtx.fill(navyDiag, with: .color(Color(red: 0.118, green: 0.227, blue: 0.541)))
                bodyCtx.fill(
                    Path(CGRect(x: cylLeft, y: cylTop + cylH * 0.64, width: cylW, height: cylH * 0.09)),
                    with: .color(Color(red: 0.863, green: 0.149, blue: 0.149))
                )
            } else if f.contains("fomapan") || f.contains("foma") {
                ctx.fill(cylRRect, with: .color(Color(red: 0.953, green: 0.957, blue: 0.965)))
                var bodyCtx = ctx
                bodyCtx.clip(to: cylRRect)
                bodyCtx.fill(
                    Path(CGRect(x: cylLeft, y: cylTop + cylH * 0.10, width: cylW, height: cylH * 0.26)),
                    with: .color(Color(red: 0.094, green: 0.102, blue: 0.118))
                )
                bodyCtx.fill(
                    Path(CGRect(x: cylLeft, y: cylTop + cylH * 0.38, width: cylW, height: cylH * 0.28)),
                    with: .color(Color(red: 0.000, green: 0.514, blue: 0.561))
                )
            } else if f.contains("rollei") {
                ctx.fill(cylRRect, with: .color(Color(red: 0.110, green: 0.122, blue: 0.149)))
                var bodyCtx = ctx
                bodyCtx.clip(to: cylRRect)
                bodyCtx.fill(
                    Path(CGRect(x: cylLeft, y: cylTop + cylH * 0.24, width: cylW, height: cylH * 0.26)),
                    with: .color(Color(red: 0.855, green: 0.875, blue: 0.902))
                )
                bodyCtx.fill(
                    Path(CGRect(x: cylLeft, y: cylTop + cylH * 0.50, width: cylW, height: cylH * 0.12)),
                    with: .color(Color(red: 0.776, green: 0.157, blue: 0.157))
                )
                bodyCtx.fill(
                    Path(CGRect(x: cylLeft, y: cylTop + cylH * 0.62, width: cylW, height: cylH * 0.08)),
                    with: .color(Color(red: 0.984, green: 0.753, blue: 0.176))
                )
            } else if f.contains("lomography") || f.contains("lomo") {
                ctx.fill(cylRRect, with: .color(Color(red: 0.416, green: 0.106, blue: 0.604)))
                var bodyCtx = ctx
                bodyCtx.clip(to: cylRRect)
                bodyCtx.fill(
                    Path(CGRect(x: cylLeft, y: cylTop + cylH * 0.28, width: cylW, height: cylH * 0.22)),
                    with: .color(Color(red: 0.000, green: 0.675, blue: 0.757))
                )
                bodyCtx.fill(
                    Path(CGRect(x: cylLeft, y: cylTop + cylH * 0.50, width: cylW, height: cylH * 0.20)),
                    with: .color(Color(red: 0.992, green: 0.847, blue: 0.208))
                )
            } else {
                ctx.fill(cylRRect, with: .color(Color(red: 0.200, green: 0.255, blue: 0.333)))
                var bodyCtx = ctx
                bodyCtx.clip(to: cylRRect)
                bodyCtx.fill(
                    Path(CGRect(x: cylLeft, y: cylTop + cylH * 0.30, width: cylW, height: cylH * 0.32)),
                    with: .color(Color(red: 0.612, green: 0.792, blue: 1.000))
                )
                bodyCtx.fill(
                    Path(CGRect(x: cylLeft, y: cylTop + cylH * 0.62, width: cylW, height: cylH * 0.09)),
                    with: .color(Color(red: 0.878, green: 0.663, blue: 0.306))
                )
            }

            // 5. Conductive DX foil squares + dynamic metallic sheen
            let dxW = cylW * 0.19
            let dxH = cylH * 0.13
            let dxTop = cylTop + cylH * 0.76
            ctx.fill(Path(CGRect(x: cylLeft + cylW * 0.12, y: dxTop, width: dxW, height: dxH)), with: .color(Color(red: 0.886, green: 0.910, blue: 0.941)))
            ctx.fill(Path(CGRect(x: cylLeft + cylW * 0.31, y: dxTop, width: dxW, height: dxH)), with: .color(Color(red: 0.078, green: 0.090, blue: 0.110)))
            ctx.fill(Path(CGRect(x: cylLeft + cylW * 0.50, y: dxTop, width: dxW, height: dxH)), with: .color(Color(red: 0.886, green: 0.910, blue: 0.941)))

            let dxBlockLeft = cylLeft + cylW * 0.12
            let dxBlockW = cylW * 0.57
            ctx.fill(
                Path(CGRect(x: dxBlockLeft, y: dxTop, width: dxBlockW, height: dxH)),
                with: .linearGradient(
                    Gradient(colors: [.clear, .white.opacity(0.42 + Double(clampedTension) * 0.25), .clear]),
                    startPoint: CGPoint(x: dxBlockLeft, y: dxTop + dxH),
                    endPoint: CGPoint(x: dxBlockLeft + dxBlockW, y: dxTop)
                )
            )

            // 6. Crimped top and bottom end caps
            let capH = h * 0.08
            let topCapRect = CGRect(x: cylLeft - w * 0.02, y: cylTop, width: cylW + w * 0.04, height: capH)
            let botCapRect = CGRect(x: cylLeft - w * 0.02, y: cylTop + cylH - capH, width: cylW + w * 0.04, height: capH)
            ctx.fill(Path(roundedRect: topCapRect, cornerRadius: w * 0.04), with: .color(Color(red: 0.118, green: 0.161, blue: 0.231)))
            ctx.fill(Path(roundedRect: botCapRect, cornerRadius: w * 0.04), with: .color(Color(red: 0.118, green: 0.161, blue: 0.231)))

            // Procedural Expired Weathering (Brassing Scratches & Patina on Crimped Steel Rims)
            let bodyRect = cylRect
            if yearsExpired >= 10 {
                let weatherIntensity = min(Double(yearsExpired) / 40.0, 1.0)
                let scratchCount = min(yearsExpired / 5, 8)
                for s in 0..<scratchCount {
                    let normX = CGFloat((s * 37 + 13) % 100) / 100.0
                    let sx = bodyRect.minX + 4.0 + normX * (bodyRect.width - 8.0)
                    let topScratch = CGRect(x: sx, y: topCapRect.minY + 1.0, width: 2.4, height: 1.2)
                    let botScratch = CGRect(x: sx, y: botCapRect.maxY - 2.2, width: 2.8, height: 1.2)
                    ctx.fill(Path(topScratch), with: .color(Color(red: 0.85, green: 0.68, blue: 0.34).opacity(0.55 * weatherIntensity)))
                    ctx.fill(Path(botScratch), with: .color(Color(red: 0.85, green: 0.68, blue: 0.34).opacity(0.55 * weatherIntensity)))
                }

                // Warm Vintage Yellow Patina Wash over Canister Body
                ctx.fill(
                    Path(roundedRect: bodyRect, cornerRadius: w * 0.06),
                    with: .color(Color(red: 0.62, green: 0.48, blue: 0.22).opacity(0.14 * weatherIntensity))
                )
            }

            // 7. 3D cylindrical horizontal shading (shifts specular highlight slightly with spoolRotation)
            let specShift = CGFloat(sin(radPhase) * 0.04)
            ctx.fill(
                cylRRect,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .white.opacity(0.22 + Double(clampedTension) * 0.08), location: min(max(0.22 + specShift, 0.12), 0.35)),
                        .init(color: .clear, location: 0.52),
                        .init(color: .black.opacity(0.30), location: 0.92),
                        .init(color: .clear, location: 1.0)
                    ]),
                    startPoint: CGPoint(x: cylLeft, y: 0),
                    endPoint: CGPoint(x: cylLeft + cylW, y: 0)
                )
            )

            // 8. Specular metal rim on each end cap
            let rimShading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [.clear, .white.opacity(0.55), .clear]),
                startPoint: CGPoint(x: cylLeft, y: 0),
                endPoint: CGPoint(x: cylLeft + cylW, y: 0)
            )
            let topRim = CGRect(x: cylLeft - w * 0.02, y: cylTop + capH * 0.16, width: cylW + w * 0.04, height: h * 0.014)
            let botRim = CGRect(x: cylLeft - w * 0.02, y: cylTop + cylH - capH * 0.30, width: cylW + w * 0.04, height: h * 0.014)
            ctx.fill(Path(roundedRect: topRim, cornerRadius: w * 0.02), with: rimShading)
            ctx.fill(Path(roundedRect: botRim, cornerRadius: w * 0.02), with: rimShading)
        }
        .frame(width: width, height: height)
    }
}
