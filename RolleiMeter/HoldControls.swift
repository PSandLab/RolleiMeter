import SwiftUI

// MARK: - Phase

/// The three states a press-and-hold control moves through.
enum HoldPhase: Equatable {
    case idle
    case holding
    case done
}

// MARK: - Press tracking

/// Tracks the pressed state of a `Button` so a hold can start on touch-down and
/// cancel on lift, while `List` keeps its own scrolling gesture.
struct HoldPressStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
    }
}

// MARK: - Driver

/// The shared hold state machine. It owns the timer, the progress value and the
/// haptics; the content closure only has to draw for a given phase and progress.
struct HoldGesture<Content: View>: View {
    var holdDuration: Double
    var isEnabled: Bool
    var accessibilityTitle: String
    var accessibilityHintText: String
    let onComplete: () -> Void
    let content: (HoldPhase, CGFloat) -> Content

    @State private var phase: HoldPhase = .idle
    @State private var progress: CGFloat = 0
    @State private var isPressed = false
    @State private var ticker: Task<Void, Never>?
    @State private var reset: Task<Void, Never>?

    init(holdDuration: Double = 1.2,
         isEnabled: Bool = true,
         accessibilityTitle: String,
         accessibilityHintText: String = "Press and hold, or use the action to do it immediately.",
         onComplete: @escaping () -> Void,
         @ViewBuilder content: @escaping (HoldPhase, CGFloat) -> Content) {
        self.holdDuration = holdDuration
        self.isEnabled = isEnabled
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityHintText = accessibilityHintText
        self.onComplete = onComplete
        self.content = content
    }

    var body: some View {
        Button(action: {}) {
            content(phase, progress)
        }
        .buttonStyle(HoldPressStyle(isPressed: $isPressed))
        .disabled(!isEnabled)
        .onChange(of: isPressed) { _, pressed in
            guard isEnabled else { return }
            if pressed {
                guard phase == .idle else { return }
                begin()
            } else if phase == .holding {
                cancel()
            }
        }
        .onChange(of: isEnabled) { _, enabled in
            guard !enabled else { return }
            if phase == .holding { cancel() }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityTitle)
        .accessibilityHint(accessibilityHintText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard isEnabled, phase == .idle else { return }
            commit()
        }
        .onDisappear {
            ticker?.cancel()
            reset?.cancel()
        }
    }

    private func begin() {
        Haptics.press()
        phase = .holding
        ticker?.cancel()
        ticker = Task { @MainActor in
            let started = Date()
            var lastTick = -1
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(started)
                let raw = min(1, max(0, elapsed / max(holdDuration, 0.1)))
                progress = CGFloat(raw)

                let tick = Int(raw * 12)
                if tick != lastTick {
                    lastTick = tick
                    if tick > 0 && tick < 12 { Haptics.rigid() }
                }

                if raw >= 1 {
                    commit()
                    return
                }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }

    private func commit() {
        ticker?.cancel()
        ticker = nil
        Haptics.success()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
            progress = 1
            phase = .done
        }
        onComplete()

        reset?.cancel()
        reset = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                progress = 0
                phase = .idle
            }
        }
    }

    private func cancel() {
        ticker?.cancel()
        ticker = nil
        Haptics.tap()
        withAnimation(.easeOut(duration: 0.22)) {
            progress = 0
            phase = .idle
        }
    }
}

// MARK: - Film strip

/// The film control: a strip of 35 mm film that winds onto a spool (or feeds
/// out of the canister) as the gesture progresses.
///
/// The strip is drawn rather than imitated with a progress bar because the
/// gesture *is* film transport: the sprockets run, the frames slide past and the
/// roll gets wound in.
struct FilmStripHoldControl: View {
    /// `windOn` pulls the strip into the spool (finishing a roll); `feedIn`
    /// pulls it out of the canister (loading one).
    enum Direction: Equatable {
        case windOn
        case feedIn
    }

    var title: String
    var workingTitle: String
    var doneTitle: String
    var systemImage: String = "film"
    var direction: Direction = .windOn
    var holdDuration: Double = 1.2
    var isEnabled: Bool = true
    let onComplete: () -> Void

    /// The strip keeps a green cast in both states: deep and unlit at rest,
    /// glowing while it moves.
    private static let green = Color(hex: 0x3AD98A)
    private static let cardFill = Color(hex: 0x0B1B13)
    private static let baseFill = Color(hex: 0x16241A)
    /// The perforations read as punched holes, so they are darker than the film.
    private static let punchFill = Color(hex: 0x060E09)

    var body: some View {
        HoldGesture(holdDuration: holdDuration,
                    isEnabled: isEnabled,
                    accessibilityTitle: title,
                    onComplete: onComplete) { phase, progress in
            card(phase: phase, progress: progress)
        }
    }

