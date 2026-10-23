import SwiftUI
import AVFoundation
import AVKit
import UIKit

// MARK: - 12 × 6 grid

/// Every control sits on the 12 × 6 grid from the design. The grid is 1460 × 665 design units
/// (76-wide columns, 70-high rows, ~50 unit gutters) inside a 1646 × 761 body, scaled by `k`
/// so the whole thing fits the screen.
struct LiquidGrid {
    static let designWidth: CGFloat = 1460
    static let designHeight: CGFloat = 665
    private static let bodyWidth: CGFloat = 1646
    private static let bodyHeight: CGFloat = 761
    private static let colPitch: CGFloat = 126
    private static let rowPitch: CGFloat = 119

    /// Points per design unit.
    let k: CGFloat

    /// Fits the grid to the screen, keeping it clear of the notch / Dynamic Island side insets.
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
    /// Places the view on the grid. The parent must be a top-leading `ZStack` of the grid's size.
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

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
            }
            .overlay {
                if edge {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.09), Color.white.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom),
                            lineWidth: 0.75)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func liquidPanel(radius: CGFloat, fill: Color = Palette.panel, edge: Bool = true) -> some View {
        modifier(LiquidPanel(radius: radius, fill: fill, edge: edge))
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
    /// Called when the interface turns between the two landscape orientations.
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
        backgroundColor = .clear // Eliminates black flashes during view resizing.
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

    /// The sensor is natively landscape (home button on the right). Interface landscape-right shows
    /// it as is; landscape-left turns the preview over 180°. Metering and LiDAR keep reading the
    /// native buffer, so the preview is the only thing that turns.
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

/// The metered shutter speed. The wheel turns to the Rollei's nearest marked speed.
struct ShutterPanel: View {
    @ObservedObject var damp: Damper
    let iso: Double
    let comp: Double
    let aperture: (label: String, n: Double)
    let k: CGFloat

    /// Slowest to fastest, left to right.
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
        .liquidPanel(radius: 26 * k)
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

// MARK: - Metering mode (the "lens" choice)

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
        .liquidPanel(radius: 26 * k)
    }
}

// MARK: - Film speed (the yellow card)

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
        .liquidPanel(radius: 26 * k, fill: Palette.accent, edge: false)
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
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: isoIndex = min(safeIndex + 1, ISOScale.values.count - 1)
            case .decrement: isoIndex = max(safeIndex - 1, 0)
            @unknown default: break
            }
        }
    }
}

// MARK: - Exposure compensation scale

struct EVScaleBar: View {
    @Binding var index: Int
    let k: CGFloat

    private static let labels = ["\u{2212}2", "\u{2212}1", "0", "+1", "+2"]
    /// Where −2 sits along the bar, and the distance between whole stops (fractions of the width).
    private static let origin: CGFloat = 0.096
    private static let stopWidth: CGFloat = 0.2145
    /// The labels sit just left of their tick, so the marker never covers a number.
    private static let labelShift: CGFloat = 0.025

    private func fraction(_ value: Double) -> CGFloat {
        Self.origin + CGFloat(value + 2) * Self.stopWidth
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let safe = min(max(index, 0), EVComp.values.count - 1)

            ZStack(alignment: .topLeading) {
                ForEach(0..<5, id: \.self) { n in
                    Text(Self.labels[n])
                        .font(AppTypography.next(size: 26 * k))
                        .foregroundStyle(Palette.text.opacity(0.92))
                        .position(x: (fraction(Double(n - 2)) - Self.labelShift) * w, y: h / 2)
                }
                Rectangle()
                    .fill(Palette.accent)
                    .frame(width: max(2, 3 * k), height: h)
                    .position(x: fraction(EVComp.values[safe]) * w, y: h / 2)
                    .animation(.spring(response: 0.28, dampingFraction: 0.78), value: safe)
            }
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let raw = Double((value.location.x / max(w, 1) - Self.origin) / Self.stopWidth) - 2
                        let stops = min(max(raw, -2), 2)
                        let target = Int((stops * 3).rounded()) + EVComp.zeroIndex
                        guard target != index else { return }
                        index = target
                        if target == EVComp.zeroIndex {
                            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
                        } else {
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    guard index != EVComp.zeroIndex else { return }
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { index = EVComp.zeroIndex }
                }
            )
        }
        .liquidPanel(radius: 22 * k)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exposure compensation")
        .accessibilityValue(Fmt.stops(EVComp.values[min(max(index, 0), EVComp.values.count - 1)]) + " stops")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: index = min(index + 1, EVComp.values.count - 1)
            case .decrement: index = max(index - 1, 0)
            @unknown default: break
            }
        }
    }
}

