import SwiftUI
import UIKit
import AudioToolbox

// MARK: - Interactive 35mm Film Leader-Pull Chamber

struct InteractiveFilmLeaderChamber: View {
    let brand: String
    let familyName: String
    let stockFullName: String
    let category: String
    let iso: Int
    let rollLength: Int
    let isAlreadyLoaded: Bool
    var onLoadComplete: () -> Void

    @State private var pullProgress: CGFloat = 0.0
    @State private var dragY: CGFloat = 0.0
    @State private var isDragging: Bool = false
    @State private var isWinding: Bool = false
    @State private var motorWindAngle: Double = 0.0
    @State private var lastSprocketTick: Int = 0
    @State private var lastSpindleThunk: Int = 0
    @State private var idlePulse: Bool = false
    @State private var canisterSwapPop: CGFloat = 0.0

    private let latchThreshold: CGFloat = 0.84

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let startX: CGFloat = 76
                let endX: CGFloat = w - 54
                let travel = max(endX - startX, 1)
                let tipX = startX + travel * pullProgress

                // Mechanical tension & high-frequency friction shudder
                let tension = min(max((pullProgress - 0.08) / 0.82, 0.0), 1.0)
                let frictionJitter = isDragging && tension > 0.35
                    ? sin(Double(pullProgress * travel) * 0.9) * Double(tension) * 1.6
                    : 0.0
                let spoolDegrees = Double(pullProgress * travel) * 3.8 + motorWindAngle

