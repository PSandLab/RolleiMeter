import SwiftUI
import UIKit

// MARK: - Hold to Load 35mm Canister Button (Liquid Wave + Unspooling Perforated Leader)

struct LoadFilmHoldButton: View {
    let label: String
    var holdDuration: Double = 0.78
    let onLoaded: () -> Void

    @State private var isPressing = false
    @State private var progress: CGFloat = 0
    @State private var wavePhase: CGFloat = 0
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        let scale: CGFloat = isPressing ? (0.97 + 0.05 * progress) : 1.0

        ZStack {
            Canvas { ctx, size in
                let w = size.width
                let h = size.height
                let rect = CGRect(origin: .zero, size: size)
                let clipPath = Path(roundedRect: rect, cornerRadius: h / 2)
                ctx.fill(clipPath, with: .color(Palette.accent.opacity(0.20)))

                if progress > 0.001 {
                    let fillX = w * progress
                    let amp: CGFloat = (progress < 0.98) ? (4.5 * sin(progress * .pi) + 2.0) : 0.0
                    var wave = Path()
                    wave.move(to: .zero)
                    wave.addLine(to: CGPoint(x: fillX, y: 0))
                    let steps = 16
                    for s in 1...steps {
                        let frac = CGFloat(s) / CGFloat(steps)
                        let y = h * frac
                        let waveOffset = sin(frac * .pi * 2.2 + wavePhase) * amp
                        wave.addLine(to: CGPoint(x: fillX + waveOffset, y: y))
                    }
                    wave.addLine(to: CGPoint(x: 0, y: h))
                    wave.closeSubpath()

                    var clipped = ctx
                    clipped.clip(to: clipPath)
                    clipped.fill(wave, with: .color(Palette.accent))
                }

                ctx.stroke(clipPath, with: .color(Palette.accent.opacity(0.55)), lineWidth: 1)
            }

            HStack(spacing: 10) {
                // Animated 35mm Canister + Unspooling Perforated Leader
                Canvas { ctx, s in
                    let w = s.width
                    let h = s.height
                    let fg = progress > 0.45 ? Color.black : Palette.accent
                    let canW = w * 0.44
                    let canTop = h * 0.18
                    let canH = h * 0.68

                    let spindle = CGRect(x: canW * 0.26, y: h * 0.05, width: canW * 0.48, height: h * 0.14)
                    ctx.fill(Path(roundedRect: spindle, cornerRadius: 1.5), with: .color(fg))

                    let bodyRect = CGRect(x: 0, y: canTop, width: canW, height: canH)
                    ctx.stroke(Path(roundedRect: bodyRect, cornerRadius: 2.5), with: .color(fg), lineWidth: 1.6)

                    let leaderMaxW = w - canW - 2
                    let leaderW = leaderMaxW * (0.28 + 0.72 * progress)
                    let leaderTop = canTop + canH * 0.16
                    let leaderH = canH * 0.68
                    let leaderRect = CGRect(x: canW, y: leaderTop, width: leaderW, height: leaderH)
                    ctx.fill(Path(roundedRect: leaderRect, cornerRadius: 2), with: .color(fg.opacity(0.32)))

                    let holeStep: CGFloat = 4.5
                    var hx: CGFloat = canW + 2
                    while hx < canW + leaderW - 3 {
                        ctx.fill(Path(CGRect(x: hx, y: leaderTop + 1.5, width: 2.2, height: 1.8)), with: .color(fg))
                        ctx.fill(Path(CGRect(x: hx, y: leaderTop + leaderH - 3.3, width: 2.2, height: 1.8)), with: .color(fg))
                        hx += holeStep
                    }
                }
                .frame(width: 26, height: 20)

                Text(isPressing ? "LOADING SPOOL… \(Int((progress * 100).rounded()))%" : label)
                    .font(AppTypography.label(13, weight: .bold))
                    .foregroundStyle(progress > 0.5 ? Color.black : Palette.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 46)
        .scaleEffect(scale)
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isPressing)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressing else { return }
                    startHold()
                }
                .onEnded { _ in
                    cancelHold()
                }
        )
    }

    private func startHold() {
        isPressing = true
        MechanicalHaptics.click()
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            let start = Date()
            var lastBucket = -1
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                let p = min(1.0, max(0.0, elapsed / holdDuration))
                progress = CGFloat(p)
                wavePhase += 0.28
                let bucket = Int(p * 5)
                if bucket > lastBucket && bucket < 5 {
                    lastBucket = bucket
                    MechanicalHaptics.tick()
                }
                if p >= 1.0 {
                    MechanicalHaptics.heavy()
                    MechanicalHaptics.confirm()
                    isPressing = false
                    progress = 0
                    onLoaded()
                    return
                }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        isPressing = false
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            progress = 0
        }
    }
}

