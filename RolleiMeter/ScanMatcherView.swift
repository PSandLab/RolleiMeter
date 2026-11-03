import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ImportedLabScan: Identifiable {
    let id = UUID()
    let url: URL
    let displayName: String
    let thumbnail: UIImage?
}

struct ScanMatcherTabView: View {
    @ObservedObject var store: FilmLogStore
    let onShareItems: ([Any]) -> Void

    @State private var selectedRollIdx: Int = 0
    @State private var importedScans: [ImportedLabScan] = []
    @State private var isLoadingScans: Bool = false
    @State private var reverseScanOrder: Bool = false
    @State private var cascadeShiftAtFrame: [Int: Int] = [:]
    @State private var injectionStatusMessage: String? = nil
    @State private var isInjectingExif: Bool = false
    @State private var showFolderImporter: Bool = false
    @State private var showPhotoFilesImporter: Bool = false

    private var rollGroups: [(key: String, header: LoggedFrame, frames: [LoggedFrame])] {
        let grouped = Dictionary(grouping: store.loggedFrames) { "\($0.rollNumber)|\($0.filmName)" }
        return grouped.keys.sorted(by: >).compactMap { key in
            guard let list = grouped[key], !list.isEmpty else { return nil }
            let sorted = list.sorted { $0.frameNumber < $1.frameNumber }
            return (key: key, header: sorted[0], frames: sorted)
        }
    }

