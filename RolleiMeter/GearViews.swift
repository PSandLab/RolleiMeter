import Foundation
import SwiftUI

// MARK: - Screen 3: Camera & Lens

struct CameraLensView: View {
    @ObservedObject var store: FilmLogStore
    var onFinish: () -> Void = {}

    @State private var showConfirm = false

    private var gear: ActiveGearProfile { store.activeGear }

    private var activeCameraBrand: String? {
        guard gear.hasCamera, !gear.cameraId.isEmpty else { return nil }
        return GearCatalogCache.allCameras(customCameras: store.customCameras)
            .first { $0.id == gear.cameraId }?.brand
    }

    private var hasFixedLens: Bool {
        gear.hasCamera && (gear.isFixedLens || gear.mount.isEmpty || gear.mount == "Fixed")
    }

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    CameraCatalogList(store: store, onFinish: onFinish)
                } label: {
                    HStack(spacing: 12) {
                        if let brand = activeCameraBrand {
                            CameraBrandLogo(brand: brand, size: 40)
                        } else {
                            Image(systemName: "camera")
                                .foregroundStyle(.secondary)
                                .frame(width: 40, height: 40)
                        }

                        VStack(alignment: .leading) {
                            Text(gear.hasCamera ? gear.cameraName : "Choose Camera")
                                .foregroundStyle(gear.hasCamera ? .primary : .tint)
                            if gear.hasCamera {
                                Text(hasFixedLens ? "Fixed lens" : formatMountBadge(gear.mount))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if hasFixedLens {
                    LabeledContent("Lens", value: gear.hasLens ? gear.lensName : "Fixed lens")
                } else {
                    NavigationLink {
                        LensCatalogList(store: store, onFinish: onFinish)
                    } label: {
                        LabeledContent("Lens", value: gear.hasLens ? gear.lensName : "None")
                    }
                }
            }

            Section("Meter Range") {
                LabeledContent("Aperture", value: formatApertureRange(gear.minAperture, gear.maxAperture))
                LabeledContent("Shutter", value: shutterRangeText(gear.minShutter, gear.maxShutter))
            }
            .monospacedDigit()

            Section {
                NavigationLink {
                    CustomGearForm(store: store, onFinish: onFinish)
                } label: {
                    Label("Add Custom Gear", systemImage: "plus")
                }
            }

            if gear.hasCamera {
                Section {
                    Button("Remove Camera", role: .destructive) {
                        showConfirm = true
                    }
                }
            }
        }
        .navigationTitle("Camera & Lens")
        .navigationBarTitleDisplayMode(.inline)
        .listSectionSpacing(.compact)
        .toolbarVisibility(.hidden, for: .tabBar)
        .confirmationDialog("Remove camera?", isPresented: $showConfirm) {
            Button("Remove", role: .destructive) {
                store.activeGear = .unloaded
                Haptics.success()
            }
        }
    }
}

// MARK: - Camera Brand Index

private let cameraPopularBrandOrder: [String] = [
    "Leica", "Nikon", "Canon", "Pentax", "Olympus", "Minolta", "Contax",
    "Fujifilm", "Rollei", "Yashica", "Voigtländer", "Mamiya", "Hasselblad",
    "Ricoh", "Konica"
]

