import SwiftUI

struct FilmBrandTheme {
    let primary: Color
    let secondary: Color
    let badgeText: Color
    let tag: String
    let subtitle: String
}

func brandThemeFor(_ brand: String) -> FilmBrandTheme {
    let b = brand.lowercased()
    if b.contains("kodak") {
        return FilmBrandTheme(
            primary: Color(hex: 0xFFB800),
            secondary: Color(hex: 0xE31B23),
            badgeText: Color(hex: 0x1A1100),
            tag: "KODAK",
            subtitle: "ROCHESTER · PROFESSIONAL & CONSUMER"
        )
    } else if b.contains("fuji") {
        return FilmBrandTheme(
            primary: Color(hex: 0x009B62),
            secondary: Color(hex: 0xE60039),
            badgeText: .white,
            tag: "FUJIFILM",
            subtitle: "TOKYO · SUPERIA · VELVIA · ACROS"
        )
    } else if b.contains("ilford") {
        return FilmBrandTheme(
            primary: Color(hex: 0xE2E8F0),
            secondary: Color(hex: 0xF97316),
            badgeText: Color(hex: 0x0F172A),
            tag: "ILFORD",
            subtitle: "MOBBERLEY · BLACK & WHITE"
        )
    } else if b.contains("cinestill") {
        return FilmBrandTheme(
            primary: Color(hex: 0xEF4444),
            secondary: Color(hex: 0x06B6D4),
            badgeText: .white,
            tag: "CINESTILL",
            subtitle: "MOTION PICTURE · TUNGSTEN & DAYLIGHT"
        )
    } else {
        return FilmBrandTheme(
            primary: Color(hex: 0xA855F7),
            secondary: Color(hex: 0xF59E0B),
            badgeText: .white,
            tag: "BOUTIQUE & CLASSIC",
            subtitle: "FOMA · KENTMERE · ROLLEI · LOMO · HARMAN"
        )
    }
}

// MARK: - Brand Header Banner

struct BrandHeaderBanner: View {
    let brand: String
    let stockCount: Int

    var body: some View {
        let theme = brandThemeFor(brand)
        ZStack {
            Canvas { ctx, size in
                let w = size.width
                let h = size.height
                ctx.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        Gradient(colors: [
                            theme.primary.opacity(0.28),
                            theme.secondary.opacity(0.16),
                            Color(hex: 0x161618)
                        ]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: w, y: h)
                    )
                )

                var stripe1 = Path()
                stripe1.move(to: CGPoint(x: w * 0.66, y: 0))
                stripe1.addLine(to: CGPoint(x: w * 0.76, y: 0))
                stripe1.addLine(to: CGPoint(x: w * 0.64, y: h))
                stripe1.addLine(to: CGPoint(x: w * 0.54, y: h))
                stripe1.closeSubpath()
                ctx.fill(stripe1, with: .color(theme.primary.opacity(0.20)))

                var stripe2 = Path()
                stripe2.move(to: CGPoint(x: w * 0.78, y: 0))
                stripe2.addLine(to: CGPoint(x: w * 0.85, y: 0))
                stripe2.addLine(to: CGPoint(x: w * 0.73, y: h))
                stripe2.addLine(to: CGPoint(x: w * 0.66, y: h))
                stripe2.closeSubpath()
                ctx.fill(stripe2, with: .color(theme.secondary.opacity(0.22)))

                // 35mm sprocket holes along top edge
                let holeW: CGFloat = 6
                let holeH: CGFloat = 3.5
                let step: CGFloat = 13
                var x: CGFloat = 12
                while x < w - 12 {
                    let r = CGRect(x: x, y: 3.5, width: holeW, height: holeH)
                    ctx.fill(Path(roundedRect: r, cornerRadius: 1), with: .color(.white.opacity(0.12)))
                    x += step
                }
            }

            HStack(spacing: 10) {
                Text(theme.tag)
                    .font(AppTypography.mono(11, weight: .black))
                    .foregroundStyle(theme.badgeText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(theme.primary, in: Capsule())

                Text(theme.subtitle)
                    .font(AppTypography.label(10, weight: .semibold))
                    .foregroundStyle(Palette.textSub)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(stockCount)")
                    .font(AppTypography.mono(11, weight: .bold))
                    .foregroundStyle(Palette.text)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.10), in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.top, 5)
        }
        .frame(height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75)
        )
    }
}

