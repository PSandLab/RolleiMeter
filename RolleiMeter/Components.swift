import SwiftUI
import AVFoundation
import AVKit
import UIKit

private let paper = Palette.paper
private let inkColor = Palette.ink
private let mutedInk = Palette.mutedInk
private let hairline = Palette.hairline
private let accentRed = Palette.accent
private let goldenGreen = Palette.green
private let warnRed = accentRed
private let inRangeGreen = goldenGreen
private let warningAmber = Palette.amber

/// Paper panel: hairline edge, a faint light edge along the top, and a very soft shadow.
struct Panel: ViewModifier {
    var stroke: Color = Palette.hairline
    var lineWidth: CGFloat = 1

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Palette.bezelTop, Palette.paper],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(stroke, lineWidth: lineWidth))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [Palette.highlight, .clear], startPoint: .top, endPoint: .center),
                            lineWidth: 1
                        )
                        .padding(1)
                )
                .compositingGroup()
                .shadow(color: Palette.cast, radius: 4, x: 0, y: 2)
        }
    }
}

// MARK: - Depth

/// 0 below `edge0`, 1 above `edge1`, easing in between.
private func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
    guard edge1 > edge0 else { return x < edge0 ? 0 : 1 }
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}

/// A window set into the plate: a bezel that stands proud of the paper, and a floor that sinks away
/// from the light — shadow gathering under the top lip, a bright line where the bottom lip catches it.
/// Every value you turn or slide in this app lives in one of these.
private struct WindowInset: ViewModifier {
    var radius: CGFloat = 12
    var bezel: CGFloat = 5

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: max(radius - bezel, 3), style: .continuous)
                    .fill(Palette.well
                        .shadow(.inner(color: Palette.shade, radius: 4, x: 0, y: 2))
                        .shadow(.inner(color: Palette.lip, radius: 1.5, x: 0, y: -1)))
            }
            .padding(bezel)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.bezelTop, Palette.bezelBottom],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.ink.opacity(0.10), lineWidth: 1)
            }
            .compositingGroup()
            .shadow(color: Palette.cast, radius: 3, x: 0, y: 2)
    }
}

/// The small triangle that sits against the window and says "this one".
private struct PointerTriangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Camera preview

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    /// Called when a volume button is released.
    var onPress: () -> Void = {}
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onVolumePress: () -> Void = {}

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        v.backgroundColor = .black
        v.onPress = onVolumePress

        // Volume buttons act like the shutter button. The system routes them to us while the camera is in use.
        if #available(iOS 17.2, *) {
            let interaction = AVCaptureEventInteraction { [weak v] event in
                if event.phase == .ended { v?.onPress() }
            }
            interaction.isEnabled = true
            v.addInteraction(interaction)
        }
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.onPress = onVolumePress
    }
}

// MARK: - EV badge

/// A small match-needle gauge. The needle rides the same spring as the numbers, so it overshoots a touch.
private struct NeedleGauge: View {
    let ev: Double

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height - 2)
            let r = size.width / 2 - 1.5
            func point(_ angle: Double, _ len: CGFloat) -> CGPoint {
                let a = angle * .pi / 180
                return CGPoint(x: c.x + CGFloat(cos(a)) * len, y: c.y + CGFloat(sin(a)) * len)
            }
            // Ticks every 3 EV across a 110 degree arc, straight up being -90.
            for i in 0...6 {
                let angle = -90.0 - 55.0 + 110.0 * Double(i) / 6.0
                var tick = Path()
                tick.move(to: point(angle, r - 3.5))
                tick.addLine(to: point(angle, r))
                ctx.stroke(tick, with: .color(mutedInk), lineWidth: i % 2 == 0 ? 1.4 : 1)
            }
            // Keep the needle inside the engraved 0–18 EV arc so it stays aligned
            // with the end ticks instead of drifting past them at either extreme.
            let norm = min(max(ev, 0), 18) / 18.0
            let needleAngle = -145.0 + 110.0 * norm
            var needle = Path()
            needle.move(to: c)
            needle.addLine(to: point(needleAngle, r - 1))
            ctx.stroke(needle, with: .color(accentRed), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)), with: .color(inkColor))
        }
        .frame(width: 34, height: 19)
        .accessibilityHidden(true)
    }
}