// MARK: - Hold to Complete & Rewind Roll Button

struct CompleteRollHoldButton: View {
    var holdDuration: Double = 0.85
    let onCompleted: () -> Void

    @State private var isPressing = false
    @State private var progress: CGFloat = 0
    @State private var wavePhase: CGFloat = 0
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        let scale: CGFloat = isPressing ? (0.97 + 0.05 * progress) : 1.0

        ZStack {
            Canvas { ctx, size in
                let w = size.width
                let h = size.height
                let rect = CGRect(origin: .zero, size: size)
                let clipPath = Path(roundedRect: rect, cornerRadius: h / 2)
                ctx.fill(clipPath, with: .color(Color.white.opacity(0.08)))

                if progress > 0.001 {
                    let fillX = w * progress
                    let amp: CGFloat = (progress < 0.98) ? (4.0 * sin(progress * .pi) + 1.8) : 0.0
                    var wave = Path()
                    wave.move(to: .zero)
                    wave.addLine(to: CGPoint(x: fillX, y: 0))
                    let steps = 16
                    for s in 1...steps {
                        let frac = CGFloat(s) / CGFloat(steps)
                        let y = h * frac
                        let waveOffset = sin(frac * .pi * 2.2 + wavePhase) * amp
                        wave.addLine(to: CGPoint(x: fillX + waveOffset, y: y))
                    }
                    wave.addLine(to: CGPoint(x: 0, y: h))
                    wave.closeSubpath()

                    var clipped = ctx
                    clipped.clip(to: clipPath)
                    clipped.fill(wave, with: .color(Palette.accent))
                }

                ctx.stroke(clipPath, with: .color(Color.white.opacity(0.16)), lineWidth: 0.8)
            }

            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(progress > 0.5 ? Color.black : Palette.accent)
                    .rotationEffect(.degrees(Double(progress) * -540))

                Text(isPressing ? "REWINDING SPOOL… \(Int((progress * 100).rounded()))%" : "Hold to Complete & Rewind Roll")
                    .font(AppTypography.label(12, weight: .bold))
                    .foregroundStyle(progress > 0.5 ? Color.black : Palette.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 40)
        .scaleEffect(scale)
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isPressing)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressing else { return }
                    startHold()
                }
                .onEnded { _ in
                    cancelHold()
                }
        )
    }

    private func startHold() {
        isPressing = true
        MechanicalHaptics.click()
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            let start = Date()
            var lastBucket = -1
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                let p = min(1.0, max(0.0, elapsed / holdDuration))
                progress = CGFloat(p)
                wavePhase += 0.28
                let bucket = Int(p * 5)
                if bucket > lastBucket && bucket < 5 {
                    lastBucket = bucket
                    MechanicalHaptics.tick()
                }
                if p >= 1.0 {
                    MechanicalHaptics.heavy()
                    MechanicalHaptics.confirm()
                    isPressing = false
                    progress = 0
                    onCompleted()
                    return
                }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        isPressing = false
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            progress = 0
        }
    }
}

// MARK: - Minimal Log Frame Pill (Shown on Viewfinder when HOLD is active)

struct MinimalLogFrameButton: View {
    let moment: CapturedMoment
    let isSaved: Bool
    let onLogFrame: () -> Void

