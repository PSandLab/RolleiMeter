import Foundation
import SwiftUI

// MARK: - Gear picker

/// Camera and lens selection for the film log.
///
/// Pushed from the parent `NavigationStack` (`RollScreen`). The screen never
/// creates a stack of its own, so the system back button, the swipe-back
/// gesture and the grouped `List` chrome all come for free.
struct GearPickerScreen: View {
    @ObservedObject var store: FilmLogStore

    private var gear: ActiveGearProfile { store.activeGear }

    var body: some View {
        List {
            inUseSection
            cameraSection
            lensSection
            customGearSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Camera & Lens")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: In use

    @ViewBuilder
    private var inUseSection: some View {
        Section {
            if gear.hasCamera {
                activeCameraRow

                LabeledContent("Lens") {
                    Text(gear.hasLens ? gear.lensName : "Body only")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if gear.hasLens {
                    LabeledContent("Aperture") {
                        Text(formatApertureRange(gear.minAperture, gear.maxAperture))
                            .font(Geist.monoText(.body))
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Shutter") {
                    Text(shutterRangeText(gear.minShutter, gear.maxShutter))
                        .font(Geist.monoText(.body))
                        .foregroundStyle(.secondary)
                }

                Button("Remove", role: .destructive) {
                    store.activeGear = .unloaded
                    Haptics.success()
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No camera selected")
                    Text(gear.hasLens
                         ? "Lens saved: \(gear.lensName)"
                         : "The meter is showing every stop.")
                        .font(Geist.text(.subheadline))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("In use")
        } footer: {
            Text(gear.hasCamera
                 ? "The meter is limited to this gear's shutter and aperture range."
                 : "Choose a body and a lens to limit the meter to the gear you are carrying.")
        }
    }

    private var activeCameraRow: some View {
        HStack(spacing: 14) {
            if let brand = activeCameraBrand {
                CameraBrandLogo(brand: brand, size: 44)
            } else {
                Image(systemName: "camera.aperture")
                    .font(Geist.text(.title3))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(gear.cameraName)
                    .font(Geist.text(.headline))
                    .lineLimit(2)
                Text(activeCameraSubtitle)
                    .font(Geist.text(.subheadline))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var activeCameraBrand: String? {
        guard !gear.cameraId.isEmpty else { return nil }
        return GearCatalogCache.allCameras(customCameras: store.customCameras)
            .first { $0.id == gear.cameraId }?.brand
    }

    private var activeCameraSubtitle: String {
        if gear.isFixedLens || gear.mount.isEmpty || gear.mount == "Fixed" {
            return "Fixed lens"
        }
        return formatMountBadge(gear.mount)
    }

    // MARK: Navigate

    private var cameraSection: some View {
        Section {
            NavigationLink {
                CameraCatalogList(store: store)
            } label: {
                HStack(spacing: 12) {
                    ListGlyph(systemName: "camera")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(gear.hasCamera ? "Change camera" : "Choose a camera")
                        Text("Browse every body by brand")
                            .font(Geist.text(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Camera")
        }
    }

    private var lensSection: some View {
        Section {
            NavigationLink {
                LensCatalogList(store: store)
            } label: {
                HStack(spacing: 12) {
                    ListGlyph(systemName: "camera.aperture")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(gear.hasLens ? "Change lens" : "Choose a lens")
                        Text("Browse one row per lens, versions inside")
                            .font(Geist.text(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Lens")
        }
    }

    private var customGearSection: some View {
        Section {
            NavigationLink {
                CustomGearForm(store: store)
            } label: {
                HStack(spacing: 12) {
                    ListGlyph(systemName: "plus", tint: Palette.good)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add custom gear")
                        Text("Create a camera or lens that is not in the catalog")
                            .font(Geist.text(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Custom gear")
        } footer: {
            Text("Custom cameras and lenses also appear in the catalogs above.")
        }
    }
}

// MARK: - Camera brand index

/// Popular brands, in the order the camera index presents them.
private let cameraPopularBrandOrder: [String] = [
    "Leica", "Nikon", "Canon", "Pentax", "Olympus", "Minolta", "Contax",
    "Fujifilm", "Rollei", "Yashica", "Voigtländer", "Mamiya", "Hasselblad",
    "Ricoh", "Konica"
]

/// The camera catalog as a brand index: 271 bodies are unusable in one list,
/// so this screen lists brands first and pushes the bodies of one brand.
struct CameraCatalogList: View {
    @ObservedObject var store: FilmLogStore

    @State private var searchText = ""

    var body: some View {
        let cameras = GearCatalogCache.allCameras(customCameras: store.customCameras)
        let groups = cameraBrandGroups(from: cameras)
        let activeBrand = activeCameraBrand(in: cameras, activeCameraId: store.activeGear.cameraId)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let brandMatches = matchingBrands(in: groups, query: query)
        let cameraMatches = matchingCameras(in: cameras, query: query)
        let popular = popularBrandGroups(from: groups)
        let rare = rareBrandGroups(from: groups)
        let rareCameraCount = rare.reduce(0) { $0 + $1.count }
        let customCameras = store.customCameras.sorted {
            if $0.brand != $1.brand {
                return $0.brand.localizedStandardCompare($1.brand) == .orderedAscending
            }
            return $0.model.localizedStandardCompare($1.model) == .orderedAscending
        }

        List {
            if query.isEmpty {
                if !popular.isEmpty {
                    Section {
                        ForEach(popular) { group in
                            NavigationLink {
                                CameraBrandScreen(store: store, brand: group.brand)
                            } label: {
                                CameraBrandRow(group: group,
                                               isActive: group.brand == activeBrand)
                            }
                        }
                    } header: {
                        Text("Popular")
                    }
                }

                if !rare.isEmpty {
                    Section {
                        NavigationLink {
                            RareBrandScreen(store: store)
                        } label: {
                            HStack(spacing: 12) {
                                ListGlyph(systemName: "clock.arrow.circlepath")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Rare brands")
                                        .font(Geist.text(.body))
                                        .foregroundStyle(Palette.text)
                                    Text("\(countText(rareCameraCount, singular: "camera", plural: "cameras")) · \(countText(rare.count, singular: "brand", plural: "brands"))")
                                        .font(Geist.text(.subheadline))
                                        .foregroundStyle(Palette.textSub)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("Vintage & rare")
                    } footer: {
                        Text("Bodies from small and discontinued makers, kept out of the popular list.")
                    }
                }

                if !customCameras.isEmpty {
                    Section {
                        ForEach(customCameras) { camera in
                            NavigationLink {
                                CameraDetailView(store: store, camera: camera)
                            } label: {
                                CameraModelRow(camera: camera,
                                               subtitle: cameraRowSubtitle(camera, includingBrand: true),
                                               isActive: camera.id == store.activeGear.cameraId)
                            }
                        }
                    } header: {
                        Text("Custom")
                    } footer: {
                        Text("Cameras you added yourself.")
                    }
                }
            } else {
                if !brandMatches.isEmpty {
                    Section {
                        ForEach(brandMatches) { group in
                            NavigationLink {
                                CameraBrandScreen(store: store, brand: group.brand)
                            } label: {
                                CameraBrandRow(group: group,
                                               isActive: group.brand == activeBrand)
                            }
                        }
                    } header: {
                        Text("Brands")
                    }
                }

                if !cameraMatches.isEmpty {
                    Section {
                        ForEach(cameraMatches) { camera in
                            NavigationLink {
                                CameraDetailView(store: store, camera: camera)
                            } label: {
                                CameraModelRow(camera: camera,
                                               subtitle: cameraRowSubtitle(camera, includingBrand: true),
                                               isActive: camera.id == store.activeGear.cameraId)
                            }
                        }
                    } header: {
                        Text("Cameras")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search brands or cameras")
        .overlay {
            if !query.isEmpty && brandMatches.isEmpty && cameraMatches.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .navigationTitle("Camera")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The bodies of one brand. Pushes the mount profiles of the selected body.
struct CameraBrandScreen: View {
    @ObservedObject var store: FilmLogStore
    let brand: String

    var body: some View {
        let cameras = GearCatalogCache.allCameras(customCameras: store.customCameras)
            .filter { $0.brand == brand }
            .sorted { $0.model.localizedStandardCompare($1.model) == .orderedAscending }

        List {
            Section {
                ForEach(cameras) { camera in
                    NavigationLink {
                        CameraDetailView(store: store, camera: camera)
                    } label: {
                        CameraModelRow(camera: camera,
                                       subtitle: cameraRowSubtitle(camera, includingBrand: false),
                                       isActive: camera.id == store.activeGear.cameraId)
                    }
                }
            } header: {
                Text("Bodies")
            } footer: {
                Text("Every \(brand) body in the catalog.")
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if cameras.isEmpty {
                ContentUnavailableView("No cameras",
                                       systemImage: "camera",
                                       description: Text("No \(brand) body is in the catalog."))
            }
        }
        .navigationTitle(brand)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The leftover brands: one-off and obscure bodies that would otherwise clutter
/// the popular part of the index. Any brand added to the JSON later that is not
/// on the popular list lands here automatically.
struct RareBrandScreen: View {
    @ObservedObject var store: FilmLogStore

    var body: some View {
        let cameras = GearCatalogCache.allCameras(customCameras: store.customCameras)
        let groups = rareBrandGroups(from: cameraBrandGroups(from: cameras))
        let activeBrand = activeCameraBrand(in: cameras, activeCameraId: store.activeGear.cameraId)

        List {
            Section {
                ForEach(groups) { group in
                    NavigationLink {
                        CameraBrandScreen(store: store, brand: group.brand)
                    } label: {
                        CameraBrandRow(group: group,
                                       isActive: group.brand == activeBrand)
                    }
                }
            } header: {
                Text("Brands")
            } footer: {
                Text("One-off and obscure bodies, grouped by brand.")
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView("No rare brands",
                                       systemImage: "camera",
                                       description: Text("Every brand in the catalog is listed under Popular."))
            }
        }
        .navigationTitle("Vintage & rare")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Camera detail (mount profiles)

/// The mount profiles of one body: the fixed lens it was built around, or the
/// native-mount lenses, an adapter profile for anything else, or no lens at
/// all. Mounting a profile pops back to the catalog.
struct CameraDetailView: View {
    @ObservedObject var store: FilmLogStore
    let camera: CameraGearSpec

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            cameraSection
            profileSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(camera.model)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var cameraSection: some View {
        Section {
            HStack(spacing: 14) {
                CameraBrandLogo(brand: camera.brand, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(camera.model)
                        .font(Geist.text(.headline))
                    Text(camera.brand)
                        .font(Geist.text(.subheadline))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)

            LabeledContent("Mount") {
                Text(camera.isFixed ? "Fixed lens" : camera.mount)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Shutter") {
                Text(shutterRangeText(camera.minShutter, camera.maxShutter))
                    .font(Geist.monoText(.body))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Camera")
        }
    }

    @ViewBuilder
    private var profileSection: some View {
        if camera.isFixed {
            Section {
                Button {
                    mount(fixedProfile)
                } label: {
                    GearProfileRow(title: fixedLensTitle,
                                   subtitle: "Fixed lens · \(formatApertureRange(camera.fixedMinAperture, camera.fixedMaxAperture))",
                                   isActive: isFixedProfileActive)
                }
            } header: {
                Text("Lens")
            } footer: {
                Text("This body is built around its lens, so mounting it also sets the aperture range.")
            }
        } else {
            Section {
                Button {
                    mount(bodyOnlyProfile)
                } label: {
                    GearProfileRow(title: "Body only",
                                   subtitle: "Use the body without a lens",
                                   isActive: isBodyOnlyActive)
                }

                Button {
                    mount(adapterProfile)
                } label: {
                    GearProfileRow(title: "Use an adapter",
                                   subtitle: "Any lens you can mount",
                                   systemImage: "arrow.triangle.swap",
                                   isActive: isAdapterActive)
                }

                ForEach(mountLenses) { entry in
                    NavigationLink {
                        LensDetailView(store: store, entry: entry, hostCamera: camera)
                    } label: {
                        GearProfileRow(title: lensRowTitle(entry),
                                       subtitle: lensRowSubtitle(entry),
                                       isActive: isEntryActive(entry))
                    }
                }
            } header: {
                Text("Lens")
            } footer: {
                if mountLenses.isEmpty {
                    Text("No catalog lens uses the \(formatMountBadge(camera.mount)) mount yet. Add one under Custom gear.\nAdapter: any lens you can mount, from f/1.2 to f/32.")
                } else {
                    Text("Lenses made for the \(formatMountBadge(camera.mount)) mount.\nAdapter: any lens you can mount, from f/1.2 to f/32.")
                }
            }
        }
    }

    /// Lenses the body's mount accepts, in focal-length order.
    private var mountLenses: [PrewarmedLensEntry] {
        guard !camera.isFixed else { return [] }
        return GearCatalogCache.allLensEntries(customLenses: store.customLenses)
            .filter { $0.lens.mount.caseInsensitiveCompare(camera.mount) == .orderedSame }
    }

    private var fixedLensTitle: String {
        camera.fixedLensName.isEmpty ? "Fixed lens" : camera.fixedLensName
    }

    private var isFixedProfileActive: Bool {
        let gear = store.activeGear
        return gear.cameraId == camera.id && gear.isFixedLens
    }

    private var isBodyOnlyActive: Bool {
        let gear = store.activeGear
        return gear.cameraId == camera.id && !gear.hasLens
    }

    private var isAdapterActive: Bool {
        let gear = store.activeGear
        return gear.cameraId == camera.id && gear.lensId == adapterProfile.lensId
    }

    private func isEntryActive(_ entry: PrewarmedLensEntry) -> Bool {
        let gear = store.activeGear
        guard gear.cameraId == camera.id, !gear.lensId.isEmpty else { return false }
        if gear.lensId == entry.lens.id { return true }
        return entry.variants.contains { $0.spec.id == gear.lensId }
    }

    private var fixedProfile: ActiveGearProfile {
        ActiveGearProfile(
            cameraId: camera.id,
            cameraName: camera.model,
            mount: "Fixed",
            isFixedLens: true,
            minShutter: camera.minShutter,
            maxShutter: camera.maxShutter,
            lensId: "\(camera.id)_fixed",
            lensName: fixedLensTitle,
            minAperture: camera.fixedMinAperture,
            maxAperture: camera.fixedMaxAperture
        )
    }

    private var bodyOnlyProfile: ActiveGearProfile {
        ActiveGearProfile(
            cameraId: camera.id,
            cameraName: camera.model,
            mount: camera.mount,
            isFixedLens: false,
            minShutter: camera.minShutter,
            maxShutter: camera.maxShutter,
            lensId: "",
            lensName: "",
            minAperture: 1.0,
            maxAperture: 32.0
        )
    }

    /// Anything the user can physically fit through an adapter: the body keeps
    /// its own shutter range and mount, the lens range is the widest usable.
    private var adapterProfile: ActiveGearProfile {
        ActiveGearProfile(
            cameraId: camera.id,
            cameraName: camera.model,
            mount: camera.mount,
            isFixedLens: false,
            minShutter: camera.minShutter,
            maxShutter: camera.maxShutter,
            lensId: "\(camera.id)_adapter",
            lensName: "Adapted lens",
            minAperture: 1.2,
            maxAperture: 32.0
        )
    }

    private func mount(_ profile: ActiveGearProfile) {
        store.activeGear = profile
        Haptics.success()
        dismiss()
    }
}

// MARK: - Lens catalog

/// Every lens in the catalog, grouped by focal-length category. There is one
/// row per family; the versions live in `LensDetailView`.
struct LensCatalogList: View {
    @ObservedObject var store: FilmLogStore

    @State private var searchText = ""

    var body: some View {
        let sections = lensSections()

        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.entries) { entry in
                        NavigationLink {
                            LensDetailView(store: store, entry: entry)
                        } label: {
                            GearLensRow(entry: entry,
                                        isActive: isEntryActive(entry))
                        }
                    }
                } header: {
                    Text(section.title)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search lenses")
        .overlay {
            if sections.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .navigationTitle("Lens")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func lensSections() -> [LensCatalogSection] {
        let entries = filteredEntries
        let custom = entries.filter { $0.lens.isCustom }
        let catalog = entries.filter { !$0.lens.isCustom }

        var sections: [LensCatalogSection] = []
        if !custom.isEmpty {
            sections.append(LensCatalogSection(id: "custom", title: "Custom", entries: custom))
        }

        var categorized = Set<String>()
        for category in FocalLengthCategory.allCases where category != .all {
            let matches = catalog.filter { entryCategory($0) == category }
            guard !matches.isEmpty else { continue }
            categorized.formUnion(matches.map { $0.lens.id })
            sections.append(LensCatalogSection(id: category.rawValue,
                                               title: category.sectionTitle,
                                               entries: matches))
        }

        // Anything the focal buckets cannot classify would otherwise vanish.
        let other = catalog.filter { !categorized.contains($0.lens.id) }
        if !other.isEmpty {
            sections.append(LensCatalogSection(id: "other", title: "Other", entries: other))
        }
        return sections
    }

    private func entryCategory(_ entry: PrewarmedLensEntry) -> FocalLengthCategory? {
        if zoomFocalRange(entry.lens.model) != nil { return .zoom }
        let mm = entry.focalLengthMm
        guard mm > 0, mm < 9999 else { return nil }
        if mm <= 25 { return .ultraWide }
        if mm <= 31 { return .w28 }
        if mm <= 43 { return .w35 }
        if mm <= 65 { return .std50 }
        if mm <= 100 { return .port85 }
        return .tele105Plus
    }

    private var filteredEntries: [PrewarmedLensEntry] {
        let all = GearCatalogCache.allLensEntries(customLenses: store.customLenses)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }

        return all
            .map { entry in
                (entry: entry,
                 score: fuzzyMatchScore(query: query,
                                        target: "\(entry.lens.brand) \(entry.lens.model) \(entry.lens.mount)"))
            }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .map { $0.entry }
    }

    private func isEntryActive(_ entry: PrewarmedLensEntry) -> Bool {
        let activeLensID = store.activeGear.lensId
        guard !activeLensID.isEmpty else { return false }
        if activeLensID == entry.lens.id { return true }
        return entry.variants.contains { $0.spec.id == activeLensID }
    }
}

private struct LensCatalogSection: Identifiable {
    let id: String
    let title: String
    let entries: [PrewarmedLensEntry]
}

// MARK: - Lens detail (version picker)

/// One lens family. The catalog row is deliberately clean; the version (New FD
/// vs FD, AI vs AI-S, …) is picked here and applied on mount.
struct LensDetailView: View {
    @ObservedObject var store: FilmLogStore
    let entry: PrewarmedLensEntry
    let hostCamera: CameraGearSpec?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedVariantID: String

    init(store: FilmLogStore, entry: PrewarmedLensEntry, hostCamera: CameraGearSpec? = nil) {
        self.store = store
        self.entry = entry
        self.hostCamera = hostCamera
        _selectedVariantID = State(initialValue: entry.variants.first?.id ?? "")
    }

    private var selectedVariant: LensVariantItem? {
        entry.variants.first { $0.id == selectedVariantID } ?? entry.variants.first
    }

    var body: some View {
        List {
            specSection
            versionSection
            mountSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(lensRowTitle(entry))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Specs

    private var specSection: some View {
        Section {
            LabeledContent("Brand") {
                Text(entry.lens.brand)
                    .foregroundStyle(Palette.textSub)
            }
            LabeledContent("Mount") {
                Text(formatMountBadge(entry.lens.mount))
                    .foregroundStyle(Palette.textSub)
            }
            LabeledContent("Focal length") {
                Text(focalLengthDisplay)
                    .font(Geist.monoText(.body))
                    .foregroundStyle(Palette.textSub)
            }
            LabeledContent("Aperture") {
                Text(formatApertureRange(entry.lens.minAperture, entry.lens.maxAperture))
                    .font(Geist.monoText(.body))
                    .foregroundStyle(Palette.textSub)
            }
        } header: {
            Text("Lens")
        }
    }

    private var focalLengthDisplay: String {
        if let zoom = zoomFocalRange(entry.lens.model) {
            return "\(zoom) mm"
        }
        if entry.focalLengthMm > 0, entry.focalLengthMm < 9999 {
            return "\(focalLengthNumberText(entry.focalLengthMm)) mm"
        }
        return "Not listed"
    }

    // MARK: Version

    @ViewBuilder
    private var versionSection: some View {
        if entry.variants.count > 1 {
            Section {
                if entry.variants.count <= 3 {
                    Picker("Version", selection: $selectedVariantID) {
                        ForEach(entry.variants) { variant in
                            Text(variant.badge).tag(variant.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if let selectedVariant {
                        Text(selectedVariant.subtitle)
                            .font(Geist.text(.caption))
                            .foregroundStyle(Palette.textSub)
                    }
                } else {
                    Picker("Version", selection: $selectedVariantID) {
                        ForEach(entry.variants) { variant in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(variant.badge)
                                Text(variant.subtitle)
                                    .font(Geist.text(.caption))
                                    .foregroundStyle(Palette.textSub)
                            }
                            .tag(variant.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            } header: {
                Text("Version")
            } footer: {
                Text("Pick the version marked on your lens.")
            }
        }
    }

    // MARK: Mount

    private var mountSection: some View {
        Section {
            Button {
                mountSelected()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "camera.aperture")
                    Text("Mount lens")
                    Spacer(minLength: 0)
                }
                .font(Geist.text(.body, .semibold))
                .foregroundStyle(Palette.accent)
                .frame(minHeight: Metrics.minTap)
                .contentShape(Rectangle())
            }
        } footer: {
            Text(mountFooter)
        }
    }

    private var mountFooter: String {
        if let hostCamera {
            return "Mounts this lens on the \(hostCamera.model)."
        }
        return "Applies this lens's aperture range to the meter."
    }

    private func mountSelected() {
        var gear = store.activeGear

        if let hostCamera {
            gear.cameraId = hostCamera.id
            gear.cameraName = hostCamera.model
            gear.mount = hostCamera.mount
            gear.isFixedLens = false
            gear.minShutter = hostCamera.minShutter
            gear.maxShutter = hostCamera.maxShutter
        }

        let lens = selectedVariant?.spec ?? entry.lens
        gear.lensId = lens.id
        gear.lensName = lens.model
        gear.minAperture = lens.minAperture
        gear.maxAperture = lens.maxAperture

        store.activeGear = gear
        Haptics.success()
        dismiss()
    }
}

// MARK: - Rows

private struct CameraBrandRow: View {
    let group: CameraBrandGroup
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            CameraBrandLogo(brand: group.brand, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.brand)
                    .font(Geist.text(.body))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text(countText(group.count, singular: "camera", plural: "cameras"))
                    .font(Geist.text(.subheadline))
                    .foregroundStyle(Palette.textSub)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isActive {
                Image(systemName: "checkmark")
                    .font(Geist.text(.body, .semibold))
                    .foregroundStyle(Palette.accent)
                    .accessibilityLabel("In use")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct CameraModelRow: View {
    let camera: CameraGearSpec
    let subtitle: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            CameraBrandLogo(brand: camera.brand, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(camera.model)
                    .font(Geist.text(.body))
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)
                Text(subtitle)
                    .font(Geist.text(.subheadline))
                    .foregroundStyle(Palette.textSub)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isActive {
                Image(systemName: "checkmark")
                    .font(Geist.text(.body, .semibold))
                    .foregroundStyle(Palette.accent)
                    .accessibilityLabel("In use")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct GearProfileRow: View {
    let title: String
    let subtitle: String
    var systemImage: String? = nil
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Geist.text(.body))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 24)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Geist.text(.body))
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)
                Text(subtitle)
                    .font(Geist.text(.subheadline))
                    .foregroundStyle(Palette.textSub)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isActive {
                Image(systemName: "checkmark")
                    .font(Geist.text(.body, .semibold))
                    .foregroundStyle(Palette.accent)
                    .accessibilityLabel("Mounted")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct GearLensRow: View {
    let entry: PrewarmedLensEntry
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lensRowTitle(entry))
                    .font(Geist.text(.body))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text(lensRowSubtitle(entry))
                    .font(Geist.text(.subheadline))
                    .foregroundStyle(Palette.textSub)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isActive {
                Image(systemName: "checkmark")
                    .font(Geist.text(.body, .semibold))
                    .foregroundStyle(Palette.accent)
                    .accessibilityLabel("Mounted")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Brand index data

private struct CameraBrandGroup: Identifiable {
    let brand: String
    let count: Int

    var id: String { brand }
}

private func cameraBrandGroups(from cameras: [CameraGearSpec]) -> [CameraBrandGroup] {
    var counts: [String: Int] = [:]
    for camera in cameras {
        let brand = camera.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brand.isEmpty else { continue }
        counts[brand, default: 0] += 1
    }
    return counts
        .map { CameraBrandGroup(brand: $0.key, count: $0.value) }
        .sorted { $0.brand.localizedStandardCompare($1.brand) == .orderedAscending }
}

private func popularBrandGroups(from groups: [CameraBrandGroup]) -> [CameraBrandGroup] {
    let byBrand = Dictionary(uniqueKeysWithValues: groups.map { ($0.brand, $0) })
    return cameraPopularBrandOrder.compactMap { byBrand[$0] }
}

/// Brands that are neither popular nor added by the user: the rare screen is
/// about the bundled catalog, while custom gear keeps its own section.
private func rareBrandGroups(from groups: [CameraBrandGroup]) -> [CameraBrandGroup] {
    let bundledBrands = Set(GearCatalogCache.loadBundledCatalog().cameras.map { $0.brand })
    return groups.filter {
        bundledBrands.contains($0.brand) && !cameraPopularBrandOrder.contains($0.brand)
    }
}

private func activeCameraBrand(in cameras: [CameraGearSpec], activeCameraId: String) -> String? {
    guard !activeCameraId.isEmpty else { return nil }
    return cameras.first { $0.id == activeCameraId }?.brand
}

private func matchingBrands(in groups: [CameraBrandGroup], query: String) -> [CameraBrandGroup] {
    guard !query.isEmpty else { return [] }
    return groups
        .map { group in
            (group: group, score: fuzzyMatchScore(query: query, target: group.brand))
        }
        .filter { $0.score > 0 }
        .sorted { $0.score > $1.score }
        .map { $0.group }
}

private func matchingCameras(in cameras: [CameraGearSpec], query: String) -> [CameraGearSpec] {
    guard !query.isEmpty else { return [] }
    return cameras
        .map { camera in
            (camera: camera, score: fuzzyMatchScore(query: query, target: "\(camera.brand) \(camera.model)"))
        }
        .filter { $0.score > 0 }
        .sorted { $0.score > $1.score }
        .map { $0.camera }
}

private func cameraRowSubtitle(_ camera: CameraGearSpec, includingBrand: Bool) -> String {
    let detail: String
    if camera.isFixed {
        detail = camera.fixedLensName.isEmpty ? "Fixed lens" : camera.fixedLensName
    } else {
        detail = "\(formatMountBadge(camera.mount)) · \(shutterRangeText(camera.minShutter, camera.maxShutter))"
    }

    let brand = camera.brand.trimmingCharacters(in: .whitespacesAndNewlines)
    if includingBrand, !brand.isEmpty {
        return "\(brand) · \(detail)"
    }
    return detail
}

private func countText(_ count: Int, singular: String, plural: String) -> String {
    "\(count) \(count == 1 ? singular : plural)"
}

// MARK: - Lens naming

/// One lens family, one clean row title: `24mm f/2.8` for a prime, a short
/// focal range for a zoom, and only then the cleaned model name.
private func lensRowTitle(_ entry: PrewarmedLensEntry) -> String {
    guard entry.lens.minAperture > 0 else {
        return shortLensName(entry.lens)
    }

    let aperture = apertureNumberText(entry.lens.minAperture)
    if let zoom = zoomFocalRange(entry.lens.model) {
        return "\(zoom)mm f/\(aperture)"
    }
    if entry.focalLengthMm > 0, entry.focalLengthMm < 9999 {
        return "\(focalLengthNumberText(entry.focalLengthMm))mm f/\(aperture)"
    }
    return shortLensName(entry.lens)
}

/// Brand plus the number of versions — never the raw model, never an aperture
/// range. A lone version only earns a mention when its badge says something.
private func lensRowSubtitle(_ entry: PrewarmedLensEntry) -> String {
    let brand = entry.lens.brand.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = brand.isEmpty ? "Lens" : brand

    if entry.variants.count > 1 {
        return "\(name) · \(entry.variants.count) versions"
    }
    if let variant = entry.variants.first,
       !variant.badge.isEmpty,
       variant.badge.caseInsensitiveCompare("Standard") != .orderedSame {
        return "\(name) · \(variant.badge)"
    }
    return name
}

/// `f/2.8` -> `2.8`, `f/1` -> `1`, `f/0.95` -> `0.95`.
private func apertureNumberText(_ value: Double) -> String {
    String(formatApertureStopLabel(value).dropFirst(2))
}

private func focalLengthNumberText(_ mm: Double) -> String {
    if mm == mm.rounded() {
        return String(Int(mm))
    }
    if (mm * 10).rounded() == mm * 10 {
        return String(format: "%.1f", mm)
    }
    return String(format: "%.2f", mm)
}

/// "35-105" for a zoom model such as `New FD 35-105mm f/3.5`.
private func zoomFocalRange(_ model: String) -> String? {
    guard let regex = zoomRangeRegex else { return nil }
    let full = NSRange(model.startIndex..., in: model)
    guard let match = regex.firstMatch(in: model, options: [], range: full),
          let lower = Range(match.range(at: 1), in: model),
          let upper = Range(match.range(at: 2), in: model) else {
        return nil
    }
    return "\(model[lower])-\(model[upper])"
}

private let zoomRangeRegex: NSRegularExpression? = try? NSRegularExpression(
    pattern: #"(\d{2,3})\s*[-–]\s*(\d{2,3})\s*mm"#,
    options: [.caseInsensitive]
)

/// Tokens that repeat what the row already says, so they only make the name
/// longer. Matched case-insensitively and removed before the name is clamped.
private let lensNameNoiseTokens: [String] = [
    "S.S.C.", "S.C.", "New FD", "AI-S", "Pre-AI", "Non-AI", "ASPH", "FLE"
]

/// A short model name for entries without a usable focal length: brand prefix
/// removed, whitespace collapsed, variant tokens dropped, clamped to 28 chars.
private func shortLensName(_ lens: LensGearSpec, maxLength: Int = 28) -> String {
    var name = lens.model.trimmingCharacters(in: .whitespacesAndNewlines)

    let brand = lens.brand.trimmingCharacters(in: .whitespacesAndNewlines)
    if !brand.isEmpty, name.lowercased().hasPrefix(brand.lowercased()) {
        name = String(name.dropFirst(brand.count))
    }

    for token in lensNameNoiseTokens {
        name = name.replacingOccurrences(of: token, with: " ", options: .caseInsensitive)
    }

    name = name
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "-–—/·,;:")))

    if name.isEmpty {
        name = "Lens"
    }

    if name.count > maxLength {
        let head = String(name.prefix(maxLength - 1)).trimmingCharacters(in: .whitespaces)
        name = "\(head)…"
    }
    return name
}

// MARK: - Shared helpers

/// "1/2–1/500" for a body or profile, always slowest first.
private func shutterRangeText(_ first: Double, _ second: Double) -> String {
    let slow = max(first, second)
    let fast = min(first, second)
    return "\(formatShutterStopLabel(slow))–\(formatShutterStopLabel(fast))"
}

private extension FocalLengthCategory {
    /// Section headers for the lens catalog. `FocalLengthCategory.label` is
    /// tuned for the meter's compact pickers, so it is not reused here.
    var sectionTitle: String {
        switch self {
        case .all: return "All"
        case .ultraWide: return "≤ 24 mm"
        case .w28: return "28 mm"
        case .w35: return "35 mm"
        case .std50: return "50 mm"
        case .port85: return "85 mm"
        case .tele105Plus: return "105 mm +"
        case .zoom: return "Zooms"
        }
    }
}
