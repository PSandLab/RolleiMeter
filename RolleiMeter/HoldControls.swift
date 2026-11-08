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
    var yearsExpired: Int = 0
    var isCustomFilm: Bool = false
    var filmName: String? = nil
    var onLoadComplete: () -> Void

    private var resolvedFilmName: String { filmName ?? stockFullName }

    @State private var pullProgress: CGFloat = 0.0
    @State private var dragY: CGFloat = 0.0
    @State private var isDragging: Bool = false
    @State private var isLatchedHold: Bool = false
    @State private var heartbeatScale: CGFloat = 1.0
    @State private var heartbeatTask: Task<Void, Never>? = nil

    // Grand Loading Ceremony States
    @State private var isRunningCeremony: Bool = false
    @State private var isFrameOneLocked: Bool = false
    @State private var ceremonyPhase: Int = 0 // 0 = open chamber, 1 = door closed, 2 = winding S->0->1, 3 = locked at 1
    @State private var doorClosedProgress: CGFloat = 0.0
    @State private var odometerPosition: Double = -2.0 // -2 = "S", -1 = "00", 0 = "0", 1 = "1"
    @State private var motorWindAngle: Double = 0.0
    @State private var ceremonyGlow: Double = 0.0
    @State private var windShift: CGFloat = 0.0

    @State private var lastSprocketTick: Int = 0
    @State private var lastSpindleThunk: Int = 0
    @State private var idlePulse: Bool = false
    @State private var canisterSwapPop: CGFloat = 0.0
    @State private var canisterFlight: CGFloat = 1.0 // 1 = still up in the list row, 0 = seated in chamber

    // Stage 0 Open-Chamber Suck-In & Mechanical Micro-States
    @State private var suckInProgress: CGFloat = 0.0        // 0.0 -> 1.0 during 450ms pre-door cinch
    @State private var pressurePlateProgress: CGFloat = 0.0 // 0.0 -> 1.0 spring-steel flatten before door latch
    @State private var rewindForkAngle: Double = 0.0        // Counter-clockwise spin during Stage 2 wind
    @State private var dxPinCompression: CGFloat = 0.0      // 0.0 -> 1.0 leaf-spring compression on canister seat
    @State private var dxTracePulse: CGFloat = 0.0          // 0.0 -> 1.0 gold electrical trace pulse
    @State private var lastToothClashStep: Int = -1

    private let latchThreshold: CGFloat = 0.82
    private var latchPulseScale: CGFloat { heartbeatScale }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let startX: CGFloat = 56.0 // strip emerges from behind the canister body
                let drumCenterX: CGFloat = w - 34.0
                let drumRadius: CGFloat = 16.0
                let tangentX: CGFloat = drumCenterX - drumRadius // Left horizon of 3D take-up drum
                let endX: CGFloat = drumCenterX                  // Tongue threads directly into drum slot center
                let travel: CGFloat = max(endX - startX, 1.0)

                // Effective inward suck distance during Stage 0 cinch (gulps 34pt of leader into the drum)
                let suckInShiftPt: CGFloat = suckInProgress * 34.0
                let restingLeader: CGFloat = 30.0 // leader sticks out a bit more at rest
                let tipX: CGFloat = startX + restingLeader + (travel - restingLeader) * pullProgress + suckInShiftPt

                // Sprocket tooth misalignment penalty when pulled at extreme vertical angles (|dragY| > 0.14h)
                let maxCleanDeflection: CGFloat = h * 0.14
                let toothClash: CGFloat = min(max((abs(dragY) - maxCleanDeflection) / (h * 0.10), 0.0), 1.0)

                // Tension mounts from 0.06 to 0.88; spikes to 1.0 during Stage 0 suck-in cinch
                let baseTension = min(max((pullProgress - 0.06) / 0.82, 0.0), 1.0)
                let tension: CGFloat = max(baseTension, suckInProgress)

                // High-frequency friction jitter amplified by toothClash
                let jitterAmp: CGFloat = (isDragging && tension > 0.35) ? (1.4 + toothClash * 2.2) : 0.0
                let frictionJitter: CGFloat = sin((pullProgress * travel) * (0.85 + toothClash * 1.4)) * tension * jitterAmp

                // Total spool rotation includes drag pull, Stage 0 suck-in cinch (140 deg), and Stage 2 motor wind
                let spoolDegrees: Double = Double(pullProgress * travel) * 3.8 + Double(suckInProgress) * 140.0 + motorWindAngle

                ZStack {
                    // 1. Recessed Camera Film-Back Chamber Track
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Palette.well)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(
                                    isRunningCeremony
                                        ? Palette.accent.opacity(0.65)
                                        : (isLatchedHold ? Palette.accent.opacity(0.85) : Palette.wellEdge),
                                    lineWidth: isLatchedHold || isRunningCeremony ? 1.5 : 1.0
                                )
                        )

                    // 2. Machined Film-Gate Guide Rails & Exposure Aperture Window
                    FilmChamberBackdropCanvas(
                        startX: startX,
                        endX: endX,
                        pullProgress: pullProgress,
                        latchThreshold: latchThreshold,
                        isWinding: isRunningCeremony
                    )

                    // LAYER 1 (BOTTOM): Take-Up Spool Cavity, Barrel Core, Vertical Slit & Catch Tooth
                    TakeUpSpoolBottomLayer(
                        drumCenterX: drumCenterX,
                        midY: h * 0.5,
                        drumRadius: drumRadius,
                        spoolDegrees: spoolDegrees,
                        isLatched: pullProgress >= 0.82,
                        suckInProgress: suckInProgress,
                        windProgress: CGFloat(min(max(motorWindAngle / 720.0, 0.0), 1.0)),
                        emulsionCategory: category
                    )

                    // LAYER 2 (MIDDLE): Unspooling Celluloid Strip + 3D Cylindrical Drum Wrap
                    UnspoolingFilmStripCanvas(
                        startX: startX,
                        tipX: tipX,
                        tangentX: tangentX,
                        drumCenterX: drumCenterX,
                        drumRadius: drumRadius,
                        midY: h * 0.5,
                        dragY: dragY * (1.0 - pressurePlateProgress),
                        pullProgress: pullProgress,
                        suckInProgress: suckInProgress,
                        windShift: windShift + suckInShiftPt,
                        tension: tension,
                        toothClash: toothClash,
                        pressurePlateProgress: pressurePlateProgress,
                        filmName: resolvedFilmName,
                        category: category,
                        yearsExpired: yearsExpired
                    )

                    // LAYER 3 (TOP): Spool Front Cheek Flanges & Over-Clamp Bar (Occludes Leader Tip Inside Slot)
                    TakeUpSpoolTopFlangeLayer(
                        drumCenterX: drumCenterX,
                        midY: h * 0.5,
                        drumRadius: drumRadius,
                        spoolDegrees: spoolDegrees,
                        isLatched: pullProgress >= 0.82,
                        heartbeatScale: latchPulseScale
                    )

                    // Left Side: Supply Well DX Leaf-Spring Contact Pins
                    DXContactPinsCanvas(
                        midY: h * 0.5,
                        compression: dxPinCompression,
                        tracePulse: dxTracePulse,
                        hasDXCode: !isCustomFilm
                    )

                    // Left Side: Supply Well + 3D Spinning & Tilting Canister
                    ZStack {
                        FilmCanisterArtwork(
                            filmName: resolvedFilmName,
                            brand: brand,
                            familyName: familyName,
                            category: category,
                            iso: iso,
                            showLeader: false,
                            leaderExtension: 0,
                            spoolRotation: spoolDegrees,
                            tension: tension,
                            yearsExpired: yearsExpired,
                            width: 66,
                            height: 86
                        )
                        .scaleEffect(1.0 + canisterSwapPop * 0.14)
                        .rotationEffect(.degrees(Double(tension) * 6.5 + frictionJitter), anchor: .bottom)
                        .offset(x: tension * 5.0, y: CGFloat(frictionJitter * 0.35))
                        .shadow(color: .black.opacity(0.7), radius: 6, x: 3, y: 3)
                    }
                    // The header canister "bounces" in here: drop from the list row, land with a soft bounce.
                    .scaleEffect(1.0 - 0.3 * canisterFlight)
                    .offset(y: -104.0 * canisterFlight)
                    .opacity(1.0 - 0.0 * canisterFlight)
                    .position(x: 42, y: h * 0.5)
                    .onAppear {
                        guard canisterFlight > 0 else { return }
                        withAnimation(.spring(response: 0.62, dampingFraction: 0.52).delay(0.14)) {
                            canisterFlight = 0.0
                        }
                    }

                    // 6. Grand Film Loading Ceremony Overlay (Camera Back Door + Odometer Wind S -> 00 -> 0 -> 1)
                    if doorClosedProgress > 0.01 {
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
                            ceremonyGlow: ceremonyGlow,
                            rewindForkAngle: rewindForkAngle
                        )
                        .transition(.opacity)
                    }

                    // 7. Leader Pickup Hit Area.
                    if !isRunningCeremony {
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

                                            guard horizontal > 4,
                                                  abs(horizontal) > abs(vertical) * 1.15 else {
                                                return
                                            }

                                            isDragging = true
                                            UIImpactFeedbackGenerator(style: .medium)
                                                .impactOccurred(intensity: 0.7)
                                        }

                                        guard isDragging else { return }

                                        let rawProgress = value.translation.width / travel
                                        let clamped = min(max(rawProgress, 0.0), 1.0)

                                        let maxDeflection = h * 0.24
                                        let yDeflection = max(
                                            -maxDeflection,
                                            min(maxDeflection, value.translation.height)
                                        )

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

                                            let distPt = Int(clamped * travel)
                                            let sprocketStep = distPt / 9

                                            if sprocketStep != lastSprocketTick {
                                                lastSprocketTick = sprocketStep
                                                UISelectionFeedbackGenerator().selectionChanged()
                                            }

                                            let spindleStep = distPt / 48

                                            if spindleStep != lastSpindleThunk {
                                                lastSpindleThunk = spindleStep
                                                UIImpactFeedbackGenerator(style: .light)
                                                    .impactOccurred(intensity: 0.5)
                                            }
                                        }

                                        if toothClash > 0.25 {
                                            let clashStep = Int((clamped * travel) / 5.0)
                                            if clashStep != lastToothClashStep {
                                                lastToothClashStep = clashStep
                                                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.35 + 0.45 * toothClash)
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
                                                suckInProgress = 0.0
                                                pressurePlateProgress = 0.0
                                                rewindForkAngle = 0.0
                                            }

                                            lastSprocketTick = 0
                                            lastSpindleThunk = 0
                                            lastToothClashStep = -1
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
                                guard !isRunningCeremony else { return }
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
            dxPinCompression = 1.0
            dxTracePulse = 1.0
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                dxPinCompression = 0.0
            }
            withAnimation(.easeOut(duration: 0.45)) {
                dxTracePulse = 0.0
            }
            guard !isRunningCeremony else { return }
            exitLatchedHoldHeartbeat()
            canisterSwapPop = 1.0
            withAnimation(.spring(response: 0.34, dampingFraction: 0.48)) {
                canisterSwapPop = 0.0
                pullProgress = 0.0
                dragY = 0.0
                suckInProgress = 0.0
                pressurePlateProgress = 0.0
                rewindForkAngle = 0.0
            }
        }
    }

    private var statusDotColor: Color {
        if isFrameOneLocked || ceremonyPhase == 3 { return Palette.good }
        if isRunningCeremony || ceremonyPhase > 0 || isLatchedHold { return Palette.accent }
        return isAlreadyLoaded ? Palette.good : Palette.textDim
    }

    private var statusTextColor: Color {
        if isFrameOneLocked || ceremonyPhase == 3 { return Palette.good }
        if isRunningCeremony || ceremonyPhase > 0 || isLatchedHold { return Palette.accent }
        return .secondary
    }

    private var statusText: String {
        switch ceremonyPhase {
        case 1: return "CLOSING CAMERA BACK & PRESSURE PLATE…"
        case 2: return "ADVANCING LEADER · S → 00 → 0 → FRAME 1…"
        case 3: return "ROLL LOADED · LOCKED AT FRAME 1"
        default:
            if suckInProgress > 0.01 {
                return "CINCHING LEADER ONTO SPOOL…"
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
                try? await Task.sleep(nanoseconds: 320_000_000)
                if Task.isCancelled || !isLatchedHold { break }
                withAnimation(.easeInOut(duration: 0.36)) {
                    heartbeatScale = 1.0
                }
                try? await Task.sleep(nanoseconds: 360_000_000)
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

    private func stopLatchHeartbeat() {
        exitLatchedHoldHeartbeat()
    }

    // MARK: - 4-Phase Grand Film Loading Ceremony

    private func runGrandLoadingCeremony() {
        guard !isRunningCeremony else { return }
        isRunningCeremony = true
        ceremonyPhase = 0
        stopLatchHeartbeat()

        Task { @MainActor in
            // =========================================================================
            // STAGE 0 (t = 0.00s - 0.45s): OPEN-CHAMBER SUCK-IN, TOOTH BITE & SLACK CINCH
            // =========================================================================
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1.0)

            // Snap catenary slack (dragY) taut like a plucked guitar string
            withAnimation(.spring(response: 0.18, dampingFraction: 0.38)) {
                dragY = 0.0
            }

            // High-torque 140-degree spool cinch sucks 34pt of tongue inside the drum core
            withAnimation(.spring(response: 0.28, dampingFraction: 0.66)) {
                pullProgress = 0.96
                suckInProgress = 1.0
            }

            // Supply canister yank feedback when slack hits zero at t = 120ms
            try? await Task.sleep(nanoseconds: 120_000_000)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.90)

            // Allow user to admire the wrapped, drum-tight film across the open rails
            try? await Task.sleep(nanoseconds: 330_000_000)

            // =========================================================================
            // STAGE 1 (t = 0.45s - 0.98s): SPRING-STEEL PRESSURE PLATE & BACK DOOR SLAM
            // =========================================================================
            ceremonyPhase = 1
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                pressurePlateProgress = 1.0
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.65)

            try? await Task.sleep(nanoseconds: 70_000_000)

            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                doorClosedProgress = 1.0
            }

            try? await Task.sleep(nanoseconds: 460_000_000)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1.0)

            // =========================================================================
            // STAGE 2 (t = 0.98s - 2.48s): TWO-STROKE WIND (S -> 00 -> 0 -> 1) & REWIND FORK SPIN
            // =========================================================================
            ceremonyPhase = 2
            try? await Task.sleep(nanoseconds: 120_000_000)

            // Stroke 1: S (-2.0) -> 0 (0.0)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.76)) {
                odometerPosition = 0.0
                motorWindAngle = 360.0
                windShift = 72.0
            }

            // Rewind fork takes up cassette slack for 190ms, then spins counter-clockwise
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 190_000_000)
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    rewindForkAngle = -240.0
                }
            }

            for _ in 0..<4 {
                try? await Task.sleep(nanoseconds: 95_000_000)
                UISelectionFeedbackGenerator().selectionChanged()
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.75)

            // 240ms mechanical lever return pause
            try? await Task.sleep(nanoseconds: 240_000_000)

            // Stroke 2: 0 (0.0) -> 1 (1.0) with full 360-degree counter-clockwise rewind fork rotation
            withAnimation(.spring(response: 0.52, dampingFraction: 0.68)) {
                odometerPosition = 1.0
                motorWindAngle = 720.0
                windShift = 144.0
                rewindForkAngle = -600.0
            }

            for _ in 0..<3 {
                try? await Task.sleep(nanoseconds: 90_000_000)
                UISelectionFeedbackGenerator().selectionChanged()
            }

            // =========================================================================
            // STAGE 3 (t = 2.48s - 3.35s): FRAME 1 LOCKED & ILLUMINATED CONFIRMATION
            // =========================================================================
            ceremonyPhase = 3
            try? await Task.sleep(nanoseconds: 220_000_000)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1.0)

            withAnimation(.spring(response: 0.38, dampingFraction: 0.62)) {
                isFrameOneLocked = true
                ceremonyGlow = 1.0
            }

            try? await Task.sleep(nanoseconds: 880_000_000)
            onLoadComplete()
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
    var rewindForkAngle: Double = 0.0

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

            HStack(spacing: 12) {
                // Left-Side Recessed Rewind Fork Spin-Check Indicator
                ZStack {
                    Circle()
                        .fill(Color(red: 0.07, green: 0.08, blue: 0.09))
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )

                    // Fork Spline + Direction Arrow
                    ZStack {
                        Capsule()
                            .fill(Color(red: 0.76, green: 0.81, blue: 0.87))
                            .frame(width: 14, height: 2.5)
                        Circle()
                            .fill(Palette.accent)
                            .frame(width: 3.5, height: 3.5)
                            .offset(x: 5)
                    }
                    .rotationEffect(.degrees(rewindForkAngle))
                }

                // Center: Classic Yellow-Bordered Film Box Reminder Window on the Camera Back
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
            ctx.stroke(rails, with: .color(Palette.text.opacity(0.10)), lineWidth: 1.0)

            // Film gate exposure aperture window in center of chamber
            let gateW: CGFloat = 72
            let gateH: CGFloat = 46
            let gateRect = CGRect(x: (startX + endX) * 0.5 - gateW * 0.5, y: midY - gateH * 0.5, width: gateW, height: gateH)
            ctx.fill(Path(roundedRect: gateRect, cornerRadius: 4), with: .color(Palette.wellDeep))
            ctx.stroke(Path(roundedRect: gateRect, cornerRadius: 4), with: .color(Palette.wellEdge), lineWidth: 1.0)

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

