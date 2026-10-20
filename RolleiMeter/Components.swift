import SwiftUI
import AVFoundation
import AVKit
import UIKit

private let paper = Color(red: Double(0xF1) / 255.0, green: Double(0xEE) / 255.0, blue: Double(0xE6) / 255.0)
private let inkColor = Color(red: Double(0x26) / 255.0, green: Double(0x26) / 255.0, blue: Double(0x26) / 255.0)
private let mutedInk = Color(red: Double(0x8B) / 255.0, green: Double(0x89) / 255.0, blue: Double(0x82) / 255.0)
private let hairline = Color(red: Double(0xD4) / 255.0, green: Double(0xD0) / 255.0, blue: Double(0xC7) / 255.0)
private let accentOrange = Color(red: Double(0xB6) / 255.0, green: Double(0x5B) / 255.0, blue: Double(0x4B) / 255.0)
private let goldenGreen = Color(red: Double(0x25) / 255.0, green: Double(0x70) / 255.0, blue: Double(0x35) / 255.0)
private let warnRed = accentOrange

private struct Panel: ViewModifier {
    var stroke: Color = hairline
    var lineWidth: CGFloat = 1

    func body(content: Content) -> some View {
        content.background(Rectangle().fill(paper).overlay(Rectangle().stroke(stroke, lineWidth: lineWidth)))
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
        .font(.system(size: 13, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.55), in: Capsule())
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
                    Text(r.label)
                        .font(.system(size: 16, weight: i == golden ? .semibold : .regular, design: .monospaced))
                        .foregroundStyle(r.status == .ok ? (i == golden ? goldenGreen : inkColor) : accentOrange)
                        .contentTransition(.numericText())
                        .frame(maxWidth: .infinity)
                        .animation(.smooth(duration: 0.2), value: r.label)
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
                    let reading = res[i]
                    VStack(spacing: 1) {
                        Text("f/" + Rollei.stops[i].label)
                            .font(.system(size: 11, weight: i == golden ? .semibold : .regular, design: .monospaced))
                            .foregroundStyle(reading.deviation == nil ? (i == golden ? goldenGreen : inkColor) : paper)
                            .frame(height: 14)
                        Text(reading.deviation.map(Fmt.exposureDeviation) ?? "")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(paper)
                            .frame(height: 10)
                    }
                    .frame(height: 30)
                    .background(reading.deviation == nil ? Color.clear : accentOrange)
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

// MARK: - Simple exposure pair

private struct SimpleApertureColumn: View {
    let damp: Damper
    let iso: Double
    let comp: Double
    let aperture: (label: String, n: Double)
    let symbol: String
    let selected: Bool
    let onSelect: () -> Void

    private var idealTime: Double {
        Exposure.idealShutter(ev100: damp.values[0], iso: iso, comp: comp, n: aperture.n)
    }
    private var reading: ShutterResult { Exposure.result(for: idealTime) }
    private var rulerPosition: Double {
        min(max(log2(max(idealTime, Rollei.fastest) / Rollei.fastest), 0), log2(Rollei.slowest / Rollei.fastest))
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .regular))
                Text("f/" + aperture.label)
                    .font(.system(size: 17, weight: .medium, design: .monospaced))
                Spacer(minLength: 0)
                if let deviation = reading.deviation {
                    Text(Fmt.exposureDeviation(deviation))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                }
            }
            .foregroundStyle(reading.deviation == nil ? inkColor : paper)
            .padding(.horizontal, 9)
            .frame(height: 42)
            .background(reading.deviation == nil ? Color.clear : accentOrange)
            .overlay(alignment: .bottom) {
                Rectangle().fill(selected ? inkColor : Color.clear).frame(height: 1)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)

            GeometryReader { geo in
                let center = geo.size.width / 2
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(hairline).frame(height: 1).offset(y: 14)
                    ForEach(Rollei.speeds.indices.reversed(), id: \.self) { i in
                        let speed = Rollei.speeds[i]
                        let coordinate = log2(Rollei.slowest / speed.t)
                        let x = center + CGFloat(coordinate - rulerPosition) * 38
                        VStack(spacing: 3) {
                            Rectangle().fill(hairline).frame(width: 1, height: i == 0 || i == Rollei.speeds.count - 1 ? 10 : 6)
                            Text(speed.label)
                                .font(.system(size: 9, weight: .regular, design: .monospaced))
                                .foregroundStyle(mutedInk)
                        }
                        .fixedSize()
                        .position(x: x, y: 23)
                    }
                    Rectangle().fill(inkColor).frame(width: 1.5, height: 20)
                        .position(x: center, y: 9)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            .frame(height: 43)

            Text(reading.label)
                .font(.system(size: 24, weight: .medium, design: .monospaced))
                .foregroundStyle(inkColor)
                .contentTransition(.numericText())
                .frame(height: 30)
                .frame(maxWidth: .infinity)
                .animation(.smooth(duration: 0.18), value: reading.label)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
    }
}