struct EVBadge: View {
    @ObservedObject var damp: Damper
    let frozen: Bool
    let spot: Bool

    private var evText: String { String(format: "%.1f", damp.values[0]) }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            NeedleGauge(ev: damp.values[0])
            if frozen {
                Text("HOLD")
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            if spot {
                Text("SPOT")
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Text("EV " + evText)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(AppTypography.font(size: 13, weight: .medium))
        .foregroundStyle(inkColor)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: frozen)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: spot)
    }
}

// MARK: - Simple exposure and focus

private struct SimpleApertureColumn: View {
    let damp: Damper
    let iso: Double
    let comp: Double
    let aperture: (label: String, n: Double)

    private var idealTime: Double {
        Exposure.idealShutter(ev100: damp.values[0], iso: iso, comp: comp, n: aperture.n)
    }
    private var reading: ShutterResult { Exposure.result(for: idealTime) }
    private var exposureStatus: String {
        guard let deviation = reading.deviation else { return reading.isSlow ? "SLOW · HOLD STEADY" : "" }
        return deviation > 0 ? "OVEREXPOSED" : "UNDEREXPOSED"
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("SHUTTER")
                .font(AppTypography.next(size: 12, weight: .medium))
                .tracking(0.9)
                .foregroundStyle(paper)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 10)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                if reading.deviation == nil {
                    Text("1/")
                        .font(AppTypography.mono(size: 30, weight: .medium))
                        .foregroundStyle(paper.opacity(0.78))
                }
                Text(reading.deviation.map(Fmt.exposureAmount) ?? reading.label)
                    .font(AppTypography.bold(size: 80))
                    .monospacedDigit()
                    .foregroundStyle(paper)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .animation(.smooth(duration: 0.18), value: reading.deviation.map(Fmt.exposureAmount) ?? reading.label)
            Text(exposureStatus)
                .font(AppTypography.next(size: 10, weight: .medium))
                .tracking(0.7)
                .foregroundStyle(paper)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .frame(height: 12)
                .accessibilityHidden(exposureStatus.isEmpty)
            Spacer(minLength: 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 174, maxHeight: 174)
        .background(outOfRange ? accentRed : (slow ? warningAmber : inRangeGreen))
    }

    private var outOfRange: Bool { reading.deviation != nil }

    /// Correct exposure, but slower than the hand-holdable line. Amber, not red: nothing is wrong
    /// with the exposure, only with your chances of holding it still.
    private var slow: Bool { reading.deviation == nil && reading.isSlow }
}

struct SimpleExposurePair: View {
    @ObservedObject var damp: Damper
    let iso: Double
    let comp: Double
    let apertureIndex: Int
    let distance: Double?
    let tooClose: Bool
    let feet: Bool

    private var activeAperture: (label: String, n: Double) {
        Rollei.stops[apertureIndex]
    }

    var body: some View {
        HStack(spacing: 0) {
            SimpleApertureColumn(damp: damp, iso: iso, comp: comp, aperture: activeAperture)
            Rectangle().fill(hairline).frame(width: 1).padding(.vertical, 8)
            SimpleFocusColumn(
                distance: distance,
                aperture: activeAperture,
                tooClose: tooClose,
                feet: feet
            )
        }
        .background(paper)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .compositingGroup()
        .shadow(color: Palette.cast, radius: 4, x: 0, y: 2)
    }
}

private struct SimpleFocusColumn: View {
    let distance: Double?
    let aperture: (label: String, n: Double)
    let tooClose: Bool
    let feet: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Image(systemName: "scope").font(.system(size: 16, weight: .regular))
                Text("FOCUS").font(AppTypography.next(size: 12, weight: .medium)).tracking(0.9)
                Spacer(minLength: 0)
            }
            .foregroundStyle(mutedInk)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if tooClose {
                Text("0")
                    .font(AppTypography.bold(size: 68))
                    .foregroundStyle(warnRed)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let distance {
                FocusRingScale(distance: distance, aperture: aperture, feet: feet)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("NO LIDAR")
                    .font(AppTypography.next(size: 11, weight: .medium))
                    .tracking(0.7)
                    .foregroundStyle(mutedInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 174, maxHeight: 174)
        .clipped()
        .background(paper)
        .accessibilityElement(children: .contain)
    }
}

