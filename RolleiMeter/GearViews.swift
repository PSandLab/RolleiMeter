import Foundation
import SwiftUI
import UIKit

// MARK: - Linked 2-Step Camera & Lens Studio with Mechanical Thumb-Wind Cocking Chamber

struct CameraLensView: View {
    @ObservedObject var store: FilmLogStore
    var onFinish: () -> Void = {}

    private enum SelectionStep: Int {
        case body = 1
        case lens = 2
    }

    private enum MountSetup: String, CaseIterable {
        case matched = "Native Lens"
        case adapter = "Adapted Lens"
        case bodyOnly = "Body Only"
    }

    @State private var step: SelectionStep = .body
    @State private var selectedBrand: String = "Leica"
    @State private var showAllBodiesForBrand: Bool = false
    @State private var focalFilter: FocalLengthCategory = .all
    @State private var allowAdaptedMounts: Bool = false
    @State private var searchText: String = ""

    @State private var stagedCamera: CameraGearSpec = GearCatalogCache.loadBundledCatalog().cameras[0]
    @State private var stagedLensEntry: PrewarmedLensEntry? = nil
    @State private var stagedVariantID: String = ""
    @State private var mountSetup: MountSetup = .matched
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

    // Prioritize flagship interchangeable & iconic rangefinder/SLR bodies before compact point-and-shoots
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
        if stagedCamera.isFixed || allowAdaptedMounts || mountSetup == .adapter {
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
            VStack(spacing: 16) {
                // ── ONE UNIFIED MECHANICAL CAMERA COCKING CHAMBER & LINKED 2-STEP SELECTOR ──
                VStack(spacing: 0) {
                    // PART A: Minimal Rig Header + Full-Width Mechanical Thumb-Wind Cocking Chamber
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 12) {
                            CameraBrandLogo(brand: stagedCamera.brand, size: 40)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(stagedCamera.model)
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(Palette.text)
                                        .lineLimit(1)

                                    if isStagedComboCurrentlyMounted {
                                        Text("MOUNTED")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Palette.good.opacity(0.20), in: Capsule())
                                            .foregroundStyle(Palette.good)
                                    }
                                }

                                let preview = resolvedPreviewProfile
                                Text(preview.hasLens ? cleanLensDisplayName(preview.lensName, brand: stagedCamera.brand) : "\(formatMountBadge(stagedCamera.mount)) Body Only")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Palette.accent)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 4)

                            // Compact Hardware Limits Pill
                            let preview = resolvedPreviewProfile
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(shutterRangeText(stagedCamera.minShutter, stagedCamera.maxShutter))
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(Palette.text)
                                Text(formatApertureRange(preview.minAperture, preview.maxAperture))
                                    .font(.caption2.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(Palette.textSub)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 10, style: .continuous))
                        }

                        // Isolated 120fps Mechanical Thumb-Wind Cocking Chamber
                        InteractiveCameraCockingChamber(
                            cameraModel: stagedCamera.model,
                            lensSummary: resolvedPreviewProfile.hasLens ? cleanLensDisplayName(resolvedPreviewProfile.lensName, brand: stagedCamera.brand) : "Body Only",
                            shutterSummary: shutterRangeText(stagedCamera.minShutter, stagedCamera.maxShutter),
                            apertureSummary: formatApertureRange(resolvedPreviewProfile.minAperture, resolvedPreviewProfile.maxAperture),
                            minAperture: resolvedPreviewProfile.minAperture,
                            isAlreadyMounted: isStagedComboCurrentlyMounted
                        ) {
                            commitStagedGear()
                        }
                    }
                    .padding(16)

                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 1)

                    // PART B: Linked 2-Step Guided Selection Drawer (Step 1: Body -> Step 2: Lens)
                    VStack(alignment: .leading, spacing: 14) {
                        // Linked Step Breadcrumb Bar
                        HStack(spacing: 8) {
                            // Step 1 Button: Camera Body
                            Button {
                                Haptics.tap()
                                withAnimation(.snappy(duration: 0.22)) {
                                    step = .body
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text("1")
                                        .font(.system(size: 10, weight: .black).monospacedDigit())
                                        .frame(width: 18, height: 18)
                                        .background(
                                            Circle()
                                                .fill(step == .body ? Palette.accentInk : Palette.accent.opacity(0.22))
                                        )
                                        .foregroundStyle(step == .body ? Palette.accent : Palette.accent)

                                    Text(stagedCamera.model)
                                        .font(.caption.weight(.bold))
                                        .lineLimit(1)
                                }
                                .padding(.leading, 6)
                                .padding(.trailing, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(step == .body ? Palette.accent : Color.white.opacity(0.07))
                                )
                                .foregroundStyle(step == .body ? Palette.accentInk : Palette.text)
                            }
                            .buttonStyle(.plain)

                            if !stagedCamera.isFixed {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Palette.textDim)

                                // Step 2 Button: Linked Lens Selection
                                Button {
                                    Haptics.tap()
                                    withAnimation(.snappy(duration: 0.22)) {
                                        step = .lens
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text("2")
                                            .font(.system(size: 10, weight: .black).monospacedDigit())
                                            .frame(width: 18, height: 18)
                                            .background(
                                                Circle()
                                                    .fill(step == .lens ? Palette.accentInk : Palette.accent.opacity(0.22))
                                            )
                                            .foregroundStyle(step == .lens ? Palette.accent : Palette.accent)

                                        Text(stepTwoPillTitle)
                                            .font(.caption.weight(.bold))
                                            .lineLimit(1)
                                    }
                                    .padding(.leading, 6)
                                    .padding(.trailing, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule()
                                            .fill(step == .lens ? Palette.accent : Color.white.opacity(0.07))
                                    )
                                    .foregroundStyle(step == .lens ? Palette.accentInk : Palette.text)
                                }
                                .buttonStyle(.plain)
                            }

                            Spacer(minLength: 0)

                            NavigationLink {
                                CustomGearForm(
                                    store: store,
                                    onFinish: onFinish,
                                    presetKinds: (step == .lens && !stagedCamera.isFixed) ? [.lens] : [.fixedLens, .body],
                                    presetBrand: selectedBrand == "Custom" || selectedBrand == "Other" ? "" : selectedBrand
                                )
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .bold))
                                    .frame(width: 30, height: 30)
                                    .background(Color.white.opacity(0.08), in: Circle())
                                    .foregroundStyle(Palette.accent)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add Custom Gear")
                        }

                        if step == .body || stagedCamera.isFixed {
                            stepOneCameraBodyPicker
                        } else {
                            stepTwoLinkedLensPicker
                        }
                    }
                    .padding(16)
                    .background(Color.black.opacity(0.28))
                }
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Palette.panel)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .clipShape(.rect(cornerRadius: 24, style: .continuous))

                if store.activeGear.hasCamera {
                    Button(role: .destructive) {
                        showRemoveConfirm = true
                    } label: {
                        Label("Detach Active Camera from Meter", systemImage: "eject.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.bad)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Palette.panel, in: .rect(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Palette.background.ignoresSafeArea())
        .searchable(
            text: $searchText,
            prompt: (step == .body || stagedCamera.isFixed) ? "Search camera models" : "Search \(formatMountBadge(stagedCamera.mount)) lenses"
        )
        .navigationTitle("Camera & Optics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .onAppear {
            syncStagedWithActiveGearIfNeeded()
        }
        .confirmationDialog("Remove active camera?", isPresented: $showRemoveConfirm) {
            Button("Detach Camera", role: .destructive) {
                store.activeGear = .unloaded
                Haptics.success()
                onFinish()
            }
        }
    }

    private var stepTwoPillTitle: String {
        if mountSetup == .bodyOnly { return "Body Only" }
        if let entry = stagedLensEntry {
            return shortFocalBadge(entry)
        }
        return "Choose Lens"
    }

    // MARK: - STEP 1: Clean, De-Bloated Camera Body Picker

    @ViewBuilder
    private var stepOneCameraBodyPicker: some View {
        let cameras = filteredCameras
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let visibleCameras = (isSearching || showAllBodiesForBrand) ? cameras : Array(cameras.prefix(8))

        VStack(alignment: .leading, spacing: 12) {
            // Clean Text Brand Pills (Never clips brand logos)
            if !isSearching {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(brandList, id: \.self) { brand in
                            let active = (selectedBrand == brand)
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                withAnimation(.snappy(duration: 0.18)) {
                                    selectedBrand = brand
                                    showAllBodiesForBrand = false
                                }
                            } label: {
                                Text(brand)
                                    .font(.caption.weight(active ? .bold : .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(active ? Palette.accent : Color.white.opacity(0.06))
                                    )
                                    .foregroundStyle(active ? Palette.accentInk : Palette.textSub)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Curated 2-Column Camera Body Grid (Zero repeated logo clutter)
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(visibleCameras) { cam in
                    let isStaged = (stagedCamera.id == cam.id)
                    CleanCameraBodyTile(
                        camera: cam,
                        isStaged: isStaged
                    ) {
                        Haptics.rigid()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.68)) {
                            selectCameraAndAdvanceIfNeeded(cam)
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
            }

            // Expand button if brand has more than 8 bodies
            if !isSearching && cameras.count > 8 {
                Button {
                    Haptics.tap()
                    withAnimation(.snappy(duration: 0.22)) {
                        showAllBodiesForBrand.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(showAllBodiesForBrand ? "Show Top Flagships" : "Show All \(cameras.count) \(selectedBrand) Bodies")
                        Image(systemName: showAllBodiesForBrand ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.04), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - STEP 2: Linked Optical Lens Picker for the Staged Camera Body

    @ViewBuilder
    private var stepTwoLinkedLensPicker: some View {
        let lenses = filteredLenses

        VStack(alignment: .leading, spacing: 12) {
            // Mount Context Bar + Quick Setup Options (Native / Adapted / Body Only)
            HStack(spacing: 6) {
                Text("FOR \(stagedCamera.model.uppercased()) (\(formatMountBadge(stagedCamera.mount)))")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(Palette.textSub)
                    .lineLimit(1)

                Spacer()

                Button {
                    Haptics.tap()
                    withAnimation(.snappy(duration: 0.18)) {
                        if mountSetup == .bodyOnly {
                            mountSetup = .matched
                        } else {
                            mountSetup = .bodyOnly
                        }
                    }
                } label: {
                    Text(mountSetup == .bodyOnly ? "✓ Body Only" : "Body Only")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(mountSetup == .bodyOnly ? Palette.accent : Color.white.opacity(0.07))
                        )
                        .foregroundStyle(mountSetup == .bodyOnly ? Palette.accentInk : Palette.textSub)
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.tap()
                    withAnimation(.snappy(duration: 0.18)) {
                        allowAdaptedMounts.toggle()
                        mountSetup = allowAdaptedMounts ? .adapter : .matched
                    }
                } label: {
                    Text(allowAdaptedMounts ? "✓ All Mounts" : "Adapt Mount")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(allowAdaptedMounts ? Palette.accent : Color.white.opacity(0.07))
                        )
                        .foregroundStyle(allowAdaptedMounts ? Palette.accentInk : Palette.textSub)
                }
                .buttonStyle(.plain)
            }

            // Focal Length Filter Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(FocalLengthCategory.allCases) { cat in
                        let active = (focalFilter == cat)
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.snappy(duration: 0.18)) {
                                focalFilter = cat
                            }
                        } label: {
                            Text(cat == .all ? "All Focal Lengths" : (cat == .zoom ? "Zooms" : "\(cat.label)mm"))
                                .font(.caption.weight(active ? .bold : .medium).monospacedDigit())
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(active ? Palette.accent : Color.white.opacity(0.06))
                                )
                                .foregroundStyle(active ? Palette.accentInk : Palette.textSub)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Inline Vintage Version Selector (only shown when the selected lens has multiple versions)
            if mountSetup != .bodyOnly,
               let entry = stagedLensEntry,
               entry.variants.count > 1 {
                HStack(spacing: 6) {
                    ForEach(entry.variants) { variant in
                        let selected = (variant.id == stagedVariantID) || (stagedVariantID.isEmpty && variant.id == entry.variants.first?.id)
                        Button {
                            Haptics.tap()
                            withAnimation(.snappy(duration: 0.18)) {
                                stagedVariantID = variant.id
                            }
                        } label: {
                            Text(variant.badge)
                                .font(.caption2.weight(selected ? .bold : .medium))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(selected ? Palette.accent.opacity(0.24) : Color.white.opacity(0.05))
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(selected ? Palette.accent : Color.clear, lineWidth: 1)
                                        )
                                )
                                .foregroundStyle(selected ? Palette.accent : Palette.textSub)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Clean, Distinct Lens Cards Showing Real Optical Names (e.g. Summicron-M 35mm f/2, Biogon 28mm f/2.8)
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(lenses) { entry in
                    let isStaged = (stagedLensEntry?.id == entry.id && mountSetup != .bodyOnly)
                    CleanOpticalLensTile(
                        entry: entry,
                        isStaged: isStaged
                    ) {
                        Haptics.rigid()
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.68)) {
                            stagedLensEntry = entry
                            stagedVariantID = entry.variants.first?.id ?? ""
                            if mountSetup == .bodyOnly {
                                mountSetup = allowAdaptedMounts ? .adapter : .matched
                            }
                        }
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
    }

    // MARK: - Selection & Linking Logic

    private func selectCameraAndAdvanceIfNeeded(_ cam: CameraGearSpec) {
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
            // Automatically advance to Step 2 (Lens selection) so the user immediately picks or confirms their lens!
            step = .lens
        }
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

        guard !stagedCamera.isFixed else {
            step = .body
            return
        }

        if active.lensId.isEmpty {
            mountSetup = .bodyOnly
            return
        }

        for entry in allLenses {
            if entry.lens.id == active.lensId {
                stagedLensEntry = entry
                stagedVariantID = entry.variants.first?.id ?? ""
                mountSetup = .matched
                return
            }
            if let v = entry.variants.first(where: { $0.spec.id == active.lensId }) {
                stagedLensEntry = entry
                stagedVariantID = v.id
                mountSetup = .matched
                return
            }
        }

        let matching = allLenses.filter { $0.lens.mount.caseInsensitiveCompare(stagedCamera.mount) == .orderedSame }
        if let firstMatch = matching.first(where: { $0.focalLengthMm >= 34 && $0.focalLengthMm <= 55 }) ?? matching.first {
            stagedLensEntry = firstMatch
            stagedVariantID = firstMatch.variants.first?.id ?? ""
            mountSetup = .matched
        }
    }

    private func commitStagedGear() {
        store.activeGear = resolvedPreviewProfile
        onFinish()
    }
}

// MARK: - Isolated 120fps Mechanical Camera Top-Plate & Thumb-Wind Cocking Chamber

private struct InteractiveCameraCockingChamber: View {
    let cameraModel: String
    let lensSummary: String
    let shutterSummary: String
    let apertureSummary: String
    let minAperture: Double
    let isAlreadyMounted: Bool
    var onCockAndMountComplete: () -> Void

    @State private var cockProgress: CGFloat = 0.0
    @State private var dragY: CGFloat = 0.0
    @State private var isDragging: Bool = false
    @State private var isLatchedHold: Bool = false
    @State private var heartbeatScale: CGFloat = 1.0
    @State private var heartbeatTask: Task<Void, Never>? = nil

    // Grand Shutter-Fire Ceremony States
    @State private var ceremonyPhase: Int = 0 // 0 = interactive, 1 = lever return, 2 = shutter fire flash, 3 = locked confirmation
    @State private var shutterFlash: Double = 0.0
    @State private var buttonDepress: CGFloat = 0.0
    @State private var irisSnapOverride: CGFloat? = nil
    @State private var idlePulse: Bool = false
    @State private var lastRatchetTooth: Int = 0

    private let latchThreshold: CGFloat = 0.84

    private var baseIrisRatio: CGFloat {
        let f = min(max(minAperture, 0.95), 8.0)
        return CGFloat(min(max(1.0 - log2(f) / log2(11.0), 0.34), 0.84))
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let startX: CGFloat = 104
                let endX: CGFloat = w - 38
                let travel = max(endX - startX, 1)

                ZStack {
                    // 1. Recessed Anodized Camera Top-Plate Housing
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(red: 0.035, green: 0.038, blue: 0.045))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(
                                    ceremonyPhase == 3
                                        ? Palette.good.opacity(0.85)
                                        : (isLatchedHold ? Palette.accent.opacity(0.85) : Color.white.opacity(0.08)),
                                    lineWidth: isLatchedHold || ceremonyPhase > 0 ? 1.5 : 1.0
                                )
                        )

                    // 2. Single 120fps Cutaway Mechanical Top-Plate, Brass Gear Train, 9-Blade Lens & Thumb-Wind Lever Canvas
                    CameraTopPlateCockingCanvas(
                        cockProgress: cockProgress,
                        dragY: dragY,
                        latchThreshold: latchThreshold,
                        irisRatio: irisSnapOverride ?? baseIrisRatio,
                        shutterFlash: shutterFlash,
                        buttonDepress: buttonDepress,
                        idlePulse: idlePulse,
                        isDragging: isDragging,
                        isLatchedHold: isLatchedHold,
                        heartbeatScale: heartbeatScale,
                        ceremonyPhase: ceremonyPhase
                    )

                    // 3. Stage 3 Engraved Top-Plate Confirmation Overlay
                    if ceremonyPhase == 3 {
                        HStack(spacing: 14) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(Palette.good)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("SHUTTER COCKED & RIG LOCKED")
                                    .font(.caption2.weight(.bold))
                                    .tracking(1.3)
                                    .foregroundStyle(Palette.good)

                                Text("\(cameraModel) · \(lensSummary)")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Palette.text)
                                    .lineLimit(1)

                                Text("Dials clamped to \(shutterSummary) · \(apertureSummary)")
                                    .font(.caption2.weight(.medium).monospacedDigit())
                                    .foregroundStyle(Palette.textSub)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(red: 0.04, green: 0.045, blue: 0.055).opacity(0.94))
                        .transition(.opacity)
                    }

                    // 4. Full-Chamber Thumb-Wind Pull Gesture (User has 100% control until finger release)
                    if ceremonyPhase == 0 {
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if !isDragging {
                                            isDragging = true
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)
                                        }

                                        let raw = (value.location.x - startX) / travel
                                        let clamped = min(max(raw, 0.0), 1.0)
                                        let yDeflect = max(-18, min(18, value.location.y - h * 0.5))

                                        if clamped >= latchThreshold {
                                            let magnet = latchThreshold + (clamped - latchThreshold) * 0.45
                                            cockProgress = min(max(magnet, latchThreshold), 0.96)
                                            dragY = yDeflect * 0.25
                                            if !isLatchedHold {
                                                enterFullCockHeartbeat()
                                            }
                                        } else {
                                            if isLatchedHold {
                                                exitFullCockHeartbeat()
                                            }
                                            cockProgress = clamped
                                            dragY = yDeflect * 0.65

                                            // Mechanical brass pawl ratchet teeth clicks (20 teeth across stroke)
                                            let tooth = Int(clamped * 20)
                                            if tooth != lastRatchetTooth {
                                                lastRatchetTooth = tooth
                                                UISelectionFeedbackGenerator().selectionChanged()
                                            }
                                        }
                                    }
                                    .onEnded { _ in
                                        isDragging = false
                                        if cockProgress >= latchThreshold {
                                            exitFullCockHeartbeat()
                                            runShutterFireAndMountCeremony()
                                        } else {
                                            exitFullCockHeartbeat()
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
                                            withAnimation(.spring(response: 0.34, dampingFraction: 0.52)) {
                                                cockProgress = 0.0
                                                dragY = 0.0
                                            }
                                            lastRatchetTooth = 0
                                        }
                                    }
                            )
                    }
                }
                .clipShape(.rect(cornerRadius: 20, style: .continuous))
            }
            .frame(height: 124)

            // Bottom Instruction & Status Bar
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(ceremonyPhase == 3 ? Palette.good : (isLatchedHold || ceremonyPhase > 0 ? Palette.accent : (isAlreadyMounted ? Palette.good : Palette.textDim)))
                        .frame(width: 6, height: 6)
                        .scaleEffect(isLatchedHold ? heartbeatScale : 1.0)

                    Text(cockingStatusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ceremonyPhase == 3 ? Palette.good : (isLatchedHold || ceremonyPhase > 0 ? Palette.accent : .secondary))
                        .contentTransition(.numericText())
                }

                Spacer()

                if isLatchedHold {
                    Text("SLIDE LEFT TO UN-COCK")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                idlePulse = true
            }
        }
        .onDisappear {
            heartbeatTask?.cancel()
            heartbeatTask = nil
        }
        .onChange(of: cameraModel) { _, _ in
            resetLeverOnGearSwap()
        }
        .onChange(of: lensSummary) { _, _ in
            resetLeverOnGearSwap()
        }
    }

    private var cockingStatusText: String {
        switch ceremonyPhase {
        case 1: return "SHUTTER COCKED · LEVER RETURNING…"
        case 2: return "FIRING MECHANICAL SHUTTER & IRIS CHECK…"
        case 3: return "RIG ACTIVE · DIALS SYNCHRONIZED"
        default:
            if isLatchedHold {
                return "SHUTTER AT FULL COCK · RELEASE THUMB TO ENGAGE"
            }
            if cockProgress > 0.04 {
                let pct = Int((cockProgress / latchThreshold * 100).rounded()).clamped(to: 1...99)
                return "WINDING SHUTTER MAINSPRING · \(pct)%"
            }
            return isAlreadyMounted ? "PULL THUMB-LEVER ACROSS TO RE-COCK RIG →" : "PULL THUMB-WIND LEVER ACROSS TO COCK & MOUNT →"
        }
    }

    private func resetLeverOnGearSwap() {
        guard ceremonyPhase == 0 else { return }
        exitFullCockHeartbeat()
        withAnimation(.spring(response: 0.30, dampingFraction: 0.62)) {
            cockProgress = 0.0
            dragY = 0.0
        }
    }

    private func enterFullCockHeartbeat() {
        isLatchedHold = true
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.9)
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor in
            while !Task.isCancelled && isLatchedHold {
                withAnimation(.easeInOut(duration: 0.32)) {
                    heartbeatScale = 1.15
                }
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.48)
                try? await Task.sleep(for: .milliseconds(320))
                if Task.isCancelled || !isLatchedHold { break }
                withAnimation(.easeInOut(duration: 0.36)) {
                    heartbeatScale = 1.0
                }
                try? await Task.sleep(for: .milliseconds(360))
            }
        }
    }

    private func exitFullCockHeartbeat() {
        isLatchedHold = false
        heartbeatTask?.cancel()
        heartbeatTask = nil
        withAnimation(.easeOut(duration: 0.2)) {
            heartbeatScale = 1.0
        }
    }

    private func runShutterFireAndMountCeremony() {
        guard ceremonyPhase == 0 else { return }
        ceremonyPhase = 1

        // Stage 1: Sear catches at full cock, thumb-wind lever springs back to parked position (0.0s -> 0.45s)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1.0)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.62)) {
            cockProgress = 0.0
            dragY = 0.0
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(360))

            // Stage 2: Chrome shutter button depresses + 9-blade iris stops down + focal-plane shutter fires KA-CHUNK! (0.45s -> 1.35s)
            ceremonyPhase = 2
            withAnimation(.easeIn(duration: 0.09)) {
                buttonDepress = 1.0
                irisSnapOverride = 0.18
            }
            try? await Task.sleep(for: .milliseconds(90))
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1.0)
            withAnimation(.easeOut(duration: 0.08)) {
                shutterFlash = 1.0
            }
            try? await Task.sleep(for: .milliseconds(95))
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.95)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) {
                shutterFlash = 0.0
                buttonDepress = 0.0
                irisSnapOverride = baseIrisRatio
            }

            // Stage 3: Engraved Top-Plate Confirmation Card (1.35s -> 2.35s)
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                ceremonyPhase = 3
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)

            try? await Task.sleep(for: .milliseconds(950))
            onCockAndMountComplete()

            try? await Task.sleep(for: .milliseconds(250))
            ceremonyPhase = 0
            irisSnapOverride = nil
        }
    }
}

