import SwiftUI
import UIKit

// MARK: - Film Logbook

/// Destinations pushed from the Roll tab. Value-based so the tab can pop back
/// to the roll after a film is loaded.
private enum FilmRoute: Hashable {
    case library
    case family(FilmFamily)
    case customFilm
    case gear
}

/// The logbook is a three-tab sheet: the loaded roll, the logged frames and the
/// lab-scan matcher. Every screen below is a plain `List`/`Form` so the system
/// supplies the chrome, separators, swipe actions and Dynamic Type.
struct FilmLogbookSheet: View {
    @ObservedObject var store: FilmLogStore
    var initialTab: Int = 0

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Int = 0
    @State private var shareSheetItem: ShareSheetItem?
    @State private var rollPath = NavigationPath()

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $rollPath) {
                RollScreen(store: store, shareSheetItem: $shareSheetItem, path: $rollPath)
            }
            .tabItem { Label("Roll", systemImage: "film") }
            .tag(0)

            NavigationStack {
                FramesScreen(store: store, shareSheetItem: $shareSheetItem)
            }
            .tabItem { Label("Frames", systemImage: "photo.on.rectangle") }
            .tag(1)

            NavigationStack {
                ScanMatcherTabView(store: store) { items in
                    shareSheetItem = ShareSheetItem(items: items)
                }
                .navigationTitle("Scans")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .tabItem { Label("Scans", systemImage: "photo.stack") }
            .tag(2)
        }
        .tint(Palette.accent)
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { selectedTab = initialTab }
        .sheet(item: $shareSheetItem) { item in
            ActivityShareSheet(items: item.items)
        }
    }
}

// MARK: - Roll

private struct RollScreen: View {
    @ObservedObject var store: FilmLogStore
    @Binding var shareSheetItem: ShareSheetItem?
    @Binding var path: NavigationPath

    @Environment(\.dismiss) private var dismiss

    private var roll: FilmRollState { store.rollState }
    private var gear: ActiveGearProfile { store.activeGear }

    private var rollFrames: [LoggedFrame] {
        store.loggedFrames.filter {
            $0.rollNumber == roll.rollNumber && $0.filmName == roll.filmName
        }
    }

    /// The active body's brand, so the log shows the real emblem instead of a
    /// generic camera glyph.
    private var activeCameraBrand: String? {
        guard gear.hasCamera, !gear.cameraId.isEmpty else { return nil }
        return GearCatalogCache.allCameras(customCameras: store.customCameras)
            .first { $0.id == gear.cameraId }?
            .brand
    }