/// A straight focus scale. The pointer is fixed at the top; the ruler slides beneath it. Only the marks near the pointer are numbered (left / middle / right).
private struct FocusRingScale: View {
    let distance: Double
    let aperture: (label: String, n: Double)
    let feet: Bool

    private var marks: [(label: String, m: Double)] {
        feet ? Focus.feetMarks : Focus.meterMarks
    }

    private var depthRange: (near: Double, far: Double) {
        DepthOfField.range(subject: distance, n: aperture.n)
    }

    private var recommendedFocus: String {
        let advice = Focus.advice(subject: distance, aperture: aperture.n, feet: feet)
        return advice.sharp ? advice.label : "between \(advice.lo) and \(advice.hi)"
    }

    var body: some View {
        FocusDialFace(
            position: Focus.position(distance),
            near: Focus.position(depthRange.near),
            far: Focus.position(depthRange.far),
            sharpLabel: Focus.advice(subject: distance, aperture: aperture.n, feet: feet).sharp
                ? Focus.advice(subject: distance, aperture: aperture.n, feet: feet).label : nil,
            marks: marks.map { (label: $0.label, p: Focus.position($0.m)) }
        )
        .animation(.spring(response: 0.38, dampingFraction: 0.84), value: distance)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus ring. Set \(recommendedFocus). Depth of field at f/\(aperture.label).")
    }
}

private struct FocusDialFace: View, Animatable {
    var position: Double
    var near: Double
    var far: Double
    let sharpLabel: String?
    let marks: [(label: String, p: Double)]

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(position, AnimatablePair(near, far)) }
        set {
            position = newValue.first
            near = newValue.second.first
            far = newValue.second.second
        }
    }

    var body: some View {
        Canvas { context, size in
            drawDial(&context, size)
        }
        .clipped()
    }

    /// Points of travel per unit of focus ring. A shallow depth of field zooms in on a few ticks, a deep one
    /// pulls out to show more numbers. It is capped so the nearest engraved number is always in view, and it
    /// depends only on the depth of field, never on where the pointer sits, so it doesn't pump while you move.
    private func zoom(width: CGFloat) -> CGFloat {
        let span = max(far - near, 0.01)
        let wanted: CGFloat = width / CGFloat(span * 1.8)
        let clamped: CGFloat = min(max(wanted, 380), 1400)
        let cap: CGFloat = width * 2.3
        return min(clamped, cap)
    }

    private func drawDial(_ context: inout GraphicsContext, _ size: CGSize) {
        let cx: CGFloat = size.width / 2
        // Pointer, number and ticks stacked as one group, centred in the tile.
        let groupHeight: CGFloat = 104
        let y0: CGFloat = max(0, (size.height - groupHeight) / 2)
        let numberY: CGFloat = y0 + 30
        let markTop: CGFloat = y0 + 50
        let baseline: CGFloat = y0 + 92
        let fadeWidth: CGFloat = 44
        let ppu: CGFloat = zoom(width: size.width)
        // Fine ticks thin out as they get crowded; the longer ones always stay.
        let fineRaw: CGFloat = (ppu / 60 - 4) / 3
        let fine: Double = Double(min(max(fineRaw, 0), 1))

        func x(_ p: Double) -> CGFloat {
            return cx + CGFloat(p - position) * ppu
        }
        func fade(_ px: CGFloat) -> Double {
            let edge: CGFloat = min(px, size.width - px)
            return Double(min(max(edge / fadeWidth, 0), 1))
        }

        // Ticks rise from the baseline: fine, every 5th taller, engraved marks tallest.
        let markPositions: [Double] = marks.map { $0.p }
        for i in 0...60 {
            let p: Double = Double(i) / 60.0
            if markPositions.contains(where: { abs($0 - p) < 0.003 }) { continue }
            let major: Bool = i % 5 == 0
            let strength: Double = major ? 1.0 : fine
            if strength <= 0 { continue }
            let px: CGFloat = x(p)
            let f: Double = fade(px)
            if f <= 0 { continue }
            let h: CGFloat = major ? 28 : 18
            var tick = Path()
            tick.move(to: CGPoint(x: px, y: baseline))
            tick.addLine(to: CGPoint(x: px, y: baseline - h))
            context.stroke(tick, with: .color(mutedInk.opacity(f * strength)), lineWidth: 1.5)
        }

        for mark in marks {
            let px: CGFloat = x(mark.p)
            let f: Double = fade(px)
            if f <= 0 { continue }
            let green: Bool = mark.label == sharpLabel
            let color: Color = green ? goldenGreen : inkColor
            var tick = Path()
            tick.move(to: CGPoint(x: px, y: baseline))
            tick.addLine(to: CGPoint(x: px, y: markTop))
            context.stroke(tick, with: .color(color.opacity(f)), lineWidth: green ? 3 : 2.5)
            // The mark under the pointer grows a little, like a detent.
            let underPointer: Bool = abs(mark.p - position) < 0.012
            let label = Text(mark.label)
                .font(AppTypography.bold(size: underPointer ? 29 : 24))
                .foregroundColor(color.opacity(f))
            let text = context.resolve(label)
            context.draw(text, at: CGPoint(x: px, y: numberY), anchor: .center)
        }

        // Fixed pointer
        var tri = Path()
        tri.move(to: CGPoint(x: cx - 7, y: y0))
        tri.addLine(to: CGPoint(x: cx + 7, y: y0))
        tri.addLine(to: CGPoint(x: cx, y: y0 + 11))
        tri.closeSubpath()
        context.fill(tri, with: .color(accentRed))
    }
}

