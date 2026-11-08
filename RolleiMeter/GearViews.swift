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
                            Palette.text.opacity(0.14),
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
    @State private var stagedCameraVariant: String = ""

    /// Exact camera model recorded in the gear profile and photo metadata.
    /// Catalog entries like "Rollei 35 S / 35 SE" are split so only the chosen variant is written.
    private var stagedCameraName: String {
        let variants = cameraModelVariants(stagedCamera.model)
        if variants.count > 1 {
            return variants.contains(stagedCameraVariant) ? stagedCameraVariant : variants[0]
        }
        return stagedCamera.model
    }
    @State private var isCocked: Bool = true
    @State private var leverThrowProgress: CGFloat = 0.0
    @State private var selectionPulseTrigger: Int = 0
    @State private var didInitialize: Bool = false
    @State private var showRemoveConfirm: Bool = false

    private var selectedVariantLabel: String {
        guard let entry = stagedLensEntry else { return "" }
        let variant = entry.variants.first { $0.id == stagedVariantID } ?? entry.variants.first
        return variant?.badge ?? ""
    }

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
                cameraName: stagedCameraName,
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
                cameraName: stagedCameraName,
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
                    cameraName: stagedCameraName,
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
                cameraName: stagedCameraName,
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
                    .padding(.horizontal, 16)
                }

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
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Palette.background.ignoresSafeArea())
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
                            Palette.text.opacity(0.07),
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
                                    : Palette.text.opacity(0.08)
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

                    let camVariants = cameraModelVariants(camera.model)
                    if isSelected && camVariants.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(camVariants, id: \.self) { name in
                                    GearGlassChip(
                                        title: name,
                                        isSelected: stagedCameraName == name,
                                        minHeight: 44
                                    ) {
                                        Haptics.tap()
                                        withAnimation(.snappy(duration: 0.2)) {
                                            stagedCameraVariant = name
                                            isCocked = true
                                            store.activeGear = resolvedPreviewProfile
                                            if !camera.isFixed {
                                                step = .lens
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                        .gearGlassGroup(spacing: 8)
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

                            selectionPulseTrigger += 1
                            isCocked = true
                            store.activeGear = resolvedPreviewProfile
                        }
                    } onVariantChange: {
                        selectionPulseTrigger += 1
                        isCocked = true
                        store.activeGear = resolvedPreviewProfile
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

        isCocked = true
        store.activeGear = resolvedPreviewProfile
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

        isCocked = true
        store.activeGear = resolvedPreviewProfile
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

        isCocked = true
        store.activeGear = resolvedPreviewProfile
    }

    private func selectCameraBody(_ cam: CameraGearSpec) {
        stagedCamera = cam
        stagedCameraVariant = cameraModelVariants(cam.model).first ?? ""

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

            if cameraModelVariants(cam.model).count <= 1 {
                step = .lens
            }
        }

        selectionPulseTrigger += 1
        isCocked = true
        store.activeGear = resolvedPreviewProfile
    }

    private func syncStagedWithActiveGearIfNeeded() {
        guard !didInitialize else { return }
        didInitialize = true
        let active = store.activeGear
        if let matchCam = allCameras.first(where: { $0.id == active.cameraId }) {
            stagedCamera = matchCam
            if cameraModelVariants(matchCam.model).contains(active.cameraName) {
                stagedCameraVariant = active.cameraName
            } else {
                stagedCameraVariant = cameraModelVariants(matchCam.model).first ?? ""
            }
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
            if isCocked { leverThrowProgress = 1.0 }
            return
        }

        if active.lensId.isEmpty {
            mountSetup = .bodyOnly
            isCocked = isStagedComboCurrentlyMounted
            if isCocked { leverThrowProgress = 1.0 }
            return
        }

        for entry in allLenses {
            if entry.lens.id == active.lensId {
                stagedLensEntry = entry
                stagedVariantID = entry.variants.first?.id ?? ""
                mountSetup = .matched
                isCocked = isStagedComboCurrentlyMounted
                if isCocked { leverThrowProgress = 1.0 }
                return
            }
            if let v = entry.variants.first(where: { $0.spec.id == active.lensId }) {
                stagedLensEntry = entry
                stagedVariantID = v.id
                mountSetup = .matched
                isCocked = isStagedComboCurrentlyMounted
                if isCocked { leverThrowProgress = 1.0 }
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
        if isCocked { leverThrowProgress = 1.0 }
    }

    private func commitStagedGear() {
        store.activeGear = resolvedPreviewProfile
        isCocked = true
        leverThrowProgress = 1.0
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.85) {
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
                                : Palette.text.opacity(0.07)
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
                                    : Palette.text.opacity(0.055),
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
                                    : Palette.text.opacity(0.07)
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
                                : Palette.text.opacity(0.055),
                            lineWidth: isSelected ? 1.1 : 0.7
                        )
                }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Clockwork Brass Ratchet Escapement Canvas

struct BrassRatchetEscapementCanvas: View {
    let throwProgress: CGFloat
    let isCocked: Bool

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let midY = size.height * 0.5
            let toothCount = 24
            let usableW = w - 28.0

            // 1. Recessed Dark Escapement Slot
            let slotRect = CGRect(x: 8, y: midY - 7, width: w - 16, height: 14)
            ctx.fill(Path(roundedRect: slotRect, cornerRadius: 5), with: .color(Color.black.opacity(0.88)))

            // 2. Sawtooth Brass Ratchet Rack & Illuminated Progress Teeth
            for i in 0..<toothCount {
                let frac = CGFloat(i) / CGFloat(toothCount - 1)
                let tx = 14.0 + frac * usableW
                let isPassed = frac <= throwProgress || isCocked
                let isMajor = (i % 4 == 0)
                let th: CGFloat = isMajor ? 8.5 : 5.5

                var toothPath = Path()
                toothPath.move(to: CGPoint(x: tx - 1.8, y: midY + th * 0.5))
                toothPath.addLine(to: CGPoint(x: tx + 1.2, y: midY - th * 0.5))
                toothPath.addLine(to: CGPoint(x: tx + 1.8, y: midY + th * 0.5))
                toothPath.closeSubpath()

                let toothColor: Color = isCocked
                    ? Palette.good.opacity(0.85)
                    : (isPassed ? Palette.accent : Color(red: 0.83, green: 0.68, blue: 0.28).opacity(0.38))
                ctx.fill(toothPath, with: .color(toothColor))
            }

            // 3. Milled Right-Hand Sear Catch Block
            let searRect = CGRect(x: w - 16, y: midY - 5.5, width: 6.5, height: 11.0)
            ctx.fill(
                Path(roundedRect: searRect, cornerRadius: 1.5),
                with: .color(isCocked ? Palette.good : (throwProgress >= 0.88 ? Palette.accent : Palette.text.opacity(0.55)))
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Bottom-Docked Mechanical Film-Advance / Shutter-Cocking Lever Tray

struct BottomCockingLeverDock: View {
    let cameraModel: String
    let lensSummary: String
    @Binding var isCocked: Bool
    var throwProgressBinding: Binding<CGFloat>? = nil
    var onLatchCocked: () -> Void

    init(
        cameraModel: String,
        lensSummary: String,
        isCocked: Binding<Bool>,
        throwProgress: Binding<CGFloat>? = nil,
        onLatchCocked: @escaping () -> Void
    ) {
        self.cameraModel = cameraModel
        self.lensSummary = lensSummary
        self._isCocked = isCocked
        self.throwProgressBinding = throwProgress
        self.onLatchCocked = onLatchCocked
    }

    @State private var throwProgress: CGFloat = 0.0
    @State private var isDragging: Bool = false
    @State private var lastToothTick: Int = 0
    @State private var dragStartProgress: CGFloat = 0.0

    private let latchPoint: CGFloat = 0.88

    private var effectiveProgress: CGFloat {
        isCocked ? 1.0 : throwProgress
    }

    var body: some View {
        VStack(spacing: 10) {
            // Subtle top status row
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isCocked ? Palette.good : Palette.textDim)
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
                        }
                        throwProgressBinding?.wrappedValue = 0.0
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

            // Mechanical Advance Lever & Inset Routed Groove
            GeometryReader { geo in
                let w = max(geo.size.width, 1)
                let h = geo.size.height
                let handleW: CGFloat = 96
                let handleH: CGFloat = h - 8
                let maxTravel = max(w - handleW - 8, 1)
                let currentHandleX = 4 + maxTravel * effectiveProgress

                ZStack(alignment: .leading) {
                    // 1. Recessed Top-Plate Housing
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Palette.panel)

                    // 2. Inset Routed Mechanical Groove Channel with Clockwork Escapement
                    BrassRatchetEscapementCanvas(
                        throwProgress: effectiveProgress,
                        isCocked: isCocked
                    )
                    .frame(height: 18)
                    .padding(.horizontal, 14)

                    // 3. Sculpted Brushed-Metal Advance Lever Handle with Swept 3D Thumb-Lever Arc
                    SculptedMetalAdvanceHandle(
                        isCocked: isCocked,
                        isDragging: isDragging,
                        isLatched: effectiveProgress >= latchPoint
                    )
                    .frame(width: handleW, height: handleH)
                    .rotationEffect(.degrees(Double(-6.0 + 12.0 * effectiveProgress)), anchor: .leading)
                    .offset(
                        x: currentHandleX,
                        y: -3.2 * sin(effectiveProgress * .pi)
                    )
                    .shadow(color: .black.opacity(0.55), radius: 5, x: 0, y: 2)
                    .contentShape(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard !isCocked else { return }

                                if !isDragging {
                                    isDragging = true
                                    dragStartProgress = throwProgress

                                    UIImpactFeedbackGenerator(style: .rigid)
                                        .impactOccurred(intensity: 0.55)
                                }

                                let raw = dragStartProgress + (value.translation.width / maxTravel)
                                let clamped = min(max(raw, 0.0), 1.0)
                                let resisted = CGFloat(pow(Double(clamped), 0.90))

                                throwProgress = resisted
                                throwProgressBinding?.wrappedValue = resisted

                                let tooth = Int(resisted * 20)
                                if tooth != lastToothTick {
                                    lastToothTick = tooth
                                    let intensity = CGFloat(0.50 + 0.45 * resisted)
                                    UIImpactFeedbackGenerator(style: .rigid)
                                        .impactOccurred(intensity: intensity)
                                }
                            }
                            .onEnded { _ in
                                guard !isCocked else {
                                    isDragging = false
                                    return
                                }

                                isDragging = false

                                if throwProgress >= latchPoint {
                                    UIImpactFeedbackGenerator(style: .heavy)
                                        .impactOccurred(intensity: 1.0)
                                    withAnimation(.spring(response: 0.24, dampingFraction: 0.68)) {
                                        throwProgress = 1.0
                                    }
                                    throwProgressBinding?.wrappedValue = 1.0
                                    isCocked = true
                                    onLatchCocked()
                                } else {
                                    UIImpactFeedbackGenerator(style: .rigid)
                                        .impactOccurred(intensity: 0.6)

                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.58)) {
                                        throwProgress = 0.0
                                    }
                                    throwProgressBinding?.wrappedValue = 0.0
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
                        guard !isCocked else { return }
                        UIImpactFeedbackGenerator(style: .heavy)
                            .impactOccurred(intensity: 1.0)
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.68)) {
                            throwProgress = 1.0
                        }
                        throwProgressBinding?.wrappedValue = 1.0
                        isCocked = true
                        onLatchCocked()
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
                        .fill(Palette.text.opacity(0.08))
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
        .onChange(of: isCocked) { _, newValue in
            if !newValue {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.62)) {
                    throwProgress = 0.0
                }
                throwProgressBinding?.wrappedValue = 0.0
                lastToothTick = 0
                dragStartProgress = 0.0
            } else {
                throwProgress = 1.0
                throwProgressBinding?.wrappedValue = 1.0
            }
        }
    }
}

