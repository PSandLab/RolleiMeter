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

/// Paper panel: hairline edge, a faint light edge along the top, and a very soft shadow.
struct Panel: ViewModifier {
    var stroke: Color = Palette.hairline
    var lineWidth: CGFloat = 1

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.paper)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(stroke, lineWidth: lineWidth))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [Palette.highlight, .clear], startPoint: .top, endPoint: .center),
                            lineWidth: 1
                        )
                        .padding(1)
                )
                .shadow(color: Palette.lensDark.opacity(0.07), radius: 3, y: 1)
        }
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
                .contentTransition(.numericText())
        }
        .font(AppTypography.font(size: 13, weight: .medium))
        .foregroundStyle(inkColor)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: frozen)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: spot)
    }
}

// MARK: - Aperture / shutter ruler

/// Full aperture range with shutter readings, fine index ticks, and a fixed-height aperture label row.
struct RulerView: View {
    @ObservedObject var damp: Damper
    let iso: Double
    let comp: Double
    let golden: Int
    let selected: Int
    let onSelect: (Int) -> Void
    let onToggleGolden: (Int) -> Void

    @Namespace private var indexNamespace

    private var results: [ShutterResult] {
        Rollei.stops.map {
            Exposure.result(for: Exposure.idealShutter(ev100: damp.values[0], iso: iso, comp: comp, n: $0.n))
        }
    }

