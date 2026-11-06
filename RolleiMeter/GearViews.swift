import Foundation
import SwiftUI
import UIKit

// MARK: - Unified Interactive Camera & Bayonet Lens-Mount Studio

struct CameraLensView: View {
    @ObservedObject var store: FilmLogStore
    var onFinish: () -> Void = {}

    private enum TrayMode: String, CaseIterable {
        case bodies = "Cameras"
        case lenses = "Lenses"
    }

    private enum MountSetup: String, CaseIterable {
        case matched = "Lens"
        case bodyOnly = "Body Only"
        case adapter = "Adapted"
    }

    @State private var trayMode: TrayMode = .bodies
    @State private var selectedBrand: String = "All"
    @State private var focalFilter: FocalLengthCategory = .all
    @State private var allowAdaptedMounts: Bool = false
    @State private var searchText: String = ""

    @State private var stagedCamera: CameraGearSpec = GearCatalogCache.loadBundledCatalog().cameras[0]
    @State private var stagedLensEntry: PrewarmedLensEntry? = nil
    @State private var stagedVariantID: String = ""
    @State private var mountSetup: MountSetup = .matched
    @State private var didInitialize: Bool = false
    @State private var showRemoveConfirm: Bool = false

    private let popularBrands: [String] = [
        "All", "Leica", "Nikon", "Canon", "Pentax", "Olympus", "Minolta",
        "Contax", "Hasselblad", "Rollei", "Mamiya", "Fujifilm", "Voigtländer",
        "Yashica", "Ricoh", "Konica", "Custom", "Other"
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
        case .adapter:
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
                lensId: "\(stagedCamera.id)_adapter",
                lensName: "Adapted lens",
                minAperture: 1.4,
                maxAperture: 22.0,
                apertureStops: [1.4, 2.0, 2.8, 4.0, 5.6, 8.0, 11.0, 16.0, 22.0]
            )
        case .matched:
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

    private var filteredCameras: [CameraGearSpec] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let pool: [CameraGearSpec]
        if !q.isEmpty {
            pool = allCameras
                .map { ($0, fuzzyMatchScore(query: q, target: "\($0.brand) \($0.model) \($0.mount) \($0.fixedLensName)")) }
                .filter { $0.1 > 0 }
                .sorted { $0.1 > $1.1 }
                .map { $0.0 }
        } else {
            switch selectedBrand {
            case "All":
                pool = allCameras
            case "Custom":
                pool = allCameras.filter { $0.isCustom }
            case "Other":
                let mainSet = Set(popularBrands)
                pool = allCameras.filter { !mainSet.contains($0.brand) && !$0.isCustom }
            default:
                pool = allCameras.filter { $0.brand.caseInsensitiveCompare(selectedBrand) == .orderedSame }
            }
        }
        return pool
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
                // ── ONE UNIFIED CAMERA BAYONET BENCH & GEAR TURRET CHASSIS ──
                VStack(spacing: 0) {
                    // PART A: Upper Interactive Bayonet Mount & 9-Blade Iris Optical Bench
                    VStack(alignment: .leading, spacing: 14) {
                        // Top Rig Header: Brand Logo + Staged Camera & Lens Summary + Setup Pill
                        HStack(alignment: .center, spacing: 12) {
                            CameraBrandLogo(brand: stagedCamera.brand, size: 42)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(stagedCamera.model)
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(Palette.text)
                                        .lineLimit(1)

                                    if isStagedComboCurrentlyMounted {
                                        Text("ACTIVE")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Palette.good.opacity(0.20), in: Capsule())
                                            .foregroundStyle(Palette.good)
                                    }
                                }

                                let preview = resolvedPreviewProfile
                                Text(preview.hasLens ? preview.lensName : (stagedCamera.isFixed ? "Fixed Lens" : "\(formatMountBadge(stagedCamera.mount)) Body Only"))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(preview.hasLens ? Palette.accent : Palette.textSub)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 4)