// MARK: - Co-Axial Camera/Lens Mounting Ceremony Visual & Optical Bench

struct GearMountingCeremonyVisual: View {
    let cameraBrand: String
    let cameraName: String
    let lensBrand: String
    let lensName: String
    let mount: String
    let isFixed: Bool
    let isBodyOnly: Bool
    let isCocked: Bool
    var minAperture: Double = 2.0
    var maxAperture: Double = 16.0
    var maxShutter: Double = 0.001
    var isAdapter: Bool = false
    var variantLabel: String = ""
    var leverThrowProgress: CGFloat = 0.0  // Coupled live to BottomCockingLeverDock (0.0 -> 1.0)
    var selectionPulseTrigger: Int = 0     // Increments on lens/variant tap to flutter iris blades

    // Backward-compatibility initializer for legacy call sites
    init(
        cameraBrand: String = "Rollei",
        cameraName: String = "",
        lensBrand: String = "",
        lensName: String = "",
        mount: String = "35mm",
        isFixed: Bool = false,
        isBodyOnly: Bool = false,
        isCocked: Bool = false,
        minAperture: Double = 2.0,
        maxAperture: Double = 16.0,
        maxShutter: Double = 0.001,
        isAdapter: Bool = false,
        variantLabel: String = "",
        leverThrowProgress: CGFloat = 0.0,
        selectionPulseTrigger: Int = 0,
        cameraModel: String? = nil,
        lensSummary: String? = nil,
        phase: Int = 0,
        lensAlignment: CGFloat = 0.0,
        bayonetRotation: Double = 0.0,
        lockPinProgress: CGFloat = 0.0,
        shutterAdvanceProgress: CGFloat = 0.0,
        mountingGlow: CGFloat = 0.0
    ) {
        self.cameraBrand = cameraBrand
        self.cameraName = cameraModel ?? cameraName
        self.lensBrand = lensBrand
        self.lensName = lensSummary ?? lensName
        self.mount = mount
        self.isFixed = isFixed
        self.isBodyOnly = isBodyOnly
        self.isCocked = isCocked
        self.minAperture = minAperture
        self.maxAperture = maxAperture
        self.maxShutter = maxShutter
        self.isAdapter = isAdapter
        self.variantLabel = variantLabel
        self.leverThrowProgress = leverThrowProgress
        self.selectionPulseTrigger = selectionPulseTrigger
    }

