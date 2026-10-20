import SwiftUI
import UIKit

private let viewfinderPaper = Color(red: Double(0xF1) / 255.0, green: Double(0xEE) / 255.0, blue: Double(0xE6) / 255.0)
private let viewfinderInk = Color(red: Double(0x26) / 255.0, green: Double(0x26) / 255.0, blue: Double(0x26) / 255.0)

struct ContentView: View {
    @StateObject private var meter = CameraMeter()

    // Held in @State, not @StateObject, so 60 fps value changes only redraw the views that watch them.
    @State private var evDamp = Damper(count: 1, initial: 12, stiffness: 70, damping: 12)
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

    @State private var frozenEV: Double?
    @State private var frozenDist: Double?
    @State private var frozenPreviewImage: UIImage?
    @State private var controlsExpanded = false
    @State private var meterPrimed = false
    @State private var distPrimed = false
    /// Spot metering only happens after a tap in the viewfinder. Tapping a mode chip goes back.
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
    @State private var showSettings = false

    private var safeISOIndex: Int { min(max(isoIndex, 0), ISOScale.values.count - 1) }
    private var safeEVIndex: Int { min(max(evIndex, 0), EVComp.values.count - 1) }
    private var safeSelected: Int { min(max(selected, 0), DepthOfField.apertures.count - 1) }