struct SimpleExposurePair: View {
    @ObservedObject var damp: Damper
    let iso: Double
    let comp: Double
    let selected: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            SimpleApertureColumn(damp: damp, iso: iso, comp: comp, aperture: Rollei.stops[0], symbol: "person.crop.portrait", selected: selected == 0, onSelect: { onSelect(0) })
            Rectangle().fill(hairline).frame(width: 1).padding(.vertical, 8)
            SimpleApertureColumn(damp: damp, iso: iso, comp: comp, aperture: Rollei.stops[3], symbol: "mountain.2", selected: selected == 3, onSelect: { onSelect(3) })
        }
        .background(paper)
        .overlay(Rectangle().stroke(hairline, lineWidth: 1))
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
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
            ZStack(alignment: .trailing) {
                Picker(title, selection: $selection) {
                    ForEach(labels.indices, id: \.self) { i in
                        Text(labels[i])
                            .font(.system(size: 16, design: .monospaced))
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
            .clipShape(Rectangle())
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

/// Shows exactly where LiDAR is measuring, with the distance next to it.
struct FocusMarker: View {
    let text: String?
    let tooClose: Bool
    let labelAbove: Bool

    var body: some View {
        ZStack {
            FocusBrackets()
                .stroke(tooClose ? warnRed : Color.white,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .frame(width: 34, height: 34)
            if let text {
                Text(text)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background((tooClose ? warnRed : Color.black).opacity(0.65), in: Capsule())
                    .offset(y: labelAbove ? -32 : 32)
                    .contentTransition(.numericText())
            }
        }
        .frame(width: 34, height: 34)
        .animation(.smooth(duration: 0.2), value: text)
        .animation(.smooth(duration: 0.2), value: tooClose)
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
    @Binding var expanded: Bool
    let onToggleUnits: () -> Void

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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .modifier(Panel(stroke: tooClose ? warnRed : hairline, lineWidth: tooClose ? 2 : 1))
        .animation(.smooth(duration: 0.25), value: tooClose)
    }

    // MARK: summary row

    private var bigText: String {
        guard let a = advice else { return "—" }
        return a.label == "∞" ? "∞" : a.label + " " + unit
    }

    private var summary: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("FOCUS")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                if tooClose {
                    TimelineView(.animation) { ctx in
                        Text("TOO CLOSE")
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundStyle(warnRed)
                            .opacity(0.65 + 0.35 * sin(ctx.date.timeIntervalSinceReferenceDate * 7))
                    }
                } else {
                    Text(bigText)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundStyle(advice == nil ? mutedInk : inkColor)
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.2), value: bigText)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                if tooClose {
                    Text("now " + Fmt.distance(distance, feet: feet))
                        .foregroundStyle(warnRed)
                    Text("min " + (feet ? "3 ft" : "0.9 m"))
                        .foregroundStyle(warnRed)
                } else if let d = distance, let a = advice {
                    Text(Fmt.distance(d, feet: feet) + " measured")
                        .foregroundStyle(inkColor)
                    if a.sharp {
                        Text("✓ sharp at ƒ" + aperture)
                            .foregroundStyle(goldenGreen)
                    } else {
                        Text("set between \(a.lo) and \(a.hi)")
                            .foregroundStyle(accentOrange)
                    }
                } else {
                    Text("no LiDAR reading")
                        .foregroundStyle(mutedInk)
                }
            }
            .font(.system(size: 12, weight: .semibold, design: .monospaced))

            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
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
                let inset: CGFloat = 12
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
                            .font(.system(size: 14, weight: i == 0 ? .semibold : .regular, design: .monospaced))
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
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(inkColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                Text(far.map { Fmt.distance($0, feet: feet) } ?? "")
                    .foregroundStyle(accentOrange)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .contentTransition(.numericText())
            .animation(.smooth(duration: 0.2), value: distance)
            .padding(.top, 2)
            .padding(.horizontal, 6)
        }
        .padding(.top, 6)
    }
}
