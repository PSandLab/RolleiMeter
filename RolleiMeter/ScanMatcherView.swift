import Foundation
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Imported Lab Scan

struct ImportedLabScan: Identifiable {
    let id = UUID()
    let url: URL
    let displayName: String
    let thumbnail: UIImage?
}

// MARK: - Logbook Roll

private struct LoggedRoll: Identifiable {
    let id: String
    let header: LoggedFrame
    let frames: [LoggedFrame]

    var rollNumber: Int { header.rollNumber }
    var filmName: String { header.filmName }
    var iso: Int { header.iso }
}

// MARK: - Lab Scan Matcher

/// Pairs the frames of one logged roll with the scans imported from a lab,
/// then writes the logbook metadata into the matched scans.
///
/// The screen is a plain inset-grouped `List` so it inherits the parent
/// `NavigationStack` and the system's grouped-table look.
struct ScanMatcherTabView: View {
    @ObservedObject var store: FilmLogStore
    let onShareItems: ([Any]) -> Void

    @State private var selectedRollKey: String? = nil
    @State private var importedScans: [ImportedLabScan] = []
    @State private var isLoadingScans = false
    @State private var reverseScanOrder = false
    @State private var cascadeShiftAtFrame: [Int: Int] = [:]
    @State private var injectionStatusMessage: String? = nil
    @State private var isInjectingExif = false
    @State private var showFolderImporter = false
    @State private var showPhotoFilesImporter = false

