import Foundation
import SwiftUI
import UIKit

// MARK: - Camera & Optics Studio (Clean Hierarchy, Single-Column List & Bottom-Docked Cocking Lever)

// MARK: - RolleiMeter Gear Liquid Glass Controls

private struct GearGlassCapsuleModifier: ViewModifier {
    let tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                content.glassEffect(
                    .regular.tint(tint).interactive(),
                    in: Capsule()
                )
            } else {
                content.glassEffect(
                    .regular.interactive(),
                    in: Capsule()
                )
            }
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(
                            Color.white.opacity(0.14),
                            lineWidth: 0.7
                        )
                }
        }
    }
}

private struct GearGlassGroupModifier: ViewModifier {
    let spacing: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

private extension View {
    func gearGlass(tint: Color? = nil) -> some View {
        modifier(GearGlassCapsuleModifier(tint: tint))
    }

    func gearGlassGroup(spacing: CGFloat = 8) -> some View {
        modifier(GearGlassGroupModifier(spacing: spacing))
    }
}

private struct GearGlassChip: View {
    let title: String
    let isSelected: Bool
    var minHeight: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(
                    .subheadline.weight(
                        isSelected ? .semibold : .medium
                    )
                )
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 14)
                .frame(minHeight: minHeight)
                .foregroundStyle(
                    isSelected ? Palette.accent : Palette.textSub
                )
                .gearGlass(
                    tint: isSelected
                        ? Palette.accent.opacity(0.22)
                        : nil
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct CameraLensView: View {
    @ObservedObject var store: FilmLogStore
    var onFinish: () -> Void = {}

    private enum SelectionStep: Int {
        case body = 1
        case lens = 2
    }

    private enum MountSetup: String, CaseIterable {
        case matched = "Native"
        case adapter = "Adapt Mount"
        case bodyOnly = "Body Only"
    }

    @State private var step: SelectionStep = .body
    @State private var selectedBrand: String = "Rollei"
    @State private var showAllBodiesForBrand: Bool = false
    @State private var focalFilter: FocalLengthCategory = .all
    @State private var mountSetup: MountSetup = .matched
    @State private var adapterMountFilter: String = "All"
    @State private var searchText: String = ""

    @State private var stagedCamera: CameraGearSpec = GearCatalogCache.defaultCamera
    @State private var stagedLensEntry: PrewarmedLensEntry? = nil
    @State private var stagedVariantID: String = ""
    @State private var isCocked: Bool = true
    @State private var didInitialize: Bool = false
    @State private var showRemoveConfirm: Bool = false

    private let brandList: [String] = [
        "Rollei", "Leica", "Nikon", "Canon", "Hasselblad", "Contax",
        "Pentax", "Olympus", "Minolta", "Mamiya", "Fujifilm",
        "Voigtländer", "Yashica", "Ricoh", "Konica", "Custom", "Other"
    ]

    private var allCameras: [CameraGearSpec] {
        GearCatalogCache.allCameras(customCameras: store.customCameras)
    }

    private var allLenses: [PrewarmedLensEntry] {
        GearCatalogCache.allLensEntries(customLenses: store.customLenses)
    }

    private var activeVariantSpec: LensGearSpec? {
        guard let entry = stagedLensEntry else { return nil }
        return entry.variants.first(where: { $0.id == stagedVariantID })?.spec
            ?? entry.variants.first?.spec
            ?? entry.lens
    }

    private var resolvedPreviewProfile: ActiveGearProfile {
        if stagedCamera.isFixed {
            let fixedTitle = stagedCamera.fixedLensName.isEmpty ? "Fixed lens" : stagedCamera.fixedLensName
            return ActiveGearProfile(
                cameraId: stagedCamera.id,
                cameraName: stagedCamera.model,
                mount: "Fixed",
                isFixedLens: true,
                minShutter: stagedCamera.minShutter,
                maxShutter: stagedCamera.maxShutter,
                lensId: "\(stagedCamera.id)_fixed",
                lensName: fixedTitle,
                minAperture: stagedCamera.fixedMinAperture > 0 ? stagedCamera.fixedMinAperture : 2.8,
                maxAperture: stagedCamera.fixedMaxAperture > 0 ? stagedCamera.fixedMaxAperture : 22.0,
                apertureStops: stagedCamera.fixedApertureStops
            )
        }

        switch mountSetup {
        case .bodyOnly:
            return ActiveGearProfile(
                cameraId: stagedCamera.id,
                cameraName: stagedCamera.model,
                mount: stagedCamera.mount,
                isFixedLens: false,
                minShutter: stagedCamera.minShutter,
                maxShutter: stagedCamera.maxShutter,
                lensId: "",
                lensName: "",
                minAperture: 1.4,
                maxAperture: 22.0,
                apertureStops: []
            )
        case .adapter, .matched:
            if let lens = activeVariantSpec {
                return ActiveGearProfile(
                    cameraId: stagedCamera.id,
                    cameraName: stagedCamera.model,
                    mount: stagedCamera.mount,
                    isFixedLens: false,
                    minShutter: stagedCamera.minShutter,
                    maxShutter: stagedCamera.maxShutter,
                    lensId: lens.id,
                    lensName: lens.model,
                    minAperture: lens.minAperture,
                    maxAperture: lens.maxAperture,
                    apertureStops: lens.apertureStops
                )
            }
            return ActiveGearProfile(
                cameraId: stagedCamera.id,
                cameraName: stagedCamera.model,
                mount: stagedCamera.mount,
                isFixedLens: false,
                minShutter: stagedCamera.minShutter,
                maxShutter: stagedCamera.maxShutter,
                lensId: "",
                lensName: "",
                minAperture: 1.4,
                maxAperture: 22.0,
                apertureStops: []
            )
        }
    }

    private var isStagedComboCurrentlyMounted: Bool {
        store.activeGear == resolvedPreviewProfile
    }

    private func cameraPriorityScore(_ cam: CameraGearSpec) -> Int {
        let m = cam.model.lowercased()
        var score = 0
        if !cam.isFixed { score += 500 }
        if m.contains("m6") || m.contains("m3") || m.contains("mp") || m.contains("m4") || m.contains("m2") || m.contains("m-a") { score += 300 }
        if m.contains("fm2") || m.contains("f3") || m.contains("f2") || m.contains("f-1") || m.contains("ae-1") { score += 300 }
        if m.contains("500c") || m.contains("501") || m.contains("503") || m.contains("35 s") || m.contains("2.8f") { score += 300 }
        if m.contains("t2") || m.contains("t3") || m.contains("g2") || m.contains("k1000") || m.contains("lx") || m.contains("om-1") { score += 250 }
        if m.contains("mini") || m.contains("zoom") || m.contains("af-") { score -= 200 }
        return score
    }

    private var filteredCameras: [CameraGearSpec] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            return allCameras
                .map { ($0, fuzzyMatchScore(query: q, target: "\($0.brand) \($0.model) \($0.mount) \($0.fixedLensName)")) }
                .filter { $0.1 > 0 }
                .sorted { $0.1 > $1.1 }
                .map { $0.0 }
        }

        let pool: [CameraGearSpec]
        switch selectedBrand {
        case "Custom":
            pool = allCameras.filter { $0.isCustom }
        case "Other":
            let known = Set(brandList)
            pool = allCameras.filter { !known.contains($0.brand) && !$0.isCustom }
        default:
            pool = allCameras.filter { $0.brand.caseInsensitiveCompare(selectedBrand) == .orderedSame }
        }

        return pool.sorted { a, b in
            let sa = cameraPriorityScore(a)
            let sb = cameraPriorityScore(b)
            if sa != sb { return sa > sb }
            return a.model.localizedStandardCompare(b.model) == .orderedAscending
        }
    }

