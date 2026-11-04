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