// MARK: - 35mm Film Canister Procedural Artwork

struct FilmCanisterArtwork: View {
    let brand: String
    let familyName: String
    let category: String
    let iso: Int
    var showLeader: Bool = false
    var width: CGFloat = 46
    var height: CGFloat = 58

    var body: some View {
        let b = brand.lowercased()
        let f = familyName.lowercased()

        let palette: (body: Color, stripe1: Color, stripe2: Color, badgeText: Color) = {
            if b.contains("kodak") && f.contains("portra") {
                return (Color(hex: 0xD99B26), Color(hex: 0x8C1D40), Color(hex: 0xFFF3D1), Color(hex: 0x1C1300))
            } else if b.contains("kodak") && (f.contains("gold") || f.contains("ultramax") || f.contains("colorplus")) {
                return (Color(hex: 0xFFB800), Color(hex: 0xE31B23), Color(hex: 0x1E3A8A), Color(hex: 0x1A1000))
            } else if b.contains("kodak") && (f.contains("tri-x") || f.contains("t-max") || f.contains("double")) {
                return (Color(hex: 0xF5B800), Color(hex: 0x18181B), Color(hex: 0xE31B23), Color(hex: 0x111111))
            } else if b.contains("kodak") && f.contains("ektachrome") {
                return (Color(hex: 0x1D4ED8), Color(hex: 0xFFB800), Color(hex: 0xE31B23), .white)
            } else if b.contains("kodak") {
                return (Color(hex: 0xFFB800), Color(hex: 0xE31B23), Color(hex: 0x111111), Color(hex: 0x111111))
            } else if b.contains("fuji") && (f.contains("velvia") || f.contains("provia")) {
                return (Color(hex: 0x1E1B4B), Color(hex: 0x00A86B), Color(hex: 0xD97706), .white)
            } else if b.contains("fuji") && f.contains("acros") {
                return (Color(hex: 0x27272A), Color(hex: 0x00A86B), Color(hex: 0xE4E4E7), .white)
            } else if b.contains("fuji") {
                return (Color(hex: 0x008C5A), Color(hex: 0xE60039), Color(hex: 0xA7F3D0), .white)
            } else if b.contains("ilford") && f.contains("delta") {
                return (Color(hex: 0x18181B), Color(hex: 0x0EA5E9), Color(hex: 0xF4F4F5), .white)
            } else if b.contains("ilford") {
                return (Color(hex: 0xF4F4F5), Color(hex: 0x18181B), Color(hex: 0xEA580C), Color(hex: 0x111111))
            } else if b.contains("cinestill") && f.contains("800") {
                return (Color(hex: 0x111827), Color(hex: 0xEF4444), Color(hex: 0x06B6D4), .white)
            } else if b.contains("cinestill") && f.contains("400") {
                return (Color(hex: 0x18181B), Color(hex: 0xF97316), Color(hex: 0xFACC15), .white)
            } else if b.contains("cinestill") {
                return (Color(hex: 0x18181B), Color(hex: 0xEF4444), Color(hex: 0x38BDF8), .white)
            } else if f.contains("foma") {
                return (Color(hex: 0x1E293B), Color(hex: 0x38BDF8), Color(hex: 0xE2E8F0), .white)
            } else if f.contains("phoenix") {
                return (Color(hex: 0xC2410C), Color(hex: 0xFACC15), Color(hex: 0x7C2D12), .white)
            } else if f.contains("lomo") {
                return (Color(hex: 0x6D28D9), Color(hex: 0xEC4899), Color(hex: 0xFDE047), .white)
            } else {
                return (Color(hex: 0x334155), Color(hex: 0xF59E0B), Color(hex: 0x94A3B8), .white)
            }
        }()

        let brandCode: String = {
            if b.contains("kodak") { return "KODAK" }
            if b.contains("fuji") { return "FUJI" }
            if b.contains("ilford") { return "ILFORD" }
            if b.contains("cinestill") { return "CS" }
            if f.contains("foma") { return "FOMA" }
            if f.contains("kentmere") { return "KENT" }
            if f.contains("phoenix") { return "PHNX" }
            if f.contains("lomo") { return "LOMO" }
            if f.contains("rollei") { return "ROLLEI" }
            return String(brand.prefix(5)).uppercased()
        }()

        ZStack {
            Canvas { ctx, size in
                let w = size.width
                let h = size.height
                let canLeft = w * 0.14
                let canRight = w * (showLeader ? 0.74 : 0.86)
                let canWidth = canRight - canLeft
                let bodyTop = h * 0.17
                let bodyBottom = h * 0.88
                let bodyHeight = bodyBottom - bodyTop

                // 1. Protruding 35mm film leader strip + sprockets
                if showLeader {
                    let leaderTop = bodyTop + bodyHeight * 0.16
                    let leaderH = bodyHeight * 0.68
                    var leader = Path()
                    leader.move(to: CGPoint(x: canRight - 2, y: leaderTop))
                    leader.addLine(to: CGPoint(x: w * 0.96, y: leaderTop + leaderH * 0.08))
                    leader.addLine(to: CGPoint(x: w * 0.99, y: leaderTop + leaderH * 0.42))
                    leader.addLine(to: CGPoint(x: w * 0.91, y: leaderTop + leaderH * 0.92))
                    leader.addLine(to: CGPoint(x: canRight - 2, y: leaderTop + leaderH))
                    leader.closeSubpath()
                    ctx.fill(
                        leader,
                        with: .linearGradient(
                            Gradient(colors: [Color(hex: 0x2B1912), Color(hex: 0x4A2B1D), Color(hex: 0x351E15)]),
                            startPoint: CGPoint(x: canRight, y: 0),
                            endPoint: CGPoint(x: w, y: 0)
                        )
                    )
                    for i in 0..<3 {
                        let hx = canRight + 3 + CGFloat(i) * (w * 0.068)
                        let topHole = CGRect(x: hx, y: leaderTop + 2.5, width: w * 0.042, height: h * 0.04)
                        let botHole = CGRect(x: hx, y: leaderTop + leaderH - h * 0.04 - 2.5, width: w * 0.042, height: h * 0.04)
                        ctx.fill(Path(roundedRect: topHole, cornerRadius: 0.8), with: .color(Color(hex: 0xD4D4D8)))
                        ctx.fill(Path(roundedRect: botHole, cornerRadius: 0.8), with: .color(Color(hex: 0xD4D4D8)))
                    }
                }

                // 2. Velvet light-trap slot
                let lipW = w * 0.055
                let lipRect = CGRect(x: canRight - 1, y: bodyTop + bodyHeight * 0.07, width: lipW, height: bodyHeight * 0.86)
                ctx.fill(Path(roundedRect: lipRect, cornerRadius: 2), with: .color(Color(hex: 0x0A0A0D)))

                // 3. Top spool spindle & metallic end caps
                let spoolW = canWidth * 0.44
                let spoolLeft = canLeft + (canWidth - spoolW) / 2
                let spoolRect = CGRect(x: spoolLeft, y: h * 0.03, width: spoolW, height: h * 0.11)
                ctx.fill(
                    Path(roundedRect: spoolRect, cornerRadius: 2.5),
                    with: .linearGradient(
                        Gradient(colors: [Color(hex: 0x1A1B1E), Color(hex: 0x43464E), Color(hex: 0x18191C)]),
                        startPoint: CGPoint(x: spoolLeft, y: 0),
                        endPoint: CGPoint(x: spoolLeft + spoolW, y: 0)
                    )
                )

                let capLeft = canLeft - w * 0.025
                let capW = canWidth + w * 0.05
                let topCap = CGRect(x: capLeft, y: h * 0.11, width: capW, height: h * 0.065)
                let botCap = CGRect(x: capLeft, y: bodyBottom - 1, width: capW, height: h * 0.065)
                let capGrad = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [Color(hex: 0x1E2024), Color(hex: 0x525761), Color(hex: 0x2A2D34), Color(hex: 0x141518)]),
                    startPoint: CGPoint(x: capLeft, y: 0),
                    endPoint: CGPoint(x: capLeft + capW, y: 0)
                )
                ctx.fill(Path(roundedRect: topCap, cornerRadius: 2), with: capGrad)
                ctx.fill(Path(roundedRect: botCap, cornerRadius: 2), with: capGrad)

                // 4. Cylindrical canister body
                let bodyRect = CGRect(x: canLeft, y: bodyTop, width: canWidth, height: bodyHeight)
                let bodyPath = Path(roundedRect: bodyRect, cornerRadius: 2.5)
                ctx.fill(bodyPath, with: .color(palette.body))

                var bodyCtx = ctx
                bodyCtx.clip(to: bodyPath)

                // Brand stripes
                if b.contains("kodak") {
                    var slash = Path()
                    slash.move(to: CGPoint(x: canLeft, y: bodyTop + bodyHeight * 0.28))
                    slash.addLine(to: CGPoint(x: canRight, y: bodyTop + bodyHeight * 0.10))
                    slash.addLine(to: CGPoint(x: canRight, y: bodyTop + bodyHeight * 0.34))
                    slash.addLine(to: CGPoint(x: canLeft, y: bodyTop + bodyHeight * 0.52))
                    slash.closeSubpath()
                    bodyCtx.fill(slash, with: .color(palette.stripe1))
                    bodyCtx.fill(Path(CGRect(x: canLeft, y: bodyBottom - bodyHeight * 0.24, width: canWidth, height: bodyHeight * 0.24)), with: .color(palette.stripe2))
                } else if b.contains("fuji") {
                    var ribbon = Path()
                    ribbon.move(to: CGPoint(x: canLeft, y: bodyTop + bodyHeight * 0.20))
                    ribbon.addLine(to: CGPoint(x: canRight, y: bodyTop + bodyHeight * 0.36))
                    ribbon.addLine(to: CGPoint(x: canRight, y: bodyTop + bodyHeight * 0.50))
                    ribbon.addLine(to: CGPoint(x: canLeft, y: bodyTop + bodyHeight * 0.34))
                    ribbon.closeSubpath()
                    bodyCtx.fill(ribbon, with: .color(palette.stripe1))
                    bodyCtx.fill(Path(CGRect(x: canLeft, y: bodyBottom - bodyHeight * 0.20, width: canWidth, height: bodyHeight * 0.20)), with: .color(palette.stripe2.opacity(0.85)))
                } else if b.contains("ilford") {
                    bodyCtx.fill(Path(CGRect(x: canLeft, y: bodyTop, width: canWidth, height: bodyHeight * 0.26)), with: .color(palette.stripe1))
                    bodyCtx.fill(Path(CGRect(x: canLeft, y: bodyTop + bodyHeight * 0.26, width: canWidth, height: bodyHeight * 0.10)), with: .color(palette.stripe2))
                } else {
                    bodyCtx.fill(Path(CGRect(x: canLeft, y: bodyTop + bodyHeight * 0.22, width: canWidth, height: bodyHeight * 0.18)), with: .color(palette.stripe1))
                    bodyCtx.fill(Path(CGRect(x: canLeft, y: bodyBottom - bodyHeight * 0.18, width: canWidth, height: bodyHeight * 0.18)), with: .color(palette.stripe2))
                }

                // DX foil patch on left edge
                let dxW = canWidth * 0.18
                let dxH = bodyHeight * 0.42
                let dxTop = bodyTop + bodyHeight * 0.48
                bodyCtx.fill(Path(CGRect(x: canLeft + 1.5, y: dxTop, width: dxW, height: dxH)), with: .color(Color(hex: 0xD4D8E0).opacity(0.88)))
                let cellH = dxH / 4
                for r in 0..<4 {
                    if r % 2 == 1 {
                        bodyCtx.fill(Path(CGRect(x: canLeft + 1.5, y: dxTop + CGFloat(r) * cellH, width: dxW * 0.55, height: cellH)), with: .color(Color(hex: 0x18181B)))
                    }
                }

                // 3D cylindrical specular highlight & shadow
                bodyCtx.fill(
                    Path(bodyRect),
                    with: .linearGradient(
                        Gradient(colors: [
                            .black.opacity(0.38),
                            .white.opacity(0.24),
                            .clear,
                            .black.opacity(0.45)
                        ]),
                        startPoint: CGPoint(x: canLeft, y: 0),
                        endPoint: CGPoint(x: canRight, y: 0)
                    )
                )
            }

            // Text labels (Brand + ISO) centered on canister cylinder
            VStack(spacing: 0) {
                Text(brandCode)
                    .font(AppTypography.mono(6.5, weight: .black))
                    .foregroundStyle(palette.badgeText.opacity(0.92))
                    .lineLimit(1)
                Text("\(iso)")
                    .font(AppTypography.mono(iso >= 1000 ? 9.5 : 11, weight: .black))
                    .foregroundStyle(palette.badgeText)
                    .lineLimit(1)
            }
            .offset(x: showLeader ? -width * 0.06 : 0, y: height * 0.03)
        }
        .frame(width: width, height: height)
    }
}
