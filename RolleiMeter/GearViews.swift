import SwiftUI
import UIKit

private let MAJOR_CAMERA_BRAND_ORDER: [String] = [
    "Leica", "Nikon", "Canon", "Pentax", "Olympus",
    "Minolta", "Contax", "Fujifilm", "Hasselblad", "Mamiya",
    "Rollei", "Yashica", "Voigtländer", "Ricoh", "Konica"
]

private let OTHER_BRANDS_GROUP_TITLE = "More Classics"

// MARK: - Gear Setup Section (Minimal Native iOS 27 Collapsible Card)

struct GearSetupSection: View {
    @ObservedObject var store: FilmLogStore
    let searchQuery: String

    @State private var isExpanded: Bool = false
    @State private var gearSubTab: Int = 0 // 0 = Cameras, 1 = Lenses, 2 = Custom
    @State private var expandedBrand: String? = nil
    @State private var expandedCameraId: String? = nil
    @State private var inlineFocalCategory: FocalLengthCategory = .all
    @State private var lensFocalCategory: FocalLengthCategory = .all

    var body: some View {
        let activeGear = store.activeGear
        let allCameras = GearCatalogCache.allCameras(customCameras: store.customCameras)
        let allLenses = GearCatalogCache.allLensEntries(customLenses: store.customLenses)

        let filteredCameras: [CameraGearSpec] = {
            let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return allCameras }
            return allCameras
                .map { ($0, fuzzyMatchScore(query: q, target: "\($0.brand) \($0.model) \($0.mount) \($0.fixedLensName)")) }
                .filter { $0.1 > 0 }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        }()

        let camerasByGroup: [(String, [CameraGearSpec])] = {
            let majorSet = Set(MAJOR_CAMERA_BRAND_ORDER)
            var groups: [String: [CameraGearSpec]] = [:]
            var otherList: [CameraGearSpec] = []

            for cam in filteredCameras {
                if majorSet.contains(cam.brand) || cam.isCustom {
                    groups[cam.brand, default: []].append(cam)
                } else {
                    otherList.append(cam)
                }
            }

            var result: [(String, [CameraGearSpec])] = []
            for brand in groups.keys.sorted() where !majorSet.contains(brand) {
                if let list = groups[brand], !list.isEmpty {
                    result.append((brand, list))
                }
            }
            for brand in MAJOR_CAMERA_BRAND_ORDER {
                if let list = groups[brand], !list.isEmpty {
                    result.append((brand, list))
                }
            }
            if !otherList.isEmpty {
                let sortedOthers = otherList.sorted {
                    "\($0.brand) \($0.model)" < "\($1.brand) \($1.model)"
                }
                result.append((OTHER_BRANDS_GROUP_TITLE, sortedOthers))
            }
            return result
        }()

