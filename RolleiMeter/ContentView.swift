import SwiftUI
import UIKit
import AudioToolbox

private struct GlassCircle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content
                .background(Circle().fill(Palette.panel))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.09), lineWidth: 0.75))
        }
    }
}

private struct GlassCapsule: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(Capsule().fill(Palette.panel))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.09), lineWidth: 0.75))
        }
    }
}

/// Portrait only: a gentle card with a hairline edge (and optionally a rule under the title)
/// so neighbouring readouts never run into each other.
private struct SoftCard: ViewModifier {
    let k: CGFloat
    let on: Bool
    var rule: Bool = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if on {
            let shape = RoundedRectangle(cornerRadius: 22 * k, style: .continuous)
            content
                .background(shape.fill(Color.white.opacity(0.045)))
                .overlay(alignment: .top) {
                    if rule {
                        Rectangle()
                            .fill(Color.white.opacity(0.09))
                            .frame(height: 0.5)
                            .padding(.horizontal, 16 * k)
                            .padding(.top, 62 * k)
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5).allowsHitTesting(false))
        } else {
            content
        }
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
    // Wake-up cover: the held frame softens while the camera restarts, then dissolves into live.
    @State private var snapshotOpacity: Double = 1
    @State private var snapshotBlur: CGFloat = 0
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
                        .modifier(SoftCard(k: k, on: p, rule: true))
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
                    .modifier(SoftCard(k: k, on: p, rule: true))
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
                    .modifier(SoftCard(k: k, on: p, rule: true))
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
                    .modifier(SoftCard(k: k, on: p))
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
                    .modifier(SoftCard(k: k, on: p))
                    .cell(grid, col: p ? 3 : 9, row: p ? 11 : 4, cols: 3, rows: 2)

                    // Last in the stack so the camera view (which overflows its cell) can't block taps.
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
        .dynamicTypeSize(.large)
        .preferredColorScheme(.dark)
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
            wakeToken &+= 1            // cancels any pending wake-up cleanup
            snapshotOpacity = 1
            snapshotBlur = 0
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

            // Fade the held frame in over the live image instead of swapping it in one frame.
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
        // A soft, quick dip like a shutter closing, then a slow release; not a hard flash.
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

        // Immediate feedback: the held frame starts to soften while the camera wakes up.
        withAnimation(.easeInOut(duration: 0.7)) { snapshotBlur = 7 }

        meter.resume {
            // Give auto-exposure a moment to settle before revealing the live image.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard token == self.wakeToken else { return }
                withAnimation(.easeInOut(duration: 0.95)) {
                    self.snapshotOpacity = 0
                    self.snapshotBlur = 18
                    self.frozenEV = nil
                    self.frozenDist = nil
                    self.isResuming = false
                    if self.manualFocus {
                        self.updateDoFOverlay()
                    }
                }
                // Remove the (now invisible) snapshot once the dissolve has finished.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard token == self.wakeToken else { return }
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) {
                        self.frozenPreviewImage = nil
                        self.snapshotOpacity = 1
                        self.snapshotBlur = 0
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

    /// Size of the full camera frame when aspect-filled into `size`.
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
                        .blur(radius: snapshotBlur, opaque: true)
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

                // Preserved in HOLD: Renders on top of the frozen snapshot
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
                        Circle().fill(Palette.lensLight.opacity(0.05))
                        SpotReticle()
                            .stroke(Palette.lensLight.opacity(0.95),
                                    style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
                        Circle().fill(Palette.lensLight).frame(width: 2.5, height: 2.5)
                    }
                    .shadow(color: Palette.lensDark.opacity(0.40), radius: 1.5)
                    .frame(width: d, height: d)
                    .position(x: spot.x * geo.size.width, y: spot.y * geo.size.height)
                    .animation(.spring(response: 0.4, dampingFraction: 0.72), value: spot)
                    .animation(.interactiveSpring, value: spotRadius)
                    .transition(.scale(scale: 1.6).combined(with: .opacity))
                    .allowsHitTesting(false)

                    if let delta = meter.spotDelta {
                        Text(Fmt.stops(delta))
                            .font(AppTypography.font(size: 13, weight: .medium))
                            .foregroundStyle(Palette.lensLight)
                            .shadow(color: Palette.lensDark.opacity(0.8), radius: 2)
                            .contentTransition(.numericText())
                            .position(x: spot.x * geo.size.width,
                                      y: max(14, spot.y * geo.size.height - d / 2 - 14))
                            .animation(.spring(response: 0.4, dampingFraction: 0.72), value: spot)
                            .animation(.smooth(duration: 0.15), value: Fmt.stops(delta))
                            .allowsHitTesting(false)
                    }
                }