    var body: some View {
        Button {
            guard !isSaved else { return }
            MechanicalHaptics.confirm()
            onLogFrame()
        } label: {
            HStack(spacing: 9) {
                if let snap = moment.snapshotImage {
                    Image(uiImage: snap)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 26, height: 26)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                } else {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.28))
                            .frame(width: 26, height: 26)
                        Image(systemName: isSaved ? "checkmark" : "film")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(isSaved ? "Logged Frame #\(String(format: "%02d", moment.frameNumber))" : "Log Frame #\(String(format: "%02d", moment.frameNumber))")
                        .font(AppTypography.label(12, weight: .bold))
                        .foregroundStyle(isSaved ? .black : .white)

                    Text("\(moment.shutterSpeed) · \(moment.aperture) · ISO \(moment.iso)")
                        .font(AppTypography.mono(9.5, weight: .semibold))
                        .foregroundStyle(isSaved ? .black.opacity(0.75) : .white.opacity(0.85))
                }

                Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isSaved ? .black : Palette.accent)
            }
            .padding(.leading, 7)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .background {
                if isSaved {
                    Capsule().fill(Palette.good)
                } else if #available(iOS 26.0, *) {
                    Capsule()
                        .fill(Color(hex: 0x15803D).opacity(0.55))
                        .glassEffect(.regular.interactive(), in: .capsule)
                } else {
                    Capsule()
                        .fill(Color(hex: 0x14532D).opacity(0.92))
                        .overlay(Capsule().strokeBorder(Palette.good.opacity(0.55), lineWidth: 1))
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
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
                // Frame Snapshot Thumbnail
                Button {
                    if snapshot != nil {
                        MechanicalHaptics.click()
                        showFullPhoto = true
                    }
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        if let snap = snapshot {
                            Image(uiImage: snap)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 68, height: 68)
                                .clipped()
                        } else {
                            VStack(spacing: 2) {
                                Text(String(format: "#%02d", frame.frameNumber))
                                    .font(AppTypography.mono(15, weight: .black))
                                    .foregroundStyle(Palette.accent)
                                Text("Z\(Roman.zone(frame.zone))")
                                    .font(AppTypography.mono(10, weight: .bold))
                                    .foregroundStyle(Palette.textSub)
                            }
                            .frame(width: 68, height: 68)
                            .background(Color.black.opacity(0.35))
                        }

                        if snapshot != nil {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Color.black.opacity(0.65), in: Circle())
                                .padding(4)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
                    )
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 5) {
                    // Top Row: Frame Badge + Timestamp + Delete
                    HStack(spacing: 6) {
                        let isBonus = frame.frameNumber > frame.rollMaxFrames
                        Text(isBonus ? String(format: "+%02d", frame.frameNumber) : String(format: "#%02d", frame.frameNumber))
                            .font(AppTypography.mono(11, weight: .black))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(isBonus ? Palette.good : Palette.accent, in: Capsule())

                        Text(formatIsoTimestampForDisplay(frame.timestampIso))
                            .font(AppTypography.label(11, weight: .medium))
                            .foregroundStyle(Palette.textSub)
                            .lineLimit(1)

                        Spacer()

                        Button {
                            MechanicalHaptics.warning()
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.textDim)
                                .padding(5)
                                .background(Color.white.opacity(0.05), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    // Exposure Specs Row
                    HStack(spacing: 6) {
                        Text(frame.shutterSpeed)
                            .font(AppTypography.mono(14, weight: .black))
                            .foregroundStyle(Palette.text)

                        Text("·")
                            .foregroundStyle(Palette.textDim)

                        Text(cleanAperture)
                            .font(AppTypography.mono(14, weight: .black))
                            .foregroundStyle(Palette.accent)

                        Text("·")
                            .foregroundStyle(Palette.textDim)

                        Text("ISO \(frame.iso)")
                            .font(AppTypography.mono(12, weight: .bold))
                            .foregroundStyle(Palette.textSub)

                        Spacer()

                        Text(String(format: "Z%@ · %.1f EV", Roman.zone(frame.zone), frame.compensatedEv))
                            .font(AppTypography.mono(10, weight: .bold))
                            .foregroundStyle(Palette.textSub)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.06), in: Capsule())
                    }

                    // Camera + Lens + EV Comp + GPS Chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            if !frame.cameraName.isEmpty || !frame.lensName.isEmpty {
                                let gearLabel = [frame.cameraName, frame.lensName].filter { !$0.isEmpty }.joined(separator: " · ")
                                HStack(spacing: 4) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 9))
                                    Text(gearLabel)
                                        .font(AppTypography.label(10, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(Palette.textSub)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.06), in: Capsule())
                            }

                            if abs(frame.totalEvComp) >= 0.05 {
                                Text(formatEvComp(frame.totalEvComp))
                                    .font(AppTypography.mono(10, weight: .bold))
                                    .foregroundStyle(Palette.slow)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Palette.slow.opacity(0.15), in: Capsule())
                            }

                            if let gps = gpsLabel, let lat = frame.latitude, let lon = frame.longitude {
                                Button {
                                    if let url = URL(string: "http://maps.apple.com/?ll=\(lat),\(lon)&q=Roll+\(frame.rollNumber)+Frame+\(frame.frameNumber)") {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "location.fill")
                                            .font(.system(size: 9))
                                        Text(gps)
                                            .font(AppTypography.mono(9.5, weight: .semibold))
                                    }
                                    .foregroundStyle(Palette.good)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Palette.good.opacity(0.14), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            // Note Section
            if editingNote {
                HStack(spacing: 8) {
                    TextField("Add frame note (lighting, filter, subject)…", text: $noteDraft)
                        .font(AppTypography.label(12))
                        .foregroundStyle(Palette.text)
                        .padding(8)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Button("Save") {
                        MechanicalHaptics.confirm()
                        onUpdateNote(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                        editingNote = false
                    }
                    .font(AppTypography.label(12, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Palette.accent, in: Capsule())
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    MechanicalHaptics.tick()
                    noteDraft = frame.note
                    editingNote = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(frame.note.isEmpty ? Palette.textDim : Palette.accent)
                        Text(frame.note.isEmpty ? "Add photographer's note…" : frame.note)
                            .font(AppTypography.label(11, weight: frame.note.isEmpty ? .regular : .medium))
                            .foregroundStyle(frame.note.isEmpty ? Palette.textDim : Palette.text)
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 0.75)
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
                                Text(String(format: "Roll #%02d · Frame #%02d — %@", frame.rollNumber, frame.frameNumber, frame.filmName))
                                    .font(AppTypography.label(15, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("\(frame.shutterSpeed) · \(cleanAperture) · ISO \(frame.iso) · Zone \(Roman.zone(frame.zone))")
                                    .font(AppTypography.mono(13, weight: .semibold))
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

// MARK: - Full Film Logbook, Gear & Lab Scan Matcher Sheet

struct FilmLogbookSheet: View {
    @ObservedObject var store: FilmLogStore
    var initialTab: Int = 0
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Int = 0
    @State private var searchQuery: String = ""
    @State private var expandedFamilyKey: String? = nil
    @State private var stagedVariant: FilmVariant? = nil
    @State private var stagedMaxFrames: Int = 36
    @State private var stagedExpired: Bool = false
    @State private var stagedExpiredYear: Int = 2005
    @State private var stagedAutoComp: Bool = true
    @State private var showCustomFilmCreator: Bool = false
    @State private var customFilmName: String = ""
    @State private var customFilmIso: Int = 400
    @State private var customFilmCategory: String = "Color"
    @State private var expandedRollKeys: Set<String> = []
    @State private var shareSheetItem: ShareSheetItem? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                // Top Search & 3-Tab Switcher
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.textDim)

                        TextField(
                            selectedTab == 0
                                ? "Search film stock, camera, lens, ISO…"
                                : (selectedTab == 1 ? "Search logged frames, notes, camera…" : "Search roll or frame…"),
                            text: $searchQuery
                        )
                        .font(AppTypography.label(13))
                        .foregroundStyle(Palette.text)

                        if !searchQuery.isEmpty {
                            Button {
                                searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Palette.textDim)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Palette.panelRaised, in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 0.75))

                    // iOS 27 Glass Segmented Tab Bar
                    HStack(spacing: 6) {
                        ForEach([
                            (0, "Roll & Gear", "film.stack"),
                            (1, "Frames (\(store.loggedFrames.count))", "list.bullet.rectangle.portrait"),
                            (2, "Scans", "photo.stack")
                        ], id: \.0) { idx, title, icon in
                            let selected = selectedTab == idx
                            Button {
                                MechanicalHaptics.tick()
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    selectedTab = idx
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: icon)
                                        .font(.system(size: 12, weight: .bold))
                                    Text(title)
                                        .font(AppTypography.label(12, weight: .bold))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(selected ? .black : Palette.textSub)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(selected ? Palette.accent : Palette.panelRaised, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)

                // Tab Content
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
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("Film Logbook & Gear")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        LocationCache.shared.requestPermissionAndRefresh()
                        MechanicalHaptics.tick()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: LocationCache.shared.lastKnownCoordinate != nil ? "location.fill" : "location")
                                .font(.system(size: 12, weight: .bold))
                            Text("GPS")
                                .font(AppTypography.mono(11, weight: .bold))
                        }
                        .foregroundStyle(LocationCache.shared.lastKnownCoordinate != nil ? Palette.good : Palette.textSub)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(AppTypography.label(14, weight: .bold))
                    .foregroundStyle(Palette.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            selectedTab = initialTab
            LocationCache.shared.refreshIfAuthorized()
        }
        .sheet(item: $shareSheetItem) { item in
            ActivityShareSheet(items: item.items)
        }
    }

    // MARK: - Tab 0: Roll & Gear

    private var rollAndGearTab: some View {
        let roll = store.rollState
        let filteredFamilies: [FilmFamily] = {
            let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return BUILTIN_FILM_FAMILIES }
            return BUILTIN_FILM_FAMILIES.filter { fam in
                if fuzzyMatchScore(query: q, target: "\(fam.brand) \(fam.familyName) \(fam.category)") > 0 {
                    return true
                }
                return fam.variants.contains { v in
                    fuzzyMatchScore(query: q, target: "\(v.fullName) \(v.iso)") > 0
                }
            }
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

        return ScrollView {
            VStack(spacing: 14) {
                // 1. Active Roll Card
                ActiveRollHeroCard(roll: roll) {
                    // Complete & rewind roll
                    var unloaded = roll
                    unloaded.rollNumber = roll.rollNumber + 1
                    unloaded.filmName = ""
                    unloaded.currentFrame = 1
                    unloaded.isExpired = false
                    store.rollState = unloaded
                } onAdjustFrame: { delta in
                    MechanicalHaptics.tick()
                    var next = roll
                    next.currentFrame = (roll.currentFrame + delta).clamped(to: 1...99)
                    store.rollState = next
                }

                // 2. Camera & Lens Gear Rig Section
                GearSetupSection(store: store, searchQuery: searchQuery)

                // 3. Custom Film Stocks Section
                customFilmSection

                // 4. Built-in Brand-Grouped Film Catalog
                ForEach(familiesByBrand, id: \.0) { brand, families in
                    let totalVariants = families.reduce(0) { $0 + $1.variants.count }
                    VStack(spacing: 8) {
                        BrandHeaderBanner(brand: brand, stockCount: totalVariants)

                        ForEach(families) { family in
                            let isExpanded = expandedFamilyKey == family.id
                            let isActiveFamily = !roll.isUnloaded && family.variants.contains {
                                $0.fullName.caseInsensitiveCompare(roll.filmName) == .orderedSame && $0.iso == roll.boxIso
                            }

                            FilmFamilyExpandableCard(
                                family: family,
                                isExpanded: isExpanded,
                                isActiveFamily: isActiveFamily,
                                activeRoll: roll,
                                stagedVariant: $stagedVariant,
                                stagedMaxFrames: $stagedMaxFrames,
                                stagedExpired: $stagedExpired,
                                stagedExpiredYear: $stagedExpiredYear,
                                stagedAutoComp: $stagedAutoComp,
                                onToggleExpand: {
                                    MechanicalHaptics.tick()
                                    withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                                        if isExpanded {
                                            expandedFamilyKey = nil
                                        } else {
                                            expandedFamilyKey = family.id
                                            stagedVariant = family.variants.first(where: { $0.fullName == roll.filmName }) ?? family.variants.first
                                            stagedMaxFrames = roll.maxFrames
                                            stagedExpired = roll.isExpired
                                            stagedExpiredYear = roll.expiredYear
                                            stagedAutoComp = roll.autoApplyExpiredComp
                                        }
                                    }
                                },
                                onLoadRoll: { variant in
                                    let nextRollNum = roll.isUnloaded ? roll.rollNumber : (roll.currentFrame > 1 ? roll.rollNumber + 1 : roll.rollNumber)
                                    store.rollState = FilmRollState(
                                        rollNumber: nextRollNum,
                                        filmName: variant.fullName,
                                        boxIso: variant.iso,
                                        category: family.category,
                                        currentFrame: 1,
                                        maxFrames: stagedMaxFrames,
                                        isExpired: stagedExpired,
                                        expiredYear: stagedExpiredYear,
                                        autoApplyExpiredComp: stagedAutoComp
                                    )
                                    withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                                        expandedFamilyKey = nil
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
    }

    private var customFilmSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CUSTOM FILM STOCKS")
                    .font(AppTypography.label(10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Palette.accent)
                Spacer()
                Button {
                    MechanicalHaptics.tick()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        showCustomFilmCreator.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showCustomFilmCreator ? "minus.circle.fill" : "plus.circle.fill")
                        Text(showCustomFilmCreator ? "Close" : "New Stock")
                    }
                    .font(AppTypography.label(11, weight: .bold))
                    .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
            }

            if showCustomFilmCreator {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Custom Film Name (e.g. Eastman 5219 / Vision3 500T)", text: $customFilmName)
                        .font(AppTypography.label(13))
                        .foregroundStyle(Palette.text)
                        .padding(10)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    HStack(spacing: 6) {
                        ForEach(["Color", "B&W", "Slide"], id: \.self) { cat in
                            let sel = customFilmCategory == cat
                            Button {
                                MechanicalHaptics.tick()
                                customFilmCategory = cat
                            } label: {
                                Text(cat)
                                    .font(AppTypography.label(11, weight: .bold))
                                    .foregroundStyle(sel ? .black : Palette.textSub)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(sel ? Palette.accent : Color.white.opacity(0.06), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(FILM_ISO_STOPS, id: \.self) { isoStop in
                                let sel = customFilmIso == isoStop
                                Button {
                                    MechanicalHaptics.tick()
                                    customFilmIso = isoStop
                                } label: {
                                    Text("ISO \(isoStop)")
                                        .font(AppTypography.mono(11, weight: .bold))
                                        .foregroundStyle(sel ? .black : Palette.textSub)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(sel ? Palette.accent : Color.white.opacity(0.06), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    let cleanName = customFilmName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Custom Film"
                        : customFilmName.trimmingCharacters(in: .whitespacesAndNewlines)

                    LoadFilmHoldButton(label: "Hold to Save & Load \(cleanName) \(customFilmIso)") {
                        let preset = FilmStockPreset(
                            name: cleanName,
                            iso: customFilmIso,
                            category: customFilmCategory,
                            isCustom: true
                        )
                        store.addCustomFilm(preset)
                        store.rollState = FilmRollState(
                            rollNumber: store.rollState.isUnloaded ? store.rollState.rollNumber : store.rollState.rollNumber + 1,
                            filmName: cleanName,
                            boxIso: customFilmIso,
                            category: customFilmCategory,
                            currentFrame: 1,
                            maxFrames: 36
                        )
                        customFilmName = ""
                        showCustomFilmCreator = false
                    }
                }
                .padding(10)
                .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if !store.customFilms.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.customFilms) { stock in
                            HStack(spacing: 8) {
                                Button {
                                    MechanicalHaptics.confirm()
                                    store.rollState = FilmRollState(
                                        rollNumber: store.rollState.isUnloaded ? store.rollState.rollNumber : store.rollState.rollNumber + 1,
                                        filmName: stock.name,
                                        boxIso: stock.iso,
                                        category: stock.category,
                                        currentFrame: 1,
                                        maxFrames: store.rollState.maxFrames
                                    )
                                } label: {
                                    HStack(spacing: 6) {
                                        FilmCanisterArtwork(
                                            brand: stock.name,
                                            familyName: stock.name,
                                            category: stock.category,
                                            iso: stock.iso,
                                            width: 28,
                                            height: 36
                                        )
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(stock.name)
                                                .font(AppTypography.label(12, weight: .bold))
                                                .foregroundStyle(Palette.text)
                                            Text("ISO \(stock.iso) · \(stock.category)")
                                                .font(AppTypography.mono(10, weight: .medium))
                                                .foregroundStyle(Palette.textSub)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)

                                Button {
                                    MechanicalHaptics.warning()
                                    store.deleteCustomFilm(stock)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(Palette.textDim)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(8)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 0.75)
                )
        )
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
                    VStack(spacing: 10) {
                        Image(systemName: "film")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .padding(14)
                            .background(Palette.accent.opacity(0.14), in: Circle())

                        Text("No Logged Frames")
                            .font(AppTypography.label(16, weight: .bold))
                            .foregroundStyle(Palette.text)

                        Text("Tap HOLD on the viewfinder to freeze a reading, then tap 'Log Frame' to record your exposure, snapshot, and GPS.")
                            .font(AppTypography.label(12, weight: .medium))
                            .foregroundStyle(Palette.textSub)
                            .multilineTextAlignment(.center)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Palette.panelRaised)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(Palette.border, lineWidth: 0.75)
                            )
                    )
                } else {
                    ForEach(Array(rollGroups.enumerated()), id: \.element.key) { idx, group in
                        let isExpanded = idx == 0 || expandedRollKeys.contains(group.key) || !searchQuery.isEmpty
                        VStack(spacing: 10) {
                            HStack(spacing: 10) {
                                Button {
                                    MechanicalHaptics.tick()
                                    if expandedRollKeys.contains(group.key) {
                                        expandedRollKeys.remove(group.key)
                                    } else {
                                        expandedRollKeys.insert(group.key)
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        FilmCanisterArtwork(
                                            brand: group.header.filmName,
                                            familyName: group.header.filmName,
                                            category: "Color",
                                            iso: group.header.iso,
                                            width: 34,
                                            height: 44
                                        )

                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text(String(format: "ROLL #%02d", group.header.rollNumber))
                                                    .font(AppTypography.mono(10, weight: .black))
                                                    .foregroundStyle(.black)
                                                    .padding(.horizontal, 7)
                                                    .padding(.vertical, 2)
                                                    .background(Palette.accent, in: Capsule())

                                                Text("\(group.frames.count) exposures")
                                                    .font(AppTypography.mono(11, weight: .bold))
                                                    .foregroundStyle(Palette.textSub)
                                            }

                                            Text(formatFilmDisplay(name: group.header.filmName, iso: group.header.iso))
                                                .font(AppTypography.label(14, weight: .bold))
                                                .foregroundStyle(Palette.text)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)

                                // CSV & Share buttons
                                Button {
                                    MechanicalHaptics.confirm()
                                    if let url = ExifAndXmpWriter.createRollCsvFileURL(group.frames) {
                                        shareSheetItem = ShareSheetItem(items: [url])
                                    }
                                } label: {
                                    Text("CSV")
                                        .font(AppTypography.mono(10, weight: .bold))
                                        .foregroundStyle(Palette.accent)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 6)
                                        .background(Palette.accent.opacity(0.14), in: Capsule())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    MechanicalHaptics.confirm()
                                    let summary = ExifAndXmpWriter.generateRollTextSummary(group.frames)
                                    if !summary.isEmpty {
                                        shareSheetItem = ShareSheetItem(items: [summary])
                                    }
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Palette.text)
                                        .padding(7)
                                        .background(Color.white.opacity(0.08), in: Circle())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Palette.panelRaised)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .strokeBorder(Palette.border, lineWidth: 0.75)
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
    let onCompleteRoll: () -> Void
    let onAdjustFrame: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if roll.isUnloaded {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Palette.accent.opacity(0.16))
                            .frame(width: 48, height: 48)
                        Image(systemName: "film.stack")
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(Palette.accent)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(format: "CAMERA CHAMBER EMPTY · NEXT ROLL #%02d", roll.rollNumber))
                            .font(AppTypography.label(10, weight: .bold))
                            .tracking(0.7)
                            .foregroundStyle(Palette.accent)

                        Text("Select a 35mm or 120 film stock below to load your camera")
                            .font(AppTypography.label(13, weight: .bold))
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
                        width: 54,
                        height: 64
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(String(format: "ACTIVE ROLL #%02d", roll.rollNumber))
                                .font(AppTypography.mono(10, weight: .black))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Palette.accent, in: Capsule())

                            Text(roll.category.uppercased())
                                .font(AppTypography.mono(9.5, weight: .bold))
                                .foregroundStyle(Palette.textSub)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.08), in: Capsule())

                            if roll.isExpired {
                                Text("EXP \(roll.expiredYear)")
                                    .font(AppTypography.mono(9.5, weight: .bold))
                                    .foregroundStyle(Palette.slow)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Palette.slow.opacity(0.16), in: Capsule())
                            }
                        }

                        Text(formatFilmDisplay(name: roll.filmName, iso: roll.boxIso))
                            .font(AppTypography.label(16, weight: .bold))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            Text(roll.isBonusFrames
                                 ? String(format: "Frame +%02d (Bonus past %d)", roll.currentFrame, roll.maxFrames)
                                 : String(format: "Frame %02d / %02d", roll.currentFrame, roll.maxFrames))
                                .font(AppTypography.mono(12, weight: .bold))
                                .foregroundStyle(roll.isBonusFrames ? Palette.good : Palette.accent)

                            if roll.activeExpiredCompEv > 0.05 {
                                Text("+\(String(format: "%.1f", roll.activeExpiredCompEv)) EV Auto-Comp")
                                    .font(AppTypography.mono(10, weight: .bold))
                                    .foregroundStyle(Palette.slow)
                            }
                        }
                    }

                    Spacer()

                    // Manual Frame Stepper (- / +)
                    VStack(spacing: 4) {
                        Button {
                            onAdjustFrame(1)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Palette.text)
                                .frame(width: 28, height: 24)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            onAdjustFrame(-1)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Palette.text)
                                .frame(width: 28, height: 24)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                CompleteRollHoldButton(onCompleted: onCompleteRoll)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(roll.isUnloaded ? Palette.border : Palette.accent.opacity(0.45), lineWidth: 1)
                )
        )
    }
}

// MARK: - Expandable Film Family Card + Inline Roll Loader

private struct FilmFamilyExpandableCard: View {
    let family: FilmFamily
    let isExpanded: Bool
    let isActiveFamily: Bool
    let activeRoll: FilmRollState
    @Binding var stagedVariant: FilmVariant?
    @Binding var stagedMaxFrames: Int
    @Binding var stagedExpired: Bool
    @Binding var stagedExpiredYear: Int
    @Binding var stagedAutoComp: Bool
    let onToggleExpand: () -> Void
    let onLoadRoll: (FilmVariant) -> Void

    private let expiryDecadeYears = [2015, 2005, 1995, 1985, 1975]

    var body: some View {
        let previewVariant = stagedVariant ?? family.variants.first!

        VStack(alignment: .leading, spacing: 10) {
            Button(action: onToggleExpand) {
                HStack(spacing: 12) {
                    FilmCanisterArtwork(
                        brand: family.brand,
                        familyName: family.familyName,
                        category: family.category,
                        iso: previewVariant.iso,
                        showLeader: isActiveFamily || isExpanded,
                        width: 44,
                        height: 54
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(family.familyName)
                                .font(AppTypography.label(14, weight: .bold))
                                .foregroundStyle(isActiveFamily ? Palette.accent : Palette.text)

                            Text(family.category.uppercased())
                                .font(AppTypography.mono(9, weight: .bold))
                                .foregroundStyle(Palette.textSub)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.06), in: Capsule())

                            if isActiveFamily {
                                Text("LOADED")
                                    .font(AppTypography.mono(9, weight: .black))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Palette.accent, in: Capsule())
                            }
                        }

                        Text(family.variants.map(\.label).joined(separator: "  ·  "))
                            .font(AppTypography.label(11, weight: .medium))
                            .foregroundStyle(Palette.textSub)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.textSub)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().overlay(Palette.border)

                // 1. Choose Variant / Speed
                Text("FILM VARIANT & BOX ISO")
                    .font(AppTypography.label(10, weight: .bold))
                    .foregroundStyle(Palette.textSub)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(family.variants) { v in
                            let sel = (stagedVariant?.id ?? family.variants.first?.id) == v.id
                            Button {
                                MechanicalHaptics.tick()
                                stagedVariant = v
                            } label: {
                                HStack(spacing: 5) {
                                    Text(v.label)
                                        .font(AppTypography.label(12, weight: .bold))
                                    Text("ISO \(v.iso)")
                                        .font(AppTypography.mono(10, weight: .bold))
                                        .opacity(0.8)
                                }
                                .foregroundStyle(sel ? .black : Palette.text)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(sel ? Palette.accent : Color.white.opacity(0.07), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // 2. Roll Exposure Length (12, 16, 24, 36)
                HStack {
                    Text("EXPOSURES")
                        .font(AppTypography.label(10, weight: .bold))
                        .foregroundStyle(Palette.textSub)
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(ROLL_LENGTH_OPTIONS, id: \.self) { len in
                            let sel = stagedMaxFrames == len
                            Button {
                                MechanicalHaptics.tick()
                                stagedMaxFrames = len
                            } label: {
                                Text("\(len) exp")
                                    .font(AppTypography.mono(11, weight: .bold))
                                    .foregroundStyle(sel ? .black : Palette.textSub)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(sel ? Palette.accent : Color.white.opacity(0.07), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // 3. Expired Film Toggle & Decade Compensation
                HStack {
                    Toggle(isOn: $stagedExpired) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Expired Film Stock")
                                .font(AppTypography.label(12, weight: .bold))
                                .foregroundStyle(Palette.text)
                            Text(family.category == "Slide" ? "Slide film keeps 0 EV highlight protection" : "+1 stop per decade rule")
                                .font(AppTypography.label(10, weight: .medium))
                                .foregroundStyle(Palette.textSub)
                        }
                    }
                    .tint(Palette.accent)
                }

                if stagedExpired {
                    HStack(spacing: 6) {
                        ForEach(expiryDecadeYears, id: \.self) { yr in
                            let sel = stagedExpiredYear == yr
                            Button {
                                MechanicalHaptics.tick()
                                stagedExpiredYear = yr
                            } label: {
                                Text("\(yr)s")
                                    .font(AppTypography.mono(11, weight: .bold))
                                    .foregroundStyle(sel ? .black : Palette.textSub)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(sel ? Palette.slow : Color.white.opacity(0.06), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if family.category != "Slide" {
                        Toggle("Auto-Apply +1 EV / Decade Compensation", isOn: $stagedAutoComp)
                            .font(AppTypography.label(11, weight: .semibold))
                            .foregroundStyle(Palette.slow)
                            .tint(Palette.slow)
                    }
                }

                // 4. Hold to Load Canister Button
                let chosen = stagedVariant ?? family.variants.first!
                LoadFilmHoldButton(label: "Hold to Load \(chosen.fullName)") {
                    onLoadRoll(chosen)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isActiveFamily ? Palette.accent.opacity(0.10) : Palette.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(isActiveFamily || isExpanded ? Palette.accent.opacity(0.55) : Palette.border, lineWidth: 0.9)
                )
        )
    }
}