                ZStack {
                    // 1. Recessed Camera Film-Back Chamber Track
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(red: 0.04, green: 0.045, blue: 0.055))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(
                                    isWinding
                                        ? Palette.good.opacity(0.65)
                                        : (pullProgress >= latchThreshold ? Palette.accent.opacity(0.75) : Color.white.opacity(0.08)),
                                    lineWidth: isWinding || pullProgress >= latchThreshold ? 1.5 : 1.0
                                )
                        )

                    // 2. Machined Film-Gate Guide Rails & Pressure Plate Grooves
                    FilmChamberBackdropCanvas(
                        startX: startX,
                        endX: endX,
                        pullProgress: pullProgress,
                        latchThreshold: latchThreshold,
                        isWinding: isWinding
                    )

                    // 3. Unspooling 35mm Celluloid Film Strip, Sprockets & Catenary Bend
                    UnspoolingFilmStripCanvas(
                        category: category,
                        startX: startX,
                        tipX: tipX,
                        travel: travel,
                        pullProgress: pullProgress,
                        dragY: dragY,
                        motorWindAngle: motorWindAngle,
                        idlePulse: idlePulse,
                        isDragging: isDragging,
                        isWinding: isWinding
                    )

                    // 4. Right Side: Mechanical Take-Up Spool & Sprocket Roller
                    TakeUpSpoolView(
                        pullProgress: pullProgress,
                        latchThreshold: latchThreshold,
                        spoolDegrees: spoolDegrees,
                        isWinding: isWinding
                    )
                    .position(x: w - 34, y: h * 0.5)

                    // 5. Left Side: Supply Bay + 3D Spinning & Tilting Canister
                    ZStack {
                        // Top-down mechanical spindle rotation telemetry dial
                        Circle()
                            .strokeBorder(
                                Color.white.opacity(0.14 + Double(tension) * 0.25),
                                style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
                            )
                            .frame(width: 58, height: 58)
                            .rotationEffect(.degrees(spoolDegrees))
                            .offset(y: -26)

                        FilmCanisterArtwork(
                            brand: brand,
                            familyName: familyName,
                            category: category,
                            iso: iso,
                            showLeader: false,
                            leaderExtension: 0,
                            spoolRotation: spoolDegrees,
                            tension: tension,
                            width: 68,
                            height: 82
                        )
                        .scaleEffect(1.0 + canisterSwapPop * 0.12)
                        .rotationEffect(.degrees(Double(tension) * 7.5 + frictionJitter), anchor: .bottom)
                        .offset(x: tension * 5.5, y: CGFloat(frictionJitter * 0.4))
                        .shadow(color: .black.opacity(0.65), radius: 6, x: 3, y: 3)
                    }
                    .position(x: 42, y: h * 0.52)

                    // 6. Full-Chamber Drag Gesture Surface
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard !isWinding else { return }
                                    if !isDragging {
                                        isDragging = true
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.75)
                                    }

                                    let rawProgress = (value.location.x - startX) / travel
                                    let clamped = min(max(rawProgress, 0.0), 1.0)
                                    let yDeflection = max(-24, min(24, value.location.y - h * 0.5))

                                    pullProgress = clamped
                                    dragY = yDeflection * (1.0 - clamped * 0.45)

                                    // Sprocket-tooth ratchet haptics every 9pt of film pulled
                                    let distPt = Int(clamped * travel)
                                    let sprocketStep = distPt / 9
                                    if sprocketStep != lastSprocketTick {
                                        let crossedLatch = (lastSprocketTick * 9 < Int(latchThreshold * travel)) && (distPt >= Int(latchThreshold * travel))
                                        lastSprocketTick = sprocketStep
                                        if crossedLatch {
                                            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1.0)
                                        } else {
                                            UISelectionFeedbackGenerator().selectionChanged()
                                        }
                                    }

                                    // Spindle revolution thunk every 48pt
                                    let spindleStep = distPt / 48
                                    if spindleStep != lastSpindleThunk {
                                        lastSpindleThunk = spindleStep
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
                                    }

                                    // Auto-trigger wind if pulled all the way into the spool core
                                    if clamped >= 0.96 {
                                        engageTakeUpSpoolAndWind()
                                    }
                                }
                                .onEnded { _ in
                                    guard !isWinding else { return }
                                    isDragging = false
                                    if pullProgress >= latchThreshold {
                                        engageTakeUpSpoolAndWind()
                                    } else {
                                        // Spring rewind snap-back with reverse spindle spin & vertical whip
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
                                        withAnimation(.spring(response: 0.36, dampingFraction: 0.50)) {
                                            pullProgress = 0.0
                                            dragY = 0.0
                                        }
                                        lastSprocketTick = 0
                                        lastSpindleThunk = 0
                                    }
                                }
                        )
                }
            }
            .frame(height: 112)

            // Bottom status & instruction bar
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isWinding ? Palette.good : (pullProgress >= latchThreshold ? Palette.accent : (isAlreadyLoaded ? Palette.good : Palette.textDim)))
                        .frame(width: 6, height: 6)

                    Text(statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isWinding ? Palette.good : (pullProgress >= latchThreshold ? Palette.accent : .secondary))
                        .contentTransition(.numericText())
                }

                Spacer()

                Text("\(stockFullName) · \(rollLength) EXP")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                idlePulse = true
            }
        }
        .onChange(of: stockFullName) { _, _ in
            guard !isWinding else { return }
            canisterSwapPop = 1.0
            withAnimation(.spring(response: 0.32, dampingFraction: 0.48)) {
                canisterSwapPop = 0.0
                pullProgress = 0.0
                dragY = 0.0
            }
        }
    }

    private var statusText: String {
        if isWinding {
            return "WINDING LEADER TO FRAME 1…"
        }
        if pullProgress >= latchThreshold {
            return "RELEASE TO LOCK IN TAKE-UP SPOOL"
        }
        if pullProgress > 0.04 {
            let pct = Int((pullProgress / latchThreshold * 100).rounded()).clamped(to: 1...99)
            return "PULLING FILM LEADER · \(pct)%"
        }
        return isAlreadyLoaded ? "PULL LEADER ACROSS TO RELOAD FRESH ROLL" : "PULL FILM LEADER ACROSS TO LOAD ROLL →"
    }

    private func engageTakeUpSpoolAndWind() {
        guard !isWinding else { return }
        isWinding = true
        isDragging = false
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1.0)

        withAnimation(.spring(response: 0.22, dampingFraction: 0.68)) {
            pullProgress = 1.0
            dragY = 0.0
        }

        // Rapid motor-drive advance wind (spins both spools +540° and fires ratchet burst)
        withAnimation(.easeInOut(duration: 0.52)) {
            motorWindAngle = 540.0
        }

        Task { @MainActor in
            for _ in 0..<5 {
                try? await Task.sleep(for: .milliseconds(85))
                UISelectionFeedbackGenerator().selectionChanged()
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onLoadComplete()
            try? await Task.sleep(for: .milliseconds(250))
            isWinding = false
            motorWindAngle = 0.0
            pullProgress = 0.0
        }
    }
}

private struct FilmChamberBackdropCanvas: View {
    let startX: CGFloat
    let endX: CGFloat
    let pullProgress: CGFloat
    let latchThreshold: CGFloat
    let isWinding: Bool