// MARK: - Take-Up Spool 3-Layer Sandwich & Photochemical Film Strip

struct TakeUpSpoolBottomLayer: View {
    let drumCenterX: CGFloat
    let midY: CGFloat
    let drumRadius: CGFloat
    let spoolDegrees: Double
    let isLatched: Bool
    let suckInProgress: CGFloat
    let windProgress: CGFloat
    let emulsionCategory: String

    private var woundCollarColor: Color {
        switch emulsionCategory.lowercased() {
        case "b&w":   return Color(red: 0.28, green: 0.32, blue: 0.38)
        case "slide": return Color(red: 0.20, green: 0.19, blue: 0.48)
        default:      return Color(red: 0.54, green: 0.30, blue: 0.16)
        }
    }

    var body: some View {
        Canvas { ctx, size in
            let barrelH: CGFloat = 56.0
            let barrelRect = CGRect(
                x: drumCenterX - drumRadius,
                y: midY - barrelH * 0.5,
                width: drumRadius * 2.0,
                height: barrelH
            )

            // 1. Recessed Spool Well Shadow
            let wellRect = barrelRect.insetBy(dx: -6, dy: -8)
            ctx.fill(
                Path(roundedRect: wellRect, cornerRadius: 8),
                with: .color(Color.black.opacity(0.85))
            )

            // 2. Cylindrical Drum Barrel Core
            ctx.fill(
                Path(roundedRect: barrelRect, cornerRadius: 4),
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.16, green: 0.17, blue: 0.20),
                        Color(red: 0.26, green: 0.28, blue: 0.32),
                        Color(red: 0.08, green: 0.09, blue: 0.11)
                    ]),
                    startPoint: CGPoint(x: barrelRect.minX, y: midY),
                    endPoint: CGPoint(x: barrelRect.maxX, y: midY)
                )
            )

            // 3. Concentric Wound Celluloid Collar (Thickens during Suck-In & Stage 2 Wind)
            let wrapThickness = (suckInProgress * 1.4) + (windProgress * 2.2)
            if wrapThickness > 0.05 {
                let collarRect = CGRect(
                    x: drumCenterX - drumRadius - wrapThickness * 0.6,
                    y: midY - 23.0,
                    width: (drumRadius * 2.0) + wrapThickness * 1.2,
                    height: 46.0
                )
                ctx.fill(
                    Path(roundedRect: collarRect, cornerRadius: 2.5),
                    with: .color(woundCollarColor.opacity(0.92))
                )
            }

            // 4. Revolving Vertical Catch Slit & Brass Sprocket Catch Tooth
            let angleRad = spoolDegrees * .pi / 180.0
            let slitOffset = CGFloat(sin(angleRad)) * (drumRadius * 0.72)
            let slitX = drumCenterX + slitOffset

            let slitRect = CGRect(x: slitX - 2.2, y: midY - 24.0, width: 4.4, height: 48.0)
            ctx.fill(
                Path(roundedRect: slitRect, cornerRadius: 1.5),
                with: .color(isLatched ? Palette.accent.opacity(0.45) : Color.black.opacity(0.92))
            )

            // Brass Catch Tooth inside slit at bottom sprocket line (midY + 17.5)
            let toothRect = CGRect(x: slitX - 1.8, y: midY + 15.5, width: 3.6, height: 4.2)
            ctx.fill(
                Path(roundedRect: toothRect, cornerRadius: 0.8),
                with: .color(isLatched ? Palette.accent : Color(red: 0.88, green: 0.66, blue: 0.31))
            )
        }
        .allowsHitTesting(false)
    }
}

