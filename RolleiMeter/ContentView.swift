import SwiftUI
import UIKit
import AudioToolbox

private struct SpotReticle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) * 0.47
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        let inner = radius * 0.72
        let outer = radius * 0.98
        path.move(to: CGPoint(x: center.x - outer, y: center.y)); path.addLine(to: CGPoint(x: center.x - inner, y: center.y))
        path.move(to: CGPoint(x: center.x + inner, y: center.y)); path.addLine(to: CGPoint(x: center.x + outer, y: center.y))
        path.move(to: CGPoint(x: center.x, y: center.y - outer)); path.addLine(to: CGPoint(x: center.x, y: center.y - inner))
        path.move(to: CGPoint(x: center.x, y: center.y + inner)); path.addLine(to: CGPoint(x: center.x, y: center.y + outer))
        let dot = min(2.2, max(1.2, radius * 0.055))
        path.addEllipse(in: CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2))
        return path
    }
}

struct ContentView: View {
    @StateObject private var meter = CameraMeter()

    // Held in @State, not @StateObject, so 60 fps value changes only redraw the views that watch them.
    // The EV needle starts low and winds up to the first reading.
    @State private var evDamp = Damper(count: 1, initial: 2, stiffness: 70, damping: 12)

    @AppStorage("mode") private var mode: MeterMode = .matrix   // matrix or highlight
    @AppStorage("isoIndex") private var isoIndex = 6      // ISO 100
    @AppStorage("evIndex") private var evIndex = 6        // 0 compensation
    @AppStorage("useDIN") private var useDIN = false
    @AppStorage("useFeet") private var useFeet = false
    @AppStorage("simpleAperture") private var apertureStop = 0     // 0 = f/2.8 … 6 = f/22
    @AppStorage("autoAperture") private var autoAperture = false
    @AppStorage("calibration") private var calibration = 0.0
    /// Metres from the phone (held at a natural distance) back to the eye. Added silently to LiDAR readings.
    @AppStorage("armOffset") private var armOffset = 0.0

    @State private var frozenEV: Double?
    @State private var frozenDist: Double?
    @State private var frozenPreviewImage: UIImage?
    @State private var trayOpen = false
    /// Spot metering only happens after a hold in the viewfinder. Tapping a mode chip goes back.
    @State private var spotActive = false
    @State private var spot = CGPoint(x: 0.5, y: 0.5)      // spot meter point (press and hold), viewfinder coordinates
    @State private var spotBuf = CGPoint(x: 0.5, y: 0.5)   // the same point in camera-frame coordinates
    @State private var focus = CGPoint(x: 0.5, y: 0.5)     // LiDAR distance point (tap), viewfinder coordinates
    @State private var focusPulse = 0
    @State private var focusBuf = CGPoint(x: 0.5, y: 0.5)  // the same point in camera-frame coordinates
    @State private var spotGestureLive = false
    @State private var suppressTap = false
    @State private var showHint = false
    @AppStorage("hintCount") private var hintCount = 0
    @State private var spotRadius: CGFloat = 0.05
    @State private var pinchBase: CGFloat = 0.05
    @State private var blink = false
    @State private var night = false
    @State private var nightSince: Date?
    /// Brief name of the metering mode, shown beside its button after a change.
    @State private var modeCaption: String?
    @State private var captionToken = 0

    private var safeISOIndex: Int { min(max(isoIndex, 0), ISOScale.values.count - 1) }
    private var safeEVIndex: Int { min(max(evIndex, 0), EVComp.values.count - 1) }
    /// The stop on the drum.
    private var apertureIndex: Int { min(max(apertureStop, 0), Rollei.stops.count - 1) }

    /// Auto: the widest stop whose shutter is no faster than the camera's top speed. Wider always
    /// means faster, so it is the first stop from f/2.8 that isn't blown.
    private var autoApertureIndex: Int {
        let reading = ev
        for i in Rollei.stops.indices {
            let t = Exposure.idealShutter(ev100: reading, iso: iso, comp: comp, n: Rollei.stops[i].n)
            if t >= Rollei.fastest { return i }
        }
        return Rollei.stops.count - 1
    }

    /// What the drum, the shutter panel and the focus scale all agree on.
    private var resolvedApertureIndex: Int { autoAperture ? autoApertureIndex : apertureIndex }
    private var resolvedAperture: (label: String, n: Double) { Rollei.stops[resolvedApertureIndex] }