    private var filteredLenses: [PrewarmedLensEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        let mountPool: [PrewarmedLensEntry]

        switch mountSetup {
        case .matched:
            // Native means exact mount equality only.
            // Never fall back to all catalog lenses.
            mountPool = allLenses.filter {
                $0.lens.mount.caseInsensitiveCompare(stagedCamera.mount) == .orderedSame
            }

        case .adapter:
            if adapterMountFilter == "All" {
                mountPool = allLenses
            } else {
                mountPool = allLenses.filter {
                    matchesAdaptedMount(
                        lensMount: $0.lens.mount,
                        filter: adapterMountFilter
                    )
                }
            }

        case .bodyOnly:
            mountPool = []
        }

        let focalPool: [PrewarmedLensEntry]

        if focalFilter == .all {
            focalPool = mountPool
        } else {
            focalPool = mountPool.filter {
                matchesFocalCategory(
                    model: $0.lens.model,
                    category: focalFilter
                )
            }
        }

        guard !q.isEmpty else {
            return focalPool
        }

        return focalPool
            .map { entry in
                let variantSearchText = entry.variants.map { variant in
                    [
                        variant.badge,
                        variant.subtitle,
                        variant.spec.model,
                        variant.spec.mount
                    ]
                    .joined(separator: " ")
                }
                .joined(separator: " ")

                let target = [
                    entry.lens.brand,
                    entry.lens.model,
                    entry.lens.mount,
                    variantSearchText
                ]
                .joined(separator: " ")

                return (
                    entry,
                    fuzzyMatchScore(query: q, target: target)
                )
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. TOP ACTIVE RIG SUMMARY & INTEGRATED 2-STEP SWITCHER
                activeRigHeaderCard
                    .padding(.horizontal, 16)

                // 2. SINGLE HORIZONTAL FILTER BAR (44pt Touch Targets, Edge-to-Edge Content Margins)
                if step == .body || stagedCamera.isFixed {
                    bodyBrandFilterStrip
                    bodyListSection
                        .padding(.horizontal, 16)
                } else {
                    lensFocalFilterStrip
                    lensListSection
                        .padding(.horizontal, 16)
                }

                if store.activeGear.hasCamera {
                    Button(role: .destructive) {
                        showRemoveConfirm = true
                    } label: {
                        Label("Detach Camera from Meter", systemImage: "eject.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.bad)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Palette.panel, in: .rect(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Palette.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            BottomCockingLeverDock(
                cameraModel: stagedCamera.model,
                lensSummary: resolvedPreviewProfile.hasLens
                    ? cleanLensDisplayName(resolvedPreviewProfile.lensName, brand: stagedCamera.brand)
                    : "Body Only",
                isCocked: $isCocked
            ) {
                commitStagedGear()
            }
        }
        .searchable(
            text: $searchText,
            prompt: (step == .body || stagedCamera.isFixed) ? "Search cameras" : "Search lenses"
        )
        .navigationTitle("Camera & Optics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    CustomGearForm(
                        store: store,
                        onFinish: onFinish,
                        presetKinds: (step == .lens && !stagedCamera.isFixed)
                            ? [.lens]
                            : [.fixedLens, .body],
                        presetBrand: selectedBrand == "Custom" || selectedBrand == "Other"
                            ? ""
                            : selectedBrand,
                        presetCamera: (step == .lens && !stagedCamera.isFixed)
                            ? stagedCamera
                            : nil
                    )
                } label: {
                    Label("Custom", systemImage: "plus")
                }
            }
        }
        .onAppear {
            syncStagedWithActiveGearIfNeeded()
        }
        .confirmationDialog("Detach active camera?", isPresented: $showRemoveConfirm) {
            Button("Detach Camera", role: .destructive) {
                store.activeGear = .unloaded
                Haptics.success()
                onFinish()
            }
        }
    }

    // MARK: - Active Rig Summary + Grouped Liquid Glass Step Switcher

    private var activeRigHeaderCard: some View {
        let preview = resolvedPreviewProfile

        return VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 12) {
                CameraBrandLogo(
                    brand: stagedCamera.brand,
                    size: 48
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(strippedCameraTitle(stagedCamera))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(
                        preview.hasLens
                            ? cleanLensDisplayName(
                                preview.lensName,
                                brand: stagedCamera.brand
                            )
                            : "NO LENS STAGED · \(formatMountBadge(stagedCamera.mount))"
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.textSub)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Circle()
                    .fill(isCocked ? Palette.good : Palette.textDim)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(isCocked ? "Rig cocked" : "Rig needs cocking")
            }

            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Image(systemName: "timer")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.textDim)

                    Text(
                        shutterRangeText(
                            stagedCamera.minShutter,
                            stagedCamera.maxShutter
                        )
                    )
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                }

                if preview.hasLens {
                    HStack(spacing: 5) {
                        Image(systemName: "camera.aperture")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.textDim)

                        Text(
                            formatApertureRange(
                                preview.minAperture,
                                preview.maxAperture
                            )
                        )
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(Palette.textSub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    }
                } else {
                    Text("BODY ONLY")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Palette.textSub)
                }

                if mountSetup == .adapter {
                    Text("ADAPTED")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Palette.accent)
                }

                Spacer(minLength: 0)
            }

            if !stagedCamera.isFixed {
                HStack(spacing: 8) {
                    stepTabButton(
                        stepNumber: "1",
                        title: "BODY",
                        isActive: step == .body
                    ) {
                        guard step != .body else { return }
                        Haptics.tap()

                        withAnimation(.snappy(duration: 0.22)) {
                            searchText = ""
                            step = .body
                        }
                    }
                    .frame(maxWidth: .infinity)

                    stepTabButton(
                        stepNumber: "2",
                        title: "LENS",
                        isActive: step == .lens
                    ) {
                        guard step != .lens else { return }
                        Haptics.tap()

                        withAnimation(.snappy(duration: 0.22)) {
                            searchText = ""
                            step = .lens
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .gearGlassGroup(spacing: 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(0.07),
                            lineWidth: 0.8
                        )
                }
        )
    }

    private func stepTabButton(
        stepNumber: String,
        title: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(stepNumber)
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .frame(width: 20, height: 20)
                    .background {
                        Circle()
                            .fill(
                                isActive
                                    ? Palette.accent.opacity(0.22)
                                    : Color.white.opacity(0.08)
                            )
                    }

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .padding(.horizontal, 12)
            .foregroundStyle(
                isActive ? Palette.accent : Palette.textSub
            )
            .gearGlass(
                tint: isActive
                    ? Palette.accent.opacity(0.22)
                    : nil
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - 2. Single-Tier Filter Strips (44pt Touch Targets, Proper Margins)

    @ViewBuilder
    private var bodyBrandFilterStrip: some View {
        let isSearching = !searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty

        if !isSearching {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(brandList, id: \.self) { brand in
                        let active = selectedBrand == brand

                        GearGlassChip(
                            title: brand,
                            isSelected: active
                        ) {
                            guard !active else { return }

                            UISelectionFeedbackGenerator()
                                .selectionChanged()

                            withAnimation(.snappy(duration: 0.20)) {
                                selectedBrand = brand
                                searchText = ""
                                showAllBodiesForBrand = false
                            }
                        }
                    }
                }
                .gearGlassGroup(spacing: 8)
                .padding(.horizontal, 16)
            }
            .contentMargins(.horizontal, 0, for: .scrollContent)
        }
    }

    private var lensFocalFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FocalLengthCategory.allCases) { category in
                    let active = focalFilter == category

                    let title = category == .all
                        ? "All"
                        : (
                            category == .zoom
                                ? "Zooms"
                                : "\(category.label)mm"
                        )

                    GearGlassChip(
                        title: title,
                        isSelected: active
                    ) {
                        guard !active else { return }

                        UISelectionFeedbackGenerator()
                            .selectionChanged()

                        withAnimation(.snappy(duration: 0.20)) {
                            focalFilter = category
                        }
                    }
                }

                GearGlassChip(
                    title: "Native",
                    isSelected: mountSetup == .matched
                ) {
                    guard mountSetup != .matched else { return }
                    Haptics.tap()
                    setMountSetup(.matched)
                }

                GearGlassChip(
                    title: "Adapt Mount",
                    isSelected: mountSetup == .adapter
                ) {
                    guard mountSetup != .adapter else { return }
                    Haptics.tap()
                    setMountSetup(.adapter)
                }

                GearGlassChip(
                    title: "Body Only",
                    isSelected: mountSetup == .bodyOnly
                ) {
                    guard mountSetup != .bodyOnly else { return }
                    Haptics.tap()
                    setMountSetup(.bodyOnly)
                }

                if mountSetup == .adapter {
                    Menu {
                        Picker(
                            "Lens Mount",
                            selection: Binding(
                                get: { adapterMountFilter },
                                set: { setAdapterMountFilter($0) }
                            )
                        ) {
                            ForEach(ADAPTER_MOUNT_FILTERS, id: \.self) { mount in
                                Text(mount).tag(mount)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.caption.weight(.semibold))

                            Text(
                                adapterMountFilter == "All"
                                    ? "Lens Mount"
                                    : adapterMountFilter
                            )
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .foregroundStyle(Palette.accent)
                        .gearGlass(
                            tint: Palette.accent.opacity(0.18)
                        )
                    }
                    .accessibilityLabel("Filter adapted lenses by lens mount")
                    .accessibilityValue(adapterMountFilter)
                }
            }
            .gearGlassGroup(spacing: 8)
            .padding(.horizontal, 16)
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }

    // MARK: - 3. Airy Single-Column Scannable Lists

    @ViewBuilder
    private var bodyListSection: some View {
        let cameras = filteredCameras
        let isSearching = !searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty

        let visibleCameras = (
            isSearching || showAllBodiesForBrand
        )
            ? cameras
            : Array(cameras.prefix(8))

        VStack(spacing: 10) {
            if visibleCameras.isEmpty {
                ContentUnavailableView(
                    isSearching ? "No Matching Cameras" : "No Camera Bodies",
                    systemImage: "camera",
                    description: Text(
                        isSearching
                            ? "Try another camera name or manufacturer."
                            : "Choose another manufacturer or add a custom camera."
                    )
                )
            } else {
                ForEach(visibleCameras) { camera in
                    let isSelected = stagedCamera.id == camera.id

                    CameraBodyListRow(
                        camera: camera,
                        isSelected: isSelected
                    ) {
                        Haptics.tap()

                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                            selectCameraBody(camera)
                        }
                    }
                    .contextMenu {
                        if camera.isCustom {
                            Button(role: .destructive) {
                                deleteCustomCamera(camera)
                            } label: {
                                Label(
                                    "Delete Custom Camera",
                                    systemImage: "trash"
                                )
                            }
                        }
                    }
                }
            }

            if !isSearching && cameras.count > 8 {
                Button {
                    Haptics.tap()

                    withAnimation(.snappy(duration: 0.22)) {
                        showAllBodiesForBrand.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(
                            showAllBodiesForBrand
                                ? "Show Top Flagships"
                                : "Show All \(cameras.count) \(selectedBrand) Models"
                        )

                        Image(
                            systemName: showAllBodiesForBrand
                                ? "chevron.up"
                                : "chevron.down"
                        )
                        .font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textSub)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        Palette.panel,
                        in: .rect(cornerRadius: 16, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var lensListSection: some View {
        let lenses = filteredLenses

        VStack(spacing: 10) {
            if mountSetup == .bodyOnly {
                ContentUnavailableView(
                    "Body Only",
                    systemImage: "camera",
                    description: Text(
                        "No lens is staged. Choose Native or Adapt Mount to attach a lens."
                    )
                )
            } else if lenses.isEmpty {
                ContentUnavailableView(
                    mountSetup == .matched
                        ? "No Native Lenses"
                        : "No Matching Lenses",
                    systemImage: "camera.macro",
                    description: Text(
                        mountSetup == .matched
                            ? "This body has no catalog lenses for its native mount. Choose Adapt Mount to browse other lens mounts."
                            : "No lenses match the selected mount and focal-length filters."
                    )
                )
            } else {
                ForEach(lenses) { entry in
                    let isSelected =
                        stagedLensEntry?.id == entry.id
                        && mountSetup != .bodyOnly

                    OpticalLensListRow(
                        entry: entry,
                        isSelected: isSelected,
                        selectedVariantID: $stagedVariantID
                    ) {
                        Haptics.tap()

                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                            stagedLensEntry = entry
                            stagedVariantID = entry.variants.first?.id ?? ""

                            if mountSetup == .bodyOnly {
                                mountSetup = .matched
                            }

                            isCocked = isStagedComboCurrentlyMounted
                        }
                    } onVariantChange: {
                        isCocked = isStagedComboCurrentlyMounted
                    }
                    .contextMenu {
                        if entry.lens.isCustom {
                            Button(role: .destructive) {
                                deleteCustomLens(entry.lens)
                            } label: {
                                Label(
                                    "Delete Custom Lens",
                                    systemImage: "trash"
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Selection & State Sync Helpers

    private func deleteCustomCamera(_ camera: CameraGearSpec) {
        let wasStaged = stagedCamera.id == camera.id

        store.removeCustomCamera(id: camera.id)

        guard wasStaged else { return }

        guard let fallback = allCameras.first else {
            stagedLensEntry = nil
            stagedVariantID = ""
            isCocked = false
            return
        }

        withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
            selectCameraBody(fallback)
        }
    }

    private func deleteCustomLens(_ lens: LensGearSpec) {
        let wasStaged = stagedLensEntry?.lens.id == lens.id

        store.removeCustomLens(id: lens.id)

        guard wasStaged else { return }

        let remaining = allLenses

        let replacement: PrewarmedLensEntry?

        switch mountSetup {
        case .matched:
            replacement = remaining.first(where: {
                $0.lens.mount.caseInsensitiveCompare(stagedCamera.mount) == .orderedSame
            })

        case .adapter:
            replacement = remaining.first(where: {
                adapterMountFilter == "All"
                    || matchesAdaptedMount(
                        lensMount: $0.lens.mount,
                        filter: adapterMountFilter
                    )
            })

        case .bodyOnly:
            replacement = nil
        }

        withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
            stagedLensEntry = replacement
            stagedVariantID = replacement?.variants.first?.id ?? ""

            if replacement == nil && mountSetup != .bodyOnly {
                mountSetup = .bodyOnly
            }
        }

        isCocked = isStagedComboCurrentlyMounted
    }

    private func setAdapterMountFilter(_ filter: String) {
        adapterMountFilter = filter

        guard mountSetup == .adapter else { return }

        let candidates = filter == "All"
            ? allLenses
            : allLenses.filter {
                matchesAdaptedMount(
                    lensMount: $0.lens.mount,
                    filter: filter
                )
            }

        if let current = stagedLensEntry,
           filter == "All" || matchesAdaptedMount(
                lensMount: current.lens.mount,
                filter: filter
           ) {
            // Keep the currently staged lens if it still matches.
        } else {
            stagedLensEntry = candidates.first
            stagedVariantID = candidates.first?.variants.first?.id ?? ""
        }

        isCocked = isStagedComboCurrentlyMounted
    }

    private func setMountSetup(_ newMode: MountSetup) {
        guard !stagedCamera.isFixed else { return }

        withAnimation(.snappy(duration: 0.22)) {
            switch newMode {
            case .matched:
                let native = allLenses.filter {
                    $0.lens.mount.caseInsensitiveCompare(stagedCamera.mount) == .orderedSame
                }

                if let current = stagedLensEntry,
                   current.lens.mount.caseInsensitiveCompare(stagedCamera.mount) == .orderedSame {
                    mountSetup = .matched
                } else if let replacement = native.first(where: {
                    $0.focalLengthMm >= 34 && $0.focalLengthMm <= 55
                }) ?? native.first {
                    stagedLensEntry = replacement
                    stagedVariantID = replacement.variants.first?.id ?? ""
                    mountSetup = .matched
                } else {
                    stagedLensEntry = nil
                    stagedVariantID = ""
                    mountSetup = .bodyOnly
                }

            case .adapter:
                mountSetup = .adapter
                setAdapterMountFilter(adapterMountFilter)

            case .bodyOnly:
                mountSetup = .bodyOnly
            }
        }

        isCocked = isStagedComboCurrentlyMounted
    }

    private func selectCameraBody(_ cam: CameraGearSpec) {
        stagedCamera = cam

        selectedBrand = cam.isCustom
            ? "Custom"
            : (
                brandList.first(where: {
                    $0.caseInsensitiveCompare(cam.brand) == .orderedSame
                }) ?? "Other"
            )

        searchText = ""
        showAllBodiesForBrand = false

        if cam.isFixed {
            step = .body
            stagedLensEntry = nil
            stagedVariantID = ""
            mountSetup = .matched
        } else {
            let matching = allLenses.filter {
                $0.lens.mount.caseInsensitiveCompare(cam.mount) == .orderedSame
            }

            if let current = stagedLensEntry,
               current.lens.mount.caseInsensitiveCompare(cam.mount) == .orderedSame {
                mountSetup = .matched
            } else if let standard = matching.first(where: {
                $0.focalLengthMm >= 34 && $0.focalLengthMm <= 55
            }) ?? matching.first {
                stagedLensEntry = standard
                stagedVariantID = standard.variants.first?.id ?? ""
                mountSetup = .matched
            } else {
                stagedLensEntry = nil
                stagedVariantID = ""
                mountSetup = .bodyOnly
            }

            step = .lens
        }

        isCocked = isStagedComboCurrentlyMounted
    }

    private func syncStagedWithActiveGearIfNeeded() {
        guard !didInitialize else { return }
        didInitialize = true
        let active = store.activeGear
        if let matchCam = allCameras.first(where: { $0.id == active.cameraId }) {
            stagedCamera = matchCam
            selectedBrand = brandList.first(where: {
                $0.caseInsensitiveCompare(matchCam.brand) == .orderedSame
            }) ?? "Other"
        } else if let firstCam = allCameras.first {
            stagedCamera = firstCam
            selectedBrand = brandList.first(where: {
                $0.caseInsensitiveCompare(firstCam.brand) == .orderedSame
            }) ?? "Other"
        }

        if stagedCamera.isFixed {
            step = .body
            isCocked = isStagedComboCurrentlyMounted
            return
        }

        if active.lensId.isEmpty {
            mountSetup = .bodyOnly
            isCocked = isStagedComboCurrentlyMounted
            return
        }

        for entry in allLenses {
            if entry.lens.id == active.lensId {
                stagedLensEntry = entry
                stagedVariantID = entry.variants.first?.id ?? ""
                mountSetup = .matched
                isCocked = isStagedComboCurrentlyMounted
                return
            }
            if let v = entry.variants.first(where: { $0.spec.id == active.lensId }) {
                stagedLensEntry = entry
                stagedVariantID = v.id
                mountSetup = .matched
                isCocked = isStagedComboCurrentlyMounted
                return
            }
        }

        let matching = allLenses.filter { $0.lens.mount.caseInsensitiveCompare(stagedCamera.mount) == .orderedSame }
        if let firstMatch = matching.first(where: { $0.focalLengthMm >= 34 && $0.focalLengthMm <= 55 }) ?? matching.first {
            stagedLensEntry = firstMatch
            stagedVariantID = firstMatch.variants.first?.id ?? ""
            mountSetup = .matched
        } else {
            stagedLensEntry = nil
            stagedVariantID = ""
            mountSetup = .bodyOnly
        }
        isCocked = isStagedComboCurrentlyMounted
    }

    private func commitStagedGear() {
        store.activeGear = resolvedPreviewProfile
        isCocked = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            onFinish()
        }
    }
}

// MARK: - Airy Single-Column Camera & Lens Rows (Surface Elevation, Zero Border Overload)

private struct CameraBodyListRow: View {
    let camera: CameraGearSpec
    let isSelected: Bool
    let onSelect: () -> Void

    private var metadata: String {
        if camera.isFixed {
            let lens = camera.fixedLensName.isEmpty
                ? "Fixed Lens"
                : cleanLensDisplayName(
                    camera.fixedLensName,
                    brand: camera.brand
                )

            return "\(lens) · \(shutterRangeText(camera.minShutter, camera.maxShutter))"
        }

        return "\(formatMountBadge(camera.mount)) Mount · Shutter \(shutterRangeText(camera.minShutter, camera.maxShutter))"
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(camera.model)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(metadata)
                        .font(.footnote.weight(.medium).monospacedDigit())
                        .foregroundStyle(Palette.textSub)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                ZStack {
                    Circle()
                        .fill(
                            isSelected
                                ? Palette.accent
                                : Color.white.opacity(0.07)
                        )
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(Palette.accentInk)
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(
                        isSelected
                            ? Palette.panelRaised
                            : Palette.panel
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .strokeBorder(
                                isSelected
                                    ? Palette.accent.opacity(0.36)
                                    : Color.white.opacity(0.055),
                                lineWidth: isSelected ? 1.1 : 0.7
                            )
                    }
            }
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct OpticalLensListRow: View {
    let entry: PrewarmedLensEntry
    let isSelected: Bool
    @Binding var selectedVariantID: String
    let onSelect: () -> Void
    let onVariantChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onSelect) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(
                            cleanLensDisplayName(
                                entry.lens.model,
                                brand: entry.lens.brand
                            )
                        )
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Palette.text)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                        Text(
                            "\(entry.lens.brand) · \(formatMountBadge(entry.lens.mount)) · \(formatApertureRange(entry.lens.minAperture, entry.lens.maxAperture))"
                        )
                        .font(.footnote.weight(.medium).monospacedDigit())
                        .foregroundStyle(Palette.textSub)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    ZStack {
                        Circle()
                            .fill(
                                isSelected
                                    ? Palette.accent
                                    : Color.white.opacity(0.07)
                            )
                            .frame(width: 24, height: 24)

                        if isSelected {
                            Circle()
                                .fill(Palette.accentInk)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSelected && entry.variants.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(entry.variants) { variant in
                            let active = (
                                variant.id == selectedVariantID
                                || (
                                    selectedVariantID.isEmpty
                                    && variant.id == entry.variants.first?.id
                                )
                            )

                            GearGlassChip(
                                title: variant.badge,
                                isSelected: active,
                                minHeight: 44
                            ) {
                                guard !active else { return }

                                UISelectionFeedbackGenerator()
                                    .selectionChanged()

                                withAnimation(.snappy(duration: 0.18)) {
                                    selectedVariantID = variant.id
                                    onVariantChange()
                                }
                            }
                        }
                    }
                    .gearGlassGroup(spacing: 8)
                    .padding(.horizontal, 1)
                }
                .transition(
                    .opacity.combined(with: .move(edge: .top))
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(
                    isSelected
                        ? Palette.panelRaised
                        : Palette.panel
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(
                            isSelected
                                ? Palette.accent.opacity(0.36)
                                : Color.white.opacity(0.055),
                            lineWidth: isSelected ? 1.1 : 0.7
                        )
                }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Bottom-Docked Mechanical Film-Advance / Shutter-Cocking Lever Tray

private struct BottomCockingLeverDock: View {
    let cameraModel: String
    let lensSummary: String
    @Binding var isCocked: Bool
    var onLatchCocked: () -> Void

    @State private var throwProgress: CGFloat = 0.0
    @State private var isDragging: Bool = false
    @State private var lastToothTick: Int = 0
    @State private var dragStartProgress: CGFloat = 0.0

    // Mounting ceremony state.
    @State private var isCompletingMount: Bool = false
    @State private var mountingPhase: Int = 0
    @State private var lensAlignment: CGFloat = 0.0
    @State private var bayonetRotation: Double = 0.0
    @State private var lockPinProgress: CGFloat = 0.0
    @State private var shutterAdvanceProgress: CGFloat = 0.0
    @State private var mountingGlow: CGFloat = 0.0
    @State private var mountingTask: Task<Void, Never>? = nil

    private let latchPoint: CGFloat = 0.88

    private var effectiveProgress: CGFloat {
        (isCocked || isCompletingMount) ? 1.0 : throwProgress
    }

    @ViewBuilder
    private var mountingCeremonyContent: some View {
        if isCompletingMount {
            GearMountingCeremonyVisual(
                cameraModel: cameraModel,
                lensSummary: lensSummary,
                phase: mountingPhase,
                lensAlignment: lensAlignment,
                bayonetRotation: bayonetRotation,
                lockPinProgress: lockPinProgress,
                shutterAdvanceProgress: shutterAdvanceProgress,
                mountingGlow: mountingGlow
            )
            .frame(height: 86)
            .transition(
                .asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                )
            )
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            // Subtle top status row
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isCocked ? Palette.accent : Palette.textDim)
                        .frame(width: 6, height: 6)

                    Text(
                        isCocked
                            ? "RIG COCKED & MOUNTED"
                            : "DRAG LEVER TO COCK RIG"
                    )
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(isCocked ? Palette.text : Palette.textSub)
                }

                Spacer()

                if isCocked {
                    Button {
                        UIImpactFeedbackGenerator(style: .rigid)
                            .impactOccurred(intensity: 0.65)

                        withAnimation(.spring(response: 0.34, dampingFraction: 0.62)) {
                            isCocked = false
                            throwProgress = 0.0
                            mountingPhase = 0
                            isCompletingMount = false
                        }
                    } label: {
                        Text("Release")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .gearGlass()
                    }
                    .buttonStyle(.plain)
                } else if throwProgress > 0.02 {
                    Text("\(Int((throwProgress / latchPoint * 100).rounded()).clamped(to: 1...100))%")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Palette.textSub)
                }
            }
            .padding(.horizontal, 4)

            mountingCeremonyContent

            // Mechanical Advance Lever & Inset Routed Groove
            GeometryReader { geo in
                let w = max(geo.size.width, 1)
                let h = geo.size.height
                let handleW: CGFloat = 96
                let handleH: CGFloat = h - 8
                let maxTravel = max(w - handleW - 8, 1)
                let currentX = 4 + maxTravel * effectiveProgress

                ZStack(alignment: .leading) {
                    // 1. Recessed Top-Plate Housing
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Palette.panel)

                    // 2. Inset Routed Mechanical Groove Channel
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.black.opacity(0.85))
                            .frame(height: 14)

                        // Machined Ratchet Teeth Etchings inside the Routed Groove
                        Canvas { ctx, size in
                            let toothCount = 24
                            let startX: CGFloat = 48
                            let endX = size.width - 28
                            let span = max(endX - startX, 1)
                            let midY = size.height * 0.5

                            for i in 0...toothCount {
                                let frac = CGFloat(i) / CGFloat(toothCount)
                                let tx = startX + frac * span
                                let passed = frac <= effectiveProgress
                                let isMajor = (i % 4 == 0)
                                let tickH: CGFloat = isMajor ? 8 : 5

                                var p = Path()
                                p.move(to: CGPoint(x: tx, y: midY - tickH * 0.5))
                                p.addLine(to: CGPoint(x: tx, y: midY + tickH * 0.5))
                                ctx.stroke(
                                    p,
                                    with: .color(passed ? Palette.accent.opacity(0.65) : Color.white.opacity(isMajor ? 0.22 : 0.10)),
                                    lineWidth: isMajor ? 1.5 : 1.0
                                )
                            }
                        }

                        // Right-End Machined Sear Catch Block
                        HStack {
                            Spacer()
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(isCocked ? Palette.accent : Color.white.opacity(0.22))
                                .frame(width: 6, height: 10)
                                .padding(.trailing, 14)
                        }
                    }
                    .padding(.horizontal, 14)

                    // 3. Sculpted Brushed-Metal Advance Lever Handle with Vertical Thumb-Knurling
                    SculptedMetalAdvanceHandle(
                        isCocked: isCocked || isCompletingMount,
                        isDragging: isDragging
                    )
                    .frame(width: handleW, height: handleH)
                    .offset(x: currentX)
                    .shadow(color: .black.opacity(0.55), radius: 5, x: 0, y: 2)
                    .contentShape(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard !isCocked, !isCompletingMount else {
                                    return
                                }

                                if !isDragging {
                                    isDragging = true
                                    dragStartProgress = throwProgress

                                    UIImpactFeedbackGenerator(style: .rigid)
                                        .impactOccurred(intensity: 0.55)
                                }

                                let raw = dragStartProgress
                                    + (value.translation.width / maxTravel)

                                let clamped = min(max(raw, 0.0), 1.0)

                                // Preserve the existing progressive resistance curve.
                                let resisted = CGFloat(
                                    pow(Double(clamped), 0.90)
                                )

                                throwProgress = resisted

                                // Preserve exactly 20 ratchet increments across the lever throw.
                                let tooth = Int(resisted * 20)

                                if tooth != lastToothTick {
                                    lastToothTick = tooth

                                    let intensity = CGFloat(
                                        0.50 + 0.45 * resisted
                                    )

                                    UIImpactFeedbackGenerator(style: .rigid)
                                        .impactOccurred(intensity: intensity)
                                }

                                // Preserve the existing 0.88 sear latch threshold.
                                if resisted >= latchPoint {
                                    beginMountingCeremony()
                                }
                            }
                            .onEnded { _ in
                                guard !isCocked, !isCompletingMount else {
                                    isDragging = false
                                    return
                                }

                                isDragging = false

                                if throwProgress >= latchPoint {
                                    beginMountingCeremony()
                                } else {
                                    UIImpactFeedbackGenerator(style: .rigid)
                                        .impactOccurred(intensity: 0.6)

                                    withAnimation(
                                        .spring(response: 0.32, dampingFraction: 0.58)
                                    ) {
                                        throwProgress = 0.0
                                    }

                                    dragStartProgress = 0.0
                                    lastToothTick = 0
                                }
                            }
                    )
                    .accessibilityElement()
                    .accessibilityLabel("Mechanical shutter cocking lever")
                    .accessibilityValue(
                        isCocked
                            ? "Rig cocked and mounted"
                            : "\(Int((throwProgress * 100).rounded())) percent"
                    )
                    .accessibilityHint(
                        "Drag the metal lever to the right until it locks to mount and cock the rig."
                    )
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(.default) {
                        guard !isCocked, !isCompletingMount else { return }
                        beginMountingCeremony()
                    }
                }
            }
            .frame(height: 56)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(
            Palette.background.opacity(0.96)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
        .onChange(of: isCocked) { _, newValue in
            if !newValue {
                mountingTask?.cancel()
                mountingTask = nil
                isCompletingMount = false
                mountingPhase = 0
                lensAlignment = 0.0
                bayonetRotation = 0.0
                lockPinProgress = 0.0
                shutterAdvanceProgress = 0.0
                mountingGlow = 0.0

                withAnimation(
                    .spring(response: 0.34, dampingFraction: 0.62)
                ) {
                    throwProgress = 0.0
                }

                lastToothTick = 0
                dragStartProgress = 0.0
            }
        }
        .onDisappear {
            mountingTask?.cancel()
            mountingTask = nil
        }
    }

    private func beginMountingCeremony() {
        guard !isCocked, !isCompletingMount else {
            return
        }

        isDragging = false
        isCompletingMount = true
        mountingPhase = 1

        // Snap the original lever into its fully thrown position.
        withAnimation(.spring(response: 0.24, dampingFraction: 0.68)) {
            throwProgress = 1.0
        }

        // Preserve the original sear-latch impact.
        UIImpactFeedbackGenerator(style: .heavy)
            .impactOccurred(intensity: 1.0)

        mountingTask?.cancel()

        mountingTask = Task { @MainActor in
            // STAGE 1 — ALIGN THE LENS WITH THE BODY MOUNT.
            // Lens slides inward and settles into the camera's mount plane.
            UIImpactFeedbackGenerator(style: .medium)
                .impactOccurred(intensity: 0.65)

            withAnimation(
                .spring(response: 0.42, dampingFraction: 0.72)
            ) {
                lensAlignment = 1.0
                mountingGlow = 0.22
            }

            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }

            // STAGE 2 — ROTATE THE BAYONET RING AND ENGAGE THE LOCK PIN.
            mountingPhase = 2

            withAnimation(
                .spring(response: 0.46, dampingFraction: 0.70)
            ) {
                bayonetRotation = 65.0
            }

            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            UIImpactFeedbackGenerator(style: .rigid)
                .impactOccurred(intensity: 0.9)

            withAnimation(
                .spring(response: 0.24, dampingFraction: 0.66)
            ) {
                lockPinProgress = 1.0
                bayonetRotation = 90.0
                mountingGlow = 0.58
            }

            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled else { return }

            // STAGE 3 — ADVANCE THE SHUTTER AND LOCK THE RIG.
            mountingPhase = 3

            withAnimation(
                .spring(response: 0.36, dampingFraction: 0.66)
            ) {
                shutterAdvanceProgress = 1.0
                mountingGlow = 1.0
            }

            // Three tactile shutter/advance ticks, evenly spaced.
            for _ in 0..<3 {
                try? await Task.sleep(for: .milliseconds(115))
                guard !Task.isCancelled else { return }

                UISelectionFeedbackGenerator()
                    .selectionChanged()
            }

            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }

            UINotificationFeedbackGenerator()
                .notificationOccurred(.success)

            // The lever is already visually at full throw.
            // Publish cocked state only after the entire ceremony finishes.
            isCocked = true
            isCompletingMount = false
            mountingPhase = 0
            mountingTask = nil

            // Preserve the existing store commit callback.
            onLatchCocked()
        }
    }
}

