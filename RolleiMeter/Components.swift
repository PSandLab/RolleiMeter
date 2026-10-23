import SwiftUI
import AVFoundation
import AVKit
import UIKit

// MARK: - 12 × 6 grid

struct LiquidGrid {
    static let designWidth: CGFloat = 1460
    static let designHeight: CGFloat = 665
    private static let bodyWidth: CGFloat = 1646
    private static let bodyHeight: CGFloat = 761
    private static let colPitch: CGFloat = 126
    private static let rowPitch: CGFloat = 119

    let k: CGFloat

    init(screen: CGSize, insets: EdgeInsets) {
        let sideInset = max(insets.leading, insets.trailing)
        let usableWidth = max(screen.width - 2 * sideInset, 1)
        k = max(0.2, min(screen.height / Self.bodyHeight,
                         screen.width / Self.bodyWidth,
                         usableWidth / Self.designWidth))
    }

    var size: CGSize {
        CGSize(width: Self.designWidth * k, height: Self.designHeight * k)
    }

    func rect(col: Int, row: Int, cols: Int, rows: Int) -> CGRect {
        CGRect(
            x: CGFloat(col) * Self.colPitch * k,
            y: CGFloat(row) * Self.rowPitch * k,
            width: (CGFloat(cols) * Self.colPitch - 50) * k,
            height: (CGFloat(rows) * Self.rowPitch - 49) * k
        )
    }
}