    @State private var stage: Int = 0
    @State private var axialSeatProgress: CGFloat = 0.0     // 0.0 (hover offset) -> 1.0 (co-axial seated)
    @State private var bayonetTwistDegrees: Double = 0.0    // 0 -> 65 -> 90 deg (or -90 for Nikon F)
    @State private var lockPinProgress: CGFloat = 0.0       // 0.0 -> 1.0 bayonet pin snap
    @State private var irisStopDownProgress: CGFloat = 0.0  // 0.0 (wide open) -> 1.0 (f/16 stop-down sweep)
    @State private var mirrorFlipProgress: CGFloat = 0.0    // 0.0 -> 1.0 SLR mirror flip during test-fire
    @State private var shutterFlashProgress: CGFloat = 0.0  // 0.0 -> 1.0 curtain/leaf flash
    @State private var coatingFlareProgress: CGFloat = 0.0  // 0.0 -> 1.0 dichroic coating ring ripple
    @State private var ceremonyGlow: CGFloat = 0.0
    @State private var ceremonyTask: Task<Void, Never>? = nil

    // Authentic mount rotation direction (Nikon F twists counter-clockwise; M42/L39 threads spin 360+)
    private var mountDirectionMultiplier: Double {
        let m = mount.lowercased()
        if m.contains("nikon f") { return -1.0 }
        if m.contains("m42") || m.contains("ltm") || m.contains("m39") { return 3.0 }
        return 1.0
    }

