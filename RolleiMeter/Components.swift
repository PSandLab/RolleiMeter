import SwiftUI
import AVFoundation
import AVKit
import UIKit

private let paper = Color(red: Double(0xF1) / 255.0, green: Double(0xEE) / 255.0, blue: Double(0xE6) / 255.0)
private let inkColor = Color(red: Double(0x26) / 255.0, green: Double(0x26) / 255.0, blue: Double(0x26) / 255.0)
private let mutedInk = Color(red: Double(0x8B) / 255.0, green: Double(0x89) / 255.0, blue: Double(0x82) / 255.0)
private let hairline = Color(red: Double(0xD4) / 255.0, green: Double(0xD0) / 255.0, blue: Double(0xC7) / 255.0)
private let accentOrange = Color(red: Double(0xB3) / 255.0, green: Double(0x26) / 255.0, blue: Double(0x31) / 255.0)
private let goldenGreen = Color(red: Double(0x4C) / 255.0, green: Double(0x6B) / 255.0, blue: Double(0x52) / 255.0)
private let warnRed = accentOrange
private let inRangeGreen = goldenGreen

private struct Panel: ViewModifier {
    var stroke: Color = hairline
    var lineWidth: CGFloat = 1

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(paper)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(stroke, lineWidth: lineWidth))
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

