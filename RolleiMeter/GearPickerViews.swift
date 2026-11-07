import SwiftUI
import UIKit

// MARK: - Custom Gear Form (With Fast Tactile Shutter & Aperture Scrubber Rulers)

struct CustomGearForm: View {
    @ObservedObject var store: FilmLogStore
    var onFinish: () -> Void = {}
    var presetKinds: [CustomGearKind] = CustomGearKind.allCases
    var presetBrand: String = ""
    var presetCamera: CameraGearSpec? = nil

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
        presetBrand: String = "",
        presetCamera: CameraGearSpec? = nil
    ) {
        self.store = store
        self.onFinish = onFinish
        self.presetKinds = presetKinds
        self.presetBrand = presetBrand
        self.presetCamera = presetCamera

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
                        Label(
                            kind == .lens
                                ? "Create & Mount Custom Lens"
                                : "Create & Mount Custom Camera",
                            systemImage: "checkmark.circle.fill"
                        )
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
        guard !trimmedModel.isEmpty else {
            return false
        }

        if kind != .fixedLens,
           mountSelection == Self.otherMountTag,
           customMount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }

        if kind == .lens,
           presetCamera == nil,
           !store.activeGear.hasCamera {
            return false
        }

        if kind != .body,
           widestApertureIndex >= smallestApertureIndex {
            return false
        }

        if kind != .lens,
           fastestShutterIndex <= slowestShutterIndex {
            return false
        }

        return true
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
        let customStops = defaultApertureStopsForRange(
            minAperture: widestApertureStop,
            maxAperture: smallestApertureStop
        )

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

        var gear: ActiveGearProfile

        if let camera = presetCamera {
            // Use the camera body that was staged in CameraLensView.
            // Do not attach this lens to a different previously committed body.
            gear = ActiveGearProfile(
                cameraId: camera.id,
                cameraName: camera.model,
                mount: camera.mount,
                isFixedLens: false,
                minShutter: camera.minShutter,
                maxShutter: camera.maxShutter,
                lensId: lens.id,
                lensName: lens.model,
                minAperture: lens.minAperture,
                maxAperture: lens.maxAperture,
                apertureStops: lens.apertureStops
            )
        } else {
            // Preserve the existing fallback path for callers that create a
            // custom lens while a camera is already committed in the store.
            gear = store.activeGear

            guard gear.hasCamera else {
                return
            }

            gear.lensId = lens.id
            gear.lensName = lens.model
            gear.isFixedLens = false
            gear.minAperture = lens.minAperture
            gear.maxAperture = lens.maxAperture
            gear.apertureStops = lens.apertureStops
        }

        store.activeGear = gear
    }

    private var cleanBrand: String {
        let value = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Custom" : value
    }

    private var cleanMount: String {
        if mountSelection == Self.otherMountTag {
            return customMount.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private var safeRange: ClosedRange<Int> {
        let lower = min(range.lowerBound, totalCount - 1)
            .clamped(to: 0...(totalCount - 1))
        let upper = max(range.upperBound, lower)
            .clamped(to: lower...(totalCount - 1))
        return lower...upper
    }

    private func updateIndex(_ proposed: Int) {
        let next = proposed.clamped(to: safeRange)

        guard next != index else { return }

        UISelectionFeedbackGenerator().selectionChanged()
        onChange(next)
    }

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
                let width = max(geo.size.width, 1)
                let usable = max(width - 20, 1)
                let denominator = CGFloat(max(totalCount - 1, 1))
                let fraction = CGFloat(index) / denominator

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.14))

                    Canvas { context, size in
                        let span = max(size.width - 20, 1)

                        for i in 0..<totalCount {
                            let position = CGFloat(i) / denominator
                            let x = 10 + position * span
                            let valid = safeRange.contains(i)
                            let selected = i == index
                            let height: CGFloat = selected
                                ? 20
                                : (i % 3 == 0 ? 13 : 7)

                            let top = (size.height - height) * 0.5

                            var path = Path()
                            path.move(to: CGPoint(x: x, y: top))
                            path.addLine(to: CGPoint(x: x, y: top + height))

                            context.stroke(
                                path,
                                with: .color(
                                    selected
                                        ? Palette.accent
                                        : (
                                            valid
                                                ? Color.primary.opacity(
                                                    i % 3 == 0 ? 0.5 : 0.25
                                                )
                                                : Color.secondary.opacity(0.10)
                                        )
                                ),
                                lineWidth: selected ? 2.5 : 1.2
                            )
                        }
                    }

                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 14, height: 14)
                        .offset(x: 10 + fraction * usable - 7)
                        .shadow(
                            color: Palette.accent.opacity(0.35),
                            radius: 3
                        )
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            // Let vertical Form scrolling win.
                            guard abs(value.translation.width)
                                    > abs(value.translation.height) * 1.1 else {
                                return
                            }

                            let ratio = (
                                (value.location.x - 10) / usable
                            )
                            .clamped(to: 0...1)

                            let rawIndex = Int(
                                (ratio * CGFloat(totalCount - 1)).rounded()
                            )

                            updateIndex(rawIndex)
                        }
                )
            }
            .frame(height: 36)
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityValue(valueLabel)
            .accessibilityHint(
                "Swipe up or down to adjust the stop, or drag horizontally across the ruler."
            )
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    updateIndex(index + 1)
                case .decrement:
                    updateIndex(index - 1)
                @unknown default:
                    break
                }
            }
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
