import SwiftUI
import UIKit

// MARK: - Film Logbook

private enum FilmRoute: Hashable {
    case library
    case family(FilmFamily)
    case customFilm
    case gear
}

// MARK: - RolleiMeter Liquid Glass Controls

private struct RolleiGlassCapsuleModifier: ViewModifier {
    let tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                content.glassEffect(
                    .regular.tint(tint).interactive(),
                    in: Capsule()
                )
            } else {
                content.glassEffect(
                    .regular.interactive(),
                    in: Capsule()
                )
            }
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(
                            Color.white.opacity(0.14),
                            lineWidth: 0.7
                        )
                }
        }
    }
}

private struct RolleiGlassGroupModifier: ViewModifier {
    let spacing: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

private extension View {
    func rolleiGlassCapsule(tint: Color? = nil) -> some View {
        modifier(RolleiGlassCapsuleModifier(tint: tint))
    }

    func rolleiGlassGroup(spacing: CGFloat = 8) -> some View {
        modifier(RolleiGlassGroupModifier(spacing: spacing))
    }
}

private struct RolleiGlassSegment: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(
                    .caption.weight(
                        isSelected ? .semibold : .medium
                    )
                )
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 9)
                .padding(.vertical, 9)
                .foregroundStyle(
                    isSelected ? Palette.accent : Palette.textSub
                )
                .rolleiGlassCapsule(
                    tint: isSelected
                        ? Palette.accent.opacity(0.24)
                        : nil
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
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

// MARK: - Screen 1: Unified Interactive Film Chamber & Physical Canister Tray (Roll tab)

struct RollView: View {
    @ObservedObject var store: FilmLogStore
    @Binding var path: NavigationPath

    @Environment(\.dismiss) private var dismiss

    @State private var stagedFamily: FilmFamily = BUILTIN_FILM_FAMILIES[0]
    @State private var stagedVariantID: String = ""
    @State private var stagedCustomStock: FilmStockPreset? = nil
    @State private var stagedFrames: Int = 36
    @State private var stagedExpired: Bool = false
    @State private var stagedExpiredYears: Int = 20
    @State private var selectedCategory: String = "Color"
    @State private var query: String = ""
    @State private var didInitializeStage: Bool = false
    /// The list row whose loading chamber is open (nil = all rows closed).
    @State private var expandedRowID: String? = nil

    private let categories = ["Color", "B&W", "Slide", "Custom"]
    private let quickDecades = [10, 15, 20, 25, 30, 40]

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
        guard !roll.isUnloaded else { return false }

        let currentYear = Calendar.current.component(.year, from: Date())
        let expectedExpiredYear = currentYear - max(1, stagedExpiredYears)

        let sameExpiration =
            roll.isExpired == stagedExpired
            && (
                !stagedExpired
                || roll.expiredYear == expectedExpiredYear
            )

        return roll.filmName.caseInsensitiveCompare(activeStagedName) == .orderedSame
            && roll.boxIso == activeStagedISO
            && roll.category.caseInsensitiveCompare(activeStagedCategory) == .orderedSame
            && roll.maxFrames == stagedFrames
            && sameExpiration
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

        guard selectedCategory != "Custom" else {
            return []
        }

        return BUILTIN_FILM_FAMILIES.filter { family in
            guard family.category == selectedCategory else {
                return false
            }

            guard !trimmed.isEmpty else {
                return true
            }

            let familyMatches = fuzzyMatchScore(
                query: trimmed,
                target: "\(family.brand) \(family.familyName) \(family.category)"
            ) > 0

            let variantMatches = family.variants.contains { variant in
                fuzzyMatchScore(
                    query: trimmed,
                    target: "\(variant.fullName) \(variant.iso)"
                ) > 0
            }

            return familyMatches || variantMatches
        }
    }

    private var filteredCustomFilms: [FilmStockPreset] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        return store.customFilms.filter { stock in
            guard !trimmed.isEmpty else {
                return true
            }

            return fuzzyMatchScore(
                query: trimmed,
                target: "\(stock.name) \(stock.iso) \(stock.category)"
            ) > 0
        }
    }

    private var nextRollNumber: Int {
        roll.isUnloaded ? max(1, roll.rollNumber) : (roll.rollNumber + 1)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - Film Category Selector: Grouped Liquid Glass

                    HStack(spacing: 6) {
                        ForEach(categories, id: \.self) { cat in
                            let active = selectedCategory == cat

                            RolleiGlassSegment(
                                title: cat,
                                isSelected: active
                            ) {
                                guard !active else { return }

                                Haptics.tap()

                                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                    selectedCategory = cat
                                    expandedRowID = nil
                                }
                            }
                        }
                    }
                    .rolleiGlassGroup(spacing: 6)

                    // MARK: - Film Canister List
                    // Each row is a film stock. Tapping a row opens the loading
                    // chamber inline, directly beneath the row that was tapped.

                    VStack(spacing: 0) {
                        if selectedCategory == "Custom" {
                            customFilmRows
                        } else if filteredFamilies.isEmpty {
                            ContentUnavailableView.search(text: query)
                                .padding(.vertical, 24)
                        } else {
                            ForEach(Array(filteredFamilies.enumerated()), id: \.element.id) { index, family in
                                if index > 0 {
                                    rowSeparator
                                }

                                filmRow(
                                    id: familyRowID(family),
                                    brand: family.brand,
                                    brandLabel: family.brand,
                                    familyName: family.familyName,
                                    category: family.category,
                                    isoLabel: family.variants.map(\.label).joined(separator: " / "),
                                    defaultISO: family.variants.first?.iso ?? 400,
                                    isLoaded: isLoaded(family),
                                    onDelete: nil
                                ) {
                                    stage(family: family)
                                }
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Palette.panel)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .clipShape(.rect(cornerRadius: 24, style: .continuous))

                    // ── COMPACT CAMERA & LENS FOOTER CARD ──
                    NavigationLink(value: FilmRoute.gear) {
                        HStack(spacing: 12) {
                            if let brand = activeCameraBrand {
                                CameraBrandLogo(brand: brand, size: 38)
                            } else {
                                Image(systemName: "camera")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 38, height: 38)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(gear.hasCamera ? gear.cameraName : "Choose Camera")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Palette.text)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.86)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let subtitle = cameraSubtitle {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(Palette.textSub)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.82)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.textDim)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Palette.panel)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .onChange(of: expandedRowID) { _, newID in
                guard let newID else { return }

                // Once the drawer has finished opening, nudge the scroll view
                // only as much as needed to reveal the whole chamber.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(420))
                    guard expandedRowID == newID else { return }
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                        proxy.scrollTo(newID, anchor: nil)
                    }
                }
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .searchable(text: $query, prompt: "Search films")
        .navigationDestination(for: FilmRoute.self) { route in
            switch route {
            case .library:
                FilmLibraryScreen(store: store)
            case .family(let family):
                FilmStockView(store: store, family: family) {
                    selectedVariant, selectedFrames, wasExpired, yearsExpired in

                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        stagedCustomStock = nil
                        stagedFamily = family
                        stagedVariantID = selectedVariant.id
                        stagedFrames = selectedFrames
                        stagedExpired = wasExpired
                        stagedExpiredYears = yearsExpired
                        selectedCategory = family.category
                        query = ""
                        expandedRowID = familyRowID(family)
                    }

                    popToRoll()
                }
            case .customFilm:
                CustomFilmScreen(store: store) { createdStock, createdFrames in
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        stagedCustomStock = createdStock
                        stagedFrames = createdFrames
                        stagedExpired = false
                        stagedExpiredYears = 20
                        selectedCategory = "Custom"
                        query = ""
                        expandedRowID = customRowID(createdStock)
                    }

                    popToRoll()
                }
            case .gear:
                CameraLensView(store: store, onFinish: popToRoll)
            }
        }
        .navigationTitle("Film")
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

    // MARK: - List Rows

    private var rowSeparator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
            .padding(.leading, 80)
    }

    private func familyRowID(_ family: FilmFamily) -> String {
        "family_\(family.id)"
    }

    private func customRowID(_ stock: FilmStockPreset) -> String {
        "custom_\(stock.id)"
    }

    private func isLoaded(_ family: FilmFamily) -> Bool {
        guard !roll.isUnloaded else { return false }
        return family.variants.contains {
            $0.fullName.caseInsensitiveCompare(roll.filmName) == .orderedSame
                && $0.iso == roll.boxIso
        }
    }

    private func isLoaded(_ stock: FilmStockPreset) -> Bool {
        guard !roll.isUnloaded else { return false }
        return stock.name.caseInsensitiveCompare(roll.filmName) == .orderedSame
            && stock.iso == roll.boxIso
    }

    /// One film in the list: a tappable header and, when open, the loading
    /// drawer (variants, roll length, expiry and the leader-pull chamber).
    @ViewBuilder
    private func filmRow(
        id: String,
        brand: String,
        brandLabel: String,
        familyName: String,
        category: String,
        isoLabel: String,
        defaultISO: Int,
        isLoaded: Bool,
        onDelete: (() -> Void)?,
        onStage: @escaping () -> Void
    ) -> some View {
        let isExpanded = expandedRowID == id

        VStack(spacing: 0) {
            FilmCanisterListRow(
                brand: brand,
                brandLabel: brandLabel,
                familyName: familyName,
                category: category,
                isoLabel: isoLabel,
                defaultISO: defaultISO,
                isExpanded: isExpanded,
                isLoaded: isLoaded,
                onSelect: {
                    if isExpanded {
                        Haptics.tap()
                    } else {
                        Haptics.rigid()
                    }

                    withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                        if isExpanded {
                            expandedRowID = nil
                        } else {
                            onStage()
                            expandedRowID = id
                        }
                    }
                },
                onDelete: onDelete
            )

            if isExpanded {
                loadingDrawer
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .scale(scale: 0.97, anchor: .top)),
                            removal: .opacity
                        )
                    )
            }
        }
        .background(isExpanded ? Palette.accent.opacity(0.05) : Color.clear)
        .clipped()
        .id(id)
    }

    @ViewBuilder
    private var customFilmRows: some View {
        let hasQuery = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if filteredCustomFilms.isEmpty && hasQuery {
            ContentUnavailableView.search(text: query)
                .padding(.vertical, 24)
            rowSeparator
        }

        ForEach(filteredCustomFilms) { stock in
            filmRow(
                id: customRowID(stock),
                brand: stock.name,
                brandLabel: "Custom",
                familyName: stock.name,
                category: stock.category,
                isoLabel: "ISO \(stock.iso)",
                defaultISO: stock.iso,
                isLoaded: isLoaded(stock),
                onDelete: { deleteCustomStock(stock) }
            ) {
                stage(custom: stock)
            }

            rowSeparator
        }

        NavigationLink(value: FilmRoute.customFilm) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                        .foregroundStyle(Palette.accent.opacity(0.55))
                        .frame(width: 44, height: 50)

                    Image(systemName: "plus")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Palette.accent)
                }
                .frame(width: 52, height: 54)

                VStack(alignment: .leading, spacing: 3) {
                    Text("New Custom Film")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.accent)

                    Text(
                        store.customFilms.isEmpty
                            ? "Add a stock that isn't in the catalog"
                            : "Add another stock"
                    )
                    .font(.caption)
                    .foregroundStyle(Palette.textSub)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.textDim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inline Loading Drawer (opens under the tapped row)

    private var loadingDrawer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 6) {
                    if stagedCustomStock != nil || stagedFamily.variants.count == 1 {
                        Text("ISO \(activeStagedISO)")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Palette.textSub)
                    }

                    if isStagedAlreadyLoaded {
                        Text("ACTIVE · \(roll.currentFrame)/\(roll.maxFrames)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(Palette.good)
                    } else {
                        Text("NEW ROLL")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Palette.textDim)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.78)

                Spacer(minLength: 4)

                HStack(spacing: 8) {
                    Menu {
                        Picker("Roll Length", selection: $stagedFrames) {
                            Text("36 Exposures · Standard").tag(36)
                            Text("24 Exposures").tag(24)
                            Text("16 Exposures · Half Roll").tag(16)
                            Text("12 Exposures").tag(12)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text("\(stagedFrames) EXP")
                                .monospacedDigit()

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .rolleiGlassCapsule()
                    }
                    .accessibilityLabel("Roll length")
                    .accessibilityValue("\(stagedFrames) exposures")

                    Button {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.68)) {
                            stagedExpired.toggle()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(
                                systemName: stagedExpired
                                    ? "clock.badge.exclamationmark.fill"
                                    : "clock"
                            )
                            .font(.system(size: 11, weight: .semibold))

                            Text("Expired")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(
                            stagedExpired ? Palette.accent : Palette.text
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .rolleiGlassCapsule(
                            tint: stagedExpired
                                ? Palette.accent.opacity(0.24)
                                : nil
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Expired film")
                    .accessibilityValue(stagedExpired ? "On" : "Off")
                }
                .rolleiGlassGroup(spacing: 8)
            }

            // Fast Tactile Expired Film Decade Pills & Continuous Scrubber (1 to 50 Years)
            if stagedExpired {
                ExpiredFilmFastScrubber(
                    years: $stagedExpiredYears,
                    quickDecades: quickDecades,
                    supportsCompensation: activeStagedCategory.caseInsensitiveCompare("Slide") != .orderedSame
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }

            // MARK: - ISO Variant Selector: One Grouped Liquid Glass Control

            if stagedCustomStock == nil && stagedFamily.variants.count > 1 {
                HStack(spacing: 8) {
                    ForEach(stagedFamily.variants) { option in
                        let isSelected = option.id == stagedVariant.id

                        RolleiGlassSegment(
                            title: option.label,
                            isSelected: isSelected
                        ) {
                            guard !isSelected else { return }

                            Haptics.tap()

                            withAnimation(.spring(response: 0.26, dampingFraction: 0.65)) {
                                stagedVariantID = option.id
                            }
                        }
                    }
                }
                .rolleiGlassGroup(spacing: 8)
                .accessibilityLabel("Film ISO")
            }

            // The Interactive 35mm Leader-Pull Chamber
            InteractiveFilmLeaderChamber(
                brand: activeStagedBrand,
                familyName: activeStagedFamilyName,
                stockFullName: shortFilmBadge(name: activeStagedName, iso: activeStagedISO),
                category: activeStagedCategory,
                iso: activeStagedISO,
                rollLength: stagedFrames,
                rollNumber: nextRollNumber,
                isAlreadyLoaded: isStagedAlreadyLoaded
            ) {
                commitLoadedFilm()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
        .padding(.bottom, 16)
    }

    // MARK: - Staging

    private func stage(family: FilmFamily) {
        stagedCustomStock = nil
        stagedFamily = family

        if isLoaded(family),
           let match = family.variants.first(where: {
               $0.fullName.caseInsensitiveCompare(roll.filmName) == .orderedSame
                   && $0.iso == roll.boxIso
           }) {
            // Re-opening the roll that is in the camera shows it as loaded.
            stagedVariantID = match.id
            stagedFrames = roll.maxFrames
            stagedExpired = roll.isExpired
            stagedExpiredYears = roll.isExpired ? roll.yearsExpired : 20
        } else {
            stagedVariantID = family.variants[0].id
            stagedFrames = 36
        }
    }

    private func stage(custom stock: FilmStockPreset) {
        stagedCustomStock = stock

        if isLoaded(stock) {
            stagedFrames = roll.maxFrames
            stagedExpired = roll.isExpired
            stagedExpiredYears = roll.isExpired ? roll.yearsExpired : 20
        } else {
            stagedFrames = 36
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

        stagedFrames = roll.isUnloaded ? 36 : roll.maxFrames
        stagedExpired = roll.isExpired
        stagedExpiredYears = roll.isExpired ? roll.yearsExpired : 20
        stagedCustomStock = nil

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

    private func deleteCustomStock(_ stock: FilmStockPreset) {
        let wasStaged = stagedCustomStock?.id == stock.id
        let rowID = customRowID(stock)

        store.deleteCustomFilm(stock)

        if expandedRowID == rowID {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                expandedRowID = nil
            }
        }

        guard wasStaged else { return }

        let fallback = BUILTIN_FILM_FAMILIES[0]

        withAnimation(.spring(response: 0.28, dampingFraction: 0.68)) {
            stagedCustomStock = nil
            stagedFamily = fallback
            stagedVariantID = fallback.variants[0].id
            stagedFrames = 36
            stagedExpired = false
            stagedExpiredYears = 20
        }
    }

    private func commitLoadedFilm() {
        let didLoad = store.loadFilm(
            filmName: activeStagedName,
            boxISO: activeStagedISO,
            category: activeStagedCategory,
            maxFrames: stagedFrames,
            isExpired: stagedExpired,
            yearsExpired: stagedExpired ? stagedExpiredYears : nil
        )

        guard didLoad else { return }

        withAnimation(.snappy) {
            dismiss()
        }
    }

    private func popToRoll() {
        path = NavigationPath()
    }
}

// MARK: - Film Canister List Row

private struct FilmCanisterListRow: View {
    let brand: String
    let brandLabel: String
    let familyName: String
    let category: String
    let isoLabel: String
    let defaultISO: Int
    let isExpanded: Bool
    let isLoaded: Bool
    let onSelect: () -> Void
    var onDelete: (() -> Void)? = nil

    var body: some View {
        if let onDelete {
            header
                .contextMenu {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete Custom Film", systemImage: "trash")
                    }
                }
        } else {
            header
        }
    }

    private var header: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                ZStack {
                    // Recessed physical foam slot.
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.black.opacity(0.42))
                        .frame(width: 48, height: 52)

                    FilmCanisterArtwork(
                        brand: brand,
                        familyName: familyName,
                        category: category,
                        iso: defaultISO,
                        showLeader: true,
                        leaderExtension: isExpanded ? 1.0 : 0.4,
                        width: 46,
                        height: 50
                    )
                    .scaleEffect(isExpanded ? 1.06 : 1.0)
                }
                .frame(width: 52, height: 54)

                VStack(alignment: .leading, spacing: 3) {
                    Text(familyName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isExpanded ? Palette.accent : Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text("\(brandLabel) · \(isoLabel)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Palette.textSub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 8)

                if isLoaded {
                    Text("IN CAMERA")
                        .font(.caption2.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(Palette.good)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Palette.good.opacity(0.14)))
                }

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isExpanded ? Palette.accent : Palette.textDim)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(FilmRowPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(brandLabel), \(familyName), \(isoLabel)")
        .accessibilityValue(
            isLoaded ? "In camera" : (isExpanded ? "Open" : "Closed")
        )
        .accessibilityHint(isExpanded ? "Closes the loading chamber" : "Opens the loading chamber")
        .accessibilityAddTraits(.isButton)
    }
}

private struct FilmRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.05 : 0))
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Fast Tactile Expired Film Scrubber (1 to 50 Years in One Swipe + Decade Pills)