// MARK: - Scrub dial

/// A window of engraved values. Drag it up or down and the strip turns through the window: the value
/// under the pointer darkens and swells while its neighbours shrink and fade towards the rim, so you
/// watch one number become the next instead of seeing it replaced.
struct ScrubDial: View {
    let title: String
    @Binding var selection: Int
    let labels: [String]
    /// The "home" value (0 compensation, ISO 100). Landing on it clicks harder; double-tap returns to it.
    var resetIndex: Int? = nil

    /// Points of travel between two neighbouring values.
    private let row: CGFloat = 15.5
    /// Height of the glass, inside the bezel.
    private let face: CGFloat = 78

    @State private var base: Int?
    @State private var drag: CGFloat = 0

    private var safeSelection: Int { min(max(selection, 0), max(labels.count - 1, 0)) }

    /// Fractional index under the pointer. Follows the finger exactly while dragging.
    private var position: Double {
        guard let base else { return Double(safeSelection) }
        return min(max(Double(base) - Double(drag / row), 0), Double(max(labels.count - 1, 0)))
    }

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(AppTypography.next(size: 10, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(mutedInk)

            ValueRail(position: position, labels: labels, row: row)
                .frame(maxWidth: .infinity)
                .frame(height: face)
                .overlay(alignment: .trailing) {
                    PointerTriangle()
                        .fill(accentRed)
                        .frame(width: 7, height: 11)
                        .padding(.trailing, 7)
                }
                .modifier(WindowInset(radius: 14, bezel: 5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if base == nil { base = safeSelection }
                    drag = value.translation.height
                    let index = Int(position.rounded())
                    if index != selection {
                        selection = index
                        if index == resetIndex {
                            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
                        } else {
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        base = nil
                        drag = 0
                    }
                }
        )
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                guard let resetIndex, selection != resetIndex else { return }
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { selection = resetIndex }
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(labels.isEmpty ? "" : labels[safeSelection])
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: selection = min(selection + 1, labels.count - 1)
            case .decrement: selection = max(selection - 1, 0)
            @unknown default: break
            }
        }
    }
}

