import SwiftUI

// MARK: - Custom gear form

/// Creates a camera (fixed-lens or interchangeable body) or a lens that is not
/// in the bundled catalog, then mounts it.
///
/// The form shows only what is unavoidable — a name, and the mount if the body
/// takes lenses — and puts the stop ranges behind disclosures. A gear form that
/// asks for eight numbers up front is one people abandon, and the defaults
/// (1 s to 1/500, f/2.8 to f/22) are right for most manual bodies anyway.
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

    @State private var showShutter = false
    @State private var showAperture = false

    // Indices into the analog stop tables.
    @State private var fastestShutterIndex = 14   // 1/500
    @State private var slowestShutterIndex = 5     // 1 s
    @State private var widestApertureIndex = 8     // f/2.8
    @State private var smallestApertureIndex = 20  // f/22

    private static let otherMountTag = "Other mount…"

    init(store: FilmLogStore,
         onFinish: @escaping () -> Void = {},
         presetKinds: [CustomGearKind] = CustomGearKind.allCases,
         presetBrand: String = "") {
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
                    .labelsHidden()
                } footer: {
                    Text(kind.explanation)
                }
            }

            identitySection

            Section {
                if kind != .lens {
                    DisclosureGroup(isExpanded: $showShutter) {
                        shutterSteppers
                    } label: {
                        LabeledContent("Shutter", value: "\(formatShutterStopLabel(slowestShutterStop))–\(formatShutterStopLabel(fastestShutterStop))")
                            .font(Geist.text(.body))
                    }
                }

                if kind != .body {
                    DisclosureGroup(isExpanded: $showAperture) {
                        apertureSteppers
                    } label: {
                        LabeledContent("Aperture", value: formatApertureRange(widestApertureStop, smallestApertureStop))
                            .font(Geist.text(.body))
                    }
                }
            } header: {
                Text("Limits")
            } footer: {
                Text("Only the extremes matter: the fastest and slowest marked speeds, the widest and smallest f-stops. The defaults suit most manual gear.")
            }

            Section {
                IrisHoldControl(
                    title: addTitle,
                    workingTitle: "Adding gear",
                    doneTitle: "Added",
                    hint: canAdd ? "Press and hold to save and mount" : "Add a model name first",
                    doneDetail: "Saved to your gear and mounted",
                    holdDuration: 1.1,
                    isEnabled: canAdd
                ) {
                    addGear()
                }
            } footer: {
                Text("The gear is stored on this device and applied to the meter.")
            }
        }
        .navigationTitle(presetTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Identity

    @ViewBuilder
    private var identitySection: some View {
        Section {
            TextField("Brand", text: $brand)
                .textInputAutocapitalization(.words)

            TextField(kind == .lens ? "Lens model" : "Camera model", text: $modelName)
                .textInputAutocapitalization(.words)

            if kind == .fixedLens {
                TextField("Lens", text: $fixedLensName)
                    .textInputAutocapitalization(.words)
            }

            if kind == .body {
                Picker("Mount", selection: $mountSelection) {
                    ForEach(knownMounts, id: \.self) { mount in
                        Text(mount).tag(mount)
                    }
                    Text(Self.otherMountTag).tag(Self.otherMountTag)
                }

                if mountSelection == Self.otherMountTag {
                    TextField("Mount name", text: $customMount)
                        .textInputAutocapitalization(.words)
                }
            }
        } header: {
            Text(kind == .lens ? "Lens" : "Camera")
        } footer: {
            Text(identityFooter)
        }
    }

    private var identityFooter: String {
        switch kind {
        case .fixedLens:
            return "A body with a built-in lens: a rangefinder, a point-and-shoot, a TLR."
        case .body:
            return "An interchangeable-lens body. The mount links it to the lenses made for it."
        case .lens:
            return "A lens for any mount. It appears in the lens catalog and on matching bodies."
        }
    }

    // MARK: Steppers

    private var shutterSteppers: some View {
        Group {
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
    }

    private var apertureSteppers: some View {
        Group {
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

    private var presetTitle: String {
        if presetKinds.count > 1 { return "Custom gear" }
        switch presetKinds.first {
        case .lens: return "Custom lens"
        case .body, .fixedLens: return "Custom camera"
        case nil: return "Custom gear"
        }
    }

    private var addTitle: String {
        switch kind {
        case .fixedLens: return "Hold to add this camera"
        case .body: return "Hold to add this body"
        case .lens: return "Hold to add this lens"
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

        onFinish()
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

// MARK: - Kind

enum CustomGearKind: String, CaseIterable, Identifiable {
    case fixedLens
    case body
    case lens

    var id: String { rawValue }

    /// Full label for menus and footers.
    var title: String {
        switch self {
        case .fixedLens: return "Fixed lens"
        case .body: return "Interchangeable"
        case .lens: return "Lens"
        }
    }

    /// Tighter label for the segmented control.
    var pickerTitle: String {
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
