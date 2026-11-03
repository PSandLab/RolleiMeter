import SwiftUI

// MARK: - Brand Tone Colors

func resolveBrandToneColor(_ brand: String) -> Color {
    switch brand.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "Leica": return Color(hex: 0xDC2626)
    case "Nikon": return Color(hex: 0xFBBF24)
    case "Fujifilm", "Fujica": return Color(hex: 0x10B981)
    case "Canon": return Color(hex: 0xEF4444)
    case "Olympus": return Color(hex: 0x3B82F6)
    case "Pentax": return Color(hex: 0xF59E0B)
    case "Minolta": return Color(hex: 0x0EA5E9)
    case "Contax", "Yashica": return Color(hex: 0xD97706)
    case "Hasselblad": return Color(hex: 0x94A3B8)
    case "Rollei": return Color(hex: 0xFB923C)
    case "Mamiya", "Bronica": return Color(hex: 0x60A5FA)
    case "Ricoh", "Konica": return Color(hex: 0x818CF8)
    case "Voigtländer", "Zeiss": return Color(hex: 0x38BDF8)
    case "Lomography", "Agfa": return Color(hex: 0xF43F5E)
    default: return Palette.accent
    }
}

// MARK: - Camera Brand Logo (26 Vintage Emblems + Machined Enamel Bevel)

struct CameraBrandLogo: View {
    let brand: String
    var size: CGFloat = 34

    var body: some View {
        let key = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let accent = resolveBrandToneColor(key)
        Canvas { ctx, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let corner = w * 0.28
            let rect = CGRect(x: 0, y: 0, width: w, height: h)
            let rrect = Path(roundedRect: rect, cornerRadius: corner)

            // Base brand background + machined enamel sheen
            switch key {
            case "Minolta":
                drawBadgeBg(ctx: &ctx, rrect: rrect, w: w, h: h, top: Color(hex: 0x004B9B), bottom: Color(hex: 0x002B5E))
                let cx = w * 0.50, cy = h * 0.50, r = w * 0.30
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)), with: .color(.white))
                for deg in [-22.0, -11.0, 0.0, 11.0, 22.0] {
                    let yOff = cy + CGFloat(sin(deg * .pi / 180.0)) * r
                    let halfChord = CGFloat(cos(deg * .pi / 180.0)) * r
                    let barH = max(h * 0.042, 1.1)
                    let rectBar = CGRect(x: cx - halfChord * 0.92, y: yOff - barH / 2, width: halfChord * 1.84, height: barH)
                    ctx.fill(Path(roundedRect: rectBar, cornerRadius: barH / 2), with: .color(Color(hex: 0x004B9B)))
                }

            case "Contax":
                drawBadgeBg(ctx: &ctx, rrect: rrect, w: w, h: h, top: Color(hex: 0x161618), bottom: Color(hex: 0x0A0A0C))
                drawCenteredLabel(ctx: &ctx, text: "CONTAX", size: w * 0.19, weight: .black, color: Color(hex: 0xE5C158), center: CGPoint(x: w * 0.5, y: h * 0.46))
                let starRect = CGRect(x: w * 0.68, y: h * 0.63, width: w * 0.18, height: h * 0.05)
                ctx.fill(Path(roundedRect: starRect, cornerRadius: 1), with: .color(Color(hex: 0xE11D48)))

