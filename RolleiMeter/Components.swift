import SwiftUI
import AVFoundation
import AVKit
import UIKit

private let accentOrange = Color(red: 0.88, green: 0.42, blue: 0.22)
private let goldenGreen = Color(red: 0.25, green: 0.70, blue: 0.35)
private let warnRed = Color(red: 0.85, green: 0.20, blue: 0.20)
private let inkColor = Color(white: 0.15)

private struct Panel: ViewModifier {
    var stroke: Color = Color(white: 0.8)
    var lineWidth: CGFloat = 1

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.97))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(stroke, lineWidth: lineWidth))
        )
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

/// Thin bar: shutter speeds on top, ticks, apertures below.
/// An aperture turns red when its shutter speed is slower than 1/60.
struct RulerView: View {
    @ObservedObject var damp: Damper
    let iso: Double
    let comp: Double
    let golden: Int
    let selected: Int
    let onSelect: (Int) -> Void
    let onToggleGolden: (Int) -> Void

    @Namespace private var selectionNS

    private var results: [ShutterResult] {
        Rollei.stops.map {
            Exposure.result(for: Exposure.idealShutter(ev100: damp.values[0], iso: iso, comp: comp, n: $0.n))
        }
    }

    var body: some View {
        let res = results
        VStack(spacing: 2) {
            // Shutter speed. "500+" means even 1/500 is too slow to hold back the light.
            HStack(spacing: 0) {
                ForEach(Rollei.stops.indices, id: \.self) { i in
                    let r = res[i]
                    Text(r.label)
                        .font(.system(size: 16, weight: i == golden ? .semibold : .regular, design: .monospaced))
                        .foregroundStyle(r.status == .tooFast ? accentOrange : (i == golden ? goldenGreen : inkColor))
                        .contentTransition(.numericText())
                        .frame(maxWidth: .infinity)
                        .animation(.smooth(duration: 0.2), value: r.label)
                }
            }

            HStack(spacing: 0) {
                ForEach(Rollei.stops.indices, id: \.self) { _ in
                    ZStack {
                        Rectangle().fill(Color(white: 0.7)).frame(height: 1)
                        Rectangle().fill(Color(white: 0.3)).frame(width: 1.5, height: 8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Apertures. Tap selects (drives the depth-of-field band), long-press sets the golden one.
            HStack(spacing: 0) {
                ForEach(Rollei.stops.indices, id: \.self) { i in
                    let slow = res[i].isSlow
                    Text("ƒ" + Rollei.stops[i].label)
                        .font(.system(size: 16, weight: i == golden ? .semibold : .regular, design: .monospaced))
                        .foregroundStyle(slow ? warnRed : (i == golden ? goldenGreen : inkColor))
                        .animation(.smooth(duration: 0.25), value: slow)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            if selected == i {
                                Capsule()
                                    .fill(Color.black.opacity(0.08))
                                    .matchedGeometryEffect(id: "selection", in: selectionNS)
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
            .clipShape(RoundedRectangle(cornerRadius: 14))
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
                Circle().fill(Color(white: 0.84)).frame(width: 84, height: 84)
                Circle()
                    .fill(LinearGradient(colors: [Color.white, Color(white: 0.88)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 68, height: 68)
                    .scaleEffect(frozen ? 0.96 : 1)
                Circle()
                    .stroke(frozen ? accentOrange : Color(white: 0.72), lineWidth: frozen ? 4 : 1)
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
                .shadow(color: .black.opacity(0.55), radius: 2)
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
        .modifier(Panel(stroke: tooClose ? warnRed : Color(white: 0.8), lineWidth: tooClose ? 2 : 1))
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
                        .foregroundStyle(advice == nil ? Color(white: 0.55) : inkColor)
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
                        .foregroundStyle(Color(white: 0.55))
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
                        .fill(Color(white: 0.7))
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
                            .fill(i == 0 ? goldenGreen : Color(white: 0.3))
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
