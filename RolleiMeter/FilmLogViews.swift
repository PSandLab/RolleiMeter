import SwiftUI
import UIKit

// MARK: - iOS 27 Liquid Glass Rewind & Complete Roll Control

struct CompleteRollHoldButton: View {
    let currentFrame: Int
    @Binding var rewindProgress: CGFloat
    var holdDuration: Double = 1.0
    let onCompleted: () -> Void

    @State private var isPressing = false
    @State private var crankAngle: Double = 0
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        let p = rewindProgress
        let displayFrame = max(0, Int((CGFloat(max(currentFrame, 1)) * (1.0 - p)).rounded()))

        ZStack {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.05))

                    if p > 0.001 {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Palette.accent.opacity(0.26),
                                        Palette.accent.opacity(0.46)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(44, w * p))
                    }
                }
            }
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isPressing ? Palette.accent.opacity(0.75) : Color.white.opacity(0.10),
                        lineWidth: isPressing ? 1.2 : 0.75
                    )
            )

            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 2.0)
                        .frame(width: 24, height: 24)

                    Circle()
                        .trim(from: 0, to: p)
                        .stroke(
                            Palette.accent,
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 24, height: 24)

                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.accent)
                        .rotationEffect(.degrees(crankAngle))
                }

                Text(isPressing ? String(format: "Rewinding \u{00B7} %02d", displayFrame) : "Hold to Rewind Roll")
                    .font(AppTypography.next(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isPressing ? Palette.accent : Palette.text)
                    .lineLimit(1)

                Spacer()

                if isPressing {
                    Text("\(Int((p * 100).rounded()))%")
                        .font(AppTypography.mono(size: 12, weight: .bold))
                        .foregroundStyle(Palette.accent)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 44)
        .scaleEffect(isPressing ? 0.985 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.78), value: isPressing)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressing else { return }
                    startRewind()
                }
                .onEnded { _ in
                    cancelRewind()
                }
        )
    }

    private func startRewind() {
        isPressing = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            let start = Date()
            var lastRatchetStep = -1
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                let raw = min(1.0, max(0.0, elapsed / holdDuration))
                let eased = raw < 0.5 ? 2 * raw * raw : 1 - pow(-2 * raw + 2, 2) / 2
                rewindProgress = CGFloat(eased)
                crankAngle -= (8.0 + 18.0 * raw)

                let step = Int(eased * 10)
                if step > lastRatchetStep && step < 10 {
                    lastRatchetStep = step
                    UIImpactFeedbackGenerator(style: .rigid)
                        .impactOccurred(intensity: CGFloat(0.45 + 0.5 * eased))
                }

                if raw >= 1.0 {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    isPressing = false
                    rewindProgress = 0
                    crankAngle = 0
                    onCompleted()
                    return
                }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }

    private func cancelRewind() {
        holdTask?.cancel()
        holdTask = nil
        isPressing = false
        withAnimation(.snappy(duration: 0.28)) {
            rewindProgress = 0
            crankAngle = 0
        }
    }
}

// MARK: - Logged Frame Card

struct LoggedFrameCard: View {
    let frame: LoggedFrame
    let snapshot: UIImage?
    let onUpdateNote: (String) -> Void
    let onDelete: () -> Void

    @State private var editingNote: Bool = false
    @State private var noteDraft: String = ""
    @State private var showFullPhoto: Bool = false

