import SwiftUI
import UIKit
import AudioToolbox

// MARK: - Interactive 35mm Film Leader-Pull Chamber & Grand Loading Ceremony

struct InteractiveFilmLeaderChamber: View {
    let brand: String
    let familyName: String
    let stockFullName: String
    let category: String
    let iso: Int
    let rollLength: Int
    let rollNumber: Int
    let isAlreadyLoaded: Bool
    var onLoadComplete: () -> Void

    @State private var pullProgress: CGFloat = 0.0
    @State private var dragY: CGFloat = 0.0
    @State private var isDragging: Bool = false
    @State private var isLatchedHold: Bool = false
    @State private var heartbeatScale: CGFloat = 1.0
    @State private var heartbeatTask: Task<Void, Never>? = nil

    // Grand Loading Ceremony States
    @State private var ceremonyPhase: Int = 0 // 0 = open chamber, 1 = door closed, 2 = winding S->0->1, 3 = locked at 1
    @State private var doorClosedProgress: CGFloat = 0.0
    @State private var odometerPosition: Double = -2.0 // -2 = "S", -1 = "00", 0 = "0", 1 = "1"
    @State private var motorWindAngle: Double = 0.0
    @State private var ceremonyGlow: Double = 0.0

    @State private var lastSprocketTick: Int = 0
    @State private var lastSpindleThunk: Int = 0
    @State private var idlePulse: Bool = false
    @State private var canisterSwapPop: CGFloat = 0.0

    // Leader Threading States (leader tucks into the take-up spool and locks)
    @State private var isThreading: Bool = false
    @State private var insertProgress: CGFloat = 0.0   // 0 = at spool mouth, 1 = tucked into catch slot
    @State private var tabVisibility: CGFloat = 1.0    // pull-tab fades as it disappears into the spool
    @State private var wrapProgress: CGFloat = 0.0     // film wrapping onto the take-up drum
    @State private var lockFlash: Double = 0.0         // catch-slot clamp flash
    @State private var lockWindAngle: Double = 0.0     // first take-up wrap after the clamp bites

    private let latchThreshold: CGFloat = 0.82

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let startX: CGFloat = 78
                let endX: CGFloat = w - 52
                let travel = max(endX - startX, 1)
                // Past the end of travel the tongue tucks into the drum's catch slot
                // (the drum is drawn on top, so the tip disappears inside it).
                let insertDepth = max((w - 30) - endX, 0)
                let tipX = startX + travel * pullProgress + insertDepth * insertProgress

                let tension = min(max((pullProgress - 0.06) / 0.82, 0.0), 1.0)
                let frictionJitter = isDragging && tension > 0.35 && !isLatchedHold
                    ? sin(Double(pullProgress * travel) * 0.85) * Double(tension) * 1.4
                    : 0.0
                let spoolDegrees = Double(pullProgress * travel) * 3.8 + motorWindAngle + lockWindAngle
                let isSealing = ceremonyPhase > 0 || isThreading

