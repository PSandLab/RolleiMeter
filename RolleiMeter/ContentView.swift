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
    @State private var spot = CGPoint(x: 0.5, y: 0.5)
    @State private var spotBuf = CGPoint(x: 0.5, y: 0.5)
    @State private var focus = CGPoint(x: 0.5, y: 0.5)
    @State private var focusPulse = 0
    @State private var focusBuf = CGPoint(x: 0.5, y: 0.5)
    @State private var spotGestureLive = false
    @State private var suppressTap = false
    @State private var showHint = false
    @AppStorage("hintCount") private var hintCount = 0
    @State private var spotRadius: CGFloat = 0.05
    @State private var pinchBase: CGFloat = 0.05
    @State private var blink = false
    @State private var night = false
    @State private var nightSince: Date?

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
        VStack(spacing: 8) {
            topBar

            if trayOpen {
                ControlTray(
                    evIndex: $evIndex,
                    isoIndex: $isoIndex,
                    useDIN: $useDIN,
                    useFeet: $useFeet,
                    calibration: $calibration,
                    armOffset: $armOffset,
                    rawDistance: { meter.distance },
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            trayOpen = false
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }

            preview

            SimpleExposurePair(
                damp: evDamp, iso: iso, comp: comp,
                apertureIndex: resolvedApertureIndex,
                distance: shownDistance,
                hasLiDAR: meter.hasLiDAR,
                tooClose: tooClose, feet: useFeet
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
        .onChange(of: advice?.label) {
            if advice != nil { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.45) }
        }
    }

    private func pushConfig() {
        meter.setConfig(mode: engineMode, spot: spotBuf, radius: spotRadius, focus: focusBuf)
    }

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

    private func bufferPoint(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let frame = 0.75
        let aspect = size.width / max(size.height, 1)
        if aspect < frame {
            return CGPoint(x: 0.5 + (p.x - 0.5) * aspect / frame, y: p.y)
        }
        return CGPoint(x: p.x, y: 0.5 + (p.y - 0.5) * frame / aspect)
    }

    // MARK: - Viewfinder (Zero-Lag Smooth Window Masking)

    private var preview: some View {
        GeometryReader { geo in
            ZStack {
                // Anchored to native 3:4 camera aspect ratio to eliminate resize lag and black flashes!
                CameraPreview(session: meter.session, onVolumePress: { toggleFreeze() })
                    .frame(width: geo.size.width, height: max(geo.size.height, geo.size.width * (4.0 / 3.0)))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

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

                Color.black
                    .opacity(blink ? 0.9 : 0)
                    .allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Palette.lensDark.opacity(0.42), lineWidth: 6)
                    .blur(radius: 5)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .allowsHitTesting(false)
            }
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

    private var trayKey: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.easeInOut(duration: 0.35)) {
                trayOpen.toggle()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(trayOpen ? Palette.ink : Palette.paper)
                    .frame(width: 38, height: 38)
                    .overlay(Circle().stroke(Palette.hairline, lineWidth: 1))
                    .shadow(color: Palette.cast, radius: 2, x: 0, y: 1)

                Text(trayOpen ? "✕" : "SET")
                    .font(AppTypography.next(size: trayOpen ? 12 : 11, weight: .bold))
                    .tracking(trayOpen ? 0 : 1.0)
                    .foregroundStyle(trayOpen ? Palette.paper : Palette.ink)
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(trayOpen ? "Close settings" : "Open settings")
    }

    private let meterModes: [MeterMode] = [.matrix, .highlight, .spot]
    private var meterChoice: MeterMode { spotActive ? .spot : baseMode }
    private var meterIndex: Int { meterModes.firstIndex(of: meterChoice) ?? 0 }

    private func pickMeterMode(_ index: Int) {
        let next = meterModes[min(max(index, 0), meterModes.count - 1)]
        guard next != meterChoice else { return }
        applyMeterMode(next)
    }

    private func cycleMeterMode() {
        UISelectionFeedbackGenerator().selectionChanged()
        applyMeterMode(meterModes[(meterIndex + 1) % meterModes.count])
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

    private var controls: some View {
        ZStack {
            FreezeButton(frozen: frozenEV != nil) {
                toggleFreeze()
            }

            HStack(spacing: 0) {
                MeterDrum(
                    modes: meterModes,
                    index: meterIndex,
                    onPick: pickMeterMode,
                    onTap: cycleMeterMode
                )

                Spacer(minLength: 0)

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

    private var autoLampState: AutoLampState {
        guard autoAperture else { return .off }
        let t = Exposure.idealShutter(ev100: ev, iso: iso, comp: comp,
                                      n: resolvedAperture.n)
        let reading = Exposure.result(for: t)
        if reading.deviation != nil { return .bad }
        return reading.isSlow ? .slow : .good
    }
}