    var body: some View {
        List {
            Section {
                NavigationLink(value: FilmRoute.library) {
                    ActiveRollRow(roll: roll)
                }
                .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))

                if !roll.isUnloaded {
                    HoldActionRow(
                        title: "Hold to complete roll",
                        workingTitle: "Completing roll",
                        doneTitle: "Roll completed",
                        systemImage: "film",
                        holdDuration: 1.1
                    ) {
                        completeRoll()
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } header: {
                Text("Current roll")
            } footer: {
                if roll.isUnloaded {
                    Text("Tap the card to choose a film stock.")
                } else {
                    Text("Tap the card to change film.")
                }
            }

            Section("Camera & Lens") {
                NavigationLink(value: FilmRoute.gear) {
                    HStack(spacing: 12) {
                        if let brand = activeCameraBrand {
                            CameraBrandLogo(brand: brand, size: 30)
                        } else {
                            ListGlyph(systemName: "camera.aperture")
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(gear.hasCamera ? gear.cameraName : "No camera selected")
                                .lineLimit(1)
                            Text(gear.hasLens
                                 ? gear.lensName
                                 : "\(formatShutterStopLabel(gear.minShutter)) – \(formatShutterStopLabel(gear.maxShutter))")
                                .font(Geist.text(.subheadline))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Section {
                Button {
                    Haptics.tap()
                    if let url = ExifAndXmpWriter.createRollCsvFileURL(rollFrames) {
                        shareSheetItem = ShareSheetItem(items: [url])
                    }
                } label: {
                    Label("Share roll as CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(rollFrames.isEmpty)

                Button {
                    Haptics.tap()
                    let summary = ExifAndXmpWriter.generateRollTextSummary(rollFrames)
                    if !summary.isEmpty {
                        shareSheetItem = ShareSheetItem(items: [summary])
                    }
                } label: {
                    Label("Share roll summary", systemImage: "text.alignleft")
                }
                .disabled(rollFrames.isEmpty)
            } header: {
                Text("Share")
            } footer: {
                Text("\(rollFrames.count) of \(roll.maxFrames) frames logged on this roll.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: FilmRoute.self) { route in
            switch route {
            case .library:
                FilmLibraryScreen(store: store)
            case .family(let family):
                FilmFamilyScreen(store: store, family: family) {
                    popToRoll()
                }
            case .customFilm:
                CustomFilmScreen(store: store) {
                    popToRoll()
                }
            case .gear:
                GearPickerScreen(store: store)
            }
        }
        .navigationTitle("Film Log")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Haptics.tap()
                    LocationCache.shared.requestPermissionAndRefresh()
                } label: {
                    Image(systemName: LocationCache.shared.lastKnownCoordinate != nil ? "location.fill" : "location")
                }
                .accessibilityLabel("Location tagging")
                .accessibilityValue(LocationCache.shared.lastKnownCoordinate != nil ? "On" : "Off")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            LocationCache.shared.refreshIfAuthorized()
        }
    }

    /// Lets the load animation breathe, then returns to the roll.
    private func popToRoll() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            path = NavigationPath()
        }
    }

    private func completeRoll() {
        var next = roll
        next.rollNumber = roll.rollNumber + 1
        next.filmName = ""
        next.currentFrame = 1
        next.isExpired = false
        withAnimation(.snappy) { store.rollState = next }
    }
}

private struct ActiveRollRow: View {
    let roll: FilmRollState

    var body: some View {
        if roll.isUnloaded {
            HStack(spacing: 14) {
                Image(systemName: "film")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.textSub)
                    .frame(width: 52, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text("No film loaded")
                        .font(Geist.text(.headline))
                    Text("Choose a stock to start shooting")
                        .font(Geist.text(.subheadline))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 14) {
                FilmCanisterArtwork(
                    brand: roll.filmName,
                    familyName: roll.filmName,
                    category: roll.category,
                    iso: roll.boxIso,
                    width: 52,
                    height: 48
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(shortFilmBadge(name: roll.filmName, iso: roll.boxIso))
                        .font(Geist.serifText(.headline))
                        .lineLimit(1)

                    Text(roll.isBonusFrames
                         ? "Frame +\(roll.currentFrame)"
                         : "Frame \(roll.currentFrame) of \(roll.maxFrames)")
                        .font(Geist.text(.subheadline))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if roll.isExpired {
                            Label("\(roll.yearsExpired) years expired", systemImage: "clock.arrow.circlepath")
                                .labelStyle(.titleAndIcon)
                                .font(Geist.text(.caption))
                                .foregroundStyle(Palette.slow)
                        }
                        if roll.activeExpiredCompEv > 0.05 {
                            Text(String(format: "+%.1f EV", roll.activeExpiredCompEv))
                                .font(Geist.text(.caption))
                                .foregroundStyle(Palette.slow)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Film library

private struct FilmLibraryScreen: View {
    @ObservedObject var store: FilmLogStore

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var category = "Color"

    private let categories = ["Color", "B&W", "Slide", "Custom"]

    private var families: [FilmFamily] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pool = trimmed.isEmpty
            ? BUILTIN_FILM_FAMILIES
            : BUILTIN_FILM_FAMILIES.filter { family in
                fuzzyMatchScore(query: trimmed, target: "\(family.brand) \(family.familyName) \(family.category)") > 0
                    || family.variants.contains { variant in
                        fuzzyMatchScore(query: trimmed, target: "\(variant.fullName) \(variant.iso)") > 0
                    }
            }
        guard trimmed.isEmpty, category != "Custom" else { return pool }
        return pool.filter { $0.category == category }
    }

    private var familiesByBrand: [(brand: String, families: [FilmFamily])] {
        var order: [String] = []
        var buckets: [String: [FilmFamily]] = [:]
        for family in families {
            if buckets[family.brand] == nil {
                order.append(family.brand)
                buckets[family.brand] = []
            }
            buckets[family.brand]?.append(family)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    var body: some View {
        List {
            Section {
                Picker("Category", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            if category == "Custom", query.isEmpty {
                customSection
            } else {
                ForEach(familiesByBrand, id: \.brand) { group in
                    Section(group.brand) {
                        ForEach(group.families) { family in
                            NavigationLink(value: FilmRoute.family(family)) {
                                FilmFamilyRow(family: family, isActive: isActive(family))
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, prompt: "Search film")
        .navigationTitle("Film")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var customSection: some View {
        Section {
            ForEach(store.customFilms) { stock in
                Button {
                    load(stock)
                } label: {
                    HStack(spacing: 12) {
                        FilmCanisterArtwork(
                            brand: stock.name,
                            familyName: stock.name,
                            category: stock.category,
                            iso: stock.iso,
                            width: 44,
                            height: 40
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stock.name)
                            Text("ISO \(stock.iso) · \(stock.category)")
                                .font(Geist.text(.subheadline))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        store.deleteCustomFilm(stock)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text("Your film")
        } footer: {
            if store.customFilms.isEmpty {
                Text("Save a stock once and it stays here.")
            }
        }

        Section {
            NavigationLink(value: FilmRoute.customFilm) {
                Label("Create custom film", systemImage: "plus")
            }
        }
    }

    private func isActive(_ family: FilmFamily) -> Bool {
        let roll = store.rollState
        guard !roll.isUnloaded else { return false }
        return family.variants.contains { variant in
            variant.fullName.caseInsensitiveCompare(roll.filmName) == .orderedSame && variant.iso == roll.boxIso
        }
    }

    private func load(_ stock: FilmStockPreset) {
        Haptics.success()
        var next = store.rollState
        if !next.isUnloaded { next.rollNumber += 1 }
        next.filmName = stock.name
        next.boxIso = stock.iso
        next.category = stock.category
        next.currentFrame = 1
        next.isExpired = false
        withAnimation(.snappy) { store.rollState = next }
    }
}

private struct FilmFamilyRow: View {
    let family: FilmFamily
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            FilmCanisterArtwork(
                brand: family.brand,
                familyName: family.familyName,
                category: family.category,
                iso: family.variants.first?.iso ?? 400,
                width: 44,
                height: 40
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(family.familyName)
                    .lineLimit(1)
                Text(summary)
                    .font(Geist.text(.subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isActive {
                Image(systemName: "checkmark")
                    .font(Geist.text(.body, .semibold))
                    .foregroundStyle(Palette.accent)
                    .accessibilityLabel("Loaded")
            }
        }
    }

    private var summary: String {
        if family.variants.count == 1 {
            return "ISO \(family.variants[0].iso) · \(family.category)"
        }
        return family.variants.map(\.label).joined(separator: " · ")
    }
}

private struct FilmFamilyScreen: View {
    @ObservedObject var store: FilmLogStore
    let family: FilmFamily
    var onLoaded: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var variantID: String = ""
    @State private var maxFrames: Int = 36
    @State private var expired = false
    @State private var expiredYears = 10

    private var variant: FilmVariant {
        family.variants.first { $0.id == variantID } ?? family.variants[0]
    }

    private var expiredComp: Double {
        guard expired, family.category != "Slide" else { return 0 }
        return ((Double(expiredYears) / 10.0) * 3.0).rounded() / 3.0
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    FilmCanisterArtwork(
                        brand: family.brand,
                        familyName: family.familyName,
                        category: family.category,
                        iso: variant.iso,
                        width: 56,
                        height: 50
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(family.familyName)
                            .font(Geist.text(.headline))
                        Text("\(family.brand) · \(family.category)")
                            .font(Geist.text(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if family.variants.count > 1 {
                Section("Stock") {
                    Picker("Speed", selection: $variantID) {
                        ForEach(family.variants) { variant in
                            Text(variant.label).tag(variant.id)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section("Roll") {
                Picker("Exposures", selection: $maxFrames) {
                    ForEach(ROLL_LENGTH_OPTIONS, id: \.self) { length in
                        Text("\(length)").tag(length)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Toggle("Expired film", isOn: $expired.animation(.snappy))

                if expired {
                    Stepper(value: $expiredYears, in: 1...50) {
                        LabeledContent("Expired \(expiredYears) \(expiredYears == 1 ? "year" : "years")",
                                       value: expiredComp > 0.04 ? String(format: "+%.1f EV", expiredComp) : "No compensation")
                    }
                }
            } header: {
                Text("Condition")
            } footer: {
                if expired && family.category == "Slide" {
                    Text("Slide film gets no expired-film compensation.")
                } else if expired {
                    Text("Adds \(String(format: "+%.1f EV", expiredComp)) of exposure compensation to every reading.")
                } else {
                    Text("Colour negative film gains about a stop of compensation per decade.")
                }
            }

            Section {
                HoldActionRow(
                    title: "Hold to load \(shortFilmBadge(name: variant.fullName, iso: variant.iso))",
                    workingTitle: "Loading film",
                    doneTitle: "Loaded",
                    systemImage: "film.stack",
                    holdDuration: 1.2
                ) {
                    load()
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } footer: {
                Text("Press and hold to load the roll and go back to the log.")
            }
        }
        .navigationTitle(family.familyName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if variantID.isEmpty { variantID = family.variants[0].id }
            maxFrames = store.rollState.maxFrames
            expired = false
        }
    }

    private func load() {
        Haptics.success()
        let currentYear = Calendar.current.component(.year, from: Date())
        var next = store.rollState
        if !next.isUnloaded { next.rollNumber += 1 }
        next.filmName = variant.fullName
        next.boxIso = variant.iso
        next.category = family.category
        next.currentFrame = 1
        next.maxFrames = maxFrames
        next.isExpired = expired
        next.expiredYear = expired ? currentYear - expiredYears : currentYear
        next.autoApplyExpiredComp = true
        withAnimation(.snappy) { store.rollState = next }
        onLoaded()
    }
}

private struct CustomFilmScreen: View {
    @ObservedObject var store: FilmLogStore
    var onLoaded: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var iso = 400
    @State private var category = "Color"
    @State private var maxFrames = 36

    private var trimmedName: String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Custom Film" : value
    }

    var body: some View {
        Form {
            Section("Film") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                Picker("Speed", selection: $iso) {
                    ForEach(FILM_ISO_STOPS, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Process", selection: $category) {
                    ForEach(["Color", "B&W", "Slide"], id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Roll") {
                Picker("Exposures", selection: $maxFrames) {
                    ForEach(ROLL_LENGTH_OPTIONS, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                HoldActionRow(
                    title: "Hold to save and load",
                    workingTitle: "Saving film",
                    doneTitle: "Saved",
                    systemImage: "film.stack",
                    holdDuration: 1.2
                ) {
                    create()
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } footer: {
                Text("The stock is saved to your custom films and loaded on the meter.")
            }
        }
        .navigationTitle("Custom Film")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func create() {
        Haptics.success()
        store.addCustomFilm(FilmStockPreset(name: trimmedName, iso: iso, category: category, isCustom: true))

        var next = store.rollState
        if !next.isUnloaded { next.rollNumber += 1 }
        next.filmName = trimmedName
        next.boxIso = iso
        next.category = category
        next.currentFrame = 1
        next.maxFrames = maxFrames
        next.isExpired = false
        withAnimation(.snappy) { store.rollState = next }
        onLoaded()
    }
}

// MARK: - Frames

private struct FramesScreen: View {
    @ObservedObject var store: FilmLogStore
    @Binding var shareSheetItem: ShareSheetItem?

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var groups: [(key: String, header: LoggedFrame, frames: [LoggedFrame])] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pool: [LoggedFrame] = trimmed.isEmpty ? store.loggedFrames : store.loggedFrames.filter { frame in
            fuzzyMatchScore(
                query: trimmed,
                target: "Roll \(frame.rollNumber) Frame \(frame.frameNumber) \(frame.filmName) \(frame.cameraName) \(frame.lensName) \(frame.note) \(frame.shutterSpeed) \(frame.aperture) ISO \(frame.iso)"
            ) > 0
        }

        let grouped = Dictionary(grouping: pool) { "\($0.rollNumber)|\($0.filmName)" }
        return grouped.keys.sorted(by: >).compactMap { key in
            guard let list = grouped[key], let header = list.first else { return nil }
            return (key: key, header: header, frames: list.sorted { $0.frameNumber > $1.frameNumber })
        }
    }

    var body: some View {
        List {
            ForEach(groups, id: \.key) { group in
                Section {
                    ForEach(group.frames) { frame in
                        NavigationLink {
                            FrameDetailScreen(
                                store: store,
                                frame: frame,
                                shareSheetItem: $shareSheetItem
                            )
                        } label: {
                            FrameRow(frame: frame, snapshot: store.loadSnapshotImage(frame.snapshotFileName))
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                store.deleteFrame(frameId: frame.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text(String(format: "Roll %02d · %@", group.header.rollNumber, shortFilmBadge(name: group.header.filmName, iso: group.header.iso)))
                } footer: {
                    Text("\(group.frames.count) logged")
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No Logged Frames" : "No Matches",
                    systemImage: query.isEmpty ? "photo.on.rectangle" : "magnifyingglass",
                    description: Text(query.isEmpty
                                      ? "Hold the shutter in the viewfinder, then tap the checkmark to log a frame."
                                      : "Try a different film, frame number or note.")
                )
            }
        }
        .searchable(text: $query, prompt: "Search frames")
        .navigationTitle("Frames")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

private struct FrameRow: View {
    let frame: LoggedFrame
    let snapshot: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let snapshot {
                    Image(uiImage: snapshot)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(Geist.text(.body))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Frame \(frame.frameNumber)")
                    .font(Geist.text(.body, .medium))
                    .monospacedDigit()

                Text("\(frame.shutterSpeed) · \(frame.aperture) · ISO \(frame.iso)")
                    .font(Geist.text(.subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !frame.note.isEmpty {
                    Text(frame.note)
                        .font(Geist.text(.footnote))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct FrameDetailScreen: View {
    @ObservedObject var store: FilmLogStore
    let frame: LoggedFrame
    @Binding var shareSheetItem: ShareSheetItem?

    @Environment(\.dismiss) private var dismiss
    @State private var note: String = ""
    @State private var showPhoto = false
    @State private var showDeleteConfirm = false

    private var snapshot: UIImage? { store.loadSnapshotImage(frame.snapshotFileName) }

    var body: some View {
        List {
            if let snapshot {
                Section {
                    Image(uiImage: snapshot)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 320)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture { showPhoto = true }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .accessibilityLabel("Frame photo")
                        .accessibilityAddTraits(.isButton)
                }
            }

            Section("Exposure") {
                LabeledContent("Shutter", value: frame.shutterSpeed)
                LabeledContent("Aperture", value: frame.aperture)
                LabeledContent("ISO", value: "\(frame.iso)")
                LabeledContent("Metered EV", value: String(format: "%.1f", frame.sceneEv))
                LabeledContent("Compensated EV", value: String(format: "%.1f", frame.compensatedEv))
                LabeledContent("Zone", value: "\(Roman.zone(frame.zone)) (\(frame.zone))")
                LabeledContent("Metering", value: frame.meterMode.capitalized)
                if frame.isAutoExposure {
                    LabeledContent("Mode", value: "Auto exposure")
                }
            }

            Section("Frame") {
                LabeledContent("Roll", value: String(format: "%02d", frame.rollNumber))
                LabeledContent("Frame", value: "\(frame.frameNumber) of \(frame.rollMaxFrames)")
                LabeledContent("Film", value: frame.filmName)
                if frame.isExpiredFilm {
                    LabeledContent("Expired", value: "\(frame.expiredYear)")
                }
                if !frame.cameraName.isEmpty {
                    LabeledContent("Camera", value: frame.cameraName)
                }
                if !frame.lensName.isEmpty {
                    LabeledContent("Lens", value: frame.lensName)
                }
                LabeledContent("Logged", value: frame.timestampIso.replacingOccurrences(of: "T", with: " "))
            }

            if let latitude = frame.latitude, let longitude = frame.longitude {
                Section("Location") {
                    LabeledContent("Coordinates", value: String(format: "%.5f, %.5f", latitude, longitude))
                }
            }

            Section("Note") {
                TextField("Add a note", text: $note, axis: .vertical)
                    .lineLimit(1...4)
            }

            Section {
                Button {
                    Haptics.tap()
                    let summary = ExifAndXmpWriter.generateRollTextSummary([frame])
                    if !summary.isEmpty {
                        shareSheetItem = ShareSheetItem(items: [summary])
                    }
                } label: {
                    Label("Share frame", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    Haptics.press()
                    showDeleteConfirm = true
                } label: {
                    Label("Delete frame", systemImage: "trash")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Frame \(frame.frameNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { note = frame.note }
        .onDisappear {
            if note != frame.note {
                store.updateFrameNote(frameId: frame.id, note: note)
            }
        }
        .confirmationDialog("Delete this frame?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.deleteFrame(frameId: frame.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The photo and exposure record are removed from this device.")
        }
        .fullScreenCover(isPresented: $showPhoto) {
            PhotoViewer(image: snapshot)
        }
    }
}

private struct PhotoViewer: View {
    let image: UIImage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Hold to act

/// Press-and-hold button used to load a film and to complete a roll.
///
/// The original app did this with a cranking film canister; this keeps the
/// idea but draws it with the same native styling as the rest of the log.
private struct HoldPressStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
    }
}

struct HoldActionRow: View {
    let title: String
    var workingTitle: String = "Working"
    var doneTitle: String = "Done"
    var systemImage: String = "film"
    var holdDuration: Double = 1.0
    var tint: Color = Palette.accent
    let onComplete: () -> Void

    private enum Phase { case idle, holding, done }

    @State private var phase: Phase = .idle
    @State private var progress: CGFloat = 0
    @State private var task: Task<Void, Never>?

    @State private var isPressed = false

    var body: some View {
        Button(action: {}) {
            bar
        }
        .buttonStyle(HoldPressStyle(isPressed: $isPressed))
        .onChange(of: isPressed) { _, pressed in
            if pressed {
                guard phase == .idle else { return }
                start()
            } else if phase == .holding {
                cancel()
            }
        }
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityHint("Press and hold, or use the action to do it immediately.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard phase == .idle else { return }
            perform()
            onComplete()
        }
        .onDisappear { task?.cancel() }
    }

    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(0.18))

                if progress > 0.001 {
                    Capsule()
                        .fill(tint)
                        .frame(width: geo.size.width * progress)
                }

                HStack(spacing: 10) {
                    Image(systemName: phase == .done ? "checkmark" : systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .rotationEffect(.degrees(Double(progress) * 540))

                    Text(label)
                        .font(Geist.text(.subheadline, .semibold))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if phase == .holding {
                        Text("\(Int((progress * 100).rounded()))%")
                            .font(Geist.monoText(.caption, .semibold))
                            .contentTransition(.numericText())
                    }
                }
                .padding(.horizontal, 16)
                .foregroundStyle(phase == .idle ? Palette.text : Palette.onAccent)
            }
        }
        .frame(height: 50)
        .contentShape(Capsule())
        .scaleEffect(phase == .done ? 0.98 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: phase)
    }

    private var label: String {
        switch phase {
        case .idle: return title
        case .holding: return workingTitle
        case .done: return doneTitle
        }
    }

    private func start() {
        Haptics.press()
        phase = .holding
        task?.cancel()
        task = Task { @MainActor in
            let started = Date()
            var lastTick = -1
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(started)
                let raw = min(1, max(0, elapsed / holdDuration))
                progress = CGFloat(raw)

                let tick = Int(raw * 10)
                if tick != lastTick {
                    lastTick = tick
                    if tick > 0 && tick < 10 { Haptics.rigid() }
                }

                if raw >= 1 {
                    perform()
                    onComplete()
                    try? await Task.sleep(nanoseconds: 650_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.snappy) {
                        progress = 0
                        phase = .idle
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }

    private func cancel() {
        task?.cancel()
        task = nil
        Haptics.tap()
        withAnimation(.snappy(duration: 0.2)) {
            progress = 0
            phase = .idle
        }
    }

    private func perform() {
        Haptics.success()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
            progress = 1
            phase = .done
        }
    }
}
