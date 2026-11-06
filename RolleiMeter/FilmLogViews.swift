import SwiftUI
import UIKit

// MARK: - Film Logbook

private enum FilmRoute: Hashable {
    case library
    case family(FilmFamily)
    case customFilm
    case gear
}

struct FilmLogbookSheet: View {
    @ObservedObject var store: FilmLogStore
    var initialTab: Int = 0

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Int = 0
    @State private var shareSheetItem: ShareSheetItem?
    @State private var rollPath = NavigationPath()

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Roll", systemImage: "film", value: 0) {
                NavigationStack(path: $rollPath) {
                    RollView(store: store, path: $rollPath)
                }
            }

            Tab("Frames", systemImage: "photo.on.rectangle", value: 1) {
                NavigationStack {
                    FramesView(store: store)
                }
            }

            Tab("Scans", systemImage: "scanner", value: 2) {
                NavigationStack {
                    ScanMatcherTabView(store: store) { items in
                        shareSheetItem = ShareSheetItem(items: items)
                    }
                    .navigationTitle("Scans")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(role: .close) { dismiss() }
                        }
                    }
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { selectedTab = initialTab }
        .sheet(item: $shareSheetItem) { item in
            ActivityShareSheet(items: item.items)
        }
    }
}

// MARK: - Screen 1: Unified Interactive Film Chamber & Canister Rack (Roll tab)

struct RollView: View {
    @ObservedObject var store: FilmLogStore
    @Binding var path: NavigationPath

    @Environment(\.dismiss) private var dismiss

    @State private var stagedFamily: FilmFamily = BUILTIN_FILM_FAMILIES[0]
    @State private var stagedVariantID: String = ""
    @State private var stagedCustomStock: FilmStockPreset? = nil
    @State private var stagedFrames: Int = 36
    @State private var stagedExpired: Bool = false
    @State private var stagedExpiredYears: Int = 10
    @State private var selectedCategory: String = "Color"
    @State private var query: String = ""
    @State private var didInitializeStage: Bool = false

    private let categories = ["Color", "B&W", "Slide", "Custom"]

    private var roll: FilmRollState { store.rollState }
    private var gear: ActiveGearProfile { store.activeGear }

    private var stagedVariant: FilmVariant {
        stagedFamily.variants.first { $0.id == stagedVariantID } ?? stagedFamily.variants[0]
    }

    private var activeStagedName: String {
        stagedCustomStock?.name ?? stagedVariant.fullName
    }

    private var activeStagedISO: Int {
        stagedCustomStock?.iso ?? stagedVariant.iso
    }

    private var activeStagedCategory: String {
        stagedCustomStock?.category ?? stagedFamily.category
    }

    private var activeStagedBrand: String {
        stagedCustomStock?.name ?? stagedFamily.brand
    }

    private var activeStagedFamilyName: String {
        stagedCustomStock?.name ?? stagedFamily.familyName
    }

    private var isStagedAlreadyLoaded: Bool {
        !roll.isUnloaded
            && roll.filmName.caseInsensitiveCompare(activeStagedName) == .orderedSame
            && roll.boxIso == activeStagedISO
    }

    private var rollFrames: [LoggedFrame] {
        store.loggedFrames.filter {
            $0.rollNumber == roll.rollNumber && $0.filmName == roll.filmName
        }
    }

    private var logged: Int { rollFrames.count }

    private var activeCameraBrand: String? {
        guard gear.hasCamera, !gear.cameraId.isEmpty else { return nil }
        return GearCatalogCache.allCameras(customCameras: store.customCameras)
            .first { $0.id == gear.cameraId }?
            .brand
    }

    private var csvURL: URL {
        ExifAndXmpWriter.createRollCsvFileURL(rollFrames)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("film_roll_log.csv")
    }

    private var summaryText: String {
        ExifAndXmpWriter.generateRollTextSummary(rollFrames)
    }