private struct ExpiredFilmFastScrubber: View {
    @Binding var years: Int
    let quickDecades: [Int]
    let supportsCompensation: Bool

    private var vintageYear: Int {
        Calendar.current.component(.year, from: Date()) - years
    }

    private var compStops: Double {
        (Double(years) / 10.0 * 3.0).rounded() / 3.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("EXPIRED \(years) YRS · \(vintageYear)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Palette.accent)

                Spacer()

                if supportsCompensation {
                    Text(String(format: "+%.1f EV", compStops))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Palette.textSub)
                } else {
                    Text("NO AUTO COMP · SLIDE")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.textSub)
                }
            }

            // MARK: - Quick Vintage Jumps: Grouped Liquid Glass

            HStack(spacing: 6) {
                ForEach(quickDecades, id: \.self) { preset in
                    let isSelected = years == preset

                    RolleiGlassSegment(
                        title: "\(preset)y",
                        isSelected: isSelected
                    ) {
                        UISelectionFeedbackGenerator().selectionChanged()

                        withAnimation(.snappy(duration: 0.18)) {
                            years = preset
                        }
                    }
                }
            }
            .rolleiGlassGroup(spacing: 6)

            // Continuous Horizontal Drag Ruler Scrubber (1 to 50 Years)
            GeometryReader { geo in
                let w = max(geo.size.width, 1)
                let progress = CGFloat(years - 1) / 49.0

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.45))

                    // Ruler ticks from 1 to 50 years
                    Canvas { ctx, size in
                        let tickCount = 50
                        let usableW = size.width - 20
                        for i in 1...tickCount {
                            let frac = CGFloat(i - 1) / 49.0
                            let x = 10 + frac * usableW
                            let isDecade = (i % 10 == 0)
                            let isFive = (i % 5 == 0)
                            let isActive = (i == years)
                            let tickH: CGFloat = isActive ? 22 : (isDecade ? 16 : (isFive ? 11 : 6))
                            let topY = (size.height - tickH) * 0.5

                            var p = Path()
                            p.move(to: CGPoint(x: x, y: topY))
                            p.addLine(to: CGPoint(x: x, y: topY + tickH))
                            ctx.stroke(
                                p,
                                with: .color(isActive ? Palette.accent : (i <= years ? Palette.accent.opacity(0.55) : Color.white.opacity(isDecade ? 0.45 : 0.18))),
                                lineWidth: isActive ? 2.5 : (isDecade ? 1.5 : 1.0)
                            )
                        }
                    }

                    // Thumb indicator
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 14, height: 14)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .offset(x: 10 + progress * (w - 20) - 7)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let ratio = ((value.location.x - 10) / max(w - 20, 1)).clamped(to: 0...1)
                            let target = Int((1.0 + ratio * 49.0).rounded()).clamped(to: 1...50)
                            if target != years {
                                if target % 10 == 0 {
                                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7)
                                } else {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                }
                                years = target
                            }
                        }
                )
            }
            .frame(height: 32)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(0.09),
                            lineWidth: 0.8
                        )
                }
        )
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

        guard category != "Custom" else {
            return []
        }

        return BUILTIN_FILM_FAMILIES.filter { family in
            guard family.category == category else {
                return false
            }

            guard !trimmed.isEmpty else {
                return true
            }

            let familyMatches = fuzzyMatchScore(
                query: trimmed,
                target: "\(family.brand) \(family.familyName) \(family.category)"
            ) > 0

            let variantMatches = family.variants.contains { variant in
                fuzzyMatchScore(
                    query: trimmed,
                    target: "\(variant.fullName) \(variant.iso)"
                ) > 0
            }

            return familyMatches || variantMatches
        }
    }

    private var filteredCustomStocks: [FilmStockPreset] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        return store.customFilms.filter { stock in
            guard !trimmed.isEmpty else {
                return true
            }

            return fuzzyMatchScore(
                query: trimmed,
                target: "\(stock.name) \(stock.iso) \(stock.category)"
            ) > 0
        }
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

            if category == "Custom" {
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
            if filteredCustomStocks.isEmpty {
                ContentUnavailableView(
                    query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "No Custom Films"
                        : "No Matching Films",
                    systemImage: "film",
                    description: Text(
                        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "Add a custom stock to see it here."
                            : "Try another film name or ISO."
                    )
                )
            }

            ForEach(filteredCustomStocks) { stock in
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
        let didLoad = store.loadFilm(
            filmName: stock.name,
            boxISO: stock.iso,
            category: stock.category,
            maxFrames: store.rollState.maxFrames,
            isExpired: false,
            yearsExpired: nil
        )

        guard didLoad else { return }

        Haptics.success()

        withAnimation(.snappy) {
            // The store has already committed the complete roll state.
        }
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
    var onLoaded: (FilmVariant, Int, Bool, Int) -> Void = { _, _, _, _ in }

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
        let didLoad = store.loadFilm(
            filmName: variant.fullName,
            boxISO: variant.iso,
            category: family.category,
            maxFrames: frames,
            isExpired: expired,
            yearsExpired: expired ? expiredYears : nil
        )

        guard didLoad else { return }

        withAnimation(.snappy) {
            onLoaded(variant, frames, expired, expiredYears)
        }
    }
}

private struct CustomFilmScreen: View {
    @ObservedObject var store: FilmLogStore
    var onCreated: (FilmStockPreset, Int) -> Void = { _, _ in }

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
        let createdStock = FilmStockPreset(
            name: trimmedName,
            iso: iso,
            category: category,
            isCustom: true
        )

        let didLoad = store.loadFilm(
            filmName: createdStock.name,
            boxISO: createdStock.iso,
            category: createdStock.category,
            maxFrames: frames,
            isExpired: false,
            yearsExpired: nil
        )

        guard didLoad else { return }

        store.addCustomFilm(createdStock)

        withAnimation(.snappy) {
            onCreated(createdStock, frames)
        }
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