    var body: some View {
        let cleanAperture = frame.aperture.lowercased().hasPrefix("f/") ? frame.aperture : "f/\(frame.aperture)"
        let gpsLabel = formatGpsCoordinates(lat: frame.latitude, lon: frame.longitude)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    if snapshot != nil {
                        UISelectionFeedbackGenerator().selectionChanged()
                        showFullPhoto = true
                    }
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        if let snap = snapshot {
                            Image(uiImage: snap)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipped()
                        } else {
                            VStack(spacing: 2) {
                                Text(String(format: "#%02d", frame.frameNumber))
                                    .font(AppTypography.mono(size: 14, weight: .bold))
                                    .foregroundStyle(Palette.accent)
                                Text("Z\(Roman.zone(frame.zone))")
                                    .font(AppTypography.mono(size: 10, weight: .medium))
                                    .foregroundStyle(Palette.dim)
                            }
                            .frame(width: 60, height: 60)
                            .background(Color.white.opacity(0.04))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75)
                    )
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        let isBonus = frame.frameNumber > frame.rollMaxFrames
                        Text(isBonus ? String(format: "+%02d", frame.frameNumber) : String(format: "#%02d", frame.frameNumber))
                            .font(AppTypography.mono(size: 12, weight: .bold))
                            .foregroundStyle(isBonus ? Palette.good : Palette.accent)

                        Text(formatIsoTimestampForDisplay(frame.timestampIso))
                            .font(AppTypography.next(size: 12, weight: .medium))
                            .foregroundStyle(Palette.dim)
                            .lineLimit(1)

                        Spacer()