    private var filteredFamilies: [FilmFamily] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pool = trimmed.isEmpty
            ? BUILTIN_FILM_FAMILIES
            : BUILTIN_FILM_FAMILIES.filter { family in
                fuzzyMatchScore(query: trimmed, target: "\(family.brand) \(family.familyName) \(family.category)") > 0
                    || family.variants.contains { variant in
                        fuzzyMatchScore(query: trimmed, target: "\(variant.fullName) \(variant.iso)") > 0
                    }
            }
        guard trimmed.isEmpty, selectedCategory != "Custom" else { return pool }
        return pool.filter { $0.category == selectedCategory }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                // 1. Interactive 35mm Leader-Pull Loading Chamber
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activeStagedName)
                                    .font(.headline)
                                Text("ISO \(activeStagedISO) · \(activeStagedCategory)")
                                    .font(.caption.weight(.medium).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if isStagedAlreadyLoaded {
                                Label("Frame \(roll.currentFrame)/\(roll.maxFrames)", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(Palette.good)
                            }
                        }

                        // Inline ISO Variant Pills (when the staged family has multiple speeds)
                        if stagedCustomStock == nil && stagedFamily.variants.count > 1 {
                            Picker("ISO Speed", selection: $stagedVariantID) {
                                ForEach(stagedFamily.variants) { option in
                                    Text(option.label).tag(option.id)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: stagedVariantID) { _, _ in
                                Haptics.tap()
                            }
                        }

                        // The Mechanical Leader-Pull Chamber
                        InteractiveFilmLeaderChamber(
                            brand: activeStagedBrand,
                            familyName: activeStagedFamilyName,
                            stockFullName: shortFilmBadge(name: activeStagedName, iso: activeStagedISO),
                            category: activeStagedCategory,
                            iso: activeStagedISO,
                            rollLength: stagedFrames,
                            isAlreadyLoaded: isStagedAlreadyLoaded
                        ) {
                            commitLoadedFilm()
                        }

                        // Inline Roll Length & Expired Controls
                        HStack(spacing: 10) {
                            Picker("Exposures", selection: $stagedFrames) {
                                ForEach([12, 16, 24, 36], id: \.self) { count in
                                    Text("\(count)").tag(count)
                                }
                            }
                            .pickerStyle(.segmented)

                            Button {
                                Haptics.tap()
                                withAnimation(.spring(response: 0.26, dampingFraction: 0.7)) {
                                    stagedExpired.toggle()
                                }
                            } label: {
                                Label(stagedExpired ? "+\( stagedExpiredYears / 10 ) EV" : "Exp", systemImage: stagedExpired ? "clock.badge.exclamationmark.fill" : "clock")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule()
                                            .fill(stagedExpired ? Palette.accent.opacity(0.22) : Color.secondary.opacity(0.14))
                                    )
                                    .foregroundStyle(stagedExpired ? Palette.accent : .primary)
                            }
                            .buttonStyle(.plain)
                        }

                        if stagedExpired {
                            Stepper(
                                "Expired \(stagedExpiredYears) yr (+\(String(format: "%.1f", (Double(stagedExpiredYears) / 10.0 * 3.0).rounded() / 3.0)) EV)",
                                value: $stagedExpiredYears,
                                in: 1...50
                            )
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .id("chamberTop")
                } header: {
                    Text("Film Loading Chamber")
                }

                // 2. Active Camera & Lens Row
                Section {
                    NavigationLink(value: FilmRoute.gear) {
                        cameraRow
                    }
                }

                // 3. Direct Canister Rack (Tap any canister to stage it in the Chamber)
                Section {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if selectedCategory == "Custom" && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ForEach(store.customFilms) { stock in
                            Button {
                                Haptics.press()
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.68)) {
                                    stagedCustomStock = stock
                                    proxy.scrollTo("chamberTop", anchor: .top)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    FilmCanisterArtwork(
                                        brand: stock.name,
                                        familyName: stock.name,
                                        category: stock.category,
                                        iso: stock.iso,
                                        width: 42,
                                        height: 40
                                    )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(stock.name)
                                            .foregroundStyle(.primary)
                                        Text("ISO \(stock.iso) · \(stock.category)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if stagedCustomStock?.id == stock.id {
                                        Text("IN CHAMBER")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(Palette.accent)
                                    }
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

                        NavigationLink(value: FilmRoute.customFilm) {
                            Label("Add Custom Film", systemImage: "plus")
                        }
                    } else {
                        ForEach(filteredFamilies) { family in
                            let isStaged = (stagedCustomStock == nil && stagedFamily.id == family.id)
                            Button {
                                Haptics.press()
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.68)) {
                                    stagedCustomStock = nil
                                    stagedFamily = family
                                    stagedVariantID = family.variants[0].id
                                    proxy.scrollTo("chamberTop", anchor: .top)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    FilmCanisterArtwork(
                                        brand: family.brand,
                                        familyName: family.familyName,
                                        category: family.category,
                                        iso: family.variants.first?.iso ?? 400,
                                        width: 42,
                                        height: 40
                                    )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(family.brand) \(family.familyName)")
                                            .font(.body.weight(isStaged ? .semibold : .regular))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)

                                        Text(family.variants.map(\.label).joined(separator: " · "))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    if isStaged {
                                        Text("IN CHAMBER")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Palette.accent.opacity(0.18), in: Capsule())
                                            .foregroundStyle(Palette.accent)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Select Canister for Chamber")
                }
            }
        }
        .searchable(text: $query, prompt: "Search film canisters")
        .navigationDestination(for: FilmRoute.self) { route in
            switch route {
            case .library:
                FilmLibraryScreen(store: store)
            case .family(let family):
                FilmStockView(store: store, family: family) {
                    popToRoll()
                }
            case .customFilm:
                CustomFilmScreen(store: store) {
                    popToRoll()
                }
            case .gear:
                CameraLensView(store: store, onFinish: popToRoll)
            }
        }
        .navigationTitle("Film Chamber")
        .navigationBarTitleDisplayMode(.inline)
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

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink("Roll as CSV", item: csvURL)
                    ShareLink("Roll Summary", item: summaryText)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(logged == 0)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .close) { dismiss() }
            }
        }
        .onAppear {
            LocationCache.shared.refreshIfAuthorized()
            syncStagedWithLoadedRollIfNeeded()
        }
    }

    private var cameraRow: some View {
        HStack(spacing: 12) {
            if let brand = activeCameraBrand {
                CameraBrandLogo(brand: brand, size: 38)
            } else {
                Image(systemName: "camera")
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 38)
            }

            VStack(alignment: .leading) {
                Text(gear.hasCamera ? gear.cameraName : "Choose Camera")
                    .foregroundStyle(gear.hasCamera ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
                if let subtitle = cameraSubtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var cameraSubtitle: String? {
        guard gear.hasCamera else { return nil }
        if gear.hasLens { return gear.lensName }
        if gear.isFixedLens || gear.mount.isEmpty || gear.mount == "Fixed" {
            return "Fixed lens"
        }
        return formatMountBadge(gear.mount)
    }

    private func syncStagedWithLoadedRollIfNeeded() {
        guard !didInitializeStage else { return }
        didInitializeStage = true
        stagedFrames = roll.maxFrames
        stagedExpired = roll.isExpired
        stagedExpiredYears = roll.yearsExpired

        guard !roll.isUnloaded else {
            stagedFamily = BUILTIN_FILM_FAMILIES[0]
            stagedVariantID = BUILTIN_FILM_FAMILIES[0].variants[0].id
            return
        }

        for family in BUILTIN_FILM_FAMILIES {
            if let match = family.variants.first(where: {
                $0.fullName.caseInsensitiveCompare(roll.filmName) == .orderedSame && $0.iso == roll.boxIso
            }) {
                stagedFamily = family
                stagedVariantID = match.id
                selectedCategory = family.category
                return
            }
        }

        if let customMatch = store.customFilms.first(where: {
            $0.name.caseInsensitiveCompare(roll.filmName) == .orderedSame && $0.iso == roll.boxIso
        }) {
            stagedCustomStock = customMatch
            selectedCategory = "Custom"
        } else {
            stagedFamily = BUILTIN_FILM_FAMILIES[0]
            stagedVariantID = BUILTIN_FILM_FAMILIES[0].variants[0].id
        }
    }

    private func commitLoadedFilm() {
        let currentYear = Calendar.current.component(.year, from: Date())
        var next = store.rollState
        if !next.isUnloaded { next.rollNumber += 1 }
        next.filmName = activeStagedName
        next.boxIso = activeStagedISO
        next.category = activeStagedCategory
        next.currentFrame = 1
        next.maxFrames = stagedFrames
        next.isExpired = stagedExpired
        next.expiredYear = stagedExpired ? currentYear - stagedExpiredYears : currentYear
        next.autoApplyExpiredComp = true
        withAnimation(.snappy) {
            store.rollState = next
        }
        dismiss()
    }

    private func popToRoll() {
        path = NavigationPath()
    }
}

// MARK: - Film Library

private struct FilmLibraryScreen: View {
    @ObservedObject var store: FilmLogStore

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
        .searchable(text: $query, prompt: "Search film")
        .navigationTitle("Film")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
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
                            width: 40,
                            height: 40
                        )
                        .clipShape(.rect(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading) {
                            Text(stock.name)
                            Text("ISO \(stock.iso) · \(stock.category)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
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

            NavigationLink(value: FilmRoute.customFilm) {
                Label("Add Custom Film", systemImage: "plus")
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
                width: 40,
                height: 40
            )
            .clipShape(.rect(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading) {
                Text(family.familyName)
                    .lineLimit(1)
                Text(summary)
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

// MARK: - Screen 2: Film Stock + Hold-to-Load

struct FilmStockView: View {
    @ObservedObject var store: FilmLogStore
    let family: FilmFamily
    var onLoaded: () -> Void = {}

    @State private var variantID: String = ""
    @State private var frames: Int = 36
    @State private var expired = false
    @State private var expiredYears = 10

    private var variant: FilmVariant {
        family.variants.first { $0.id == variantID } ?? family.variants[0]
    }

    private var stockNavigationTitle: String {
        if family.familyName.localizedCaseInsensitiveContains(family.brand) || family.brand.contains("·") {
            return family.familyName
        }
        return "\(family.brand) \(family.familyName)"
    }

    var body: some View {
        Form {
            Section("ISO") {
                Picker("ISO", selection: $variantID) {
                    ForEach(family.variants) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Roll") {
                Picker("Roll length", selection: $frames) {
                    ForEach([12, 16, 24, 36], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Toggle("Expired", isOn: $expired)
                if expired {
                    Stepper("Years: \(expiredYears)", value: $expiredYears, in: 1...50)
                        .monospacedDigit()
                }
            } footer: {
                if expired {
                    Text("+1 stop per decade.")
                }
            }
        }
        .navigationTitle(stockNavigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .listSectionSpacing(.compact)
        .toolbarVisibility(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            HoldToLoadButton(rollLength: frames) {
                load()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .onAppear {
            if variantID.isEmpty { variantID = family.variants[0].id }
            frames = store.rollState.maxFrames
            expired = false
        }
    }

    private func load() {
        let currentYear = Calendar.current.component(.year, from: Date())
        var next = store.rollState
        if !next.isUnloaded { next.rollNumber += 1 }
        next.filmName = variant.fullName
        next.boxIso = variant.iso
        next.category = family.category
        next.currentFrame = 1
        next.maxFrames = frames
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

    @State private var name = ""
    @State private var iso = 400
    @State private var category = "Color"
    @State private var frames = 36

    private var trimmedName: String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Custom Film" : value
    }

    var body: some View {
        Form {
            Section("Film") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                Picker("ISO", selection: $iso) {
                    ForEach(FILM_ISO_STOPS, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Process", selection: $category) {
                    ForEach(["Color", "B&W", "Slide"], id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Roll") {
                Picker("Roll length", selection: $frames) {
                    ForEach([12, 16, 24, 36], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle("Custom Film")
        .navigationBarTitleDisplayMode(.inline)
        .listSectionSpacing(.compact)
        .toolbarVisibility(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            HoldToLoadButton(rollLength: frames) {
                create()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func create() {
        store.addCustomFilm(FilmStockPreset(name: trimmedName, iso: iso, category: category, isCustom: true))

        var next = store.rollState
        if !next.isUnloaded { next.rollNumber += 1 }
        next.filmName = trimmedName
        next.boxIso = iso
        next.category = category
        next.currentFrame = 1
        next.maxFrames = frames
        next.isExpired = false
        withAnimation(.snappy) { store.rollState = next }
        onLoaded()
    }
}

// MARK: - Frames

struct FramesView: View {
    @ObservedObject var store: FilmLogStore

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
                Section(String(format: "Roll %02d · %@", group.header.rollNumber, shortFilmBadge(name: group.header.filmName, iso: group.header.iso))) {
                    ForEach(group.frames) { frame in
                        NavigationLink {
                            FrameDetailScreen(store: store, frame: frame)
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
                }
            }
        }
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No Logged Frames" : "No Matches",
                    systemImage: query.isEmpty ? "photo.on.rectangle" : "magnifyingglass"
                )
            }
        }
        .searchable(text: $query, prompt: "Search frames")
        .navigationTitle("Frames")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .close) { dismiss() }
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
                        .font(.body)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading) {
                Text("Frame \(frame.frameNumber)")
                    .font(.body.weight(.medium))
                    .monospacedDigit()

                Text("\(frame.shutterSpeed) · \(frame.aperture) · ISO \(frame.iso)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()

                if !frame.note.isEmpty {
                    Text(frame.note)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct FrameDetailScreen: View {
    @ObservedObject var store: FilmLogStore
    let frame: LoggedFrame

    @Environment(\.dismiss) private var dismiss
    @State private var note: String = ""
    @State private var showPhoto = false
    @State private var showDeleteConfirm = false

    private var snapshot: UIImage? { store.loadSnapshotImage(frame.snapshotFileName) }

    var body: some View {
        List {
            if let snapshot {
                Section {
                    Button {
                        showPhoto = true
                    } label: {
                        Image(uiImage: snapshot)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 280)
                            .frame(maxWidth: .infinity)
                            .clipShape(.rect(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Frame photo")
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
                    LabeledContent("Mode", value: "Auto")
                }
            }
            .monospacedDigit()

            Section("Frame") {
                LabeledContent("Roll", value: String(format: "%02d", frame.rollNumber))
                    .monospacedDigit()
                LabeledContent("Frame", value: "\(frame.frameNumber) / \(frame.rollMaxFrames)")
                    .monospacedDigit()
                LabeledContent("Film", value: frame.filmName)
                if frame.isExpiredFilm {
                    LabeledContent("Expired", value: "\(frame.expiredYear)")
                        .monospacedDigit()
                }
                if !frame.cameraName.isEmpty {
                    LabeledContent("Camera", value: frame.cameraName)
                }
                if !frame.lensName.isEmpty {
                    LabeledContent("Lens", value: frame.lensName)
                }
                LabeledContent("Logged", value: frame.timestampIso.replacingOccurrences(of: "T", with: " "))
                    .monospacedDigit()
                if let latitude = frame.latitude, let longitude = frame.longitude {
                    LabeledContent("Location", value: String(format: "%.5f, %.5f", latitude, longitude))
                        .monospacedDigit()
                }
            }

            Section("Note") {
                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(1...4)
            }

            Section {
                ShareLink(item: ExifAndXmpWriter.generateRollTextSummary([frame])) {
                    Label("Share Frame", systemImage: "square.and.arrow.up")
                }

                Button("Delete Frame", role: .destructive) {
                    showDeleteConfirm = true
                }
            }
        }
        .navigationTitle("Frame \(frame.frameNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .onAppear { note = frame.note }
        .onDisappear {
            if note != frame.note {
                store.updateFrameNote(frameId: frame.id, note: note)
            }
        }
        .confirmationDialog("Delete frame?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                store.deleteFrame(frameId: frame.id)
                dismiss()
            }
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }
}