struct TakeUpSpoolTopFlangeLayer: View {
    let drumCenterX: CGFloat
    let midY: CGFloat
    let drumRadius: CGFloat
    let spoolDegrees: Double
    let isLatched: Bool
    let heartbeatScale: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let flangeW = (drumRadius * 2.0) + 6.0
            let topFlange = CGRect(x: drumCenterX - flangeW * 0.5, y: midY - 31.0, width: flangeW, height: 5.5)
            let botFlange = CGRect(x: drumCenterX - flangeW * 0.5, y: midY + 25.5, width: flangeW, height: 5.5)

            // Top & Bottom Knurled Spool Flanges (Gear Teeth)
            for flange in [topFlange, botFlange] {
                ctx.fill(
                    Path(roundedRect: flange, cornerRadius: 2.0),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.22, green: 0.24, blue: 0.28),
                            Color(red: 0.48, green: 0.52, blue: 0.58),
                            Color(red: 0.12, green: 0.13, blue: 0.16)
                        ]),
                        startPoint: CGPoint(x: flange.minX, y: flange.midY),
                        endPoint: CGPoint(x: flange.maxX, y: flange.midY)
                    )
                )

                // Revolving Knurl Notches on Flanges
                let notchCount = 7
                let phase = CGFloat(spoolDegrees.truncatingRemainder(dividingBy: 360.0) / 360.0)
                for i in 0..<notchCount {
                    let norm = (CGFloat(i) / CGFloat(notchCount) + phase).truncatingRemainder(dividingBy: 1.0)
                    let nx = flange.minX + 2.0 + norm * (flange.width - 4.0)
                    let nRect = CGRect(x: nx - 0.8, y: flange.minY + 1.0, width: 1.6, height: flange.height - 2.0)
                    ctx.fill(Path(nRect), with: .color(Color.black.opacity(0.65)))
                }
            }

            // Right-Side Over-Clamp Bar (Occludes Leader Tip Once Threaded Into Slit)
            let clampRect = CGRect(
                x: drumCenterX + 1.5,
                y: midY - 25.5,
                width: drumRadius - 1.5,
                height: 51.0
            )
            ctx.fill(
                Path(roundedRect: clampRect, cornerRadius: 2.0),
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.18, green: 0.20, blue: 0.24).opacity(0.92),
                        Color(red: 0.06, green: 0.07, blue: 0.09).opacity(0.98)
                    ]),
                    startPoint: CGPoint(x: clampRect.minX, y: midY),
                    endPoint: CGPoint(x: clampRect.maxX, y: midY)
                )
            )

            // Latched Magnetic Target Halo
            if isLatched {
                let haloW = (drumRadius * 2.0 + 10.0) * heartbeatScale
                let haloH = 62.0 * heartbeatScale
                let haloRect = CGRect(
                    x: drumCenterX - haloW * 0.5,
                    y: midY - haloH * 0.5,
                    width: haloW,
                    height: haloH
                )
                ctx.stroke(
                    Path(roundedRect: haloRect, cornerRadius: 8.0),
                    with: .color(Palette.accent.opacity(0.85)),
                    lineWidth: 1.6
                )
            }
        }
        .allowsHitTesting(false)
    }
}