                            if !stagedCamera.isFixed {
                                Menu {
                                    Picker("Mount Setup", selection: $mountSetup) {
                                        Text("Matched Mount (\(formatMountBadge(stagedCamera.mount)))").tag(MountSetup.matched)
                                        Text("Adapted Lens (Any Mount)").tag(MountSetup.adapter)
                                        Text("Body Only (Unclamped Lens)").tag(MountSetup.bodyOnly)
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(mountSetup == .matched ? formatMountBadge(stagedCamera.mount) : mountSetup.rawValue)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.08), in: Capsule())
                                    .foregroundStyle(Palette.textSub)
                                }
                            } else {
                                Text("FIXED LENS")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Color.white.opacity(0.07), in: Capsule())
                                    .foregroundStyle(Palette.textSub)
                            }
                        }

                        // Inline Vintage Lens Generation Pills (e.g. ASPH vs Pre-ASPH, AI-S vs AI vs Pre-AI, nFD vs Breech-Lock)
                        if !stagedCamera.isFixed,
                           mountSetup != .bodyOnly,
                           let entry = stagedLensEntry,
                           entry.variants.count > 1 {
                            HStack(spacing: 6) {
                                ForEach(entry.variants) { variant in
                                    let selected = (variant.id == stagedVariantID) || (stagedVariantID.isEmpty && variant.id == entry.variants.first?.id)
                                    Button {
                                        Haptics.tap()
                                        withAnimation(.spring(response: 0.26, dampingFraction: 0.65)) {
                                            stagedVariantID = variant.id
                                        }
                                    } label: {
                                        Text(variant.badge)
                                            .font(.caption2.weight(selected ? .bold : .medium))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.75)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule()
                                                    .fill(selected ? Palette.accent : Color.white.opacity(0.07))
                                            )
                                            .foregroundStyle(selected ? Palette.accentInk : Palette.textSub)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // The Interactive Bayonet Twist-to-Mount & 9-Blade Iris Optical Bench
                        InteractiveBayonetMountBench(
                            brand: stagedCamera.brand,
                            cameraModel: stagedCamera.model,
                            lensName: resolvedPreviewProfile.hasLens ? resolvedPreviewProfile.lensName : "Body Only",
                            mountBadge: stagedCamera.isFixed ? "FIXED" : formatMountBadge(stagedCamera.mount),
                            shutterRange: shutterRangeText(stagedCamera.minShutter, stagedCamera.maxShutter),
                            apertureRange: formatApertureRange(resolvedPreviewProfile.minAperture, resolvedPreviewProfile.maxAperture),
                            minAperture: resolvedPreviewProfile.minAperture,
                            maxAperture: resolvedPreviewProfile.maxAperture,
                            apertureStops: clampApertureStopsForGear(resolvedPreviewProfile).map(\.n),
                            isFixedLens: stagedCamera.isFixed,
                            isAlreadyMounted: isStagedComboCurrentlyMounted
                        ) {
                            commitStagedGear()
                        }
                    }
                    .padding(16)

                    // Machined Seam Connecting the Optical Bench to the Gear Turret Tray
                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 1)

                    // PART B: Connected Dual-Mode Physical Camera & Lens Turret Tray
                    VStack(alignment: .leading, spacing: 14) {
                        // Mode Switcher: [ Cameras ] vs [ Lenses ] + Add Custom Gear Button
                        HStack(spacing: 10) {
                            HStack(spacing: 4) {
                                ForEach(TrayMode.allCases, id: \.self) { mode in
                                    let active = (trayMode == mode)
                                    let disabled = (mode == .lenses && stagedCamera.isFixed)
                                    Button {
                                        guard !disabled else { return }
                                        Haptics.tap()
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                            trayMode = mode
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: mode == .bodies ? "camera.fill" : "camera.aperture")
                                                .font(.system(size: 12, weight: .bold))
                                            Text(mode.rawValue)
                                                .font(.caption.weight(.bold))
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(
                                            Capsule()
                                                .fill(active ? Palette.accent : Color.clear)
                                        )
                                        .foregroundStyle(active ? Palette.accentInk : (disabled ? Palette.faint : Palette.textSub))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(disabled)
                                }
                            }
                            .padding(3)
                            .background(Color.black.opacity(0.45), in: Capsule())

                            Spacer()

                            NavigationLink {
                                CustomGearForm(
                                    store: store,
                                    onFinish: onFinish,
                                    presetKinds: trayMode == .lenses ? [.lens] : [.fixedLens, .body],
                                    presetBrand: selectedBrand == "All" || selectedBrand == "Custom" || selectedBrand == "Other" ? "" : selectedBrand
                                )
                            } label: {
                                Label("Custom", systemImage: "plus")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.08), in: Capsule())
                                    .foregroundStyle(Palette.accent)
                            }
                            .buttonStyle(.plain)
                        }

                        if trayMode == .bodies || stagedCamera.isFixed {
                            cameraBodiesTrayContent
                        } else {
                            opticalLensesTurretContent
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
        .searchable(text: $searchText, prompt: trayMode == .bodies ? "Search camera bodies" : "Search optical lenses")
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

    // MARK: - Camera Bodies Tray Content

    @ViewBuilder
    private var cameraBodiesTrayContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Horizontal Brand Medallion Strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(popularBrands, id: \.self) { brand in
                        let isSelected = (selectedBrand == brand)
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.snappy(duration: 0.20)) {
                                selectedBrand = brand
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if brand != "All" && brand != "Custom" && brand != "Other" {
                                    CameraBrandLogo(brand: brand, size: 20)
                                }
                                Text(brand)
                                    .font(.caption.weight(isSelected ? .bold : .medium))
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Palette.accent : Color.white.opacity(0.06))
                            )
                            .foregroundStyle(isSelected ? Palette.accentInk : Palette.textSub)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // 2-Column Tactile Camera Body Cards Grid
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(filteredCameras) { cam in
                    let isStaged = (stagedCamera.id == cam.id)
                    PhysicalCameraBodySlotCard(
                        camera: cam,
                        isStaged: isStaged
                    ) {
                        Haptics.rigid()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.64)) {
                            selectCameraForBench(cam)
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
        }
    }

    // MARK: - Optical Lenses Turret Content

    @ViewBuilder
    private var opticalLensesTurretContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Mount Filter Toggle + Focal Length Turret Strip
            HStack {
                Text(allowAdaptedMounts ? "ALL MOUNTS (ADAPTED)" : "\(formatMountBadge(stagedCamera.mount).uppercased()) MOUNT OPTICS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(Palette.accent)

                Spacer()

                Button {
                    Haptics.tap()
                    withAnimation(.snappy(duration: 0.2)) {
                        allowAdaptedMounts.toggle()
                        if allowAdaptedMounts { mountSetup = .adapter } else { mountSetup = .matched }
                    }
                } label: {
                    Text(allowAdaptedMounts ? "Native Mount Only" : "Show All Mounts")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.textSub)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)
            }

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
                            Text(cat == .all ? "All" : (cat == .zoom ? "Zoom" : "\(cat.label)mm"))
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

            // 2-Column Tactile Optical Lens Barrel Cards Grid
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(filteredLenses) { entry in
                    let isStaged = (stagedLensEntry?.id == entry.id && mountSetup != .bodyOnly)
                    PhysicalLensBarrelSlotCard(
                        entry: entry,
                        displayTitle: lensRowTitle(entry),
                        isStaged: isStaged
                    ) {
                        Haptics.rigid()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) {
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

    // MARK: - Staging & Mounting Helpers

    private func selectCameraForBench(_ cam: CameraGearSpec) {
        stagedCamera = cam
        if cam.isFixed {
            trayMode = .bodies
            stagedLensEntry = nil
            stagedVariantID = ""
            mountSetup = .matched
        } else {
            // Auto-stage a matching native lens if the current staged lens doesn't match the new body's mount
            let matching = allLenses.filter { $0.lens.mount.caseInsensitiveCompare(cam.mount) == .orderedSame }
            if let current = stagedLensEntry,
               current.lens.mount.caseInsensitiveCompare(cam.mount) == .orderedSame {
                // Keep current compatible lens
            } else if let std50 = matching.first(where: { $0.focalLengthMm >= 45 && $0.focalLengthMm <= 58 }) ?? matching.first {
                stagedLensEntry = std50
                stagedVariantID = std50.variants.first?.id ?? ""
                mountSetup = .matched
            } else {
                stagedLensEntry = nil
                mountSetup = .bodyOnly
            }
        }
    }

    private func syncStagedWithActiveGearIfNeeded() {
        guard !didInitialize else { return }
        didInitialize = true
        let active = store.activeGear
        if let matchCam = allCameras.first(where: { $0.id == active.cameraId }) {
            stagedCamera = matchCam
            selectedBrand = popularBrands.contains(matchCam.brand) ? matchCam.brand : "All"
        } else if let firstCam = allCameras.first {
            stagedCamera = firstCam
        }

        guard !stagedCamera.isFixed else { return }

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

        // Default to a matching lens for the staged body if available
        let matching = allLenses.filter { $0.lens.mount.caseInsensitiveCompare(stagedCamera.mount) == .orderedSame }
        if let firstMatch = matching.first(where: { $0.focalLengthMm >= 45 && $0.focalLengthMm <= 58 }) ?? matching.first {
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

// MARK: - Interactive Bayonet Twist-to-Mount & 9-Blade Iris Optical Bench

private struct InteractiveBayonetMountBench: View {
    let brand: String
    let cameraModel: String
    let lensName: String
    let mountBadge: String
    let shutterRange: String
    let apertureRange: String
    let minAperture: Double
    let maxAperture: Double
    let apertureStops: [Double]
    let isFixedLens: Bool
    let isAlreadyMounted: Bool
    var onMountComplete: () -> Void

    @State private var twistProgress: CGFloat = 0.0
    @State private var isDragging: Bool = false
    @State private var isLatchedHold: Bool = false
    @State private var heartbeatScale: CGFloat = 1.0
    @State private var heartbeatTask: Task<Void, Never>? = nil

    // 3-Stage Grand Lock & Shutter Calibration Ceremony States
    @State private var ceremonyPhase: Int = 0 // 0 = interactive, 1 = pin locked, 2 = iris sweep & shutter fire, 3 = confirmed
    @State private var irisOverride: CGFloat? = nil
    @State private var shutterFiredProgress: CGFloat = 0.0
    @State private var pinLockPop: CGFloat = 0.0
    @State private var swapBounce: CGFloat = 0.0
    @State private var lastDetentStep: Int = 0

    private let latchThreshold: CGFloat = 0.82

    // Normalized wide-open iris ratio (f/1.2 -> 0.82 wide open, f/4 -> 0.48)
    private var baseIrisOpenness: CGFloat {
        let clampedF = min(max(minAperture, 0.95), 8.0)
        let norm = 1.0 - (log2(clampedF) / log2(11.0))
        return CGFloat(min(max(norm, 0.35), 0.85))
    }

    // Live iris opening responds as you twist the bayonet barrel
    private var currentIrisOpenness: CGFloat {
        if let override = irisOverride { return override }
        let stopDownWave = sin(Double(twistProgress) * .pi) * 0.42
        return max(0.18, baseIrisOpenness - CGFloat(stopDownWave))
    }

    var body: some View {
        let brandColor = resolveBrandToneColor(brand)

        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(red: 0.035, green: 0.038, blue: 0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(
                                ceremonyPhase == 3
                                    ? Palette.good.opacity(0.80)
                                    : (isLatchedHold ? Palette.accent.opacity(0.85) : Color.white.opacity(0.08)),
                                lineWidth: isLatchedHold || ceremonyPhase > 0 ? 1.5 : 1.0
                            )
                    )

                HStack(spacing: 16) {
                    // LEFT: Front-View Machined Bayonet Flange, Rotating Lens Barrel & 9-Blade Geometric Iris
                    BayonetIrisOpticalDial(
                        twistProgress: twistProgress,
                        latchThreshold: latchThreshold,
                        irisOpenness: currentIrisOpenness,
                        shutterFiredProgress: shutterFiredProgress,
                        brandColor: brandColor,
                        isLatchedHold: isLatchedHold,
                        heartbeatScale: heartbeatScale,
                        pinLockPop: pinLockPop,
                        ceremonyPhase: ceremonyPhase
                    )
                    .frame(width: 124, height: 124)
                    .scaleEffect(1.0 + swapBounce * 0.08)

                    // RIGHT: Live Engraved Optical Telemetry & Twist-to-Mount Track
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(ceremonyPhase == 3 ? Palette.good : (isLatchedHold ? Palette.accent : brandColor))
                                .frame(width: 6.5, height: 6.5)
                                .scaleEffect(isLatchedHold ? heartbeatScale : 1.0)

                            Text(ceremonyPhase == 3 ? "RIG CALIBRATED & LOCKED" : "\(mountBadge) BAYONET MOUNT")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(ceremonyPhase == 3 ? Palette.good : (isLatchedHold ? Palette.accent : Palette.textSub))
                        }

                        // Clamped Shutter & Aperture Hardware Limits Preview
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("SHUTTER DIAL")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Palette.textDim)
                                Text(shutterRange)
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(Palette.text)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 9, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("APERTURE RING")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Palette.textDim)
                                Text(apertureRange)
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(Palette.accent)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 9, style: .continuous))
                        }

                        // Physical F-Stop Detent Strip Preview
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(Array(apertureStops.enumerated()), id: \.offset) { idx, stop in
                                    let activeIdx = Int((twistProgress * CGFloat(max(apertureStops.count - 1, 1))).rounded())
                                    let highlighted = isDragging && (idx == activeIdx)
                                    Text(formatApertureStopLabel(stop).replacingOccurrences(of: "f/", with: ""))
                                        .font(.system(size: 10, weight: highlighted ? .bold : .medium).monospacedDigit())
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(highlighted ? Palette.accent : Color.white.opacity(0.05))
                                        )
                                        .foregroundStyle(highlighted ? Palette.accentInk : Palette.textSub)
                                }
                            }
                        }
                        .allowsHitTesting(false)

                        // Knurled Bayonet Twist-Lock Track
                        BayonetTwistTrackBar(
                            twistProgress: twistProgress,
                            latchThreshold: latchThreshold,
                            isDragging: isDragging,
                            isLatchedHold: isLatchedHold,
                            heartbeatScale: heartbeatScale,
                            ceremonyPhase: ceremonyPhase
                        )
                    }
                }
                .padding(14)

                // Full-Bench Interactive Twist/Drag Gesture (User stays in 100% control until release)
                if ceremonyPhase == 0 {
                    GeometryReader { geo in
                        let travel = max(geo.size.width - 90, 1)
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if !isDragging {
                                            isDragging = true
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)
                                        }

                                        let raw = value.translation.width / (travel * 0.62)
                                        let posFromX = (value.location.x - 45) / travel
                                        let combined = max(raw, posFromX)
                                        let clamped = min(max(combined, 0.0), 1.0)

                                        if clamped >= latchThreshold {
                                            let magnet = latchThreshold + (clamped - latchThreshold) * 0.45
                                            twistProgress = min(max(magnet, latchThreshold), 0.96)
                                            if !isLatchedHold {
                                                enterBayonetHeartbeat()
                                            }
                                        } else {
                                            if isLatchedHold {
                                                exitBayonetHeartbeat()
                                            }
                                            twistProgress = clamped
                                            let step = Int(clamped * 16)
                                            if step != lastDetentStep {
                                                lastDetentStep = step
                                                UISelectionFeedbackGenerator().selectionChanged()
                                            }
                                        }
                                    }
                                    .onEnded { _ in
                                        isDragging = false
                                        if twistProgress >= latchThreshold {
                                            exitBayonetHeartbeat()
                                            runGrandBayonetLockCeremony()
                                        } else {
                                            exitBayonetHeartbeat()
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
                                            withAnimation(.spring(response: 0.36, dampingFraction: 0.54)) {
                                                twistProgress = 0.0
                                            }
                                            lastDetentStep = 0
                                        }
                                    }
                            )
                    }
                }
            }
            .frame(height: 152)

            // Bottom Status & Instruction Line
            HStack {
                Text(benchStatusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ceremonyPhase == 3 ? Palette.good : (isLatchedHold || ceremonyPhase > 0 ? Palette.accent : .secondary))
                    .contentTransition(.numericText())

                Spacer()

                if isLatchedHold {
                    Text("SLIDE LEFT TO CANCEL")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
        .onDisappear {
            heartbeatTask?.cancel()
            heartbeatTask = nil
        }
        .onChange(of: cameraModel) { _, _ in
            triggerSwapBounce()
        }
        .onChange(of: lensName) { _, _ in
            triggerSwapBounce()
        }
    }

    private var benchStatusText: String {
        switch ceremonyPhase {
        case 1: return "LOCKING BAYONET PIN & COUPLING LINKAGE…"
        case 2: return "CALIBRATING 9-BLADE IRIS & SHUTTER CURTAIN…"
        case 3: return "MOUNTED · \(cameraModel.uppercased()) READY"
        default:
            if isLatchedHold {
                return "BAYONET ALIGNED · RELEASE FINGER TO LOCK PIN"
            }
            if twistProgress > 0.04 {
                let deg = Int((twistProgress / latchThreshold * 60.0).rounded()).clamped(to: 1...60)
                return "ROTATING BAYONET RING · \(deg)° / 60°"
            }
            return isAlreadyMounted ? "TWIST BAYONET RING TO RE-CALIBRATE RIG →" : "TWIST BAYONET RING TO LOCK CAMERA & LENS →"
        }
    }

    private func triggerSwapBounce() {
        guard ceremonyPhase == 0 else { return }
        exitBayonetHeartbeat()
        swapBounce = 1.0
        withAnimation(.spring(response: 0.32, dampingFraction: 0.48)) {
            swapBounce = 0.0
            twistProgress = 0.0
        }
    }

    private func enterBayonetHeartbeat() {
        isLatchedHold = true
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.85)
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor in
            while !Task.isCancelled && isLatchedHold {
                withAnimation(.easeInOut(duration: 0.32)) {
                    heartbeatScale = 1.14
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

    private func exitBayonetHeartbeat() {
        isLatchedHold = false
        heartbeatTask?.cancel()
        heartbeatTask = nil
        withAnimation(.easeOut(duration: 0.2)) {
            heartbeatScale = 1.0
        }
    }

    private func runGrandBayonetLockCeremony() {
        guard ceremonyPhase == 0 else { return }
        ceremonyPhase = 1

        // Stage 1: Snap bayonet ring to 100% and lock the chrome pin (0.0s -> 0.5s)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1.0)
        pinLockPop = 1.0
        withAnimation(.spring(response: 0.24, dampingFraction: 0.62)) {
            twistProgress = 1.0
        }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.45)) {
            pinLockPop = 0.0
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))

            // Stage 2: 9-Blade Iris Stop-Down Sweep + High-Speed Shutter Actuation (0.5s -> 1.75s)
            ceremonyPhase = 2
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                irisOverride = 0.16 // Stop down to minimum aperture
            }
            for _ in 0..<3 {
                try? await Task.sleep(for: .milliseconds(75))
                UISelectionFeedbackGenerator().selectionChanged()
            }

            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(.spring(response: 0.30, dampingFraction: 0.62)) {
                irisOverride = baseIrisOpenness // Spring back wide-open
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.8)

            // Fire the mechanical shutter blades across the throat
            try? await Task.sleep(for: .milliseconds(220))
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1.0)
            withAnimation(.easeIn(duration: 0.08)) {
                shutterFiredProgress = 1.0
            }
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(.spring(response: 0.24, dampingFraction: 0.68)) {
                shutterFiredProgress = 0.0
            }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.9)

            // Stage 3: Locked & Calibrated Confirmation (1.75s -> 2.55s)
            try? await Task.sleep(for: .milliseconds(180))
            ceremonyPhase = 3
            UINotificationFeedbackGenerator().notificationOccurred(.success)

            try? await Task.sleep(for: .milliseconds(750))
            onMountComplete()

            try? await Task.sleep(for: .milliseconds(250))
            ceremonyPhase = 0
            irisOverride = nil
            twistProgress = 0.0
        }
    }
}

