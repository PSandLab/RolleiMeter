import SwiftUI

// MARK: - Hold to Mount Gear Button (Liquid Wave + Bayonet & 6-Blade Iris)

struct HoldToMountGearButton: View {
    let label: String
    var holdDuration: Double = 0.72
    let onMounted: () -> Void

    @State private var isPressing = false
    @State private var progress: CGFloat = 0
    @State private var wavePhase: CGFloat = 0
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        let scale: CGFloat = isPressing ? (0.97 + 0.05 * progress) : 1.0

        ZStack {
            Canvas { ctx, size in
                let w = size.width
                let h = size.height
                let rect = CGRect(origin: .zero, size: size)
                let clipPath = Path(roundedRect: rect, cornerRadius: h / 2)
                ctx.fill(clipPath, with: .color(Palette.accent.opacity(0.20)))

                if progress > 0.001 {
                    let fillX = w * progress
                    let amp: CGFloat = (progress < 0.98) ? (4.5 * sin(progress * .pi) + 2.0) : 0.0
                    var wave = Path()
                    wave.move(to: .zero)
                    wave.addLine(to: CGPoint(x: fillX, y: 0))
                    let steps = 16
                    for s in 1...steps {
                        let frac = CGFloat(s) / CGFloat(steps)
                        let y = h * frac
                        let waveOffset = sin(frac * .pi * 2.2 + wavePhase) * amp
                        wave.addLine(to: CGPoint(x: fillX + waveOffset, y: y))
                    }
                    wave.addLine(to: CGPoint(x: 0, y: h))
                    wave.closeSubpath()

                    var clipped = ctx
                    clipped.clip(to: clipPath)
                    clipped.fill(wave, with: .color(Palette.accent))
                }

                ctx.stroke(clipPath, with: .color(Palette.accent.opacity(0.55)), lineWidth: 1)
            }

            HStack(spacing: 10) {
                // Rotating Bayonet + 6-Blade Iris
                Canvas { ctx, s in
                    let r = min(s.width, s.height) / 2
                    let c = CGPoint(x: s.width / 2, y: s.height / 2)
                    let fg = progress > 0.45 ? Color.black : Palette.accent
                    ctx.stroke(
                        Path(ellipseIn: CGRect(x: c.x - r * 0.85, y: c.y - r * 0.85, width: r * 1.7, height: r * 1.7)),
                        with: .color(fg),
                        lineWidth: 1.6
                    )
                    let rot = Double(progress) * 90.0
                    for lug in 0..<3 {
                        let startDeg = Double(lug) * 120.0 + rot
                        var arc = Path()
                        arc.addArc(center: c, radius: r * 0.64, startAngle: .degrees(startDeg), endAngle: .degrees(startDeg + 42), clockwise: false)
                        ctx.stroke(arc, with: .color(fg), style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
                    }
                    let irisR = max(2.0, r * (0.42 - 0.22 * progress))
                    var hex = Path()
                    for b in 0..<6 {
                        let rad = (Double(b) * 60.0 + rot * 0.5) * .pi / 180.0
                        let pt = CGPoint(x: c.x + CGFloat(cos(rad)) * irisR, y: c.y + CGFloat(sin(rad)) * irisR)
                        if b == 0 { hex.move(to: pt) } else { hex.addLine(to: pt) }
                    }
                    hex.closeSubpath()
                    ctx.stroke(hex, with: .color(fg.opacity(0.85)), lineWidth: 1.2)
                }
                .frame(width: 20, height: 20)

                Text(isPressing ? "MOUNTING BAYONET… \(Int((progress * 100).rounded()))%" : label)
                    .font(AppTypography.label(13, weight: .bold))
                    .foregroundStyle(progress > 0.5 ? Color.black : Palette.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 46)
        .scaleEffect(scale)
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isPressing)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressing else { return }
                    startHold()
                }
                .onEnded { _ in
                    cancelHold()
                }
        )
    }

    private func startHold() {
        isPressing = true
        MechanicalHaptics.click()
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            let start = Date()
            var lastBucket = -1
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                let p = min(1.0, max(0.0, elapsed / holdDuration))
                progress = CGFloat(p)
                wavePhase += 0.28
                let bucket = Int(p * 5)
                if bucket > lastBucket && bucket < 5 {
                    lastBucket = bucket
                    MechanicalHaptics.tick()
                }
                if p >= 1.0 {
                    MechanicalHaptics.heavy()
                    MechanicalHaptics.confirm()
                    isPressing = false
                    progress = 0
                    onMounted()
                    return
                }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        isPressing = false
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            progress = 0
        }
    }
}