// MARK: - Cutaway Camera Top-Plate, Brass Gear Train, 9-Blade Optic & Thumb-Wind Lever Canvas

private struct CameraTopPlateCockingCanvas: View {
    let cockProgress: CGFloat
    let dragY: CGFloat
    let latchThreshold: CGFloat
    let irisRatio: CGFloat
    let shutterFlash: Double
    let buttonDepress: CGFloat
    let idlePulse: Bool
    let isDragging: Bool
    let isLatchedHold: Bool
    let heartbeatScale: CGFloat
    let ceremonyPhase: Int

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let midY = h * 0.5
            let lensX: CGFloat = 54
            let pivotX: CGFloat = 108
            let endX: CGFloat = w - 34
            let travel = max(endX - pivotX, 1)
            let tipX = pivotX + travel * cockProgress
            let tipY = midY + dragY * 0.65

            let brassColor = Color(red: 0.88, green: 0.68, blue: 0.24)
            let steelColor = Color(red: 0.72, green: 0.76, blue: 0.82)
            let gearAngle = Double(cockProgress) * 320.0

            // 1. Cutaway Sapphire Gear-Train Track Slot (connecting Optic to Lever Pivot)
            let slotRect = CGRect(x: lensX, y: midY - 22, width: w - lensX - 18, height: 44)
            ctx.fill(Path(roundedRect: slotRect, cornerRadius: 22), with: .color(Color.black.opacity(0.65)))
            ctx.stroke(Path(roundedRect: slotRect, cornerRadius: 22), with: .color(Color.white.opacity(0.07)), lineWidth: 1.0)