// MARK: - Front-View Bayonet Mount & 9-Blade Geometric Iris Canvas

private struct BayonetIrisOpticalDial: View {
    let twistProgress: CGFloat
    let latchThreshold: CGFloat
    let irisOpenness: CGFloat
    let shutterFiredProgress: CGFloat
    let brandColor: Color
    let isLatchedHold: Bool
    let heartbeatScale: CGFloat
    let pinLockPop: CGFloat
    let ceremonyPhase: Int

    var body: some View {
        let isAligned = twistProgress >= latchThreshold || ceremonyPhase > 0
        let normalizedTwist = min(max(twistProgress / max(latchThreshold, 0.01), 0.0), 1.0)
        let barrelDegrees = -60.0 + Double(normalizedTwist) * 60.0 // Rotates from -60° to 0° (top-center lock)

        ZStack {
            Canvas { ctx, size in
                let cx = size.width * 0.5
                let cy = size.height * 0.5
                let center = CGPoint(x: cx, y: cy)
                let outerR = min(cx, cy) - 2

                // 1. Machined Stainless-Steel Camera Body Mount Flange
                let flangeRect = CGRect(x: cx - outerR, y: cy - outerR, width: outerR * 2, height: outerR * 2)
                ctx.fill(
                    Path(ellipseIn: flangeRect),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.26, green: 0.28, blue: 0.33),
                            Color(red: 0.12, green: 0.13, blue: 0.16),
                            Color(red: 0.22, green: 0.24, blue: 0.28)
                        ]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: size.width, y: size.height)
                    )
                )
                ctx.stroke(
                    Path(ellipseIn: flangeRect),
                    with: .color(ceremonyPhase == 3 ? Palette.good : (isAligned ? Palette.accent : Color.white.opacity(0.22))),
                    lineWidth: isAligned ? 2.0 : 1.2
                )

                // Fixed Top-Center Camera Body Alignment Dot & Locking Pin
                let bodyDotY = cy - outerR + 5.5
                let bodyDotR: CGFloat = 3.2 + pinLockPop * 2.0
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - bodyDotR, y: bodyDotY - bodyDotR, width: bodyDotR * 2, height: bodyDotR * 2)),
                    with: .color(ceremonyPhase == 3 ? Palette.good : (isAligned ? Palette.accent : Color(red: 0.92, green: 0.20, blue: 0.20)))
                )

                // 2. Rotating Knurled Outer Lens Barrel & Bayonet Lugs
                let barrelR = outerR - 11
                var barrelCtx = ctx
                barrelCtx.translateBy(x: cx, y: cy)
                barrelCtx.rotate(by: .degrees(barrelDegrees))

                let barrelRect = CGRect(x: -barrelR, y: -barrelR, width: barrelR * 2, height: barrelR * 2)
                barrelCtx.fill(Path(ellipseIn: barrelRect), with: .color(Color(red: 0.06, green: 0.07, blue: 0.09)))
                barrelCtx.stroke(Path(ellipseIn: barrelRect), with: .color(Color.white.opacity(0.18)), lineWidth: 1.5)

                // Knurled grip ridges around rotating lens barrel
                let ridgeCount = 36
                for i in 0..<ridgeCount {
                    let a = Double(i) * (2.0 * .pi / Double(ridgeCount))
                    let isLug = (i % 12 < 3)
                    let r1 = barrelR - (isLug ? 4.5 : 2.5)
                    let r2 = barrelR
                    var tick = Path()
                    tick.move(to: CGPoint(x: CGFloat(cos(a)) * r1, y: CGFloat(sin(a)) * r1))
                    tick.addLine(to: CGPoint(x: CGFloat(cos(a)) * r2, y: CGFloat(sin(a)) * r2))
                    barrelCtx.stroke(
                        tick,
                        with: .color(isLug ? Color.white.opacity(0.42) : Color.white.opacity(0.16)),
                        lineWidth: isLug ? 2.0 : 1.0
                    )
                }

                // Rotating Lens Red Alignment Dot (meets the top body dot at 0°)
                let lensDotR: CGFloat = 3.2
                let lensDotY = -barrelR + 5.5
                barrelCtx.fill(
                    Path(ellipseIn: CGRect(x: -lensDotR, y: lensDotY - lensDotR, width: lensDotR * 2, height: lensDotR * 2)),
                    with: .color(isAligned ? Palette.accent : Color(red: 0.95, green: 0.22, blue: 0.22))
                )

                // 3. Deep Optical Glass Throat & 9-Blade Geometric Aperture Iris
                let glassR = barrelR - 11
                let glassRect = CGRect(x: cx - glassR, y: cy - glassR, width: glassR * 2, height: glassR * 2)
                let glassPath = Path(ellipseIn: glassRect)
                ctx.fill(glassPath, with: .color(Color(red: 0.02, green: 0.03, blue: 0.05)))

                var irisCtx = ctx
                irisCtx.clip(to: glassPath)

                // 9 Overlapping Geometric Aperture Blades
                let bladeCount = 9
                let apertureR = glassR * min(max(irisOpenness, 0.14), 0.88)
                let bladeTwist = Double(1.0 - irisOpenness) * 0.65

                // Fill outer blade ring
                var irisRing = Path()
                irisRing.addEllipse(in: glassRect)
                irisRing.addEllipse(in: CGRect(x: cx - apertureR, y: cy - apertureR, width: apertureR * 2, height: apertureR * 2))
                irisCtx.fill(irisRing, with: .color(Color(red: 0.09, green: 0.10, blue: 0.12)), style: FillStyle(eoFill: true))

                // Draw the 9 individual overlapping blade edges & pivot pins
                for bIdx in 0..<bladeCount {
                    let a1 = Double(bIdx) * (2.0 * .pi / Double(bladeCount)) + bladeTwist
                    let a2 = a1 + 1.18
                    let p1 = CGPoint(
                        x: cx + CGFloat(cos(a1)) * apertureR,
                        y: cy + CGFloat(sin(a1)) * apertureR
                    )
                    let p2 = CGPoint(
                        x: cx + CGFloat(cos(a2)) * (glassR + 4),
                        y: cy + CGFloat(sin(a2)) * (glassR + 4)
                    )
                    var edge = Path()
                    edge.move(to: p1)
                    edge.addLine(to: p2)
                    irisCtx.stroke(edge, with: .color(Color.white.opacity(0.22)), lineWidth: 1.1)
                }

                // 4. Multi-Coated Optical Glass Reflections (Zeiss T* / S.S.C. Cyan-Violet-Amber Sheen)
                let coatShift = CGFloat(normalizedTwist) * 14.0
                let reflRect1 = CGRect(x: cx - glassR * 0.72 + coatShift * 0.4, y: cy - glassR * 0.75, width: glassR * 1.1, height: glassR * 0.65)
                irisCtx.fill(
                    Path(ellipseIn: reflRect1),
                    with: .linearGradient(
                        Gradient(colors: [
                            brandColor.opacity(0.24),
                            Color(red: 0.15, green: 0.75, blue: 0.95).opacity(0.16),
                            .clear
                        ]),
                        startPoint: CGPoint(x: reflRect1.minX, y: reflRect1.minY),
                        endPoint: CGPoint(x: reflRect1.maxX, y: reflRect1.maxY)
                    )
                )

                // 5. Mechanical Shutter Curtain Actuation Flash (during Stage 2 Ceremony)
                if shutterFiredProgress > 0.01 {
                    let curtainH = glassR * 2 * shutterFiredProgress
                    irisCtx.fill(
                        Path(CGRect(x: cx - glassR, y: cy - glassR, width: glassR * 2, height: curtainH)),
                        with: .color(Color(red: 0.18, green: 0.19, blue: 0.22))
                    )
                    irisCtx.fill(
                        glassPath,
                        with: .color(Color.white.opacity(Double(shutterFiredProgress) * 0.35))
                    )
                }

                ctx.stroke(glassPath, with: .color(Color.white.opacity(0.16)), lineWidth: 1.0)
            }
        }
        .scaleEffect(isLatchedHold ? heartbeatScale : 1.0)
        .allowsHitTesting(false)
    }
}