// MARK: - Gear Setup Section (Collapsible Card inside Roll & Gear Tab)

struct GearSetupSection: View {
    @ObservedObject var store: FilmLogStore
    let searchQuery: String

    @State private var isExpanded: Bool = false
    @State private var gearSubTab: Int = 0 // 0 = Bodies, 1 = Lenses, 2 = + Custom
    @State private var expandedCameraBrands: Set<String> = []
    @State private var expandedCameraId: String? = nil
    @State private var inlineIncludeAdapter: Bool = false
    @State private var inlineAdapterMountFilter: String = "All"
    @State private var inlineFocalCategory: FocalLengthCategory = .all
    @State private var inlineLensSearchQuery: String = ""
    @State private var lensFocalCategory: FocalLengthCategory = .all

    var body: some View {
        let activeGear = store.activeGear
        let allCameras = GearCatalogCache.allCameras(customCameras: store.customCameras)
        let allLenses = GearCatalogCache.allLensEntries(customLenses: store.customLenses)

        let filteredCameras: [CameraGearSpec] = {
            let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return allCameras }
            return allCameras
                .map { ($0, fuzzyMatchScore(query: q, target: "\($0.brand) \($0.model) \($0.mount) \($0.fixedLensName)")) }
                .filter { $0.1 > 0 }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        }()

        let camerasByBrand: [(String, [CameraGearSpec])] = {
            let grouped = Dictionary(grouping: filteredCameras, by: \.brand)
            return grouped.keys.sorted().map { brand in
                (brand, grouped[brand] ?? [])
            }
        }()