            // 2. Meshing Internal Brass Ratchet Wheel & Coiled Shutter Mainspring at Pivot
            var gearCtx = ctx
            gearCtx.translateBy(x: pivotX, y: midY)
            gearCtx.rotate(by: .degrees(gearAngle))
            let gearR: CGFloat = 24
            let toothCount = 16
            for i in 0..<toothCount {
                let a = Double(i) * (2.0 * .pi / Double(toothCount))
                var tooth = Path()
                tooth.move(to: CGPoint(x: CGFloat(cos(a)) * (gearR - 4), y: CGFloat(sin(a)) * (gearR - 4)))
                tooth.addLine(to: CGPoint(x: CGFloat(cos(a)) * (gearR + 2.5), y: CGFloat(sin(a)) * (gearR + 2.5)))
                gearCtx.stroke(tooth, with: .color(brassColor.opacity(0.75)), lineWidth: 2.4)
            }
            gearCtx.stroke(
                Path(ellipseIn: CGRect(x: -gearR + 3, y: -gearR + 3, width: (gearR - 3) * 2, height: (gearR - 3) * 2)),
                with: .color(brassColor.opacity(0.85)),
                lineWidth: 2.0
            )

            // Coiled Mainspring Spiral inside Pivot Boss (winds tighter with cockProgress)
            var spiral = Path()
            let turns = 2.5 + Double(cockProgress) * 1.8
            let steps = 48
            for s in 0...steps {
                let frac = Double(s) / Double(steps)
                let angle = frac * turns * 2.0 * .pi + (gearAngle * .pi / 180.0)
                let r = 3.0 + CGFloat(frac) * (13.0 - cockProgress * 3.5)
                let pt = CGPoint(x: pivotX + CGFloat(cos(angle)) * r, y: midY + CGFloat(sin(angle)) * r)
                if s == 0 { spiral.move(to: pt) } else { spiral.addLine(to: pt) }
            }
            ctx.stroke(spiral, with: .color(Palette.accent.opacity(0.55 + Double(cockProgress) * 0.40)), lineWidth: 1.3)