struct CameraCatalogList: View {
    @ObservedObject var store: FilmLogStore
    var onFinish: () -> Void = {}

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
                    Section("Brands") {
                        ForEach(popular) { group in
                            NavigationLink {
                                CameraBrandScreen(store: store, brand: group.brand, onFinish: onFinish)
                            } label: {
                                CameraBrandRow(
                                    group: group,
                                    isActive: group.brand == activeBrand
                                )
                            }
                        }

                        if !rare.isEmpty {
                            NavigationLink {
                                RareBrandScreen(store: store, onFinish: onFinish)
                            } label: {
                                LabeledContent(
                                    "Other Brands",
                                    value: countText(rareCameraCount, singular: "camera", plural: "cameras")
                                )
                                .monospacedDigit()
                            }
                        }
                    }
                }
            } else {
                if !brandMatches.isEmpty {
                    Section("Brands") {
                        ForEach(brandMatches) { group in
                            NavigationLink {
                                CameraBrandScreen(store: store, brand: group.brand, onFinish: onFinish)
                            } label: {
                                CameraBrandRow(
                                    group: group,
                                    isActive: group.brand == activeBrand
                                )
                            }
                        }
                    }
                }

                if !cameraMatches.isEmpty {
                    Section("Cameras") {
                        ForEach(cameraMatches) { camera in
                            NavigationLink {
                                CameraDetailView(store: store, camera: camera, onFinish: onFinish)
                            } label: {
                                CameraModelRow(
                                    camera: camera,
                                    subtitle: cameraRowSubtitle(camera, includingBrand: true),
                                    isActive: camera.id == store.activeGear.cameraId
                                )
                            }
                        }
                    }
                }
            }

            customSection(customCameras)
        }
        .searchable(text: $searchText, prompt: "Search cameras")
        .overlay {
            if !query.isEmpty && brandMatches.isEmpty && cameraMatches.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .navigationTitle("Camera")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
    }

    @ViewBuilder
    private func customSection(_ customCameras: [CameraGearSpec]) -> some View {
        Section {
            ForEach(customCameras) { camera in
                NavigationLink {
                    CameraDetailView(store: store, camera: camera, onFinish: onFinish)
                } label: {
                    CameraModelRow(
                        camera: camera,
                        subtitle: cameraRowSubtitle(camera, includingBrand: true),
                        isActive: camera.id == store.activeGear.cameraId
                    )
                }
                .swipeActions {
                    Button(role: .destructive) {
                        store.removeCustomCamera(id: camera.id)
                        Haptics.warning()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            NavigationLink {
                CustomGearForm(store: store, onFinish: onFinish, presetKinds: [.fixedLens, .body])
            } label: {
                Label("Add Custom Camera", systemImage: "plus")
            }
        }
    }
}

struct CameraBrandScreen: View {
    @ObservedObject var store: FilmLogStore
    let brand: String
    var onFinish: () -> Void = {}

    var body: some View {
        let cameras = GearCatalogCache.allCameras(customCameras: store.customCameras)
            .filter { $0.brand == brand }
            .sorted { $0.model.localizedStandardCompare($1.model) == .orderedAscending }

        List {
            Section {
                ForEach(cameras) { camera in
                    NavigationLink {
                        CameraDetailView(store: store, camera: camera, onFinish: onFinish)
                    } label: {
                        CameraModelRow(
                            camera: camera,
                            subtitle: cameraRowSubtitle(camera, includingBrand: false),
                            isActive: camera.id == store.activeGear.cameraId
                        )
                    }
                }

                NavigationLink {
                    CustomGearForm(store: store, onFinish: onFinish, presetKinds: [.fixedLens, .body], presetBrand: brand)
                } label: {
                    Label("Add Custom Camera", systemImage: "plus")
                }
            }
        }
        .overlay {
            if cameras.isEmpty {
                ContentUnavailableView("No Cameras", systemImage: "camera")
            }
        }
        .navigationTitle(brand)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
    }
}

struct RareBrandScreen: View {
    @ObservedObject var store: FilmLogStore
    var onFinish: () -> Void = {}

    var body: some View {
        let cameras = GearCatalogCache.allCameras(customCameras: store.customCameras)
        let groups = rareBrandGroups(from: cameraBrandGroups(from: cameras))
        let activeBrand = activeCameraBrand(in: cameras, activeCameraId: store.activeGear.cameraId)

        List {
            Section {
                ForEach(groups) { group in
                    NavigationLink {
                        CameraBrandScreen(store: store, brand: group.brand, onFinish: onFinish)
                    } label: {
                        CameraBrandRow(
                            group: group,
                            isActive: group.brand == activeBrand
                        )
                    }
                }
            }
        }
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView("No Brands", systemImage: "camera")
            }
        }
        .navigationTitle("Other Brands")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
    }
}

// MARK: - Camera Detail

struct CameraDetailView: View {
    @ObservedObject var store: FilmLogStore
    let camera: CameraGearSpec
    var onFinish: () -> Void = {}

    private enum Choice: Hashable {
        case fixed
        case bodyOnly
        case adapter
    }

    @State private var choice: Choice = .fixed

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    CameraBrandLogo(brand: camera.brand, size: 40)
                    VStack(alignment: .leading) {
                        Text(camera.model)
                        Text(camera.brand)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Mount", value: camera.isFixed ? "Fixed lens" : formatMountBadge(camera.mount))
                LabeledContent("Shutter", value: shutterRangeText(camera.minShutter, camera.maxShutter))
                    .monospacedDigit()

                if camera.isFixed {
                    LabeledContent("Lens", value: fixedLensTitle)
                    LabeledContent("Aperture", value: formatApertureRange(camera.fixedMinAperture, camera.fixedMaxAperture))
                        .monospacedDigit()
                }
            }

