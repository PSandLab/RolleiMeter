import SwiftUI
import UIKit

private let MAJOR_CAMERA_BRAND_ORDER: [String] = [
    "Leica", "Nikon", "Canon", "Pentax", "Olympus",
    "Minolta", "Contax", "Fujifilm", "Hasselblad", "Mamiya",
    "Rollei", "Yashica", "Voigtländer", "Ricoh", "Konica"
]

private let OTHER_BRANDS_GROUP_TITLE = "Other & Boutique Classics"

// MARK: - Gear Setup Section (Clean iOS 27 Collapsible Card)

struct GearSetupSection: View {
    @ObservedObject var store: FilmLogStore
    let searchQuery: String

    @State private var isExpanded: Bool = false
    @State private var gearSubTab: Int = 0 // 0 = Cameras, 1 = Lenses, 2 = Custom
    @State private var expandedBrand: String? = nil
    @State private var expandedCameraId: String? = nil
    @State private var inlineIncludeAdapter: Bool = false
    @State private var inlineAdapterMountFilter: String = "All"
    @State private var inlineFocalCategory: FocalLengthCategory = .all
    @State private var inlineLensSearchQuery: String = ""
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
            // Custom brands first if any
            for brand in groups.keys.sorted() where !majorSet.contains(brand) {
                if let list = groups[brand], !list.isEmpty {
                    result.append((brand, list))
                }
            }
            // Major brands in curated order
            for brand in MAJOR_CAMERA_BRAND_ORDER {
                if let list = groups[brand], !list.isEmpty {
                    result.append((brand, list))
                }
            }
            // Consolidated Other & Boutique Classics at the bottom
            if !otherList.isEmpty {
                let sortedOthers = otherList.sorted {
                    "\($0.brand) \($0.model)" < "\($1.brand) \($1.model)"
                }
                result.append((OTHER_BRANDS_GROUP_TITLE, sortedOthers))
            }
            return result
        }()

        VStack(alignment: .leading, spacing: 14) {
            // Main Card Header
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.snappy(duration: 0.30, extraBounce: 0.0)) {
                    isExpanded.toggle()
                    if !isExpanded {
                        expandedCameraId = nil
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(activeGear.hasCamera ? Palette.accent.opacity(0.16) : Color.white.opacity(0.06))
                            .frame(width: 42, height: 42)
                        Image(systemName: "camera.aperture")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(activeGear.hasCamera ? Palette.accent : Palette.dim)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("CAMERA & LENS")
                                .font(AppTypography.next(size: 11, weight: .semibold))
                                .tracking(1.2)
                                .foregroundStyle(Palette.dim)

                            if activeGear.hasCamera {
                                Text(activeGear.isFixedLens ? "FIXED" : formatMountBadge(activeGear.mount))
                                    .font(AppTypography.mono(size: 10, weight: .semibold))
                                    .foregroundStyle(Palette.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(Palette.accent.opacity(0.14), in: Capsule())
                            }
                        }

                        Text(activeGear.hasCamera ? activeGear.cameraName : "All Shutter & Aperture Stops")
                            .font(AppTypography.next(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)

                        if activeGear.hasCamera {
                            let shutterRange = "\(formatShutterStopLabel(activeGear.maxShutter))–\(formatShutterStopLabel(activeGear.minShutter))"
                            let lensSummary = activeGear.hasLens
                                ? "\(activeGear.lensName) (\(formatApertureRange(activeGear.minAperture, activeGear.maxAperture)))"
                                : "Body only"
                            Text("\(shutterRange)  \u{00B7}  \(lensSummary)")
                                .font(AppTypography.next(size: 12, weight: .medium))
                                .foregroundStyle(Palette.dim)
                                .lineLimit(1)
                        } else {
                            Text("Optional: clamp meter to a specific camera & lens")
                                .font(AppTypography.next(size: 12, weight: .medium))
                                .foregroundStyle(Palette.dim)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 5) {
                        Text(isExpanded ? "Done" : (activeGear.hasCamera ? "Change" : "Choose"))
                            .font(AppTypography.next(size: 13, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Palette.accent.opacity(0.12), in: Capsule())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().overlay(Color.white.opacity(0.08))

                if activeGear.hasCamera {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activeGear.cameraName)
                                .font(AppTypography.next(size: 14, weight: .semibold))
                                .foregroundStyle(Palette.text)
                            if activeGear.hasLens {
                                Text(activeGear.lensName)
                                    .font(AppTypography.next(size: 12, weight: .medium))
                                    .foregroundStyle(Palette.dim)
                            }
                        }
                        Spacer()
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.snappy(duration: 0.26)) {
                                store.activeGear = .unloaded
                            }
                        } label: {
                            Text("Remove Rig")
                                .font(AppTypography.next(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.bad)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(Palette.bad.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                // Native iOS Segmented Picker for Bodies / Lenses / Custom
                Picker("Gear Category", selection: $gearSubTab.animation(.snappy(duration: 0.25))) {
                    Text("Bodies").tag(0)
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
                                inlineIncludeAdapter: $inlineIncludeAdapter,
                                inlineAdapterMountFilter: $inlineAdapterMountFilter,
                                inlineFocalCategory: $inlineFocalCategory,
                                inlineLensSearchQuery: $inlineLensSearchQuery,
                                onToggleBrand: {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    withAnimation(.snappy(duration: 0.28, extraBounce: 0.0)) {
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
                                    withAnimation(.snappy(duration: 0.30, extraBounce: 0.0)) {
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
                            withAnimation(.snappy(duration: 0.30, extraBounce: 0.0)) {
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
                            withAnimation(.snappy(duration: 0.30, extraBounce: 0.0)) {
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
                            withAnimation(.snappy(duration: 0.30, extraBounce: 0.0)) {
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
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.75)
                )
        )
    }
}

// MARK: - Camera Brand Accordion (Clean Typography, Single-Open Smooth iOS Disclosure)

private struct CameraBrandGroupView: View {
    let groupTitle: String
    let cameras: [CameraGearSpec]
    let isExpanded: Bool
    let activeGear: ActiveGearProfile
    @Binding var expandedCameraId: String?
    let allLensEntries: [PrewarmedLensEntry]
    @Binding var inlineIncludeAdapter: Bool
    @Binding var inlineAdapterMountFilter: String
    @Binding var inlineFocalCategory: FocalLengthCategory
    @Binding var inlineLensSearchQuery: String
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
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 30, height: 30)
                            Image(systemName: "camera.on.rectangle")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.dim)
                        }
                    }

                    Text(groupTitle)
                        .font(AppTypography.next(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.text)

                    if hasActiveCam {
                        Circle()
                            .fill(Palette.accent)
                            .frame(width: 6, height: 6)
                    }

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
                                UISelectionFeedbackGenerator().selectionChanged()
                                withAnimation(.snappy(duration: 0.26, extraBounce: 0.0)) {
                                    expandedCameraId = isCardOpen ? nil : cam.id
                                    inlineIncludeAdapter = false
                                    inlineAdapterMountFilter = "All"
                                    inlineFocalCategory = .all
                                    inlineLensSearchQuery = ""
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(displayTitle)
                                            .font(AppTypography.next(size: 15, weight: .semibold))
                                            .foregroundStyle(isMounted ? Palette.accent : Palette.text)
                                            .lineLimit(1)

                                        let shutterText = "\(formatShutterStopLabel(cam.maxShutter))–\(formatShutterStopLabel(cam.minShutter))"
                                        let subText = cam.isFixed
                                            ? "\(shutterText)  \u{00B7}  \(cam.fixedLensName)"
                                            : "\(shutterText)  \u{00B7}  \(formatMountBadge(cam.mount)) mount"
                                        Text(subText)
                                            .font(AppTypography.next(size: 12, weight: .medium))
                                            .foregroundStyle(Palette.dim)
                                            .lineLimit(1)
                                    }

                                    Spacer(minLength: 8)

                                    if isMounted {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(Palette.accent)
                                    } else {
                                        Text(cam.isFixed ? "Fixed" : formatMountBadge(cam.mount))
                                            .font(AppTypography.mono(size: 11, weight: .medium))
                                            .foregroundStyle(Palette.dim)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.white.opacity(0.06), in: Capsule())
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if isCardOpen {
                                CameraInlineSetupPanel(
                                    camera: cam,
                                    activeGear: activeGear,
                                    allLensEntries: allLensEntries,
                                    includeAdapter: $inlineIncludeAdapter,
                                    adapterMountFilter: $inlineAdapterMountFilter,
                                    focalCategory: $inlineFocalCategory,
                                    lensSearchQuery: $inlineLensSearchQuery,
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
                        .strokeBorder(hasActiveCam ? Palette.accent.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 0.75)
                )
        )
        .clipped()
    }
}

// MARK: - Inline Camera & Lens Pairing Panel

private struct CameraInlineSetupPanel: View {
    let camera: CameraGearSpec
    let activeGear: ActiveGearProfile
    let allLensEntries: [PrewarmedLensEntry]
    @Binding var includeAdapter: Bool
    @Binding var adapterMountFilter: String
    @Binding var focalCategory: FocalLengthCategory
    @Binding var lensSearchQuery: String
    let onMountProfile: (ActiveGearProfile) -> Void

    @State private var selectedLens: LensGearSpec? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Color.white.opacity(0.08))

            if camera.isFixed {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(camera.fixedLensName)
                            .font(AppTypography.next(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.text)
                        Text("Built-in optic  \u{00B7}  \(formatApertureRange(camera.fixedMinAperture, camera.fixedMaxAperture))")
                            .font(AppTypography.next(size: 12, weight: .medium))
                            .foregroundStyle(Palette.dim)
                    }
                    Spacer()
                    Button {
                        onMountProfile(
                            ActiveGearProfile(
                                cameraId: camera.id,
                                cameraName: camera.model,
                                mount: "Fixed",
                                isFixedLens: true,
                                minShutter: camera.minShutter,
                                maxShutter: camera.maxShutter,
                                lensId: "\(camera.id)_fixed",
                                lensName: camera.fixedLensName,
                                minAperture: camera.fixedMinAperture,
                                maxAperture: camera.fixedMaxAperture
                            )
                        )
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text("Mount Camera")
                                .font(AppTypography.next(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Palette.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            } else {
                HStack {
                    Text("SELECT \(camera.mount.uppercased()) LENS")
                        .font(AppTypography.next(size: 11, weight: .semibold))
                        .tracking(1.0)
                        .foregroundStyle(Palette.dim)
                    Spacer()
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.snappy(duration: 0.22)) {
                            includeAdapter.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: includeAdapter ? "checkmark.circle.fill" : "link")
                                .font(.system(size: 11, weight: .semibold))
                            Text(includeAdapter ? "Adapted Mounts" : "Use Adapter")
                                .font(AppTypography.next(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(includeAdapter ? Color.black : Palette.dim)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(includeAdapter ? Palette.accent : Color.white.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if includeAdapter {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(ADAPTER_MOUNT_FILTERS, id: \.self) { mFilter in
                                let sel = adapterMountFilter == mFilter
                                Button {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    adapterMountFilter = mFilter
                                } label: {
                                    Text(mFilter)
                                        .font(AppTypography.next(size: 11, weight: .semibold))
                                        .foregroundStyle(sel ? Color.black : Palette.dim)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(sel ? Palette.accent : Color.white.opacity(0.06), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Focal length filter pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(FocalLengthCategory.allCases) { cat in
                            let sel = focalCategory == cat
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                focalCategory = cat
                            } label: {
                                Text(cat.label)
                                    .font(AppTypography.mono(size: 11, weight: .semibold))
                                    .foregroundStyle(sel ? Color.black : Palette.dim)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(sel ? Palette.accent : Color.white.opacity(0.06), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Lens filter field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.dim)
                    TextField("Filter lenses (e.g. 35mm, Summicron, f/1.4)\u{2026}", text: $lensSearchQuery)
                        .font(AppTypography.next(size: 13, weight: .regular))
                        .foregroundStyle(Palette.text)
                    if !lensSearchQuery.isEmpty {
                        Button {
                            lensSearchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.dim)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                let matchingLenses: [PrewarmedLensEntry] = allLensEntries.filter { entry in
                    let mountOk: Bool = {
                        if !includeAdapter {
                            return entry.lens.mount.caseInsensitiveCompare(camera.mount) == .orderedSame
                        } else {
                            return matchesAdaptedMount(lensMount: entry.lens.mount, filter: adapterMountFilter)
                        }
                    }()
                    guard mountOk else { return false }
                    guard matchesFocalCategory(model: entry.lens.model, category: focalCategory) else { return false }
                    let q = lensSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    if q.isEmpty { return true }
                    return fuzzyMatchScore(query: q, target: "\(entry.lens.brand) \(entry.lens.model) \(entry.lens.mount)") > 0
                }

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(matchingLenses.prefix(40)) { entry in
                            ForEach(entry.variants) { variant in
                                let spec = variant.spec
                                let isChosen = selectedLens?.id == spec.id
                                    || (selectedLens == nil && activeGear.lensId == spec.id)

                                Button {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    selectedLens = spec
                                } label: {
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(spec.model)
                                                .font(AppTypography.next(size: 13, weight: .semibold))
                                                .foregroundStyle(isChosen ? Palette.accent : Palette.text)
                                                .lineLimit(1)
                                            Text("\(variant.badge)  \u{00B7}  \(formatApertureRange(spec.minAperture, spec.maxAperture))")
                                                .font(AppTypography.next(size: 11, weight: .medium))
                                                .foregroundStyle(Palette.dim)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        if isChosen {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(Palette.accent)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(isChosen ? Palette.accent.opacity(0.14) : Color.white.opacity(0.04))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxHeight: 190)

                let effectiveLens = selectedLens ?? matchingLenses.first?.variants.first?.spec
                Button {
                    onMountProfile(
                        ActiveGearProfile(
                            cameraId: camera.id,
                            cameraName: camera.model,
                            mount: camera.mount,
                            isFixedLens: false,
                            minShutter: camera.minShutter,
                            maxShutter: camera.maxShutter,
                            lensId: effectiveLens?.id ?? "",
                            lensName: effectiveLens?.model ?? "",
                            minAperture: effectiveLens?.minAperture ?? 1.4,
                            maxAperture: effectiveLens?.maxAperture ?? 22.0
                        )
                    )
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text(effectiveLens != nil ? "Mount \(camera.model) + \(effectiveLens!.model)" : "Mount \(camera.model) (Body Only)")
                            .font(AppTypography.next(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Palette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(FocalLengthCategory.allCases) { cat in
                        let sel = focalCategory == cat
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            focalCategory = cat
                        } label: {
                            Text(cat.label)
                                .font(AppTypography.mono(size: 11, weight: .semibold))
                                .foregroundStyle(sel ? Color.black : Palette.dim)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(sel ? Palette.accent : Color.white.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let filtered = allLensEntries.filter { entry in
                guard matchesFocalCategory(model: entry.lens.model, category: focalCategory) else { return false }
                let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                if q.isEmpty { return true }
                return fuzzyMatchScore(query: q, target: "\(entry.lens.brand) \(entry.lens.model) \(entry.lens.mount)") > 0
            }

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filtered.prefix(60)) { entry in
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
                                    Text("\(spec.brand)  \u{00B7}  \(formatMountBadge(spec.mount))  \u{00B7}  \(formatApertureRange(spec.minAperture, spec.maxAperture))")
                                        .font(AppTypography.next(size: 12, weight: .medium))
                                        .foregroundStyle(Palette.dim)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if isMounted {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Palette.accent)
                                } else {
                                    Text("Mount")
                                        .font(AppTypography.next(size: 12, weight: .semibold))
                                        .foregroundStyle(Palette.accent)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Palette.accent.opacity(0.14), in: Capsule())
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isMounted ? Palette.accent.opacity(0.10) : Color.white.opacity(0.035))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
    }
}

// MARK: - Custom Gear Builder

private struct CustomGearBuilderView: View {
    let initialSearchText: String
    let onCreatedCamera: (CameraGearSpec, ActiveGearProfile) -> Void
    let onCreatedLens: (LensGearSpec) -> Void

    @State private var mode: Int = 0 // 0 = Fixed-Lens Camera, 1 = Interchangeable Body, 2 = Lens
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
                Text("Fixed Camera").tag(0)
                Text("Body Only").tag(1)
                Text("Lens").tag(2)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                TextField("Brand (e.g. Rollei)", text: $brand)
                    .font(AppTypography.next(size: 13, weight: .regular))
                    .foregroundStyle(Palette.text)
                    .padding(10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                TextField(mode == 2 ? "Lens (e.g. 50mm f/1.4)" : "Model Name", text: $modelName)
                    .font(AppTypography.next(size: 13, weight: .regular))
                    .foregroundStyle(Palette.text)
                    .padding(10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if mode == 0 {
                TextField("Built-in Lens (e.g. Sonnar 40mm f/2.8)", text: $fixedLensName)
                    .font(AppTypography.next(size: 13, weight: .regular))
                    .foregroundStyle(Palette.text)
                    .padding(10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                TextField("Mount (e.g. Leica M, Nikon F, M42)", text: $mountName)
                    .font(AppTypography.next(size: 13, weight: .regular))
                    .foregroundStyle(Palette.text)
                    .padding(10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if mode != 2 {
                let fastStop = ALL_ANALOG_SHUTTER_STOPS[fastestShutterIdx.clamped(to: 0...(ALL_ANALOG_SHUTTER_STOPS.count - 1))]
                let slowStop = ALL_ANALOG_SHUTTER_STOPS[slowestShutterIdx.clamped(to: 0...(ALL_ANALOG_SHUTTER_STOPS.count - 1))]
                Stepper {
                    LabeledContent("Fastest Shutter", value: formatShutterStopLabel(fastStop))
                        .font(AppTypography.next(size: 13, weight: .medium))
                } onIncrement: {
                    fastestShutterIdx = min(fastestShutterIdx + 1, ALL_ANALOG_SHUTTER_STOPS.count - 1)
                } onDecrement: {
                    fastestShutterIdx = max(fastestShutterIdx - 1, 6)
                }

                Stepper {
                    LabeledContent("Slowest Shutter", value: formatShutterStopLabel(slowStop))
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
                    LabeledContent("Widest Aperture", value: String(format: "f/%.1f", wideF).replacingOccurrences(of: ".0", with: ""))
                        .font(AppTypography.next(size: 13, weight: .medium))
                } onIncrement: {
                    widestApertureIdx = min(widestApertureIdx + 1, 14)
                } onDecrement: {
                    widestApertureIdx = max(widestApertureIdx - 1, 0)
                }

                Stepper {
                    LabeledContent("Smallest Aperture", value: String(format: "f/%.1f", smallF).replacingOccurrences(of: ".0", with: ""))
                        .font(AppTypography.next(size: 13, weight: .medium))
                } onIncrement: {
                    smallestApertureIdx = min(smallestApertureIdx + 1, ALL_ANALOG_APERTURE_STOPS.count - 1)
                } onDecrement: {
                    smallestApertureIdx = max(smallestApertureIdx - 1, 12)
                }
            }

            let trimmedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (initialSearchText.isEmpty ? "Custom Analog Rig" : initialSearchText)
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
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Save & Mount \(trimmedModel)")
                        .font(AppTypography.next(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
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