/// The strip of values drawn inside a window. Everything is one piece: the number at the centre of
/// the window is the same drawing as the numbers above and below it, only closer to the light.
private struct ValueRail: View, Animatable {
    var position: Double
    let labels: [String]
    let row: CGFloat

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let midY = size.height / 2
            let half = max(size.height / 2, 1)
            for i in labels.indices {
                let d = CGFloat(Double(i) - position)
                let y = midY + d * row
                if y < -row || y > size.height + row { continue }
                // Distance from the middle of the window, 0 at the pointer and 1 at the rim.
                let r = min(abs(d * row) / half, 1.3)
                let rim = 1 - smoothstep(0.70, 1.05, r)
                if rim <= 0.02 { continue }
                let near = 1 - smoothstep(0, 0.9, r)
                let text = Text(labels[i])
                    .font(AppTypography.mono(size: 16.5, weight: .bold))
                    .foregroundColor(inkColor.opacity(rim * (0.34 + 0.66 * near)))
                var sub = ctx
                sub.translateBy(x: cx, y: y)
                sub.scaleBy(x: 1 - 0.22 * smoothstep(0, 0.95, r), y: 1 - 0.22 * smoothstep(0, 0.95, r))
                sub.draw(ctx.resolve(text), at: .zero, anchor: .center)
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Paper keys (the square buttons beside the shutter)

/// A key standing off the plate: lit along its top-left edge, casting a soft shadow underneath.
/// Pressed, it loses the light and sinks a little.
struct PaperKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(
                        colors: configuration.isPressed
                            ? [Palette.bezelBottom, Palette.paper]
                            : [Palette.bezelTop, Palette.bezelBottom],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .compositingGroup()
                    .shadow(color: Palette.cast,
                            radius: configuration.isPressed ? 1 : 3,
                            x: 0, y: configuration.isPressed ? 0.5 : 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.ink.opacity(0.10), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// A word-shaped key. Braun labels are printed words on the panel, not pictograms.
struct SetKeyStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(
                            colors: configuration.isPressed
                                ? [Palette.bezelBottom, Palette.paper]
                                : [Palette.bezelTop, Palette.bezelBottom],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.ink)
                        .opacity(active ? 1 : 0)
                }
                .compositingGroup()
                .shadow(color: Palette.cast,
                        radius: active ? 1 : 3,
                        x: 0, y: active ? 0.5 : 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.ink.opacity(active ? 0 : 0.10), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.2), value: active)
    }
}

// MARK: - Aperture drum

/// What the auto light is saying.
enum AutoLampState {
    case off, good, slow, bad
}

/// The LED beside the drum. Green while the ring has room to work, amber when it is pinned wide
/// open and the shutter has slipped past the hand-holdable line, red when even f/22 can't save it.
struct AutoLamp: View {
    let state: AutoLampState

    private var color: Color {
        switch state {
        case .off: return Color.clear
        case .good: return Palette.green
        case .slow: return Palette.amber
        case .bad: return Palette.accent
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.55), radius: 3)
            Text("A")
                .font(AppTypography.next(size: 8, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(state == .off ? Color.clear : Palette.mutedInk)
        }
        .frame(width: 16, alignment: .trailing)
        .opacity(state == .off ? 0 : 1)
        .animation(.easeOut(duration: 0.18), value: state)
        .accessibilityHidden(true)
    }
}

/// The vertical aperture wheel in the bottom-right corner. The chosen stop sits in a fixed window
/// and the strip turns behind it. Tap hands the aperture to the meter; a drag takes it back.
struct ApertureDrum: View {
    /// The stop the app wants shown: your choice, or auto's answer.
    let index: Int
    let auto: Bool
    /// A stop picked by hand. Always leaves auto.
    let onPick: (Int) -> Void
    let onTap: () -> Void
    /// Long press: back to f/8.
    let onHome: () -> Void

    private let width: CGFloat = 60
    private let height: CGFloat = 84
    /// Thickness of the bezel around the glass.
    private let bezel: CGFloat = 4
    /// Points of finger travel per stop.
    private let pitch: CGFloat = 22
    private let homeIndex = 3

    @State private var position: Double = 0
    @State private var base: Double?
    @State private var moved = false
    @State private var longPressFired = false
    @State private var pressToken = 0
    @State private var lastDetent = -1