// MARK: - Knurled Bayonet Twist-Lock Track Bar

private struct BayonetTwistTrackBar: View {
    let twistProgress: CGFloat
    let latchThreshold: CGFloat
    let isDragging: Bool
    let isLatchedHold: Bool
    let heartbeatScale: CGFloat
    let ceremonyPhase: Int

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let h = geo.size.height
            let thumbW: CGFloat = 44
            let usable = max(w - thumbW - 6, 1)
            let xOff = 3 + usable * min(max(twistProgress, 0), 1)
            let ready = twistProgress >= latchThreshold || isLatchedHold || ceremonyPhase > 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.65))
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                ceremonyPhase == 3 ? Palette.good.opacity(0.7) : (ready ? Palette.accent.opacity(0.75) : Color.white.opacity(0.10)),
                                lineWidth: 1.0
                            )
                    )

                // Progress fill
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                (ceremonyPhase == 3 ? Palette.good : Palette.accent).opacity(0.15),
                                (ceremonyPhase == 3 ? Palette.good : Palette.accent).opacity(0.38)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: xOff + thumbW * 0.5)

                HStack {
                    Spacer()
                    Text(ceremonyPhase == 3 ? "LOCKED" : (ready ? "RELEASE TO LOCK" : "TWIST RING →"))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(ceremonyPhase == 3 ? Palette.good : (ready ? Palette.accent : Palette.textDim))
                        .padding(.trailing, 14)
                }

                // Knurled Bayonet Lug Thumb
                ZStack {
                    Capsule()
                        .fill(ceremonyPhase == 3 ? Palette.good : Palette.accent)

                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule()
                                .fill(Palette.accentInk.opacity(0.65))
                                .frame(width: 2, height: 12)
                        }
                    }
                }
                .frame(width: thumbW, height: h - 6)
                .scaleEffect(isLatchedHold ? heartbeatScale : (isDragging ? 1.06 : 1.0))
                .offset(x: xOff)
            }
        }
        .frame(height: 30)
        .allowsHitTesting(false)
    }
}

