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
    @State private var distDamp = Damper(count: 3, initial: 0.5, stiffness: 110, damping: 17)

    @AppStorage("simpleMode") private var simpleMode = false
    @AppStorage("mode") private var mode: MeterMode = .matrix   // matrix or highlight
    @AppStorage("isoIndex") private var isoIndex = 6      // ISO 100
    @AppStorage("evIndex") private var evIndex = 6        // 0 compensation
    @AppStorage("useDIN") private var useDIN = false
    @AppStorage("useFeet") private var useFeet = false
    @AppStorage("golden") private var golden = 2          // f/5.6, -1 = none
    @AppStorage("aperture") private var selected = 2      // aperture used for depth of field
    @AppStorage("simpleAperture") private var simpleAperture = 0
    @AppStorage("calibration") private var calibration = 0.0
    /// Metres from the phone (held at a natural distance) back to the eye. Added silently to LiDAR readings.
    @AppStorage("armOffset") private var armOffset = 0.0

    @State private var frozenEV: Double?
    @State private var frozenDist: Double?
    @State private var frozenPreviewImage: UIImage?
    @State private var trayOpen = false
    @State private var distPrimed = false
    /// Spot metering only happens after a hold in the viewfinder. Tapping a mode chip goes back.
    @State private var spotActive = false
    @State private var spot = CGPoint(x: 0.5, y: 0.5)      // spot meter point (press and hold), viewfinder coordinates
    @State private var spotBuf = CGPoint(x: 0.5, y: 0.5)   // the same point in camera-frame coordinates
    @State private var focus = CGPoint(x: 0.5, y: 0.5)     // LiDAR distance point (tap), viewfinder coordinates
    @State private var focusBuf = CGPoint(x: 0.5, y: 0.5)  // the same point in camera-frame coordinates
    @State private var focusExpanded = false
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
    private var safeSelected: Int { min(max(selected, 0), DepthOfField.apertures.count - 1) }

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

    private var dof: (near: Double, far: Double)? {
        guard let d = shownDistance, d >= Focus.nearest else { return nil }
        return DepthOfField.range(subject: d, n: DepthOfField.apertures[safeSelected])
    }

    private var advice: FocusAdvice? {
        guard let d = shownDistance, d >= Focus.nearest else { return nil }
        return Focus.advice(subject: d, aperture: DepthOfField.apertures[safeSelected], feet: useFeet)
    }

    var body: some View {
        VStack(spacing: 10) {
            topBar
            preview

            if simpleMode {
                SimpleExposurePair(
                    damp: evDamp, iso: iso, comp: comp,
                    apertureIndex: simpleAperture == 3 ? 3 : 0,
                    distance: shownDistance, tooClose: tooClose, feet: useFeet,
                    onToggleAperture: toggleSimpleAperture
                )
            } else {
                RulerView(
                    damp: evDamp,
                    iso: iso,
                    comp: comp,
                    golden: golden,
                    selected: safeSelected,
                    onSelect: { i in
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selected = i }
                        resetFocusToCenter()
                    },
                    onToggleGolden: { i in
                        golden = (golden == i) ? -1 : i
                    }
                )
            }

            if meter.hasLiDAR && !simpleMode {
                focusPanel(card: false)
            }

            controls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if trayOpen {
                ControlTray(
                    evIndex: $evIndex,
                    isoIndex: $isoIndex,
                    useDIN: $useDIN,
                    useFeet: $useFeet,
                    simpleMode: $simpleMode,
                    calibration: $calibration,
                    armOffset: $armOffset,
                    rawDistance: { meter.distance }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 102)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.88), value: trayOpen)
        .background(PaperBackground().ignoresSafeArea())
        .preferredColorScheme(night ? .dark : .light)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if mode == .spot { mode = .matrix }   // older versions could save spot as the mode
            pushConfig()
            evDamp.set([ev])
            syncDistance()
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
        .onChange(of: shownDistance) { syncDistance() }
        .onChange(of: selected) { syncDistance() }
        .onChange(of: focusExpanded) {
            if focusExpanded && trayOpen { withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { trayOpen = false } }
        }
        .onChange(of: simpleMode) { focusExpanded = false }
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

    private func syncDistance() {
        guard let d = shownDistance else {
            distPrimed = false
            return
        }
        let r = dof ?? (near: d, far: d)
        let target = [Focus.position(d), Focus.position(r.near), Focus.position(r.far)]
        // First reading after nothing: jump there instead of sweeping in from the left.
        distDamp.set(target, snap: !distPrimed)
        distPrimed = true
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

    private func resetFocusToCenter() {
        focusBuf = CGPoint(x: 0.5, y: 0.5)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
            focus = CGPoint(x: 0.5, y: 0.5)
        }
    }

    private func toggleSimpleAperture() {
        simpleAperture = simpleAperture == 0 ? 3 : 0
        selected = simpleAperture
        UISelectionFeedbackGenerator().selectionChanged()
        resetFocusToCenter()
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
                    FocusMarker(tooClose: tooClose)
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

                // Tray and focus scale float over the bottom of the viewfinder. Nothing in the layout moves,
                // so the live camera layer never resizes while they open and close.
                VStack {
                    Spacer()
                    if focusExpanded && meter.hasLiDAR && !simpleMode && !trayOpen {
                        focusPanel(card: true)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(10)

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
        HStack {
            EVBadge(damp: evDamp, frozen: frozenEV != nil, spot: spotActive)
            Spacer(minLength: 12)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private func focusPanel(card: Bool) -> some View {
        FocusPanel(
            damp: distDamp,
            distance: shownDistance,
            near: dof?.near,
            far: dof?.far,
            advice: advice,
            tooClose: tooClose,
            feet: useFeet,
            aperture: Rollei.stops[safeSelected].label,
            showsAperturePicker: false,
            expanded: $focusExpanded,
            onToggleUnits: { useFeet.toggle() },
            onSelectAperture: { index in
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selected = index }
            },
            card: card
        )
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
                Button {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        trayOpen.toggle()
                        if trayOpen { focusExpanded = false }
                    }
                } label: {
                    Image(systemName: trayOpen ? "chevron.down" : "slider.horizontal.3")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Palette.ink.opacity(0.78))
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
                .buttonStyle(PaperKeyStyle())
                .accessibilityLabel(trayOpen ? "Hide controls" : "Show controls")
                .accessibilityValue(safeEVIndex != EVComp.zeroIndex ? "Exposure compensation on" : "")

                Spacer(minLength: 0)

                if let modeCaption {
                    Text(modeCaption)
                        .font(AppTypography.next(size: 11, weight: .medium))
                        .tracking(1)
                        .foregroundStyle(Palette.mutedInk)
                        .padding(.trailing, 10)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }

                Button {
                    cycleMeterMode()
                } label: {
                    ZStack {
                        ModeGlyph(mode: meterChoice)
                            .id(meterChoice)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                    .frame(width: 46, height: 46)
                }
                .buttonStyle(PaperKeyStyle())
                .accessibilityLabel("Metering mode, \(meterChoice.title)")
                .accessibilityHint("Tap to change between matrix, highlight and spot")
            }
        }
    }
}