    var body: some View {
        let groups = rollGroups
        let safeRollIdx = groups.isEmpty ? 0 : selectedRollIdx.clamped(to: 0...(groups.count - 1))
        let activeRollFrames = groups.isEmpty ? [] : groups[safeRollIdx].frames
        let orderedScans = reverseScanOrder ? Array(importedScans.reversed()) : importedScans
        let hasActiveShifts = cascadeShiftAtFrame.values.contains(where: { $0 != 0 })

        let maxCount = activeRollFrames.map(\.frameNumber).max()
            ?? (activeRollFrames.isEmpty ? nil : activeRollFrames.count)
            ?? (importedScans.isEmpty ? nil : importedScans.count)
        let endLabel = maxCount.map(String.init) ?? "N"
        let scanOrderLabel = reverseScanOrder ? "\(endLabel) → 1" : "1 → \(endLabel)"

        ScrollView {
            VStack(spacing: 12) {
                // Header & Controls Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(importedScans.isEmpty ? Color.white.opacity(0.06) : Palette.accent.opacity(0.20))
                                .frame(width: 44, height: 44)
                            Image(systemName: "photo.stack.fill")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(Palette.accent)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("LAB SCAN MATCHER")
                                    .font(AppTypography.label(11, weight: .bold))
                                    .tracking(0.7)
                                    .foregroundStyle(Palette.accent)

                                if !importedScans.isEmpty {
                                    Text("\(importedScans.count) SCANS")
                                        .font(AppTypography.mono(10, weight: .bold))
                                        .foregroundStyle(Palette.good)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(Palette.good.opacity(0.18), in: Capsule())
                                }
                            }

                            Text(
                                isLoadingScans
                                    ? "Decoding lab scan thumbnails…"
                                    : (importedScans.isEmpty ? "Anchor & Cascade EXIF tagger for lab scans" : "Order: \(scanOrderLabel)")
                            )
                            .font(AppTypography.label(12, weight: .medium))
                            .foregroundStyle(Palette.textSub)
                            .lineLimit(1)
                        }

                        Spacer()

                        // Export Menu (.csv, .xmp, text summary)
                        Menu {
                            Button {
                                let target = activeRollFrames.isEmpty ? store.loggedFrames : activeRollFrames
                                if let url = ExifAndXmpWriter.createRollCsvFileURL(target) {
                                    onShareItems([url])
                                }
                            } label: {
                                Label("Export Roll CSV (.csv)", systemImage: "tablecells")
                            }

                            Button {
                                let target = activeRollFrames.isEmpty ? store.loggedFrames : activeRollFrames
                                if let url = ExifAndXmpWriter.createXmpSidecarsFileURL(target) {
                                    onShareItems([url])
                                }
                            } label: {
                                Label("Export XMP Sidecars (.xmp)", systemImage: "doc.badge.gearshape")
                            }

                            Button {
                                let target = activeRollFrames.isEmpty ? store.loggedFrames : activeRollFrames
                                let text = ExifAndXmpWriter.generateRollTextSummary(target)
                                if !text.isEmpty {
                                    onShareItems([text])
                                }
                            } label: {
                                Label("Share Text Summary", systemImage: "square.and.arrow.up")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(Palette.textSub)
                        }
                    }

                    // Roll Selector Carousel
                    if !groups.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("LOGGED ROLLS (\(groups.count))")
                                    .font(AppTypography.label(10, weight: .bold))
                                    .tracking(0.6)
                                    .foregroundStyle(Palette.textSub)
                                Spacer()
                                if groups.count > 1 {
                                    Text("Swipe to switch rolls →")
                                        .font(AppTypography.label(10, weight: .semibold))
                                        .foregroundStyle(Palette.accent)
                                }
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(groups.enumerated()), id: \.element.key) { idx, group in
                                        let selected = idx == safeRollIdx
                                        Button {
                                            MechanicalHaptics.tick()
                                            selectedRollIdx = idx
                                            cascadeShiftAtFrame.removeAll()
                                        } label: {
                                            VStack(alignment: .leading, spacing: 5) {
                                                HStack {
                                                    Text(String(format: "ROLL #%02d", group.header.rollNumber))
                                                        .font(AppTypography.mono(10, weight: .bold))
                                                        .foregroundStyle(selected ? .black : Palette.textSub)
                                                        .padding(.horizontal, 7)
                                                        .padding(.vertical, 2)
                                                        .background(selected ? Palette.accent : Color.white.opacity(0.08), in: Capsule())

                                                    Spacer()

                                                    Text("\(group.frames.count) exp")
                                                        .font(AppTypography.mono(11, weight: .bold))
                                                        .foregroundStyle(selected ? Palette.accent : Palette.textSub)
                                                }

                                                Text(formatFilmDisplay(name: group.header.filmName, iso: group.header.iso))
                                                    .font(AppTypography.label(13, weight: .bold))
                                                    .foregroundStyle(Palette.text)
                                                    .lineLimit(1)
                                            }
                                            .padding(10)
                                            .frame(width: 190)
                                            .background(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .fill(selected ? Palette.accent.opacity(0.14) : Color.white.opacity(0.04))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                            .strokeBorder(selected ? Palette.accent : Color.white.opacity(0.08), lineWidth: selected ? 1.4 : 0.75)
                                                    )
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    // Action Strip: Import Folder / Files + Reverse Order + Reset Shifts
                    HStack(spacing: 6) {
                        Menu {
                            Button {
                                MechanicalHaptics.click()
                                showFolderImporter = true
                            } label: {
                                Label("Select Scans Folder", systemImage: "folder.fill")
                            }

                            Button {
                                MechanicalHaptics.click()
                                showPhotoFilesImporter = true
                            } label: {
                                Label("Select Image Files", systemImage: "photo.on.rectangle.angled")
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.fill.badge.plus")
                                    .font(.system(size: 14, weight: .bold))
                                Text(importedScans.isEmpty ? "Import Lab Scans" : "Folder (\(importedScans.count))")
                                    .font(AppTypography.label(12, weight: .bold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Palette.accent, in: Capsule())
                        }

                        Button {
                            MechanicalHaptics.tick()
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                                reverseScanOrder.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: 12, weight: .bold))
                                    .rotationEffect(.degrees(reverseScanOrder ? 180 : 0))
                                Text(scanOrderLabel)
                                    .font(AppTypography.mono(11, weight: .bold))
                            }
                            .foregroundStyle(reverseScanOrder ? .black : Palette.text)
                            .padding(.horizontal, 12)
                            .frame(height: 40)
                            .background(reverseScanOrder ? Palette.slow : Color.white.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        if hasActiveShifts {
                            Button {
                                MechanicalHaptics.click()
                                cascadeShiftAtFrame.removeAll()
                            } label: {
                                Text("0±")
                                    .font(AppTypography.mono(12, weight: .bold))
                                    .foregroundStyle(Palette.accent)
                                    .padding(.horizontal, 12)
                                    .frame(height: 40)
                                    .background(Palette.accent.opacity(0.16), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Write Lossless EXIF Button
                    if !activeRollFrames.isEmpty && !orderedScans.isEmpty {
                        Button {
                            guard !isInjectingExif else { return }
                            MechanicalHaptics.confirm()
                            isInjectingExif = true
                            injectionStatusMessage = nil

                            var cumulativeShift = 0
                            let pairs: [(LoggedFrame, ImportedLabScan)] = activeRollFrames.enumerated().compactMap { idx, frame in
                                cumulativeShift += (cascadeShiftAtFrame[idx] ?? 0)
                                let scanIdx = idx + cumulativeShift
                                guard orderedScans.indices.contains(scanIdx) else { return nil }
                                return (frame, orderedScans[scanIdx])
                            }

                            DispatchQueue.global(qos: .userInitiated).async {
                                var count = 0
                                for (frame, scan) in pairs {
                                    if ExifAndXmpWriter.injectExifMetadataIntoScan(url: scan.url, frame: frame) {
                                        count += 1
                                    }
                                }
                                DispatchQueue.main.async {
                                    isInjectingExif = false
                                    MechanicalHaptics.heavy()
                                    injectionStatusMessage = "Wrote lossless EXIF into \(count) matched scan(s)"
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 15, weight: .bold))
                                Text(isInjectingExif ? "Writing Lossless EXIF…" : "Write EXIF to Matched Scans")
                                    .font(AppTypography.label(13, weight: .bold))
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Palette.good, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    if let status = injectionStatusMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Palette.good)
                            Text(status)
                                .font(AppTypography.label(12, weight: .bold))
                                .foregroundStyle(Palette.good)
                            Spacer()
                            if !orderedScans.isEmpty {
                                Button("Share Scans") {
                                    onShareItems(orderedScans.map(\.url))
                                }
                                .font(AppTypography.label(11, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Palette.good, in: Capsule())
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(10)
                        .background(Palette.good.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

                // Matched Frame Rows
                if activeRollFrames.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .padding(12)
                            .background(Palette.accent.opacity(0.14), in: Circle())

                        Text("No Logged Frames Yet")
                            .font(AppTypography.label(15, weight: .bold))
                            .foregroundStyle(Palette.text)

                        Text("Hold a meter reading on the main viewfinder and tap 'Log Frame' to build your roll reference strip.")
                            .font(AppTypography.label(12, weight: .medium))
                            .foregroundStyle(Palette.textSub)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
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
                    let cumulativeOffsets: [Int] = {
                        var running = 0
                        return activeRollFrames.indices.map { i in
                            running += (cascadeShiftAtFrame[i] ?? 0)
                            return running
                        }
                    }()

                    ForEach(Array(activeRollFrames.enumerated()), id: \.element.id) { idx, frame in
                        let offset = cumulativeOffsets[idx]
                        let targetScanIdx = idx + offset
                        let matchedScan = orderedScans.indices.contains(targetScanIdx) ? orderedScans[targetScanIdx] : nil
                        let localShift = cascadeShiftAtFrame[idx] ?? 0

                        ScanMatcherRowCard(
                            frame: frame,
                            targetScanIndex: targetScanIdx,
                            localShift: localShift,
                            hasImportedScans: !orderedScans.isEmpty,
                            matchedScan: matchedScan,
                            referenceImage: store.loadSnapshotImage(frame.snapshotFileName),
                            onImportTap: {
                                MechanicalHaptics.click()
                                showPhotoFilesImporter = true
                            },
                            onShiftChange: { delta in
                                MechanicalHaptics.tick()
                                let current = cascadeShiftAtFrame[idx] ?? 0
                                cascadeShiftAtFrame[idx] = current + delta
                            }
                        )
                    }
                }
            }
            .padding(.bottom, 28)
        }
        .fileImporter(
            isPresented: $showFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let folderURL = urls.first {
                loadScansFromFolder(folderURL)
            }
        }
        .fileImporter(
            isPresented: $showPhotoFilesImporter,
            allowedContentTypes: [.image, .rawImage, .jpeg, .tiff],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result, !urls.isEmpty {
                loadScansFromFileURLs(urls)
            }
        }
    }

    private func loadScansFromFolder(_ folderURL: URL) {
        isLoadingScans = true
        injectionStatusMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let accessed = folderURL.startAccessingSecurityScopedResource()
            defer {
                if accessed { folderURL.stopAccessingSecurityScopedResource() }
            }
            let exts: Set<String> = ["jpg", "jpeg", "dng", "tif", "tiff", "heic", "webp", "png"]
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            let imageURLs = contents
                .filter { exts.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

            let loaded = imageURLs.map { url in
                ImportedLabScan(
                    url: url,
                    displayName: url.lastPathComponent,
                    thumbnail: decodeThumbnail(at: url)
                )
            }

            DispatchQueue.main.async {
                cascadeShiftAtFrame.removeAll()
                importedScans = loaded
                isLoadingScans = false
                MechanicalHaptics.confirm()
            }
        }
    }

    private func loadScansFromFileURLs(_ urls: [URL]) {
        isLoadingScans = true
        injectionStatusMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let sorted = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            let loaded = sorted.map { url -> ImportedLabScan in
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                return ImportedLabScan(
                    url: url,
                    displayName: url.lastPathComponent,
                    thumbnail: decodeThumbnail(at: url)
                )
            }
            DispatchQueue.main.async {
                cascadeShiftAtFrame.removeAll()
                importedScans = loaded
                isLoadingScans = false
                MechanicalHaptics.confirm()
            }
        }
    }

    private func decodeThumbnail(at url: URL) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 320
        ]
        guard let cgImg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImg)
    }
}

// MARK: - Scan Matcher Row Card

private struct ScanMatcherRowCard: View {
    let frame: LoggedFrame
    let targetScanIndex: Int
    let localShift: Int
    let hasImportedScans: Bool
    let matchedScan: ImportedLabScan?
    let referenceImage: UIImage?
    let onImportTap: () -> Void
    let onShiftChange: (Int) -> Void

    var body: some View {
        let cleanAperture = frame.aperture.lowercased().hasPrefix("f/") ? frame.aperture : "f/\(frame.aperture)"
        let isMatched = matchedScan != nil

        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(String(format: "#%02d", frame.frameNumber))
                    .font(AppTypography.mono(12, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(frame.shutterSpeed)  ·  \(cleanAperture)  ·  ISO \(frame.iso)")
                        .font(AppTypography.mono(12, weight: .bold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)

                    if !frame.cameraName.isEmpty || !frame.lensName.isEmpty {
                        Text([frame.cameraName, frame.lensName].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(AppTypography.label(10, weight: .medium))
                            .foregroundStyle(Palette.textSub)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Anchor & Cascade Shift Controls (-1 / +1)
                HStack(spacing: 4) {
                    if localShift != 0 {
                        Text(localShift > 0 ? "+\(localShift)" : "\(localShift)")
                            .font(AppTypography.mono(10, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Palette.slow, in: Capsule())
                    }

                    Button {
                        onShiftChange(-1)
                    } label: {
                        Text("-1")
                            .font(AppTypography.mono(11, weight: .bold))
                            .foregroundStyle(Palette.text)
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onShiftChange(1)
                    } label: {
                        Text("+1")
                            .font(AppTypography.mono(11, weight: .bold))
                            .foregroundStyle(Palette.text)
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                // Left: Phone Reference Frame
                ZStack(alignment: .topLeading) {
                    if let refImg = referenceImage {
                        Image(uiImage: refImg)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 92)
                            .clipped()
                    } else {
                        VStack(spacing: 3) {
                            Text(String(format: "FRAME #%02d", frame.frameNumber))
                                .font(AppTypography.mono(11, weight: .bold))
                                .foregroundStyle(Palette.accent)
                            Text(String(format: "Zone %d · %.1f EV", frame.zone, frame.sceneEv))
                                .font(AppTypography.label(10, weight: .medium))
                                .foregroundStyle(Palette.textSub)
                        }
                        .frame(maxWidth: .infinity, minHeight: 92)
                    }

                    Image(systemName: "iphone")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .padding(6)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 92)
                .background(Color.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                // Center match indicator
                ZStack {
                    Circle()
                        .fill(isMatched ? Palette.good.opacity(0.22) : Color.white.opacity(0.06))
                        .frame(width: 28, height: 28)
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isMatched ? Palette.good : Palette.textDim)
                }

                // Right: Matched Lab Scan
                ZStack {
                    if let scan = matchedScan {
                        if let thumb = scan.thumbnail {
                            Image(uiImage: thumb)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 92)
                                .clipped()
                        }
                        VStack {
                            HStack {
                                Spacer()
                                Text(String(format: "SCAN #%02d", targetScanIndex + 1))
                                    .font(AppTypography.mono(9.5, weight: .bold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Palette.good, in: Capsule())
                                    .padding(6)
                            }
                            Spacer()
                            HStack {
                                Spacer()
                                Text(scan.displayName)
                                    .font(AppTypography.mono(9.5, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.70), in: Capsule())
                                    .padding(6)
                            }
                        }
                    } else if !hasImportedScans {
                        Button(action: onImportTap) {
                            VStack(spacing: 4) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Palette.accent)
                                Text("Import Scan #\(targetScanIndex + 1)")
                                    .font(AppTypography.label(11, weight: .bold))
                                    .foregroundStyle(Palette.accent)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(targetScanIndex < 0 ? "Skipped Frame" : "Unmatched (#\(targetScanIndex + 1))")
                            .font(AppTypography.label(11, weight: .medium))
                            .foregroundStyle(Palette.textDim)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 92)
                .background(Color.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(isMatched ? Palette.good.opacity(0.45) : Palette.border, lineWidth: 0.75)
                )
        )
    }
}
