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
        if let currentRoll {
            Section("Roll") {
                Picker("Active Roll", selection: rollSelectionBinding(rolls: rolls)) {
                    ForEach(rolls) { roll in
                        Text(rollMenuTitle(roll)).tag(roll.id)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("Frames", value: "\(currentRoll.frames.count)")
                    .monospacedDigit()
            }
        } else {
            Section {
                ContentUnavailableView("No Logged Frames", systemImage: "film")
            }
        }
    }

    @ViewBuilder
    private var scansSection: some View {
        Section("Scans") {
            Button {
                Haptics.press()
                showFolderImporter = true
            } label: {
                Label("Import Folder…", systemImage: "folder")
            }
            .disabled(isLoadingScans || isInjectingExif)

            Button {
                Haptics.press()
                showPhotoFilesImporter = true
            } label: {
                Label("Import Files…", systemImage: "doc")
            }
            .disabled(isLoadingScans || isInjectingExif)

            if isLoadingScans {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading scans…")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                LabeledContent("Imported", value: "\(importedScans.count)")
                    .monospacedDigit()

                if importedScans.count > 1 {
                    Toggle("Reverse Order", isOn: $reverseScanOrder)
                }
            }
        }
    }

    @ViewBuilder
    private func matchSection(
        roll: LoggedRoll,
        scanCount: Int,
        shifts: [Int],
        matchedCount: Int
    ) -> some View {
        Section("Alignment") {
            LabeledContent("Matched", value: "\(matchedCount) / \(roll.frames.count)")
                .monospacedDigit()

            if hasActiveShifts {
                Button("Reset Shifts", role: .destructive) {
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

                    Text(isInjectingExif ? "Writing EXIF…" : "Write EXIF to Scans")
                }
            }
            .disabled(matchedCount == 0 || isInjectingExif)

            if !scans.isEmpty {
                Button {
                    Haptics.press()
                    onShareItems(scans.map(\.url))
                } label: {
                    Label("Share Scans", systemImage: "square.and.arrow.up")
                }
                .disabled(isInjectingExif)
            }

            Menu {
                if let url = ExifAndXmpWriter.createRollCsvFileURL(frames) {
                    ShareLink("Roll as CSV", item: url)
                }

                if let url = ExifAndXmpWriter.createXmpSidecarsFileURL(frames) {
                    ShareLink("XMP Sidecars", item: url)
                }

                let summary = ExifAndXmpWriter.generateRollTextSummary(frames)
                if !summary.isEmpty {
                    ShareLink("Roll Summary", item: summary)
                }
            } label: {
                Label("Export Roll…", systemImage: "square.and.arrow.up.on.square")
            }
            .disabled(isInjectingExif)
        } header: {
            Text("Export")
        } footer: {
            if let message = injectionStatusMessage {
                Text(message)
            }
        }
    }

    @ViewBuilder
    private func framesSection(roll: LoggedRoll, scans: [ImportedLabScan], shifts: [Int]) -> some View {
        Section("Frames") {
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
            injectionStatusMessage = "No scans matched."
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
                    injectionStatusMessage = "EXIF written to \(written) scan\(written == 1 ? "" : "s")."
                } else if written > 0 {
                    Haptics.warning()
                    injectionStatusMessage = "EXIF written to \(written) / \(jobs.count) scans."
                } else {
                    Haptics.error()
                    injectionStatusMessage = "Could not write EXIF."
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
                    .monospacedDigit()
            } label: {
                VStack(alignment: .leading) {
                    Text("Frame \(frame.frameNumber)")
                        .monospacedDigit()

                    if localShift != 0 {
                        Text(shiftDescription)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
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
        localShift > 0 ? "+\(localShift)" : "\(localShift)"
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

            VStack(alignment: .leading) {
                Text("Frame \(frame.frameNumber)")
                    .monospacedDigit()

                Text(subtitleText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }

            Spacer()

            Menu {
                if let scan {
                    Button {
                        onShareScan(scan)
                    } label: {
                        Label("Share Scan", systemImage: "square.and.arrow.up")
                    }
                }

                if localShift != 0 {
                    Button {
                        onResetShift()
                    } label: {
                        Label("Reset Shift", systemImage: "arrow.counterclockwise")
                    }
                }

                if scan == nil {
                    Button {
                        onImportScans()
                    } label: {
                        Label("Import Scans…", systemImage: "folder")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Actions for frame \(frame.frameNumber)")
        }
    }

    private var subtitleText: String {
        let aperture = frame.aperture.lowercased().hasPrefix("f/")
            ? frame.aperture
            : "f/\(frame.aperture)"
        let exp = "\(frame.shutterSpeed) · \(aperture)"
        if let scan, let scanNumber {
            return "Scan \(scanNumber) · \(scan.displayName)"
        }
        if isSkipped {
            return "\(exp) · Skipped"
        }
        if hasScans {
            return "\(exp) · Unmatched"
        }
        return exp
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
                Image(systemName: "photo")
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }
}