struct UnspoolingFilmStripCanvas: View {
    let startX: CGFloat
    let tipX: CGFloat
    let tangentX: CGFloat
    let drumCenterX: CGFloat
    let drumRadius: CGFloat
    let midY: CGFloat
    let dragY: CGFloat
    let pullProgress: CGFloat
    let suckInProgress: CGFloat
    let windShift: CGFloat
    let tension: CGFloat
    let toothClash: CGFloat
    let pressurePlateProgress: CGFloat
    var filmName: String = ""
    let category: String
    var yearsExpired: Int = 0

    private func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(max((x - edge0) / max(edge1 - edge0, 0.0001), 0.0), 1.0)
        return t * t * (3.0 - 2.0 * t)
    }

    private var isVision3Remjet: Bool {
        filmName.localizedCaseInsensitiveContains("vision3")
    }

    private var isCineStillHalation: Bool {
        filmName.localizedCaseInsensitiveContains("cinestill") && category.lowercased() != "b&w"
    }

    private var isClearPETBase: Bool {
        filmName.localizedCaseInsensitiveContains("rollei") || filmName.localizedCaseInsensitiveContains("ortho")
    }

    private var baseEmulsionColor: Color {
        let fogFactor = min(Double(yearsExpired) / 50.0, 1.0) * 0.22
        switch category.lowercased() {
        case "b&w":
            return Color(red: 0.28 + fogFactor * 0.4, green: 0.32 + fogFactor * 0.3, blue: 0.38 + fogFactor * 0.2)
        case "slide":
            return Color(red: 0.20 + fogFactor * 0.3, green: 0.19 + fogFactor * 0.2, blue: 0.48)
        default:
            return Color(red: 0.54 + fogFactor * 0.35, green: 0.30 + fogFactor * 0.25, blue: 0.16 + fogFactor * 0.45)
        }
    }

    private var freshHalideColor: Color {
        switch category.lowercased() {
        case "b&w":   return Color(red: 0.43, green: 0.48, blue: 0.55)
        case "slide": return Color(red: 0.32, green: 0.30, blue: 0.64)
        default:      return Color(red: 0.71, green: 0.54, blue: 0.35)
        }
    }

    var body: some View {
        Canvas { ctx, size in
            let stripHalfH: CGFloat = 23.0 - (pressurePlateProgress * 0.8)
            let isLatched = pullProgress >= 0.82
            let latchBlend = smoothstep(0.78, 0.84, pullProgress)

            // When latched (>= 0.82), tipY locks onto the spool catch tooth at midY while belly (ctrlY) pivots!
            let effectiveTipY = midY + dragY * 0.45 * (1.0 - latchBlend)
            let effectiveCtrlY = midY + dragY * (isLatched ? 0.55 : 0.85)

            // Tongue taper shrinks as Stage 0 sucks the narrow tongue inside the drum core
            let tongueLen: CGFloat = 26.0 * (1.0 - suckInProgress * 0.85)
            let rawBodyEndX = max(startX + 4.0, tipX - tongueLen)
            let flatBodyEndX = min(rawBodyEndX, tangentX)
            let ctrlX = startX + (flatBodyEndX - startX) * 0.52

            // 1. Vision3 Remjet Carbon Underside Shadow when bowed
            if isVision3Remjet && abs(dragY) > 2.0 {
                var remjetPath = Path()
                let offset: CGFloat = dragY > 0 ? 2.5 : -2.5
                remjetPath.move(to: CGPoint(x: startX, y: midY - stripHalfH + offset))
                remjetPath.addQuadCurve(
                    to: CGPoint(x: flatBodyEndX, y: effectiveTipY - stripHalfH + offset),
                    control: CGPoint(x: ctrlX, y: effectiveCtrlY - stripHalfH + offset)
                )
                remjetPath.addLine(to: CGPoint(x: flatBodyEndX, y: effectiveTipY + stripHalfH + offset))
                remjetPath.addQuadCurve(
                    to: CGPoint(x: startX, y: midY + stripHalfH + offset),
                    control: CGPoint(x: ctrlX, y: effectiveCtrlY + stripHalfH + offset)
                )
                remjetPath.closeSubpath()
                ctx.fill(remjetPath, with: .color(Color(red: 0.04, green: 0.05, blue: 0.06)))
            }

            // 2. Flat Chamber Parallel Bezier Strip (from startX up to tangentX)
            var stripPath = Path()
            stripPath.move(to: CGPoint(x: startX, y: midY - stripHalfH))
            stripPath.addQuadCurve(
                to: CGPoint(x: flatBodyEndX, y: effectiveTipY - stripHalfH),
                control: CGPoint(x: ctrlX, y: effectiveCtrlY - stripHalfH)
            )

            // If tip hasn't reached the 3D drum horizon yet, draw the stepped 35mm leader tongue in 2D
            if tipX <= tangentX + 6.0 {
                let tipTopY = effectiveTipY - stripHalfH * 0.40
                stripPath.addQuadCurve(
                    to: CGPoint(x: tipX, y: tipTopY),
                    control: CGPoint(x: flatBodyEndX + tongueLen * 0.45, y: effectiveTipY - stripHalfH * 0.40)
                )
                stripPath.addLine(to: CGPoint(x: tipX, y: effectiveTipY + stripHalfH))
            } else {
                stripPath.addLine(to: CGPoint(x: flatBodyEndX, y: effectiveTipY + stripHalfH))
            }

            stripPath.addQuadCurve(
                to: CGPoint(x: startX, y: midY + stripHalfH),
                control: CGPoint(x: ctrlX, y: effectiveCtrlY + stripHalfH)
            )
            stripPath.closeSubpath()

            // Fill Flat Strip with Light-Struck vs. Fresh Unspooled Halide Dichroic Gradient
            let baseOpacity: Double = isClearPETBase ? 0.54 : 0.90
            let halideBoundary = min(startX + 26.0 * pullProgress, flatBodyEndX)
            ctx.fill(
                stripPath,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: freshHalideColor.opacity(baseOpacity), location: 0.0),
                        .init(color: baseEmulsionColor.opacity(baseOpacity), location: max(0.05, min(0.28, (halideBoundary - startX) / max(flatBodyEndX - startX, 1.0)))),
                        .init(color: baseEmulsionColor.opacity(baseOpacity), location: 1.0)
                    ]),
                    startPoint: CGPoint(x: startX, y: midY),
                    endPoint: CGPoint(x: max(flatBodyEndX, startX + 10), y: midY)
                )
            )

            // Acetate Cupping Specular Wave (Diagonal plastic curl reflection that sharpens with tension)
            let waveCenter = startX + (flatBodyEndX - startX) * (0.35 + 0.30 * tension)
            let waveHalfW = max(14.0, 38.0 * (1.0 - tension * 0.55))
            var waveCtx = ctx
            waveCtx.clip(to: stripPath)
            waveCtx.fill(
                stripPath,
                with: .linearGradient(
                    Gradient(colors: [
                        Color.white.opacity(0.0),
                        Color.white.opacity(isClearPETBase ? 0.26 : 0.14),
                        Color.white.opacity(0.0)
                    ]),
                    startPoint: CGPoint(x: waveCenter - waveHalfW, y: midY - stripHalfH),
                    endPoint: CGPoint(x: waveCenter + waveHalfW, y: midY + stripHalfH)
                )
            )

            // Tooth-Clash Friction Amber Border Highlight
            let strokeColor = toothClash > 0.1
                ? Color.orange.opacity(0.45 + 0.45 * Double(toothClash))
                : Color.white.opacity(0.22)
            ctx.stroke(stripPath, with: .color(strokeColor), lineWidth: 0.9)

            // 3. 3D CYLINDRICAL DRUM WRAP PASS (For film past tangentX wrapping onto take-up spool)
            if tipX > tangentX {
                let linearPastTangent = tipX - tangentX
                let maxPhi = min(linearPastTangent / drumRadius, .pi * 0.58)
                let wrappedMaxX = tangentX + drumRadius * sin(maxPhi)

                // Taper top edge smoothly as tongue wraps around the cylinder; full height once sucked in
                let wrapTopInset = (1.0 - suckInProgress) * (stripHalfH * 0.45) * smoothstep(0.0, 1.0, maxPhi / (.pi * 0.5))
                var wrapPath = Path()
                wrapPath.move(to: CGPoint(x: tangentX - 0.5, y: effectiveTipY - stripHalfH))
                wrapPath.addLine(to: CGPoint(x: wrappedMaxX, y: midY - stripHalfH + wrapTopInset))
                wrapPath.addLine(to: CGPoint(x: wrappedMaxX, y: midY + stripHalfH))
                wrapPath.addLine(to: CGPoint(x: tangentX - 0.5, y: effectiveTipY + stripHalfH))
                wrapPath.closeSubpath()

                // 3-Stop Cylindrical Shader: Tangent Knuckle Highlight -> Emulsion -> Roll-Off Shadow
                ctx.fill(
                    wrapPath,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: Color.white.opacity(0.32), location: 0.0),
                            .init(color: baseEmulsionColor.opacity(0.95), location: 0.35),
                            .init(color: Color.black.opacity(0.82), location: 1.0)
                        ]),
                        startPoint: CGPoint(x: tangentX, y: midY),
                        endPoint: CGPoint(x: tangentX + drumRadius, y: midY)
                    )
                )
            }

            // 4. SPROCKET PERFORATIONS, NEGATIVE WINDOWS & COS(PHI) CYLINDRICAL FORESHORTENING
            let pitch: CGFloat = 11.0
            let holeW: CGFloat = 5.5
            let holeH: CGFloat = 3.8
            let phaseShift = windShift.truncatingRemainder(dividingBy: pitch)
            var hx = startX + 6.0 - phaseShift
            var holeIndex = Int(floor(windShift / pitch))

            while hx < tipX - 4.0 {
                defer {
                    hx += pitch
                    holeIndex += 1
                }
                guard hx >= startX + 2.0 else { continue }

                if hx <= tangentX {
                    // Flat Bezier Parametric Curve Mapping
                    let t = min(max((hx - startX) / max(flatBodyEndX - startX, 1.0), 0.0), 1.0)
                    let oneMinusT = 1.0 - t
                    let curveY = (oneMinusT * oneMinusT * midY)
                        + (2.0 * oneMinusT * t * effectiveCtrlY)
                        + (t * t * effectiveTipY)

                    // Latent Exposure Negative Window every 4 perforations
                    if holeIndex % 4 == 0 && (hx + 30.0) < flatBodyEndX {
                        let winRect = CGRect(x: hx, y: curveY - 14.0, width: 30.0, height: 28.0)
                        ctx.fill(
                            Path(roundedRect: winRect, cornerRadius: 1.5),
                            with: .color(Color.black.opacity(0.32))
                        )
                    }

                    // Latent Amber Rebate Edge Markings every 2 perforations
                    if holeIndex % 2 == 0 {
                        let rebateRect = CGRect(x: hx + 1.0, y: curveY - stripHalfH + 0.8, width: 4.0, height: 1.0)
                        ctx.fill(Path(rebateRect), with: .color(Palette.accent.opacity(0.38)))
                    }

                    // Top & Bottom Sprocket Perforations
                    let topHole = CGRect(x: hx - holeW * 0.5, y: curveY - stripHalfH + 2.4, width: holeW, height: holeH)
                    let botHole = CGRect(x: hx - holeW * 0.5, y: curveY + stripHalfH - 2.4 - holeH, width: holeW, height: holeH)

                    // CineStill Remjet-Free Red Halation Glow around Sprockets
                    if isCineStillHalation {
                        ctx.fill(
                            Path(roundedRect: topHole.insetBy(dx: -1.6, dy: -1.4), cornerRadius: 1.8),
                            with: .color(Color(red: 1.0, green: 0.23, blue: 0.19).opacity(0.30))
                        )
                        ctx.fill(
                            Path(roundedRect: botHole.insetBy(dx: -1.6, dy: -1.4), cornerRadius: 1.8),
                            with: .color(Color(red: 1.0, green: 0.23, blue: 0.19).opacity(0.30))
                        )
                    }

                    if hx < rawBodyEndX {
                        ctx.fill(Path(roundedRect: topHole, cornerRadius: 0.9), with: .color(Color.white.opacity(0.88)))
                    }
                    ctx.fill(Path(roundedRect: botHole, cornerRadius: 0.9), with: .color(Color.white.opacity(0.88)))

                } else {
                    // 3D Cylindrical Drum Foreshortening: x_wrapped = tangentX + R * sin(phi), w = 5.5 * cos(phi)
                    let phi = (hx - tangentX) / drumRadius
                    guard phi < (.pi * 0.48) else { continue } // Vanishes behind right horizon of drum!

                    let cosPhi = cos(phi)
                    let wrappedX = tangentX + drumRadius * sin(phi)
                    let foreshortenedW = max(0.8, holeW * cosPhi)
                    let holeOpacity = 0.88 * Double(cosPhi)

                    let botWrappedHole = CGRect(
                        x: wrappedX - foreshortenedW * 0.5,
                        y: midY + stripHalfH - 2.4 - holeH,
                        width: foreshortenedW,
                        height: holeH
                    )
                    ctx.fill(
                        Path(roundedRect: botWrappedHole, cornerRadius: 0.6),
                        with: .color(Color.white.opacity(holeOpacity))
                    )

                    // Top sprocket only visible once full-height strip wraps onto drum
                    if suckInProgress > 0.35 {
                        let topWrappedHole = CGRect(
                            x: wrappedX - foreshortenedW * 0.5,
                            y: midY - stripHalfH + 2.4,
                            width: foreshortenedW,
                            height: holeH
                        )
                        ctx.fill(
                            Path(roundedRect: topWrappedHole, cornerRadius: 0.6),
                            with: .color(Color.white.opacity(holeOpacity * Double(suckInProgress)))
                        )
                    }
                }
            }

            // 5. DISSOLVING CIRCULAR PULL-TAB GRIP BADGE (Scales 1.0 -> 0.0 across 0.76...0.84 so tongue inserts cleanly)
            let gripBadgeScale = 1.0 - smoothstep(0.76, 0.84, pullProgress)
            if gripBadgeScale > 0.01 && suckInProgress == 0.0 {
                let badgeR: CGFloat = 13.0 * gripBadgeScale
                let badgeCenter = CGPoint(x: min(tipX - 4.0, tangentX), y: effectiveTipY + 2.0)
                let badgeRect = CGRect(
                    x: badgeCenter.x - badgeR,
                    y: badgeCenter.y - badgeR,
                    width: badgeR * 2.0,
                    height: badgeR * 2.0
                )
                // Grip badge circle removed (rendered as a stray blue semicircle beside the pull tab).
                _ = badgeRect
            }
        }
        .allowsHitTesting(false)
    }
}