extension View {
    func cell(_ grid: LiquidGrid, col: Int, row: Int, cols: Int, rows: Int) -> some View {
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
    var onFlip: (Bool) -> Void = { _ in }

    private var flipped: Bool?

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
        let isFlipped = orientation == .landscapeLeft
        let angle: CGFloat = isFlipped ? 180 : 0
        if let connection = previewLayer.connection,
           connection.isVideoRotationAngleSupported(angle),
           connection.videoRotationAngle != angle {
            connection.videoRotationAngle = angle
        }
        if flipped != isFlipped {
            flipped = isFlipped
            let callback = onFlip
            DispatchQueue.main.async { callback(isFlipped) }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onVolumePress: () -> Void = {}
    var onFlip: (Bool) -> Void = { _ in }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        v.backgroundColor = .clear
        v.onPress = onVolumePress
        v.onFlip = onFlip

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
        uiView.onFlip = onFlip
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

    var body: some View {
        let r = reading
        let index = Self.labels.firstIndex(of: r.label) ?? 0
        let tint: Color = r.deviation != nil ? Palette.bad : (r.isSlow ? Palette.slow : Palette.accent)
        let sub: String = r.deviation.map { Fmt.exposureAmount($0) + " EV" } ?? (r.isSlow ? "slow" : "sec")

        ZStack(alignment: .top) {
            ShutterWheel(position: Double(index), labels: Self.labels, tint: tint, sub: sub, k: k)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: index)
            PanelTitle(text: "SHUTTER", k: k)
        }
        .liquidPanel(radius: 26 * k, useGlass: false)
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

                let number = Text("1/" + labels[i])
                    .font(AppTypography.next(size: 40 * k))
                    .foregroundColor(color)
                ctx.draw(ctx.resolve(number), at: CGPoint(x: x, y: 108 * k), anchor: .center)

                let unit = Text(active ? sub : "sec")
                    .font(AppTypography.next(size: 25 * k))
                    .foregroundColor(color)
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
                .padding(.horizontal, 15 * k)
                .padding(.top, 69 * k)
                .padding(.bottom, 15 * k)
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
    let k: CGFloat
    let onBegin: () -> Double
    let onSlide: (Double) -> Void
    let onEnd: () -> Void
    let onAuto: () -> Void
    let onUnits: () -> Void

    @State private var isDragging: Bool = false
    @State private var lastHapticTick: Int = -1

    private let totalTicks = 28
    private let tickHaptic = UISelectionFeedbackGenerator()
    private let stopHaptic = UIImpactFeedbackGenerator(style: .rigid)

    private var subject: Double? {
        if manual { return Focus.distance(at: position) }
        return hasLiDAR ? lidarDistance : nil
    }

    private var dofBand: (near: Double, far: Double)? {
        guard let s = subject, s >= Focus.nearest - 0.001 else { return nil }
        let r = DepthOfField.range(subject: s, n: aperture.n)
        return (Focus.position(r.near), Focus.position(r.far))
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 8 * k) {
                // Balanced insets keep both touch targets away from the panel edge.
                HStack(spacing: 0) {
                    Button {
                        stopHaptic.impactOccurred(intensity: 0.6)
                        onAuto()
                    } label: {
                        Text(manual ? "MF" : "AF")
                            .font(AppTypography.next(size: 19 * k, weight: .semibold))
                            .foregroundStyle(manual ? Palette.bad : Palette.dim)
                            .frame(width: 48, height: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(manual ? "Switch to autofocus" : "Autofocus active")
                    .accessibilityHint(manual ? "Tap to return to autofocus" : "Autofocus is already active")

                    Spacer(minLength: 0)

                    Text("FOCUS")
                        .font(AppTypography.next(size: 24 * k, weight: .semibold))
                        .tracking(2.2 * k)
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                        .fixedSize()

                    Spacer(minLength: 0)

                    if let subject {
                        Button(action: onUnits) {
                            Text(Fmt.distance(subject, feet: feet))
                                .font(AppTypography.font(size: 19 * k, weight: .semibold))
                                .foregroundStyle(manual ? Palette.text : (tooClose ? Palette.bad : Palette.dim))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(width: 48, height: 44, alignment: .trailing)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Focus distance, \(Fmt.distance(subject, feet: feet))")
                        .accessibilityHint("Tap to switch between metres and feet")
                    } else {
                        Color.clear
                            .frame(width: 48, height: 44)
                            .accessibilityHidden(true)
                    }
                }
                .frame(height: 44)
                .padding(.horizontal, 9)
                .padding(.top, 12 * k)

                // Static Bed Dial Track
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let knobRadius: CGFloat = 16 * k
                    let usableWidth = max(w - (knobRadius * 2), 1)

                    // Left is 0.0 (0.9m), Right is 1.0 (Infinity)
                    let knobX = knobRadius + CGFloat(min(max(position, 0.0), 1.0)) * usableWidth

                    ZStack(alignment: .leading) {
                        // Recessed dark housing
                        RoundedRectangle(cornerRadius: 14 * k, style: .continuous)
                            .fill(Color(hex: 0x050505))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14 * k, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                            )

                        // Depth-of-Field Red Band
                        if let band = dofBand {
                            let leftX = knobRadius + CGFloat(min(max(band.near, 0.0), 1.0)) * usableWidth
                            let rightX = knobRadius + CGFloat(min(max(band.far, 0.0), 1.0)) * usableWidth
                            let bandW = max(rightX - leftX, 6 * k)

                            RoundedRectangle(cornerRadius: 6 * k, style: .continuous)
                                .fill(Color(hex: 0xFF1E1E).opacity(0.35))
                                .frame(width: bandW, height: max(h - 12 * k, 1))
                                .position(x: leftX + bandW / 2, y: h / 2)
                        }

                        // STATIC Lines (Do NOT scroll)
                        Canvas { ctx, size in
                            let ribH = size.height - 18 * k
                            let topY = (size.height - ribH) / 2
                            let botY = topY + ribH

                            for i in 0...totalTicks {
                                let fraction = CGFloat(i) / CGFloat(totalTicks)
                                let x = knobRadius + fraction * usableWidth

                                var path = Path()
                                path.move(to: CGPoint(x: x, y: topY))
                                path.addLine(to: CGPoint(x: x, y: botY))

                                let isMajor = (i == 0 || i == totalTicks || i == totalTicks / 2)
                                let alpha = isMajor ? 0.70 : 0.28
                                let lineWidth = isMajor ? max(1.5, 2.0 * k) : max(1.0, 1.2 * k)

                                ctx.stroke(path, with: .color(Color.white.opacity(alpha)), lineWidth: lineWidth)
                            }
                        }
                        .allowsHitTesting(false)

                        // Red Circle Knob (Slides Left to Right)
                        ZStack {
                            Circle()
                                .fill(Color(hex: 0xFF2A2A).opacity(0.40))
                                .frame(width: 40 * k, height: 40 * k)
                                .blur(radius: 4 * k)

                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [Color(hex: 0xFF3B30), Color(hex: 0xC70010)],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 16 * k
                                    )
                                )
                                .frame(width: knobRadius * 2, height: knobRadius * 2)
                                .overlay(
                                    Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5 * k)
                                )
                        }
                        .position(x: knobX, y: h / 2)
                        .allowsHitTesting(false)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard available else { return }
                                if !isDragging {
                                    isDragging = true
                                    _ = onBegin()
                                }

                                let rawPos = Double((value.location.x - knobRadius) / usableWidth)
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
                                isDragging = false
                                onEnd()
                            }
                    )
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            guard available else { return }
                            stopHaptic.impactOccurred(intensity: 0.8)
                            onAuto()
                        }
                    )
                }
                .padding(.horizontal, 10 * k)
                .padding(.bottom, 12 * k)
            }
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