struct EVBadge: View {
    @ObservedObject var damp: Damper
    let frozen: Bool
    let spot: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(accentOrange)
            if frozen {
                Text("HOLD")
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            if spot {
                Text("SPOT")
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Text("EV " + String(format: "%.1f", damp.values[0]))
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
                        .foregroundStyle(r.deviation == nil ? (i == golden ? goldenGreen : inkColor) : accentOrange)
                        .contentTransition(.numericText())
                        .frame(maxWidth: .infinity)
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
                            Rectangle().fill(selected == i ? inkColor : Color.clear).frame(height: 1)
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
        guard let deviation = reading.deviation else { return "" }
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
            Text(reading.deviation.map(Fmt.exposureAmount) ?? reading.label)
                .font(AppTypography.bold(size: 80))
                .foregroundStyle(paper)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.62)
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
        .background(outOfRange ? accentOrange : inRangeGreen)
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
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                Text("FOCUS").font(AppTypography.next(size: 12, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(mutedInk)

            Spacer(minLength: 2)
            if tooClose {
                Text("0")
                    .font(AppTypography.bold(size: 68))
                    .foregroundStyle(warnRed)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let distance {
                FocusRingScale(distance: distance, aperture: aperture, feet: feet)
                    .frame(maxWidth: .infinity)
                    .frame(height: 128)
            } else {
                Text("NO LIDAR")
                    .font(AppTypography.next(size: 11, weight: .medium))
                    .tracking(0.7)
                    .foregroundStyle(mutedInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Spacer(minLength: 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(minHeight: 174, maxHeight: 174)
        .background(paper)
        .accessibilityElement(children: .contain)
    }
}

/// A large lens-style focus scale. The red index remains fixed while the engraved
/// distance marks and aperture-specific depth-of-field arc rotate underneath it.
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
        GeometryReader { geometry in
            let size = geometry.size
            let diameter = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = diameter * 0.34
            let labelRadius = diameter * 0.445
            let rotation = 90 - 180 * Focus.position(distance)
            let ringMarks = marks
            let markPositions = ringMarks.map { Focus.position($0.m) }
            let nearPosition = Focus.position(depthRange.near)
            let farPosition = Focus.position(depthRange.far)

            ZStack {
                ZStack {
                    Canvas { context, canvasSize in
                        let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                        func point(_ p: Double, radius: CGFloat) -> CGPoint {
                            let angle = Double.pi + Double.pi * p
                            return CGPoint(
                                x: c.x + CGFloat(cos(angle)) * radius,
                                y: c.y + CGFloat(sin(angle)) * radius
                            )
                        }
                        func arc(_ start: Double, _ end: Double) -> Path {
                            var path = Path()
                            let steps = max(2, Int(abs(end - start) * 100))
                            for step in 0...steps {
                                let p = start + (end - start) * Double(step) / Double(steps)
                                let value = point(p, radius: radius)
                                if step == 0 { path.move(to: value) } else { path.addLine(to: value) }
                            }
                            return path
                        }

                        context.stroke(
                            arc(0, 1),
                            with: .color(hairline),
                            style: StrokeStyle(lineWidth: 1, lineCap: .round)
                        )
                        context.stroke(
                            arc(nearPosition, farPosition),
                            with: .color(goldenGreen.opacity(0.9)),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )

                        var ticks = Path()
                        for step in 0...100 {
                            let p = Double(step) / 100
                            let isLensMark = markPositions.contains { abs($0 - p) < 0.005 }
                            let isMedium = step.isMultiple(of: 5)
                            let length: CGFloat = isLensMark ? 8 : (isMedium ? 5 : 2.5)
                            let inner = point(p, radius: radius - length / 2)
                            let outer = point(p, radius: radius + length / 2)
                            ticks.move(to: inner)
                            ticks.addLine(to: outer)
                        }
                        context.stroke(ticks, with: .color(mutedInk), lineWidth: 1)
                    }
                    .frame(width: diameter, height: diameter)

                    ForEach(ringMarks.indices, id: \.self) { index in
                        let mark = ringMarks[index]
                        let p = markPositions[index]
                        let angle = Double.pi + Double.pi * p
                        Text(mark.label)
                            .font(AppTypography.mono(size: 10, weight: .medium))
                            .foregroundStyle(inkColor)
                            .fixedSize()
                            .position(
                                x: center.x + CGFloat(cos(angle)) * labelRadius,
                                y: center.y + CGFloat(sin(angle)) * labelRadius
                            )
                    }
                }
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(rotation))
                .animation(.spring(response: 0.38, dampingFraction: 0.84), value: distance)

                // Fixed index: the rotating lens scale turns behind this point.
                Path { path in
                    path.move(to: CGPoint(x: center.x, y: center.y - radius - 10))
                    path.addLine(to: CGPoint(x: center.x, y: center.y - radius - 1))
                }
                .stroke(accentOrange, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accentOrange)
                    .position(x: center.x, y: center.y - radius - 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus ring. Set \(recommendedFocus). Depth of field at f/\(aperture.label).")
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
                .foregroundStyle(accentOrange)
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

// MARK: - Wheel

struct WheelBox: View {
    let title: String
    @Binding var selection: Int
    let labels: [String]

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(AppTypography.next(size: 12))
                .foregroundStyle(.secondary)
            ZStack(alignment: .trailing) {
                Picker(title, selection: $selection) {
                    ForEach(labels.indices, id: \.self) { i in
                        Text(labels[i])
                            .font(AppTypography.mono(size: 16))
                            .tag(i)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 100, height: 92)
                .clipped()

                Image(systemName: "arrowtriangle.left.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(accentOrange)
                    .padding(.trailing, 5)
                    .allowsHitTesting(false)
            }
            .modifier(Panel())
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onChange(of: selection) {
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
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
                    .stroke(frozen ? accentOrange : mutedInk, lineWidth: frozen ? 4 : 1)
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
            .stroke(tooClose ? warnRed : paper,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .frame(width: 30, height: 30)
            .animation(.smooth(duration: 0.2), value: tooClose)
            .allowsHitTesting(false)
    }
}

// MARK: - Focus panel

/// Compact by default: the nearest mark on the Rollei's focus ring for the measured distance.
/// Tap it to open the full scale with the depth-of-field band.
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

    private var marks: [(label: String, m: Double)] { feet ? Focus.feetMarks : Focus.meterMarks }
    private var unit: String { feet ? "ft" : "m" }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { expanded.toggle() }
            } label: {
                summary
            }
            .buttonStyle(.plain)

            if expanded {
                scale
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .modifier(Panel(stroke: tooClose ? warnRed : hairline, lineWidth: tooClose ? 1.5 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(.smooth(duration: 0.25), value: tooClose)
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
        return advice.sharp ? goldenGreen : accentOrange
    }

    private var summary: some View {
        HStack(spacing: 5) {
            Text("FOCUS")
                .font(AppTypography.next(size: 9, weight: .medium))
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
        let tint = tooClose ? warnRed : accentOrange

        return VStack(spacing: 0) {
            GeometryReader { geo in
                let inset: CGFloat = 8
                let w = geo.size.width - inset * 2
                let subjectX = inset + CGFloat(damp.values[0]) * w
                let nearX = inset + CGFloat(damp.values[1]) * w
                let farX = inset + CGFloat(damp.values[2]) * w

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(hairline)
                        .frame(width: w, height: 1)
                        .position(x: geo.size.width / 2, y: 17)

                    // Depth of field
                    Capsule()
                        .fill(accentOrange.opacity(0.38))
                        .frame(width: max(farX - nearX, 3), height: 9)
                        .position(x: (nearX + farX) / 2, y: 17)
                        .opacity(showBand ? 1 : 0)
                    Rectangle()
                        .fill(accentOrange)
                        .frame(width: 2, height: 15)
                        .position(x: nearX, y: 17)
                        .opacity(showBand ? 1 : 0)
                    Rectangle()
                        .fill(accentOrange)
                        .frame(width: 2, height: 15)
                        .position(x: farX, y: 17)
                        .opacity(showBand ? 1 : 0)

                    // Rollei marks. The closest focusing distance is green.
                    ForEach(marks.indices, id: \.self) { i in
                        let x = inset + CGFloat(Focus.position(marks[i].m)) * w
                        Rectangle()
                            .fill(i == 0 ? goldenGreen : mutedInk)
                            .frame(width: 1.5, height: 12)
                            .position(x: x, y: 17)
                        Text(marks[i].label)
                            .font(AppTypography.font(size: 14, weight: i == 0 ? .semibold : .regular))
                            .foregroundStyle(i == 0 ? goldenGreen : inkColor)
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
                    .foregroundStyle(accentOrange)
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
                    .foregroundStyle(accentOrange)
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
