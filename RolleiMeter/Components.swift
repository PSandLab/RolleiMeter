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
                .shadow(color: Palette.cast, radius: 10, x: 0, y: 3)
        }
    }
}

// MARK: - Depth

private func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
    guard edge1 > edge0 else { return x < edge0 ? 0 : 1 }
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}

private struct WindowInset: ViewModifier {
    var radius: CGFloat = 12
    var bezel: CGFloat = 5

    private var inner: CGFloat { max(radius - bezel, 3) }

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: inner, style: .continuous)
                    .fill(Palette.well)
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: Palette.recess, location: 0),
                                .init(color: Palette.recess.opacity(0), location: 0.26)
                            ],
                            startPoint: .top, endPoint: .bottom)
                        .mask(RoundedRectangle(cornerRadius: inner, style: .continuous))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: inner, style: .continuous)
                            .strokeBorder(Palette.ink.opacity(0.13), lineWidth: 1)
                    }
            }
            .padding(bezel)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.bezelTop, Palette.bezelBottom],
                                         startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.ink.opacity(0.07), lineWidth: 1)
            }
            .compositingGroup()
            .shadow(color: Palette.cast, radius: 7, x: 0, y: 2)
    }
}

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
            for i in 0...6 {
                let angle = -90.0 - 55.0 + 110.0 * Double(i) / 6.0
                var tick = Path()
                tick.move(to: point(angle, r - 3.5))
                tick.addLine(to: point(angle, r))
                ctx.stroke(tick, with: .color(mutedInk), lineWidth: i % 2 == 0 ? 1.4 : 1)
            }
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

// Observes damp directly so only this column updates when the needle moves
private struct SimpleApertureColumn: View {
    @ObservedObject var damp: Damper
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
                .foregroundStyle(mutedInk)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 10)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                if reading.deviation == nil {
                    Text("1/")
                        .font(AppTypography.mono(size: 30, weight: .medium))
                        .foregroundStyle(mutedInk)
                }
                Text(reading.deviation.map(Fmt.exposureAmount) ?? reading.label)
                    .font(AppTypography.bold(size: 80))
                    .monospacedDigit()
                    .foregroundStyle(stateInk)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .animation(.smooth(duration: 0.18), value: reading.deviation.map(Fmt.exposureAmount) ?? reading.label)
            .animation(.easeInOut(duration: 0.25), value: stateID)
            Text(exposureStatus)
                .font(AppTypography.next(size: 10, weight: .medium))
                .tracking(0.7)
                .foregroundStyle(stateInk.opacity(0.72))
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
    }

    private var stateInk: Color {
        if outOfRange { return Palette.accent }
        return slow ? Palette.amber : Palette.green
    }

    private var stateID: Int {
        if outOfRange { return 2 }
        return slow ? 1 : 0
    }

    private var outOfRange: Bool { reading.deviation != nil }
    private var slow: Bool { reading.deviation == nil && reading.isSlow }
}

struct SimpleExposurePair: View {
    // Does NOT observe damp directly, preventing the focus dial from redrawing needlessly!
    let damp: Damper
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
        .shadow(color: Palette.cast, radius: 10, x: 0, y: 3)
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
            marks: marks.map { (label: $0.label, p: Focus.position($0.m)) }
        )
        .animation(.spring(response: 0.38, dampingFraction: 0.84), value: distance)
        .animation(.spring(response: 0.62, dampingFraction: 0.86), value: aperture.n)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus ring. Set \(recommendedFocus). Depth of field at f/\(aperture.label).")
    }
}

private struct FocusDialFace: View, Animatable {
    var position: Double
    var near: Double
    var far: Double
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

    private func zoom(width: CGFloat) -> CGFloat {
        let span = max(far - near, 0.006)
        let wanted: CGFloat = width * 0.55 / CGFloat(span)
        return min(max(wanted, width * 1.15), width * 8)
    }

