import Foundation
import ImageIO
import UniformTypeIdentifiers
import UIKit
import SwiftUI

enum ExifAndXmpWriter {

    // MARK: - Build CGImageProperties Dictionary

    static func buildExifProperties(from existing: [String: Any]?, frame: LoggedFrame) -> [String: Any] {
        var props = existing ?? [:]

        var tiff = (props[kCGImagePropertyTIFFDictionary as String] as? [String: Any]) ?? [:]
        var exif = (props[kCGImagePropertyExifDictionary as String] as? [String: Any]) ?? [:]
        var gps = (props[kCGImagePropertyGPSDictionary as String] as? [String: Any]) ?? [:]

        // 1. Camera & Lens Make/Model
        let camName = frame.cameraName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Analog Film Camera"
            : frame.cameraName
        let make = camName.components(separatedBy: " ").first ?? camName
        tiff[kCGImagePropertyTIFFMake as String] = make
        tiff[kCGImagePropertyTIFFModel as String] = camName
        tiff[kCGImagePropertyTIFFSoftware as String] = "RolleiMeter iOS"

        let lensName = frame.lensName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !lensName.isEmpty {
            exif[kCGImagePropertyExifLensModel as String] = lensName
        }

        // 2. Optical Focal Length
        if let focalMm = extractFocalLengthMm(lensName), focalMm > 0 {
            exif[kCGImagePropertyExifFocalLength as String] = focalMm
            exif[kCGImagePropertyExifFocalLenIn35mmFilm as String] = Int(focalMm.rounded())
        }

        // 3. Shutter Speed (ExposureTime in seconds)
        if let expSec = parseShutterSpeedSeconds(frame.shutterSpeed), expSec > 0 {
            exif[kCGImagePropertyExifExposureTime as String] = expSec
        }

        // 4. Aperture (FNumber)
        let fClean = frame.aperture.replacingOccurrences(of: "f/", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        if let fNum = Double(fClean), fNum > 0 {
            exif[kCGImagePropertyExifFNumber as String] = fNum
        }

        // 5. Film ISO & EV Bias
        exif[kCGImagePropertyExifISOSpeedRatings as String] = [frame.iso]
        exif[kCGImagePropertyExifExposureBiasValue as String] = frame.totalEvComp

        // 6. Original Capture Timestamp
        if let exifDate = convertIsoToExifDateTime(frame.timestampIso) {
            exif[kCGImagePropertyExifDateTimeOriginal as String] = exifDate
            exif[kCGImagePropertyExifDateTimeDigitized as String] = exifDate
            tiff[kCGImagePropertyTIFFDateTime as String] = exifDate
        }

        // 7. Film Stock, Roll #, Frame #, Camera/Lens & Notes
        var desc = String(format: "Roll #%02d Frame #%02d · %@ (ISO %d)", frame.rollNumber, frame.frameNumber, frame.filmName, frame.iso)
        if !camName.isEmpty { desc += " · \(camName)" }
        if !lensName.isEmpty { desc += " + \(lensName)" }
        if !frame.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            desc += " · Note: \(frame.note)"
        }
        tiff[kCGImagePropertyTIFFImageDescription as String] = desc
        exif[kCGImagePropertyExifUserComment as String] = desc

        // 8. GPS Coordinates
        if let lat = frame.latitude, let lon = frame.longitude {
            gps[kCGImagePropertyGPSLatitude as String] = abs(lat)
            gps[kCGImagePropertyGPSLatitudeRef as String] = lat >= 0 ? "N" : "S"
            gps[kCGImagePropertyGPSLongitude as String] = abs(lon)
            gps[kCGImagePropertyGPSLongitudeRef as String] = lon >= 0 ? "E" : "W"
            props[kCGImagePropertyGPSDictionary as String] = gps
        }

        props[kCGImagePropertyTIFFDictionary as String] = tiff
        props[kCGImagePropertyExifDictionary as String] = exif
        return props
    }

    // MARK: - Write EXIF to File / Lab Scan