                ZStack {
                    // 1. Recessed Camera Film-Back Chamber Track
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(red: 0.035, green: 0.038, blue: 0.045))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(
                                    isSealing
                                        ? Palette.accent.opacity(0.65)
                                        : (isLatchedHold ? Palette.accent.opacity(0.85) : Color.white.opacity(0.08)),
                                    lineWidth: isLatchedHold || isSealing ? 1.5 : 1.0
                                )
                        )

                    // 2. Machined Film-Gate Guide Rails & Exposure Aperture Window
                    FilmChamberBackdropCanvas(
                        startX: startX,
                        endX: endX,
                        pullProgress: pullProgress,
                        latchThreshold: latchThreshold,
                        isWinding: isSealing
                    )

                    // 3. Unspooling 35mm Celluloid Film Strip (Parallel Top/Bottom Bezier Curves)
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
                        isLatchedHold: isLatchedHold,
                        heartbeatScale: heartbeatScale,
                        tabVisibility: tabVisibility
                    )

                    // 4. Right Side: Realistic Cylindrical Take-Up Spool Drum (No floating semicircles)
                    TakeUpSpoolView(
                        category: category,
                        pullProgress: pullProgress,
                        latchThreshold: latchThreshold,
                        spoolDegrees: spoolDegrees,
                        isLatchedHold: isLatchedHold,
                        heartbeatScale: heartbeatScale,
                        isWinding: ceremonyPhase > 0,
                        wrapProgress: wrapProgress,
                        lockFlash: lockFlash
                    )
                    .position(x: w - 34, y: h * 0.5)

                    // 5. Left Side: Supply Well + 3D Spinning & Tilting Canister (No floating semicircle above)
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.black.opacity(0.55))
                            .frame(width: 62, height: 102)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                            )

                        FilmCanisterArtwork(
                            brand: brand,
                            familyName: familyName,
                            category: category,
                            iso: iso,
                            showLeader: false,
                            leaderExtension: 0,
                            spoolRotation: spoolDegrees,
                            tension: tension,
                            width: 66,
                            height: 86
                        )
                        .scaleEffect(1.0 + canisterSwapPop * 0.14)
                        .rotationEffect(.degrees(Double(tension) * 6.5 + frictionJitter), anchor: .bottom)
                        .offset(x: tension * 5.0, y: CGFloat(frictionJitter * 0.35))
                        .shadow(color: .black.opacity(0.7), radius: 6, x: 3, y: 3)
                    }
                    .position(x: 42, y: h * 0.5)

                    // 6. Grand Film Loading Ceremony Overlay (Camera Back Door + Odometer Wind S -> 00 -> 0 -> 1)
                    if ceremonyPhase > 0 {
                        GrandFilmLoadingCeremonyView(
                            brand: brand,
                            stockFullName: stockFullName,
                            iso: iso,
                            rollLength: rollLength,
                            rollNumber: rollNumber,
                            ceremonyPhase: ceremonyPhase,
                            doorClosedProgress: doorClosedProgress,
                            odometerPosition: odometerPosition,
                            motorWindAngle: motorWindAngle,
                            ceremonyGlow: ceremonyGlow
                        )
                        .transition(.opacity)
                    }

                    // 7. Leader Pickup Hit Area.
