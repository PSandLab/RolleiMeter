import SwiftUI
import UIKit
import AudioToolbox

private struct GlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Palette.panel, in: Circle())
    }
}

private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Palette.panel, in: Capsule())
    }
}

private struct SpotReticle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2 - 0.5
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                   width: radius * 2, height: radius * 2))
        return path
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var meter = CameraMeter()
    @StateObject private var logStore = FilmLogStore()

    @State private var evDamp = Damper(count: 1, initial: 2, stiffness: 70, damping: 12)

    @AppStorage("mode") private var mode: MeterMode = .matrix
    @AppStorage("isoIndex") private var isoIndex = 6
    @AppStorage("useDIN") private var useDIN = false
    @AppStorage("useFeet") private var useFeet = false
    @AppStorage("simpleAperture") private var apertureStop = 0
    @AppStorage("autoAperture") private var autoAperture = false
    @AppStorage("calibration") private var calibration = 0.0
    @AppStorage("armOffset") private var armOffset = 0.0

    @State private var frozenEV: Double?
    @State private var frozenDist: Double?
    @State private var frozenPreviewImage: UIImage?
    @State private var isResuming = false
    @State private var showFilmLogbook = false
    @State private var logbookInitialTab = 0
    @State private var capturedMoment: CapturedMoment? = nil
    @State private var momentSaved: Bool = false
    @State private var showEvPopover: Bool = false
    @State private var snapshotOpacity: Double = 1
    @State private var wakeToken = 0
    @State private var showSettings = false
    @State private var spotActive = false
    @State private var spot = CGPoint(x: 0.5, y: 0.5)
    @State private var focus = CGPoint(x: 0.5, y: 0.5)
    @State private var focusPulse = 0
    @State private var spotGestureLive = false
    @State private var suppressTap = false
    @State private var showHint = false
    @AppStorage("hintCount") private var hintCount = 0
    @State private var spotRadius: CGFloat = 0.05
    @State private var pinchBase: CGFloat = 0.05
    @State private var flash: Double = 0
    @State private var previewSize = CGSize(width: 4, height: 3)
    @State private var rotation: ViewRotation = .landscapeRight

    // Manual focus & LiDAR DoF
    @State private var manualFocus = false
    @State private var focusPos: Double = 0.5
    @State private var focusTouching = false
    @State private var peakingVisible = false
    @State private var peakingTask: Task<Void, Never>?

    private var activeShutterSpeeds: [(label: String, t: Double)] {
        clampShutterStopsForGear(logStore.activeGear)
    }

    private var activeApertureStops: [(label: String, n: Double)] {
        clampApertureStopsForGear(logStore.activeGear)
    }

    private var safeISOIndex: Int { min(max(isoIndex, 0), ISOScale.values.count - 1) }
    private var apertureIndex: Int { min(max(apertureStop, 0), max(0, activeApertureStops.count - 1)) }

    private var autoApertureIndex: Int {
        let reading = ev
        let stops = activeApertureStops
        let fastest = activeShutterSpeeds.first?.t ?? Rollei.fastest
        for i in stops.indices {
            let t = Exposure.idealShutter(ev100: reading, iso: iso, comp: comp, n: stops[i].n)
            if t >= fastest { return i }
        }
        return max(0, stops.count - 1)
    }

    private var resolvedApertureIndex: Int { autoAperture ? autoApertureIndex : apertureIndex }
    private var resolvedAperture: (label: String, n: Double) {
        let stops = activeApertureStops
        return stops[min(max(resolvedApertureIndex, 0), max(0, stops.count - 1))]
    }

    private var iso: Double { Double(ISOScale.values[safeISOIndex]) }
    private var comp: Double { logStore.totalEvComp }
    private var liveEV: Double { meter.sceneEV + calibration }
    private var ev: Double { frozenEV ?? liveEV }

    private var shownDistance: Double? {
        guard let raw = frozenEV != nil ? frozenDist : meter.distance else { return nil }
        return raw + armOffset
    }

    private var baseMode: MeterMode { mode == .spot ? .matrix : mode }
    private var engineMode: MeterMode { spotActive ? .spot : baseMode }
    private var isModalOpen: Bool { showSettings || showFilmLogbook }

    private var tooClose: Bool {
        guard let d = shownDistance else { return false }
        return d < Focus.nearest
    }

    private var advice: FocusAdvice? {
        guard let d = shownDistance, d >= Focus.nearest else { return nil }
        return Focus.advice(subject: d, aperture: resolvedAperture.n, feet: useFeet)
    }

    var body: some View {
        GeometryReader { screen in
            let grid = LiquidGrid(screen: screen.size, insets: screen.safeAreaInsets)
            let k = grid.k
            let p = grid.portrait
            let roll = logStore.rollState
            let gear = logStore.activeGear

            ZStack {
                Palette.background

                ZStack(alignment: .topLeading) {
                    ShutterPanel(damp: evDamp, iso: iso, comp: comp, aperture: resolvedAperture, speeds: activeShutterSpeeds, k: k)
                        .cell(grid, col: 0, row: p ? 7 : 0, cols: 3, rows: 2)

                    FilmPanel(
                        isoIndex: $isoIndex,
                        useDIN: useDIN,
                        filmName: shortFilmBadge(name: roll.filmName, iso: roll.boxIso),
                        boxISO: roll.boxIso,
                        isUnloaded: roll.isUnloaded,
                        cameraBadge: gear.cameraName,
                        k: k,
                        onTap: {
                            logbookInitialTab = 0
                            showFilmLogbook = true
                        }
                    )
                    .cell(grid, col: 0, row: p ? 11 : 4, cols: 3, rows: 2)

                    FramePanel(
                        frame: roll.currentFrame,
                        rollLength: roll.maxFrames,
                        isUnloaded: roll.isUnloaded,
                        loggedCount: logStore.loggedFrames.count,
                        k: k,
                        onTap: {
                            logbookInitialTab = 1
                            showFilmLogbook = true
                        }
                    )
                    .cell(grid, col: 0, row: p ? 9 : 2, cols: 3, rows: 2)

                    preview(k: k)
                        .cell(grid, col: p ? 0 : 3, row: 1, cols: 6, rows: p ? 6 : 5)

                    AperturePanel(
                        index: resolvedApertureIndex,
                        stops: activeApertureStops,
                        auto: autoAperture,
                        lamp: autoLampState,
                        k: k,
                        onPick: pickAperture,
                        onTap: toggleAutoAperture,
                        onHome: returnHomeAperture
                    )
                    .cell(grid, col: p ? 3 : 9, row: p ? 7 : 0, cols: 3, rows: 2)

                    FocusPanel(
                        position: focusPos,
                        manual: manualFocus,
                        touching: focusTouching,
                        available: meter.canFocusManually,
                        lidarDistance: shownDistance,
                        hasLiDAR: meter.hasLiDAR,
                        tooClose: tooClose,
                        aperture: resolvedAperture,
                        feet: useFeet,
                        isHeld: (frozenEV != nil && !isResuming),
                        k: k,
                        onBegin: beginFocusDrag,
                        onSlide: slideFocus,
                        onEnd: endFocusDrag,
                        onAuto: resumeAutoFocus,
                        onUnits: toggleUnits
                    )
                    .cell(grid, col: p ? 3 : 9, row: p ? 9 : 2, cols: 3, rows: 2)

                    HoldControl(
                        frozen: (frozenEV != nil && !isResuming),
                        frameNumber: capturedMoment?.frameNumber ?? roll.currentFrame,
                        isSaved: momentSaved,
                        k: k,
                        modes: meterModes,
                        meterIndex: meterIndex,
                        onPickMeter: pickMeterMode,
                        onHold: toggleFreeze,
                        onConfirmLog: confirmAndLogHeldFrame,
                        onDiscardHold: unfreeze
                    )
                    .cell(grid, col: p ? 3 : 9, row: p ? 11 : 4, cols: 3, rows: 2)

                    topBar(k: k)
                        .cell(grid, col: p ? 0 : 3, row: 0, cols: 6, rows: 1)
                }
                .frame(width: grid.size.width, height: grid.size.height)
                .offset(y: grid.yShift)
            }
            .frame(width: screen.size.width, height: screen.size.height)
        }
        .ignoresSafeArea()
        .background(Palette.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.large)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if mode == .spot { mode = .matrix }
            if !logStore.rollState.isUnloaded,
               let boxIdx = ISOScale.values.firstIndex(of: logStore.rollState.boxIso) {
                isoIndex = boxIdx
            }
            pushConfig()
            evDamp.set([ev])
            meter.start()
            LocationCache.shared.refreshIfAuthorized()
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
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                UIApplication.shared.isIdleTimerDisabled = true
                if frozenEV == nil && !isModalOpen {
                    meter.start()
                }
            } else {
                UIApplication.shared.isIdleTimerDisabled = false
                meter.stop()
            }
        }
        .onChange(of: isModalOpen) { _, open in
            if open {
                meter.pause()
            } else if frozenEV == nil && scenePhase == .active {
                meter.resume()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                useDIN: $useDIN,
                useFeet: $useFeet,
                calibration: $calibration,
                armOffset: $armOffset,
                rawDistance: { meter.distance },
                onNeedSensor: { needed in
                    if needed {
                        meter.resume()
                    } else if isModalOpen || frozenEV != nil {
                        meter.pause()
                    }
                }
            )
        }
        .sheet(isPresented: $showFilmLogbook) {
            FilmLogbookSheet(store: logStore, initialTab: logbookInitialTab)
        }
        .onChange(of: logStore.rollState.boxIso) { _, newBoxIso in
            if let idx = ISOScale.values.firstIndex(of: newBoxIso) {
                isoIndex = idx
            }
        }
        .onChange(of: mode) { pushConfig() }
        .onChange(of: spotActive) { pushConfig() }
        .onChange(of: spot) { pushConfig() }
        .onChange(of: focus) { pushConfig() }
        .onChange(of: spotRadius) { pushConfig() }
        .onChange(of: rotation) { pushConfig() }
        .onChange(of: previewSize) { pushConfig() }
        .onChange(of: meter.sceneEV) { evDamp.set([ev]) }
        .onChange(of: calibration) { evDamp.set([ev]) }
        .onChange(of: frozenEV) { evDamp.set([ev]) }
        .onChange(of: apertureStop) { _ in
            if manualFocus { updateDoFOverlay() }
        }
        .onChange(of: autoAperture) { _ in
            if manualFocus { updateDoFOverlay() }
        }
        .onChange(of: tooClose) {
            guard !isModalOpen, frozenEV == nil else { return }
            if tooClose { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        }
        .onChange(of: advice?.label) {
            guard !isModalOpen, frozenEV == nil else { return }
            if advice != nil { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.45) }
        }
    }

    private func pushConfig() {
        meter.setConfig(
            mode: engineMode,
            spot: bufferPoint(spot, in: previewSize),
            radius: spotRadius,
            focus: bufferPoint(focus, in: previewSize),
            rotation: rotation
        )
    }

    private func toggleFreeze() {
        guard !isResuming, !isModalOpen else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        if frozenEV == nil {
            shutterBlink()
            let snapshot = meter.previewSnapshot()
            wakeToken &+= 1
            snapshotOpacity = 1
            momentSaved = false

            let heldEV = liveEV
            let idealT = Exposure.idealShutter(ev100: heldEV, iso: iso, comp: comp, n: resolvedAperture.n)
            let shutterRes = Exposure.result(for: idealT, speeds: activeShutterSpeeds)
            let formattedShutter = shutterRes.label.hasSuffix("\"") ? shutterRes.label.replacingOccurrences(of: "\"", with: "s") : "1/\(shutterRes.label)"
            let formattedAperture = "f/\(resolvedAperture.label)"
            let computedZone = Int((5.0 + (meter.spotDelta ?? 0.0)).rounded()).clamped(to: 0...10)

            let moment = logStore.captureMoment(
                shutterSpeed: formattedShutter,
                aperture: formattedAperture,
                iso: Int(iso.rounded()),
                sceneEv: heldEV,
                compensatedEv: heldEV - comp,
                zone: computedZone,
                meterMode: engineMode.rawValue.uppercased(),
                isAutoExposure: autoAperture,
                previewImage: snapshot
            )

            withAnimation(.easeOut(duration: 0.28)) {
                frozenPreviewImage = snapshot
                frozenEV = heldEV
                frozenDist = meter.distance
                capturedMoment = moment
            }
            meter.freezeDepth()
            meter.pause()
            if manualFocus {
                updateDoFOverlay()
            }
        } else {
            unfreeze()
        }
    }

    private func confirmAndLogHeldFrame() {
        guard !momentSaved else { return }
        if let moment = capturedMoment {
            _ = logStore.recordMoment(moment)
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            momentSaved = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            if self.frozenEV != nil && !self.isResuming {
                self.unfreeze()
            }
        }
    }

    private func shutterBlink() {
        AudioServicesPlaySystemSound(1108)
        withAnimation(.easeOut(duration: 0.07)) { flash = 0.3 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
            withAnimation(.easeInOut(duration: 0.5)) { flash = 0 }
        }
    }

    private func normalized(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: min(max(p.x / max(size.width, 1), 0), 1), y: min(max(p.y / max(size.height, 1), 0), 1))
    }

    private func unfreeze() {
        guard frozenEV != nil || isResuming else { return }
        isResuming = true
        wakeToken &+= 1
        let token = wakeToken
        capturedMoment = nil
        momentSaved = false
        meter.unfreezeDepth()

        meter.resume {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard token == self.wakeToken else { return }
                withAnimation(.easeInOut(duration: 0.95)) {
                    self.snapshotOpacity = 0
                    self.frozenEV = nil
                    self.frozenDist = nil
                    self.isResuming = false
                    if self.manualFocus {
                        self.updateDoFOverlay()
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard token == self.wakeToken else { return }
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) {
                        self.frozenPreviewImage = nil
                        self.snapshotOpacity = 1
                    }
                }
            }
        }
    }

    // MARK: - Manual Focus & LiDAR DoF

    private func updateDoFOverlay() {
        let subject = Focus.distance(at: focusPos)
        let dof = DepthOfField.range(subject: subject, n: resolvedAperture.n)
        meter.setDoFRange(near: dof.near, far: dof.far, active: true)
    }

    private func beginFocusDrag() -> Double {
        peakingTask?.cancel()
        if !manualFocus { manualFocus = true }
        focusTouching = true
        updateDoFOverlay()
        withAnimation(.easeOut(duration: 0.15)) { peakingVisible = true }
        return focusPos
    }

    private func slideFocus(_ position: Double) {
        if !manualFocus { manualFocus = true }
        focusPos = position
        updateDoFOverlay()
    }

    private func endFocusDrag() {
        focusTouching = false
        updateDoFOverlay()
    }

    private func resumeAutoFocus() {
        meter.resumeAutoFocus()
        manualFocus = false
        focusTouching = false
        meter.setDoFRange(near: 0, far: 0, active: false)
        withAnimation(.easeOut(duration: 0.25)) { peakingVisible = false }
    }

    private func toggleUnits() {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeInOut(duration: 0.2)) { useFeet.toggle() }
    }

    private func pickAperture(_ index: Int) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            autoAperture = false
            apertureStop = min(max(index, 0), max(0, activeApertureStops.count - 1))
        }
        if manualFocus {
            updateDoFOverlay()
        }
    }

    private func toggleAutoAperture() {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            autoAperture.toggle()
        }
        if manualFocus {
            updateDoFOverlay()
        }
    }

    private func returnHomeAperture() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            autoAperture = false
            apertureStop = min(3, max(0, activeApertureStops.count - 1))
        }
        if manualFocus {
            updateDoFOverlay()
        }
    }

    private func bufferPoint(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let frame = rotation.frameAspect
        let aspect = size.width / max(size.height, 1)
        var q = p
        if aspect > frame {
            q.y = 0.5 + (p.y - 0.5) * frame / aspect
        } else {
            q.x = 0.5 + (p.x - 0.5) * aspect / frame
        }
        return rotation.toBuffer(q)
    }

    private func fullFrame(_ size: CGSize) -> CGSize {
        let a = rotation.frameAspect
        return CGSize(width: max(size.width, size.height * a), height: max(size.height, size.width / a))
    }

    // MARK: - Viewfinder

    private func preview(k: CGFloat) -> some View {
        let radius = 22 * k
        let held = frozenEV != nil && !isResuming
        return GeometryReader { geo in
            ZStack {
                CameraPreview(
                    session: meter.session,
                    onVolumePress: { toggleFreeze() },
                    onRotate: { rotation = $0 }
                )
                .frame(width: fullFrame(geo.size).width, height: fullFrame(geo.size).height)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .clipped()

                if let frozenPreviewImage {
                    Image(uiImage: frozenPreviewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .opacity(snapshotOpacity)
                        .overlay(Palette.lensLight.opacity(0.04))
                        .transition(.opacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                } else if frozenEV != nil {
                    Color.black.opacity(0.35)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }

                if peakingVisible || manualFocus {
                    PeakingOverlay(feed: meter.peakingFeed)
                        .frame(width: fullFrame(geo.size).width, height: fullFrame(geo.size).height)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .transition(.opacity)
                }

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture().onEnded { value in
                            if suppressTap { return }
                            let p = normalized(value.location, geo.size)
                            focusPulse &+= 1
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) { focus = p }
                            if frozenEV != nil {
                                if let dist = meter.sampleFrozenDepth(at: bufferPoint(p, in: previewSize)) {
                                    frozenDist = dist
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                } else {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            } else {
                                unfreeze()
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
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
                    let full = fullFrame(geo.size)
                    let d = spotRadius * 2 * max(full.width, full.height)
                    ZStack {
                        Circle().fill(Palette.lensLight.opacity(0.06))
                        SpotReticle()
                            .stroke(Palette.lensLight.opacity(0.95),
                                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        Circle().fill(Palette.lensLight).frame(width: 3, height: 3)
                    }
                    .frame(width: d, height: d)
                    .shadow(color: Color.black.opacity(0.75), radius: 2, x: 0, y: 1)
                    .position(x: spot.x * geo.size.width, y: spot.y * geo.size.height)
                    .animation(.spring(response: 0.4, dampingFraction: 0.72), value: spot)
                    .animation(.interactiveSpring, value: spotRadius)
                    .transition(.scale(scale: 1.6).combined(with: .opacity))
                    .allowsHitTesting(false)

                    if let delta = meter.spotDelta {
                        Text(Fmt.stops(delta))
                            .font(AppTypography.numeral(size: 13, weight: .bold))
                            .foregroundStyle(Palette.lensLight)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.68), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75))
                            .contentTransition(.numericText())
                            .position(x: spot.x * geo.size.width,
                                      y: max(18, spot.y * geo.size.height - d / 2 - 16))
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
                    VStack(spacing: 4) {
                        Text("Tap: distance   \u{00B7}   Hold: spot meter")
                        Text("Tap aperture: auto   \u{00B7}   Slide focus: manual")
                    }
                    .font(AppTypography.next(size: 11, weight: .medium))
                    .foregroundStyle(Palette.lensLight)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Palette.lensDark.opacity(0.88), in: .rect(cornerRadius: 12, style: .continuous))
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.3)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }

                if meter.denied {
                    VStack(spacing: 10) {
                        Text("Camera access is off")
                            .font(AppTypography.next(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.text)
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
                }

                Color.black
                    .opacity(flash)
                    .allowsHitTesting(false)

                EVChip(damp: evDamp, frozen: (frozenEV != nil && !isResuming), spot: spotActive)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)
                    .allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(.rect(cornerRadius: radius, style: .continuous))
            .overlay {
                if held {
                    ContainerRelativeShape()
                        .strokeBorder(Palette.accent.opacity(0.75), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
            .containerShape(.rect(cornerRadius: radius, style: .continuous))
            .onAppear { previewSize = geo.size }
            .onChange(of: geo.size) { _, newSize in previewSize = newSize }
        }
    }

    private func topBar(k: CGFloat) -> some View {
        let btnSize: CGFloat = 62 * k
        return HStack(spacing: 10 * k) {
            Text("ROLLEIMETER")
                .font(AppTypography.next(size: 21 * k, weight: .semibold))
                .tracking(3.0 * k)
                .foregroundStyle(Palette.textDim)
                .padding(.leading, 6 * k)
                .lineLimit(1)

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showEvPopover.toggle()
            } label: {
                Text(abs(logStore.totalEvComp) >= 0.05 ? formatEvComp(logStore.totalEvComp) : "±EV")
                    .font(AppTypography.numeral(size: 20 * k, weight: .bold))
                    .foregroundStyle(abs(logStore.totalEvComp) >= 0.05 ? Palette.accent : Palette.text)
                    .padding(.horizontal, 18 * k)
                    .frame(height: btnSize)
                    .modifier(GlassCapsule())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showEvPopover) {
                ExposureCompDialPopover(store: logStore)
                    .presentationCompactAdaptation(.popover)
            }

            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                logbookInitialTab = 2
                showFilmLogbook = true
            } label: {
                Image(systemName: "scanner")
                    .font(.system(size: 22 * k, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .frame(width: btnSize, height: btnSize)
                    .modifier(GlassCircle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Lab Scan Matcher and Film Logbook")

            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 22 * k, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .frame(width: btnSize, height: btnSize)
                    .modifier(GlassCircle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    private let meterModes: [MeterMode] = [.matrix, .highlight, .spot]
    private var meterChoice: MeterMode { spotActive ? .spot : baseMode }
    private var meterIndex: Int { meterModes.firstIndex(of: meterChoice) ?? 0 }

    private func pickMeterMode(_ index: Int) {
        let next = meterModes[min(max(index, 0), meterModes.count - 1)]
        guard next != meterChoice else { return }
        applyMeterMode(next)
    }

    private func applyMeterMode(_ next: MeterMode) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            if next == .spot {
                spotActive = true
            } else {
                mode = next
                spotActive = false
            }
        }
        unfreeze()
    }

    private var autoLampState: AutoLampState {
        guard autoAperture else { return .off }
        let t = Exposure.idealShutter(ev100: ev, iso: iso, comp: comp,
                                      n: resolvedAperture.n)
        let reading = Exposure.result(for: t, speeds: activeShutterSpeeds)
        if reading.deviation != nil { return .bad }
        return reading.isSlow ? .slow : .good
    }
}

// MARK: - Exposure Compensation Popover

private struct ExposureCompDialPopover: View {
    @ObservedObject var store: FilmLogStore

    private let zeroIdx = EV_COMP_STOPS.firstIndex(of: 0.0) ?? 9

    var body: some View {
        let idx = store.manualEvCompIndex.clamped(to: 0...(EV_COMP_STOPS.count - 1))
        let totalEv = store.totalEvComp
        let isNonZero = idx != zeroIdx

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("EXPOSURE BIAS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if isNonZero {
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.snappy(duration: 0.22)) {
                            store.manualEvCompIndex = zeroIdx
                        }
                    } label: {
                        Text("Reset")
                            .font(.caption.weight(.semibold))
                    }
                }
            }

            if store.rollState.isSlideFilm {
                Label("Slide film locks exposure bias to 0.0 EV.", systemImage: "lock.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                HStack(spacing: 16) {
                    Button {
                        guard idx > 0 else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.snappy(duration: 0.18)) {
                            store.manualEvCompIndex = idx - 1
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.headline.weight(.bold))
                            .frame(width: 44, height: 44)
                    }
                    .disabled(idx <= 0)

                    VStack(spacing: 2) {
                        Text(formatEvComp(totalEv))
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(abs(totalEv) >= 0.05 ? Palette.accent : Palette.text)
                            .contentTransition(.numericText())

                        if store.rollState.activeExpiredCompEv > 0.05 {
                            Text("+\(String(format: "%.1f", store.rollState.activeExpiredCompEv)) EV expired")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Button {
                        guard idx < EV_COMP_STOPS.count - 1 else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.snappy(duration: 0.18)) {
                            store.manualEvCompIndex = idx + 1
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline.weight(.bold))
                            .frame(width: 44, height: 44)
                    }
                    .disabled(idx >= EV_COMP_STOPS.count - 1)
                }

                GeometryReader { geo in
                    let w = geo.size.width
                    let count = EV_COMP_STOPS.count

                    ZStack(alignment: .topLeading) {
                        HStack(spacing: 0) {
                            ForEach(0..<count, id: \.self) { i in
                                let isWhole = i % 3 == 0
                                let isSelected = i == idx
                                let isZero = i == zeroIdx
                                VStack(spacing: 5) {
                                    Capsule()
                                        .fill(isSelected ? Palette.accent : (isZero ? Palette.text : (isWhole ? Palette.textSub : Palette.faint)))
                                        .frame(width: isSelected ? 2.5 : (isWhole ? 1.5 : 1.0),
                                               height: isSelected ? 18 : (isWhole ? 13 : 8))
                                        .frame(height: 18, alignment: .bottom)

                                    if isWhole {
                                        let wholeVal = Int(EV_COMP_STOPS[i].rounded())
                                        Text(wholeVal > 0 ? "+\(wholeVal)" : "\(wholeVal)")
                                            .font(.caption2.weight(isSelected ? .bold : .medium).monospacedDigit())
                                            .foregroundStyle(isSelected ? Palette.accent : .secondary)
                                    } else {
                                        Text(" ")
                                            .font(.caption2)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let ratio = (value.location.x / max(w, 1)).clamped(to: 0...1)
                                let target = Int((ratio * CGFloat(count - 1)).rounded()).clamped(to: 0...(count - 1))
                                if target != store.manualEvCompIndex {
                                    if target == zeroIdx || target % 3 == 0 {
                                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7)
                                    } else {
                                        UISelectionFeedbackGenerator().selectionChanged()
                                    }
                                    store.manualEvCompIndex = target
                                }
                            }
                    )
                }
                .frame(height: 38)
            }
        }
        .padding(16)
        .frame(width: 286)
    }
}