            // 3. Left Side: Optical Lens Barrel & Live 9-Blade Iris Throat
            let opticR: CGFloat = 36
            let opticRect = CGRect(x: lensX - opticR, y: midY - opticR, width: opticR * 2, height: opticR * 2)
            ctx.fill(Path(ellipseIn: opticRect), with: .color(Color(red: 0.08, green: 0.09, blue: 0.11)))
            ctx.stroke(
                Path(ellipseIn: opticRect),
                with: .color(ceremonyPhase == 2 ? Palette.accent : Color.white.opacity(0.22)),
                lineWidth: 2.0
            )

            let glassR: CGFloat = 27
            let glassRect = CGRect(x: lensX - glassR, y: midY - glassR, width: glassR * 2, height: glassR * 2)
            let glassPath = Path(ellipseIn: glassRect)
            ctx.fill(glassPath, with: .color(Color(red: 0.02, green: 0.03, blue: 0.05)))

            var irisCtx = ctx
            irisCtx.clip(to: glassPath)

            let liveOpen = max(0.16, irisRatio - cockProgress * 0.22)
            let holeR = glassR * liveOpen
            var bladeMask = Path()
            bladeMask.addEllipse(in: glassRect)
            bladeMask.addEllipse(in: CGRect(x: lensX - holeR, y: midY - holeR, width: holeR * 2, height: holeR * 2))
            irisCtx.fill(bladeMask, with: .color(Color(red: 0.11, green: 0.12, blue: 0.15)), style: FillStyle(eoFill: true))