            if !camera.isFixed {
                Section("Setup") {
                    Picker("Setup", selection: $choice) {
                        Text("Body Only").tag(Choice.bodyOnly)
                        Text("Adapter").tag(Choice.adapter)
                    }
                    .pickerStyle(.segmented)
                }

                if !mountLenses.isEmpty {
                    Section("\(formatMountBadge(camera.mount)) Lenses") {
                        ForEach(mountLenses) { entry in
                            NavigationLink {
                                LensDetailView(store: store, entry: entry, hostCamera: camera, onFinish: onFinish)
                            } label: {
                                GearProfileRow(
                                    title: lensTitles(mountLenses)[entry.id] ?? lensRowTitle(entry),
                                    subtitle: lensRowSubtitle(entry),
                                    isActive: isEntryActive(entry)
                                )
                            }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        CustomGearForm(store: store, onFinish: onFinish, presetKinds: [.lens])
                    } label: {
                        Label("Add Custom Lens", systemImage: "plus")
                    }
                }
            }

            Section {
                Button("Use \(camera.model)") {
                    Haptics.success()
                    store.activeGear = selectedProfile
                    onFinish()
                }
            }
        }
        .navigationTitle(camera.model)
        .navigationBarTitleDisplayMode(.inline)
        .listSectionSpacing(.compact)
        .toolbarVisibility(.hidden, for: .tabBar)
        .onAppear {
            choice = camera.isFixed ? .fixed : .bodyOnly
        }
    }

    private var mountLenses: [PrewarmedLensEntry] {
        guard !camera.isFixed else { return [] }
        return GearCatalogCache.allLensEntries(customLenses: store.customLenses)
            .filter { $0.lens.mount.caseInsensitiveCompare(camera.mount) == .orderedSame }
    }

    private var fixedLensTitle: String {
        camera.fixedLensName.isEmpty ? "Fixed lens" : camera.fixedLensName
    }

    private func isEntryActive(_ entry: PrewarmedLensEntry) -> Bool {
        let gear = store.activeGear
        guard gear.cameraId == camera.id, !gear.lensId.isEmpty else { return false }
        if gear.lensId == entry.lens.id { return true }
        return entry.variants.contains { $0.spec.id == gear.lensId }
    }

    private var selectedProfile: ActiveGearProfile {
        switch choice {
        case .fixed: return fixedProfile
        case .bodyOnly: return bodyOnlyProfile
        case .adapter: return adapterProfile
        }
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
            maxAperture: camera.fixedMaxAperture,
            apertureStops: camera.fixedApertureStops
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
            maxAperture: 32.0,
            apertureStops: []
        )
    }

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
            maxAperture: 32.0,
            apertureStops: [1.2, 1.4, 2.0, 2.8, 4.0, 5.6, 8.0, 11.0, 16.0, 22.0, 32.0]
        )
    }
}

// MARK: - Lens Catalog

struct LensCatalogList: View {
    @ObservedObject var store: FilmLogStore
    var onFinish: () -> Void = {}

    @State private var searchText = ""