        VStack(alignment: .leading, spacing: 12) {
            // Header Row
            Button {
                MechanicalHaptics.tick()
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    if activeGear.hasCamera {
                        let activeBrand = allCameras.first(where: { $0.id == activeGear.cameraId })?.brand
                            ?? activeGear.cameraName.components(separatedBy: " ").first
                            ?? ""
                        CameraSilhouetteArtwork(
                            model: activeGear.cameraName,
                            mount: activeGear.mount,
                            isFixed: activeGear.isFixedLens,
                            brand: activeBrand,
                            size: 42
                        )
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Palette.panelRaised)
                                .frame(width: 42, height: 42)
                            Image(systemName: "camera.aperture")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Palette.accent)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("CAMERA & LENS RIG")
                                .font(AppTypography.label(10, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(Palette.accent)

                            if activeGear.hasCamera {
                                Text(activeGear.isFixedLens ? "FIXED" : formatMountBadge(activeGear.mount))
                                    .font(AppTypography.mono(9.5, weight: .bold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Palette.accent, in: Capsule())
                            }
                        }

                        Text(activeGear.hasCamera ? activeGear.cameraName : "All Stops Unlocked (Tap to select gear)")
                            .font(AppTypography.label(14, weight: .bold))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)

                        if activeGear.hasCamera {
                            let shutterRange = "\(formatShutterStopLabel(activeGear.maxShutter))–\(formatShutterStopLabel(activeGear.minShutter))"
                            let lensSummary = activeGear.hasLens
                                ? "\(activeGear.lensName) (\(formatApertureRange(activeGear.minAperture, activeGear.maxAperture)))"
                                : "No lens mounted"
                            Text("\(shutterRange) · \(lensSummary)")
                                .font(AppTypography.label(11, weight: .medium))
                                .foregroundStyle(Palette.textSub)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 4)

                    HStack(spacing: 4) {
                        Text(isExpanded ? "Hide" : (activeGear.hasCamera ? "Change" : "Select"))
                            .font(AppTypography.label(11, weight: .bold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Palette.accent.opacity(0.14), in: Capsule())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().overlay(Palette.border)

                // Active Gear Summary + Unmount button if mounted
                if activeGear.hasCamera {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mounted: \(activeGear.cameraName)")
                                .font(AppTypography.label(12, weight: .bold))
                                .foregroundStyle(Palette.text)
                            if activeGear.hasLens {
                                Text("Lens: \(activeGear.lensName)")
                                    .font(AppTypography.label(11, weight: .medium))
                                    .foregroundStyle(Palette.textSub)
                            }
                        }
                        Spacer()
                        Button {
                            MechanicalHaptics.click()
                            store.activeGear = .unloaded
                        } label: {
                            Label("Clear Rig", systemImage: "xmark.circle.fill")
                                .font(AppTypography.label(11, weight: .bold))
                                .foregroundStyle(Palette.bad)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Palette.bad.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Sub-tabs: Bodies / Lenses / + Custom
                HStack(spacing: 6) {
                    ForEach([(0, "Bodies (\(filteredCameras.count))"), (1, "Lenses (\(allLenses.count))"), (2, "+ Custom")], id: \.0) { idx, title in
                        let selected = gearSubTab == idx
                        Button {
                            MechanicalHaptics.tick()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                gearSubTab = idx
                            }
                        } label: {
                            Text(title)
                                .font(AppTypography.label(12, weight: .bold))
                                .foregroundStyle(selected ? .black : Palette.textSub)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    selected ? Palette.accent : Color.white.opacity(0.06),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if gearSubTab == 0 {
                    // Camera Brand Groups
                    VStack(spacing: 8) {
                        ForEach(camerasByBrand, id: \.0) { brand, brandCameras in
                            let isBrandExpanded = !searchQuery.isEmpty
                                || expandedCameraBrands.contains(brand)
                                || brandCameras.contains(where: { $0.id == activeGear.cameraId })

                            CameraBrandAccordion(
                                brand: brand,
                                cameras: brandCameras,
                                isExpanded: isBrandExpanded,
                                activeGear: activeGear,
                                expandedCameraId: $expandedCameraId,
                                allLensEntries: allLenses,
                                inlineIncludeAdapter: $inlineIncludeAdapter,
                                inlineAdapterMountFilter: $inlineAdapterMountFilter,
                                inlineFocalCategory: $inlineFocalCategory,
                                inlineLensSearchQuery: $inlineLensSearchQuery,
                                onToggleBrand: {
                                    MechanicalHaptics.tick()
                                    if expandedCameraBrands.contains(brand) {
                                        expandedCameraBrands.remove(brand)
                                    } else {
                                        expandedCameraBrands.insert(brand)
                                    }
                                },
                                onMountProfile: { profile in
                                    store.activeGear = profile
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                        expandedCameraId = nil
                                        isExpanded = false
                                    }
                                }
                            )
                        }
                    }
                } else if gearSubTab == 1 {
                    // Lenses Tab
                    StandaloneLensBrowser(
                        activeGear: activeGear,
                        allLensEntries: allLenses,
                        searchQuery: searchQuery,
                        focalCategory: $lensFocalCategory,
                        onMountLens: { lens in
                            var updated = activeGear
                            updated.lensId = lens.id
                            updated.lensName = lens.model
                            updated.minAperture = lens.minAperture
                            updated.maxAperture = lens.maxAperture
                            store.activeGear = updated
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                isExpanded = false
                            }
                        }
                    )
                } else {
                    // Custom Gear Builder
                    CustomGearBuilderView(
                        initialSearchText: searchQuery,
                        onCreatedCamera: { cam, profile in
                            store.addCustomCamera(cam)
                            store.activeGear = profile
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                gearSubTab = 0
                                isExpanded = false
                            }
                        },
                        onCreatedLens: { lens in
                            store.addCustomLens(lens)
                            var updated = store.activeGear
                            updated.lensId = lens.id
                            updated.lensName = lens.model
                            updated.minAperture = lens.minAperture
                            updated.maxAperture = lens.maxAperture
                            store.activeGear = updated
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                gearSubTab = 0
                                isExpanded = false
                            }
                        }
                    )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 0.75)
                )
        )
    }
}