// MARK: - Three-Stage Camera/Lens Mounting Ceremony Visual

private struct GearMountingCeremonyVisual: View {
    let cameraModel: String
    let lensSummary: String
    let phase: Int
    let lensAlignment: CGFloat
    let bayonetRotation: Double
    let lockPinProgress: CGFloat
    let shutterAdvanceProgress: CGFloat
    let mountingGlow: CGFloat

    var body: some View {
        HStack(spacing: 14) {
            // Camera body silhouette.
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.30, green: 0.32, blue: 0.36),
                                Color(red: 0.12, green: 0.13, blue: 0.16)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(0.22),
                                lineWidth: 0.8
                            )
                    }

                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 7, height: 18)

                    Circle()
                        .strokeBorder(
                            Color.white.opacity(0.48),
                            lineWidth: 2
                        )
                        .frame(width: 21, height: 21)
                }
            }
            .frame(width: 70, height: 48)
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 22, height: 5)
                    .offset(y: -3)
            }

            // Mount plane and locking ring.
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.9))
                    .frame(width: 48, height: 48)

                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.8),
                                Color.white.opacity(0.16),
                                Color.white.opacity(0.56)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 4
                    )
                    .frame(width: 43, height: 43)
                    .rotationEffect(.degrees(bayonetRotation))

                Circle()
                    .trim(from: 0.0, to: lockPinProgress)
                    .stroke(
                        Palette.accent,
                        style: StrokeStyle(
                            lineWidth: 3,
                            lineCap: .round
                        )
                    )
                    .frame(width: 34, height: 34)
                    .rotationEffect(.degrees(-90))

                // Five rotating shutter leaves visibly advance during Stage 3.
                ForEach(0..<5, id: \.self) { blade in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.65),
                                    Color(red: 0.20, green: 0.22, blue: 0.26)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 4, height: 17)
                        .offset(y: -7)
                        .rotationEffect(
                            .degrees(
                                Double(blade) * 72
                                + Double(shutterAdvanceProgress) * 36
                            )
                        )
                        .opacity(shutterAdvanceProgress * 0.85)
                }

                Circle()
                    .fill(
                        mountingGlow > 0.5
                            ? Palette.good
                            : Palette.accent
                    )
                    .frame(width: 5, height: 5)
                    .offset(y: -19)
                    .rotationEffect(.degrees(bayonetRotation))
            }
            .shadow(
                color: Palette.accent.opacity(mountingGlow * 0.36),
                radius: 8
            )

            // Lens barrel slides toward the body and seats into the mount.
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.36, green: 0.38, blue: 0.42),
                                Color(red: 0.12, green: 0.13, blue: 0.16),
                                Color(red: 0.28, green: 0.30, blue: 0.34)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(0.22),
                                lineWidth: 0.8
                            )
                    }

                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.black.opacity(0.65))
                            .frame(width: 3, height: 31)
                            .overlay {
                                RoundedRectangle(cornerRadius: 1)
                                    .strokeBorder(
                                        Color.white.opacity(0.16),
                                        lineWidth: 0.5
                                    )
                            }
                    }

                    Circle()
                        .fill(Color.black)
                        .frame(width: 23, height: 23)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    Color.white.opacity(0.42),
                                    lineWidth: 2
                                )
                        }
                        .overlay {
                            Circle()
                                .fill(Color(red: 0.04, green: 0.05, blue: 0.07))
                                .frame(width: 13, height: 13)
                        }
                }
                .padding(.horizontal, 5)
            }
            .frame(width: 70, height: 42)
            .offset(x: (1.0 - lensAlignment) * 24)
            .rotation3DEffect(
                .degrees((1.0 - lensAlignment) * -7),
                axis: (x: 0, y: 1, z: 0)
            )
            .scaleEffect(0.94 + lensAlignment * 0.06)
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 5) {
                Circle()
                    .fill(phase == 3 ? Palette.good : Palette.accent)
                    .frame(width: 5, height: 5)

                Text(stageTitle)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(
                        phase == 3 ? Palette.good : Palette.textSub
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .offset(y: 11)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Camera and lens mounting ceremony")
        .accessibilityValue(stageTitle)
    }

    private var stageTitle: String {
        switch phase {
        case 1:
            return "ALIGNING \(cameraModel.uppercased()) · \(lensSummary.uppercased())"
        case 2:
            return "BAYONET ROTATION · LOCK PIN ENGAGING"
        case 3:
            return "SHUTTER ADVANCED · RIG COCKED"
        default:
            return "MOUNTING"
        }
    }
}