struct DXContactPinsCanvas: View {
    let midY: CGFloat
    let compression: CGFloat   // 0.0 -> 1.0 on canisterSwapPop
    let tracePulse: CGFloat    // 0.0 -> 1.0 gold electrical readout pulse
    let hasDXCode: Bool

    var body: some View {
        Canvas { ctx, size in
            let pinCount = 6
            let spacing: CGFloat = 6.8
            let startY = midY - (CGFloat(pinCount - 1) * spacing) * 0.5
            let baseX: CGFloat = 14.0
            let tipExtend: CGFloat = 6.5 - (compression * 2.5)

            for i in 0..<pinCount {
                let py = startY + CGFloat(i) * spacing
                var pinPath = Path()
                pinPath.move(to: CGPoint(x: baseX, y: py - 1.2))
                pinPath.addLine(to: CGPoint(x: baseX + tipExtend, y: py))
                pinPath.addLine(to: CGPoint(x: baseX, y: py + 1.2))

                let pinColor = (hasDXCode && tracePulse > 0.1)
                    ? Palette.accent
                    : Color(red: 0.88, green: 0.66, blue: 0.31)
                ctx.stroke(pinPath, with: .color(pinColor), lineWidth: 1.4)

                // Contact spark dot
                let dotRect = CGRect(x: baseX + tipExtend - 1.0, y: py - 1.0, width: 2.0, height: 2.0)
                ctx.fill(Path(ellipseIn: dotRect), with: .color(Color.white.opacity(0.65 + 0.35 * Double(tracePulse))))
            }
        }
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