// MARK: - Physical Camera Body & Optical Lens Slot Cards

private struct PhysicalCameraBodySlotCard: View {
    let camera: CameraGearSpec
    let isStaged: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    CameraBrandLogo(brand: camera.brand, size: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(camera.brand.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(isStaged ? Palette.accent : Palette.textDim)
                            .lineLimit(1)

                        Text(camera.isFixed ? "FIXED" : formatMountBadge(camera.mount))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.textSub)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                Text(camera.model)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isStaged ? Palette.accent : Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(camera.isFixed && !camera.fixedLensName.isEmpty
                     ? camera.fixedLensName
                     : "Shutter \(shutterRangeText(camera.minShutter, camera.maxShutter))")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Palette.textSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isStaged ? Palette.accent.opacity(0.14) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                isStaged ? Palette.accent.opacity(0.75) : Color.white.opacity(0.06),
                                lineWidth: isStaged ? 1.5 : 1.0
                            )
                    )
            )
        }
        .buttonStyle(PressStyle(scale: 0.95))
    }
}

private struct PhysicalLensBarrelSlotCard: View {
    let entry: PrewarmedLensEntry
    let displayTitle: String
    let isStaged: Bool
    let onSelect: () -> Void

    private var glassRatio: CGFloat {
        let f = min(max(entry.lens.minAperture, 0.95), 5.6)
        return CGFloat(min(max(1.0 - (f - 0.95) / 6.5, 0.42), 0.86))
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    // Miniature Front-Element Optical Barrel Icon
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.7))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        isStaged ? Palette.accent : Color.white.opacity(0.22),
                                        style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2.0])
                                    )
                            )

                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        resolveBrandToneColor(entry.lens.brand).opacity(0.45),
                                        Color(red: 0.10, green: 0.55, blue: 0.75).opacity(0.25),
                                        Color.black
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 32 * glassRatio, height: 32 * glassRatio)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75)
                            )
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.lens.brand.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.0)
                            .foregroundStyle(isStaged ? Palette.accent : Palette.textDim)
                            .lineLimit(1)

                        Text(formatMountBadge(entry.lens.mount))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.textSub)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                Text(displayTitle)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(isStaged ? Palette.accent : Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 4) {
                    Text(formatApertureRange(entry.lens.minAperture, entry.lens.maxAperture))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(Palette.textSub)

                    if entry.variants.count > 1 {
                        Text("· \(entry.variants.count) ver")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.accent.opacity(0.85))
                    }
                }
                .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isStaged ? Palette.accent.opacity(0.14) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                isStaged ? Palette.accent.opacity(0.75) : Color.white.opacity(0.06),
                                lineWidth: isStaged ? 1.5 : 1.0
                            )
                    )
            )
        }
        .buttonStyle(PressStyle(scale: 0.95))
    }
}