    var body: some View {
        let rolls = loggedRolls
        let currentRoll = activeRoll(in: rolls)
        let frames = currentRoll?.frames ?? []
        let scans = reverseScanOrder ? Array(importedScans.reversed()) : importedScans
        let shifts = cumulativeShifts(frameCount: frames.count)
        let matchedCount = matchedScanCount(scans: scans, shifts: shifts)

        List {
            rollSection(rolls: rolls, currentRoll: currentRoll)

            scansSection

            if let currentRoll, !frames.isEmpty {
                // Keep the write/share actions within reach before the long
                // frame lists, the way a native task screen front-loads its action.
                exportSection(frames: frames, scans: scans, matchedCount: matchedCount)

                if !scans.isEmpty {
                    matchSection(
                        roll: currentRoll,
                        scanCount: scans.count,
                        shifts: shifts,
                        matchedCount: matchedCount
                    )
                }

                framesSection(roll: currentRoll, scans: scans, shifts: shifts)
            }
        }
        .listStyle(.insetGrouped)
        .fileImporter(
            isPresented: $showFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let folderURL = urls.first else { return }
            loadScansFromFolder(folderURL)
        }
        .fileImporter(
            isPresented: $showPhotoFilesImporter,
            allowedContentTypes: [.image, .rawImage, .jpeg, .tiff],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            loadScansFromFileURLs(urls)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func rollSection(rolls: [LoggedRoll], currentRoll: LoggedRoll?) -> some View {
        Section {
            if let currentRoll {
                Picker("Active roll", selection: rollSelectionBinding(rolls: rolls)) {
                    ForEach(rolls) { roll in
                        Text(rollMenuTitle(roll)).tag(roll.id)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("Frames logged") {
                    Text("\(currentRoll.frames.count)")
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSub)
                }
            } else {
                ContentUnavailableView(
                    "No Logged Frames",
                    systemImage: "film",
                    description: Text("Hold the shutter in the viewfinder, then log the frame.")
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        } header: {
            Text("Roll")
        }
    }

    @ViewBuilder
    private var scansSection: some View {
        Section {
            Button {
                Haptics.press()
                showFolderImporter = true
            } label: {
                Label("Import folder…", systemImage: "folder")
            }
            .disabled(isLoadingScans || isInjectingExif)

            Button {
                Haptics.press()
                showPhotoFilesImporter = true
            } label: {
                Label("Import files…", systemImage: "doc")
            }
            .disabled(isLoadingScans || isInjectingExif)

            if isLoadingScans {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading scans…")
                        .foregroundStyle(Palette.textSub)
                }
                .frame(minHeight: Metrics.minTap)
                .accessibilityElement(children: .combine)
            } else {
                LabeledContent("Imported scans") {
                    Text("\(importedScans.count)")
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSub)
                }

                if importedScans.count > 1 {
                    Toggle("Reverse scan order", isOn: $reverseScanOrder)
                }
            }
        } header: {
            Text("Scans")
        } footer: {
            Text("Scans are matched to frames in filename order, starting with frame 1. Turn on reverse order if the lab numbered the files backwards.")
        }
    }

    @ViewBuilder
    private func matchSection(
        roll: LoggedRoll,
        scanCount: Int,
        shifts: [Int],
        matchedCount: Int
    ) -> some View {
        Section {
            LabeledContent("Matched scans") {
                Text("\(matchedCount) of \(roll.frames.count)")
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSub)
            }

            if hasActiveShifts {
                Button("Reset shift adjustments", role: .destructive) {
                    Haptics.rigid()
                    cascadeShiftAtFrame.removeAll()
                }
            }

            ForEach(Array(roll.frames.enumerated()), id: \.element.id) { index, frame in
                let targetIndex = index + shifts[index]

                FrameShiftRow(
                    frame: frame,
                    targetLabel: scanTargetLabel(targetIndex: targetIndex, scanCount: scanCount),
                    localShift: cascadeShiftAtFrame[index] ?? 0,
                    onShift: { delta in
                        Haptics.tap()
                        cascadeShiftAtFrame[index] = (cascadeShiftAtFrame[index] ?? 0) + delta
                    }
                )
            }
        } header: {
            Text("Match")
        } footer: {
            Text("Each frame uses the scan in the same position. A shift moves that frame and every frame after it.")
        }
    }

    @ViewBuilder
    private func exportSection(frames: [LoggedFrame], scans: [ImportedLabScan], matchedCount: Int) -> some View {
        Section {
            Button {
                writeExif(frames: frames, scans: scans)
            } label: {
                HStack(spacing: 8) {
                    if isInjectingExif {
                        ProgressView()
                    } else {
                        Image(systemName: "wand.and.stars")
                    }

                    Text(isInjectingExif ? "Writing EXIF…" : "Write EXIF to matched scans")
                }
            }
            .controlSize(.large)
            .disabled(matchedCount == 0 || isInjectingExif)

            if !scans.isEmpty {
                Button {
                    Haptics.press()
                    onShareItems(scans.map(\.url))
                } label: {
                    Label("Share scans", systemImage: "square.and.arrow.up")
                }
                .disabled(isInjectingExif)
            }

            Menu {
                Button {
                    guard let url = ExifAndXmpWriter.createRollCsvFileURL(frames) else { return }
                    onShareItems([url])
                } label: {
                    Label("Roll log spreadsheet", systemImage: "tablecells")
                }

                Button {
                    guard let url = ExifAndXmpWriter.createXmpSidecarsFileURL(frames) else { return }
                    onShareItems([url])
                } label: {
                    Label("XMP sidecars", systemImage: "doc.badge.gearshape")
                }

                Button {
                    let summary = ExifAndXmpWriter.generateRollTextSummary(frames)
                    guard !summary.isEmpty else { return }
                    onShareItems([summary])
                } label: {
                    Label("Text summary", systemImage: "text.alignleft")
                }
            } label: {
                Label("Export roll…", systemImage: "square.and.arrow.up.on.square")
            }
            .disabled(isInjectingExif)
        } header: {
            Text("Export")
        } footer: {
            if let message = injectionStatusMessage {
                Text(message)
            } else {
                Text("Writes film, exposure and gear metadata into each matched scan without re-encoding the image.")
            }
        }
    }

    @ViewBuilder
    private func framesSection(roll: LoggedRoll, scans: [ImportedLabScan], shifts: [Int]) -> some View {
        Section {
            ForEach(Array(roll.frames.enumerated()), id: \.element.id) { index, frame in
                let localShift = cascadeShiftAtFrame[index] ?? 0
                let targetIndex = index + shifts[index]
                let scan = scans.indices.contains(targetIndex) ? scans[targetIndex] : nil

                FrameScanRow(
                    frame: frame,
                    scan: scan,
                    scanNumber: scan == nil ? nil : targetIndex + 1,
                    hasScans: !scans.isEmpty,
                    isSkipped: targetIndex < 0,
                    localShift: localShift,
                    onShareScan: { matched in
                        Haptics.press()
                        onShareItems([matched.url])
                    },
                    onResetShift: {
                        Haptics.tap()
                        cascadeShiftAtFrame[index] = nil
                    },
                    onImportScans: {
                        Haptics.press()
                        showPhotoFilesImporter = true
                    }
                )
            }
        } header: {
            Text("Frames")
        } footer: {
            Text("Use a frame's menu to share its scan, reset its alignment, or import scans.")
        }
    }

    // MARK: - Import

    private func loadScansFromFolder(_ folderURL: URL) {
        isLoadingScans = true
        injectionStatusMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let didAccess = folderURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess { folderURL.stopAccessingSecurityScopedResource() }
            }

            let extensions: Set<String> = ["jpg", "jpeg", "dng", "tif", "tiff", "heic", "webp", "png"]
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            let imageURLs = contents
                .filter { extensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

            let loaded = imageURLs.map { url in
                ImportedLabScan(
                    url: url,
                    displayName: url.lastPathComponent,
                    thumbnail: decodeThumbnail(at: url)
                )
            }

            DispatchQueue.main.async {
                finishLoadingScans(loaded)
            }
        }
    }

    private func loadScansFromFileURLs(_ urls: [URL]) {
        isLoadingScans = true
        injectionStatusMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let sorted = urls.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }

            let loaded = sorted.map { url -> ImportedLabScan in
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess { url.stopAccessingSecurityScopedResource() }
                }
                return ImportedLabScan(
                    url: url,
                    displayName: url.lastPathComponent,
                    thumbnail: decodeThumbnail(at: url)
                )
            }