    var body: some View {
        let sections = lensSections()
        let entries = GearCatalogCache.allLensEntries(customLenses: store.customLenses)
        let titles = lensTitles(entries)

        List {
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.entries) { entry in
                        NavigationLink {
                            LensDetailView(store: store, entry: entry, onFinish: onFinish)
                        } label: {
                            GearLensRow(
                                entry: entry,
                                displayTitle: titles[entry.id],
                                isActive: isEntryActive(entry)
                            )
                        }
                        .swipeActions {
                            if entry.lens.isCustom {
                                Button(role: .destructive) {
                                    store.removeCustomLens(id: entry.lens.id)
                                    Haptics.warning()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }

            Section {
                NavigationLink {
                    CustomGearForm(store: store, onFinish: onFinish, presetKinds: [.lens])
                } label: {
                    Label("Add Custom Lens", systemImage: "plus")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search lenses")
        .overlay {
            if sections.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .navigationTitle("Lens")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
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
            sections.append(LensCatalogSection(
                id: category.rawValue,
                title: category.sectionTitle,
                entries: matches
            ))
        }

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
                 score: fuzzyMatchScore(query: query, target: "\(entry.lens.brand) \(entry.lens.model) \(entry.lens.mount)"))
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

// MARK: - Lens Detail

struct LensDetailView: View {
    @ObservedObject var store: FilmLogStore
    let entry: PrewarmedLensEntry
    let hostCamera: CameraGearSpec?
    var onFinish: () -> Void = {}

    @State private var selectedVariantID: String

    init(
        store: FilmLogStore,
        entry: PrewarmedLensEntry,
        hostCamera: CameraGearSpec? = nil,
        onFinish: @escaping () -> Void = {}
    ) {
        self.store = store
        self.entry = entry
        self.hostCamera = hostCamera
        self.onFinish = onFinish
        _selectedVariantID = State(initialValue: entry.variants.first?.id ?? "")
    }

    private var selectedVariant: LensVariantItem? {
        entry.variants.first { $0.id == selectedVariantID } ?? entry.variants.first
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Brand", value: entry.lens.brand)
                LabeledContent("Mount", value: formatMountBadge(entry.lens.mount))
                LabeledContent("Focal Length", value: focalLengthDisplay)
                    .monospacedDigit()
                let activeSpec = selectedVariant?.spec ?? entry.lens
                LabeledContent("Aperture", value: formatApertureRange(activeSpec.minAperture, activeSpec.maxAperture))
                    .monospacedDigit()
            }

            if entry.variants.count > 1 {
                Section("Version") {
                    Picker("Version", selection: $selectedVariantID) {
                        ForEach(entry.variants) { variant in
                            Text(variant.badge).tag(variant.id)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section {
                Button(hostCamera != nil ? "Use on \(hostCamera!.model)" : "Use Lens") {
                    mountSelected()
                }
            }
        }
        .navigationTitle(lensRowTitle(entry))
        .navigationBarTitleDisplayMode(.inline)
        .listSectionSpacing(.compact)
        .toolbarVisibility(.hidden, for: .tabBar)
    }

    private var focalLengthDisplay: String {
        if let zoom = zoomFocalRange(entry.lens.model) {
            return "\(zoom) mm"
        }
        if entry.focalLengthMm > 0, entry.focalLengthMm < 9999 {
            return "\(focalLengthNumberText(entry.focalLengthMm)) mm"
        }
        return "—"
    }

    private func mountSelected() {
        Haptics.success()
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
        gear.apertureStops = lens.apertureStops

        store.activeGear = gear
        onFinish()
    }
}

// MARK: - Rows

private struct CameraBrandRow: View {
    let group: CameraBrandGroup
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            CameraBrandLogo(brand: group.brand, size: 40)

            VStack(alignment: .leading) {
                Text(group.brand)
                    .lineLimit(1)
                Text(countText(group.count, singular: "camera", plural: "cameras"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .accessibilityLabel("In use")
            }
        }
    }
}

private struct CameraModelRow: View {
    let camera: CameraGearSpec
    let subtitle: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            CameraBrandLogo(brand: camera.brand, size: 40)

            VStack(alignment: .leading) {
                Text(camera.model)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .accessibilityLabel("In use")
            }
        }
    }
}

private struct GearProfileRow: View {
    let title: String
    let subtitle: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading) {
                Text(title)
                    .lineLimit(2)
                    .monospacedDigit()
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Mounted")
            }
        }
    }
}

private struct GearLensRow: View {
    let entry: PrewarmedLensEntry
    var displayTitle: String? = nil
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading) {
                Text(displayTitle ?? lensRowTitle(entry))
                    .lineLimit(1)
                    .monospacedDigit()
                Text(lensRowSubtitle(entry))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Mounted")
            }
        }
    }
}

// MARK: - Brand Index Helpers

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

// MARK: - Lens Naming

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

private func lensTitles(_ entries: [PrewarmedLensEntry]) -> [String: String] {
    var counts: [String: Int] = [:]
    for entry in entries {
        counts["\(entry.lens.brand)|\(lensRowTitle(entry))", default: 0] += 1
    }

    var titles: [String: String] = [:]
    for entry in entries {
        let clean = lensRowTitle(entry)
        if (counts["\(entry.lens.brand)|\(clean)"] ?? 0) > 1 {
            titles[entry.id] = fullModelName(entry.lens)
        } else {
            titles[entry.id] = clean
        }
    }
    return titles
}

private func fullModelName(_ lens: LensGearSpec, maxLength: Int = 34) -> String {
    var name = lens.model.trimmingCharacters(in: .whitespacesAndNewlines)
    let brand = lens.brand.trimmingCharacters(in: .whitespacesAndNewlines)
    if !brand.isEmpty, name.lowercased().hasPrefix(brand.lowercased()) {
        name = String(name.dropFirst(brand.count))
    }
    name = name
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "-–—/·,;:")))
    if name.isEmpty { return "Lens" }
    if name.count > maxLength {
        return String(name.prefix(maxLength - 1)) + "…"
    }
    return name
}

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

private let lensNameNoiseTokens: [String] = [
    "S.S.C.", "S.C.", "New FD", "AI-S", "Pre-AI", "Non-AI", "ASPH", "FLE"
]

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

// MARK: - Shared Helpers

func shutterRangeText(_ first: Double, _ second: Double) -> String {
    let slow = max(first, second)
    let fast = min(first, second)
    return "\(formatShutterStopLabel(slow))–\(formatShutterStopLabel(fast))"
}

private extension FocalLengthCategory {
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