                // Hide live LiDAR bracket during HOLD
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
                    .background(Palette.lensDark.opacity(0.88), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    .padding(10)
                    .allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(held ? Palette.accent.opacity(0.75) : Color.white.opacity(0.12),
                                  lineWidth: held ? 1.5 : 1)
                    .animation(.easeInOut(duration: 0.35), value: held)
                    .allowsHitTesting(false)
            }
            .onAppear { previewSize = geo.size }
            .onChange(of: geo.size) { _, newSize in previewSize = newSize }
        }
    }

    /// Slim bar above the viewfinder: app name on the left, ±EV & Scans/Gear & Settings on the right.
    private func topBar(k: CGFloat) -> some View {
        HStack(spacing: 8 * k) {
            Text("ROLLEIMETER")
                .font(AppTypography.next(size: 22 * k, weight: .medium))
                .tracking(2.6 * k)
                .foregroundStyle(Palette.dim)
                .padding(.leading, 17 * k)
                .lineLimit(1)

            Spacer()

            // ±EV Compensation Pill
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showEvPopover.toggle()
            } label: {
                Text(abs(logStore.totalEvComp) >= 0.05 ? formatEvComp(logStore.totalEvComp) : "±EV")
                    .font(AppTypography.mono(size: 19 * k, weight: .bold))
                    .foregroundStyle(abs(logStore.totalEvComp) >= 0.05 ? Palette.accent : Palette.text)
                    .padding(.horizontal, 14 * k)
                    .frame(height: 62 * k)
                    .modifier(GlassCapsule())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showEvPopover) {
                ExposureCompDialPopover(store: logStore)
                    .presentationCompactAdaptation(.popover)
            }

            // Lab Scan Matcher & Gear Quick Button
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                logbookInitialTab = 2
                showFilmLogbook = true
            } label: {
                Image(systemName: "photo.stack")
                    .font(.system(size: 24 * k, weight: .medium))
                    .foregroundStyle(Palette.text)
                    .frame(width: 66 * k, height: 66 * k)
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
                    .font(.system(size: 28 * k, weight: .medium))
                    .foregroundStyle(Palette.text)
                    .frame(width: 70 * k, height: 70 * k)
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

// MARK: - Native iOS Exposure Compensation Dial & Stepper Popover

private struct ExposureCompDialPopover: View {
    @ObservedObject var store: FilmLogStore

    private let zeroIdx = EV_COMP_STOPS.firstIndex(of: 0.0) ?? 9

    var body: some View {
        let idx = store.manualEvCompIndex.clamped(to: 0...(EV_COMP_STOPS.count - 1))
        let manualEv = EV_COMP_STOPS[idx]
        let totalEv = store.totalEvComp
        let isNonZero = idx != zeroIdx

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("EXPOSURE BIAS")
                    .font(AppTypography.next(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Palette.dim)

                Spacer()

                if isNonZero {
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.snappy(duration: 0.22)) {
                            store.manualEvCompIndex = zeroIdx
                        }
                    } label: {
                        Text("Reset")
                            .font(AppTypography.next(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if store.rollState.isSlideFilm {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                    Text("Slide film locks exposure bias to 0.0 EV to protect highlights.")
                        .font(AppTypography.next(size: 13, weight: .medium))
                        .foregroundStyle(Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            } else {
                // Tactile Stepper Row (-1/3 / Readout / +1/3)
                HStack(spacing: 16) {
                    Button {
                        guard idx > 0 else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.snappy(duration: 0.18)) {
                            store.manualEvCompIndex = idx - 1
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(idx > 0 ? Palette.text : Palette.faint)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(idx <= 0)

                    VStack(spacing: 2) {
                        Text(formatEvComp(totalEv))
                            .font(AppTypography.next(size: 28, weight: .bold).monospacedDigit())
                            .foregroundStyle(abs(totalEv) >= 0.05 ? Palette.accent : Palette.text)
                            .contentTransition(.numericText())

                        if store.rollState.activeExpiredCompEv > 0.05 {
                            Text("Includes +\(String(format: "%.1f", store.rollState.activeExpiredCompEv)) EV expired film comp")
                                .font(AppTypography.next(size: 10, weight: .medium))
                                .foregroundStyle(Palette.dim)
                        } else {
                            Text("1/3-stop steps")
                                .font(AppTypography.next(size: 11, weight: .medium))
                                .foregroundStyle(Palette.dim)
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
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(idx < EV_COMP_STOPS.count - 1 ? Palette.text : Palette.faint)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(idx >= EV_COMP_STOPS.count - 1)
                }

                // Interactive Machined Exposure Scale (-3 .. 0 .. +3)
                GeometryReader { geo in
                    let w = geo.size.width
                    let count = EV_COMP_STOPS.count
                    let stepW = w / CGFloat(max(count - 1, 1))

                    ZStack(alignment: .topLeading) {
                        // Tick marks
                        HStack(spacing: 0) {
                            ForEach(0..<count, id: \.self) { i in
                                let isWhole = i % 3 == 0
                                let isSelected = i == idx
                                let isZero = i == zeroIdx
                                VStack(spacing: 5) {
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(isSelected ? Palette.accent : (isZero ? Palette.text : (isWhole ? Color.white.opacity(0.55) : Color.white.opacity(0.22))))
                                        .frame(width: isSelected ? 2.5 : (isWhole ? 1.5 : 1.0),
                                               height: isSelected ? 18 : (isWhole ? 13 : 8))
                                        .frame(height: 18, alignment: .bottom)

                                    if isWhole {
                                        let wholeVal = Int(EV_COMP_STOPS[i].rounded())
                                        Text(wholeVal > 0 ? "+\(wholeVal)" : "\(wholeVal)")
                                            .font(AppTypography.mono(size: 10, weight: isSelected ? .bold : .medium))
                                            .foregroundStyle(isSelected ? Palette.accent : Palette.dim)
                                    } else {
                                        Text(" ")
                                            .font(AppTypography.mono(size: 10, weight: .medium))
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
        .background(Palette.panel)
    }
}