                        Button {
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Palette.dim)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 6) {
                        Text(frame.shutterSpeed)
                            .font(AppTypography.mono(size: 15, weight: .bold))
                            .foregroundStyle(Palette.text)

                        Text("\u{00B7}")
                            .foregroundStyle(Palette.dim)

                        Text(cleanAperture)
                            .font(AppTypography.mono(size: 15, weight: .bold))
                            .foregroundStyle(Palette.accent)

                        Text("\u{00B7}")
                            .foregroundStyle(Palette.dim)

                        Text("ISO \(frame.iso)")
                            .font(AppTypography.mono(size: 12, weight: .medium))
                            .foregroundStyle(Palette.dim)

                        Spacer()

                        Text(String(format: "Z%@", Roman.zone(frame.zone)))
                            .font(AppTypography.mono(size: 11, weight: .medium))
                            .foregroundStyle(Palette.dim)
                    }

                    if !frame.cameraName.isEmpty || !frame.lensName.isEmpty || gpsLabel != nil {
                        HStack(spacing: 8) {
                            if !frame.cameraName.isEmpty || !frame.lensName.isEmpty {
                                let gearLabel = [frame.cameraName, frame.lensName].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
                                Text(gearLabel)
                                    .font(AppTypography.next(size: 12, weight: .medium))
                                    .foregroundStyle(Palette.dim)
                                    .lineLimit(1)
                            }

                            if let gps = gpsLabel, let lat = frame.latitude, let lon = frame.longitude {
                                Spacer(minLength: 0)
                                Button {
                                    if let url = URL(string: "http://maps.apple.com/?ll=\(lat),\(lon)&q=Roll+\(frame.rollNumber)+Frame+\(frame.frameNumber)") {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "location.fill")
                                            .font(.system(size: 9))
                                        Text(gps)
                                            .font(AppTypography.mono(size: 10, weight: .medium))
                                    }
                                    .foregroundStyle(Palette.good)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            if editingNote {
                HStack(spacing: 8) {
                    TextField("Note\u{2026}", text: $noteDraft)
                        .font(AppTypography.next(size: 13, weight: .regular))
                        .foregroundStyle(Palette.text)
                        .padding(8)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Button("Save") {
                        UISelectionFeedbackGenerator().selectionChanged()
                        onUpdateNote(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                        editingNote = false
                    }
                    .font(AppTypography.next(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    noteDraft = frame.note
                    editingNote = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(frame.note.isEmpty ? Palette.dim : Palette.accent)
                        Text(frame.note.isEmpty ? "Add note\u{2026}" : frame.note)
                            .font(AppTypography.next(size: 12, weight: .medium))
                            .foregroundStyle(frame.note.isEmpty ? Palette.dim : Palette.text)
                            .lineLimit(2)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
                )
        )
        .sheet(isPresented: $showFullPhoto) {
            if let snap = snapshot {
                NavigationStack {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        VStack(spacing: 16) {
                            Image(uiImage: snap)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .padding()

                            VStack(spacing: 4) {
                                Text(String(format: "Roll #%02d \u{00B7} Frame #%02d", frame.rollNumber, frame.frameNumber))
                                    .font(AppTypography.next(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("\(frame.shutterSpeed)  \u{00B7}  \(cleanAperture)  \u{00B7}  ISO \(frame.iso)")
                                    .font(AppTypography.mono(size: 13, weight: .medium))
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showFullPhoto = false }
                                .foregroundStyle(Palette.accent)
                        }
                    }
                }
                .preferredColorScheme(.dark)
            }
        }
    }
}

// MARK: - Film Logbook, Gear & Lab Scan Matcher Sheet

struct FilmLogbookSheet: View {
    @ObservedObject var store: FilmLogStore
    var initialTab: Int = 0
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Int = 0
    @State private var searchQuery: String = ""
    @State private var isBrowsingFilmCatalog: Bool = false
    @State private var selectedFilmCategory: String = "Color"
    @State private var expandedFamilyKey: String? = nil
    @State private var stagedVariant: FilmVariant? = nil
    @State private var stagedMaxFrames: Int = 36
    @State private var stagedExpired: Bool = false
    @State private var stagedYearsExpired: Int = 10
    @State private var customFilmName: String = ""
    @State private var customFilmIso: Int = 400
    @State private var customFilmCategory: String = "Color"
    @State private var expandedRollKeys: Set<String> = []
    @State private var shareSheetItem: ShareSheetItem? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VStack(spacing: 10) {
                    Picker("Section", selection: $selectedTab.animation(.snappy(duration: 0.25))) {
                        Text("Roll & Gear").tag(0)
                        Text("Frames (\(store.loggedFrames.count))").tag(1)
                        Text("Scans").tag(2)
                    }
                    .pickerStyle(.segmented)

                    if selectedTab != 2 {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Palette.dim)

                            TextField(
                                selectedTab == 0 ? "Search film or gear\u{2026}" : "Search frames\u{2026}",
                                text: $searchQuery
                            )
                            .font(AppTypography.next(size: 14, weight: .regular))
                            .foregroundStyle(Palette.text)

                            if !searchQuery.isEmpty {
                                Button {
                                    searchQuery = ""
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Palette.dim)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)

                if selectedTab == 0 {
                    rollAndGearTab
                } else if selectedTab == 1 {
                    framesArchiveTab
                } else {
                    ScanMatcherTabView(store: store) { items in
                        shareSheetItem = ShareSheetItem(items: items)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle(selectedTab == 0 ? "Roll & Gear" : (selectedTab == 1 ? "Frames" : "Scans"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        LocationCache.shared.requestPermissionAndRefresh()
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: LocationCache.shared.lastKnownCoordinate != nil ? "location.fill" : "location")
                                .font(.system(size: 12, weight: .semibold))
                            Text("GPS")
                                .font(AppTypography.mono(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(LocationCache.shared.lastKnownCoordinate != nil ? Palette.good : Palette.dim)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(AppTypography.next(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .onAppear {
            selectedTab = initialTab
            isBrowsingFilmCatalog = store.rollState.isUnloaded
            LocationCache.shared.refreshIfAuthorized()
        }
        .sheet(item: $shareSheetItem) { item in
            ActivityShareSheet(items: item.items)
        }
    }

    // MARK: - Tab 0: Roll & Gear

    private var rollAndGearTab: some View {
        let roll = store.rollState
        let queryTrimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldShowCatalog = roll.isUnloaded || isBrowsingFilmCatalog || !queryTrimmed.isEmpty

        return ScrollView {
            VStack(spacing: 14) {
                ActiveRollHeroCard(
                    roll: roll,
                    isBrowsingCatalog: isBrowsingFilmCatalog,
                    onToggleCatalog: {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.snappy(duration: 0.28, extraBounce: 0.0)) {
                            isBrowsingFilmCatalog.toggle()
                            if !isBrowsingFilmCatalog {
                                expandedFamilyKey = nil
                            }
                        }
                    },
                    onCompleteRoll: {
                        var unloaded = roll
                        unloaded.rollNumber = roll.rollNumber + 1
                        unloaded.filmName = ""
                        unloaded.currentFrame = 1
                        unloaded.isExpired = false
                        withAnimation(.snappy(duration: 0.30, extraBounce: 0.0)) {
                            store.rollState = unloaded
                            isBrowsingFilmCatalog = true
                        }
                    }
                )

                if shouldShowCatalog {
                    filmCatalogContainer(roll: roll, query: queryTrimmed)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                GearSetupSection(store: store, searchQuery: searchQuery)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
    }

    // MARK: - Categorized Film Stock Catalog

    private func filmCatalogContainer(roll: FilmRollState, query: String) -> some View {
        let filteredFamilies: [FilmFamily] = {
            if !query.isEmpty {
                return BUILTIN_FILM_FAMILIES.filter { fam in
                    if fuzzyMatchScore(query: query, target: "\(fam.brand) \(fam.familyName) \(fam.category)") > 0 {
                        return true
                    }
                    return fam.variants.contains { v in
                        fuzzyMatchScore(query: query, target: "\(v.fullName) \(v.iso)") > 0
                    }
                }
            }
            return BUILTIN_FILM_FAMILIES.filter { $0.category == selectedFilmCategory }
        }()

        let familiesByBrand: [(String, [FilmFamily])] = {
            var order: [String] = []
            var dict: [String: [FilmFamily]] = [:]
            for fam in filteredFamilies {
                if dict[fam.brand] == nil {
                    order.append(fam.brand)
                    dict[fam.brand] = []
                }
                dict[fam.brand]?.append(fam)
            }
            return order.map { ($0, dict[$0] ?? []) }
        }()

        return VStack(alignment: .leading, spacing: 14) {
            if query.isEmpty {
                Picker("Film Category", selection: $selectedFilmCategory.animation(.snappy(duration: 0.24))) {
                    Text("Color").tag("Color")
                    Text("B&W").tag("B&W")
                    Text("Slide").tag("Slide")
                    Text("Custom").tag("Custom")
                }
                .pickerStyle(.segmented)
            }

            if selectedFilmCategory == "Custom" && query.isEmpty {
                customFilmBrowserSection
            } else {
                ForEach(familiesByBrand, id: \.0) { brand, families in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(brand.uppercased())
                            .font(AppTypography.next(size: 11, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(Palette.dim)
                            .padding(.leading, 4)

                        VStack(spacing: 6) {
                            ForEach(families) { family in
                                let isExpanded = expandedFamilyKey == family.id
                                let isActiveFamily = !roll.isUnloaded && family.variants.contains {
                                    $0.fullName.caseInsensitiveCompare(roll.filmName) == .orderedSame && $0.iso == roll.boxIso
                                }

                                FilmFamilyExpandableCard(
                                    family: family,
                                    isExpanded: isExpanded,
                                    isActiveFamily: isActiveFamily,
                                    stagedVariant: $stagedVariant,
                                    stagedMaxFrames: $stagedMaxFrames,
                                    stagedExpired: $stagedExpired,
                                    stagedYearsExpired: $stagedYearsExpired,
                                    onToggleExpand: {
                                        UISelectionFeedbackGenerator().selectionChanged()
                                        withAnimation(.snappy(duration: 0.26, extraBounce: 0.0)) {
                                            if isExpanded {
                                                expandedFamilyKey = nil
                                            } else {
                                                expandedFamilyKey = family.id
                                                stagedVariant = family.variants.first(where: { $0.fullName == roll.filmName }) ?? family.variants.first
                                                stagedMaxFrames = roll.maxFrames
                                                stagedExpired = roll.isExpired
                                                stagedYearsExpired = roll.isExpired ? roll.yearsExpired.clamped(to: 1...50) : 10
                                            }
                                        }
                                    },
                                    onLoadRoll: { variant in
                                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                                        let nextRollNum = roll.isUnloaded ? roll.rollNumber : (roll.currentFrame > 1 ? roll.rollNumber + 1 : roll.rollNumber)
                                        let currentYear = Calendar.current.component(.year, from: Date())
                                        withAnimation(.snappy(duration: 0.28, extraBounce: 0.0)) {
                                            store.rollState = FilmRollState(
                                                rollNumber: nextRollNum,
                                                filmName: variant.fullName,
                                                boxIso: variant.iso,
                                                category: family.category,
                                                currentFrame: 1,
                                                maxFrames: stagedMaxFrames,
                                                isExpired: stagedExpired,
                                                expiredYear: currentYear - stagedYearsExpired,
                                                autoApplyExpiredComp: true
                                            )
                                            expandedFamilyKey = nil
                                            isBrowsingFilmCatalog = false
                                        }
                                    }
                                )
                            }
                        }
                    }
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

    private var customFilmBrowserSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !store.customFilms.isEmpty {
                VStack(spacing: 6) {
                    ForEach(store.customFilms) { stock in
                        HStack(spacing: 12) {
                            FilmCanisterArtwork(
                                brand: stock.name,
                                familyName: stock.name,
                                category: stock.category,
                                iso: stock.iso,
                                width: 42,
                                height: 38
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(stock.name)
                                    .font(AppTypography.next(size: 14, weight: .semibold))
                                    .foregroundStyle(Palette.text)
                                Text("ISO \(stock.iso) \u{00B7} \(stock.category)")
                                    .font(AppTypography.mono(size: 11, weight: .medium))
                                    .foregroundStyle(Palette.dim)
                            }

                            Spacer()

                            Button {
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                withAnimation(.snappy(duration: 0.28, extraBounce: 0.0)) {
                                    store.rollState = FilmRollState(
                                        rollNumber: store.rollState.isUnloaded ? store.rollState.rollNumber : store.rollState.rollNumber + 1,
                                        filmName: stock.name,
                                        boxIso: stock.iso,
                                        category: stock.category,
                                        currentFrame: 1,
                                        maxFrames: store.rollState.maxFrames
                                    )
                                    isBrowsingFilmCatalog = false
                                }
                            } label: {
                                Text("Load")
                                    .font(AppTypography.next(size: 13, weight: .semibold))
                                    .foregroundStyle(Palette.accent)
                            }
                            .buttonStyle(.plain)

                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                store.deleteCustomFilm(stock)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Palette.dim)
                                    .padding(6)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField("Film Name", text: $customFilmName)
                    .font(AppTypography.next(size: 14, weight: .regular))
                    .foregroundStyle(Palette.text)
                    .padding(10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Picker("Process", selection: $customFilmCategory) {
                    Text("Color").tag("Color")
                    Text("B&W").tag("B&W")
                    Text("Slide").tag("Slide")
                }
                .pickerStyle(.segmented)

                Stepper {
                    LabeledContent("Box Speed", value: "ISO \(customFilmIso)")
                        .font(AppTypography.next(size: 13, weight: .medium))
                } onIncrement: {
                    if let idx = FILM_ISO_STOPS.firstIndex(of: customFilmIso), idx < FILM_ISO_STOPS.count - 1 {
                        UISelectionFeedbackGenerator().selectionChanged()
                        customFilmIso = FILM_ISO_STOPS[idx + 1]
                    }
                } onDecrement: {
                    if let idx = FILM_ISO_STOPS.firstIndex(of: customFilmIso), idx > 0 {
                        UISelectionFeedbackGenerator().selectionChanged()
                        customFilmIso = FILM_ISO_STOPS[idx - 1]
                    }
                }

                let cleanName = customFilmName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Custom Film"
                    : customFilmName.trimmingCharacters(in: .whitespacesAndNewlines)

                Button {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    let preset = FilmStockPreset(
                        name: cleanName,
                        iso: customFilmIso,
                        category: customFilmCategory,
                        isCustom: true
                    )
                    store.addCustomFilm(preset)
                    withAnimation(.snappy(duration: 0.28, extraBounce: 0.0)) {
                        store.rollState = FilmRollState(
                            rollNumber: store.rollState.isUnloaded ? store.rollState.rollNumber : store.rollState.rollNumber + 1,
                            filmName: cleanName,
                            boxIso: customFilmIso,
                            category: customFilmCategory,
                            currentFrame: 1,
                            maxFrames: 36
                        )
                        customFilmName = ""
                        isBrowsingFilmCatalog = false
                    }
                } label: {
                    Text("Load \(cleanName) \(customFilmIso)")
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

    // MARK: - Tab 1: Logged Frames Roll Archive

    private var framesArchiveTab: some View {
        let filteredFrames: [LoggedFrame] = {
            let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return store.loggedFrames }
            return store.loggedFrames.filter { f in
                fuzzyMatchScore(
                    query: q,
                    target: "Roll \(f.rollNumber) Frame \(f.frameNumber) \(f.filmName) \(f.cameraName) \(f.lensName) \(f.note) \(f.shutterSpeed) \(f.aperture) ISO \(f.iso)"
                ) > 0
            }
        }()

        let rollGroups: [(key: String, header: LoggedFrame, frames: [LoggedFrame])] = {
            let grouped = Dictionary(grouping: filteredFrames) { "\($0.rollNumber)|\($0.filmName)" }
            return grouped.keys.sorted(by: >).compactMap { key in
                guard let list = grouped[key], !list.isEmpty else { return nil }
                let sorted = list.sorted { $0.frameNumber > $1.frameNumber }
                return (key: key, header: sorted[0], frames: sorted)
            }
        }()

        return ScrollView {
            VStack(spacing: 12) {
                if rollGroups.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "film")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Palette.accent)

                        Text("No Logged Frames")
                            .font(AppTypography.next(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.text)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Palette.panel)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
                            )
                    )
                } else {
                    ForEach(Array(rollGroups.enumerated()), id: \.element.key) { idx, group in
                        let isExpanded = idx == 0 || expandedRollKeys.contains(group.key) || !searchQuery.isEmpty
                        VStack(spacing: 10) {
                            HStack(spacing: 12) {
                                Button {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    withAnimation(.snappy(duration: 0.26, extraBounce: 0.0)) {
                                        if expandedRollKeys.contains(group.key) {
                                            expandedRollKeys.remove(group.key)
                                        } else {
                                            expandedRollKeys.insert(group.key)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        FilmCanisterArtwork(
                                            brand: group.header.filmName,
                                            familyName: group.header.filmName,
                                            category: "Color",
                                            iso: group.header.iso,
                                            width: 42,
                                            height: 38
                                        )

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(String(format: "Roll #%02d \u{00B7} %d frames", group.header.rollNumber, group.frames.count))
                                                .font(AppTypography.mono(size: 11, weight: .medium))
                                                .foregroundStyle(Palette.dim)

                                            Text(shortFilmBadge(name: group.header.filmName, iso: group.header.iso))
                                                .font(AppTypography.next(size: 15, weight: .semibold))
                                                .foregroundStyle(Palette.text)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)

                                Button {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    if let url = ExifAndXmpWriter.createRollCsvFileURL(group.frames) {
                                        shareSheetItem = ShareSheetItem(items: [url])
                                    }
                                } label: {
                                    Text("CSV")
                                        .font(AppTypography.mono(size: 12, weight: .semibold))
                                        .foregroundStyle(Palette.accent)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    let summary = ExifAndXmpWriter.generateRollTextSummary(group.frames)
                                    if !summary.isEmpty {
                                        shareSheetItem = ShareSheetItem(items: [summary])
                                    }
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Palette.text)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Palette.panel)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
                                    )
                            )

                            if isExpanded {
                                VStack(spacing: 8) {
                                    ForEach(group.frames) { frame in
                                        LoggedFrameCard(
                                            frame: frame,
                                            snapshot: store.loadSnapshotImage(frame.snapshotFileName),
                                            onUpdateNote: { newNote in
                                                store.updateFrameNote(frameId: frame.id, note: newNote)
                                            },
                                            onDelete: {
                                                store.deleteFrame(frameId: frame.id)
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }
}

// MARK: - Active Roll Hero Card

private struct ActiveRollHeroCard: View {
    let roll: FilmRollState
    let isBrowsingCatalog: Bool
    let onToggleCatalog: () -> Void
    let onCompleteRoll: () -> Void

    @State private var rewindProgress: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if roll.isUnloaded {
                HStack(spacing: 12) {
                    Image(systemName: "film")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "Roll #%02d", roll.rollNumber))
                            .font(AppTypography.mono(size: 11, weight: .medium))
                            .foregroundStyle(Palette.dim)

                        Text("Select a film stock below")
                            .font(AppTypography.next(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.text)
                    }
                    Spacer()
                }
            } else {
                HStack(spacing: 12) {
                    FilmCanisterArtwork(
                        brand: roll.filmName,
                        familyName: roll.filmName,
                        category: roll.category,
                        iso: roll.boxIso,
                        showLeader: true,
                        leaderExtension: 1.0 - rewindProgress,
                        width: 52,
                        height: 48
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(String(format: "Roll #%02d", roll.rollNumber))
                                .font(AppTypography.mono(size: 11, weight: .medium))
                                .foregroundStyle(Palette.dim)

                            if roll.isExpired {
                                Text("\u{00B7} \(roll.yearsExpired)y exp")
                                    .font(AppTypography.mono(size: 11, weight: .medium))
                                    .foregroundStyle(Palette.slow)
                            }
                        }

                        Text(shortFilmBadge(name: roll.filmName, iso: roll.boxIso))
                            .font(AppTypography.next(size: 18, weight: .bold))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Text(roll.isBonusFrames
                                 ? String(format: "Frame +%02d", roll.currentFrame)
                                 : String(format: "Frame %02d / %02d", roll.currentFrame, roll.maxFrames))
                                .font(AppTypography.mono(size: 12, weight: .semibold))
                                .foregroundStyle(roll.isBonusFrames ? Palette.good : Palette.accent)

                            if roll.activeExpiredCompEv > 0.05 {
                                Text(String(format: "\u{00B7} +%.1f EV", roll.activeExpiredCompEv))
                                    .font(AppTypography.mono(size: 11, weight: .semibold))
                                    .foregroundStyle(Palette.slow)
                            }
                        }
                    }

                    Spacer(minLength: 4)

                    Button(action: onToggleCatalog) {
                        Text(isBrowsingCatalog ? "Done" : "Change")
                            .font(AppTypography.next(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                    }
                    .buttonStyle(.plain)
                }

                CompleteRollHoldButton(
                    currentFrame: roll.currentFrame,
                    rewindProgress: $rewindProgress,
                    onCompleted: onCompleteRoll
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(roll.isUnloaded ? Color.white.opacity(0.08) : Palette.accent.opacity(0.32), lineWidth: 0.75)
                )
        )
    }
}

// MARK: - Expandable Film Family Card + Minimal Native iOS Controls

private struct FilmFamilyExpandableCard: View {
    let family: FilmFamily
    let isExpanded: Bool
    let isActiveFamily: Bool
    @Binding var stagedVariant: FilmVariant?
    @Binding var stagedMaxFrames: Int
    @Binding var stagedExpired: Bool
    @Binding var stagedYearsExpired: Int
    let onToggleExpand: () -> Void
    let onLoadRoll: (FilmVariant) -> Void

    var body: some View {
        let previewVariant = stagedVariant ?? family.variants.first!
        let selectedVariantBinding = Binding<String>(
            get: { (stagedVariant ?? family.variants.first!).id },
            set: { newId in
                if let found = family.variants.first(where: { $0.id == newId }) {
                    UISelectionFeedbackGenerator().selectionChanged()
                    stagedVariant = found
                }
            }
        )

        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggleExpand) {
                HStack(spacing: 12) {
                    FilmCanisterArtwork(
                        brand: family.brand,
                        familyName: family.familyName,
                        category: family.category,
                        iso: previewVariant.iso,
                        showLeader: true,
                        width: 46,
                        height: 42
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(family.familyName)
                            .font(AppTypography.next(size: 15, weight: .semibold))
                            .foregroundStyle(isActiveFamily ? Palette.accent : Palette.text)
                            .lineLimit(1)

                        let subSummary = family.variants.count == 1
                            ? "ISO \(family.variants[0].iso)"
                            : family.variants.map(\.label).joined(separator: " \u{00B7} ")
                        Text(subSummary)
                            .font(AppTypography.mono(size: 11, weight: .medium))
                            .foregroundStyle(Palette.dim)
                            .lineLimit(1)
                    }

                    Spacer()

                    if isActiveFamily && !isExpanded {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.accent)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.dim)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().overlay(Color.white.opacity(0.08))

                // 1. Full-width native segmented Picker for film stock / ISO variant
                if family.variants.count > 1 {
                    Picker("Stock", selection: selectedVariantBinding) {
                        ForEach(family.variants) { v in
                            Text(v.label).tag(v.id)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // 2. Full-width native segmented Picker for Roll Length (12, 16, 24, 36)
                Picker("Exposures", selection: $stagedMaxFrames) {
                    ForEach(ROLL_LENGTH_OPTIONS, id: \.self) { len in
                        Text("\(len) exp").tag(len)
                    }
                }
                .pickerStyle(.segmented)

                // 3. Minimal Expired Film Toggle + Years Stepper (Auto +1 EV / decade)
                Toggle("Expired", isOn: $stagedExpired.animation(.snappy(duration: 0.22)))
                    .font(AppTypography.next(size: 14, weight: .medium))
                    .foregroundStyle(Palette.text)
                    .tint(Palette.accent)

                if stagedExpired {
                    let compStops = family.category == "Slide"
                        ? 0.0
                        : ((Double(stagedYearsExpired) / 10.0) * 3.0).rounded() / 3.0
                    let compText = compStops > 0.04 ? String(format: "+%.1f EV", compStops) : "0.0 EV"

                    Stepper {
                        HStack {
                            Text("\(stagedYearsExpired) \(stagedYearsExpired == 1 ? "yr" : "yrs")")
                                .font(AppTypography.mono(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.text)
                            Spacer()
                            Text(compText)
                                .font(AppTypography.mono(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.slow)
                        }
                    } onIncrement: {
                        UISelectionFeedbackGenerator().selectionChanged()
                        stagedYearsExpired = min(50, stagedYearsExpired + 1)
                    } onDecrement: {
                        UISelectionFeedbackGenerator().selectionChanged()
                        stagedYearsExpired = max(1, stagedYearsExpired - 1)
                    }
                }

                // 4. Load Film Button
                let chosen = stagedVariant ?? family.variants.first!
                Button {
                    onLoadRoll(chosen)
                } label: {
                    Text("Load \(shortFilmBadge(name: chosen.fullName, iso: chosen.iso))")
                        .font(AppTypography.next(size: 14, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Palette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isExpanded ? Color.white.opacity(0.05) : (isActiveFamily ? Palette.accent.opacity(0.08) : Color.white.opacity(0.03)))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isActiveFamily || isExpanded ? Palette.accent.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 0.75)
                )
        )
        .clipped()
    }
}