private struct SculptedMetalAdvanceHandle: View {
    let isCocked: Bool
    let isDragging: Bool

    var body: some View {
        ZStack {
            // Brushed Titanium/Steel Lever Body
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.32, green: 0.34, blue: 0.38),
                            Color(red: 0.20, green: 0.22, blue: 0.25),
                            Color(red: 0.27, green: 0.29, blue: 0.33)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    isCocked ? Palette.accent.opacity(0.85) : Color.white.opacity(0.32),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.0
                        )
                )

            HStack(spacing: 10) {
                // Left Recessed Pivot Boss Cap
                Circle()
                    .fill(Color(red: 0.14, green: 0.15, blue: 0.18))
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .overlay(
                        Circle()
                            .fill(isCocked ? Palette.accent : Color.white.opacity(0.35))
                            .frame(width: 5, height: 5)
                    )

                // 7 Precision-Machined Vertical Thumb-Knurling Ribs
                HStack(spacing: 3.5) {
                    ForEach(0..<7, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.38),
                                        Color.black.opacity(0.65)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 2.2, height: 22)
                    }
                }
            }
        }
        .scaleEffect(isDragging ? 1.03 : 1.0)
        .animation(.spring(response: 0.20, dampingFraction: 0.65), value: isDragging)
    }
}