    private var iso: Double { Double(ISOScale.values[safeISOIndex]) }
    private var comp: Double { EVComp.values[safeEVIndex] }
    private var liveEV: Double { meter.sceneEV + calibration }
    private var ev: Double { frozenEV ?? liveEV }

    /// LiDAR distance plus the arm offset, so it is the distance from the film plane, not from the phone.
    private var shownDistance: Double? {
        guard let raw = frozenEV != nil ? frozenDist : meter.distance else { return nil }
        return raw + armOffset
    }

    private var baseMode: MeterMode { mode == .spot ? .matrix : mode }
    private var engineMode: MeterMode { spotActive ? .spot : baseMode }

    private var tooClose: Bool {
        guard let d = shownDistance else { return false }
        return d < Focus.nearest
    }

    private var advice: FocusAdvice? {
        guard let d = shownDistance, d >= Focus.nearest else { return nil }
        return Focus.advice(subject: d, aperture: resolvedAperture.n, feet: useFeet)
    }

    var body: some View {
        VStack(spacing: 10) {
            topBar
            preview

            if trayOpen {
                ControlTray(
                    evIndex: $evIndex,
                    isoIndex: $isoIndex,
                    useDIN: $useDIN,
                    useFeet: $useFeet,
                    calibration: $calibration,
                    armOffset: $armOffset,
                    rawDistance: { meter.distance }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            SimpleExposurePair(
                damp: evDamp, iso: iso, comp: comp,
                apertureIndex: resolvedApertureIndex,
                distance: shownDistance, tooClose: tooClose, feet: useFeet
            )

            controls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaperBackground().ignoresSafeArea())
        .preferredColorScheme(night ? .dark : .light)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if mode == .spot { mode = .matrix }   // older versions could save spot as the mode
            pushConfig()
            evDamp.set([ev])
            meter.start()
            hintCount += 1
            if hintCount <= 3 {
                showHint = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                    withAnimation(.easeOut(duration: 0.4)) { showHint = false }
                }
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            meter.stop()
        }
        .onChange(of: mode) { pushConfig() }
        .onChange(of: spotActive) { pushConfig() }
        .onChange(of: spotBuf) { pushConfig() }
        .onChange(of: focusBuf) { pushConfig() }
        .onChange(of: spotRadius) { pushConfig() }
        .onChange(of: meter.sceneEV) {
            evDamp.set([ev])
            updateNight()
        }
        .onChange(of: calibration) { evDamp.set([ev]) }
        .onChange(of: frozenEV) { evDamp.set([ev]) }
        .onChange(of: tooClose) {
            if tooClose { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        }
        // A small click as the focus ring passes each engraved mark.
        .onChange(of: advice?.label) {
            if advice != nil { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.45) }
        }
    }

    private func pushConfig() {
        meter.setConfig(mode: engineMode, spot: spotBuf, radius: spotRadius, focus: focusBuf)
    }

    /// Switch to the dark palette in dim scenes, and back again in bright ones.
    /// Needs a couple of seconds in the new light, so a quick glance at a dark corner does nothing.
    private func updateNight() {
        let wantNight = night ? liveEV < 6.5 : liveEV < 5.0
        if wantNight == night {
            nightSince = nil
            return
        }
        guard let since = nightSince else {
            nightSince = Date()
            return
        }
        if Date().timeIntervalSince(since) > (night ? 1.5 : 2.5) {
            withAnimation(.easeInOut(duration: 0.8)) { night = wantNight }
            nightSince = nil
        }
    }

    private func toggleFreeze() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        if frozenEV == nil {
            shutterBlink()
            frozenPreviewImage = meter.previewSnapshot()
            frozenEV = liveEV
            frozenDist = meter.distance
        } else {
            unfreeze()
        }
    }