            for b in 0..<9 {
                let a1 = Double(b) * (2.0 * .pi / 9.0) + Double(cockProgress) * 0.5
                let a2 = a1 + 1.15
                var edge = Path()
                edge.move(to: CGPoint(x: lensX + CGFloat(cos(a1)) * holeR, y: midY + CGFloat(sin(a1)) * holeR))
                edge.addLine(to: CGPoint(x: lensX + CGFloat(cos(a2)) * (glassR + 3), y: midY + CGFloat(sin(a2)) * (glassR + 3)))
                irisCtx.stroke(edge, with: .color(Color.white.opacity(0.24)), lineWidth: 1.0)
            }

            // Optical coating reflection + shutter actuation flash
            irisCtx.fill(
                Path(ellipseIn: CGRect(x: lensX - glassR * 0.7, y: midY - glassR * 0.75, width: glassR * 1.1, height: glassR * 0.65)),
                with: .linearGradient(
                    Gradient(colors: [Color(red: 0.15, green: 0.75, blue: 0.98).opacity(0.22), .clear]),
                    startPoint: CGPoint(x: lensX - glassR, y: midY - glassR),
                    endPoint: CGPoint(x: lensX + glassR, y: midY + glassR)
                )
            )
            if shutterFlash > 0.01 {
                irisCtx.fill(glassPath, with: .color(Color.white.opacity(shutterFlash * 0.75)))
            }