// MARK: - Camera Brand Accordion & Inline Setup

private struct CameraBrandAccordion: View {
    let brand: String
    let cameras: [CameraGearSpec]
    let isExpanded: Bool
    let activeGear: ActiveGearProfile
    @Binding var expandedCameraId: String?
    let allLensEntries: [PrewarmedLensEntry]
    @Binding var inlineIncludeAdapter: Bool
    @Binding var inlineAdapterMountFilter: String
    @Binding var inlineFocalCategory: FocalLengthCategory
    @Binding var inlineLensSearchQuery: String
    let onToggleBrand: () -> Void
    let onMountProfile: (ActiveGearProfile) -> Void

    var body: some View {
        let hasActiveCam = cameras.contains(where: { $0.id == activeGear.cameraId })
        VStack(spacing: 6) {
            Button(action: onToggleBrand) {
                HStack(spacing: 10) {
                    CameraBrandLogo(brand: brand, size: 32)

                    Text(brand)
                        .font(AppTypography.label(14, weight: .bold))
                        .foregroundStyle(Palette.text)

                    if hasActiveCam {
                        Text("MOUNTED")
                            .font(AppTypography.mono(9, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Palette.accent, in: Capsule())
                    }

                    Spacer()

                    Text("\(cameras.count)")
                        .font(AppTypography.mono(11, weight: .bold))
                        .foregroundStyle(Palette.textSub)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.06), in: Capsule())

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.textSub)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(hasActiveCam ? Palette.accent.opacity(0.12) : Color.white.opacity(0.04))
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(cameras) { cam in
                        let isMounted = cam.id == activeGear.cameraId
                        let isCardOpen = expandedCameraId == cam.id

                        VStack(spacing: 8) {
                            Button {
                                MechanicalHaptics.tick()
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                                    expandedCameraId = isCardOpen ? nil : cam.id
                                    inlineIncludeAdapter = false
                                    inlineAdapterMountFilter = "All"
                                    inlineFocalCategory = .all
                                    inlineLensSearchQuery = ""
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    CameraSilhouetteArtwork(
                                        model: cam.model,
                                        mount: cam.mount,
                                        isFixed: cam.isFixed,
                                        brand: cam.brand,
                                        size: 34
                                    )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(cam.model)
                                            .font(AppTypography.label(13, weight: .bold))
                                            .foregroundStyle(isMounted ? Palette.accent : Palette.text)
                                            .lineLimit(1)

                                        let shutterText = "\(formatShutterStopLabel(cam.maxShutter))–\(formatShutterStopLabel(cam.minShutter))"
                                        let subText = cam.isFixed
                                            ? "\(shutterText) · \(cam.fixedLensName)"
                                            : "\(shutterText) · \(formatMountBadge(cam.mount))"
                                        Text(subText)
                                            .font(AppTypography.label(11, weight: .medium))
                                            .foregroundStyle(Palette.textSub)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    if isMounted {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Palette.accent)
                                    } else {
                                        Text(cam.isFixed ? "Fixed" : formatMountBadge(cam.mount))
                                            .font(AppTypography.mono(10, weight: .bold))
                                            .foregroundStyle(Palette.textSub)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Color.white.opacity(0.06), in: Capsule())
                                    }
                                }
                                .padding(10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if isCardOpen {
                                CameraInlineSetupPanel(
                                    camera: cam,
                                    activeGear: activeGear,
                                    allLensEntries: allLensEntries,
                                    includeAdapter: $inlineIncludeAdapter,
                                    adapterMountFilter: $inlineAdapterMountFilter,
                                    focalCategory: $inlineFocalCategory,
                                    lensSearchQuery: $inlineLensSearchQuery,
                                    onMountProfile: onMountProfile
                                )
                                .padding(.horizontal, 10)
                                .padding(.bottom, 10)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isMounted ? Palette.accent.opacity(0.10) : Color.black.opacity(0.28))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(isMounted || isCardOpen ? Palette.accent.opacity(0.55) : Color.white.opacity(0.06), lineWidth: 1)
                                )
                        )
                    }
                }
                .padding(.leading, 8)
            }
        }
    }
}