            case "Leica":
                drawBadgeBg(ctx: &ctx, rrect: rrect, w: w, h: h, top: Color(hex: 0x1C1917), bottom: Color(hex: 0x0C0A09))
                let r = w * 0.38
                let circleRect = CGRect(x: w * 0.5 - r, y: h * 0.5 - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: circleRect), with: .color(Color(hex: 0xDC1F26)))
                ctx.stroke(Path(ellipseIn: circleRect), with: .color(.white.opacity(0.28)), lineWidth: w * 0.03)
                drawCenteredLabel(ctx: &ctx, text: "Leica", size: w * 0.27, weight: .bold, italic: true, serif: true, color: .white, center: CGPoint(x: w * 0.5, y: h * 0.50))

            case "Nikon":
                drawBadgeBg(ctx: &ctx, rrect: rrect, w: w, h: h, top: Color(hex: 0xFFE100), bottom: Color(hex: 0xEAB308))
                for i in 0..<5 {
                    let y = h * (0.20 + CGFloat(i) * 0.07)
                    var ray = Path()
                    ray.move(to: CGPoint(x: w * 0.55 + CGFloat(i) * 1.5, y: y))
                    ray.addLine(to: CGPoint(x: w * 0.90, y: y - h * 0.08))
                    ctx.stroke(ray, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: w * 0.035, lineCap: .round))
                }
                drawCenteredLabel(ctx: &ctx, text: "Nikon", size: w * 0.27, weight: .black, italic: true, color: Color(hex: 0x111111), center: CGPoint(x: w * 0.5, y: h * 0.53))

            case "Fujifilm":
                drawBadgeBg(ctx: &ctx, rrect: rrect, w: w, h: h, top: Color(hex: 0x007A4D), bottom: Color(hex: 0x004D30))
                drawCenteredLabel(ctx: &ctx, text: "FUJI", size: w * 0.26, weight: .black, color: .white, center: CGPoint(x: w * 0.5, y: h * 0.44))
                let bar = CGRect(x: w * 0.22, y: h * 0.66, width: w * 0.56, height: h * 0.065)
                ctx.fill(Path(roundedRect: bar, cornerRadius: 2), with: .color(Color(hex: 0xE11D48)))

            case "Canon":
                drawBadgeBg(ctx: &ctx, rrect: rrect, w: w, h: h, top: Color(hex: 0xF8FAFC), bottom: Color(hex: 0xE2E8F0))
                drawCenteredLabel(ctx: &ctx, text: "Canon", size: w * 0.26, weight: .black, serif: true, color: Color(hex: 0xBC0024), center: CGPoint(x: w * 0.5, y: h * 0.50))

            case "Olympus":
                drawBadgeBg(ctx: &ctx, rrect: rrect, w: w, h: h, top: Color(hex: 0x0E2460), bottom: Color(hex: 0x071336))
                drawCenteredLabel(ctx: &ctx, text: "OLYMPUS", size: w * 0.17, weight: .black, color: .white, center: CGPoint(x: w * 0.5, y: h * 0.44))
                let goldBar = CGRect(x: w * 0.15, y: h * 0.64, width: w * 0.70, height: h * 0.065)
                ctx.fill(Path(roundedRect: goldBar, cornerRadius: 1.5), with: .color(Color(hex: 0xF59E0B)))

            case "Pentax":
                drawBadgeBg(ctx: &ctx, rrect: rrect, w: w, h: h, top: Color(hex: 0x18181B), bottom: Color(hex: 0x09090B))
                var shield = Path()
                shield.move(to: CGPoint(x: w * 0.50, y: h * 0.15))
                shield.addLine(to: CGPoint(x: w * 0.67, y: h * 0.28))
                shield.addLine(to: CGPoint(x: w * 0.60, y: h * 0.44))
                shield.addLine(to: CGPoint(x: w * 0.40, y: h * 0.44))
                shield.addLine(to: CGPoint(x: w * 0.33, y: h * 0.28))
                shield.closeSubpath()
                ctx.fill(shield, with: .color(Color(hex: 0xD4AF37)))
                drawCenteredLabel(ctx: &ctx, text: "PENTAX", size: w * 0.18, weight: .black, color: Color(hex: 0xE11D48), center: CGPoint(x: w * 0.5, y: h * 0.66))

            case "Rollei":
                drawBadgeBg(ctx: &ctx, rrect: rrect, w: w, h: h, top: Color(hex: 0x1E1B18), bottom: Color(hex: 0x0F0D0B))
                let frame = CGRect(x: w * 0.15, y: h * 0.15, width: w * 0.70, height: h * 0.70)
                ctx.stroke(Path(roundedRect: frame, cornerRadius: w * 0.14), with: .color(Color(hex: 0xD4AF37)), lineWidth: w * 0.045)
                drawCenteredLabel(ctx: &ctx, text: "Rollei", size: w * 0.24, weight: .bold, serif: true, color: Color(hex: 0xFBBF24), center: CGPoint(x: w * 0.5, y: h * 0.50))

            case "Hasselblad":
                drawBadgeBg(ctx: &ctx, rrect: rrect, w: w, h: h, top: Color(hex: 0x18181B), bottom: Color(hex: 0x09090B))
                let ringR = w * 0.31
                let ringRect = CGRect(x: w * 0.5 - ringR, y: h * 0.5 - ringR, width: ringR * 2, height: ringR * 2)
                ctx.stroke(Path(ellipseIn: ringRect), with: .color(Color(hex: 0xE2E8F0)), lineWidth: w * 0.045)
                drawCenteredLabel(ctx: &ctx, text: "H", size: w * 0.36, weight: .bold, color: .white, center: CGPoint(x: w * 0.5, y: h * 0.50))

            case "Mamiya":
                drawBadgeBg(ctx: &ctx, rrect: rrect, w: w, h: h, top: Color(hex: 0x0F172A), bottom: Color(hex: 0x090D16))
                drawCenteredLabel(ctx: &ctx, text: "Mamiya", size: w * 0.21, weight: .black, italic: true, color: Color(hex: 0x38BDF8), center: CGPoint(x: w * 0.5, y: h * 0.50))

            case "Yashica":
                drawBadgeBg(ctx: &ctx, rrect: rrect, w: w, h: h, top: Color(hex: 0x1C1917), bottom: Color(hex: 0x0C0A09))
                var diamond = Path()
                diamond.move(to: CGPoint(x: w * 0.50, y: h * 0.14))
                diamond.addLine(to: CGPoint(x: w * 0.86, y: h * 0.50))
                diamond.addLine(to: CGPoint(x: w * 0.50, y: h * 0.86))
                diamond.addLine(to: CGPoint(x: w * 0.14, y: h * 0.50))
                diamond.closeSubpath()
                ctx.stroke(diamond, with: .color(Color(hex: 0xEF4444)), lineWidth: w * 0.05)
                drawCenteredLabel(ctx: &ctx, text: "Y", size: w * 0.34, weight: .black, color: .white, center: CGPoint(x: w * 0.5, y: h * 0.50))

            case "Zeiss":
                drawBadgeBg(ctx: &ctx, rrect: rrect, w: w, h: h, top: Color(hex: 0x003882), bottom: Color(hex: 0x001F4D))
                let zFrame = CGRect(x: w * 0.14, y: h * 0.24, width: w * 0.72, height: h * 0.52)
                ctx.stroke(Path(roundedRect: zFrame, cornerRadius: 3), with: .color(.white.opacity(0.85)), lineWidth: w * 0.04)
                drawCenteredLabel(ctx: &ctx, text: "ZEISS", size: w * 0.21, weight: .black, color: .white, center: CGPoint(x: w * 0.5, y: h * 0.50))

            case "Voigtländer":
                drawBadgeBg(ctx: &ctx, rrect: rrect, w: w, h: h, top: Color(hex: 0x0C4A6E), bottom: Color(hex: 0x082F49))
                let oval = CGRect(x: w * 0.12, y: h * 0.24, width: w * 0.76, height: h * 0.52)
                ctx.stroke(Path(ellipseIn: oval), with: .color(Color(hex: 0xBAE6FD)), lineWidth: w * 0.04)
                drawCenteredLabel(ctx: &ctx, text: "V", size: w * 0.34, weight: .bold, italic: true, serif: true, color: .white, center: CGPoint(x: w * 0.5, y: h * 0.50))

            case "Ricoh":
                drawBadgeBg(ctx: &ctx, rrect: rrect, w: w, h: h, top: Color(hex: 0x18181B), bottom: Color(hex: 0x09090B))
                drawCenteredLabel(ctx: &ctx, text: "RICOH", size: w * 0.21, weight: .black, color: Color(hex: 0xDC2626), center: CGPoint(x: w * 0.5, y: h * 0.50))

            case "Konica":
                drawBadgeBg(ctx: &ctx, rrect: rrect, w: w, h: h, top: Color(hex: 0x0047AB), bottom: Color(hex: 0x002868))
                drawCenteredLabel(ctx: &ctx, text: "Konica", size: w * 0.22, weight: .bold, color: .white, center: CGPoint(x: w * 0.5, y: h * 0.50))

            case "Lomography":
                drawBadgeBg(ctx: &ctx, rrect: rrect, w: w, h: h, top: Color(hex: 0xE11D48), bottom: Color(hex: 0x9F1239))
                drawCenteredLabel(ctx: &ctx, text: "LOMO", size: w * 0.24, weight: .black, color: .white, center: CGPoint(x: w * 0.5, y: h * 0.50))

            case "Agfa":
                drawBadgeBg(ctx: &ctx, rrect: rrect, w: w, h: h, top: Color(hex: 0xEA580C), bottom: Color(hex: 0xC2410C))
                drawCenteredLabel(ctx: &ctx, text: "AGFA", size: w * 0.24, weight: .black, color: .white, center: CGPoint(x: w * 0.5, y: h * 0.50))

            default:
                drawBadgeBg(ctx: &ctx, rrect: rrect, w: w, h: h, top: Color(hex: 0x27272A), bottom: Color(hex: 0x18181B))
                let prefix = String(key.prefix(4)).uppercased()
                drawCenteredLabel(ctx: &ctx, text: prefix.isEmpty ? "CAM" : prefix, size: w * 0.23, weight: .black, color: accent, center: CGPoint(x: w * 0.5, y: h * 0.50))
            }

            // Machined Enamel Bevel & Specular Finish
            var sheen = Path()
            sheen.move(to: .zero)
            sheen.addLine(to: CGPoint(x: w * 0.82, y: 0))
            sheen.addLine(to: CGPoint(x: 0, y: h * 0.62))
            sheen.closeSubpath()
            ctx.clip(to: rrect)
            ctx.fill(
                sheen,
                with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.16), .clear]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: w * 0.55, y: h * 0.55)
                )
            )
            ctx.stroke(rrect, with: .color(.white.opacity(0.22)), lineWidth: max(w * 0.03, 0.8))
        }
        .frame(width: size, height: size)
    }

    private func drawBadgeBg(ctx: inout GraphicsContext, rrect: Path, w: CGFloat, h: CGFloat, top: Color, bottom: Color) {
        ctx.fill(
            rrect,
            with: .linearGradient(
                Gradient(colors: [top, bottom]),
                startPoint: .zero,
                endPoint: CGPoint(x: w, y: h)
            )
        )
    }

    private func drawCenteredLabel(
        ctx: inout GraphicsContext,
        text: String,
        size: CGFloat,
        weight: Font.Weight,
        italic: Bool = false,
        serif: Bool = false,
        color: Color,
        center: CGPoint
    ) {
        var font = Font.system(size: size, weight: weight, design: serif ? .serif : .default)
        if italic { font = font.italic() }
        let resolved = ctx.resolve(Text(text).font(font).foregroundColor(color))
        ctx.draw(resolved, at: center, anchor: .center)
    }
}

