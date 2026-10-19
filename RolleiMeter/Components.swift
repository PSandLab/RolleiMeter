import SwiftUI
import AVFoundation
import UIKit

private let accentOrange = Color(red: 0.88, green: 0.42, blue: 0.22)
private let goldenGreen = Color(red: 0.25, green: 0.70, blue: 0.35)
private let warnRed = Color(red: 0.85, green: 0.20, blue: 0.20)
private let inkColor = Color(white: 0.15)

private struct Panel: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.97))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(white: 0.8), lineWidth: 1))
        )
    }
}

// MARK: - Camera preview

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

// MARK: - EV badge

struct EVBadge: View {
    @ObservedObject var damp: Damper
    let frozen: Bool

    var body: some View {
        HStack(spacing: 6) {
            if frozen {
                Text("HOLD")
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
    }
}

// MARK: - Aperture / shutter ruler

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
        VStack(spacing: 4) {
            // Shutter speed, or a sun / moon when this aperture can't be exposed correctly.
            HStack(spacing: 0) {
                ForEach(Rollei.stops.indices, id: \.self) { i in
                    let r = res[i]
                    ZStack {
                        if r.error == 0 {
                            Text(r.label)
                                .font(.system(size: 16, weight: i == golden ? .semibold : .regular, design: .monospaced))
                                .foregroundStyle(i == golden ? goldenGreen : inkColor)
                                .contentTransition(.numericText())
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        } else {
                            Image(systemName: r.error > 0 ? "sun.max.fill" : "moon.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(warnRed)
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 22)
                    .animation(.smooth(duration: 0.25), value: r.error == 0)
                    .animation(.smooth(duration: 0.2), value: r.label)
                }
            }

            HStack(spacing: 0) {
                ForEach(Rollei.stops.indices, id: \.self) { _ in
                    ZStack {
                        Rectangle().fill(Color(white: 0.7)).frame(height: 1)
                        Rectangle().fill(Color(white: 0.3)).frame(width: 1.5, height: 12)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Apertures. Tap selects (drives the depth-of-field band), long-press sets the golden one.
            HStack(spacing: 0) {
                ForEach(Rollei.stops.indices, id: \.self) { i in
                    let bad = res[i].error != 0
                    ZStack {
                        if selected == i {
                            Capsule()
                                .fill(Color.black.opacity(0.08))
                                .matchedGeometryEffect(id: "selection", in: selectionNS)
                        }
                        Text("ƒ" + Rollei.stops[i].label)
                            .font(.system(size: 16, weight: i == golden ? .semibold : .regular, design: .monospaced))
                            .foregroundStyle(bad ? warnRed : (i == golden ? goldenGreen : inkColor))
                            .animation(.smooth(duration: 0.25), value: bad)
                    }
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(i) }
                    .onLongPressGesture(minimumDuration: 0.5) {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        onToggleGolden(i)
                    }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selected)

            // How far off, in stops.
            HStack(spacing: 0) {
                ForEach(Rollei.stops.indices, id: \.self) { i in
                    let e = res[i].error
                    Text(e == 0 ? "+0" : Fmt.stops(e))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(warnRed)
                        .opacity(e == 0 ? 0 : 1)
                        .contentTransition(.numericText())
                        .frame(maxWidth: .infinity)
                        .animation(.smooth(duration: 0.25), value: e)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .modifier(Panel())
    }
}

// MARK: - Wheel

struct WheelBox: View {
    let title: String
    @Binding var selection: Int
    let labels: [String]

    var body: some View {
        VStack(spacing: 6) {
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
                .frame(width: 100, height: 104)
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
                Circle().fill(Color(white: 0.84)).frame(width: 88, height: 88)
                Circle()
                    .fill(LinearGradient(colors: [Color.white, Color(white: 0.88)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 72, height: 72)
                    .scaleEffect(frozen ? 0.96 : 1)
                Circle()
                    .stroke(frozen ? accentOrange : Color(white: 0.72), lineWidth: frozen ? 4 : 1)
                    .frame(width: 72, height: 72)
                    .scaleEffect(frozen ? 0.96 : 1)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: frozen)
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - Distance dial

/// Rollei 35 focusing scale. Marks are spaced by lens extension, like the real ring.
/// The orange triangle is the LiDAR distance; the orange band is the depth of field at the selected aperture.
struct DistanceDial: View {
    /// Channels: subject, near limit, far limit. All are 0...1 positions on the scale.
    @ObservedObject var damp: Damper
    let distance: Double?
    let near: Double?
    let far: Double?
    let feet: Bool
    let onTap: () -> Void

    private var marks: [(label: String, m: Double)] { feet ? Focus.feetMarks : Focus.meterMarks }

    var body: some View {
        let visible = distance != nil
        VStack(spacing: 0) {
            GeometryReader { geo in
                let inset: CGFloat = 22
                let w = geo.size.width - inset * 2
                let subjectX = inset + CGFloat(damp.values[0]) * w
                let nearX = inset + CGFloat(damp.values[1]) * w
                let farX = inset + CGFloat(damp.values[2]) * w

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color(white: 0.7))
                        .frame(width: w, height: 1)
                        .position(x: geo.size.width / 2, y: 18)

                    // Depth of field
                    Capsule()
                        .fill(accentOrange.opacity(0.38))
                        .frame(width: max(farX - nearX, 3), height: 9)
                        .position(x: (nearX + farX) / 2, y: 18)
                        .opacity(visible ? 1 : 0)
                    Rectangle()
                        .fill(accentOrange)
                        .frame(width: 2, height: 15)
                        .position(x: nearX, y: 18)
                        .opacity(visible ? 1 : 0)
                    Rectangle()
                        .fill(accentOrange)
                        .frame(width: 2, height: 15)
                        .position(x: farX, y: 18)
                        .opacity(visible ? 1 : 0)

                    // Rollei marks. The closest focusing distance is green.
                    ForEach(marks.indices, id: \.self) { i in
                        let x = inset + CGFloat(Focus.position(marks[i].m)) * w
                        Rectangle()
                            .fill(i == 0 ? goldenGreen : Color(white: 0.3))
                            .frame(width: 1.5, height: 12)
                            .position(x: x, y: 18)
                        Text(marks[i].label)
                            .font(.system(size: 14, weight: i == 0 ? .semibold : .regular, design: .monospaced))
                            .foregroundStyle(i == 0 ? goldenGreen : inkColor)
                            .position(x: x, y: 38)
                    }

                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(accentOrange)
                        .position(x: subjectX, y: 5)
                        .opacity(visible ? 1 : 0)
                }
                .animation(.smooth(duration: 0.3), value: visible)
            }
            .frame(height: 48)

            HStack {
                Text(near.map { Fmt.distance($0, feet: feet) } ?? "")
                    .foregroundStyle(accentOrange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(Fmt.distance(distance, feet: feet))
                    .foregroundStyle(distance == nil ? Color(white: 0.55) : inkColor)
                    .frame(maxWidth: .infinity)
                Text(far.map { Fmt.distance($0, feet: feet) } ?? "")
                    .foregroundStyle(accentOrange)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .contentTransition(.numericText())
            .animation(.smooth(duration: 0.2), value: distance)
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .modifier(Panel())
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}