    private var stopCount: Int { Rollei.stops.count }
    private var nearest: Int { min(max(Int(position.rounded()), 0), stopCount - 1) }

    var body: some View {
        DrumFace(position: position, pitch: pitch)
            .frame(width: width - bezel * 2, height: height - bezel * 2)
            .modifier(WindowInset(radius: 11, bezel: bezel))
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .gesture(dragGesture)
            .onAppear {
                position = Double(index)
                lastDetent = index
            }
            .onChange(of: index) { newValue in
                guard base == nil else { return }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                    position = Double(newValue)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Aperture")
            .accessibilityValue("f/" + Rollei.stops[nearest].label + (auto ? ", auto" : ", manual"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onPick(min(nearest + 1, stopCount - 1))
                case .decrement: onPick(max(nearest - 1, 0))
                @unknown default: break
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if base == nil {
                    base = position
                    moved = false
                    longPressFired = false
                    scheduleHome()
                }
                guard !longPressFired else { return }
                if !moved && abs(value.translation.height) > 4 {
                    moved = true
                    pressToken += 1      // the finger is scrolling, not holding
                }
                guard moved, let start = base else { return }
                position = rubber(start - Double(value.translation.height / pitch))
                detent()
            }
            .onEnded { value in
                pressToken += 1
                let start = base ?? position
                let wasMoved = moved
                let fired = longPressFired
                base = nil
                moved = false
                longPressFired = false

                if fired { return }
                if !wasMoved {
                    onTap()
                    return
                }
                let predicted = start - Double(value.predictedEndTranslation.height / pitch)
                let target = Double(min(max(Int(rubber(predicted).rounded()), 0), stopCount - 1))
                withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) { position = target }
                detent()
                onPick(Int(target))
            }
    }

    /// Past either end the drum stretches a little and springs back.
    private func rubber(_ v: Double) -> Double {
        let lo = 0.0
        let hi = Double(stopCount - 1)
        if v < lo { return max(lo - 0.35, lo - (lo - v) * 0.3) }
        if v > hi { return min(hi + 0.35, hi + (v - hi) * 0.3) }
        return v
    }

    private func detent() {
        let stop = nearest
        guard stop != lastDetent else { return }
        lastDetent = stop
        if stop == homeIndex {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
        } else {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    /// Held still for a moment: the ring goes home to f/8.
    private func scheduleHome() {
        pressToken += 1
        let token = pressToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard token == pressToken, base != nil, !moved else { return }
            longPressFired = true
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                position = Double(homeIndex)
            }
            lastDetent = homeIndex
            onHome()
        }
    }
}

/// The ring of stops turning behind the window. Every stop is drawn the same way; the one at the
/// pointer is simply nearer the light and a little larger, so a drag reads as the ring turning and
/// not as one number being swapped for another.
private struct DrumFace: View, Animatable {
    var position: Double
    let pitch: CGFloat

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let midY = size.height / 2
            let half = max(size.height / 2, 1)
            for i in Rollei.stops.indices {
                let d = CGFloat(Double(i) - position)
                let y = midY + d * pitch
                if y < -pitch || y > size.height + pitch { continue }
                let r = min(abs(d * pitch) / half, 1.3)
                let rim = 1 - smoothstep(0.68, 1.02, r)
                if rim <= 0.02 { continue }
                let near = 1 - smoothstep(0, 0.95, r)
                let text = Text(Rollei.stops[i].label)
                    .font(AppTypography.bold(size: 20))
                    .foregroundColor(inkColor.opacity(rim * (0.34 + 0.66 * near)))
                let scale = 1 - 0.26 * smoothstep(0, 0.98, r)
                var sub = ctx
                sub.translateBy(x: cx, y: y)
                sub.scaleBy(x: scale, y: scale)
                sub.draw(ctx.resolve(text), at: .zero, anchor: .center)
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Metering mode drawn as a tiny sensor: a frame with a grid of weighted dots.
/// Matrix: all cells, centre weighted. Highlight: one bright cell. Spot: a single ring.
struct ModeGlyph: View {
    let mode: MeterMode

    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 22
            let box = CGRect(x: (size.width - s) / 2, y: (size.height - s) / 2, width: s, height: s)
            ctx.stroke(Path(roundedRect: box, cornerRadius: 4), with: .color(inkColor.opacity(0.78)), lineWidth: 1.3)

            func dot(_ col: Int, _ row: Int, _ r: CGFloat, _ color: Color) {
                let c = CGPoint(x: box.minX + s * (0.25 + 0.25 * CGFloat(col)), y: box.minY + s * (0.25 + 0.25 * CGFloat(row)))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color))
            }