// MARK: - Camera Body Silhouettes (TLR, Medium Format, Folding, Compact, Rangefinder, SLR)

enum CameraBodyStyle: Int {
    case tlr = 0
    case mediumFormat = 1
    case folding = 2
    case compact = 3
    case rangefinder = 4
    case slr = 5
    case generic = 6
}

func resolveCameraBodyStyle(model: String, mount: String, isFixed: Bool) -> CameraBodyStyle {
    let m = model.lowercased()
    let mt = mount.lowercased()
    if m.contains("tlr") || m.contains("rolleiflex") || m.contains("rolleicord") || m.contains("autocord") || m.contains("mat-124") || m.contains("yashica-d") || mt.contains("tlr") {
        return .tlr
    }
    if mt.contains("hasselblad v") || mt.contains("rb67") || mt.contains("rz67") || mt.contains("bronica") || mt.contains("sl66") || m.contains("500c") || m.contains("swc") {
        return .mediumFormat
    }
    if m.contains("makina") || m.contains("gf670") || m.contains("folder") {
        return .folding
    }
    if isFixed && (m.contains("t2") || m.contains("t3") || m.contains("tvs") || m.contains("gr1") || m.contains("gr21") || m.contains("mju") || m.contains("xa") || m.contains("minilux") || m.contains("35ti") || m.contains("28ti") || m.contains("klasse") || m.contains("rollei 35") || m.contains("tc-1") || m.contains("lomo") || m.contains("pentax 17") || m.contains("espio") || m.contains("big mini") || m.contains("sureshot") || m.contains("autoboy") || m.contains("t4")) {
        return .compact
    }
    if mt.contains("leica m") || mt.contains("ltm") || mt.contains("m39") || mt.contains("contax g") || mt.contains("nikon s") || mt.contains("xpan") || mt.contains("mamiya 7") || mt.contains("mamiya 6") || m.contains("canonet") || m.contains("electro 35") || m.contains("hi-matic") || m.contains("hexar") || m.contains("35 sp") || m.contains("35 rc") || m.contains("gw690") {
        return .rangefinder
    }
    if !isFixed {
        return .slr
    }
    return .generic
}

