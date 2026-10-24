import SwiftUI
import AVFoundation
import AVKit
import UIKit

// MARK: - 12 × 6 grid

struct LiquidGrid {
    static let landscapeSize = CGSize(width: 1460, height: 665)   // 12 x 6 cells
    static let portraitSize = CGSize(width: 706, height: 1498)    // 6 x 13 cells
    private static let colPitch: CGFloat = 126
    private static let rowPitch: CGFloat = 119

    let k: CGFloat
    let portrait: Bool
    /// Vertical shift that centres the grid between the top and bottom safe areas (portrait only).
    let yShift: CGFloat

    init(screen: CGSize, insets: EdgeInsets) {
        portrait = screen.height > screen.width
        if portrait {
            let usableHeight = max(screen.height - insets.top - insets.bottom, 1)
            k = max(0.2, min(screen.width / (Self.portraitSize.width + 96),
                             usableHeight / (Self.portraitSize.height + 24)))
            yShift = (insets.top - insets.bottom) / 2
        } else {
            let sideInset = max(insets.leading, insets.trailing)
            let usableWidth = max(screen.width - 2 * sideInset, 1)
            k = max(0.2, min(screen.height / 761, screen.width / 1646, usableWidth / 1460))
            yShift = 0
        }
    }

    var size: CGSize {
        let d = portrait ? Self.portraitSize : Self.landscapeSize
        return CGSize(width: d.width * k, height: d.height * k)
    }

    func rect(col: CGFloat, row: CGFloat, cols: Int, rows: Int) -> CGRect {
        CGRect(
            x: col * Self.colPitch * k,
            y: row * Self.rowPitch * k,
            width: (CGFloat(cols) * Self.colPitch - 50) * k,
            height: (CGFloat(rows) * Self.rowPitch - 49) * k
        )
    }
}

extension View {
    func cell(_ grid: LiquidGrid, col: CGFloat, row: CGFloat, cols: Int, rows: Int) -> some View {
        let r = grid.rect(col: col, row: row, cols: cols, rows: rows)
        return self
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
    }
}

// MARK: - Panel chrome

struct LiquidPanel: ViewModifier {
    let radius: CGFloat
    var fill: Color = Palette.panel
    var edge: Bool = true
    var useGlass: Bool = true
    var interactive: Bool = true
    var glassTint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        if #available(iOS 26.0, *), useGlass {
            if let glassTint {
                content.glassEffect(.regular.tint(glassTint).interactive(), in: shape)
            } else if interactive {
                content.glassEffect(.regular.interactive(), in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        } else if useGlass {
            // Compatibility treatment for iOS 17–25, where native Liquid Glass isn't available.
            content
                .background { shape.fill(fill) }
                .overlay {
                    if edge {
                        shape
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.09), Color.white.opacity(0.02)],
                                    startPoint: .top, endPoint: .bottom),
                                lineWidth: 0.75)
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(shape)
        } else {
            // Standard material is appropriate for readouts; reserve Liquid Glass for the control layer.
            content.background(.regularMaterial, in: shape)
        }
    }
}

extension View {
    func liquidPanel(
        radius: CGFloat,
        fill: Color = Palette.panel,
        edge: Bool = true,
        useGlass: Bool = true,
        interactive: Bool = true,
        glassTint: Color? = nil
    ) -> some View {
        modifier(LiquidPanel(
            radius: radius,
            fill: fill,
            edge: edge,
            useGlass: useGlass,
            interactive: interactive,
            glassTint: glassTint
        ))
    }
}

private struct PanelTitle: View {
    let text: String
    let k: CGFloat
    var color: Color = Palette.text

    var body: some View {
        Text(text)
            .font(AppTypography.next(size: 25 * k))
            .tracking(2.6 * k)
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.top, 17 * k)
            .accessibilityAddTraits(.isHeader)
    }
}

struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.20, dampingFraction: 0.70), value: configuration.isPressed)
    }
}