            switch mode {
            case .matrix:
                for row in 0..<3 {
                    for col in 0..<3 {
                        let centre = row == 1 && col == 1
                        dot(col, row, centre ? 2.4 : 1.3, inkColor.opacity(0.78))
                    }
                }
            case .highlight:
                for row in 0..<3 {
                    for col in 0..<3 where !(row == 0 && col == 2) {
                        dot(col, row, 1.3, inkColor.opacity(0.4))
                    }
                }
                dot(2, 0, 2.8, accentRed)
            case .spot:
                let c = CGPoint(x: box.midX, y: box.midY)
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 4.6, y: c.y - 4.6, width: 9.2, height: 9.2)),
                           with: .color(inkColor.opacity(0.78)), lineWidth: 1.3)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 1.3, y: c.y - 1.3, width: 2.6, height: 2.6)),
                         with: .color(accentRed))
            }
        }
        .frame(width: 46, height: 46)
        .accessibilityHidden(true)
    }
}

// MARK: - Freeze button

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

struct FreezeButton: View {
    let frozen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Palette.bezelTop, Palette.bezelBottom],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 84, height: 84)
                    .shadow(color: Palette.cast, radius: 4, x: 0, y: 2)
                Circle().fill(hairline).frame(width: 68, height: 68)
                Circle()
                    .fill(paper.shadow(.inner(color: Palette.shade, radius: 3, x: 0, y: 2)))
                    .frame(width: 68, height: 68)
                    .scaleEffect(frozen ? 0.96 : 1)
                Circle()
                    .stroke(frozen ? accentRed : mutedInk, lineWidth: frozen ? 4 : 1)
                    .frame(width: 68, height: 68)
                    .scaleEffect(frozen ? 0.96 : 1)
                Image(systemName: frozen ? "pause.fill" : "viewfinder")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(frozen ? accentRed : mutedInk)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: frozen)
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - LiDAR marker (on the viewfinder)

private struct FocusBrackets: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let l = r.width * 0.3
        p.move(to: CGPoint(x: r.minX, y: r.minY + l)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}

/// A short, expanding ring confirms a new focus point without obscuring the camera image.
private struct FocusPing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    let tooClose: Bool

    var body: some View {
        Circle()
            .stroke(tooClose ? warnRed : Palette.lensLight, lineWidth: 1)
            .frame(width: 30, height: 30)
            .scaleEffect(expanded ? 1.8 : 0.45)
            .opacity(expanded ? 0 : 0.7)
            .onAppear {
                if reduceMotion {
                    expanded = true
                } else {
                    withAnimation(.easeOut(duration: 0.48)) { expanded = true }
                }
            }
            .accessibilityHidden(true)
    }
}

/// Shows the LiDAR focus point as a clean cursor on the viewfinder.
struct FocusMarker: View {
    let tooClose: Bool
    var pulseID: Int = 0

    var body: some View {
        ZStack {
            if pulseID > 0 {
                FocusPing(tooClose: tooClose).id(pulseID)
            }
            FocusBrackets()
                .stroke(tooClose ? warnRed : Palette.lensLight,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 30, height: 30)
                .scaleEffect(tooClose ? 0.88 : 1)
            Circle()
                .fill(tooClose ? warnRed : Palette.lensLight)
                .frame(width: 3, height: 3)
        }
        .frame(width: 30, height: 30)
        .animation(.spring(response: 0.28, dampingFraction: 0.64), value: tooClose)
        .allowsHitTesting(false)
    }
}
