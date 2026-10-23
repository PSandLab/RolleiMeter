import SwiftUI
import UIKit
import AudioToolbox

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

    @State private var evDamp = Damper(count: 1, initial: 2, stiffness: 70, damping: 12)

    @AppStorage("mode") private var mode: MeterMode = .matrix
    @AppStorage("isoIndex") private var isoIndex = 6
    @AppStorage("evIndex") private var evIndex = 6
    @AppStorage("useDIN") private var useDIN = false
    @AppStorage("useFeet") private var useFeet = false
    @AppStorage("simpleAperture") private var apertureStop = 0
    @AppStorage("autoAperture") private var autoAperture = false
    @AppStorage("calibration") private var calibration = 0.0
    @AppStorage("armOffset") private var armOffset = 0.0

    @State private var frozenEV: Double?
    @State private var frozenDist: Double?
    @State private var frozenPreviewImage: UIImage?
    @State private var trayOpen = false
    @State private var spotActive = false
    /// Where the spot and the distance point sit on screen, 0...1 across the viewfinder.
    @State private var spot = CGPoint(x: 0.5, y: 0.5)
    @State private var focus = CGPoint(x: 0.5, y: 0.5)
    @State private var focusPulse = 0
    @State private var spotGestureLive = false
    @State private var suppressTap = false
    @State private var showHint = false
    @AppStorage("hintCount") private var hintCount = 0
    @State private var spotRadius: CGFloat = 0.05
    @State private var pinchBase: CGFloat = 0.05
    @State private var blink = false
    @State private var previewSize = CGSize(width: 4, height: 3)
    /// True when the interface is landscape-left, so the sensor buffer is upside down on screen.
    @State private var flipped = false
    /// Manual focus. `focusPos` is where the slider sits on the Rollei scale (0 = 0.9 m, 1 = infinity).
    /// Peaking shows while a finger is on the slider and for a moment after.
    @State private var manualFocus = false
    @State private var focusPos: Double = 1
    @State private var focusTouching = false
    @State private var peakingVisible = false
    @State private var peakingTask: Task<Void, Never>?

    private var safeISOIndex: Int { min(max(isoIndex, 0), ISOScale.values.count - 1) }
    private var safeEVIndex: Int { min(max(evIndex, 0), EVComp.values.count - 1) }
    private var apertureIndex: Int { min(max(apertureStop, 0), Rollei.stops.count - 1) }

    private var autoApertureIndex: Int {
        let reading = ev
        for i in Rollei.stops.indices {
            let t = Exposure.idealShutter(ev100: reading, iso: iso, comp: comp, n: Rollei.stops[i].n)
            if t >= Rollei.fastest { return i }
        }
        return Rollei.stops.count - 1
    }

    private var resolvedApertureIndex: Int { autoAperture ? autoApertureIndex : apertureIndex }
    private var resolvedAperture: (label: String, n: Double) { Rollei.stops[resolvedApertureIndex] }

    private var iso: Double { Double(ISOScale.values[safeISOIndex]) }
    private var comp: Double { EVComp.values[safeEVIndex] }
    private var liveEV: Double { meter.sceneEV + calibration }
    private var ev: Double { frozenEV ?? liveEV }

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
        GeometryReader { screen in
            let grid = LiquidGrid(screen: screen.size, insets: screen.safeAreaInsets)
            let k = grid.k

            ZStack {
                Palette.background

                ZStack(alignment: .topLeading) {
                    // Left column
                    ShutterPanel(damp: evDamp, iso: iso, comp: comp, aperture: resolvedAperture, k: k)
                        .cell(grid, col: 0, row: 0, cols: 3, rows: 2)

                    MeterPanel(modes: meterModes, index: meterIndex, k: k, onPick: pickMeterMode)
                        .cell(grid, col: 0, row: 2, cols: 3, rows: 2)

                    FilmPanel(isoIndex: $isoIndex, useDIN: $useDIN, k: k)
                        .cell(grid, col: 0, row: 4, cols: 3, rows: 2)

                    // Centre: exposure compensation over the viewfinder
                    EVScaleBar(index: $evIndex, k: k)
                        .cell(grid, col: 3, row: 0, cols: 6, rows: 1)

                    preview(k: k)
                        .cell(grid, col: 3, row: 1, cols: 6, rows: 5)

                    // Right column
                    AperturePanel(
                        index: resolvedApertureIndex,
                        auto: autoAperture,
                        lamp: autoLampState,
                        k: k,
                        onPick: pickAperture,
                        onTap: toggleAutoAperture,
                        onHome: returnHomeAperture
                    )
                    .cell(grid, col: 9, row: 0, cols: 3, rows: 2)

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
                        k: k,
                        onBegin: beginFocusDrag,
                        onSlide: slideFocus,
                        onEnd: endFocusDrag,
                        onAuto: resumeAutoFocus,
                        onUnits: toggleUnits
                    )
                    .cell(grid, col: 9, row: 2, cols: 3, rows: 2)

                    HoldControl(frozen: frozenEV != nil, k: k, action: toggleFreeze)
                        .cell(grid, col: 9, row: 4, cols: 3, rows: 2)
                }
                .frame(width: grid.size.width, height: grid.size.height)
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
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                UIApplication.shared.isIdleTimerDisabled = true
                meter.start()
            } else {
                UIApplication.shared.isIdleTimerDisabled = false
                meter.stop()
            }
        }
                .onChange(of: apertureStop) {
            if manualFocus { updateDoFOverlay() }
        }
        .onChange(of: autoAperture) {
            if manualFocus { updateDoFOverlay() }
        }
        .onChange(of: mode) { pushConfig() }
        .onChange(of: spotActive) { pushConfig() }
        .onChange(of: spot) { pushConfig() }
        .onChange(of: focus) { pushConfig() }
        .onChange(of: spotRadius) { pushConfig() }
        .onChange(of: flipped) { pushConfig() }
        .onChange(of: previewSize) { pushConfig() }
        .onChange(of: meter.sceneEV) { evDamp.set([ev]) }
        .onChange(of: calibration) { evDamp.set([ev]) }
        .onChange(of: frozenEV) { evDamp.set([ev]) }
        .onChange(of: tooClose) {
            if tooClose { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        }
        .onChange(of: advice?.label) {
            if advice != nil { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.45) }
        }
    }

    private func pushConfig() {
        meter.setConfig(
            mode: engineMode,
            spot: bufferPoint(spot, in: previewSize),
            radius: spotRadius,
            focus: bufferPoint(focus, in: previewSize),
            flipped: flipped
        )
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

    // MARK: - Manual focus

    /// Finger down on the focus slider. Returns where the slide starts: where the lens is now.

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
        // Keep LiDAR DoF overlay active while manual focus is set
        updateDoFOverlay()
    }

    private func resumeAutoFocus() {
        manualFocus = false
        focusTouching = false
        meter.setDoFRange(near: 0, far: 0, active: false)
        withAnimation(.easeOut(duration: 0.25)) { peakingVisible = false }
    }

    private func toggleUnits() {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeInOut(duration: 0.2)) { useFeet.toggle() }
    }

    private func closeTray() {
        withAnimation(.easeInOut(duration: 0.3)) { trayOpen = false }
    }

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

    /// Screen point (0...1 across the viewfinder) to the sensor buffer (0...1). The buffer is 4:3
    /// landscape and fills the viewfinder, so the longer side is cropped. When the interface is
    /// landscape-left the buffer is upside down relative to the screen.
    private func bufferPoint(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let frame: CGFloat = 4.0 / 3.0
        let aspect = size.width / max(size.height, 1)
        var q = p
        if aspect > frame {
            q.y = 0.5 + (p.y - 0.5) * frame / aspect
        } else {
            q.x = 0.5 + (p.x - 0.5) * aspect / frame
        }
        if flipped { q = CGPoint(x: 1 - q.x, y: 1 - q.y) }
        return q
    }

    // MARK: - Viewfinder

    private func preview(k: CGFloat) -> some View {
        let radius = 22 * k
        return GeometryReader { geo in
            ZStack {
                // Anchored to the native 4:3 camera aspect so resizing never lags or flashes black.
                CameraPreview(
                    session: meter.session,
                    onVolumePress: { toggleFreeze() },
                    onFlip: { flipped = $0 }
                )
                .frame(width: max(geo.size.width, geo.size.height * (4.0 / 3.0)), height: geo.size.height)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .clipped()

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
                } else if frozenEV != nil {
                    Color.black.opacity(0.35)
                        .allowsHitTesting(false)
                }

                if peakingVisible && frozenEV == nil {
                    PeakingOverlay(feed: meter.peakingFeed)
                        .frame(width: max(geo.size.width, geo.size.height * (4.0 / 3.0)), height: geo.size.height)
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
                    let d = spotRadius * 2 * max(geo.size.width, geo.size.height * (4.0 / 3.0))
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
                    .liquidPanel(radius: 16, fill: Palette.panelRaised)
                }

                Color.black
                    .opacity(blink ? 0.9 : 0)
                    .allowsHitTesting(false)

                // Readout and settings key
                EVChip(damp: evDamp, frozen: frozenEV != nil, spot: spotActive, comp: comp)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(10)
                    .allowsHitTesting(false)

                settingsKey
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(10)

                if trayOpen {
                    Color.black.opacity(0.6)
                        .contentShape(Rectangle())
                        .onTapGesture { closeTray() }
                        .transition(.opacity)

                    ControlTray(
                        useDIN: $useDIN,
                        useFeet: $useFeet,
                        calibration: $calibration,
                        armOffset: $armOffset,
                        rawDistance: { meter.distance },
                        onClose: closeTray
                    )
                    .padding(12)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.lensDark.opacity(0.42), lineWidth: 6)
                    .blur(radius: 5)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .allowsHitTesting(false)
            }
            .onAppear { previewSize = geo.size }
            .onChange(of: geo.size) { _, newSize in previewSize = newSize }
        }
    }

    private var settingsKey: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.easeInOut(duration: 0.3)) { trayOpen.toggle() }
        } label: {
            Text(trayOpen ? "\u{2715}" : "SET")
                .font(AppTypography.next(size: 11, weight: .bold))
                .tracking(trayOpen ? 0 : 1.0)
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.55), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(trayOpen ? "Close settings" : "Open settings")
    }

    // MARK: - Metering mode

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
        let reading = Exposure.result(for: t)
        if reading.deviation != nil { return .bad }
        return reading.isSlow ? .slow : .good
    }
}
