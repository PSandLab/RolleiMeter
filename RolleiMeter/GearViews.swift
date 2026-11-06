import Foundation
import SwiftUI
import UIKit

// MARK: - Camera & Optics Studio (Clean Hierarchy, Single-Column List & Bottom-Docked Cocking Lever)

struct CameraLensView: View {
    @ObservedObject var store: FilmLogStore
    var onFinish: () -> Void = {}

    private enum SelectionStep: Int {
        case body = 1
        case lens = 2
    }

    private enum MountSetup: String, CaseIterable {
        case matched = "Native"
        case adapter = "Adapted"
        case bodyOnly = "Body Only"
    }

    @State private var step: SelectionStep = .body
    @State private var selectedBrand: String = "Rollei"
    @State private var showAllBodiesForBrand: Bool = false
    @State private var focalFilter: FocalLengthCategory = .all
    @State private var mountSetup: MountSetup = .matched
    @State private var searchText: String = ""

    @State private var stagedCamera: CameraGearSpec = GearCatalogCache.loadBundledCatalog().cameras[0]
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
        let active = store.activeGear
        let preview = resolvedPreviewProfile
        return active.cameraId == preview.cameraId && active.lensId == preview.lensId
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
        if stagedCamera.isFixed || mountSetup == .adapter {
            mountPool = allLenses
        } else {
            let native = allLenses.filter { $0.lens.mount.caseInsensitiveCompare(stagedCamera.mount) == .orderedSame }
            mountPool = native.isEmpty ? allLenses : native
        }

        if !q.isEmpty {
            return mountPool
                .map { ($0, fuzzyMatchScore(query: q, target: "\($0.lens.brand) \($0.lens.model) \($0.lens.mount)")) }
                .filter { $0.1 > 0 }
                .sorted { $0.1 > $1.1 }
                .map { $0.0 }
        }

        if focalFilter == .all {
            return mountPool
        }
        return mountPool.filter { matchesFocalCategory(model: $0.lens.model, category: focalFilter) }
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
                        presetKinds: (step == .lens && !stagedCamera.isFixed) ? [.lens] : [.fixedLens, .body],
                        presetBrand: selectedBrand == "Custom" || selectedBrand == "Other" ? "" : selectedBrand
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

    // MARK: - 1. Top Active Rig Summary & 2-Step Segmented Switcher