// MARK: - Shared Helpers

func shutterRangeText(_ first: Double, _ second: Double) -> String {
    let slow = max(first, second)
    let fast = min(first, second)
    return "\(formatShutterStopLabel(slow))–\(formatShutterStopLabel(fast))"
}

private func lensRowTitle(_ entry: PrewarmedLensEntry) -> String {
    guard entry.lens.minAperture > 0 else {
        return entry.lens.model
    }
    let aperture = String(formatApertureStopLabel(entry.lens.minAperture).dropFirst(2))
    if let zoom = zoomFocalRange(entry.lens.model) {
        return "\(zoom)mm f/\(aperture)"
    }
    if entry.focalLengthMm > 0, entry.focalLengthMm < 9999 {
        let mmStr = entry.focalLengthMm == entry.focalLengthMm.rounded()
            ? String(Int(entry.focalLengthMm))
            : String(format: "%.1f", entry.focalLengthMm)
        return "\(mmStr)mm f/\(aperture)"
    }
    return entry.lens.model
}

private func zoomFocalRange(_ model: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: #"(\d{2,3})\s*[-–]\s*(\d{2,3})\s*mm"#, options: [.caseInsensitive]) else {
        return nil
    }
    let full = NSRange(model.startIndex..., in: model)
    guard let match = regex.firstMatch(in: model, options: [], range: full),
          let lower = Range(match.range(at: 1), in: model),
          let upper = Range(match.range(at: 2), in: model) else {
        return nil
    }
    return "\(model[lower])-\(model[upper])"
}