            // 4. Right Side Target: Threaded Chrome Shutter Release Button & Full-Cock Sear Catch
            let catchCenter = CGPoint(x: endX, y: midY)
            let catchR: CGFloat = 18 - buttonDepress * 2.5
            ctx.stroke(
                Path(ellipseIn: CGRect(x: catchCenter.x - 22, y: catchCenter.y - 22, width: 44, height: 44)),
                with: .color(isLatchedHold ? Palette.accent : Color.white.opacity(0.16)),
                style: StrokeStyle(lineWidth: isLatchedHold ? 2.0 : 1.2, dash: [4, 3])
            )
            ctx.fill(
                Path(ellipseIn: CGRect(x: catchCenter.x - catchR, y: catchCenter.y - catchR, width: catchR * 2, height: catchR * 2)),
                with: .color(isLatchedHold ? Palette.accent.opacity(0.28) : Color(red: 0.18, green: 0.20, blue: 0.24))
            )

            // 5. Sculpted Metal Thumb-Wind Cocking Lever Arm (stretching from Pivot to Thumb Tip)
            var arm = Path()
            let ctrlX = (pivotX + tipX) * 0.5
            let ctrlY = midY + dragY * 0.95
            arm.move(to: CGPoint(x: pivotX, y: midY - 8))
            arm.addQuadCurve(
                to: CGPoint(x: tipX, y: tipY - 12),
                control: CGPoint(x: ctrlX, y: ctrlY - 10)
            )
            arm.addQuadCurve(
                to: CGPoint(x: tipX, y: tipY + 12),
                control: CGPoint(x: tipX + 12, y: tipY)
            )
            arm.addQuadCurve(
                to: CGPoint(x: pivotX, y: midY + 8),
                control: CGPoint(x: ctrlX, y: ctrlY + 10)
            )
            arm.closeSubpath()