        VStack(alignment: .leading, spacing: 14) {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.snappy(duration: 0.28, extraBounce: 0.0)) {
                    isExpanded.toggle()
                    if !isExpanded {
                        expandedCameraId = nil
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    if activeGear.hasCamera,
                       let camBrand = allCameras.first(where: { $0.id == activeGear.cameraId })?.brand {
                        CameraBrandLogo(brand: camBrand, size: 36)
                    } else {
                        Image(systemName: "camera.aperture")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(activeGear.hasCamera ? Palette.accent : Palette.dim)
                            .frame(width: 36, height: 36)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(activeGear.hasCamera ? activeGear.cameraName : "Camera & Lens")
                            .font(AppTypography.next(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)

                        if activeGear.hasCamera {
                            let sub = activeGear.hasLens
                                ? activeGear.lensName
                                : "\(formatShutterStopLabel(activeGear.minShutter)) \u{2013} \(formatShutterStopLabel(activeGear.maxShutter))"
                            Text(sub)
                                .font(AppTypography.next(size: 12, weight: .medium))
                                .foregroundStyle(Palette.dim)
                                .lineLimit(1)
                        } else {
                            Text("All stops unlocked")
                                .font(AppTypography.next(size: 12, weight: .medium))
                                .foregroundStyle(Palette.dim)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    Text(isExpanded ? "Done" : (activeGear.hasCamera ? "Change" : "Select"))
                        .font(AppTypography.next(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().overlay(Color.white.opacity(0.08))

                if activeGear.hasCamera {
                    HStack {
                        Text(activeGear.hasLens ? "\(activeGear.cameraName) \u{00B7} \(activeGear.lensName)" : activeGear.cameraName)
                            .font(AppTypography.next(size: 13, weight: .medium))
                            .foregroundStyle(Palette.dim)
                            .lineLimit(1)

                        Spacer()

                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.snappy(duration: 0.24)) {
                                store.activeGear = .unloaded
                            }
                        } label: {
                            Text("Clear")
                                .font(AppTypography.next(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.bad)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Picker("Gear Category", selection: $gearSubTab.animation(.snappy(duration: 0.24))) {
                    Text("Cameras").tag(0)
                    Text("Lenses").tag(1)
                    Text("Custom").tag(2)
                }
                .pickerStyle(.segmented)

                if gearSubTab == 0 {
                    VStack(spacing: 8) {
                        ForEach(camerasByGroup, id: \.0) { groupTitle, groupCameras in
                            let isGroupOpen = !searchQuery.isEmpty || expandedBrand == groupTitle

                            CameraBrandGroupView(
                                groupTitle: groupTitle,
                                cameras: groupCameras,
                                isExpanded: isGroupOpen,
                                activeGear: activeGear,
                                expandedCameraId: $expandedCameraId,
                                allLensEntries: allLenses,
                                inlineFocalCategory: $inlineFocalCategory,
                                onToggleBrand: {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    withAnimation(.snappy(duration: 0.26, extraBounce: 0.0)) {
                                        if expandedBrand == groupTitle {
                                            expandedBrand = nil
                                            expandedCameraId = nil
                                        } else {
                                            expandedBrand = groupTitle
                                            expandedCameraId = nil
                                        }
                                    }
                                },
                                onMountProfile: { profile in
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    withAnimation(.snappy(duration: 0.28, extraBounce: 0.0)) {
                                        store.activeGear = profile
                                        expandedCameraId = nil
                                        expandedBrand = nil
                                        isExpanded = false
                                    }
                                }
                            )
                        }
                    }
                } else if gearSubTab == 1 {
                    StandaloneLensBrowser(
                        activeGear: activeGear,
                        allLensEntries: allLenses,
                        searchQuery: searchQuery,
                        focalCategory: $lensFocalCategory,
                        onMountLens: { lens in
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            var updated = activeGear
                            updated.lensId = lens.id
                            updated.lensName = lens.model
                            updated.minAperture = lens.minAperture
                            updated.maxAperture = lens.maxAperture
                            withAnimation(.snappy(duration: 0.28, extraBounce: 0.0)) {
                                store.activeGear = updated
                                isExpanded = false
                            }
                        }
                    )
                } else {
                    CustomGearBuilderView(
                        initialSearchText: searchQuery,
                        onCreatedCamera: { cam, profile in
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            store.addCustomCamera(cam)
                            withAnimation(.snappy(duration: 0.28, extraBounce: 0.0)) {
                                store.activeGear = profile
                                gearSubTab = 0
                                isExpanded = false
                            }
                        },
                        onCreatedLens: { lens in
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            store.addCustomLens(lens)
                            var updated = store.activeGear
                            updated.lensId = lens.id
                            updated.lensName = lens.model
                            updated.minAperture = lens.minAperture
                            updated.maxAperture = lens.maxAperture
                            withAnimation(.snappy(duration: 0.28, extraBounce: 0.0)) {
                                store.activeGear = updated
                                gearSubTab = 0
                                isExpanded = false
                            }
                        }
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
                )
        )
    }
}

// MARK: - Camera Brand Group (Pure Geometric Brand Emblem + Clean Non-Redundant Rows)

private struct CameraBrandGroupView: View {
    let groupTitle: String
    let cameras: [CameraGearSpec]
    let isExpanded: Bool
    let activeGear: ActiveGearProfile
    @Binding var expandedCameraId: String?
    let allLensEntries: [PrewarmedLensEntry]
    @Binding var inlineFocalCategory: FocalLengthCategory
    let onToggleBrand: () -> Void
    let onMountProfile: (ActiveGearProfile) -> Void

    var body: some View {
        let hasActiveCam = cameras.contains(where: { $0.id == activeGear.cameraId })
        let isOtherGroup = groupTitle == OTHER_BRANDS_GROUP_TITLE

        VStack(spacing: 0) {
            Button(action: onToggleBrand) {
                HStack(spacing: 12) {
                    if !isOtherGroup {
                        CameraBrandLogo(brand: groupTitle, size: 30)
                    } else {
                        CameraBrandLogo(brand: "Classic", size: 30)
                    }

                    Text(groupTitle)
                        .font(AppTypography.next(size: 15, weight: .semibold))
                        .foregroundStyle(hasActiveCam ? Palette.accent : Palette.text)

                    Spacer()

                    Text("\(cameras.count)")
                        .font(AppTypography.mono(size: 12, weight: .medium))
                        .foregroundStyle(Palette.dim)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.dim)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .overlay(Color.white.opacity(0.07))
                    .padding(.horizontal, 12)

                VStack(spacing: 4) {
                    ForEach(cameras) { cam in
                        let isMounted = cam.id == activeGear.cameraId
                        let isCardOpen = expandedCameraId == cam.id
                        let displayTitle = isOtherGroup && !cam.model.lowercased().hasPrefix(cam.brand.lowercased())
                            ? "\(cam.brand) \(cam.model)"
                            : cam.model

                        VStack(alignment: .leading, spacing: 0) {
                            Button {
                                if cam.isFixed {
                                    // Fixed-lens cameras already have their lens built in — mount immediately in 1 tap!
                                    onMountProfile(
                                        ActiveGearProfile(
                                            cameraId: cam.id,
                                            cameraName: displayTitle,
                                            mount: "Fixed",
                                            isFixedLens: true,
                                            minShutter: cam.minShutter,
                                            maxShutter: cam.maxShutter,
                                            lensId: "\(cam.id)_fixed",
                                            lensName: cam.fixedLensName,
                                            minAperture: cam.fixedMinAperture,
                                            maxAperture: cam.fixedMaxAperture
                                        )
                                    )
                                } else {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    withAnimation(.snappy(duration: 0.24, extraBounce: 0.0)) {
                                        expandedCameraId = isCardOpen ? nil : cam.id
                                        inlineFocalCategory = .all
                                    }
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    if isOtherGroup {
                                        CameraBrandLogo(brand: cam.brand, size: 24)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(displayTitle)
                                            .font(AppTypography.next(size: 15, weight: .semibold))
                                            .foregroundStyle(isMounted ? Palette.accent : Palette.text)
                                            .lineLimit(1)

                                        // Subtitle shows ONLY the built-in lens (if fixed) OR the shutter speed range (never repeating the mount!)
                                        let subText = cam.isFixed
                                            ? cam.fixedLensName
                                            : "\(formatShutterStopLabel(cam.minShutter)) \u{2013} \(formatShutterStopLabel(cam.maxShutter))"
                                        Text(subText)
                                            .font(AppTypography.next(size: 12, weight: .medium))
                                            .foregroundStyle(Palette.dim)
                                            .lineLimit(1)
                                    }

                                    Spacer(minLength: 8)

                                    if isMounted {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(Palette.accent)
                                    } else {
                                        Text(cam.isFixed ? "Fixed" : formatMountBadge(cam.mount))
                                            .font(AppTypography.mono(size: 11, weight: .medium))
                                            .foregroundStyle(Palette.dim)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if isCardOpen && !cam.isFixed {
                                CameraInlineLensPicker(
                                    camera: cam,
                                    displayCameraTitle: displayTitle,
                                    activeGear: activeGear,
                                    allLensEntries: allLensEntries,
                                    focalCategory: $inlineFocalCategory,
                                    onMountProfile: onMountProfile
                                )
                                .padding(.horizontal, 12)
                                .padding(.bottom, 12)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isCardOpen ? Color.white.opacity(0.05) : (isMounted ? Palette.accent.opacity(0.08) : Color.clear))
                        )
                    }
                }
                .padding(8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(hasActiveCam ? Palette.accent.opacity(0.32) : Color.white.opacity(0.06), lineWidth: 0.75)
                )
        )
        .clipped()
    }
}

// MARK: - Concise 1-Tap Lens Picker for Interchangeable Bodies (No Search Bar Clutter)

private struct CameraInlineLensPicker: View {
    let camera: CameraGearSpec
    let displayCameraTitle: String
    let activeGear: ActiveGearProfile
    let allLensEntries: [PrewarmedLensEntry]
    @Binding var focalCategory: FocalLengthCategory
    let onMountProfile: (ActiveGearProfile) -> Void

    var body: some View {
        let mountLenses = allLensEntries.filter {
            $0.lens.mount.caseInsensitiveCompare(camera.mount) == .orderedSame
        }

        let visibleLenses = mountLenses.filter {
            matchesFocalCategory(model: $0.lens.model, category: focalCategory)
        }

        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Color.white.opacity(0.08))

            HStack {
                Text("Select Lens")
                    .font(AppTypography.next(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.dim)

                Spacer()

                Button {
                    onMountProfile(
                        ActiveGearProfile(
                            cameraId: camera.id,
                            cameraName: displayCameraTitle,
                            mount: camera.mount,
                            isFixedLens: false,
                            minShutter: camera.minShutter,
                            maxShutter: camera.maxShutter,
                            lensId: "",
                            lensName: "",
                            minAperture: 1.0,
                            maxAperture: 32.0
                        )
                    )
                } label: {
                    Text("Body Only")
                        .font(AppTypography.next(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
            }

            // Only show focal length segmented filter when this mount has > 8 lenses
            if mountLenses.count > 8 {
                Picker("Focal Length", selection: $focalCategory.animation(.snappy(duration: 0.20))) {
                    ForEach(FocalLengthCategory.allCases) { cat in
                        Text(cat.label).tag(cat)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(spacing: 4) {
                ForEach(Array(visibleLenses.prefix(24))) { entry in
                    let spec = entry.lens
                    let isChosen = activeGear.cameraId == camera.id && activeGear.lensId == spec.id

                    Button {
                        onMountProfile(
                            ActiveGearProfile(
                                cameraId: camera.id,
                                cameraName: displayCameraTitle,
                                mount: camera.mount,
                                isFixedLens: false,
                                minShutter: camera.minShutter,
                                maxShutter: camera.maxShutter,
                                lensId: spec.id,
                                lensName: spec.model,
                                minAperture: spec.minAperture,
                                maxAperture: spec.maxAperture
                            )
                        )
                    } label: {
                        HStack(spacing: 8) {
                            Text(spec.model)
                                .font(AppTypography.next(size: 13, weight: .medium))
                                .foregroundStyle(isChosen ? Palette.accent : Palette.text)
                                .lineLimit(1)

                            Spacer()

                            Text(formatApertureRange(spec.minAperture, spec.maxAperture))
                                .font(AppTypography.mono(size: 11, weight: .medium))
                                .foregroundStyle(Palette.dim)

                            if isChosen {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isChosen ? Palette.accent.opacity(0.12) : Color.white.opacity(0.035))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Standalone Lens Browser

private struct StandaloneLensBrowser: View {
    let activeGear: ActiveGearProfile
    let allLensEntries: [PrewarmedLensEntry]
    let searchQuery: String
    @Binding var focalCategory: FocalLengthCategory
    let onMountLens: (LensGearSpec) -> Void

    var body: some View {
        let filtered = allLensEntries.filter { entry in
            guard matchesFocalCategory(model: entry.lens.model, category: focalCategory) else { return false }
            let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty { return true }
            return fuzzyMatchScore(query: q, target: "\(entry.lens.brand) \(entry.lens.model) \(entry.lens.mount)") > 0
        }

        VStack(alignment: .leading, spacing: 10) {
            Picker("Focal Length", selection: $focalCategory.animation(.snappy(duration: 0.20))) {
                ForEach(FocalLengthCategory.allCases) { cat in
                    Text(cat.label).tag(cat)
                }
            }
            .pickerStyle(.segmented)

            VStack(spacing: 4) {
                ForEach(Array(filtered.prefix(30))) { entry in
                    let spec = entry.lens
                    let isMounted = activeGear.lensId == spec.id
                    Button {
                        onMountLens(spec)
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(spec.model)
                                    .font(AppTypography.next(size: 14, weight: .semibold))
                                    .foregroundStyle(isMounted ? Palette.accent : Palette.text)
                                    .lineLimit(1)
                                Text("\(formatMountBadge(spec.mount)) \u{00B7} \(formatApertureRange(spec.minAperture, spec.maxAperture))")
                                    .font(AppTypography.next(size: 12, weight: .medium))
                                    .foregroundStyle(Palette.dim)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if isMounted {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isMounted ? Palette.accent.opacity(0.10) : Color.white.opacity(0.035))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Custom Gear Builder

private struct CustomGearBuilderView: View {
    let initialSearchText: String
    let onCreatedCamera: (CameraGearSpec, ActiveGearProfile) -> Void
    let onCreatedLens: (LensGearSpec) -> Void

    @State private var mode: Int = 0 // 0 = Fixed Camera, 1 = Body, 2 = Lens
    @State private var brand: String = "Custom"
    @State private var modelName: String = ""
    @State private var fixedLensName: String = "40mm f/2.8"
    @State private var mountName: String = "Leica M"
    @State private var fastestShutterIdx: Int = 14 // 1/500
    @State private var slowestShutterIdx: Int = 5  // 1s
    @State private var widestApertureIdx: Int = 8  // f/2.8
    @State private var smallestApertureIdx: Int = 20 // f/22

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Custom Type", selection: $mode) {
                Text("Fixed").tag(0)
                Text("Body").tag(1)
                Text("Lens").tag(2)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                TextField("Brand", text: $brand)
                    .font(AppTypography.next(size: 13, weight: .regular))
                    .foregroundStyle(Palette.text)
                    .padding(10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                TextField(mode == 2 ? "Lens Model" : "Camera Model", text: $modelName)
                    .font(AppTypography.next(size: 13, weight: .regular))
                    .foregroundStyle(Palette.text)
                    .padding(10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if mode == 0 {
                TextField("Lens (e.g. 40mm f/2.8)", text: $fixedLensName)
                    .font(AppTypography.next(size: 13, weight: .regular))
                    .foregroundStyle(Palette.text)
                    .padding(10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                TextField("Mount (e.g. Leica M)", text: $mountName)
                    .font(AppTypography.next(size: 13, weight: .regular))
                    .foregroundStyle(Palette.text)
                    .padding(10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if mode != 2 {
                let fastStop = ALL_ANALOG_SHUTTER_STOPS[fastestShutterIdx.clamped(to: 0...(ALL_ANALOG_SHUTTER_STOPS.count - 1))]
                let slowStop = ALL_ANALOG_SHUTTER_STOPS[slowestShutterIdx.clamped(to: 0...(ALL_ANALOG_SHUTTER_STOPS.count - 1))]
                Stepper {
                    LabeledContent("Fastest", value: formatShutterStopLabel(fastStop))
                        .font(AppTypography.next(size: 13, weight: .medium))
                } onIncrement: {
                    fastestShutterIdx = min(fastestShutterIdx + 1, ALL_ANALOG_SHUTTER_STOPS.count - 1)
                } onDecrement: {
                    fastestShutterIdx = max(fastestShutterIdx - 1, 6)
                }

                Stepper {
                    LabeledContent("Slowest", value: formatShutterStopLabel(slowStop))
                        .font(AppTypography.next(size: 13, weight: .medium))
                } onIncrement: {
                    slowestShutterIdx = min(slowestShutterIdx + 1, 10)
                } onDecrement: {
                    slowestShutterIdx = max(slowestShutterIdx - 1, 0)
                }
            }

            if mode != 1 {
                let wideF = ALL_ANALOG_APERTURE_STOPS[widestApertureIdx.clamped(to: 0...(ALL_ANALOG_APERTURE_STOPS.count - 1))]
                let smallF = ALL_ANALOG_APERTURE_STOPS[smallestApertureIdx.clamped(to: 0...(ALL_ANALOG_APERTURE_STOPS.count - 1))]
                Stepper {
                    LabeledContent("Max Aperture", value: String(format: "f/%.1f", wideF).replacingOccurrences(of: ".0", with: ""))
                        .font(AppTypography.next(size: 13, weight: .medium))
                } onIncrement: {
                    widestApertureIdx = min(widestApertureIdx + 1, 14)
                } onDecrement: {
                    widestApertureIdx = max(widestApertureIdx - 1, 0)
                }

                Stepper {
                    LabeledContent("Min Aperture", value: String(format: "f/%.1f", smallF).replacingOccurrences(of: ".0", with: ""))
                        .font(AppTypography.next(size: 13, weight: .medium))
                } onIncrement: {
                    smallestApertureIdx = min(smallestApertureIdx + 1, ALL_ANALOG_APERTURE_STOPS.count - 1)
                } onDecrement: {
                    smallestApertureIdx = max(smallestApertureIdx - 1, 12)
                }
            }

            let trimmedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (initialSearchText.isEmpty ? "Custom Rig" : initialSearchText)
                : modelName.trimmingCharacters(in: .whitespacesAndNewlines)

            Button {
                let cleanBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom" : brand.trimmingCharacters(in: .whitespacesAndNewlines)
                let fastStop = ALL_ANALOG_SHUTTER_STOPS[fastestShutterIdx.clamped(to: 0...(ALL_ANALOG_SHUTTER_STOPS.count - 1))]
                let slowStop = ALL_ANALOG_SHUTTER_STOPS[slowestShutterIdx.clamped(to: 0...(ALL_ANALOG_SHUTTER_STOPS.count - 1))]
                let wideF = ALL_ANALOG_APERTURE_STOPS[widestApertureIdx.clamped(to: 0...(ALL_ANALOG_APERTURE_STOPS.count - 1))]
                let smallF = ALL_ANALOG_APERTURE_STOPS[smallestApertureIdx.clamped(to: 0...(ALL_ANALOG_APERTURE_STOPS.count - 1))]

                if mode == 2 {
                    let lens = LensGearSpec(
                        id: "custom_lens_\(Int(Date().timeIntervalSince1970))",
                        brand: cleanBrand,
                        model: trimmedModel,
                        mount: mountName,
                        minAperture: wideF,
                        maxAperture: smallF,
                        isCustom: true
                    )
                    onCreatedLens(lens)
                } else {
                    let isFixed = (mode == 0)
                    let camId = "custom_cam_\(Int(Date().timeIntervalSince1970))"
                    let cam = CameraGearSpec(
                        id: camId,
                        brand: cleanBrand,
                        model: trimmedModel,
                        isFixed: isFixed,
                        mount: isFixed ? "Fixed" : mountName,
                        minShutter: slowStop,
                        maxShutter: fastStop,
                        fixedLensName: isFixed ? fixedLensName : "",
                        fixedMinAperture: isFixed ? wideF : 0.0,
                        fixedMaxAperture: isFixed ? smallF : 0.0,
                        isCustom: true
                    )
                    let profile = ActiveGearProfile(
                        cameraId: camId,
                        cameraName: trimmedModel,
                        mount: isFixed ? "Fixed" : mountName,
                        isFixedLens: isFixed,
                        minShutter: slowStop,
                        maxShutter: fastStop,
                        lensId: isFixed ? "\(camId)_fixed" : "",
                        lensName: isFixed ? fixedLensName : "",
                        minAperture: isFixed ? wideF : 1.4,
                        maxAperture: isFixed ? smallF : 22.0
                    )
                    onCreatedCamera(cam, profile)
                }
            } label: {
                Text("Mount \(trimmedModel)")
                    .font(AppTypography.next(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Palette.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