            DispatchQueue.main.async {
                finishLoadingScans(loaded)
            }
        }
    }

    private func finishLoadingScans(_ scans: [ImportedLabScan]) {
        cascadeShiftAtFrame.removeAll()
        importedScans = scans
        isLoadingScans = false

        if scans.isEmpty {
            Haptics.warning()
        } else {
            Haptics.success()
        }
    }

    private func decodeThumbnail(at url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 320
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    // MARK: - EXIF Injection

    private func writeExif(frames: [LoggedFrame], scans: [ImportedLabScan]) {
        guard !isInjectingExif else { return }

        let shifts = cumulativeShifts(frameCount: frames.count)
        var jobs: [(url: URL, frame: LoggedFrame)] = []
        jobs.reserveCapacity(frames.count)

        for (index, frame) in frames.enumerated() {
            let targetIndex = index + shifts[index]
            guard scans.indices.contains(targetIndex) else { continue }
            jobs.append((url: scans[targetIndex].url, frame: frame))
        }

        guard !jobs.isEmpty else {
            injectionStatusMessage = "No scans are matched to this roll yet."
            Haptics.warning()
            return
        }

        isInjectingExif = true
        injectionStatusMessage = nil
        Haptics.rigid()

        DispatchQueue.global(qos: .userInitiated).async {
            var written = 0
            for job in jobs {
                if ExifAndXmpWriter.injectExifMetadataIntoScan(url: job.url, frame: job.frame) {
                    written += 1
                }
            }

            DispatchQueue.main.async {
                isInjectingExif = false

                if written == jobs.count {
                    Haptics.success()
                    injectionStatusMessage = "EXIF written to \(written) matched scan\(written == 1 ? "" : "s")."
                } else if written > 0 {
                    Haptics.warning()
                    injectionStatusMessage = "EXIF written to \(written) of \(jobs.count) matched scans."
                } else {
                    Haptics.error()
                    injectionStatusMessage = "No EXIF metadata could be written to the matched scans."
                }
            }
        }
    }

    // MARK: - Matching Helpers

    private var loggedRolls: [LoggedRoll] {
        let grouped = Dictionary(grouping: store.loggedFrames) { "\($0.rollNumber)|\($0.filmName)" }
        return grouped.compactMap { entry -> LoggedRoll? in
            let frames = entry.value.sorted { $0.frameNumber < $1.frameNumber }
            guard let header = frames.first else { return nil }
            return LoggedRoll(id: entry.key, header: header, frames: frames)
        }
        .sorted { lhs, rhs in
            if lhs.rollNumber != rhs.rollNumber { return lhs.rollNumber > rhs.rollNumber }
            return lhs.filmName.localizedStandardCompare(rhs.filmName) == .orderedAscending
        }
    }

    private func activeRoll(in rolls: [LoggedRoll]) -> LoggedRoll? {
        guard let first = rolls.first else { return nil }
        guard let key = selectedRollKey,
              let match = rolls.first(where: { $0.id == key }) else {
            return first
        }
        return match
    }

    private func rollSelectionBinding(rolls: [LoggedRoll]) -> Binding<String> {
        Binding(
            get: { activeRoll(in: rolls)?.id ?? "" },
            set: { newKey in
                guard newKey != activeRoll(in: rolls)?.id else { return }
                selectedRollKey = newKey
                cascadeShiftAtFrame.removeAll()
                injectionStatusMessage = nil
                Haptics.tap()
            }
        )
    }

    private func rollMenuTitle(_ roll: LoggedRoll) -> String {
        let film = formatFilmDisplay(name: roll.filmName, iso: roll.iso)
        return String(format: "Roll %02d · %@", roll.rollNumber, film)
    }

    private func cumulativeShifts(frameCount: Int) -> [Int] {
        guard frameCount > 0 else { return [] }
        var running = 0
        var shifts: [Int] = []
        shifts.reserveCapacity(frameCount)

        for index in 0..<frameCount {
            running += cascadeShiftAtFrame[index] ?? 0
            shifts.append(running)
        }
        return shifts
    }

    private func matchedScanCount(scans: [ImportedLabScan], shifts: [Int]) -> Int {
        guard !scans.isEmpty else { return 0 }
        return shifts.indices.reduce(0) { count, index in
            count + (scans.indices.contains(index + shifts[index]) ? 1 : 0)
        }
    }

    private func scanTargetLabel(targetIndex: Int, scanCount: Int) -> String {
        guard targetIndex >= 0 else { return "Skipped" }
        guard targetIndex < scanCount else { return "No scan" }
        return "Scan \(targetIndex + 1)"
    }

    private var hasActiveShifts: Bool {
        cascadeShiftAtFrame.values.contains { $0 != 0 }
    }
}