    private var activeRigHeaderCard: some View {
        let preview = resolvedPreviewProfile

        return VStack(spacing: 14) {
            HStack(spacing: 14) {
                CameraBrandLogo(brand: stagedCamera.brand, size: 46)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(stagedCamera.model)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)

                        Circle()
                            .fill(isCocked ? Palette.accent : Palette.textDim)
                            .frame(width: 7, height: 7)
                    }

                    Text(preview.hasLens
                         ? cleanLensDisplayName(preview.lensName, brand: stagedCamera.brand)
                         : "\(formatMountBadge(stagedCamera.mount)) Body Only")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.textSub)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(shutterRangeText(stagedCamera.minShutter, stagedCamera.maxShutter))
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Palette.text)

                    Text(formatApertureRange(preview.minAperture, preview.maxAperture))
                        .font(.footnote.weight(.medium).monospacedDigit())
                        .foregroundStyle(Palette.textSub)
                }
            }

            // Integrated 44pt 2-Step Segmented Switcher (Only shown for interchangeable-lens bodies)
            if !stagedCamera.isFixed {
                HStack(spacing: 6) {
                    stepTabButton(
                        stepNumber: "1",
                        title: "Body · \(strippedCameraTitle(stagedCamera))",
                        isActive: step == .body
                    ) {
                        Haptics.tap()
                        withAnimation(.snappy(duration: 0.22)) {
                            step = .body
                        }
                    }

                    stepTabButton(
                        stepNumber: "2",
                        title: "Lens · \(stepTwoShortLabel)",
                        isActive: step == .lens
                    ) {
                        Haptics.tap()
                        withAnimation(.snappy(duration: 0.22)) {
                            step = .lens
                        }
                    }
                }
                .padding(4)
                .background(Palette.background, in: .rect(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .background(Palette.panel, in: .rect(cornerRadius: 16, style: .continuous))
    }

    private func stepTabButton(
        stepNumber: String,
        title: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(stepNumber)
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(isActive ? Palette.background.opacity(0.22) : Color.white.opacity(0.08))
                    )

                Text(title)
                    .font(.subheadline.weight(isActive ? .semibold : .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 38)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isActive ? Palette.text : Color.clear)
            )
            .foregroundStyle(isActive ? Palette.background : Palette.textSub)
        }
        .buttonStyle(.plain)
    }

    private var stepTwoShortLabel: String {
        if mountSetup == .bodyOnly { return "Body Only" }
        if let entry = stagedLensEntry {
            return shortFocalBadge(entry)
        }
        return "Select"
    }

    // MARK: - 2. Single-Tier Filter Strips (44pt Touch Targets, Proper Margins)

    @ViewBuilder
    private var bodyBrandFilterStrip: some View {
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !isSearching {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(brandList, id: \.self) { brand in
                        let active = (selectedBrand == brand)
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.snappy(duration: 0.20)) {
                                selectedBrand = brand
                                showAllBodiesForBrand = false
                            }
                        } label: {
                            Text(brand)
                                .font(.subheadline.weight(active ? .semibold : .medium))
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44)
                                .background(
                                    Capsule()
                                        .fill(active ? Palette.text : Palette.panel)
                                )
                                .foregroundStyle(active ? Palette.background : Palette.textSub)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
        }
    }

    private var lensFocalFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FocalLengthCategory.allCases) { cat in
                    let active = (focalFilter == cat && mountSetup != .bodyOnly)
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.snappy(duration: 0.20)) {
                            if mountSetup == .bodyOnly { mountSetup = .matched }
                            focalFilter = cat
                        }
                    } label: {
                        Text(cat == .all ? "All" : (cat == .zoom ? "Zooms" : "\(cat.label)mm"))
                            .font(.subheadline.weight(active ? .semibold : .medium).monospacedDigit())
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(
                                Capsule()
                                    .fill(active ? Palette.text : Palette.panel)
                            )
                            .foregroundStyle(active ? Palette.background : Palette.textSub)
                    }
                    .buttonStyle(.plain)
                }

                // Inline Mount Setup Pills at the end of the single filter strip (Eliminates stacked filter rows)
                Button {
                    Haptics.tap()
                    withAnimation(.snappy(duration: 0.20)) {
                        mountSetup = (mountSetup == .adapter) ? .matched : .adapter
                    }
                } label: {
                    Text(mountSetup == .adapter ? "✓ All Mounts" : "Adapt Mount")
                        .font(.subheadline.weight(mountSetup == .adapter ? .semibold : .medium))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(
                            Capsule()
                                .fill(mountSetup == .adapter ? Palette.text : Palette.panel)
                        )
                        .foregroundStyle(mountSetup == .adapter ? Palette.background : Palette.textSub)
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.tap()
                    withAnimation(.snappy(duration: 0.20)) {
                        mountSetup = (mountSetup == .bodyOnly) ? .matched : .bodyOnly
                        isCocked = isStagedComboCurrentlyMounted
                    }
                } label: {
                    Text("Body Only")
                        .font(.subheadline.weight(mountSetup == .bodyOnly ? .semibold : .medium))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(
                            Capsule()
                                .fill(mountSetup == .bodyOnly ? Palette.text : Palette.panel)
                        )
                        .foregroundStyle(mountSetup == .bodyOnly ? Palette.background : Palette.textSub)
                }
                .buttonStyle(.plain)
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
    }

    // MARK: - 3. Airy Single-Column Scannable Lists

    @ViewBuilder
    private var bodyListSection: some View {
        let cameras = filteredCameras
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let visibleCameras = (isSearching || showAllBodiesForBrand) ? cameras : Array(cameras.prefix(8))

        VStack(spacing: 10) {
            ForEach(visibleCameras) { cam in
                let isSelected = (stagedCamera.id == cam.id)
                CameraBodyListRow(
                    camera: cam,
                    isSelected: isSelected
                ) {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        selectCameraBody(cam)
                    }
                }
                .contextMenu {
                    if cam.isCustom {
                        Button(role: .destructive) {
                            store.removeCustomCamera(id: cam.id)
                        } label: {
                            Label("Delete Custom Camera", systemImage: "trash")
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
                        Text(showAllBodiesForBrand ? "Show Top Flagships" : "Show All \(cameras.count) \(selectedBrand) Models")
                        Image(systemName: showAllBodiesForBrand ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textSub)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Palette.panel, in: .rect(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var lensListSection: some View {
        let lenses = filteredLenses

        VStack(spacing: 10) {
            ForEach(lenses) { entry in
                let isSelected = (stagedLensEntry?.id == entry.id && mountSetup != .bodyOnly)
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
                            store.removeCustomLens(id: entry.lens.id)
                        } label: {
                            Label("Delete Custom Lens", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Selection & State Sync Helpers

    private func selectCameraBody(_ cam: CameraGearSpec) {
        stagedCamera = cam
        if cam.isFixed {
            step = .body
            stagedLensEntry = nil
            stagedVariantID = ""
            mountSetup = .matched
        } else {
            let matching = allLenses.filter { $0.lens.mount.caseInsensitiveCompare(cam.mount) == .orderedSame }
            if let current = stagedLensEntry,
               current.lens.mount.caseInsensitiveCompare(cam.mount) == .orderedSame {
                // Keep compatible lens
            } else if let std = matching.first(where: { $0.focalLengthMm >= 34 && $0.focalLengthMm <= 55 }) ?? matching.first {
                stagedLensEntry = std
                stagedVariantID = std.variants.first?.id ?? ""
                mountSetup = .matched
            } else {
                stagedLensEntry = nil
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
            selectedBrand = brandList.contains(matchCam.brand) ? matchCam.brand : "Other"
        } else if let firstCam = allCameras.first {
            stagedCamera = firstCam
            selectedBrand = brandList.contains(firstCam.brand) ? firstCam.brand : "Rollei"
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

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(camera.model)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)

                    Text(camera.isFixed
                         ? (camera.fixedLensName.isEmpty ? "Fixed Lens · \(shutterRangeText(camera.minShutter, camera.maxShutter))" : "\(cleanLensDisplayName(camera.fixedLensName, brand: camera.brand)) · \(shutterRangeText(camera.minShutter, camera.maxShutter))")
                         : "\(formatMountBadge(camera.mount)) Mount  ·  Shutter \(shutterRangeText(camera.minShutter, camera.maxShutter))")
                        .font(.footnote.weight(.medium).monospacedDigit())
                        .foregroundStyle(Palette.textSub)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                ZStack {
                    Circle()
                        .fill(isSelected ? Palette.accent : Color.white.opacity(0.06))
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(Palette.accentInk)
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Palette.panelRaised : Palette.panel)
            )
        }
        .buttonStyle(PressStyle(scale: 0.98))
    }
}

private struct OpticalLensListRow: View {
    let entry: PrewarmedLensEntry
    let isSelected: Bool
    @Binding var selectedVariantID: String
    let onSelect: () -> Void
    let onVariantChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cleanLensDisplayName(entry.lens.model, brand: entry.lens.brand))
                            .font(.body.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)

                        Text("\(entry.lens.brand)  ·  \(formatMountBadge(entry.lens.mount))  ·  \(formatApertureRange(entry.lens.minAperture, entry.lens.maxAperture))")
                            .font(.footnote.weight(.medium).monospacedDigit())
                            .foregroundStyle(Palette.textSub)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    ZStack {
                        Circle()
                            .fill(isSelected ? Palette.accent : Color.white.opacity(0.06))
                            .frame(width: 24, height: 24)

                        if isSelected {
                            Circle()
                                .fill(Palette.accentInk)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Inline Version Pills (Only expanded on the selected lens row when multiple generations exist)
            if isSelected && entry.variants.count > 1 {
                HStack(spacing: 8) {
                    ForEach(entry.variants) { variant in
                        let active = (variant.id == selectedVariantID) || (selectedVariantID.isEmpty && variant.id == entry.variants.first?.id)
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.snappy(duration: 0.18)) {
                                selectedVariantID = variant.id
                                onVariantChange()
                            }
                        } label: {
                            Text(variant.badge)
                                .font(.caption.weight(active ? .semibold : .medium))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(active ? Palette.text : Palette.background)
                                )
                                .foregroundStyle(active ? Palette.background : Palette.textSub)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? Palette.panelRaised : Palette.panel)
        )
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
                        .fill(isCocked ? Palette.accent : Palette.textDim)
                        .frame(width: 6, height: 6)

                    Text(isCocked ? "COCKED & LOCKED · \(cameraModel.uppercased())" : "THROW ADVANCE LEVER TO COCK & MOUNT")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(isCocked ? Palette.text : Palette.textSub)
                }

                Spacer()

                if isCocked {
                    Button {
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.65)
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.62)) {
                            isCocked = false
                            throwProgress = 0.0
                        }
                    } label: {
                        Text("Release")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.textSub)
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
                        isCocked: isCocked,
                        isDragging: isDragging
                    )
                    .frame(width: handleW, height: handleH)
                    .offset(x: currentX)
                    .shadow(color: .black.opacity(0.55), radius: 5, x: 0, y: 2)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if isCocked { return }
                            if !isDragging {
                                isDragging = true
                                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.55)
                            }

                            let raw = (value.location.x - handleW * 0.5) / maxTravel
                            let clamped = min(max(raw, 0.0), 1.0)
                            // Progressive physical spring resistance curve
                            let resisted = CGFloat(pow(Double(clamped), 0.90))
                            throwProgress = resisted

                            // Rigid ratcheting gear-tooth haptics across the throw
                            let tooth = Int(resisted * 20)
                            if tooth != lastToothTick {
                                lastToothTick = tooth
                                let intensity = CGFloat(0.50 + 0.45 * resisted)
                                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: intensity)
                            }

                            // Sharp mechanical thud when sear latches at full throw
                            if resisted >= latchPoint {
                                latchCockedPosition()
                            }
                        }
                        .onEnded { _ in
                            guard !isCocked else { return }
                            isDragging = false
                            if throwProgress >= latchPoint {
                                latchCockedPosition()
                            } else {
                                // Un-cocked spring return recoil
                                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.6)
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.58)) {
                                    throwProgress = 0.0
                                }
                                lastToothTick = 0
                            }
                        }
                )
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
                withAnimation(.spring(response: 0.34, dampingFraction: 0.62)) {
                    throwProgress = 0.0
                }
                lastToothTick = 0
            }
        }
    }

    private func latchCockedPosition() {
        guard !isCocked else { return }
        isDragging = false
        // Sharp mechanical thud (.heavy) when sear latches and cocks the frame
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1.0)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.68)) {
            throwProgress = 1.0
            isCocked = true
        }
        onLatchCocked()
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