// MARK: - Shared Formatting Helpers

func shutterRangeText(_ first: Double, _ second: Double) -> String {
    let slow = max(first, second)
    let fast = min(first, second)
    return "\(formatShutterStopLabel(slow))–\(formatShutterStopLabel(fast))"
}

private func strippedCameraTitle(_ camera: CameraGearSpec) -> String {
    var name = camera.model.trimmingCharacters(in: .whitespacesAndNewlines)
    if name.lowercased().hasPrefix(camera.brand.lowercased() + " ") {
        name = String(name.dropFirst(camera.brand.count + 1))
    }
    return name.isEmpty ? camera.model : name
}

private func cleanLensDisplayName(_ rawModel: String, brand: String) -> String {
    var s = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
    if let slashIdx = s.range(of: " / ") {
        s = String(s[s.startIndex..<slashIdx.lowerBound])
    }
    let prefixes = [brand + " ", "Carl Zeiss ", "Leica ", "Nikkor ", "Canon ", "Olympus Zuiko ", "Minolta ", "SMC Pentax-M ", "SMC Pentax ", "Super-Takumar ", "Voigtländer "]
    for p in prefixes {
        if s.lowercased().hasPrefix(p.lowercased()) {
            s = String(s.dropFirst(p.count))
            break
        }
    }
    s = s.replacingOccurrences(of: " (AI / AI-S)", with: "")
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func shortFocalBadge(_ entry: PrewarmedLensEntry) -> String {
    let f = String(formatApertureStopLabel(entry.lens.minAperture).dropFirst(2))
    if entry.focalLengthMm > 0 && entry.focalLengthMm < 9999 {
        let mm = entry.focalLengthMm == entry.focalLengthMm.rounded()
            ? "\(Int(entry.focalLengthMm))"
            : String(format: "%.1f", entry.focalLengthMm)
        return "\(mm)mm f/\(f)"
    }
    return cleanLensDisplayName(entry.lens.model, brand: entry.lens.brand)
}