    private func card(phase: HoldPhase, progress: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            FilmStripGraphic(progress: phase == .idle ? 0 : progress,
                             direction: direction,
                             tint: Self.green,
                             base: Self.baseFill,
                             punch: Self.punchFill)
                .frame(height: 42)

            HStack(spacing: 7) {
                Image(systemName: symbol(phase))
                    .font(.system(size: 11, weight: .bold))

                Text(label(phase))
                    .font(Geist.text(.subheadline, .semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                if phase == .holding {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(Geist.monoText(.caption, .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(phase == .done ? Self.green : Palette.text)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Self.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Self.green.opacity(phase == .idle ? 0.20 : 0.45), lineWidth: 1)
        )
        .scaleEffect(phase == .holding ? 0.996 : 1)
        .animation(.easeOut(duration: 0.2), value: phase)
    }

    private func symbol(_ phase: HoldPhase) -> String {
        switch phase {
        case .idle: return systemImage
        case .holding: return "arrow.left.arrow.right"
        case .done: return "checkmark"
        }
    }

    private func label(_ phase: HoldPhase) -> String {
        switch phase {
        case .idle: return title
        case .holding: return workingTitle
        case .done: return doneTitle
        }
    }
}

// MARK: - The strip itself

private struct FilmStripGraphic: View {
    let progress: CGFloat
    let direction: FilmStripHoldControl.Direction
    let tint: Color
    let base: Color
    let punch: Color

    var body: some View {
        Canvas { ctx, size in
            let h = size.height
            let cy = h / 2
            let p = min(1, max(0, progress))

            let reelR = h * 0.47
            let reelCx = reelR + 1
            let wound: CGFloat = direction == .windOn ? p : 1 - p
            let woundR = reelR * (0.50 + 0.50 * wound)

            let stripH = h * 0.68
            let stripTop = cy - stripH / 2
            let maxLen = max(0, size.width - (reelCx + reelR) - 2)
            let stripLen: CGFloat = direction == .windOn ? maxLen * (1 - p) : maxLen * p
            let x0 = reelCx + woundR - 2
            let strip = CGRect(x: x0, y: stripTop, width: stripLen, height: stripH)

            if stripLen > 1 {
                ctx.drawLayer { layer in
                    layer.clip(to: Path(strip))
                    layer.fill(Path(strip), with: .color(base))

                    // Clear film edges.
                    layer.fill(Path(CGRect(x: strip.minX, y: strip.minY, width: strip.width, height: 1.2)),
                               with: .color(tint.opacity(0.40)))
                    layer.fill(Path(CGRect(x: strip.minX, y: strip.maxY - 1.2, width: strip.width, height: 1.2)),
                               with: .color(tint.opacity(0.28)))

                    // Sprocket holes, running as the strip moves.
                    let pitch: CGFloat = 11
                    let holeW: CGFloat = 6.2
                    let holeH: CGFloat = 3.6
                    let scroll = (p * pitch * 4).truncatingRemainder(dividingBy: pitch)
                    var x = strip.minX - pitch - scroll
                    while x < strip.maxX {
                        let top = CGRect(x: x, y: strip.minY + 3.2, width: holeW, height: holeH)
                        let bottom = CGRect(x: x, y: strip.maxY - 3.2 - holeH, width: holeW, height: holeH)
                        layer.fill(Path(roundedRect: top, cornerRadius: 1), with: .color(punch))
                        layer.fill(Path(roundedRect: bottom, cornerRadius: 1), with: .color(punch))
                        x += pitch
                    }

                    // Frame windows between the perforations.
                    let framePitch: CGFloat = 33
                    let frameScroll = (p * framePitch * 4).truncatingRemainder(dividingBy: framePitch)
                    var fx = strip.minX - framePitch - frameScroll
                    while fx < strip.maxX {
                        let window = CGRect(x: fx + 3,
                                            y: strip.minY + 7.2,
                                            width: framePitch - 8,
                                            height: strip.height - 14.4)
                        let path = Path(roundedRect: window, cornerRadius: 1.5)
                        layer.fill(path, with: .color(tint.opacity(0.20)))
                        layer.stroke(path, with: .color(tint.opacity(0.45)), lineWidth: 0.8)
                        fx += framePitch
                    }
                }
            }

            // The spool, drawn last so the strip disappears behind it.
            let reelRect = CGRect(x: reelCx - woundR, y: cy - woundR,
                                  width: woundR * 2, height: woundR * 2)
            ctx.fill(Path(ellipseIn: reelRect), with: .color(Color(hex: 0x12251A)))

            let rings: [Double] = [0.55, 0.35, 0.22]
            for (index, alpha) in rings.enumerated() {
                let r = woundR * (1 - CGFloat(index) * 0.16) - 0.6
                guard r > 2 else { continue }
                ctx.stroke(Path(ellipseIn: CGRect(x: reelCx - r, y: cy - r, width: r * 2, height: r * 2)),
                           with: .color(tint.opacity(alpha)),
                           lineWidth: 0.9)
            }

            let hubR = reelR * 0.30
            let hub = CGRect(x: reelCx - hubR, y: cy - hubR, width: hubR * 2, height: hubR * 2)
            ctx.fill(Path(ellipseIn: hub), with: .color(Color(hex: 0x08130D)))
            ctx.stroke(Path(ellipseIn: hub), with: .color(tint.opacity(0.85)), lineWidth: 1.2)

            let spin = Double(p) * 800 * .pi / 180
            for k in 0..<3 {
                let angle = spin + Double(k) * (2 * .pi / 3)
                var spoke = Path()
                spoke.move(to: CGPoint(x: reelCx + hubR * 0.30 * CGFloat(cos(angle)),
                                       y: cy + hubR * 0.30 * CGFloat(sin(angle))))
                spoke.addLine(to: CGPoint(x: reelCx + hubR * 0.92 * CGFloat(cos(angle)),
                                          y: cy + hubR * 0.92 * CGFloat(sin(angle))))
                ctx.stroke(spoke,
                           with: .color(tint.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
        }
    }
}

// MARK: - Aperture iris

/// The mount control: an aperture that stops down as the hold progresses. Used
/// wherever a camera or lens is applied, so mounting feels like fitting glass
/// rather than flipping a switch.
struct IrisHoldControl: View {
    var title: String
    var workingTitle: String
    var doneTitle: String
    var hint: String = "Press and hold"
    var doneDetail: String = ""
    var holdDuration: Double = 1.0
    var isEnabled: Bool = true
    let onComplete: () -> Void

    var body: some View {
        HoldGesture(holdDuration: holdDuration,
                    isEnabled: isEnabled,
                    accessibilityTitle: title,
                    onComplete: onComplete) { phase, progress in
            row(phase: phase, progress: progress)
        }
    }

    private func row(phase: HoldPhase, progress: CGFloat) -> some View {
        HStack(spacing: 12) {
            ApertureIris(progress: phase == .idle ? 0 : progress,
                         tint: isEnabled ? Palette.accent : Palette.textDim)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(primary(phase))
                    .font(Geist.text(.body, .semibold))
                    .foregroundStyle(isEnabled ? Palette.text : Palette.textSub)
                    .lineLimit(2)

                Text(secondary(phase, progress))
                    .font(Geist.text(.subheadline))
                    .foregroundStyle(Palette.textSub)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if phase == .done {
                Image(systemName: "checkmark.circle.fill")
                    .font(Geist.text(.body))
                    .foregroundStyle(Palette.good)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: Metrics.minTap)
        .contentShape(Rectangle())
    }

    private func primary(_ phase: HoldPhase) -> String {
        switch phase {
        case .idle: return title
        case .holding: return workingTitle
        case .done: return doneTitle
        }
    }

    private func secondary(_ phase: HoldPhase, _ progress: CGFloat) -> String {
        switch phase {
        case .idle: return hint
        case .holding: return "\(Int((progress * 100).rounded()))%"
        case .done: return doneDetail
        }
    }
}

private struct ApertureIris: View {
    let progress: CGFloat
    let tint: Color

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let cx = w / 2
            let cy = h / 2
            let r = min(w, h) / 2 - 0.5
            let p = min(1, max(0, progress))

            // Open at rest, closed when the mount has been made.
            let innerR = r * (0.62 - 0.56 * p)
            let rotation = Double(p) * 140 * .pi / 180
            let sides = 6

            var blades = Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            var hole = Path()
            for i in 0..<sides {
                let angle = rotation + Double(i) / Double(sides) * 2 * .pi
                let point = CGPoint(x: cx + innerR * CGFloat(cos(angle)),
                                    y: cy + innerR * CGFloat(sin(angle)))
                if i == 0 { hole.move(to: point) } else { hole.addLine(to: point) }
            }
            hole.closeSubpath()
            blades.addPath(hole)
            ctx.fill(blades, with: .color(tint), style: FillStyle(eoFill: true))

            // Blade seams.
            for i in 0..<sides {
                let angle = rotation + Double(i) / Double(sides) * 2 * .pi
                let outer = angle + 0.55
                var seam = Path()
                seam.move(to: CGPoint(x: cx + innerR * CGFloat(cos(angle)),
                                      y: cy + innerR * CGFloat(sin(angle))))
                seam.addLine(to: CGPoint(x: cx + r * 0.98 * CGFloat(cos(outer)),
                                         y: cy + r * 0.98 * CGFloat(sin(outer))))
                ctx.stroke(seam, with: .color(Color.black.opacity(0.30)), lineWidth: 0.7)
            }
        }
    }
}
