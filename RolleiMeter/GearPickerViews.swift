import SwiftUI

// MARK: - Custom gear form

/// Creates a camera (fixed-lens or interchangeable body) or a lens that is not
/// in the bundled catalog, then mounts it. Adding is the toolbar action; gear
/// that was added before can be swiped away at the bottom of the form.
struct CustomGearForm: View {
    @ObservedObject var store: FilmLogStore

    @Environment(\.dismiss) private var dismiss

    @State private var kind: CustomGearKind = .fixedLens
    @State private var brand = ""
    @State private var modelName = ""
    @State private var fixedLensName = "40mm f/2.8"
    @State private var mountName = "Leica M"

    // Indices into the analog stop tables.
    @State private var fastestShutterIndex = 14   // 1/500
    @State private var slowestShutterIndex = 5    // 1 s
    @State private var widestApertureIndex = 8    // f/2.8
    @State private var smallestApertureIndex = 20 // f/22

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $kind) {
                    ForEach(CustomGearKind.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(kind.explanation)
            }

            Section {
                TextField("Brand", text: $brand)
                    .textInputAutocapitalization(.words)
                TextField(modelFieldTitle, text: $modelName)
                    .textInputAutocapitalization(.words)

                if kind == .fixedLens {
                    TextField("Lens", text: $fixedLensName)
                        .textInputAutocapitalization(.words)
                } else {
                    TextField("Mount", text: $mountName)
                        .textInputAutocapitalization(.words)

                    Menu {
                        ForEach(knownMounts, id: \.self) { mount in
                            Button(mount) { mountName = mount }
                        }
                    } label: {
                        Label("Choose a known mount", systemImage: "list.bullet")
                    }
                }
            } header: {
                Text("Details")
            } footer: {
                Text(detailsFooter)
            }

            if kind != .lens {
                Section {
                    Stepper {
                        LabeledContent("Fastest", value: formatShutterStopLabel(fastestShutterStop))
                    } onIncrement: {
                        setFastestShutter(fastestShutterIndex + 1)
                    } onDecrement: {
                        setFastestShutter(fastestShutterIndex - 1)
                    }

                    Stepper {
                        LabeledContent("Slowest", value: formatShutterStopLabel(slowestShutterStop))
                    } onIncrement: {
                        setSlowestShutter(slowestShutterIndex + 1)
                    } onDecrement: {
                        setSlowestShutter(slowestShutterIndex - 1)
                    }
                } header: {
                    Text("Shutter")
                } footer: {
                    Text("The fastest and slowest marked speeds on the body.")
                }
            }

            if kind != .body {
                Section {
                    Stepper {
                        LabeledContent("Widest", value: formatApertureStopLabel(widestApertureStop))
                    } onIncrement: {
                        setWidestAperture(widestApertureIndex + 1)
                    } onDecrement: {
                        setWidestAperture(widestApertureIndex - 1)
                    }

                    Stepper {
                        LabeledContent("Smallest", value: formatApertureStopLabel(smallestApertureStop))
                    } onIncrement: {
                        setSmallestAperture(smallestApertureIndex + 1)
                    } onDecrement: {
                        setSmallestAperture(smallestApertureIndex - 1)
                    }
                } header: {
                    Text("Aperture")
                } footer: {
                    Text("The widest and smallest apertures marked on the lens.")
                }
            }

            savedCamerasSection
            savedLensesSection
        }
        .navigationTitle("Custom gear")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { addGear() }
                    .disabled(!canAdd)
            }
        }
    }

    // MARK: Saved gear

    @ViewBuilder
    private var savedCamerasSection: some View {
        if !store.customCameras.isEmpty {
            Section {
                ForEach(store.customCameras) { camera in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(camera.model)
                            .lineLimit(1)
                        Text(savedCameraSubtitle(camera))
                            .font(Geist.monoText(.subheadline))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .onDelete(perform: deleteCameras)
            } header: {
                Text("Custom cameras")
            } footer: {
                Text("Swipe a row to delete it.")
            }
        }
    }

    @ViewBuilder
    private var savedLensesSection: some View {
        if !store.customLenses.isEmpty {
            Section {
                ForEach(store.customLenses) { lens in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lens.model)
                            .lineLimit(1)
                        Text("\(lens.brand) · \(formatMountBadge(lens.mount)) · \(formatApertureRange(lens.minAperture, lens.maxAperture))")
                            .font(Geist.monoText(.subheadline))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .onDelete(perform: deleteLenses)
            } header: {
                Text("Custom lenses")
            } footer: {
                Text("Swipe a row to delete it.")
            }
        }
    }

    private func savedCameraSubtitle(_ camera: CameraGearSpec) -> String {
        if camera.isFixed {
            return camera.fixedLensName.isEmpty ? "Fixed lens" : camera.fixedLensName
        }
        let slow = max(camera.minShutter, camera.maxShutter)
        let fast = min(camera.minShutter, camera.maxShutter)
        return "\(formatMountBadge(camera.mount)) · \(formatShutterStopLabel(slow))–\(formatShutterStopLabel(fast))"
    }

    private func deleteCameras(at offsets: IndexSet) {
        let removed = offsets.map { store.customCameras[$0].id }
        store.customCameras.remove(atOffsets: offsets)
        if removed.contains(store.activeGear.cameraId) {
            store.activeGear = .unloaded
        }
        Haptics.warning()
    }

    private func deleteLenses(at offsets: IndexSet) {
        let removed = offsets.map { store.customLenses[$0].id }
        store.customLenses.remove(atOffsets: offsets)
        if removed.contains(store.activeGear.lensId) {
            var gear = store.activeGear
            gear.lensId = ""
            gear.lensName = ""
            gear.minAperture = 1.0
            gear.maxAperture = 32.0
            store.activeGear = gear
        }
        Haptics.warning()
    }

    // MARK: Stops

    private var fastestShutterStop: Double {
        ALL_ANALOG_SHUTTER_STOPS[fastestShutterIndex.clamped(to: 0...(ALL_ANALOG_SHUTTER_STOPS.count - 1))]
    }

    private var slowestShutterStop: Double {
        ALL_ANALOG_SHUTTER_STOPS[slowestShutterIndex.clamped(to: 0...(ALL_ANALOG_SHUTTER_STOPS.count - 1))]
    }

    private var widestApertureStop: Double {
        ALL_ANALOG_APERTURE_STOPS[widestApertureIndex.clamped(to: 0...(ALL_ANALOG_APERTURE_STOPS.count - 1))]
    }

    private var smallestApertureStop: Double {
        ALL_ANALOG_APERTURE_STOPS[smallestApertureIndex.clamped(to: 0...(ALL_ANALOG_APERTURE_STOPS.count - 1))]
    }

    private func setFastestShutter(_ value: Int) {
        let upper = ALL_ANALOG_SHUTTER_STOPS.count - 1
        let lower = min(slowestShutterIndex + 1, upper)
        fastestShutterIndex = value.clamped(to: lower...upper)
    }

    private func setSlowestShutter(_ value: Int) {
        let upper = max(fastestShutterIndex - 1, 0)
        slowestShutterIndex = value.clamped(to: 0...upper)
    }

    private func setWidestAperture(_ value: Int) {
        let upper = max(smallestApertureIndex - 1, 0)
        widestApertureIndex = value.clamped(to: 0...upper)
    }

    private func setSmallestAperture(_ value: Int) {
        let upper = ALL_ANALOG_APERTURE_STOPS.count - 1
        let lower = min(widestApertureIndex + 1, upper)
        smallestApertureIndex = value.clamped(to: lower...upper)
    }

    // MARK: Fields

    private var knownMounts: [String] {
        GearCatalogCache.loadBundledCatalog().mounts.filter { $0 != "Fixed" }
    }

    private var modelFieldTitle: String {
        kind == .lens ? "Lens model" : "Camera model"
    }

    private var detailsFooter: String {
        switch kind {
        case .fixedLens:
            return "A camera with a built-in lens, like a point-and-shoot or a TLR."
        case .body:
            return "An interchangeable-lens body. The mount links it to the lenses made for it."
        case .lens:
            return "A lens for any mount. It appears in the lens catalog and on matching bodies."
        }
    }

    private var trimmedModel: String {
        modelName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAdd: Bool {
        !trimmedModel.isEmpty
    }

    // MARK: Create

    private func addGear() {
        guard canAdd else { return }

        switch kind {
        case .fixedLens:
            addCamera(isFixed: true)
        case .body:
            addCamera(isFixed: false)
        case .lens:
            addLens()
        }

        Haptics.success()
        dismiss()
    }

    private func addCamera(isFixed: Bool) {
        let name = trimmedModel
        let brandName = cleanBrand
        let mount = cleanMount
        let lens = cleanFixedLens
        let cameraId = "custom_cam_\(UUID().uuidString)"

        let camera = CameraGearSpec(
            id: cameraId,
            brand: brandName,
            model: name,
            isFixed: isFixed,
            mount: isFixed ? "Fixed" : mount,
            minShutter: slowestShutterStop,
            maxShutter: fastestShutterStop,
            fixedLensName: isFixed ? lens : "",
            fixedMinAperture: isFixed ? widestApertureStop : 0.0,
            fixedMaxAperture: isFixed ? smallestApertureStop : 0.0,
            isCustom: true
        )

        let profile = ActiveGearProfile(
            cameraId: cameraId,
            cameraName: name,
            mount: isFixed ? "Fixed" : mount,
            isFixedLens: isFixed,
            minShutter: slowestShutterStop,
            maxShutter: fastestShutterStop,
            lensId: isFixed ? "\(cameraId)_fixed" : "",
            lensName: isFixed ? lens : "",
            minAperture: isFixed ? widestApertureStop : 1.4,
            maxAperture: isFixed ? smallestApertureStop : 22.0
        )

        store.addCustomCamera(camera)
        store.activeGear = profile
    }

    private func addLens() {
        let lens = LensGearSpec(
            id: "custom_lens_\(UUID().uuidString)",
            brand: cleanBrand,
            model: trimmedModel,
            mount: cleanMount,
            minAperture: widestApertureStop,
            maxAperture: smallestApertureStop,
            isCustom: true
        )

        store.addCustomLens(lens)

        var gear = store.activeGear
        gear.lensId = lens.id
        gear.lensName = lens.model
        gear.minAperture = lens.minAperture
        gear.maxAperture = lens.maxAperture
        store.activeGear = gear
    }

    private var cleanBrand: String {
        let value = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Custom" : value
    }

    private var cleanMount: String {
        let value = mountName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Custom" : value
    }

    private var cleanFixedLens: String {
        let value = fixedLensName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Fixed lens" : value
    }
}

// MARK: - Kind

private enum CustomGearKind: String, CaseIterable, Identifiable {
    case fixedLens
    case body
    case lens

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fixedLens: return "Fixed"
        case .body: return "Body"
        case .lens: return "Lens"
        }
    }

    var explanation: String {
        switch self {
        case .fixedLens:
            return "A camera that is built around its lens, with a marked shutter range."
        case .body:
            return "An interchangeable-lens camera body, with a marked shutter range."
        case .lens:
            return "A lens for any mount, with a marked aperture range."
        }
    }
}
