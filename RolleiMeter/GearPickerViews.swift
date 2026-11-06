import SwiftUI
import UIKit

// MARK: - Custom Gear Form (With Fast Tactile Shutter & Aperture Scrubber Rulers)

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
                TextField("Brand (e.g. Leica, Nikon)", text: $brand)
                    .textInputAutocapitalization(.words)

                TextField("Model Name", text: $modelName)
                    .textInputAutocapitalization(.words)

                if kind == .fixedLens {
                    TextField("Built-in Lens (e.g. 40mm f/2.8)", text: $fixedLensName)
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
                        TextField("Custom Mount Name", text: $customMount)
                            .textInputAutocapitalization(.words)
                    }
                }
            }

            if kind != .lens {
                Section("Shutter Speed Range") {
                    AnalogStopRulerScrubber(
                        title: "Fastest Shutter",
                        valueLabel: formatShutterStopLabel(fastestShutterStop),
                        index: fastestShutterIndex,
                        range: min(slowestShutterIndex + 1, ALL_ANALOG_SHUTTER_STOPS.count - 1)...(ALL_ANALOG_SHUTTER_STOPS.count - 1),
                        totalCount: ALL_ANALOG_SHUTTER_STOPS.count
                    ) { newIdx in
                        setFastestShutter(newIdx)
                    }

                    AnalogStopRulerScrubber(
                        title: "Slowest Shutter",
                        valueLabel: formatShutterStopLabel(slowestShutterStop),
                        index: slowestShutterIndex,
                        range: 0...max(fastestShutterIndex - 1, 0),
                        totalCount: ALL_ANALOG_SHUTTER_STOPS.count
                    ) { newIdx in
                        setSlowestShutter(newIdx)
                    }
                }
                .monospacedDigit()
            }

            if kind != .body {
                Section("Aperture Ring Range") {
                    AnalogStopRulerScrubber(
                        title: "Widest (Max) Aperture",
                        valueLabel: formatApertureStopLabel(widestApertureStop),
                        index: widestApertureIndex,
                        range: 0...max(smallestApertureIndex - 1, 0),
                        totalCount: ALL_ANALOG_APERTURE_STOPS.count
                    ) { newIdx in
                        setWidestAperture(newIdx)
                    }

                    AnalogStopRulerScrubber(
                        title: "Smallest (Min) Aperture",
                        valueLabel: formatApertureStopLabel(smallestApertureStop),
                        index: smallestApertureIndex,
                        range: min(widestApertureIndex + 1, ALL_ANALOG_APERTURE_STOPS.count - 1)...(ALL_ANALOG_APERTURE_STOPS.count - 1),
                        totalCount: ALL_ANALOG_APERTURE_STOPS.count
                    ) { newIdx in
                        setSmallestAperture(newIdx)
                    }
                }
                .monospacedDigit()
            }

            Section {
                Button {
                    addGear()
                } label: {
                    HStack {
                        Spacer()
                        Label("Mount & Save Custom Gear", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                        Spacer()
                    }
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

private struct AnalogStopRulerScrubber: View {
    let title: String
    let valueLabel: String
    let index: Int
    let range: ClosedRange<Int>
    let totalCount: Int
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(valueLabel)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Palette.accent)
            }

            GeometryReader { geo in
                let w = max(geo.size.width, 1)
                let usable = max(w - 20, 1)
                let frac = CGFloat(index) / CGFloat(max(totalCount - 1, 1))

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.14))

                    Canvas { ctx, size in
                        let span = size.width - 20
                        for i in 0..<totalCount {
                            let f = CGFloat(i) / CGFloat(max(totalCount - 1, 1))
                            let x = 10 + f * span
                            let inValidRange = range.contains(i)
                            let isSelected = (i == index)
                            let tickH: CGFloat = isSelected ? 20 : (i % 3 == 0 ? 13 : 7)
                            let topY = (size.height - tickH) * 0.5

                            var p = Path()
                            p.move(to: CGPoint(x: x, y: topY))
                            p.addLine(to: CGPoint(x: x, y: topY + tickH))
                            ctx.stroke(
                                p,
                                with: .color(
                                    isSelected
                                        ? Palette.accent
                                        : (inValidRange ? Color.primary.opacity(i % 3 == 0 ? 0.5 : 0.25) : Color.secondary.opacity(0.10))
                                ),
                                lineWidth: isSelected ? 2.5 : 1.2
                            )
                        }
                    }

                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 14, height: 14)
                        .offset(x: 10 + frac * usable - 7)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let ratio = ((value.location.x - 10) / usable).clamped(to: 0...1)
                            let rawIdx = Int((ratio * CGFloat(totalCount - 1)).rounded())
                            let clamped = rawIdx.clamped(to: range)
                            if clamped != index {
                                UISelectionFeedbackGenerator().selectionChanged()
                                onChange(clamped)
                            }
                        }
                )
            }
            .frame(height: 30)
        }
        .padding(.vertical, 4)
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