    var body: some View {
        Canvas { ctx, size in
            let midY = size.height * 0.5
            let gateTop = midY - 26
            let gateBot = midY + 26

            // Upper and lower machined film guide rails
            var rails = Path()
            rails.move(to: CGPoint(x: startX, y: gateTop))
            rails.addLine(to: CGPoint(x: endX, y: gateTop))
            rails.move(to: CGPoint(x: startX, y: gateBot))
            rails.addLine(to: CGPoint(x: endX, y: gateBot))
            ctx.stroke(rails, with: .color(.white.opacity(0.07)), lineWidth: 1.0)

            // Film gate exposure aperture window in center of chamber
            let gateW: CGFloat = 68
            let gateH: CGFloat = 44
            let gateRect = CGRect(x: (startX + endX) * 0.5 - gateW * 0.5, y: midY - gateH * 0.5, width: gateW, height: gateH)
            ctx.fill(Path(roundedRect: gateRect, cornerRadius: 4), with: .color(.black.opacity(0.55)))
            ctx.stroke(Path(roundedRect: gateRect, cornerRadius: 4), with: .color(.white.opacity(0.08)), lineWidth: 1.0)

            // Guide chevrons inviting the pull gesture
            if pullProgress < 0.15 && !isWinding {
                for i in 0..<3 {
                    let cx = startX + 58 + CGFloat(i) * 26
                    var chev = Path()
                    chev.move(to: CGPoint(x: cx - 4, y: midY - 6))
                    chev.addLine(to: CGPoint(x: cx + 2, y: midY))
                    chev.addLine(to: CGPoint(x: cx - 4, y: midY + 6))
                    ctx.stroke(
                        chev,
                        with: .color(Palette.accent.opacity(0.28 - Double(i) * 0.07)),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct UnspoolingFilmStripCanvas: View {
    let category: String
    let startX: CGFloat
    let tipX: CGFloat
    let travel: CGFloat
    let pullProgress: CGFloat
    let dragY: CGFloat
    let motorWindAngle: Double
    let idlePulse: Bool
    let isDragging: Bool
    let isWinding: Bool

    var body: some View {
        let cat = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        Canvas { ctx, size in
            let midY = size.height * 0.5
            let stripHalfH: CGFloat = 23
            let leaderLen: CGFloat = 34
            let currentTipX = max(startX + 28, tipX)
            let bodyEndX = max(startX, currentTipX - leaderLen)
            let ctrlX = (startX + currentTipX) * 0.5
            let ctrlY = midY + dragY * 1.15
            let tipY = midY + dragY * 0.65

            let emulsionColor: Color = {
                if cat == "b&w" { return Color(red: 0.28, green: 0.32, blue: 0.38) }
                if cat == "slide" { return Color(red: 0.20, green: 0.19, blue: 0.48) }
                return Color(red: 0.54, green: 0.30, blue: 0.16)
            }()

            // 1. Curved Catenary Film Strip + Die-Cut Leader Tongue
            var strip = Path()
            strip.move(to: CGPoint(x: startX, y: midY - stripHalfH))
            strip.addQuadCurve(
                to: CGPoint(x: bodyEndX, y: tipY - stripHalfH),
                control: CGPoint(x: ctrlX, y: ctrlY - stripHalfH)
            )
            // Classic 35mm stepped leader tongue taper
            strip.addQuadCurve(
                to: CGPoint(x: currentTipX, y: tipY - stripHalfH * 0.42),
                control: CGPoint(x: bodyEndX + leaderLen * 0.45, y: tipY - stripHalfH)
            )
            strip.addQuadCurve(
                to: CGPoint(x: currentTipX, y: tipY + stripHalfH * 0.32),
                control: CGPoint(x: currentTipX + 5, y: tipY - stripHalfH * 0.05)
            )
            strip.addLine(to: CGPoint(x: startX, y: midY + stripHalfH))
            strip.closeSubpath()

            ctx.fill(strip, with: .color(emulsionColor.opacity(0.94)))
            ctx.stroke(strip, with: .color(Color.white.opacity(0.18)), lineWidth: 0.8)

            // 2. Unspooling Sprocket Perforations & Exposed Negative Windows (clipped to strip)
            var filmCtx = ctx
            filmCtx.clip(to: strip)

            // Specular celluloid sheen
            filmCtx.fill(
                strip,
                with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.14), .clear, .black.opacity(0.22)]),
                    startPoint: CGPoint(x: startX, y: midY - stripHalfH),
                    endPoint: CGPoint(x: startX, y: midY + stripHalfH)
                )
            )

            let windShift = CGFloat(motorWindAngle / 360.0) * 72.0
            let holePitch: CGFloat = 11.0
            let holeW: CGFloat = 5.5
            let holeH: CGFloat = 3.8
            let span = currentTipX - startX + windShift
            let holeCount = Int(span / holePitch) + 2

            for i in 0..<holeCount {
                let hx = currentTipX + windShift - CGFloat(i) * holePitch - 10
                guard hx >= startX - holeW && hx <= currentTipX - 4 else { continue }
                let t = min(max((hx - startX) / max(currentTipX - startX, 1), 0), 1)
                // Quadratic Bezier Y interpolation matching the catenary curve
                let oneMinusT = 1.0 - t
                let localMidY = oneMinusT * oneMinusT * midY + 2 * oneMinusT * t * ctrlY + t * t * tipY

                let topHole = CGRect(x: hx, y: localMidY - stripHalfH + 3.0, width: holeW, height: holeH)
                let botHole = CGRect(x: hx, y: localMidY + stripHalfH - 3.0 - holeH, width: holeW, height: holeH)
                filmCtx.fill(Path(roundedRect: topHole, cornerRadius: 0.9), with: .color(.white.opacity(0.86)))
                filmCtx.fill(Path(roundedRect: botHole, cornerRadius: 0.9), with: .color(.white.opacity(0.86)))

                // Every 4th perforation, draw a dark negative frame window + amber edge number
                if i > 2 && i % 4 == 0 && hx - 32 >= startX {
                    let winRect = CGRect(x: hx - 32, y: localMidY - stripHalfH + 9.0, width: 30, height: (stripHalfH - 9.0) * 2)
                    filmCtx.fill(Path(roundedRect: winRect, cornerRadius: 1.5), with: .color(.black.opacity(0.32)))
                }
            }

            // 3. Tactile Leader Pull-Tab Handle at the Tip
            if !isWinding {
                let tabCenter = CGPoint(x: currentTipX - 10, y: tipY)
                let handleR: CGFloat = isDragging ? 13 : (idlePulse ? 11.5 : 10.0)
                let glowRect = CGRect(x: tabCenter.x - handleR * 1.4, y: tabCenter.y - handleR * 1.4, width: handleR * 2.8, height: handleR * 2.8)
                ctx.fill(Path(ellipseIn: glowRect), with: .color(Palette.accent.opacity(isDragging ? 0.35 : (idlePulse ? 0.22 : 0.08))))

                let tabRect = CGRect(x: tabCenter.x - handleR, y: tabCenter.y - handleR, width: handleR * 2, height: handleR * 2)
                ctx.fill(Path(ellipseIn: tabRect), with: .color(Palette.accent))

                var grip = Path()
                grip.move(to: CGPoint(x: tabCenter.x - 2, y: tabCenter.y - 4.5))
                grip.addLine(to: CGPoint(x: tabCenter.x + 3, y: tabCenter.y))
                grip.addLine(to: CGPoint(x: tabCenter.x - 2, y: tabCenter.y + 4.5))
                ctx.stroke(
                    grip,
                    with: .color(Palette.accentInk),
                    style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct TakeUpSpoolView: View {
    let pullProgress: CGFloat
    let latchThreshold: CGFloat
    let spoolDegrees: Double
    let isWinding: Bool

    var body: some View {
        let isReady = pullProgress >= latchThreshold || isWinding
        let ringColor: Color = isWinding ? Palette.good : (isReady ? Palette.accent : Color.white.opacity(0.22))

        ZStack {
            // Outer take-up chamber well
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.65))
                .frame(width: 44, height: 84)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(ringColor, lineWidth: isReady ? 1.5 : 1.0)
                )

            // Rotating top & bottom sprocket gear wheels on the take-up drum
            VStack(spacing: 38) {
                Circle()
                    .strokeBorder(
                        ringColor,
                        style: StrokeStyle(lineWidth: 2.2, dash: [2.5, 2.5])
                    )
                    .frame(width: 26, height: 26)
                    .rotationEffect(.degrees(spoolDegrees))

                Circle()
                    .strokeBorder(
                        ringColor,
                        style: StrokeStyle(lineWidth: 2.2, dash: [2.5, 2.5])
                    )
                    .frame(width: 26, height: 26)
                    .rotationEffect(.degrees(spoolDegrees))
            }

            // Take-up spool core cylinder + vertical film catch slot
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.22, green: 0.25, blue: 0.30),
                            Color(red: 0.42, green: 0.46, blue: 0.54),
                            Color(red: 0.16, green: 0.18, blue: 0.22)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 22, height: 54)
                .overlay {
                    Rectangle()
                        .fill(isReady ? Palette.accent : Color.black.opacity(0.75))
                        .frame(width: 3, height: 34)
                }

            if isWinding {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Palette.good)
                    .background(Circle().fill(Color.black))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(isReady ? 1.06 : 1.0)
        .animation(.spring(response: 0.24, dampingFraction: 0.58), value: isReady)
        .allowsHitTesting(false)
    }
}

import SwiftUI

struct HoldToLoadButton: View {
    let rollLength: Int
    var holdDuration: Double = 1.2
    var isEnabled: Bool = true
    var onComplete: () -> Void

    @State private var progress: CGFloat = 0
    @State private var completed = false
    @State private var pop = false
    @State private var flash = false
    @State private var pressTick = 0
    @State private var doneTick = 0

    var body: some View {
        ZStack {
            Label("Hold to Load", systemImage: "film")
                .font(.headline)
                .opacity(max(0, 1 - Double(progress) * 2))
            FilmStripFill(progress: progress, frames: rollLength, flash: flash)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .clipShape(.capsule)
        .glassEffect(.regular.interactive(), in: .capsule)
        .scaleEffect(pop ? 1.06 : 1)
        .allowsHitTesting(isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .onLongPressGesture(minimumDuration: holdDuration, maximumDistance: 60) {
            guard isEnabled else { return }
            completed = true
            doneTick += 1
            withAnimation(.spring(duration: 0.35, bounce: 0.5)) {
                pop = true
                flash = true
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(.easeOut(duration: 0.15)) {
                    flash = false
                }
                try? await Task.sleep(for: .milliseconds(200))
                withAnimation(.spring(duration: 0.25)) {
                    pop = false
                }
                onComplete()
            }
        } onPressingChanged: { pressing in
            guard isEnabled, !completed else { return }
            if pressing {
                pressTick += 1
                withAnimation(.linear(duration: holdDuration)) {
                    progress = 1
                }
            } else {
                withAnimation(.snappy) {
                    progress = 0
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: pressTick)
        .sensoryFeedback(.success, trigger: doneTick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hold to load film")
        .accessibilityHint("Press and hold to load the roll")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard isEnabled, !completed else { return }
            completed = true
            doneTick += 1
            progress = 1
            onComplete()
        }
    }
}

struct FilmStripFill: View, Animatable {
    var progress: CGFloat
    var frames: Int
    var flash: Bool = false

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private static let filmGreen = Color(red: 0.16, green: 0.68, blue: 0.42)
    private static let litWindow = Color(red: 0.52, green: 0.96, blue: 0.72)

    var body: some View {
        GeometryReader { geo in
            let totalWidth = max(geo.size.width, 1)
            let clamped = min(max(progress, 0), 1)

            Canvas { ctx, size in
                let pitch: CGFloat = 16
                var x: CGFloat = 8
                while x < totalWidth {
                    for y in [CGFloat(5), size.height - 9] {
                        ctx.fill(
                            Path(roundedRect: CGRect(x: x, y: y, width: 6, height: 4), cornerRadius: 1),
                            with: .color(.black.opacity(0.55))
                        )
                    }
                    x += pitch
                }

                let safeFrames = max(frames, 1)
                let litFrameCount = Int((clamped * CGFloat(safeFrames)).rounded(.down))
                let slotCount = min(safeFrames, max(6, Int((totalWidth - 20) / 28)))
                let horizontalInset: CGFloat = 10
                let spacing: CGFloat = 4
                let availableW = max(1, totalWidth - horizontalInset * 2 - spacing * CGFloat(max(slotCount - 1, 0)))
                let slotW = availableW / CGFloat(max(slotCount, 1))
                let windowY: CGFloat = 12
                let windowH = max(8, size.height - 24)

                for slot in 0..<slotCount {
                    let slotThreshold = Int((Double(slot + 1) / Double(slotCount) * Double(safeFrames)).rounded(.down))
                    let isLit = litFrameCount >= max(1, slotThreshold) || clamped >= 0.99
                    let wx = horizontalInset + CGFloat(slot) * (slotW + spacing)
                    let rect = CGRect(x: wx, y: windowY, width: slotW, height: windowH)
                    let path = Path(roundedRect: rect, cornerRadius: 3)

                    ctx.fill(
                        path,
                        with: .color(isLit ? Self.litWindow.opacity(0.45) : .black.opacity(0.28))
                    )
                    ctx.stroke(
                        path,
                        with: .color(isLit ? Self.litWindow.opacity(0.85) : .white.opacity(0.18)),
                        lineWidth: 1
                    )
                }

                if flash {
                    ctx.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .color(.white.opacity(0.28))
                    )
                }
            }
            .background(Self.filmGreen.gradient)
            .frame(width: max(totalWidth * clamped, 0), alignment: .leading)
            .clipShape(.capsule)
            .frame(width: totalWidth, alignment: .leading)
        }
        .allowsHitTesting(false)
    }
}