    private var iso: Double { Double(ISOScale.values[safeISOIndex]) }
    private var comp: Double { EVComp.values[safeEVIndex] }
    private var liveEV: Double { meter.sceneEV + calibration }
    private var ev: Double { frozenEV ?? liveEV }
    private var shownDistance: Double? { frozenEV != nil ? frozenDist : meter.distance }

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
                    distance: shownDistance, advice: advice, tooClose: tooClose, feet: useFeet,
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
                    }
                )
            }

            controls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(viewfinderPaper.ignoresSafeArea())
        .preferredColorScheme(.light)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if mode == .spot { mode = .matrix }   // older versions could save spot as the mode
            pushConfig()
            evDamp.set([ev], snap: true)
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
            evDamp.set([ev], snap: !meterPrimed)
            meterPrimed = true
        }
        .onChange(of: calibration) { evDamp.set([ev]) }
        .onChange(of: frozenEV) { evDamp.set([ev]) }
        .onChange(of: shownDistance) { syncDistance() }
        .onChange(of: selected) { syncDistance() }
        .onChange(of: tooClose) {
            if tooClose { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(simpleMode: $simpleMode, useDIN: $useDIN, useFeet: $useFeet, golden: $golden, calibration: $calibration)
                .presentationDetents([.medium, .large])
                .preferredColorScheme(.light)
        }
    }

    private func pushConfig() {
        meter.setConfig(mode: engineMode, spot: spotBuf, radius: spotRadius, focus: focusBuf)
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
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if frozenEV == nil {
            frozenPreviewImage = meter.previewSnapshot()
            frozenEV = liveEV
            frozenDist = meter.distance
        } else {
            unfreeze()
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
                        .opacity(0.9)
                        .overlay(viewfinderPaper.opacity(0.04))
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
                    Circle()
                        .strokeBorder(viewfinderPaper, lineWidth: 2)
                        .shadow(color: viewfinderInk.opacity(0.5), radius: 2)
                        .frame(width: d, height: d)
                        .position(x: spot.x * geo.size.width, y: spot.y * geo.size.height)
                        .animation(.spring(response: 0.4, dampingFraction: 0.72), value: spot)
                        .animation(.interactiveSpring, value: spotRadius)
                        .transition(.scale(scale: 1.6).combined(with: .opacity))
                        .allowsHitTesting(false)
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
                        .foregroundStyle(viewfinderPaper)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(viewfinderInk.opacity(0.88), in: Capsule())
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.3)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }

                VStack {
                    Spacer()
                    modeChips
                }
                .padding(12)

                if meter.denied {
                    VStack(spacing: 10) {
                        Text("Camera access is off")
                            .font(AppTypography.next(size: 16, weight: .semibold))
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
    }

    private var topBar: some View {
        HStack {
            EVBadge(damp: evDamp, frozen: frozenEV != nil, spot: spotActive)
            Spacer(minLength: 12)
            Button {
                showSettings = true
            } label: {
                Text("SETTINGS")
                    .font(AppTypography.next(size: 12, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(viewfinderInk)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }

    private var modeChips: some View {
        HStack(spacing: 0) {
            modeButton(.matrix)
            Rectangle().fill(viewfinderPaper.opacity(0.34)).frame(width: 1, height: 17)
                .padding(.horizontal, 2)
            modeButton(.highlight)
        }
        .padding(.horizontal, 4)
        .background(viewfinderInk.opacity(0.48), in: Capsule())
    }

    private func modeButton(_ meterMode: MeterMode) -> some View {
        let isSelected = !spotActive && baseMode == meterMode
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                mode = meterMode
                spotActive = false
            }
            unfreeze()
        } label: {
            Text(meterMode.title.uppercased())
                .font(AppTypography.next(size: 11, weight: isSelected ? .semibold : .regular))
                .tracking(0.8)
                .foregroundStyle(isSelected ? viewfinderPaper : viewfinderPaper.opacity(0.68))
                .frame(minWidth: 82, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(meterMode.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 8) {
            if controlsExpanded {
                VStack(spacing: 4) {
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                controlsExpanded = false
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(viewfinderInk.opacity(0.65))
                                .frame(width: 32, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Hide exposure controls")
                    }
                    HStack(spacing: 12) {
                        WheelBox(title: "EV", selection: $evIndex, labels: EVComp.labels)
                        WheelBox(
                            title: useDIN ? "DIN" : "ISO",
                            selection: $isoIndex,
                            labels: ISOScale.values.map { ISOScale.label($0, din: useDIN) }
                        )
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack {
                if controlsExpanded {
                    Spacer(minLength: 0)
                } else {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            controlsExpanded = true
                        }
                    } label: {
                        compactSettingLabel("EV", value: EVComp.labels[safeEVIndex])
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Adjust exposure compensation")
                }

                Spacer()

                FreezeButton(frozen: frozenEV != nil) {
                    toggleFreeze()
                }

                Spacer()

                if controlsExpanded {
                    Spacer(minLength: 0)
                } else {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            controlsExpanded = true
                        }
                    } label: {
                        compactSettingLabel(useDIN ? "DIN" : "ISO", value: ISOScale.label(ISOScale.values[safeISOIndex], din: useDIN))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Adjust film speed")
                }
            }
        }
        .padding(.horizontal, 4)

    }

    private func compactSettingLabel(_ title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(AppTypography.next(size: 9, weight: .medium))
                .tracking(0.8)
            Text(value)
                .font(AppTypography.mono(size: 12, weight: .medium))
        }
        .foregroundStyle(viewfinderInk.opacity(0.78))
        .frame(minWidth: 58, minHeight: 48)
        .contentShape(Rectangle())
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Binding var simpleMode: Bool
    @Binding var useDIN: Bool
    @Binding var useFeet: Bool
    @Binding var golden: Int
    @Binding var calibration: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Simple exposure pair", isOn: $simpleMode)
                    Toggle("Show film speed as DIN", isOn: $useDIN)
                    Picker("Distance units", selection: $useFeet) {
                        Text("Meters").tag(false)
                        Text("Feet").tag(true)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("You can also tap m / ft on the open focus scale.")
                }
                Section {
                    Picker("Golden aperture", selection: $golden) {
                        Text("None").tag(-1)
                        ForEach(Rollei.stops.indices, id: \.self) { i in
                            Text("ƒ/" + Rollei.stops[i].label).tag(i)
                        }
                    }
                } footer: {
                    Text("You can also long-press any aperture on the scale. Tap an aperture to set the depth of field shown on the distance dial.")
                }
                Section {
                    Stepper(value: $calibration, in: -3...3, step: 1.0 / 3.0) {
                        HStack {
                            Text("Calibration")
                            Spacer()
                            Text(Fmt.stops(calibration))
                                .font(AppTypography.regular(size: 17))
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Shifts every reading, in stops. Set it once against a meter you trust.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(viewfinderPaper)
            .listRowBackground(viewfinderPaper)
            .toolbarBackground(viewfinderPaper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