    var body: some View {
        let res = results
        VStack(spacing: 2) {
            // Shutter speed readings use only native Rollei markings.
            HStack(spacing: 0) {
                ForEach(Rollei.stops.indices, id: \.self) { i in
                    let r = res[i]
                    Text(r.deviation.map(Fmt.exposureAmount) ?? r.label)
                        .font(AppTypography.font(size: r.deviation == nil ? 16 : 11, weight: i == golden ? .semibold : .medium))
                        .foregroundStyle(shutterColor(r, golden: i == golden))
                        .contentTransition(.numericText())
                        .frame(maxWidth: .infinity)
                        .background {
                            // Pale band behind every aperture that gives a correct exposure right now.
                            Rectangle()
                                .fill(goldenGreen.opacity(r.deviation == nil ? 0.12 : 0))
                                .padding(.vertical, -1)
                        }
                        .animation(.smooth(duration: 0.25), value: r.deviation == nil)
                        .minimumScaleFactor(0.7)
                        .animation(.smooth(duration: 0.2), value: r.deviation.map(Fmt.exposureAmount) ?? r.label)
                }
            }

            HStack(spacing: 0) {
                ForEach(Rollei.stops.indices, id: \.self) { _ in
                    ZStack {
                        Rectangle().fill(hairline).frame(height: 1)
                        Rectangle().fill(mutedInk).frame(width: 1.5, height: 8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Apertures. Tap selects (drives the depth-of-field band), long-press sets the golden one.
            HStack(spacing: 0) {
                ForEach(Rollei.stops.indices, id: \.self) { i in
                    Text("f/" + Rollei.stops[i].label)
                        .font(AppTypography.font(size: 11, weight: i == golden ? .semibold : .regular))
                        .foregroundStyle(i == golden ? goldenGreen : inkColor)
                        .frame(height: 22)
                        .overlay(alignment: .bottom) {
                            if selected == i {
                                Rectangle()
                                    .fill(inkColor)
                                    .frame(height: 1.5)
                                    .matchedGeometryEffect(id: "apertureIndex", in: indexNamespace)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(i) }
                        .onLongPressGesture(minimumDuration: 0.5) {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            onToggleGolden(i)
                        }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selected)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .modifier(Panel())
    }

    /// Orange-red for out of range, a warning tint for readings slower than 1/60 s, green for the golden aperture.
    private func shutterColor(_ r: ShutterResult, golden: Bool) -> Color {
        if r.deviation != nil { return accentRed }
        if r.isSlow { return accentRed.opacity(0.75) }
        return golden ? goldenGreen : inkColor
    }
}

// MARK: - Simple exposure and focus

private struct SimpleApertureColumn: View {
    let damp: Damper
    let iso: Double
    let comp: Double
    let aperture: (label: String, n: Double)
    let symbol: String
    let onSelect: () -> Void

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
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .regular))
                Text("f/" + aperture.label)
                    .font(AppTypography.font(size: 15, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(paper)
            Spacer(minLength: 10)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                if reading.deviation == nil {
                    Text("1/")
                        .font(AppTypography.mono(size: 30, weight: .medium))
                        .foregroundStyle(paper.opacity(0.78))
                }
                Text(reading.deviation.map(Fmt.exposureAmount) ?? reading.label)
                    .font(AppTypography.bold(size: 80))
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
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .background(outOfRange ? accentRed : inRangeGreen)
    }

    private var outOfRange: Bool { reading.deviation != nil }
}

struct SimpleExposurePair: View {
    @ObservedObject var damp: Damper
    let iso: Double
    let comp: Double
    let apertureIndex: Int
    let distance: Double?
    let tooClose: Bool
    let feet: Bool
    let onToggleAperture: () -> Void

    private var activeAperture: (label: String, n: Double) {
        Rollei.stops[apertureIndex]
    }

    var body: some View {
        HStack(spacing: 0) {
            SimpleApertureColumn(damp: damp, iso: iso, comp: comp, aperture: activeAperture, symbol: "camera.aperture", onSelect: onToggleAperture)
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

/// How strongly a point on the focus scale reads as "inside the depth of field".
/// 1 inside, easing to 0 just outside. Marks and ticks are drawn darker inside and recede outside,
/// so depth of field shows as weight, with no extra lines or brackets.
private enum DepthShade {
    static func weight(_ p: Double, near: Double, far: Double) -> Double {
        let ease = 0.012
        let lo = min(1, max(0, (p - near) / ease + 1))
        let hi = min(1, max(0, (far - p) / ease + 1))
        return lo * hi
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
            let cx = size.width / 2
            // Scale the ruler to the depth-of-field span: wider at small apertures,
            // tighter at large apertures, while keeping the focused distance centered.
            let depthSpan = max(far - near, 0.015)
            let pointsPerUnit = CGFloat(min(max(Double(size.width) * 0.72 / depthSpan, 180), 1400))
            // Pointer, number and ticks stacked as one group, centred in the tile.
            let groupHeight: CGFloat = 104
            let y0 = max(0, (size.height - groupHeight) / 2)
            let numberY = y0 + 30
            let markTop = y0 + 50
            let baseline = y0 + 92
            let fadeWidth: CGFloat = 44

            func x(_ p: Double) -> CGFloat { cx + CGFloat(p - position) * pointsPerUnit }
            func fade(_ x: CGFloat) -> Double {
                let edge = min(x, size.width - x)
                return Double(min(1, max(0, edge / fadeWidth)))
            }

            // Ticks rise from the baseline: fine, every 5th taller, engraved marks tallest.
            let markPositions = marks.map { $0.p }
            let n = 60
            for i in 0...n {
                let p = Double(i) / Double(n)
                if markPositions.contains(where: { abs($0 - p) < 0.003 }) { continue }
                let px = x(p)
                let f = fade(px)
                if f <= 0 { continue }
                let h: CGFloat = i.isMultiple(of: 5) ? 28 : 18
                var tick = Path()
                tick.move(to: CGPoint(x: px, y: baseline))
                tick.addLine(to: CGPoint(x: px, y: baseline - h))
                context.stroke(tick, with: .color(inkColor.opacity(f * 0.78)), lineWidth: 1.5)
            }
            for mark in marks {
                let px = x(mark.p)
                let f = fade(px)
                if f <= 0 { continue }
                let color = inkColor
                let a = f * 0.78
                var tick = Path()
                tick.move(to: CGPoint(x: px, y: baseline))
                tick.addLine(to: CGPoint(x: px, y: markTop))
                context.stroke(tick, with: .color(color.opacity(a)), lineWidth: 2.5)
                // The mark under the pointer grows a little, like a detent.
                let underPointer = abs(mark.p - position) < 0.012
                let text = context.resolve(
                    Text(mark.label)
                        .font(AppTypography.bold(size: underPointer ? 29 : 24))
                        .foregroundColor(color.opacity(a))
                )
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
        .clipped()
    }
}

/// Lens marks with a small downward index showing the interval to set between.
private struct FocusRangeIndicator: View {
    let lo: String
    let hi: String
    let fontSize: CGFloat

    var body: some View {
        HStack(spacing: 2) {
            Text(lo)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: max(9, fontSize * 0.32), weight: .semibold))
                .foregroundStyle(accentRed)
                .frame(width: max(13, fontSize * 0.42))
            Text(hi)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(AppTypography.bold(size: fontSize))
        .foregroundStyle(inkColor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus between \(lo) and \(hi)")
    }
}

// MARK: - Scrub dial

/// A horizontal ruler you drag under a fixed pointer. One haptic tick per step.
struct ScrubDial: View {
    let title: String
    @Binding var selection: Int
    let labels: [String]
    /// The "home" value (0 compensation, ISO 100). Landing on it clicks harder; double-tap returns to it.
    var resetIndex: Int? = nil

    private let spacing: CGFloat = 15
    @State private var base: Int?
    @State private var drag: CGFloat = 0

    private var safeSelection: Int { min(max(selection, 0), max(labels.count - 1, 0)) }

    /// Fractional index under the pointer. Follows the finger while dragging.
    private var position: Double {
        guard let base else { return Double(safeSelection) }
        return min(max(Double(base) - Double(drag / spacing), 0), Double(max(labels.count - 1, 0)))
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(AppTypography.next(size: 10, weight: .medium))
                .tracking(1)
                .foregroundStyle(mutedInk)
            Text(labels.isEmpty ? "" : labels[safeSelection])
                .font(AppTypography.bold(size: 28))
                .foregroundStyle(inkColor)
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.15), value: selection)
            DialFace(position: position, count: labels.count, spacing: spacing, home: resetIndex)
                .frame(height: 30)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if base == nil { base = safeSelection }
                    drag = value.translation.width
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
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
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

private struct DialFace: View, Animatable {
    var position: Double
    let count: Int
    let spacing: CGFloat
    var home: Int? = nil

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let cx = size.width / 2
            for i in 0..<count {
                let x = cx + CGFloat(Double(i) - position) * spacing
                let fade = Double(min(1, max(0, min(x, size.width - x) / 30)))
                if fade <= 0 { continue }
                // Third-stop steps: every third tick is a full stop.
                let major = i % 3 == 0
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: size.height))
                tick.addLine(to: CGPoint(x: x, y: size.height - (major ? 17 : 9)))
                let isHome = i == home
                context.stroke(tick, with: .color((isHome ? inkColor : mutedInk).opacity(fade)),
                               lineWidth: isHome ? 2.4 : (major ? 1.8 : 1.2))
            }
            var pointer = Path()
            pointer.move(to: CGPoint(x: cx - 5, y: 0))
            pointer.addLine(to: CGPoint(x: cx + 5, y: 0))
            pointer.addLine(to: CGPoint(x: cx, y: 8))
            pointer.closeSubpath()
            context.fill(pointer, with: .color(accentRed))
        }
    }
}

// MARK: - Paper keys (the square buttons beside the shutter)

struct PaperKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(configuration.isPressed ? Palette.hairline : Palette.paper)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Palette.ink.opacity(0.16), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
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
                Circle().fill(hairline).frame(width: 84, height: 84)
                Circle()
                    .fill(paper)
                    .frame(width: 68, height: 68)
                    .scaleEffect(frozen ? 0.96 : 1)
                Circle()
                    .stroke(frozen ? accentRed : mutedInk, lineWidth: frozen ? 4 : 1)
                    .frame(width: 68, height: 68)
                    .scaleEffect(frozen ? 0.96 : 1)
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

/// Shows the LiDAR focus point as a clean cursor on the viewfinder.
struct FocusMarker: View {
    let tooClose: Bool

    var body: some View {
        FocusBrackets()
            .stroke(tooClose ? warnRed : Palette.lensLight,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .frame(width: 30, height: 30)
            .animation(.smooth(duration: 0.2), value: tooClose)
            .allowsHitTesting(false)
    }
}

// MARK: - Focus panel

/// Compact by default: the nearest mark on the Rollei's focus ring for the measured distance.
/// Tap it to open the full scale; marks inside the depth of field stay dark.
struct FocusPanel: View {
    /// Channels: subject, near limit, far limit. All are 0...1 positions on the scale.
    @ObservedObject var damp: Damper
    let distance: Double?
    let near: Double?
    let far: Double?
    let advice: FocusAdvice?
    let tooClose: Bool
    let feet: Bool
    let aperture: String
    let showsAperturePicker: Bool
    @Binding var expanded: Bool
    let onToggleUnits: () -> Void
    let onSelectAperture: (Int) -> Void
    /// False: the compact summary row that sits in the layout.
    /// True: the full scale as a card, shown floating over the viewfinder so the layout never moves.
    var card: Bool = false

    private var marks: [(label: String, m: Double)] { feet ? Focus.feetMarks : Focus.meterMarks }
    private var unit: String { feet ? "ft" : "m" }

    var body: some View {
        if card {
            scale
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .modifier(Panel(stroke: tooClose ? warnRed : hairline, lineWidth: tooClose ? 1.5 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onTapGesture {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { expanded = false }
                }
        } else {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { expanded.toggle() }
            } label: {
                summary
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .modifier(Panel(stroke: tooClose ? warnRed : hairline, lineWidth: tooClose ? 1.5 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .animation(.smooth(duration: 0.25), value: tooClose)
        }
    }

    // MARK: summary row

    private var bigText: String {
        guard let a = advice else { return "—" }
        if !a.sharp { return "BETWEEN " + a.lo + "–" + a.hi + " " + unit.uppercased() }
        return a.label == "∞" ? "∞" : a.label + " " + unit
    }

    private var detailText: String {
        if tooClose {
            return "MIN " + (feet ? "3 FT" : "0.9 M")
        }
        guard let d = distance, let advice else { return "—" }
        if advice.sharp { return Fmt.distance(d, feet: feet) + " · SHARP" }
        return "SUBJECT " + Fmt.distance(d, feet: feet).uppercased()
    }

    private var detailColor: Color {
        if tooClose { return warnRed }
        guard let advice else { return mutedInk }
        return advice.sharp ? goldenGreen : accentRed
    }

    private var summary: some View {
        HStack(alignment: .lastTextBaseline, spacing: 5) {
            Text("FOCUS")
                .font(AppTypography.next(size: 9, weight: .medium))
                .tracking(1)
                .foregroundStyle(mutedInk)
            if !tooClose, let advice, !advice.sharp {
                FocusRangeIndicator(lo: advice.lo, hi: advice.hi, fontSize: 17)
            } else {
                Text(tooClose ? "TOO CLOSE" : bigText)
                    .font(AppTypography.font(size: tooClose ? 14 : 20, weight: .medium))
                    .foregroundStyle(tooClose ? warnRed : (advice == nil ? mutedInk : inkColor))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 2)
            if showsAperturePicker {
                Menu {
                    ForEach(Rollei.stops.indices, id: \.self) { index in
                        Button("f/" + Rollei.stops[index].label) { onSelectAperture(index) }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("f/" + aperture)
                            .font(AppTypography.font(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundStyle(inkColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(hairline.opacity(0.45), in: Capsule())
                }
                .accessibilityLabel("Focus aperture, f/\(aperture)")
            }
            Text(detailText)
                .font(AppTypography.next(size: 9, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(detailColor)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(mutedInk)
                .rotationEffect(.degrees(expanded ? 180 : 0))
        }
        .contentShape(Rectangle())
    }

    // MARK: full scale

    private var scale: some View {
        let visible = distance != nil
        let showBand = visible && !tooClose
        let tint = tooClose ? warnRed : accentRed

        return VStack(spacing: 0) {
            GeometryReader { geo in
                let inset: CGFloat = 8
                let w = geo.size.width - inset * 2
                let subjectX = inset + CGFloat(damp.values[0]) * w

                ZStack(alignment: .topLeading) {
                    // Rollei marks. Marks inside the depth of field stay dark, the rest recede.
                    // The closest focusing distance is green.
                    ForEach(marks.indices, id: \.self) { i in
                        let p = Focus.position(marks[i].m)
                        let x = inset + CGFloat(p) * w
                        let shade = showBand ? 0.4 + 0.6 * DepthShade.weight(p, near: damp.values[1], far: damp.values[2]) : 1
                        Rectangle()
                            .fill(i == 0 ? goldenGreen : inkColor)
                            .frame(width: 1.5, height: 12)
                            .opacity(shade)
                            .position(x: x, y: 17)
                        Text(marks[i].label)
                            .font(AppTypography.font(size: 14, weight: i == 0 ? .semibold : .regular))
                            .foregroundStyle(i == 0 ? goldenGreen : inkColor)
                            .opacity(shade)
                            .position(x: x, y: 36)
                    }

                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: tooClose ? 14 : 11))
                        .foregroundStyle(tint)
                        .position(x: subjectX, y: 5)
                        .opacity(visible ? 1 : 0)
                }
                .animation(.smooth(duration: 0.3), value: visible)
                .animation(.smooth(duration: 0.3), value: showBand)
            }
            .frame(height: 44)

            HStack {
                Text(near.map { Fmt.distance($0, feet: feet) } ?? "")
                    .foregroundStyle(inkColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    onToggleUnits()
                } label: {
                    Text(unit.uppercased())
                        .font(AppTypography.bold(size: 11))
                        .foregroundStyle(inkColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(inkColor.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                Text(far.map { Fmt.distance($0, feet: feet) } ?? "")
                    .foregroundStyle(inkColor)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(AppTypography.mono(size: 13, weight: .semibold))
            .contentTransition(.numericText())
            .animation(.smooth(duration: 0.2), value: distance)
            .padding(.top, 2)
            .padding(.horizontal, 6)
        }
        .padding(.top, 6)
    }
}