struct CameraSilhouetteArtwork: View {
    let model: String
    let mount: String
    let isFixed: Bool
    var brand: String = ""
    var size: CGFloat = 34

    var body: some View {
        let style = resolveCameraBodyStyle(model: model, mount: mount, isFixed: isFixed)
        let tone = resolveBrandToneColor(brand)

        Canvas { ctx, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let tile = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: w * 0.28)
            ctx.fill(
                tile,
                with: .linearGradient(
                    Gradient(colors: [Color(hex: 0x202227), Color(hex: 0x121316)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: w, y: h)
                )
            )
            ctx.stroke(tile, with: .color(tone.opacity(0.35)), lineWidth: max(w * 0.032, 0.9))

            let chromeLight = Color(hex: 0xE2E8F0)
            let bodyDark = Color(hex: 0x18181B)

            switch style {
            case .tlr:
                let chassis = CGRect(x: w * 0.25, y: h * 0.20, width: w * 0.50, height: h * 0.66)
                ctx.fill(Path(roundedRect: chassis, cornerRadius: w * 0.07), with: .color(bodyDark))
                ctx.stroke(Path(roundedRect: chassis, cornerRadius: w * 0.07), with: .color(chromeLight.opacity(0.75)), lineWidth: w * 0.035)
                drawMultiCoatedGlass(ctx: &ctx, center: CGPoint(x: w * 0.50, y: h * 0.38), radius: w * 0.12, tint: tone)
                drawMultiCoatedGlass(ctx: &ctx, center: CGPoint(x: w * 0.50, y: h * 0.66), radius: w * 0.145, tint: tone)

            case .mediumFormat:
                let mag = CGRect(x: w * 0.14, y: h * 0.30, width: w * 0.16, height: h * 0.48)
                ctx.fill(Path(roundedRect: mag, cornerRadius: w * 0.03), with: .color(Color(hex: 0x27272A)))
                let cube = CGRect(x: w * 0.28, y: h * 0.26, width: w * 0.46, height: h * 0.54)
                ctx.fill(Path(roundedRect: cube, cornerRadius: w * 0.05), with: .color(bodyDark))
                ctx.stroke(Path(roundedRect: cube, cornerRadius: w * 0.05), with: .color(chromeLight.opacity(0.8)), lineWidth: w * 0.035)
                drawMultiCoatedGlass(ctx: &ctx, center: CGPoint(x: w * 0.53, y: h * 0.54), radius: w * 0.17, tint: tone)

            case .folding:
                let left = CGRect(x: w * 0.16, y: h * 0.22, width: w * 0.20, height: h * 0.60)
                ctx.fill(Path(roundedRect: left, cornerRadius: w * 0.04), with: .color(bodyDark))
                ctx.stroke(Path(roundedRect: left, cornerRadius: w * 0.04), with: .color(chromeLight), lineWidth: w * 0.035)
                drawMultiCoatedGlass(ctx: &ctx, center: CGPoint(x: w * 0.62, y: h * 0.52), radius: w * 0.16, tint: tone)

            case .compact:
                let bodyRect = CGRect(x: w * 0.14, y: h * 0.28, width: w * 0.72, height: h * 0.48)
                ctx.fill(Path(roundedRect: bodyRect, cornerRadius: w * 0.09), with: .color(Color(hex: 0x27272A)))
                ctx.stroke(Path(roundedRect: bodyRect, cornerRadius: w * 0.09), with: .color(chromeLight.opacity(0.8)), lineWidth: w * 0.035)
                let flash = CGRect(x: w * 0.20, y: h * 0.34, width: w * 0.16, height: h * 0.09)
                ctx.fill(Path(roundedRect: flash, cornerRadius: 2), with: .color(Color(hex: 0xFEF08A)))
                drawMultiCoatedGlass(ctx: &ctx, center: CGPoint(x: w * 0.54, y: h * 0.55), radius: w * 0.155, tint: tone)

            case .rangefinder:
                let bodyRect = CGRect(x: w * 0.14, y: h * 0.27, width: w * 0.72, height: h * 0.50)
                ctx.fill(Path(roundedRect: bodyRect, cornerRadius: w * 0.07), with: .color(bodyDark))
                let topPlate = CGRect(x: w * 0.14, y: h * 0.27, width: w * 0.72, height: h * 0.15)
                ctx.fill(Path(roundedRect: topPlate, cornerRadius: w * 0.05), with: .color(chromeLight))
                let dotR = w * 0.045
                ctx.fill(Path(ellipseIn: CGRect(x: w * 0.28 - dotR, y: h * 0.345 - dotR, width: dotR * 2, height: dotR * 2)), with: .color(Color(hex: 0xEF4444)))
                drawMultiCoatedGlass(ctx: &ctx, center: CGPoint(x: w * 0.52, y: h * 0.56), radius: w * 0.17, tint: tone)

            case .slr, .generic:
                var prism = Path()
                prism.move(to: CGPoint(x: w * 0.34, y: h * 0.32))
                prism.addLine(to: CGPoint(x: w * 0.43, y: h * 0.17))
                prism.addLine(to: CGPoint(x: w * 0.57, y: h * 0.17))
                prism.addLine(to: CGPoint(x: w * 0.66, y: h * 0.32))
                prism.closeSubpath()
                ctx.fill(prism, with: .color(chromeLight))
                let bodyRect = CGRect(x: w * 0.14, y: h * 0.30, width: w * 0.72, height: h * 0.48)
                ctx.fill(Path(roundedRect: bodyRect, cornerRadius: w * 0.06), with: .color(bodyDark))
                ctx.stroke(Path(roundedRect: bodyRect, cornerRadius: w * 0.06), with: .color(chromeLight.opacity(0.75)), lineWidth: w * 0.035)
                drawMultiCoatedGlass(ctx: &ctx, center: CGPoint(x: w * 0.50, y: h * 0.55), radius: w * 0.185, tint: tone)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Optical Lens Aperture Icon (Multi-Coated Glass + 6-Blade Iris)

struct OpticalLensApertureIcon: View {
    let minAperture: Double
    var brand: String = ""
    var isSelected: Bool = false
    var size: CGFloat = 38

    var body: some View {
        let tone = resolveBrandToneColor(brand)
        let openFraction = CGFloat((1.8 - minAperture.clamped(to: 0.95...8.0)) / 7.05).clamped(to: 0.25...0.72)

        Canvas { ctx, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let cx = w * 0.5
            let cy = h * 0.5
            let outerR = min(w, h) * 0.46
            let center = CGPoint(x: cx, y: cy)

            // Outer knurled barrel
            let outerCircle = Path(ellipseIn: CGRect(x: cx - outerR, y: cy - outerR, width: outerR * 2, height: outerR * 2))
            ctx.fill(outerCircle, with: .color(Color(hex: 0x141519)))
            ctx.stroke(outerCircle, with: .color(isSelected ? Palette.accent : Color.white.opacity(0.28)), lineWidth: w * 0.045)

            // Knurled ticks
            for i in 0..<20 {
                let angle = Double(i) * (2.0 * .pi / 20.0)
                let p1 = CGPoint(x: cx + CGFloat(cos(angle)) * outerR * 0.87, y: cy + CGFloat(sin(angle)) * outerR * 0.87)
                let p2 = CGPoint(x: cx + CGFloat(cos(angle)) * outerR * 0.96, y: cy + CGFloat(sin(angle)) * outerR * 0.96)
                var tick = Path()
                tick.move(to: p1)
                tick.addLine(to: p2)
                ctx.stroke(tick, with: .color(.white.opacity(0.22)), lineWidth: 1.0)
            }

            // Multi-coated front element
            drawMultiCoatedGlass(ctx: &ctx, center: center, radius: outerR * 0.78, tint: tone)

            // 6-blade iris polygon
            let pupilR = outerR * openFraction * 0.68
            var hex = Path()
            for i in 0..<6 {
                let rad = (Double(i) * 60.0 + 15.0) * .pi / 180.0
                let pt = CGPoint(x: cx + CGFloat(cos(rad)) * pupilR, y: cy + CGFloat(sin(rad)) * pupilR)
                if i == 0 { hex.move(to: pt) } else { hex.addLine(to: pt) }
            }
            hex.closeSubpath()
            ctx.stroke(hex, with: .color(.white.opacity(0.45)), lineWidth: max(w * 0.028, 0.9))
        }
        .frame(width: size, height: size)
    }
}

func drawMultiCoatedGlass(ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat, tint: Color) {
    let rRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    ctx.fill(
        Path(ellipseIn: rRect),
        with: .radialGradient(
            Gradient(colors: [Color(hex: 0x1A2234), Color(hex: 0x090C12), Color(hex: 0x040508)]),
            center: CGPoint(x: center.x - radius * 0.2, y: center.y - radius * 0.2),
            startRadius: 0,
            endRadius: radius
        )
    )
    ctx.stroke(Path(ellipseIn: rRect), with: .color(Color(hex: 0xCBD5E1).opacity(0.65)), lineWidth: max(radius * 0.14, 1.1))

    // Coating crescent
    let glintR = radius * 0.42
    let glintCenter = CGPoint(x: center.x - radius * 0.28, y: center.y - radius * 0.28)
    let glintRect = CGRect(x: glintCenter.x - glintR, y: glintCenter.y - glintR * 0.65, width: glintR * 2, height: glintR * 1.3)
    ctx.fill(
        Path(ellipseIn: glintRect),
        with: .radialGradient(
            Gradient(colors: [.white.opacity(0.50), tint.opacity(0.32), .clear]),
            center: glintCenter,
            startRadius: 0,
            endRadius: glintR
        )
    )
}