            ctx.fill(
                arm,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.62, green: 0.66, blue: 0.73),
                        Color(red: 0.32, green: 0.35, blue: 0.40),
                        Color(red: 0.50, green: 0.54, blue: 0.60)
                    ]),
                    startPoint: CGPoint(x: pivotX, y: midY - 12),
                    endPoint: CGPoint(x: tipX, y: tipY + 12)
                )
            )
            ctx.stroke(arm, with: .color(Color.white.opacity(0.35)), lineWidth: 1.0)

            // Pivot Cap Screw
            let capR: CGFloat = 9
            ctx.fill(
                Path(ellipseIn: CGRect(x: pivotX - capR, y: midY - capR, width: capR * 2, height: capR * 2)),
                with: .color(steelColor)
            )

            // 6. Tactile Contoured Thumb Grip Pad at Lever Tip
            let baseR: CGFloat = isDragging ? 15.5 : (idlePulse ? 14.0 : 13.0)
            let padR = baseR * (isLatchedHold ? heartbeatScale : 1.0)
            let glowR = padR * 1.45
            ctx.fill(
                Path(ellipseIn: CGRect(x: tipX - glowR, y: tipY - glowR, width: glowR * 2, height: glowR * 2)),
                with: .color(Palette.accent.opacity(isLatchedHold ? 0.45 : (isDragging ? 0.30 : 0.14)))
            )
            ctx.fill(
                Path(ellipseIn: CGRect(x: tipX - padR, y: tipY - padR, width: padR * 2, height: padR * 2)),
                with: .color(Palette.accent)
            )

            // Knurled grip chevron on thumb pad
            var chev = Path()
            chev.move(to: CGPoint(x: tipX - 2.5, y: tipY - 5))
            chev.addLine(to: CGPoint(x: tipX + 3.5, y: tipY))
            chev.addLine(to: CGPoint(x: tipX - 2.5, y: tipY + 5))
            ctx.stroke(
                chev,
                with: .color(Palette.accentInk),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Clean, De-Bloated Camera Body & Optical Lens Tiles (Zero Repeated Canvas Overhead)

private struct CleanCameraBodyTile: View {
    let camera: CameraGearSpec
    let isStaged: Bool
    let onSelect: () -> Void

    private var strippedModelName: String {
        var name = camera.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasPrefix(camera.brand.lowercased() + " ") {
            name = String(name.dropFirst(camera.brand.count + 1))
        }
        return name.isEmpty ? camera.model : name
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(strippedModelName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isStaged ? Palette.accent : Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Spacer(minLength: 4)

                    if isStaged {
                        Circle()
                            .fill(Palette.accent)
                            .frame(width: 6, height: 6)
                    }
                }

                Text(camera.isFixed
                     ? (camera.fixedLensName.isEmpty ? "Fixed Lens" : cleanLensDisplayName(camera.fixedLensName, brand: camera.brand))
                     : "\(formatMountBadge(camera.mount)) · \(shutterRangeText(camera.minShutter, camera.maxShutter))")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Palette.textSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isStaged ? Palette.accent.opacity(0.14) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isStaged ? Palette.accent.opacity(0.75) : Color.white.opacity(0.06),
                                lineWidth: isStaged ? 1.5 : 1.0
                            )
                    )
            )
        }
        .buttonStyle(PressStyle(scale: 0.96))
    }
}