// Only the physical leader origin starts the drag.
// The rest of the chamber remains available to vertical scrolling.
if ceremonyPhase == 0 && !isThreading {
    Color.clear
        .frame(width: 58, height: 58)
        .contentShape(Circle())
        .position(x: startX, y: h * 0.5)
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if !isDragging {
                        let horizontal = value.translation.width
                        let vertical = value.translation.height

                        // Ignore taps and vertical gestures.
                        // This lets the surrounding ScrollView keep scrolling.
                        guard horizontal > 4,
                              abs(horizontal) > abs(vertical) * 1.15 else {
                            return
                        }

                        isDragging = true
                        UIImpactFeedbackGenerator(style: .medium)
                            .impactOccurred(intensity: 0.7)
                    }

                    guard isDragging else { return }

                    // Progress is based on movement from the leader's
                    // original pickup location, never the finger's absolute X.
                    let rawProgress = value.translation.width / travel
                    let clamped = min(max(rawProgress, 0.0), 1.0)

                    let maxDeflection = h * 0.24
                    let yDeflection = max(
                        -maxDeflection,
                        min(maxDeflection, value.translation.height)
                    )

                    // Preserve the original magnetic latch behavior.
                    if clamped >= latchThreshold {
                        let magnet =
                            latchThreshold
                            + (clamped - latchThreshold) * 0.45

                        pullProgress = min(
                            max(magnet, latchThreshold),
                            0.94
                        )

                        dragY = yDeflection * 0.22

                        if !isLatchedHold {
                            enterLatchedHoldHeartbeat()
                        }
                    } else {
                        if isLatchedHold {
                            exitLatchedHoldHeartbeat()
                        }

                        pullProgress = clamped
                        dragY = yDeflection * (1.0 - clamped * 0.45)

                        // Keep the original sprocket ratchet cadence.
                        let distPt = Int(clamped * travel)
                        let sprocketStep = distPt / 9

                        if sprocketStep != lastSprocketTick {
                            lastSprocketTick = sprocketStep
                            UISelectionFeedbackGenerator().selectionChanged()
                        }

                        // Keep the original spindle revolution cadence.
                        let spindleStep = distPt / 48

                        if spindleStep != lastSpindleThunk {
                            lastSpindleThunk = spindleStep
                            UIImpactFeedbackGenerator(style: .light)
                                .impactOccurred(intensity: 0.5)
                        }
                    }
                }
                .onEnded { _ in
                    guard isDragging else { return }

                    isDragging = false

                    if pullProgress >= latchThreshold {
                        exitLatchedHoldHeartbeat()
                        runGrandLoadingCeremony()
                    } else {
                        exitLatchedHoldHeartbeat()

                        UIImpactFeedbackGenerator(style: .light)
                            .impactOccurred(intensity: 0.55)

                        withAnimation(
                            .spring(response: 0.38, dampingFraction: 0.52)
                        ) {
                            pullProgress = 0.0
                            dragY = 0.0
                        }

                        lastSprocketTick = 0
                        lastSpindleThunk = 0
                    }
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Film leader")
        .accessibilityHint(
            "Drag right to load the selected film. Drag left to rewind."
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) {
            guard ceremonyPhase == 0, !isThreading else { return }
            guard !isDragging else { return }
            runGrandLoadingCeremony()
        }
}

                }
                .clipShape(.rect(cornerRadius: 20, style: .continuous))
            }
            .frame(height: 132)

            // Bottom status & instruction bar
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 6.5, height: 6.5)
                        .scaleEffect(isLatchedHold ? heartbeatScale : 1.0)

                    Text(statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusTextColor)
                        .contentTransition(.numericText())
                }

                Spacer()

                if isLatchedHold {
                    Text("SLIDE LEFT TO CANCEL")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                } else {
                    Text(String(format: "ROLL #%02d", rollNumber))
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 4)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                idlePulse = true
            }
        }
        .onDisappear {
            heartbeatTask?.cancel()
            heartbeatTask = nil
        }
        .onChange(of: stockFullName) { _, _ in
            guard ceremonyPhase == 0, !isThreading else { return }
            exitLatchedHoldHeartbeat()
            canisterSwapPop = 1.0
            withAnimation(.spring(response: 0.34, dampingFraction: 0.48)) {
                canisterSwapPop = 0.0
                pullProgress = 0.0
                dragY = 0.0
            }
        }
    }

    private var statusDotColor: Color {
        if ceremonyPhase == 3 { return Palette.good }
        if ceremonyPhase > 0 || isThreading || isLatchedHold { return Palette.accent }
        return isAlreadyLoaded ? Palette.good : Palette.textDim
    }

    private var statusTextColor: Color {
        if ceremonyPhase == 3 { return Palette.good }
        if ceremonyPhase > 0 || isThreading || isLatchedHold { return Palette.accent }
        return .secondary
    }

    private var statusText: String {
        switch ceremonyPhase {
        case 1: return "CLOSING CAMERA BACK & PRESSURE PLATE…"
        case 2: return "ADVANCING LEADER · S → 00 → 0 → FRAME 1…"
        case 3: return "ROLL LOADED · LOCKED AT FRAME 1"
        default:
            if isThreading {
                return "LEADER CAUGHT · LOCKING INTO SPOOL…"
            }
            if isLatchedHold {
                return "SPOOL ENGAGED · RELEASE FINGER TO LOAD"
            }
            if pullProgress > 0.04 {
                let pct = Int((pullProgress / latchThreshold * 100).rounded()).clamped(to: 1...99)
                return "PULLING 35MM LEADER · \(pct)%"
            }
            return isAlreadyLoaded ? "PULL LEADER ACROSS TO LOAD FRESH ROLL" : "PULL FILM LEADER ACROSS TO TAKE-UP SPOOL →"
        }
    }

    // MARK: - Gentle Heartbeat While Holding in Spool

    private func enterLatchedHoldHeartbeat() {
        isLatchedHold = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.85)
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor in
            while !Task.isCancelled && isLatchedHold {
                withAnimation(.easeInOut(duration: 0.32)) {
                    heartbeatScale = 1.16
                }
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.48)
                try? await Task.sleep(for: .milliseconds(320))
                if Task.isCancelled || !isLatchedHold { break }
                withAnimation(.easeInOut(duration: 0.36)) {
                    heartbeatScale = 1.0
                }
                try? await Task.sleep(for: .milliseconds(360))
            }
        }
    }

    private func exitLatchedHoldHeartbeat() {
        isLatchedHold = false
        heartbeatTask?.cancel()
        heartbeatTask = nil
        withAnimation(.easeOut(duration: 0.2)) {
            heartbeatScale = 1.0
        }
    }

    // MARK: - 3-Stage Grand Film Loading Ceremony

    private func runGrandLoadingCeremony() {
        guard ceremonyPhase == 0, !isThreading else { return }
        isThreading = true
        odometerPosition = -2.0 // Starts at "S"

        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)

        Task { @MainActor in
            // Stage 0a: Leader slides the rest of the way and tucks into the
            // take-up drum's catch slot. The pull-tab disappears inside the drum.
            withAnimation(.timingCurve(0.42, 0.0, 0.22, 1.0, duration: 0.34)) {
                pullProgress = 1.0
                insertProgress = 1.0
                dragY = 0.0
            }
            withAnimation(.easeIn(duration: 0.28)) {
                tabVisibility = 0.0
            }
            try? await Task.sleep(for: .milliseconds(320))

            // Stage 0b: The catch slot bites — the drum clamps the tongue and
            // takes up the first wrap of film, then settles.
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1.0)
            withAnimation(.spring(response: 0.2, dampingFraction: 0.45)) {
                lockFlash = 1.0
            }
            withAnimation(.timingCurve(0.3, 0.0, 0.2, 1.0, duration: 0.52)) {
                lockWindAngle = 150.0
                wrapProgress = 1.0
            }
            for _ in 0..<3 {
                try? await Task.sleep(for: .milliseconds(120))
                UISelectionFeedbackGenerator().selectionChanged()
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.8)
            withAnimation(.easeOut(duration: 0.32)) {
                lockFlash = 0.0
            }
            try? await Task.sleep(for: .milliseconds(180))

            // Stage 1: Close the Camera Back Door over the chamber
            ceremonyPhase = 1
            isThreading = false
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                doorClosedProgress = 1.0
            }
            try? await Task.sleep(for: .milliseconds(320))
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1.0)

            // Stage 2: Two-stroke mechanical film wind (S -> 00 -> 0 -> 1) (0.55s -> 2.05s)
            ceremonyPhase = 2

            // Stroke 1: Wind from "S" (-2) to "00" (-1) to "0" (0)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.76)) {
                odometerPosition = 0.0
                motorWindAngle = 360.0
            }
            for _ in 0..<4 {
                try? await Task.sleep(for: .milliseconds(95))
                UISelectionFeedbackGenerator().selectionChanged()
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.75)

            // Brief pause between lever strokes
            try? await Task.sleep(for: .milliseconds(240))

            // Stroke 2: Wind from "0" (0) to "1" (1) and lock!
            withAnimation(.spring(response: 0.52, dampingFraction: 0.68)) {
                odometerPosition = 1.0
                motorWindAngle = 720.0
            }
            for _ in 0..<3 {
                try? await Task.sleep(for: .milliseconds(90))
                UISelectionFeedbackGenerator().selectionChanged()
            }

            // Stage 3: Frame 1 Locked & Illuminated Confirmation (2.05s -> 3.0s)
            try? await Task.sleep(for: .milliseconds(140))
            ceremonyPhase = 3
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1.0)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.62)) {
                ceremonyGlow = 1.0
            }

            try? await Task.sleep(for: .milliseconds(900))
            onLoadComplete()

            // Reset internal ceremony state after dismissal
            try? await Task.sleep(for: .milliseconds(300))
            ceremonyPhase = 0
            doorClosedProgress = 0.0
            odometerPosition = -2.0
            motorWindAngle = 0.0
            ceremonyGlow = 0.0
            pullProgress = 0.0
            insertProgress = 0.0
            tabVisibility = 1.0
            wrapProgress = 0.0
            lockFlash = 0.0
            lockWindAngle = 0.0
        }
    }
}