    /// A very short dip to black and the camera shutter click, like a mirror slap.
    private func shutterBlink() {
        AudioServicesPlaySystemSound(1108)
        blink = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(.easeOut(duration: 0.2)) { blink = false }
        }
    }

    private func normalized(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: min(max(p.x / max(size.width, 1), 0), 1), y: min(max(p.y / max(size.height, 1), 0), 1))
    }

    private func unfreeze() {
        frozenEV = nil
        frozenDist = nil
        frozenPreviewImage = nil
    }

    /// A stop picked by hand. Touching the drum always means "I'll take it".
    private func pickAperture(_ index: Int) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            autoAperture = false
            apertureStop = min(max(index, 0), Rollei.stops.count - 1)
        }
    }

    private func toggleAutoAperture() {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            autoAperture.toggle()
        }
    }

    private func returnHomeAperture() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            autoAperture = false
            apertureStop = 3
        }
    }

    /// The camera frame is 3:4 and the viewfinder fills its box, cropping whatever overflows.
    /// Converts a point in the box (0...1) to a point in the camera frame (0...1).
    private func bufferPoint(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let frame = 0.75
        let aspect = size.width / max(size.height, 1)
        if aspect < frame {
            return CGPoint(x: 0.5 + (p.x - 0.5) * aspect / frame, y: p.y)
        }
        return CGPoint(x: p.x, y: 0.5 + (p.y - 0.5) * frame / aspect)
    }

    // MARK: - Viewfinder

    private var preview: some View {
        GeometryReader { geo in
            ZStack {
                CameraPreview(session: meter.session, onVolumePress: { toggleFreeze() })

                if let frozenPreviewImage {
                    Image(uiImage: frozenPreviewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .overlay(Palette.lensLight.opacity(0.04))
                        .transition(.opacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                // Tap = measure distance there (the crosshair).
                // Press, hold and drag = spot meter there. Pinch = resize the spot.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture().onEnded { value in
                            if suppressTap { return }
                            let p = normalized(value.location, geo.size)
                            focusBuf = bufferPoint(p, in: geo.size)
                            focusPulse &+= 1
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) { focus = p }
                            unfreeze()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    )
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.4)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .onChanged { value in
                                guard case .second(true, let drag?) = value else { return }
                                if !spotGestureLive {
                                    spotGestureLive = true
                                    suppressTap = true
                                    unfreeze()
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                }
                                let p = normalized(drag.location, geo.size)
                                spotBuf = bufferPoint(p, in: geo.size)
                                withAnimation(.interactiveSpring) {
                                    spot = p
                                    spotActive = true
                                }
                            }
                            .onEnded { _ in
                                spotGestureLive = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { suppressTap = false }
                            }
                    )
                    .simultaneousGesture(
                        MagnifyGesture()
                            .onChanged { value in
                                spotRadius = min(max(pinchBase * value.magnification, 0.02), 0.15)
                            }
                            .onEnded { _ in
                                pinchBase = spotRadius
                            }
                    )

                if spotActive {
                    let d = spotRadius * 2 * max(geo.size.width, geo.size.height * 0.75)
                    SpotReticle()
                        .stroke(Palette.lensLight.opacity(0.96), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        .shadow(color: Palette.lensDark.opacity(0.45), radius: 1.5)
                        .frame(width: d, height: d)
                        .position(x: spot.x * geo.size.width, y: spot.y * geo.size.height)
                        .animation(.spring(response: 0.4, dampingFraction: 0.72), value: spot)
                        .animation(.interactiveSpring, value: spotRadius)
                        .transition(.scale(scale: 1.6).combined(with: .opacity))
                        .allowsHitTesting(false)

                    // How far the spot sits from the overall scene, in stops.
                    if let delta = meter.spotDelta {
                        Text(Fmt.stops(delta))
                            .font(AppTypography.font(size: 12, weight: .medium))
                            .foregroundStyle(Palette.lensLight)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Palette.lensDark.opacity(0.62), in: Capsule())
                            .contentTransition(.numericText())
                            .position(x: spot.x * geo.size.width, y: max(14, spot.y * geo.size.height - d / 2 - 14))
                            .animation(.spring(response: 0.4, dampingFraction: 0.72), value: spot)
                            .animation(.smooth(duration: 0.15), value: Fmt.stops(delta))
                            .allowsHitTesting(false)
                    }
                }

                if meter.hasLiDAR {
                    FocusMarker(tooClose: tooClose, pulseID: focusPulse)
                    .position(x: focus.x * geo.size.width, y: focus.y * geo.size.height)
                    .animation(.spring(response: 0.4, dampingFraction: 0.72), value: focus)
                    .allowsHitTesting(false)
                }

                if showHint {
                    Text("Tap: distance   ·   Hold: spot meter")
                        .font(AppTypography.next(size: 12, weight: .medium))
                        .foregroundStyle(Palette.lensLight)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Palette.lensDark.opacity(0.88), in: Capsule())
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.3)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }

                if meter.denied {
                    VStack(spacing: 10) {
                        Text("Camera access is off")
                            .font(AppTypography.next(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("OPEN SETTINGS")
                                .font(AppTypography.next(size: 12, weight: .semibold))
                                .tracking(1)
                                .foregroundStyle(Palette.accent)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(20)
                    .modifier(Panel())
                }

                // Shutter blink on freeze.
                Color.black
                    .opacity(blink ? 0.9 : 0)
                    .allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            EVBadge(damp: evDamp, frozen: frozenEV != nil, spot: spotActive)
            Spacer(minLength: 12)
            trayKey
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    /// The tray key. A printed word, not a pictogram.
    private var trayKey: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                trayOpen.toggle()
            }
        } label: {
            Text("SET")
                .font(AppTypography.next(size: 10, weight: .medium))
                .tracking(1.3)
                .foregroundStyle(trayOpen ? Palette.paper : Palette.ink.opacity(0.78))
                .frame(width: 46, height: 46)
                .overlay(alignment: .topTrailing) {
                    // A small red dot while exposure compensation is on, so it can't be forgotten.
                    if safeEVIndex != EVComp.zeroIndex && !trayOpen {
                        Circle()
                            .fill(Palette.accent)
                            .frame(width: 7, height: 7)
                            .offset(x: -5, y: 5)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: safeEVIndex == EVComp.zeroIndex)
        }
        .buttonStyle(SetKeyStyle(active: trayOpen))
        .accessibilityLabel(trayOpen ? "Hide controls" : "Show controls")
        .accessibilityValue(safeEVIndex != EVComp.zeroIndex ? "Exposure compensation on" : "")
    }

    // MARK: - Metering mode

    /// What the metering key shows: spot wins while a spot is placed, otherwise matrix or highlight.
    private var meterChoice: MeterMode { spotActive ? .spot : baseMode }

    /// Matrix, then highlight, then spot, then round again.
    private func cycleMeterMode() {
        UISelectionFeedbackGenerator().selectionChanged()
        let next: MeterMode
        switch meterChoice {
        case .matrix: next = .highlight
        case .highlight: next = .spot
        case .spot: next = .matrix
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            if next == .spot {
                spotActive = true
            } else {
                mode = next
                spotActive = false
            }
        }
        unfreeze()
        showCaption(next.title.uppercased())
    }

    private func showCaption(_ text: String) {
        captionToken += 1
        let token = captionToken
        withAnimation(.easeOut(duration: 0.2)) { modeCaption = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard token == captionToken else { return }
            withAnimation(.easeOut(duration: 0.35)) { modeCaption = nil }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        ZStack {
            FreezeButton(frozen: frozenEV != nil) {
                toggleFreeze()
            }

            HStack(spacing: 0) {
                // Metering lives on the left, under the EV badge it belongs to.
                Button {
                    cycleMeterMode()
                } label: {
                    ZStack {
                        ModeGlyph(mode: meterChoice)
                            .id(meterChoice)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                    .frame(width: 60, height: 84)
                }
                .buttonStyle(PaperKeyStyle())
                .accessibilityLabel("Metering mode, \(meterChoice.title)")
                .accessibilityHint("Tap to change between matrix, highlight and spot")

                if let modeCaption {
                    Text(modeCaption)
                        .font(AppTypography.next(size: 11, weight: .medium))
                        .tracking(1)
                        .foregroundStyle(Palette.mutedInk)
                        .padding(.leading, 10)
                        .transition(.opacity)
                        .contentTransition(.opacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                Spacer(minLength: 0)

                // Aperture lives on the right, under the tray key.
                HStack(spacing: 6) {
                    AutoLamp(state: autoLampState)
                    ApertureDrum(
                        index: resolvedApertureIndex,
                        auto: autoAperture,
                        onPick: pickAperture,
                        onTap: toggleAutoAperture,
                        onHome: returnHomeAperture
                    )
                }
            }
        }
    }

    /// The lamp repeats the shutter panel's verdict beside your thumb.
    private var autoLampState: AutoLampState {
        guard autoAperture else { return .off }
        let t = Exposure.idealShutter(ev100: ev, iso: iso, comp: comp,
                                      n: resolvedAperture.n)
        let reading = Exposure.result(for: t)
        if reading.deviation != nil { return .bad }
        return reading.isSlow ? .slow : .good
    }
}