private struct CameraInlineSetupPanel: View {
    let camera: CameraGearSpec
    let activeGear: ActiveGearProfile
    let allLensEntries: [PrewarmedLensEntry]
    @Binding var includeAdapter: Bool
    @Binding var adapterMountFilter: String
    @Binding var focalCategory: FocalLengthCategory
    @Binding var lensSearchQuery: String
    let onMountProfile: (ActiveGearProfile) -> Void

    @State private var selectedLens: LensGearSpec? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Palette.border)

            if camera.isFixed {
                HStack(spacing: 10) {
                    OpticalLensApertureIcon(
                        minAperture: camera.fixedMinAperture,
                        brand: camera.brand,
                        isSelected: true,
                        size: 36
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(camera.fixedLensName)
                            .font(AppTypography.label(13, weight: .bold))
                            .foregroundStyle(Palette.text)
                        Text("Built-in Optic · \(formatApertureRange(camera.fixedMinAperture, camera.fixedMaxAperture))")
                            .font(AppTypography.label(11, weight: .medium))
                            .foregroundStyle(Palette.textSub)
                    }
                    Spacer()
                }
                .padding(8)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                HoldToMountGearButton(label: "Hold to Mount \(camera.model)") {
                    onMountProfile(
                        ActiveGearProfile(
                            cameraId: camera.id,
                            cameraName: camera.model,
                            mount: "Fixed",
                            isFixedLens: true,
                            minShutter: camera.minShutter,
                            maxShutter: camera.maxShutter,
                            lensId: "\(camera.id)_fixed",
                            lensName: camera.fixedLensName,
                            minAperture: camera.fixedMinAperture,
                            maxAperture: camera.fixedMaxAperture
                        )
                    )
                }
            } else {
                // Interchangeable-lens camera setup
                HStack {
                    Text("PAIR \(camera.mount.uppercased()) LENS")
                        .font(AppTypography.label(10, weight: .bold))
                        .foregroundStyle(Palette.accent)
                    Spacer()
                    Button {
                        MechanicalHaptics.tick()
                        includeAdapter.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: includeAdapter ? "checkmark.circle.fill" : "link")
                                .font(.system(size: 10, weight: .bold))
                            Text(includeAdapter ? "Adapter On" : "Mount Adapter")
                                .font(AppTypography.label(10, weight: .bold))
                        }
                        .foregroundStyle(includeAdapter ? .black : Palette.textSub)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(includeAdapter ? Palette.accent : Color.white.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if includeAdapter {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(ADAPTER_MOUNT_FILTERS, id: \.self) { mFilter in
                                let sel = adapterMountFilter == mFilter
                                Button {
                                    MechanicalHaptics.tick()
                                    adapterMountFilter = mFilter
                                } label: {
                                    Text(mFilter)
                                        .font(AppTypography.label(10, weight: .bold))
                                        .foregroundStyle(sel ? .black : Palette.textSub)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(sel ? Palette.accent : Color.white.opacity(0.06), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Focal length category bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(FocalLengthCategory.allCases) { cat in
                            let sel = focalCategory == cat
                            Button {
                                MechanicalHaptics.tick()
                                focalCategory = cat
                            } label: {
                                Text(cat.label)
                                    .font(AppTypography.mono(10, weight: .bold))
                                    .foregroundStyle(sel ? .black : Palette.textSub)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(sel ? Palette.accent : Color.white.opacity(0.06), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Search field for lens
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textDim)
                    TextField("Filter lenses (e.g. 35mm, Summicron, f/1.4)…", text: $lensSearchQuery)
                        .font(AppTypography.label(12))
                        .foregroundStyle(Palette.text)
                    if !lensSearchQuery.isEmpty {
                        Button {
                            lensSearchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.textDim)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                let matchingLenses: [PrewarmedLensEntry] = allLensEntries.filter { entry in
                    let mountOk: Bool = {
                        if !includeAdapter {
                            return entry.lens.mount.caseInsensitiveCompare(camera.mount) == .orderedSame
                        } else {
                            return matchesAdaptedMount(lensMount: entry.lens.mount, filter: adapterMountFilter)
                        }
                    }()
                    guard mountOk else { return false }
                    guard matchesFocalCategory(model: entry.lens.model, category: focalCategory) else { return false }
                    let q = lensSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    if q.isEmpty { return true }
                    return fuzzyMatchScore(query: q, target: "\(entry.lens.brand) \(entry.lens.model) \(entry.lens.mount)") > 0
                }

                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(matchingLenses.prefix(40)) { entry in
                            ForEach(entry.variants) { variant in
                                let spec = variant.spec
                                let isChosen = selectedLens?.id == spec.id
                                    || (selectedLens == nil && activeGear.lensId == spec.id)

                                Button {
                                    MechanicalHaptics.tick()
                                    selectedLens = spec
                                } label: {
                                    HStack(spacing: 8) {
                                        OpticalLensApertureIcon(
                                            minAperture: spec.minAperture,
                                            brand: spec.brand,
                                            isSelected: isChosen,
                                            size: 30
                                        )
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(spec.model)
                                                .font(AppTypography.label(12, weight: .bold))
                                                .foregroundStyle(isChosen ? Palette.accent : Palette.text)
                                                .lineLimit(1)
                                            Text("\(variant.badge) · \(formatApertureRange(spec.minAperture, spec.maxAperture))")
                                                .font(AppTypography.label(10, weight: .medium))
                                                .foregroundStyle(Palette.textSub)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        if isChosen {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(Palette.accent)
                                        }
                                    }
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(isChosen ? Palette.accent.opacity(0.14) : Color.white.opacity(0.04))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)

                let effectiveLens = selectedLens ?? matchingLenses.first?.variants.first?.spec
                HoldToMountGearButton(
                    label: effectiveLens != nil
                        ? "Hold to Mount \(camera.model) + Lens"
                        : "Hold to Mount \(camera.model) (Body Only)"
                ) {
                    onMountProfile(
                        ActiveGearProfile(
                            cameraId: camera.id,
                            cameraName: camera.model,
                            mount: camera.mount,
                            isFixedLens: false,
                            minShutter: camera.minShutter,
                            maxShutter: camera.maxShutter,
                            lensId: effectiveLens?.id ?? "",
                            lensName: effectiveLens?.model ?? "",
                            minAperture: effectiveLens?.minAperture ?? 1.4,
                            maxAperture: effectiveLens?.maxAperture ?? 22.0
                        )
                    )
                }
            }
        }
    }
}

// MARK: - Standalone Lens Browser

private struct StandaloneLensBrowser: View {
    let activeGear: ActiveGearProfile
    let allLensEntries: [PrewarmedLensEntry]
    let searchQuery: String
    @Binding var focalCategory: FocalLengthCategory
    let onMountLens: (LensGearSpec) -> Void

    @State private var mountFilter: String = "All"
    @State private var stagedLens: LensGearSpec? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(FocalLengthCategory.allCases) { cat in
                        let sel = focalCategory == cat
                        Button {
                            MechanicalHaptics.tick()
                            focalCategory = cat
                        } label: {
                            Text(cat.label)
                                .font(AppTypography.mono(10, weight: .bold))
                                .foregroundStyle(sel ? .black : Palette.textSub)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(sel ? Palette.accent : Color.white.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let filtered = allLensEntries.filter { entry in
                if !activeGear.isFixedLens && !activeGear.mount.isEmpty && mountFilter == "Camera Mount" {
                    if entry.lens.mount.caseInsensitiveCompare(activeGear.mount) != .orderedSame {
                        return false
                    }
                }
                guard matchesFocalCategory(model: entry.lens.model, category: focalCategory) else { return false }
                let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                if q.isEmpty { return true }
                return fuzzyMatchScore(query: q, target: "\(entry.lens.brand) \(entry.lens.model) \(entry.lens.mount)") > 0
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(filtered.prefix(60)) { entry in
                        let spec = entry.lens
                        let isStaged = stagedLens?.id == spec.id || activeGear.lensId == spec.id
                        Button {
                            MechanicalHaptics.tick()
                            stagedLens = spec
                        } label: {
                            HStack(spacing: 10) {
                                OpticalLensApertureIcon(
                                    minAperture: spec.minAperture,
                                    brand: spec.brand,
                                    isSelected: isStaged,
                                    size: 34
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(spec.model)
                                        .font(AppTypography.label(13, weight: .bold))
                                        .foregroundStyle(isStaged ? Palette.accent : Palette.text)
                                        .lineLimit(1)
                                    Text("\(formatMountBadge(spec.mount)) · \(formatApertureRange(spec.minAperture, spec.maxAperture))")
                                        .font(AppTypography.label(11, weight: .medium))
                                        .foregroundStyle(Palette.textSub)
                                }
                                Spacer()
                                if isStaged {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Palette.accent)
                                }
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isStaged ? Palette.accent.opacity(0.14) : Color.white.opacity(0.04))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 240)

            if let staged = stagedLens {
                HoldToMountGearButton(label: "Hold to Mount \(staged.model)") {
                    onMountLens(staged)
                }
            }
        }
    }
}

// MARK: - Custom Gear Builder

private struct CustomGearBuilderView: View {
    let initialSearchText: String
    let onCreatedCamera: (CameraGearSpec, ActiveGearProfile) -> Void
    let onCreatedLens: (LensGearSpec) -> Void

    @State private var mode: Int = 0 // 0 = Fixed-Lens Camera, 1 = Interchangeable Body, 2 = Lens
    @State private var brand: String = "Custom"
    @State private var modelName: String = ""
    @State private var fixedLensName: String = "40mm f/2.8"
    @State private var mountName: String = "Leica M"
    @State private var fastestShutterIdx: Int = 14 // 1/500
    @State private var slowestShutterIdx: Int = 5  // 1s
    @State private var widestApertureIdx: Int = 8  // f/2.8
    @State private var smallestApertureIdx: Int = 20 // f/22

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach([(0, "Fixed Camera"), (1, "Camera Body"), (2, "Custom Lens")], id: \.0) { idx, label in
                    let sel = mode == idx
                    Button {
                        MechanicalHaptics.tick()
                        mode = idx
                    } label: {
                        Text(label)
                            .font(AppTypography.label(11, weight: .bold))
                            .foregroundStyle(sel ? .black : Palette.textSub)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(sel ? Palette.accent : Color.white.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                TextField("Brand (e.g. Rollei)", text: $brand)
                    .font(AppTypography.label(12))
                    .foregroundStyle(Palette.text)
                    .padding(9)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                TextField(mode == 2 ? "Lens Model (e.g. 50mm f/1.4)" : "Camera Model", text: $modelName)
                    .font(AppTypography.label(12))
                    .foregroundStyle(Palette.text)
                    .padding(9)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if mode == 0 {
                TextField("Built-in Lens (e.g. Sonnar 40mm f/2.8)", text: $fixedLensName)
                    .font(AppTypography.label(12))
                    .foregroundStyle(Palette.text)
                    .padding(9)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                TextField("Mount (e.g. Leica M, Nikon F, M42)", text: $mountName)
                    .font(AppTypography.label(12))
                    .foregroundStyle(Palette.text)
                    .padding(9)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if mode != 2 {
                let fastStop = ALL_ANALOG_SHUTTER_STOPS[fastestShutterIdx.clamped(to: 0...(ALL_ANALOG_SHUTTER_STOPS.count - 1))]
                let slowStop = ALL_ANALOG_SHUTTER_STOPS[slowestShutterIdx.clamped(to: 0...(ALL_ANALOG_SHUTTER_STOPS.count - 1))]
                HStack {
                    Text("Shutter Range:")
                        .font(AppTypography.label(11, weight: .medium))
                        .foregroundStyle(Palette.textSub)
                    Spacer()
                    Text("\(formatShutterStopLabel(fastStop)) – \(formatShutterStopLabel(slowStop))")
                        .font(AppTypography.mono(11, weight: .bold))
                        .foregroundStyle(Palette.accent)
                }
                HStack(spacing: 10) {
                    Stepper("Fast", value: $fastestShutterIdx, in: 6...(ALL_ANALOG_SHUTTER_STOPS.count - 1))
                        .font(AppTypography.label(11))
                    Stepper("Slow", value: $slowestShutterIdx, in: 0...10)
                        .font(AppTypography.label(11))
                }
                .foregroundStyle(Palette.textSub)
            }

            if mode != 1 {
                let wideF = ALL_ANALOG_APERTURE_STOPS[widestApertureIdx.clamped(to: 0...(ALL_ANALOG_APERTURE_STOPS.count - 1))]
                let smallF = ALL_ANALOG_APERTURE_STOPS[smallestApertureIdx.clamped(to: 0...(ALL_ANALOG_APERTURE_STOPS.count - 1))]
                HStack {
                    Text("Aperture Range:")
                        .font(AppTypography.label(11, weight: .medium))
                        .foregroundStyle(Palette.textSub)
                    Spacer()
                    Text("\(formatApertureRange(wideF, smallF))")
                        .font(AppTypography.mono(11, weight: .bold))
                        .foregroundStyle(Palette.accent)
                }
                HStack(spacing: 10) {
                    Stepper("Wide", value: $widestApertureIdx, in: 0...14)
                        .font(AppTypography.label(11))
                    Stepper("Min", value: $smallestApertureIdx, in: 12...(ALL_ANALOG_APERTURE_STOPS.count - 1))
                        .font(AppTypography.label(11))
                }
                .foregroundStyle(Palette.textSub)
            }

            let trimmedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (initialSearchText.isEmpty ? "Custom Analog Rig" : initialSearchText)
                : modelName.trimmingCharacters(in: .whitespacesAndNewlines)

            HoldToMountGearButton(label: "Hold to Save & Mount \(trimmedModel)") {
                let cleanBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom" : brand.trimmingCharacters(in: .whitespacesAndNewlines)
                let fastStop = ALL_ANALOG_SHUTTER_STOPS[fastestShutterIdx.clamped(to: 0...(ALL_ANALOG_SHUTTER_STOPS.count - 1))]
                let slowStop = ALL_ANALOG_SHUTTER_STOPS[slowestShutterIdx.clamped(to: 0...(ALL_ANALOG_SHUTTER_STOPS.count - 1))]
                let wideF = ALL_ANALOG_APERTURE_STOPS[widestApertureIdx.clamped(to: 0...(ALL_ANALOG_APERTURE_STOPS.count - 1))]
                let smallF = ALL_ANALOG_APERTURE_STOPS[smallestApertureIdx.clamped(to: 0...(ALL_ANALOG_APERTURE_STOPS.count - 1))]

                if mode == 2 {
                    let lens = LensGearSpec(
                        id: "custom_lens_\(Int(Date().timeIntervalSince1970))",
                        brand: cleanBrand,
                        model: trimmedModel,
                        mount: mountName,
                        minAperture: wideF,
                        maxAperture: smallF,
                        isCustom: true
                    )
                    onCreatedLens(lens)
                } else {
                    let isFixed = (mode == 0)
                    let camId = "custom_cam_\(Int(Date().timeIntervalSince1970))"
                    let cam = CameraGearSpec(
                        id: camId,
                        brand: cleanBrand,
                        model: trimmedModel,
                        isFixed: isFixed,
                        mount: isFixed ? "Fixed" : mountName,
                        minShutter: slowStop,
                        maxShutter: fastStop,
                        fixedLensName: isFixed ? fixedLensName : "",
                        fixedMinAperture: isFixed ? wideF : 0.0,
                        fixedMaxAperture: isFixed ? smallF : 0.0,
                        isCustom: true
                    )
                    let profile = ActiveGearProfile(
                        cameraId: camId,
                        cameraName: trimmedModel,
                        mount: isFixed ? "Fixed" : mountName,
                        isFixedLens: isFixed,
                        minShutter: slowStop,
                        maxShutter: fastStop,
                        lensId: isFixed ? "\(camId)_fixed" : "",
                        lensName: isFixed ? fixedLensName : "",
                        minAperture: isFixed ? wideF : 1.4,
                        maxAperture: isFixed ? smallF : 22.0
                    )
                    onCreatedCamera(cam, profile)
                }
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