// MARK: - Aperture (the "frame" wheel)

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
        .liquidPanel(radius: 26 * k)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aperture")
        .accessibilityValue("f/" + Rollei.stops[min(max(index, 0), stopCount - 1)].label + (auto ? ", auto" : ""))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onPick(min(index + 1, stopCount - 1))
            case .decrement: onPick(max(index - 1, 0))
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

// MARK: - Focus (LiDAR distance against the Rollei's focus scale)

struct FocusPanel: View {
    let distance: Double?
    let hasLiDAR: Bool
    let aperture: (label: String, n: Double)
    let tooClose: Bool
    let feet: Bool
    let k: CGFloat
    let onTap: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            content
                .padding(.horizontal, 15 * k)
                .padding(.top, 69 * k)
                .padding(.bottom, 15 * k)
            PanelTitle(text: "FOCUS", k: k)
            if hasLiDAR, !tooClose, let distance {
                Text(Fmt.distance(distance, feet: feet))
                    .font(AppTypography.font(size: 22 * k, weight: .medium))
                    .foregroundStyle(Palette.dim)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 21 * k)
                    .padding(.trailing, 20 * k)
                    .allowsHitTesting(false)
            }
        }
        .liquidPanel(radius: 26 * k)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var content: some View {
        if !hasLiDAR {
            Text("NO LIDAR")
                .font(AppTypography.next(size: 24 * k, weight: .medium))
                .tracking(1.5 * k)
                .foregroundStyle(Palette.dim)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if tooClose {
            Text("TOO CLOSE")
                .font(AppTypography.next(size: 28 * k, weight: .semibold))
                .tracking(1.5 * k)
                .foregroundStyle(Palette.bad)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let distance {
            FocusRingScale(distance: distance, aperture: aperture, feet: feet, k: k)
        } else {
            VStack(spacing: 4 * k) {
                Text("\u{2014}")
                    .font(AppTypography.mono(size: 40 * k, weight: .medium))
                    .foregroundStyle(Palette.dim)
                Text("OUT OF RANGE")
                    .font(AppTypography.next(size: 20 * k, weight: .medium))
                    .tracking(1.2 * k)
                    .foregroundStyle(Palette.faint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct FocusRingScale: View {
    let distance: Double
    let aperture: (label: String, n: Double)
    let feet: Bool
    let k: CGFloat

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
            marks: marks.map { (label: $0.label, p: Focus.position($0.m)) },
            k: k
        )
        .animation(.spring(response: 0.38, dampingFraction: 0.84), value: distance)
        .animation(.spring(response: 0.62, dampingFraction: 0.86), value: aperture.n)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus ring. Set \(recommendedFocus). Depth of field at f/\(aperture.label).")
    }
}

/// A tape of fine vertical ticks under a fixed yellow pointer. Marks inside the depth of field
/// turn green; the green band behind them is the depth of field itself.
private struct FocusDialFace: View, Animatable {
    var position: Double
    var near: Double
    var far: Double
    let marks: [(label: String, p: Double)]
    let k: CGFloat

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
        .allowsHitTesting(false)
    }

    private func zoom(width: CGFloat) -> CGFloat {
        let span = max(far - near, 0.006)
        let wanted: CGFloat = width * 0.55 / CGFloat(span)
        return min(max(wanted, width * 1.15), width * 8)
    }

    private func drawDial(_ context: inout GraphicsContext, _ size: CGSize) {
        let cx: CGFloat = size.width / 2
        let h: CGFloat = size.height
        let numberY: CGFloat = h * 0.24
        let markTop: CGFloat = h * 0.50
        let baseline: CGFloat = h
        let fadeWidth: CGFloat = 36 * k
        let ppu: CGFloat = zoom(width: size.width)
        let fineRaw: CGFloat = (ppu / 60 - 4) / 3
        let fine: Double = Double(min(max(fineRaw, 0), 1))
        let tickWidth: CGFloat = max(1, 1.8 * k)

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
        let bandTop: CGFloat = markTop - 5 * k
        if right - left > 1.5 {
            let width: CGFloat = right - left
            context.fill(
                Path(roundedRect: CGRect(x: left, y: bandTop, width: width, height: baseline - bandTop),
                     cornerRadius: 3 * k),
                with: .color(Palette.good.opacity(0.16)))
            context.fill(
                Path(roundedRect: CGRect(x: left, y: bandTop, width: max(width, 2.5), height: max(2, 4 * k)),
                     cornerRadius: 1.5),
                with: .color(Palette.good.opacity(0.85)))
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
            let span: CGFloat = baseline - markTop
            let tickHeight: CGFloat = major ? span * 0.8 : span * 0.5
            var tick = Path()
            tick.move(to: CGPoint(x: px, y: baseline))
            tick.addLine(to: CGPoint(x: px, y: baseline - tickHeight))
            context.stroke(tick, with: .color(Palette.text.opacity(f * strength * 0.62)), lineWidth: tickWidth)
        }

        var lastRight: CGFloat = -CGFloat.greatestFiniteMagnitude
        for mark in marks {
            let px: CGFloat = x(mark.p)
            let f: Double = fade(px)
            if f <= 0 { continue }
            let inside: Bool = mark.p >= near - 0.004 && mark.p <= far + 0.004
            let color: Color = inside ? Palette.good : Palette.text
            var tick = Path()
            tick.move(to: CGPoint(x: px, y: baseline))
            tick.addLine(to: CGPoint(x: px, y: markTop))
            context.stroke(tick, with: .color(color.opacity(f)), lineWidth: tickWidth * (inside ? 1.6 : 1.3))

            let underPointer: Bool = abs(mark.p - position) < 0.012
            let label = Text(mark.label)
                .font(AppTypography.bold(size: (underPointer ? 38 : 32) * k))
                .foregroundColor(color.opacity(f))
            let text = context.resolve(label)
            let textWidth: CGFloat = text.measure(in: CGSize(width: 400, height: 80)).width

            guard underPointer || px - textWidth / 2 > lastRight + 4 else { continue }
            context.draw(text, at: CGPoint(x: px, y: numberY), anchor: .center)
            lastRight = px + textWidth / 2
        }

        // The pointer: a yellow line through the tape, like the EV marker.
        var pointer = Path()
        pointer.move(to: CGPoint(x: cx, y: markTop - 8 * k))
        pointer.addLine(to: CGPoint(x: cx, y: baseline))
        context.stroke(pointer, with: .color(Palette.accent),
                       style: StrokeStyle(lineWidth: max(2, 3 * k), lineCap: .butt))
    }
}

// MARK: - Hold button

struct HoldControl: View {
    let frozen: Bool
    let k: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .trailing) {
                Capsule()
                    .fill(Palette.panel)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.06), lineWidth: 0.75))

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
            .animation(.spring(response: 0.3, dampingFraction: 0.72), value: frozen)
        }
        .buttonStyle(PressStyle(scale: 0.97))
        .accessibilityLabel(frozen ? "Unfreeze exposure" : "Freeze exposure")
    }
}

// MARK: - Viewfinder overlays

struct EVChip: View {
    @ObservedObject var damp: Damper
    let frozen: Bool
    let spot: Bool
    let comp: Double

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
            if comp != 0 {
                Text(Fmt.stops(comp)).foregroundStyle(Palette.accent)
            }
        }
        .font(AppTypography.font(size: 11, weight: .medium))
        .foregroundStyle(Palette.text)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.55), in: Capsule())
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