// MARK: - Camera preview

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onPress: () -> Void = {}
    var onRotate: (ViewRotation) -> Void = { _ in }

    private var rotation: ViewRotation?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        backgroundColor = .clear
        NotificationCenter.default.addObserver(
            self, selector: #selector(sessionStarted),
            name: AVCaptureSession.didStartRunningNotification, object: nil)
    }

    @objc private func sessionStarted() {
        applyOrientation()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyOrientation()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
        applyOrientation()
    }

    private func applyOrientation() {
        guard let orientation = window?.windowScene?.interfaceOrientation else { return }
        let newRotation = ViewRotation(orientation)
        let angle = newRotation.videoAngle
        if let connection = previewLayer.connection,
           connection.isVideoRotationAngleSupported(angle),
           connection.videoRotationAngle != angle {
            connection.videoRotationAngle = angle
        }
        if rotation != newRotation {
            rotation = newRotation
            let callback = onRotate
            DispatchQueue.main.async { callback(newRotation) }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onVolumePress: () -> Void = {}
    var onRotate: (ViewRotation) -> Void = { _ in }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        v.backgroundColor = .clear
        v.onPress = onVolumePress
        v.onRotate = onRotate

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
        uiView.onRotate = onRotate
    }
}

// MARK: - Shutter (read-out wheel)

struct ShutterPanel: View {
    @ObservedObject var damp: Damper
    let iso: Double
    let comp: Double
    let aperture: (label: String, n: Double)
    let k: CGFloat

    private static let labels: [String] = Rollei.speeds.reversed().map { $0.label }

    private var reading: ShutterResult {
        let t = Exposure.idealShutter(ev100: damp.values[0], iso: iso, comp: comp, n: aperture.n)
        return Exposure.result(for: t)
    }

    @State private var position: Double = 0