// MARK: - Shared Emulsion Tint

fileprivate func filmEmulsionColor(for category: String) -> Color {
    let cat = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if cat == "b&w" { return Color(red: 0.28, green: 0.32, blue: 0.38) }
    if cat == "slide" { return Color(red: 0.20, green: 0.19, blue: 0.48) }
    return Color(red: 0.54, green: 0.30, blue: 0.16)
}

// MARK: - Grand Film Loading Ceremony View (Camera Back Door + Odometer S -> 00 -> 0 -> 1)

private struct GrandFilmLoadingCeremonyView: View {
    let brand: String
    let stockFullName: String
    let iso: Int
    let rollLength: Int
    let rollNumber: Int
    let ceremonyPhase: Int
    let doorClosedProgress: CGFloat
    let odometerPosition: Double
    let motorWindAngle: Double
    let ceremonyGlow: Double

    var body: some View {
        ZStack {
            // Anodized Camera Back Door & Pressure Plate
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.11, green: 0.115, blue: 0.13),
                            Color(red: 0.06, green: 0.065, blue: 0.075)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            ceremonyPhase == 3 ? Palette.good.opacity(0.8) : Palette.accent.opacity(0.45),
                            lineWidth: ceremonyPhase == 3 ? 2.0 : 1.2
                        )
                )

            HStack(spacing: 16) {
                // Left: Classic Yellow-Bordered Film Box Reminder Window on the Camera Back
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ceremonyPhase == 3 ? Palette.good : Palette.accent)
                            .frame(width: 7, height: 7)
                        Text(String(format: "ROLL #%02d", rollNumber))
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .tracking(1.2)
                            .foregroundStyle(ceremonyPhase == 3 ? Palette.good : Palette.accent)
                    }

                    Text(stockFullName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("ISO \(iso) · \(rollLength) EXPOSURES")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Palette.textSub)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.04, green: 0.04, blue: 0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Palette.accent.opacity(0.65), lineWidth: 1.5)
                        )
                )

                // Right: Mechanical Frame Counter Odometer Window (S -> 00 -> 0 -> 1)
                VStack(spacing: 6) {
                    Text(ceremonyPhase == 3 ? "READY" : "COUNTER")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(ceremonyPhase == 3 ? Palette.good : Palette.textSub)

                    OdometerDialWindow(
                        position: odometerPosition,
                        locked: ceremonyPhase == 3
                    )
                    .frame(width: 86, height: 54)
                }
            }
            .padding(.horizontal, 16)
            .scaleEffect(0.94 + 0.06 * doorClosedProgress)
            .opacity(Double(doorClosedProgress))
        }
        .scaleEffect(y: max(0.05, doorClosedProgress), anchor: .top)
    }
}