    private func drawDial(_ context: inout GraphicsContext, _ size: CGSize) {
        let cx: CGFloat = size.width / 2
        let groupHeight: CGFloat = 104
        let y0: CGFloat = max(0, (size.height - groupHeight) / 2)
        let numberY: CGFloat = y0 + 30
        let markTop: CGFloat = y0 + 50
        let baseline: CGFloat = y0 + 92
        let fadeWidth: CGFloat = 44
        let ppu: CGFloat = zoom(width: size.width)
        let fineRaw: CGFloat = (ppu / 60 - 4) / 3
        let fine: Double = Double(min(max(fineRaw, 0), 1))

        func x(_ p: Double) -> CGFloat {
            return cx + CGFloat(p - position) * ppu
        }
        func fade(_ px: CGFloat) -> Double {
            let edge: CGFloat = min(px, size.width - px)
            return Double(min(max(edge / fadeWidth, 0), 1))
        }

        let nearX: CGFloat = x(near)
        let farX: CGFloat = x(far)
        let left: CGFloat = min(nearX, farX)
        let right: CGFloat = max(nearX, farX)
        let bandTop: CGFloat = markTop - 7
        if right - left > 1.5 {
            let width: CGFloat = right - left
            context.fill(
                Path(roundedRect: CGRect(x: left, y: bandTop, width: width,
                                         height: baseline - bandTop + 2),
                     cornerRadius: 3),
                with: .color(goldenGreen.opacity(0.10)))
            context.fill(
                Path(roundedRect: CGRect(x: left, y: bandTop, width: max(width, 2.5), height: 3),
                     cornerRadius: 1.5),
                with: .color(goldenGreen.opacity(0.70)))
        }

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

        var lastRight: CGFloat = -CGFloat.greatestFiniteMagnitude
        for mark in marks {
            let px: CGFloat = x(mark.p)
            let f: Double = fade(px)
            if f <= 0 { continue }
            let green: Bool = mark.p >= near - 0.004 && mark.p <= far + 0.004
            let color: Color = green ? goldenGreen : inkColor
            var tick = Path()
            tick.move(to: CGPoint(x: px, y: baseline))
            tick.addLine(to: CGPoint(x: px, y: markTop))
            context.stroke(tick, with: .color(color.opacity(f)), lineWidth: green ? 3 : 2.5)
            let underPointer: Bool = abs(mark.p - position) < 0.012
            let label = Text(mark.label)
                .font(AppTypography.bold(size: underPointer ? 29 : 24))
                .foregroundColor(color.opacity(f))
            let text = context.resolve(label)
            let textWidth: CGFloat = text.measure(in: CGSize(width: 400, height: 80)).width
            guard underPointer || px - textWidth / 2 > lastRight + 5 else { continue }
            context.draw(text, at: CGPoint(x: px, y: numberY), anchor: .center)
            lastRight = px + textWidth / 2
        }

        var tri = Path()
        tri.move(to: CGPoint(x: cx - 7, y: y0))
        tri.addLine(to: CGPoint(x: cx + 7, y: y0))
        tri.addLine(to: CGPoint(x: cx, y: y0 + 11))
        tri.closeSubpath()
        context.fill(tri, with: .color(accentRed))
    }
}

// MARK: - Scrub dial

struct ScrubDial: View {
    let title: String
    @Binding var selection: Int
    let labels: [String]
    var resetIndex: Int? = nil

    private let row: CGFloat = 15.5
    private let face: CGFloat = 78

    @State private var base: Int?
    @State private var drag: CGFloat = 0

    private var safeSelection: Int { min(max(selection, 0), max(labels.count - 1, 0)) }

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