// MARK: - Frame Shift Row

private struct FrameShiftRow: View {
    let frame: LoggedFrame
    let targetLabel: String
    let localShift: Int
    let onShift: (Int) -> Void

    var body: some View {
        Stepper {
            LabeledContent {
                Text(targetLabel)
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSub)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Frame \(frame.frameNumber)")
                        .font(.body)
                        .monospacedDigit()

                    if localShift != 0 {
                        Text(shiftDescription)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Palette.slow)
                    }
                }
            }
        } onIncrement: {
            onShift(1)
        } onDecrement: {
            onShift(-1)
        }
    }

    private var shiftDescription: String {
        localShift > 0 ? "Shifted +\(localShift)" : "Shifted \(localShift)"
    }
}

// MARK: - Frame Scan Row

private struct FrameScanRow: View {
    let frame: LoggedFrame
    let scan: ImportedLabScan?
    let scanNumber: Int?
    let hasScans: Bool
    let isSkipped: Bool
    let localShift: Int
    let onShareScan: (ImportedLabScan) -> Void
    let onResetShift: () -> Void
    let onImportScans: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ScanThumbnail(image: scan?.thumbnail)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Frame \(frame.frameNumber)")
                        .font(.headline)
                        .monospacedDigit()

                    statusLabel
                }

                Text(formatFilmDisplay(name: frame.filmName, iso: frame.iso))
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSub)
                    .lineLimit(1)

                Text(exposureDescription)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSub)
                    .lineLimit(1)

                if let scan, let scanNumber {
                    Text("Scan \(scanNumber) · \(scan.displayName)")
                        .font(.caption)
                        .foregroundStyle(Palette.textDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            actionsMenu
        }
        .padding(.vertical, 3)
    }

    private var exposureDescription: String {
        let aperture = frame.aperture.lowercased().hasPrefix("f/")
            ? frame.aperture
            : "f/\(frame.aperture)"
        return "\(frame.shutterSpeed) · \(aperture) · ISO \(frame.iso)"
    }

    @ViewBuilder
    private var statusLabel: some View {
        if scan != nil {
            status("Matched", systemImage: "checkmark.circle.fill", tint: Palette.good)
        } else if isSkipped {
            status("Skipped", systemImage: "minus.circle.fill", tint: Palette.textSub)
        } else if hasScans {
            status("Unmatched", systemImage: "exclamationmark.triangle.fill", tint: Palette.slow)
        } else {
            status("No scans", systemImage: "exclamationmark.circle", tint: Palette.textSub)
        }
    }

    private func status(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
    }

    private var actionsMenu: some View {
        Menu {
            if let scan {
                Button {
                    onShareScan(scan)
                } label: {
                    Label("Share scan", systemImage: "square.and.arrow.up")
                }
            }

            if localShift != 0 {
                Button {
                    onResetShift()
                } label: {
                    Label("Reset shift", systemImage: "arrow.counterclockwise")
                }
            }

            if scan == nil {
                Button {
                    onImportScans()
                } label: {
                    Label("Import scans…", systemImage: "folder")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
                .foregroundStyle(Palette.textSub)
                .frame(width: Metrics.minTap, height: Metrics.minTap)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Actions for frame \(frame.frameNumber)"))
    }
}

// MARK: - Scan Thumbnail

private struct ScanThumbnail: View {
    let image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Palette.panelRaised
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(Palette.textDim)
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }
}