    @discardableResult
    static func writeExifMetadataToFile(url: URL, frame: LoggedFrame) -> Bool {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let uti = CGImageSourceGetType(src) else {
            return false
        }

        let existingProps = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]
        let updatedProps = buildExifProperties(from: existingProps, frame: frame)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("exif_\(UUID().uuidString).\(url.pathExtension.isEmpty ? "jpg" : url.pathExtension)")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let dest = CGImageDestinationCreateWithURL(tempURL as CFURL, uti, 1, nil) else {
            return false
        }

        // First try lossless copy of image source with updated metadata
        var copyOptions = updatedProps
        copyOptions[kCGImageDestinationMergeMetadata as String] = true
        var error: Unmanaged<CFError>?
        let copiedLossless = CGImageDestinationCopyImageSource(dest, src, copyOptions as CFDictionary, &error)

        if !copiedLossless {
            // Fallback: re-add image at index 0 with 0.98 quality
            guard let fallbackDest = CGImageDestinationCreateWithURL(tempURL as CFURL, uti, 1, nil) else {
                return false
            }
            var addProps = updatedProps
            addProps[kCGImageDestinationLossyCompressionQuality as String] = 0.98
            CGImageDestinationAddImageFromSource(fallbackDest, src, 0, addProps as CFDictionary)
            guard CGImageDestinationFinalize(fallbackDest) else {
                return false
            }
        }

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: url)
            }
            return true
        } catch {
            // If replaceItemAt fails on external security-scoped volume, write data directly
            if let data = try? Data(contentsOf: tempURL) {
                return (try? data.write(to: url, options: .atomic)) != nil
            }
            return false
        }
    }

    static func injectExifMetadataIntoScan(url: URL, frame: LoggedFrame) -> Bool {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        return writeExifMetadataToFile(url: url, frame: frame)
    }

    // MARK: - Parsers

    static func parseShutterSpeedSeconds(_ shutterText: String) -> Double? {
        let clean = shutterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.hasSuffix("s") {
            return Double(clean.dropLast())
        }
        if clean.hasPrefix("1/") {
            guard let denom = Double(clean.dropFirst(2)), denom > 0 else { return nil }
            return 1.0 / denom
        }
        guard let val = Double(clean) else { return nil }
        return val >= 4.0 ? (1.0 / val) : val
    }

    static func convertIsoToExifDateTime(_ isoString: String) -> String? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString)
        guard let date else { return nil }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return out.string(from: date)
    }

    // MARK: - XMP Sidecar Export

    static func generateRollXmpSidecars(_ frames: [LoggedFrame]) -> String {
        var lines: [String] = []
        lines.append("<?xpacket begin=\"\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>")
        lines.append("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\">")
        lines.append(" <rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">")
        for f in frames {
            let fl = extractFocalLengthMm(f.lensName)
            let flAttr: String
            if let fl, fl > 0 {
                let rounded = Int(fl.rounded())
                flAttr = " exif:FocalLength=\"\(rounded)/1\" exif:FocalLengthIn35mmFilm=\"\(rounded)\""
            } else {
                flAttr = ""
            }
            let fClean = f.aperture.replacingOccurrences(of: "f/", with: "", options: .caseInsensitive)
            let fNumAttr = Double(fClean) != nil ? " exif:FNumber=\"\(fClean)\"" : " exif:FNumber=\"\(f.aperture)\""
            let camAttr = f.cameraName.isEmpty ? "" : " tiff:Model=\"\(xmlEscape(f.cameraName))\""
            let lensAttr = f.lensName.isEmpty ? "" : " aux:Lens=\"\(xmlEscape(f.lensName))\""
            let desc = xmlEscape("\(f.filmName) Roll #\(f.rollNumber) Frame #\(f.frameNumber) \(f.note)".trimmingCharacters(in: .whitespaces))
            lines.append(
                "  <rdf:Description rdf:about=\"Roll\(f.rollNumber)_Frame\(f.frameNumber)\"" +
                camAttr + lensAttr + flAttr +
                " exif:ISOSpeedRatings=\"\(f.iso)\"" +
                fNumAttr +
                " exif:ExposureTime=\"\(xmlEscape(f.shutterSpeed))\"" +
                " dc:description=\"\(desc)\"/>"
            )
        }
        lines.append(" </rdf:RDF>")
        lines.append("</x:xmpmeta>")
        lines.append("<?xpacket end=\"w\"?>")
        return lines.joined(separator: "\n")
    }

    static func createXmpSidecarsFileURL(_ frames: [LoggedFrame]) -> URL? {
        guard !frames.isEmpty else { return nil }
        let content = generateRollXmpSidecars(frames)
        let rollNum = frames.first?.rollNumber ?? 1
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(String(format: "roll_%02d_sidecars.xmp", rollNum))
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - CSV & Plain-Text Summary Export

    static func generateRollCsv(_ frames: [LoggedFrame]) -> String {
        var lines: [String] = []
        lines.append("Roll,Frame,Film Stock,Expired,Expired Year,Camera,Lens,ISO,Shutter Speed,Aperture,Scene EV,Compensated EV,Zone,Meter Mode,Exposure Program,Manual EV Comp,Expired EV Comp,Total EV Comp,Timestamp ISO,Timestamp UTC,Timezone,Latitude,Longitude,Snapshot File,Notes")
        let sorted = frames.sorted { ($0.rollNumber, $0.frameNumber) < ($1.rollNumber, $1.frameNumber) }
        for f in sorted {
            let row: [String] = [
                "\(f.rollNumber)",
                "\(f.frameNumber)",
                csvEscape(f.filmName),
                f.isExpiredFilm ? "Yes" : "No",
                f.isExpiredFilm ? "\(f.expiredYear)" : "",
                csvEscape(f.cameraName),
                csvEscape(f.lensName),
                "\(f.iso)",
                csvEscape(f.shutterSpeed),
                csvEscape(f.aperture),
                String(format: "%.2f", f.sceneEv),
                String(format: "%.2f", f.compensatedEv),
                "\(f.zone)",
                csvEscape(f.meterMode),
                f.isAutoExposure ? "AUTO" : "MANUAL",
                String(format: "%.2f", f.manualEvComp),
                String(format: "%.2f", f.expiredEvComp),
                String(format: "%.2f", f.totalEvComp),
                csvEscape(f.timestampIso),
                csvEscape(f.timestampUtc),
                csvEscape(f.timezoneId),
                f.latitude.map { String(format: "%.6f", $0) } ?? "",
                f.longitude.map { String(format: "%.6f", $0) } ?? "",
                csvEscape(f.snapshotFileName ?? ""),
                csvEscape(f.note)
            ]
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    static func createRollCsvFileURL(_ frames: [LoggedFrame]) -> URL? {
        guard !frames.isEmpty else { return nil }
        let csv = generateRollCsv(frames)
        let rollNum = frames.first?.rollNumber ?? 1
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(String(format: "film_roll_%02d_log.csv", rollNum))
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func generateRollTextSummary(_ frames: [LoggedFrame]) -> String {
        guard let first = frames.first else { return "" }
        let sorted = frames.sorted { $0.frameNumber < $1.frameNumber }
        var lines: [String] = []
        lines.append("🎞️ ROLLEI METER — FILM ROLL LOGBOOK")
        lines.append(String(format: "Roll #%02d · %@ (ISO %d)", first.rollNumber, first.filmName, first.iso))
        if first.isExpiredFilm {
            lines.append("Expired Stock: \(first.expiredYear)")
        }
        if !first.cameraName.isEmpty || !first.lensName.isEmpty {
            let gearLine = [first.cameraName, first.lensName].filter { !$0.isEmpty }.joined(separator: " + ")
            lines.append("Gear: \(gearLine)")
        }
        lines.append("Total Logged Exposures: \(sorted.count)")
        lines.append("────────────────────────────────────────")
        for f in sorted {
            var line = String(format: "#%02d  |  %@  %@  |  Zone %d (%.1f EV)", f.frameNumber, f.shutterSpeed, f.aperture, f.zone, f.compensatedEv)
            if abs(f.totalEvComp) >= 0.05 {
                line += " [\(formatEvComp(f.totalEvComp))]"
            }
            line += "  |  \(formatIsoTimestampForDisplay(f.timestampIso))"
            if let gps = formatGpsCoordinates(lat: f.latitude, lon: f.longitude) {
                line += "  |  📍 \(gps)"
            }
            if !f.note.isEmpty {
                line += "\n     📝 \(f.note)"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - SwiftUI ShareSheet Helper

struct ShareSheetItem: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