            ValueRail(
                position: position,
                labels: labels,
                row: row,
                size: 16.5,
                weight: .bold,
                shrink: 0.20,
                alpha: { d in 0.22 + 0.78 * (1 - smoothstep(0.10, 2.00, d)) }
            )
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

private struct ValueRail: View, Animatable {
    var position: Double
    let labels: [String]
    let row: CGFloat
    let size: CGFloat
    let weight: Font.Weight
    let shrink: CGFloat
    var offsetX: CGFloat = 0
    let alpha: (CGFloat) -> CGFloat

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        Canvas { ctx, canvas in
            let cx = canvas.width / 2 + offsetX
            let midY = canvas.height / 2
            for i in labels.indices {
                let d = CGFloat(Double(i) - position)
                let y = midY + d * row
                if y < -row || y > canvas.height + row { continue }
                let a = alpha(abs(d))
                if a <= 0.02 { continue }
                let scale = 1 - shrink * smoothstep(0, 1.6, abs(d))
                let text = Text(labels[i])
                    .font(AppTypography.mono(size: size, weight: weight))
                    .foregroundColor(Palette.engraved.opacity(a))
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

// MARK: - Paper keys

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
                        radius: active ? 2 : 6,
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

enum AutoLampState {
    case off, good, slow, bad
}

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

struct ApertureDrum: View {
    let index: Int
    let auto: Bool
    let onPick: (Int) -> Void
    let onTap: () -> Void
    let onHome: () -> Void

    private let width: CGFloat = 60
    private let height: CGFloat = 84
    private let bezel: CGFloat = 4
    private let pitch: CGFloat = 18.5
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
        ZStack {
            DrumFace(position: position, pitch: pitch)
            PointerTriangle()
                .fill(accentRed)
                .frame(width: 4.5, height: 9)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .offset(x: -3)
        }
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
                    pressToken += 1
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

private struct DrumFace: View, Animatable {
    var position: Double
    let pitch: CGFloat

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2 - 3.5
            let midY = size.height / 2
            for i in Rollei.stops.indices {
                let d = CGFloat(Double(i) - position)
                let y = midY + d * pitch
                if y < -pitch || y > size.height + pitch { continue }
                let ad = abs(d)
                let near = 1 - smoothstep(0.30, 1.10, ad)
                let mid = 1 - smoothstep(0.80, 1.90, ad)
                let a = 0.10 + 0.90 * (0.5 * mid + 0.5 * near)
                if a <= 0.02 { continue }
                let scale = 1 - 0.26 * smoothstep(0, 1.6, ad)
                let text = Text(Rollei.stops[i].label)
                    .font(AppTypography.bold(size: 19.5))
                    .foregroundColor(Palette.engraved.opacity(a))
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

// MARK: - Metering mode

struct MeterDrum: View {
    let modes: [MeterMode]
    let index: Int
    let onPick: (Int) -> Void
    let onTap: () -> Void

    private let width: CGFloat = 82
    private let height: CGFloat = 84
    private let bezel: CGFloat = 4
    private let pitch: CGFloat = 19

    @State private var position: Double = 0
    @State private var base: Double?
    @State private var moved = false
    @State private var lastDetent = -1

    private var labels: [String] { modes.map { $0.title.uppercased() } }
    private var nearest: Int { min(max(Int(position.rounded()), 0), max(modes.count - 1, 0)) }

    var body: some View {
        ValueRail(
            position: position,
            labels: labels,
            row: pitch,
            size: 13.5,
            weight: .bold,
            shrink: 0.20,
            alpha: { d in
                0.10 + 0.90 * (0.5 * (1 - smoothstep(0.8, 1.9, d)) + 0.5 * (1 - smoothstep(0.3, 1.1, d)))
            }
        )
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
        .accessibilityLabel("Metering mode")
        .accessibilityValue(modes.isEmpty ? "" : modes[nearest].title)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onPick(min(nearest + 1, modes.count - 1))
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
                }
                if !moved && abs(value.translation.height) > 4 { moved = true }
                guard moved, let start = base else { return }
                position = rubber(start - Double(value.translation.height / pitch))
                detent()
            }
            .onEnded { value in
                let start = base ?? position
                let wasMoved = moved
                base = nil
                moved = false
                if !wasMoved {
                    onTap()
                    return
                }
                let predicted = start - Double(value.predictedEndTranslation.height / pitch)
                let target = Double(min(max(Int(rubber(predicted).rounded()), 0), max(modes.count - 1, 0)))
                withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) { position = target }
                onPick(Int(target))
            }
    }

    private func rubber(_ v: Double) -> Double {
        let hi = Double(max(modes.count - 1, 0))
        if v < 0 { return max(-0.3, v * 0.3) }
        if v > hi { return min(hi + 0.3, hi + (v - hi) * 0.3) }
        return v
    }

    private func detent() {
        let stop = nearest
        guard stop != lastDetent else { return }
        lastDetent = stop
        UISelectionFeedbackGenerator().selectionChanged()
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
                    .shadow(color: Palette.cast, radius: 8, x: 0, y: 2.5)
                Circle().fill(hairline).frame(width: 68, height: 68)
                Circle()
                    .fill(paper)
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: Palette.recess.opacity(0.85), location: 0),
                                .init(color: Palette.recess.opacity(0), location: 0.34)
                            ],
                            startPoint: .top, endPoint: .bottom)
                        .clipShape(Circle())
                    }
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

// MARK: - LiDAR marker

private struct FocusPing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    let tooClose: Bool

    var body: some View {
        Circle()
            .stroke(tooClose ? warnRed : Palette.lensLight, lineWidth: 1)
            .frame(width: 26, height: 26)
            .scaleEffect(expanded ? 1.7 : 0.5)
            .opacity(expanded ? 0 : 0.55)
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

struct FocusMarker: View {
    let tooClose: Bool
    var pulseID: Int = 0

    var body: some View {
        ZStack {
            if pulseID > 0 {
                FocusPing(tooClose: tooClose).id(pulseID)
            }
            Circle()
                .stroke(tooClose ? warnRed : Palette.lensLight.opacity(0.92),
                        style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                .frame(width: 26, height: 26)
                .scaleEffect(tooClose ? 0.86 : 1)
            Circle()
                .fill(tooClose ? warnRed : Palette.lensLight)
                .frame(width: 2.5, height: 2.5)
        }
        .frame(width: 30, height: 30)
        .shadow(color: Palette.lensDark.opacity(0.45), radius: 1.5)
        .animation(.spring(response: 0.28, dampingFraction: 0.64), value: tooClose)
        .allowsHitTesting(false)
    }
}