private struct CleanOpticalLensTile: View {
    let entry: PrewarmedLensEntry
    let isStaged: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(cleanLensDisplayName(entry.lens.model, brand: entry.lens.brand))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(isStaged ? Palette.accent : Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Spacer(minLength: 4)

                    if isStaged {
                        Circle()
                            .fill(Palette.accent)
                            .frame(width: 6, height: 6)
                    }
                }

                HStack(spacing: 4) {
                    Text("\(entry.lens.brand) · \(formatApertureRange(entry.lens.minAperture, entry.lens.maxAperture))")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Palette.textSub)
                        .lineLimit(1)

                    if entry.variants.count > 1 {
                        Text("· \(entry.variants.count)v")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.accent.opacity(0.85))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isStaged ? Palette.accent.opacity(0.14) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isStaged ? Palette.accent.opacity(0.75) : Color.white.opacity(0.06),
                                lineWidth: isStaged ? 1.5 : 1.0
                            )
                    )
            )
        }
        .buttonStyle(PressStyle(scale: 0.96))
    }
}

// MARK: - Shared Formatting Helpers

func shutterRangeText(_ first: Double, _ second: Double) -> String {
    let slow = max(first, second)
    let fast = min(first, second)
    return "\(formatShutterStopLabel(slow))–\(formatShutterStopLabel(fast))"
}

/// Preserves the iconic optical family name (e.g. "Summicron-M 35mm f/2", "Elmarit-M 28mm f/2.8", "Biogon 28mm f/2.8")
/// while stripping redundant brand prefixes and dual-generation slash noise.
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