    // Combine live lever drag (0.0 -> 0.88) with post-release ceremony lock
    private var effectiveSeatProgress: CGFloat {
        if isCocked || stage > 0 { return max(axialSeatProgress, 1.0) }
        return min(max(leverThrowProgress / 0.32, 0.0), 1.0)
    }

    private var effectiveBayonetDegrees: Double {
        if isCocked && stage == 0 { return 90.0 * mountDirectionMultiplier }
        if stage > 0 { return bayonetTwistDegrees * mountDirectionMultiplier }
        let twistNorm = min(max((leverThrowProgress - 0.30) / 0.58, 0.0), 1.0)
        return (-28.0 + Double(twistNorm) * 93.0) * mountDirectionMultiplier
    }

    private var effectiveLockPin: CGFloat {
        if isCocked || stage >= 2 { return 1.0 }
        return leverThrowProgress >= 0.88 ? 1.0 : 0.0
    }

    private var statusTitle: String {
        if isCocked && stage == 0 {
            return "OPTICAL RIG LOCKED • SHUTTER COCKED"
        }
        switch stage {
        case 1:
            return "BAYONET PIN ENGAGED • 90° REGISTER LOCK"
        case 2:
            return "STOP-DOWN COUPLER • CALIBRATING IRIS DIAPHRAGM"
        case 3:
            return "DRY TEST-FIRE • SHUTTER & MIRROR ACTUATION"
        case 4:
            return "RIG COCKED & CLAMPED • READY TO METER"
        default:
            if leverThrowProgress >= 0.88 {
                return "SEAR PIN ENGAGED • RELEASE TO LOCK & TEST-FIRE"
            } else if leverThrowProgress > 0.30 {
                return "TWISTING BAYONET LUGS INTO FLANGE…"
            } else if leverThrowProgress > 0.02 {
                return "ALIGNING RED MOUNT DOTS CO-AXIALLY…"
            } else {
                return isFixed
                    ? "PULL LEVER TO EXTEND BARREL & COCK SHUTTER"
                    : "PULL COCKING LEVER TO SEAT & LOCK OPTICS"
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Top Instrument Telemetry Bar
            HStack {
                Circle()
                    .fill(isCocked ? Palette.good : (leverThrowProgress >= 0.88 ? Palette.accent : Palette.textDim))
                    .frame(width: 7, height: 7)

                Text(statusTitle)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(isCocked ? Palette.good : (leverThrowProgress > 0.02 ? Palette.accent : Palette.textSub))
                    .lineLimit(1)

                Spacer()

                Text(mount.uppercased())
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.textDim)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Palette.text.opacity(0.06), in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            // Co-Axial Optical Bench Viewport
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let benchDiameter = min(h * 0.92, 112.0)
                let hoverOffset: CGFloat = isBodyOnly ? 0.0 : (1.0 - effectiveSeatProgress) * 52.0
                let lensScale: CGFloat = 0.92 + (0.08 * effectiveSeatProgress)
                let tiltDegrees: Double = Double(1.0 - effectiveSeatProgress) * -14.0

                ZStack {
                    // Subtle Optical Axis Laser Crosshair Guide
                    Path { p in
                        p.move(to: CGPoint(x: 24, y: h * 0.5))
                        p.addLine(to: CGPoint(x: w - 24, y: h * 0.5))
                    }
                    .stroke(
                        (isCocked ? Palette.good : Palette.accent).opacity(0.18),
                        style: StrokeStyle(lineWidth: 1.0, dash: [4, 4])
                    )

                    // BASE LAYER: Co-Axial Camera Mount Throat
                    CoAxialCameraThroatCanvas(
                        cameraBrand: cameraBrand,
                        cameraModel: cameraName,
                        mount: mount,
                        isFixed: isFixed,
                        maxShutter: maxShutter,
                        isAdapter: isAdapter,
                        lockPinProgress: effectiveLockPin,
                        mirrorFlipProgress: mirrorFlipProgress,
                        shutterFlashProgress: shutterFlashProgress
                    )
                    .frame(width: benchDiameter * 1.38, height: benchDiameter * 1.05)
                    .offset(x: isBodyOnly ? 0 : -(1.0 - effectiveSeatProgress) * 28.0)

                    // CO-AXIAL FLOATING / SEATING LAYER: Procedural Multi-Coated Lens Barrel
                    if !isBodyOnly {
                        ProceduralLensBarrelCanvas(
                            lensBrand: lensBrand,
                            lensName: lensName,
                            mount: mount,
                            minAperture: minAperture,
                            maxAperture: maxAperture,
                            variantLabel: variantLabel,
                            bayonetAngle: effectiveBayonetDegrees,
                            irisStopDownProgress: irisStopDownProgress,
                            coatingFlareProgress: coatingFlareProgress
                        )
                        .frame(width: benchDiameter, height: benchDiameter)
                        .scaleEffect(lensScale)
                        .rotation3DEffect(
                            .degrees(tiltDegrees),
                            axis: (x: 0.0, y: 1.0, z: 0.0),
                            perspective: 0.55
                        )
                        .offset(x: hoverOffset)
                        .shadow(color: Color.black.opacity(0.65), radius: 8 * (1.0 - effectiveSeatProgress) + 2, x: 4 * (1.0 - effectiveSeatProgress), y: 2)
                    }

                    // Circular Bayonet Lock-Pin Trim Ring
                    Circle()
                        .trim(from: 0.0, to: isCocked ? 1.0 : max(effectiveSeatProgress * 0.85, 0.0))
                        .stroke(
                            isCocked ? Palette.good : Palette.accent,
                            style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: benchDiameter * 0.96, height: benchDiameter * 0.96)
                        .opacity(effectiveSeatProgress > 0.15 ? 0.75 : 0.0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 118)

            // Bottom Optical Telemetry Readout Bar
            HStack(spacing: 6) {
                Text(cameraName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)

                Text("•")
                    .foregroundStyle(Palette.textDim)

                Text(isBodyOnly ? "Body Only (Unclamped)" : lensName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.accent)
                    .lineLimit(1)

                Spacer()

                if !isBodyOnly {
                    Text(String(format: "f/%.1f–f/%.0f", minAperture, maxAperture).replacingOccurrences(of: ".0", with: ""))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Palette.textSub)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.05, green: 0.055, blue: 0.068))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isCocked
                        ? Palette.good.opacity(0.45 + 0.45 * Double(ceremonyGlow))
                        : (leverThrowProgress > 0.05 ? Palette.accent.opacity(0.45) : Palette.text.opacity(0.08)),
                    lineWidth: isCocked ? 1.5 : 1.0
                )
        )
        .onChange(of: selectionPulseTrigger) { _, _ in
            // Quick mechanical iris flutter whenever user taps a lens or sub-variant chip
            withAnimation(.spring(response: 0.18, dampingFraction: 0.52)) {
                irisStopDownProgress = 0.65
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 140_000_000)
                withAnimation(.spring(response: 0.28, dampingFraction: 0.58)) {
                    irisStopDownProgress = 0.0
                }
            }
        }
        .onChange(of: isCocked) { _, newValue in
            if newValue {
                runFourStageOpticalCeremony()
            } else {
                ceremonyTask?.cancel()
                ceremonyTask = nil
                withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) {
                    stage = 0
                    axialSeatProgress = 0.0
                    bayonetTwistDegrees = 0.0
                    lockPinProgress = 0.0
                    irisStopDownProgress = 0.0
                    mirrorFlipProgress = 0.0
                    shutterFlashProgress = 0.0
                    coatingFlareProgress = 0.0
                    ceremonyGlow = 0.0
                }
            }
        }
        .onDisappear {
            ceremonyTask?.cancel()
            ceremonyTask = nil
        }
    }

    private func runFourStageOpticalCeremony() {
        ceremonyTask?.cancel()
        ceremonyTask = Task { @MainActor in
            // =========================================================================
            // STAGE 1 (t = 0.00s - 0.28s): FINAL 90° BAYONET LOCK-PIN SNAP & FLANGE SEAT
            // =========================================================================
            stage = 1
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.95)
            withAnimation(.spring(response: 0.24, dampingFraction: 0.64)) {
                axialSeatProgress = 1.0
                bayonetTwistDegrees = 90.0
                lockPinProgress = 1.0
            }

            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }

            // =========================================================================
            // STAGE 2 (t = 0.28s - 0.78s): STOP-DOWN COUPLER IRIS CALIBRATION SWEEP
            // =========================================================================
            stage = 2
            withAnimation(.spring(response: 0.22, dampingFraction: 0.70)) {
                irisStopDownProgress = 1.0 // Constricts blades to f/16
            }
            for _ in 0..<3 {
                guard !Task.isCancelled else { return }
                UISelectionFeedbackGenerator().selectionChanged()
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
            withAnimation(.spring(response: 0.24, dampingFraction: 0.58)) {
                irisStopDownProgress = 0.0 // Snaps wide-open for viewing
            }

            try? await Task.sleep(nanoseconds: 240_000_000)
            guard !Task.isCancelled else { return }

            // =========================================================================
            // STAGE 3 (t = 0.78s - 1.25s): DRY SHUTTER TEST-FIRE & COATING FLARE RIPPLE
            // =========================================================================
            stage = 3
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1.0)
            withAnimation(.easeOut(duration: 0.09)) {
                mirrorFlipProgress = 1.0
            }
            withAnimation(.linear(duration: 0.16)) {
                shutterFlashProgress = 1.0
            }
            withAnimation(.easeOut(duration: 0.42)) {
                coatingFlareProgress = 1.0
            }

            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.65) // Mirror return damper bounce
            withAnimation(.spring(response: 0.22, dampingFraction: 0.62)) {
                mirrorFlipProgress = 0.0
                shutterFlashProgress = 0.0
            }

            try? await Task.sleep(nanoseconds: 310_000_000)
            guard !Task.isCancelled else { return }

            // =========================================================================
            // STAGE 4 (t = 1.25s - 1.65s): RIG LOCKED & DIAL CLAMPING CONFIRMATION
            // =========================================================================
            stage = 4
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.36, dampingFraction: 0.62)) {
                ceremonyGlow = 1.0
            }

            try? await Task.sleep(nanoseconds: 420_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.35)) {
                coatingFlareProgress = 0.0
                ceremonyGlow = 0.35
                stage = 0
            }
        }
    }
}

