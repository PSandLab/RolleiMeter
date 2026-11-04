import SwiftUI

// MARK: - Custom Gear Form

struct CustomGearForm: View {
    @ObservedObject var store: FilmLogStore
    var onFinish: () -> Void = {}
    var presetKinds: [CustomGearKind] = CustomGearKind.allCases
    var presetBrand: String = ""

    @State private var kind: CustomGearKind
    @State private var brand = ""
    @State private var modelName = ""
    @State private var fixedLensName = ""
    @State private var mountSelection: String
    @State private var customMount = ""

    @State private var fastestShutterIndex = 14   // 1/500
    @State private var slowestShutterIndex = 5     // 1 s
    @State private var widestApertureIndex = 8     // f/2.8
    @State private var smallestApertureIndex = 20  // f/22

    private static let otherMountTag = "Other…"

    init(
        store: FilmLogStore,
        onFinish: @escaping () -> Void = {},
        presetKinds: [CustomGearKind] = CustomGearKind.allCases,
        presetBrand: String = ""
    ) {
        self.store = store
        self.onFinish = onFinish
        self.presetKinds = presetKinds
        self.presetBrand = presetBrand

        let initial = presetKinds.first ?? .fixedLens
        _kind = State(initialValue: initial)
        _brand = State(initialValue: presetBrand)

        let mounts = GearCatalogCache.loadBundledCatalog().mounts.filter { $0 != "Fixed" }
        _mountSelection = State(initialValue: mounts.first { $0 == "Leica M" } ?? mounts.first ?? CustomGearForm.otherMountTag)
    }

    var body: some View {
        Form {
            if presetKinds.count > 1 {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(presetKinds) { option in
                            Text(option.pickerTitle).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section(kind == .lens ? "Lens" : "Camera") {
                TextField("Brand", text: $brand)
                    .textInputAutocapitalization(.words)

                TextField(kind == .lens ? "Model" : "Model", text: $modelName)
                    .textInputAutocapitalization(.words)

                if kind == .fixedLens {
                    TextField("Lens", text: $fixedLensName)
                        .textInputAutocapitalization(.words)
                }

                if kind != .fixedLens {
                    Picker("Mount", selection: $mountSelection) {
                        ForEach(knownMounts, id: \.self) { mount in
                            Text(mount).tag(mount)
                        }
                        Text(Self.otherMountTag).tag(Self.otherMountTag)
                    }

                    if mountSelection == Self.otherMountTag {
                        TextField("Mount", text: $customMount)
                            .textInputAutocapitalization(.words)
                    }
                }
            }

            if kind != .lens {
                Section("Shutter") {
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
                }
                .monospacedDigit()
            }

            if kind != .body {
                Section("Aperture") {
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
                }
                .monospacedDigit()
            }

            Section {
                Button("Add Gear") {
                    addGear()
                }
                .disabled(!canAdd)
            }
        }
        .navigationTitle(presetTitle)
        .navigationBarTitleDisplayMode(.inline)
        .listSectionSpacing(.compact)
        .toolbarVisibility(.hidden, for: .tabBar)
    }

    // MARK: - Stops

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

    private var knownMounts: [String] {
        GearCatalogCache.loadBundledCatalog().mounts.filter { $0 != "Fixed" }
    }

    private var presetTitle: String {
        if presetKinds.count > 1 { return "Custom Gear" }
        switch presetKinds.first {
        case .lens: return "Custom Lens"
        case .body, .fixedLens: return "Custom Camera"
        case nil: return "Custom Gear"
        }
    }

    private var trimmedModel: String {
        modelName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAdd: Bool {
        !trimmedModel.isEmpty
    }

    private func addGear() {
        guard canAdd else { return }
        Haptics.success()

        switch kind {
        case .fixedLens:
            addCamera(isFixed: true)
        case .body:
            addCamera(isFixed: false)
        case .lens:
            addLens()
        }

        onFinish()
    }

    private func addCamera(isFixed: Bool) {
        let name = trimmedModel
        let brandName = cleanBrand
        let mount = cleanMount
        let lens = cleanFixedLens
        let cameraId = "custom_cam_\(UUID().uuidString)"
        let customStops = isFixed
            ? defaultApertureStopsForRange(minAperture: widestApertureStop, maxAperture: smallestApertureStop)
            : []

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
            fixedApertureStops: customStops,
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
            maxAperture: isFixed ? smallestApertureStop : 22.0,
            apertureStops: customStops
        )

        store.addCustomCamera(camera)
        store.activeGear = profile
    }

    private func addLens() {
        let customStops = defaultApertureStopsForRange(minAperture: widestApertureStop, maxAperture: smallestApertureStop)
        let lens = LensGearSpec(
            id: "custom_lens_\(UUID().uuidString)",
            brand: cleanBrand,
            model: trimmedModel,
            mount: cleanMount,
            minAperture: widestApertureStop,
            maxAperture: smallestApertureStop,
            apertureStops: customStops,
            isCustom: true
        )

        store.addCustomLens(lens)

        var gear = store.activeGear
        gear.lensId = lens.id
        gear.lensName = lens.model
        gear.minAperture = lens.minAperture
        gear.maxAperture = lens.maxAperture
        gear.apertureStops = lens.apertureStops
        store.activeGear = gear
    }

    private var cleanBrand: String {
        let value = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Custom" : value
    }

    private var cleanMount: String {
        if mountSelection == Self.otherMountTag {
            let value = customMount.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? "Custom" : value
        }
        return mountSelection
    }

    private var cleanFixedLens: String {
        let value = fixedLensName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Fixed lens" : value
    }
}

enum CustomGearKind: String, CaseIterable, Identifiable {
    case fixedLens
    case body
    case lens

    var id: String { rawValue }

    var pickerTitle: String {
        switch self {
        case .fixedLens: return "Fixed"
        case .body: return "Body"
        case .lens: return "Lens"
        }
    }
}