private struct OdometerDialWindow: View, Animatable {
    var position: Double // -2 = S, -1 = 00, 0 = 0, 1 = 1
    let locked: Bool

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    private let stops: [(val: Double, label: String)] = [
        (-2.0, "S"),
        (-1.0, "00"),
        (0.0, "0"),
        (1.0, "1"),
        (2.0, "2")
    ]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            locked ? Palette.good : Palette.accent.opacity(0.55),
                            lineWidth: locked ? 2.0 : 1.2
                        )
                )

            Canvas { ctx, size in
                let cx = size.width * 0.5
                let cy = size.height * 0.54
                let pitch: CGFloat = 28

                for item in stops {
                    let d = item.val - position
                    if abs(d) > 1.6 { continue }
                    let x = cx + CGFloat(d) * pitch
                    let ad = abs(d)
                    let isCenter = ad < 0.45
                    let color: Color = isCenter
                        ? (locked ? Palette.good : (item.label == "S" ? Palette.accent : Palette.text))
                        : Palette.textDim.opacity(max(0.15, 0.65 - 0.35 * ad))

                    let txt = Text(item.label)
                        .font(.system(size: isCenter ? 26 : 17, weight: isCenter ? .bold : .medium, design: .default).monospacedDigit())
                        .foregroundColor(color)
                    ctx.draw(ctx.resolve(txt), at: CGPoint(x: x, y: cy), anchor: .center)
                }

                // Top index pointer triangle
                var ptr = Path()
                ptr.move(to: CGPoint(x: cx - 4, y: 4))
                ptr.addLine(to: CGPoint(x: cx + 4, y: 4))
                ptr.addLine(to: CGPoint(x: cx, y: 9))
                ptr.closeSubpath()
                ctx.fill(ptr, with: .color(locked ? Palette.good : Palette.accent))
            }
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
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
            let gateTop = midY - 28
            let gateBot = midY + 28

            // Upper and lower machined film guide rails
            var rails = Path()
            rails.move(to: CGPoint(x: startX, y: gateTop))
            rails.addLine(to: CGPoint(x: endX, y: gateTop))
            rails.move(to: CGPoint(x: startX, y: gateBot))
            rails.addLine(to: CGPoint(x: endX, y: gateBot))
            ctx.stroke(rails, with: .color(.white.opacity(0.07)), lineWidth: 1.0)

            // Film gate exposure aperture window in center of chamber
            let gateW: CGFloat = 72
            let gateH: CGFloat = 46
            let gateRect = CGRect(x: (startX + endX) * 0.5 - gateW * 0.5, y: midY - gateH * 0.5, width: gateW, height: gateH)
            ctx.fill(Path(roundedRect: gateRect, cornerRadius: 4), with: .color(.black.opacity(0.55)))
            ctx.stroke(Path(roundedRect: gateRect, cornerRadius: 4), with: .color(.white.opacity(0.08)), lineWidth: 1.0)

            // Guide chevrons inviting the pull gesture
            if pullProgress < 0.15 && !isWinding {
                for i in 0..<3 {
                    let cx = startX + 60 + CGFloat(i) * 26
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

private struct UnspoolingFilmStripCanvas: View, Animatable {
    let category: String
    let startX: CGFloat
    var tipX: CGFloat
    let travel: CGFloat
    let pullProgress: CGFloat
    var dragY: CGFloat
    var motorWindAngle: Double
    let idlePulse: Bool
    let isDragging: Bool
    let isLatchedHold: Bool
    let heartbeatScale: CGFloat
    var tabVisibility: CGFloat

    // Interpolate the strip geometry so the rewind spring and the leader
    // tucking into the spool are actually animated frame by frame.
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<Double, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(tipX, dragY),
                AnimatablePair(motorWindAngle, tabVisibility)
            )
        }
        set {
            tipX = newValue.first.first
            dragY = newValue.first.second
            motorWindAngle = newValue.second.first
            tabVisibility = newValue.second.second
        }
    }

    var body: some View {

        Canvas { ctx, size in
            let midY = size.height * 0.5
            let stripHalfH: CGFloat = 23
            let leaderLen: CGFloat = 34
            let currentTipX = max(startX + 30, tipX)
            let bodyEndX = max(startX, currentTipX - leaderLen)
            let ctrlX = (startX + bodyEndX) * 0.5
            let ctrlY = midY + dragY * 1.15
            let tipY = midY + dragY * 0.72

            let emulsionColor = filmEmulsionColor(for: category)

            // 1. Parallel Top & Bottom Catenary Bezier Film Strip (Never collapses or disappears on vertical drag)
            var strip = Path()
            strip.move(to: CGPoint(x: startX, y: midY - stripHalfH))
            strip.addQuadCurve(
                to: CGPoint(x: bodyEndX, y: tipY - stripHalfH),
                control: CGPoint(x: ctrlX, y: ctrlY - stripHalfH)
            )
            // Classic 35mm stepped leader tongue taper at the tip
            strip.addQuadCurve(
                to: CGPoint(x: currentTipX, y: tipY - stripHalfH * 0.40),
                control: CGPoint(x: bodyEndX + leaderLen * 0.45, y: tipY - stripHalfH)
            )
            strip.addQuadCurve(
                to: CGPoint(x: currentTipX, y: tipY + stripHalfH * 0.36),
                control: CGPoint(x: currentTipX + 4, y: tipY)
            )
            strip.addLine(to: CGPoint(x: bodyEndX, y: tipY + stripHalfH))
            // Parallel bottom Bezier curve back to canister mouth
            strip.addQuadCurve(
                to: CGPoint(x: startX, y: midY + stripHalfH),
                control: CGPoint(x: ctrlX, y: ctrlY + stripHalfH)
            )
            strip.closeSubpath()

            ctx.fill(strip, with: .color(emulsionColor.opacity(0.95)))
            ctx.stroke(
                strip,
                with: .color(isLatchedHold ? Palette.accent.opacity(0.65) : Color.white.opacity(0.20)),
                lineWidth: isLatchedHold ? 1.3 : 0.9
            )

            // 2. Unspooling Sprocket Perforations & Exposed Negative Windows (clipped to strip)
            var filmCtx = ctx
            filmCtx.clip(to: strip)

            filmCtx.fill(
                strip,
                with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.15), .clear, .black.opacity(0.24)]),
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
                let t = min(max((hx - startX) / max(bodyEndX - startX, 1), 0), 1)
                let oneMinusT = 1.0 - t
                let localMidY = oneMinusT * oneMinusT * midY + 2 * oneMinusT * t * ctrlY + t * t * tipY

                let topHole = CGRect(x: hx, y: localMidY - stripHalfH + 3.0, width: holeW, height: holeH)
                let botHole = CGRect(x: hx, y: localMidY + stripHalfH - 3.0 - holeH, width: holeW, height: holeH)
                filmCtx.fill(Path(roundedRect: topHole, cornerRadius: 0.9), with: .color(.white.opacity(0.88)))
                filmCtx.fill(Path(roundedRect: botHole, cornerRadius: 0.9), with: .color(.white.opacity(0.88)))

                if i > 2 && i % 4 == 0 && hx - 32 >= startX {
                    let winRect = CGRect(x: hx - 32, y: localMidY - stripHalfH + 9.0, width: 30, height: (stripHalfH - 9.0) * 2)
                    filmCtx.fill(Path(roundedRect: winRect, cornerRadius: 1.5), with: .color(.black.opacity(0.32)))
                }
            }

            // 3. Tactile Leader Pull-Tab Handle at the Tip
            let tabVis = min(max(tabVisibility, 0), 1)
            if tabVis > 0.01 {
                var tabCtx = ctx
                tabCtx.opacity = Double(tabVis)
                let tabCenter = CGPoint(x: currentTipX - 10, y: tipY)
                let baseR: CGFloat = isDragging ? 13.0 : (idlePulse ? 11.5 : 10.2)
                let handleR = baseR * (isLatchedHold ? heartbeatScale : 1.0) * (0.55 + 0.45 * tabVis)
                let glowRect = CGRect(x: tabCenter.x - handleR * 1.45, y: tabCenter.y - handleR * 1.45, width: handleR * 2.9, height: handleR * 2.9)
                tabCtx.fill(Path(ellipseIn: glowRect), with: .color(Palette.accent.opacity(isLatchedHold ? 0.45 : (isDragging ? 0.32 : 0.14))))

                let tabRect = CGRect(x: tabCenter.x - handleR, y: tabCenter.y - handleR, width: handleR * 2, height: handleR * 2)
                tabCtx.fill(Path(ellipseIn: tabRect), with: .color(Palette.accent))

                var grip = Path()
                grip.move(to: CGPoint(x: tabCenter.x - 2, y: tabCenter.y - 4.5))
                grip.addLine(to: CGPoint(x: tabCenter.x + 3, y: tabCenter.y))
                grip.addLine(to: CGPoint(x: tabCenter.x - 2, y: tabCenter.y + 4.5))
                tabCtx.stroke(
                    grip,
                    with: .color(Palette.accentInk),
                    style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Realistic Side-Profile Cylindrical Take-Up Spool Drum (No Floating Semicircles)

private struct TakeUpSpoolView: View, Animatable {
    let category: String
    let pullProgress: CGFloat
    let latchThreshold: CGFloat
    var spoolDegrees: Double
    let isLatchedHold: Bool
    let heartbeatScale: CGFloat
    let isWinding: Bool
    var wrapProgress: CGFloat
    var lockFlash: Double

    var animatableData: AnimatablePair<Double, AnimatablePair<CGFloat, Double>> {
        get { AnimatablePair(spoolDegrees, AnimatablePair(wrapProgress, lockFlash)) }
        set {
            spoolDegrees = newValue.first
            wrapProgress = newValue.second.first
            lockFlash = newValue.second.second
        }
    }

    var body: some View {
        let isReady = pullProgress >= latchThreshold || isLatchedHold || isWinding
        let flash = min(max(lockFlash, 0), 1)
        let ringColor: Color = isWinding ? Palette.good : (isReady ? Palette.accent : Color.white.opacity(0.16))
        let emulsion = filmEmulsionColor(for: category)

        ZStack {
            // Recessed take-up spool well
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.black.opacity(0.65))
                .frame(width: 46, height: 96)
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(ringColor, lineWidth: isReady ? 1.5 + CGFloat(flash) : 1.0)
                )
                .shadow(color: Palette.accent.opacity(0.75 * flash), radius: 8 * CGFloat(flash))

            // Side-profile cylindrical take-up drum with horizontal knurled sprocket flanges
            Canvas { ctx, size in
                let cx = size.width * 0.5
                let cy = size.height * 0.5
                let drumW: CGFloat = 24
                let drumH: CGFloat = 72
                let drumRect = CGRect(x: cx - drumW * 0.5, y: cy - drumH * 0.5, width: drumW, height: drumH)
                let drumPath = Path(roundedRect: drumRect, cornerRadius: 4)

                ctx.fill(
                    drumPath,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.16, green: 0.18, blue: 0.22),
                            Color(red: 0.34, green: 0.38, blue: 0.45),
                            Color(red: 0.12, green: 0.14, blue: 0.17)
                        ]),
                        startPoint: CGPoint(x: drumRect.minX, y: cy),
                        endPoint: CGPoint(x: drumRect.maxX, y: cy)
                    )
                )

                var drumCtx = ctx
                drumCtx.clip(to: drumPath)

                // Revolving vertical catch slots & sprocket teeth across the cylinder
                let rad = spoolDegrees * .pi / 180.0
                let fluteCount = 6
                for i in 0..<fluteCount {
                    let a = rad + Double(i) * (2.0 * .pi / Double(fluteCount))
                    let sinA = sin(a)
                    let cosA = cos(a)
                    guard cosA > 0 else { continue }
                    let fx = cx + CGFloat(sinA) * (drumW * 0.44)
                    let slotW = max(1.2, 3.2 * CGFloat(cosA))

                    // Center film-catch slot
                    let slotRect = CGRect(x: fx - slotW * 0.5, y: cy - 18, width: slotW, height: 36)
                    drumCtx.fill(
                        Path(slotRect),
                        with: .color(
                            (i == 0 && isReady)
                                ? Palette.accent.opacity(Double(cosA))
                                : Color.black.opacity(0.75 * Double(cosA))
                        )
                    )

                    // Top & bottom horizontal sprocket gear teeth along the drum collars
                    let topTooth = CGRect(x: fx - slotW * 0.4, y: drumRect.minY + 3, width: slotW * 0.8, height: 6)
                    let botTooth = CGRect(x: fx - slotW * 0.4, y: drumRect.maxY - 9, width: slotW * 0.8, height: 6)
                    let toothColor = isReady ? Palette.accent : Color.white
                    drumCtx.fill(Path(topTooth), with: .color(toothColor.opacity(0.75 * Double(cosA))))
                    drumCtx.fill(Path(botTooth), with: .color(toothColor.opacity(0.75 * Double(cosA))))
                }

                // Film wrapped onto the drum once the leader is clamped in the catch slot
                let wrap = min(max(wrapProgress, 0), 1)
                if wrap > 0.001 {
                    let bandH: CGFloat = 46
                    let bandRect = CGRect(x: drumRect.minX, y: cy - bandH * 0.5, width: drumW * wrap, height: bandH)
                    let bandPath = Path(bandRect)

                    drumCtx.fill(bandPath, with: .color(emulsion.opacity(0.96)))
                    drumCtx.fill(
                        bandPath,
                        with: .linearGradient(
                            Gradient(colors: [.black.opacity(0.45), .white.opacity(0.14), .black.opacity(0.5)]),
                            startPoint: CGPoint(x: drumRect.minX, y: cy),
                            endPoint: CGPoint(x: drumRect.maxX, y: cy)
                        )
                    )

                    var bandCtx = drumCtx
                    bandCtx.clip(to: bandPath)
                    let holeCount = 10
                    for i in 0..<holeCount {
                        let a = rad + Double(i) * (2.0 * .pi / Double(holeCount))
                        let cosA = cos(a)
                        guard cosA > 0.05 else { continue }
                        let hx = cx + CGFloat(sin(a)) * (drumW * 0.42)
                        let hw = max(0.8, 3.0 * CGFloat(cosA))
                        for hy in [bandRect.minY + 3.0, bandRect.maxY - 3.0 - 3.4] {
                            bandCtx.fill(
                                Path(roundedRect: CGRect(x: hx - hw * 0.5, y: hy, width: hw, height: 3.4), cornerRadius: 0.6),
                                with: .color(.white.opacity(0.8 * cosA))
                            )
                        }
                    }

                    // Clamp flash where the tongue is held
                    if flash > 0.01 {
                        drumCtx.fill(bandPath, with: .color(Palette.accent.opacity(0.35 * flash)))
                    }
                }

                // Top and bottom flat horizontal flange collars
                let flangeW: CGFloat = 30
                let topFlange = CGRect(x: cx - flangeW * 0.5, y: drumRect.minY, width: flangeW, height: 3)
                let botFlange = CGRect(x: cx - flangeW * 0.5, y: drumRect.maxY - 3, width: flangeW, height: 3)
                ctx.fill(Path(roundedRect: topFlange, cornerRadius: 1.5), with: .color(Color(red: 0.55, green: 0.60, blue: 0.68)))
                ctx.fill(Path(roundedRect: botFlange, cornerRadius: 1.5), with: .color(Color(red: 0.55, green: 0.60, blue: 0.68)))
            }
            .frame(width: 46, height: 96)
        }
        .scaleEffect((isLatchedHold ? heartbeatScale : (isReady ? 1.04 : 1.0)) + 0.07 * CGFloat(flash))
        .animation(.spring(response: 0.24, dampingFraction: 0.58), value: isReady)
        .allowsHitTesting(false)
    }
}

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