// MARK: - Sculpted Brushed-Metal Advance Lever Handle

struct SculptedMetalAdvanceHandle: View {
    let isCocked: Bool
    var isDragging: Bool = false
    var isLatched: Bool = false

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
                                    (isCocked || isLatched) ? Palette.accent.opacity(0.85) : Palette.text.opacity(0.32),
                                    Palette.text.opacity(0.08)
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
                            .strokeBorder(Palette.text.opacity(0.18), lineWidth: 1)
                    )
                    .overlay(
                        Circle()
                            .fill((isCocked || isLatched) ? Palette.accent : Palette.text.opacity(0.35))
                            .frame(width: 5, height: 5)
                    )

                // 7 Precision-Machined Vertical Thumb-Knurling Ribs
                HStack(spacing: 3.5) {
                    ForEach(0..<7, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Palette.text.opacity(0.38),
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


// MARK: - Camera model variants

/// Splits catalog models such as "Rollei 35 S / 35 SE" into the exact models
/// ["Rollei 35 S", "Rollei 35 SE"], so metadata records the specific body.
/// Trailing parentheticals like "(TLR)" are dropped from the variant names.
func cameraModelVariants(_ model: String) -> [String] {
    var base = model.trimmingCharacters(in: .whitespacesAndNewlines)
    if let paren = base.range(of: " (") { base = String(base[..<paren.lowerBound]) }
    let parts = base.components(separatedBy: " / ")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    guard parts.count > 1 else { return [model] }

    let firstTokens = parts[0].split(separator: " ").map(String.init)
    guard let brand = firstTokens.first else { return [model] }
    var result = [parts[0]]
    for part in parts.dropFirst() {
        if part.lowercased().hasPrefix(brand.lowercased() + " ") {
            result.append(part)
            continue
        }
        let partTokens = part.split(separator: " ").map(String.init)
        var prefix = Array(firstTokens.dropLast())
        // Drop any overlap between the end of the prefix and the start of this variant.
        var overlap = min(prefix.count, partTokens.count)
        while overlap > 0 {
            if Array(prefix.suffix(overlap)).map({ $0.lowercased() }) == Array(partTokens.prefix(overlap)).map({ $0.lowercased() }) {
                prefix.removeLast(overlap)
                break
            }
            overlap -= 1
        }
        if prefix.isEmpty { prefix = [brand] }
        result.append((prefix + partTokens).joined(separator: " "))
    }
    var seen = Set<String>()
    return result.filter { seen.insert($0).inserted }
}
