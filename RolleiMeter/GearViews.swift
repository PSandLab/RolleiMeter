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
                        Text("Browse lenses by focal length")
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

// MARK: - Camera catalog

/// Every camera in the catalog, grouped by brand. Rows push the mount profiles
/// of the selected body.
struct CameraCatalogList: View {
    @ObservedObject var store: FilmLogStore

    @State private var searchText = ""

    var body: some View {
        let sections = cameraSections()

        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.cameras) { camera in
                        NavigationLink {
                            CameraDetailView(store: store, camera: camera)
                        } label: {
                            GearCameraRow(camera: camera,
                                          isActive: camera.id == store.activeGear.cameraId)
                        }
                    }
                } header: {
                    Text(section.title)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search cameras")
        .overlay {
            if sections.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .navigationTitle("Camera")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func cameraSections() -> [CameraCatalogSection] {
        let cameras = filteredCameras
        let custom = cameras.filter(\.isCustom)
        let catalog = cameras.filter { !$0.isCustom }

        var buckets: [String: [CameraGearSpec]] = [:]
        for camera in catalog {
            buckets[camera.brand, default: []].append(camera)
        }

        var sections: [CameraCatalogSection] = []
        if !custom.isEmpty {
            sections.append(CameraCatalogSection(id: "custom", title: "Custom", cameras: sorted(custom)))
        }
        for brand in buckets.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            sections.append(CameraCatalogSection(id: brand,
                                                 title: brand,
                                                 cameras: sorted(buckets[brand] ?? [])))
        }
        return sections
    }

    private func sorted(_ cameras: [CameraGearSpec]) -> [CameraGearSpec] {
        cameras.sorted { $0.model.localizedStandardCompare($1.model) == .orderedAscending }
    }

    private var filteredCameras: [CameraGearSpec] {
        let all = GearCatalogCache.allCameras(customCameras: store.customCameras)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }

        return all
            .map { camera in
                (camera: camera,
                 score: fuzzyMatchScore(query: query,
                                        target: "\(camera.brand) \(camera.model) \(camera.mount) \(camera.fixedLensName)"))
            }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .map { $0.camera }
    }
}

private struct CameraCatalogSection: Identifiable {
    let id: String
    let title: String
    let cameras: [CameraGearSpec]
}

private struct GearCameraRow: View {
    let camera: CameraGearSpec
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            CameraBrandLogo(brand: camera.brand, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(camera.model)
                    .lineLimit(2)
                Text(summary)
                    .font(Geist.monoText(.subheadline))
                    .foregroundStyle(.secondary)
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
    }

    private var summary: String {
        if camera.isFixed {
            return camera.fixedLensName.isEmpty ? "Fixed lens" : camera.fixedLensName
        }
        return "\(formatMountBadge(camera.mount)) · \(shutterRangeText(camera.minShutter, camera.maxShutter))"
    }
}

// MARK: - Camera detail (mount profiles)

/// The mount profiles of one body: the fixed lens it was built around, or a
/// lens for each lens the mount accepts. Selecting a profile mounts it and pops
/// back to the catalog.
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

                ForEach(mountLenses) { entry in
                    Button {
                        mount(profile(for: entry.lens))
                    } label: {
                        GearProfileRow(title: entry.lens.model,
                                       subtitle: "\(entry.lens.brand) · \(formatApertureRange(entry.lens.minAperture, entry.lens.maxAperture))",
                                       isActive: isLensActive(entry.lens))
                    }
                }
            } header: {
                Text("Lens")
            } footer: {
                if mountLenses.isEmpty {
                    Text("No catalog lens uses the \(formatMountBadge(camera.mount)) mount yet. Add one under Custom gear.")
                } else {
                    Text("Lenses made for the \(formatMountBadge(camera.mount)) mount.")
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

    private func isLensActive(_ lens: LensGearSpec) -> Bool {
        let gear = store.activeGear
        return gear.cameraId == camera.id && gear.lensId == lens.id
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

    private func profile(for lens: LensGearSpec) -> ActiveGearProfile {
        ActiveGearProfile(
            cameraId: camera.id,
            cameraName: camera.model,
            mount: camera.mount,
            isFixedLens: false,
            minShutter: camera.minShutter,
            maxShutter: camera.maxShutter,
            lensId: lens.id,
            lensName: lens.model,
            minAperture: lens.minAperture,
            maxAperture: lens.maxAperture
        )
    }

    private func mount(_ profile: ActiveGearProfile) {
        store.activeGear = profile
        Haptics.success()
        dismiss()
    }
}

private struct GearProfileRow: View {
    let title: String
    let subtitle: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)
                Text(subtitle)
                    .font(Geist.monoText(.subheadline))
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
        .contentShape(Rectangle())
    }
}

// MARK: - Lens catalog

/// Every lens in the catalog, grouped by focal-length category. Selecting a
/// lens updates the active gear's lens and pops back.
struct LensCatalogList: View {
    @ObservedObject var store: FilmLogStore

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        let sections = lensSections()

        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.entries) { entry in
                        Button {
                            mount(entry.lens)
                        } label: {
                            GearLensRow(lens: entry.lens,
                                        isActive: isActive(entry.lens))
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
            let matches = catalog.filter {
                matchesFocalCategory(model: $0.lens.model, category: category)
            }
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

    private func isActive(_ lens: LensGearSpec) -> Bool {
        store.activeGear.lensId == lens.id
    }

    private func mount(_ lens: LensGearSpec) {
        var updated = store.activeGear
        updated.lensId = lens.id
        updated.lensName = lens.model
        updated.minAperture = lens.minAperture
        updated.maxAperture = lens.maxAperture
        store.activeGear = updated
        Haptics.success()
        dismiss()
    }
}

private struct LensCatalogSection: Identifiable {
    let id: String
    let title: String
    let entries: [PrewarmedLensEntry]
}

private struct GearLensRow: View {
    let lens: LensGearSpec
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lens.model)
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)
                Text("\(lens.brand) · \(formatMountBadge(lens.mount)) · \(formatApertureRange(lens.minAperture, lens.maxAperture))")
                    .font(Geist.monoText(.subheadline))
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
        .contentShape(Rectangle())
    }
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