    var body: some View {
        let r = reading
        let index = Self.labels.firstIndex(of: r.label) ?? 0
        let tint: Color = r.deviation != nil ? Palette.bad : (r.isSlow ? Palette.slow : Palette.accent)
        let sub: String = r.deviation.map { Fmt.exposureAmount($0) + " EV" } ?? (r.isSlow ? "slow" : "sec")

        ZStack(alignment: .top) {
            ShutterWheel(position: position, labels: Self.labels, tint: tint, sub: sub, k: k)
            PanelTitle(text: "SHUTTER", k: k)
        }
        .onAppear { position = Double(index) }
        .onChange(of: index) { _, newIndex in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                position = Double(newIndex)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shutter speed")
        .accessibilityValue(r.deviation == nil ? "1/\(r.label) second" : sub)
    }
}

private struct ShutterWheel: View, Animatable {
    var position: Double
    let labels: [String]
    let tint: Color
    let sub: String
    let k: CGFloat

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let pitch = size.width * 0.40
            for i in labels.indices {
                let d = Double(i) - position
                let x = cx + CGFloat(d) * pitch
                if x < -pitch || x > size.width + pitch { continue }
                let active = abs(d) < 0.5
                let color: Color = active ? tint : Palette.text.opacity(0.8)

                let ad = abs(d)
                let number = Text("1/" + labels[i])
                    .font(AppTypography.next(size: 42 * k, weight: active ? .bold : .medium))
                    .foregroundColor(color.opacity(max(0.16, 1 - 0.5 * ad)))
                ctx.draw(ctx.resolve(number), at: CGPoint(x: x, y: 108 * k), anchor: .center)

                let unit = Text(active ? sub : "sec")
                    .font(AppTypography.next(size: 25 * k, weight: active ? .bold : .medium))
                    .foregroundColor(color.opacity(max(0.16, 1 - 0.5 * ad)))
                ctx.draw(ctx.resolve(unit), at: CGPoint(x: x, y: 152 * k), anchor: .center)
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

// MARK: - Metering mode

struct MeterPanel: View {
    let modes: [MeterMode]
    let index: Int
    let k: CGFloat
    let onPick: (Int) -> Void

    private func caption(_ mode: MeterMode) -> String {
        switch mode {
        case .matrix: return "scene"
        case .highlight: return "peaks"
        case .spot: return "point"
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                ForEach(modes.indices, id: \.self) { i in
                    Button {
                        guard i != index else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        onPick(i)
                    } label: {
                        VStack(spacing: 6 * k) {
                            Text(modes[i].title)
                                .font(AppTypography.next(size: 31 * k, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(caption(modes[i]))
                                .font(AppTypography.next(size: 23 * k))
                                .lineLimit(1)
                        }
                        .foregroundStyle(i == index ? Palette.accent : Palette.text)
                        .animation(.easeOut(duration: 0.18), value: index)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 72 * k)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(modes[i].title + " metering")
                    .accessibilityAddTraits(i == index ? .isSelected : [])
                }
            }
            PanelTitle(text: "METER", k: k)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Film speed

struct FilmPanel: View {
    @Binding var isoIndex: Int
    @Binding var useDIN: Bool
    let k: CGFloat

    @State private var dragBase: Int?

    private var safeIndex: Int { min(max(isoIndex, 0), ISOScale.values.count - 1) }

    private var readout: String {
        let value = ISOScale.label(ISOScale.values[safeIndex], din: useDIN)
        return (useDIN ? "DIN" : "ISO") + "  \u{2022}  " + value
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Yellow card background matching reference mockup
            RoundedRectangle(cornerRadius: 22 * k, style: .continuous)
                .fill(Palette.accent)

            PanelTitle(text: "FILM", k: k, color: Palette.accentInk)

            RoundedRectangle(cornerRadius: 14 * k, style: .continuous)
                .fill(Palette.accentInk)
                .overlay {
                    Text(readout)
                        .font(AppTypography.next(size: 34 * k, weight: .medium))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.15), value: readout)
                }
                .padding(.horizontal, 14 * k)
                .padding(.top, 65 * k)
                .padding(.bottom, 14 * k)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeInOut(duration: 0.2)) { useDIN.toggle() }
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            guard let hundred = ISOScale.values.firstIndex(of: 100), isoIndex != hundred else { return }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
            isoIndex = hundred
        }
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    if dragBase == nil { dragBase = safeIndex }
                    let steps = Int((value.translation.width / (26 * k)).rounded())
                    let target = min(max((dragBase ?? safeIndex) + steps, 0), ISOScale.values.count - 1)
                    guard target != isoIndex else { return }
                    isoIndex = target
                    if ISOScale.values[target] == 100 {
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
                    } else {
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                }
                .onEnded { _ in dragBase = nil }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Film speed")
        .accessibilityValue(readout)
    }
}

// MARK: - Aperture wheel

enum AutoLampState {
    case off, good, slow, bad
}

struct AperturePanel: View {
    let index: Int
    let auto: Bool
    let lamp: AutoLampState
    let k: CGFloat
    let onPick: (Int) -> Void
    let onTap: () -> Void
    let onHome: () -> Void

    private let homeIndex = 3

    @State private var position: Double = 0
    @State private var base: Double?
    @State private var moved = false
    @State private var longPressFired = false
    @State private var pressToken = 0
    @State private var lastDetent = -1

    private var stopCount: Int { Rollei.stops.count }
    private var nearest: Int { min(max(Int(position.rounded()), 0), stopCount - 1) }
    private var pitch: CGFloat { 81 * k }

    private var lampColor: Color {
        switch lamp {
        case .off: return Palette.text
        case .good: return Palette.good
        case .slow: return Palette.slow
        case .bad: return Palette.bad
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ApertureWheel(position: position, labels: Rollei.stops.map { $0.label },
                          tint: auto ? lampColor : Palette.text, k: k)
            PanelTitle(text: "APERTURE", k: k)
        }
        .overlay(alignment: .topTrailing) {
            if auto {
                Text("A")
                    .font(AppTypography.next(size: 25 * k, weight: .bold))
                    .foregroundStyle(lampColor)
                    .padding(.top, 17 * k)
                    .padding(.trailing, 22 * k)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onAppear {
            position = Double(index)
            lastDetent = index
        }
        .onChange(of: index) { _, newValue in
            guard base == nil else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                position = Double(newValue)
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
                if !moved && abs(value.translation.width) > 4 {
                    moved = true
                    pressToken += 1
                }
                guard moved, let start = base else { return }
                position = rubber(start - Double(value.translation.width / pitch))
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
                let predicted = start - Double(value.predictedEndTranslation.width / pitch)
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

private struct ApertureWheel: View, Animatable {
    var position: Double
    let labels: [String]
    let tint: Color
    let k: CGFloat

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let pitch = 81 * k
            for i in labels.indices {
                let d = Double(i) - position
                let x = cx + CGFloat(d) * pitch
                if x < -pitch || x > size.width + pitch { continue }
                let ad = abs(d)
                let selected = ad < 0.5
                let color: Color = selected ? tint : Palette.text
                let text = Text(labels[i])
                    .font(AppTypography.next(size: 42 * k, weight: selected ? .bold : .medium))
                    .foregroundColor(color.opacity(max(0.16, 1 - 0.5 * ad)))
                ctx.draw(ctx.resolve(text), at: CGPoint(x: x, y: 120 * k), anchor: .center)
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

// MARK: - Focus (Static Bed Dial with Left-to-Right Knob)

private struct FocusStripLines: View, Animatable {
    var focusPosition: Double
    var scrollProgress: Double
    var rippleProgress: Double
    var rippleCenter: Double
    var manual: Bool
    var dofNear: Double
    var dofFar: Double
    var hasMeasurement: Bool
    var isTooClose: Bool
    let totalTicks: Int
    let k: CGFloat

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, AnimatablePair<Double, AnimatablePair<Double, AnimatablePair<Double, Double>>>>> {
        get {
            .init(focusPosition, .init(scrollProgress, .init(rippleProgress, .init(rippleCenter, .init(dofNear, dofFar)))))
        }
        set {
            focusPosition = newValue.first
            scrollProgress = newValue.second.first
            rippleProgress = newValue.second.second.first
            rippleCenter = newValue.second.second.second.first
            dofNear = newValue.second.second.second.second.first
            dofFar = newValue.second.second.second.second.second
        }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let lineMargin: CGFloat = 2 * k
            let linesWidth = max(w - lineMargin * 2, 1)
            let touchX = lineMargin + CGFloat(min(max(focusPosition, 0.0), 1.0)) * linesWidth
            let rippleX = lineMargin + CGFloat(min(max(rippleCenter, 0.0), 1.0)) * linesWidth
            let baseRibH = h - 22 * k
            let zoomRadius = 42 * k

            Canvas { ctx, size in
                for i in 0...totalTicks {
                    let fraction = CGFloat(i) / CGFloat(totalTicks)
                    let x = lineMargin + fraction * linesWidth
                    let d = abs(x - touchX)

                    // 1. Gentle macOS dock zoom magnification following finger
                    var boost: CGFloat = 0
                    if scrollProgress > 0 && d < zoomRadius {
                        let t = 1.0 - (d / zoomRadius)
                        let wCurve = t * t * (3 - 2 * t)
                        boost = 11 * k * CGFloat(scrollProgress) * wCurve
                    }

                    // 2. Gentle ripple wave expanding outward on release
                    if rippleProgress < 1.0 {
                        let dRipple = abs(x - rippleX)
                        let waveRadius = CGFloat(rippleProgress) * 95 * k
                        let waveWidth: CGFloat = 30 * k
                        let distToWave = abs(dRipple - waveRadius)
                        if distToWave < waveWidth {
                            let waveT = 1.0 - (distToWave / waveWidth)
                            let waveCurve = waveT * waveT * (3 - 2 * waveT)
                            let decay = 1.0 - CGFloat(rippleProgress)
                            let rippleBoost = 7 * k * decay * waveCurve
                            boost = max(boost, rippleBoost)
                        }
                    }

                    let lineH = baseRibH + boost
                    let topY = (h - 22 * k - lineH) / 2
                    let botY = topY + lineH

                    var path = Path()
                    path.move(to: CGPoint(x: x, y: topY))
                    path.addLine(to: CGPoint(x: x, y: botY))

                    var r: Double = 1.0
                    var g: Double = 1.0
                    var b: Double = 1.0
                    var alpha: Double = 0.85
                    var lw = max(1.2, 1.8 * k) + (boost > 0 ? 0.6 * k : 0)

                    if manual {
                        // Manual Mode: Lines inside depth-of-field turn RED when resting
                        if scrollProgress < 0.95 {
                            let inDoF = fraction >= (dofNear - 0.015) && fraction <= (dofFar + 0.015)
                            if inDoF {
                                let restingFactor = 1.0 - scrollProgress
                                let distToFocus = abs(fraction - focusPosition)
                                let centerBonus = max(0.0, 1.0 - distToFocus / max(0.05, (dofFar - dofNear) * 0.5))
                                r = 1.0
                                g = 1.0 - restingFactor * (1.0 - 0.23)
                                b = 1.0 - restingFactor * (1.0 - 0.19)
                                alpha = min(1.0, 0.85 + restingFactor * 0.15)
                                if centerBonus > 0.6 {
                                    lw += 0.4 * k
                                }
                            }
                        }
                    } else {
                        // Auto Mode: Green lines reflecting measurement and DoF in real time
                        if isTooClose {
                            if fraction <= 0.12 {
                                r = 1.0
                                g = 0.27
                                b = 0.23
                                alpha = 1.0
                            }
                        } else if hasMeasurement {
                            let inDoF = fraction >= (dofNear - 0.015) && fraction <= (dofFar + 0.015)
                            if inDoF {
                                let distToFocus = abs(fraction - focusPosition)
                                let centerBonus = max(0.0, 1.0 - distToFocus / max(0.06, (dofFar - dofNear) * 0.5))
                                r = 0.19
                                g = 0.82 + 0.14 * centerBonus
                                b = 0.35
                                alpha = min(1.0, 0.88 + 0.12 * centerBonus)
                                if centerBonus > 0.5 {
                                    lw += 0.4 * k
                                }
                            }
                        }
                    }

                    ctx.stroke(
                        path,
                        with: .color(Color(red: r, green: g, blue: b, opacity: alpha)),
                        lineWidth: lw
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct FocusPanel: View {
    /// 0.0 (closest focus / 0.9m on Left) to 1.0 (infinity on Right)
    let position: Double
    let manual: Bool
    let touching: Bool
    let available: Bool
    let lidarDistance: Double?
    let hasLiDAR: Bool
    let tooClose: Bool
    let aperture: (label: String, n: Double)
    let feet: Bool
    var isHeld: Bool = false
    let k: CGFloat
    let onBegin: () -> Double
    let onSlide: (Double) -> Void
    let onEnd: () -> Void
    let onAuto: () -> Void
    let onUnits: () -> Void

    @State private var isDragging: Bool = false
    @State private var lastHapticTick: Int = -1
    @State private var rippleProgress: Double = 1.0
    @State private var rippleCenter: Double = 0.5

    private let totalTicks = 36
    private let tickHaptic = UISelectionFeedbackGenerator()
    private let stopHaptic = UIImpactFeedbackGenerator(style: .rigid)

    private var isScrolling: Bool {
        isDragging || touching
    }

    private var subject: Double? {
        if manual { return Focus.distance(at: position) }
        return lidarDistance
    }

    private var activePosition: Double {
        if manual { return position }
        if let d = lidarDistance { return Focus.position(d) }
        return 1.0
    }

    private var currentDoFRange: (near: Double, far: Double) {
        let s: Double? = manual ? Focus.distance(at: position) : lidarDistance
        if let dist = s, dist >= Focus.nearest - 0.001 {
            let r = DepthOfField.range(subject: dist, n: aperture.n)
            return (Focus.position(r.near), Focus.position(r.far))
        } else if !manual, let dist = s, dist < Focus.nearest {
            return (0.0, 0.08)
        } else if !manual && lidarDistance == nil {
            let r = DepthOfField.range(subject: .infinity, n: aperture.n)
            return (Focus.position(r.near), 1.0)
        }
        return (0.0, 0.0)
    }

    private var dofBoundaryMarkers: (near: (pos: Double, label: String), far: (pos: Double, label: String))? {
        guard let s = subject, s >= Focus.nearest - 0.001 else { return nil }
        let r = DepthOfField.range(subject: s, n: aperture.n)
        let marks = feet ? Focus.feetMarks : Focus.meterMarks

        let nearMark = marks.min(by: { abs($0.m - r.near) < abs($1.m - r.near) }) ?? marks[0]
        let farMark = marks.min(by: { abs($0.m - r.far) < abs($1.m - r.far) }) ?? marks[marks.count - 1]

        var nearLabel = nearMark.label
        var farLabel = farMark.label

        if nearLabel == farLabel {
            let lo = marks.last { $0.m <= s } ?? marks[0]
            let hi = marks.first { $0.m > s } ?? marks[marks.count - 1]
            nearLabel = lo.label
            farLabel = hi.label
        }

        return (
            near: (pos: Focus.position(r.near), label: nearLabel),
            far: (pos: Focus.position(r.far), label: farLabel)
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            PanelTitle(text: "FOCUS", k: k)

            // Static Bed Dial Track (No box, no ball, lines span end to end)
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let lineMargin: CGFloat = 2 * k
                let usableWidth = max(w - lineMargin * 2, 1)
                let ribH = h - 22 * k
                let touchX = lineMargin + CGFloat(min(max(activePosition, 0.0), 1.0)) * usableWidth

                ZStack(alignment: .leading) {
                    // Atmospheric red gradient wash following finger directly
                    let glowWidth = max(w * 0.82, 110 * k)
                    RoundedRectangle(cornerRadius: 8 * k, style: .continuous)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color(hex: 0xFF2A2A).opacity(0.0), location: 0.0),
                                    .init(color: Color(hex: 0xFF2A2A).opacity(0.18), location: 0.20),
                                    .init(color: Color(hex: 0xFF1E1E).opacity(0.60), location: 0.50),
                                    .init(color: Color(hex: 0xFF2A2A).opacity(0.18), location: 0.80),
                                    .init(color: Color(hex: 0xFF2A2A).opacity(0.0), location: 1.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: glowWidth, height: ribH + 6 * k)
                        .position(x: touchX, y: ribH / 2)
                        .opacity(isScrolling && manual ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.25), value: isScrolling)
                        .allowsHitTesting(false)

                    // Lines with gentle dock zoom, release ripple & DoF coloring
                    FocusStripLines(
                        focusPosition: activePosition,
                        scrollProgress: isScrolling ? 1.0 : 0.0,
                        rippleProgress: rippleProgress,
                        rippleCenter: rippleCenter,
                        manual: manual,
                        dofNear: currentDoFRange.near,
                        dofFar: currentDoFRange.far,
                        hasMeasurement: subject != nil || !manual,
                        isTooClose: tooClose,
                        totalTicks: totalTicks,
                        k: k
                    )
                    .animation(.easeInOut(duration: 0.22), value: activePosition)
                    .animation(.easeInOut(duration: 0.22), value: currentDoFRange.near)

                    // DoF boundary markers displayed under the lines on HOLD (shutter pressed)
                    if (isHeld || (manual && !isScrolling)), let markers = dofBoundaryMarkers {
                        let leftX = lineMargin + CGFloat(markers.near.pos) * usableWidth
                        let rightX = lineMargin + CGFloat(markers.far.pos) * usableWidth
                        let minGap: CGFloat = 34 * k
                        let actualGap = max(rightX - leftX, minGap)
                        let midX = (leftX + rightX) / 2
                        let adjLeftX = min(leftX, midX - actualGap / 2)
                        let adjRightX = max(rightX, midX + actualGap / 2)
                        let markerY = ribH + 11 * k

                        ZStack {
                            VStack(spacing: 2 * k) {
                                Rectangle()
                                    .fill(Palette.accent)
                                    .frame(width: 1.5 * k, height: 4 * k)
                                Text(markers.near.label)
                                    .font(AppTypography.mono(size: 13 * k, weight: .bold))
                                    .foregroundStyle(Palette.accent)
                                    .lineLimit(1)
                            }
                            .position(x: adjLeftX, y: markerY)

                            VStack(spacing: 2 * k) {
                                Rectangle()
                                    .fill(Palette.accent)
                                    .frame(width: 1.5 * k, height: 4 * k)
                                Text(markers.far.label)
                                    .font(AppTypography.mono(size: 13 * k, weight: .bold))
                                    .foregroundStyle(Palette.accent)
                                    .lineLimit(1)
                            }
                            .position(x: adjRightX, y: markerY)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        .animation(.easeInOut(duration: 0.22), value: markers.near.pos)
                        .animation(.easeInOut(duration: 0.22), value: markers.far.pos)
                        .animation(.easeInOut(duration: 0.22), value: aperture.n)
                        .animation(.easeInOut(duration: 0.25), value: isHeld)
                        .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .animation(.easeInOut(duration: 0.25), value: isScrolling)
                .animation(.easeInOut(duration: 0.25), value: manual)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard available else { return }
                            if !isDragging {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isDragging = true
                                }
                                _ = onBegin()
                            }

                            let rawPos = Double((value.location.x - lineMargin) / usableWidth)
                            let newPos = min(max(rawPos, 0.0), 1.0)

                            let tickIndex = Int((newPos * Double(totalTicks)).rounded())
                            if tickIndex != lastHapticTick {
                                lastHapticTick = tickIndex
                                tickHaptic.selectionChanged()
                            }

                            if (newPos == 0.0 && position == 0.0) || (newPos == 1.0 && position == 1.0) {
                                stopHaptic.impactOccurred(intensity: 0.4)
                            }

                            onSlide(newPos)
                        }
                        .onEnded { _ in
                            rippleCenter = position
                            rippleProgress = 0.0
                            withAnimation(.easeOut(duration: 0.45)) {
                                rippleProgress = 1.0
                            }
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isDragging = false
                            }
                            onEnd()
                        }
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        guard available else { return }
                        stopHaptic.impactOccurred(intensity: 0.8)
                        withAnimation(.easeInOut(duration: 0.25)) {
                            onAuto()
                        }
                    }
                )
            }
            .padding(.top, 56 * k)
            .padding(.bottom, 10 * k)
            .padding(.horizontal, 14 * k)
        }
        .overlay(alignment: .topLeading) {
            Button {
                if manual {
                    stopHaptic.impactOccurred(intensity: 0.6)
                    withAnimation(.easeInOut(duration: 0.25)) {
                        onAuto()
                    }
                }
            } label: {
                Text(manual ? "MF" : "AF")
                    .font(AppTypography.next(size: 19 * k, weight: .bold))
                    .foregroundStyle(manual ? Palette.bad : Palette.good)
                    .padding(.top, 17 * k)
                    .padding(.leading, 18 * k)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(manual ? "Switch to autofocus" : "Autofocus active")
        }
        .overlay(alignment: .topTrailing) {
            let displayDistance = subject != nil ? Fmt.distance(subject, feet: feet) : (hasLiDAR ? "∞" : "—")
            Button(action: onUnits) {
                Text(displayDistance)
                    .font(AppTypography.mono(size: 19 * k, weight: .semibold))
                    .foregroundStyle(manual ? Palette.text : (tooClose ? Palette.bad : Palette.good))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 17 * k)
                    .padding(.trailing, 18 * k)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Focus distance, \(displayDistance)")
        }
        .onAppear {
            tickHaptic.prepare()
        }
    }
}

// MARK: - Peaking overlay (Pure LiDAR DoF wash)

struct PeakingOverlay: View {
    @ObservedObject var feed: PeakingFeed

    var body: some View {
        ZStack {
            if let image = feed.image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Hold button

struct HoldControl: View {
    let frozen: Bool
    let k: CGFloat
    let action: () -> Void

    var body: some View {
        buttonContent.buttonStyle(PressStyle(scale: 0.97))
    }

    private var buttonContent: some View {
        Button(action: action) {
            holdLabel
                .animation(.spring(response: 0.3, dampingFraction: 0.72), value: frozen)
        }
    }

    private var holdLabel: some View {
        ZStack(alignment: .trailing) {
            Text(frozen ? "hold" : "live")
                .font(AppTypography.next(size: 29 * k))
                .foregroundStyle(frozen ? Palette.accent : Palette.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 17 * k)

            ZStack {
                Circle()
                    .fill(Color(hex: 0x070707))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                Circle()
                    .fill(frozen ? Palette.accent : Color.white)
                    .frame(width: 126 * k, height: 126 * k)
                    .scaleEffect(frozen ? 0.9 : 1.0)
            }
            .frame(width: 175 * k, height: 175 * k)
            .padding(.trailing, 7 * k)
        }
    }
}

// MARK: - Viewfinder overlays

struct EVChip: View {
    @ObservedObject var damp: Damper
    let frozen: Bool
    let spot: Bool

    var body: some View {
        HStack(spacing: 6) {
            if frozen {
                Text("HOLD").foregroundStyle(Palette.accent)
            }
            if spot {
                Text("SPOT")
            }
            Text("EV " + String(format: "%.1f", damp.values[0]))
                .monospacedDigit()
        }
        .font(AppTypography.font(size: 11, weight: .medium))
        .foregroundStyle(Palette.text)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: frozen)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: spot)
    }
}

// MARK: - LiDAR marker

private struct FocusPing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    let tooClose: Bool

    var body: some View {
        Circle()
            .stroke(tooClose ? Palette.bad : Palette.lensLight, lineWidth: 1)
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
                .stroke(tooClose ? Palette.bad : Palette.lensLight.opacity(0.92),
                        style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                .frame(width: 26, height: 26)
                .scaleEffect(tooClose ? 0.86 : 1)
            Circle()
                .fill(tooClose ? Palette.bad : Palette.lensLight)
                .frame(width: 2.5, height: 2.5)
        }
        .frame(width: 30, height: 30)
        .shadow(color: Palette.lensDark.opacity(0.45), radius: 1.5)
        .animation(.spring(response: 0.28, dampingFraction: 0.64), value: tooClose)
        .allowsHitTesting(false)
    }
}
