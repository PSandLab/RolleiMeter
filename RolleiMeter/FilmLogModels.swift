import Foundation
import UIKit

// MARK: - Film ISO & EV Stops

let FILM_ISO_STOPS: [Int] = [
    25, 50, 64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 3200, 6400
]

let EV_COMP_STOPS: [Double] = [
    -3.0, -2.67, -2.33, -2.0, -1.67, -1.33, -1.0, -0.67, -0.33,
    0.0,
    0.33, 0.67, 1.0, 1.33, 1.67, 2.0, 2.33, 2.67, 3.0
]

let ROLL_LENGTH_OPTIONS: [Int] = [12, 16, 24, 36]

// MARK: - Film Stock Presets & Families

struct FilmStockPreset: Codable, Identifiable, Equatable, Hashable {
    var id: String { "\(name.lowercased())_\(iso)" }
    let name: String
    let iso: Int
    var category: String = "Color"
    var isCustom: Bool = false
}

struct FilmVariant: Identifiable, Equatable, Hashable {
    var id: String { "\(fullName)_\(iso)" }
    let label: String
    let fullName: String
    let iso: Int
}

struct FilmFamily: Identifiable, Equatable, Hashable {
    var id: String { "\(brand)_\(familyName)" }
    let brand: String
    let familyName: String
    let category: String
    let variants: [FilmVariant]
}

let BUILTIN_FILM_FAMILIES: [FilmFamily] = [
    // ── KODAK ──
    FilmFamily(
        brand: "Kodak",
        familyName: "Portra",
        category: "Color",
        variants: [
            FilmVariant(label: "160", fullName: "Kodak Portra 160", iso: 160),
            FilmVariant(label: "400", fullName: "Kodak Portra 400", iso: 400),
            FilmVariant(label: "800", fullName: "Kodak Portra 800", iso: 800)
        ]
    ),
    FilmFamily(
        brand: "Kodak",
        familyName: "Gold / UltraMax / ColorPlus",
        category: "Color",
        variants: [
            FilmVariant(label: "Gold 200", fullName: "Kodak Gold 200", iso: 200),
            FilmVariant(label: "UltraMax 400", fullName: "Kodak UltraMax 400", iso: 400),
            FilmVariant(label: "ColorPlus 200", fullName: "Kodak ColorPlus 200", iso: 200),
            FilmVariant(label: "ProImage 100", fullName: "Kodak ProImage 100", iso: 100),
            FilmVariant(label: "Ektar 100", fullName: "Kodak Ektar 100", iso: 100)
        ]
    ),
    FilmFamily(
        brand: "Kodak",
        familyName: "Tri-X / T-Max",
        category: "B&W",
        variants: [
            FilmVariant(label: "Tri-X 400", fullName: "Kodak Tri-X 400", iso: 400),
            FilmVariant(label: "T-Max 100", fullName: "Kodak T-Max 100", iso: 100),
            FilmVariant(label: "T-Max 400", fullName: "Kodak T-Max 400", iso: 400),
            FilmVariant(label: "T-Max P3200", fullName: "Kodak T-Max P3200", iso: 3200),
            FilmVariant(label: "Double-X 5222", fullName: "Kodak Double-X", iso: 250)
        ]
    ),
    FilmFamily(
        brand: "Kodak",
        familyName: "Ektachrome",
        category: "Slide",
        variants: [
            FilmVariant(label: "E100", fullName: "Kodak Ektachrome E100", iso: 100)
        ]
    ),

    // ── FUJIFILM ──
    FilmFamily(
        brand: "Fujifilm",
        familyName: "Superia / C200 / Pro 400H",
        category: "Color",
        variants: [
            FilmVariant(label: "200 / C200", fullName: "Fujifilm 200", iso: 200),
            FilmVariant(label: "400 / X-TRA", fullName: "Fujifilm Superia 400", iso: 400),
            FilmVariant(label: "Pro 400H", fullName: "Fujifilm Pro 400H", iso: 400),
            FilmVariant(label: "Natura 1600", fullName: "Fujifilm Natura 1600", iso: 1600)
        ]
    ),
    FilmFamily(
        brand: "Fujifilm",
        familyName: "Velvia / Provia",
        category: "Slide",
        variants: [
            FilmVariant(label: "Velvia 50", fullName: "Fujifilm Velvia 50", iso: 50),
            FilmVariant(label: "Velvia 100", fullName: "Fujifilm Velvia 100", iso: 100),
            FilmVariant(label: "Provia 100F", fullName: "Fujifilm Provia 100F", iso: 100)
        ]
    ),
    FilmFamily(
        brand: "Fujifilm",
        familyName: "Neopan Acros",
        category: "B&W",
        variants: [
            FilmVariant(label: "Acros II 100", fullName: "Fujifilm Acros II", iso: 100)
        ]
    ),

    // ── ILFORD ──
    FilmFamily(
        brand: "Ilford",
        familyName: "HP5 / FP4 / Pan F",
        category: "B&W",
        variants: [
            FilmVariant(label: "HP5 Plus 400", fullName: "Ilford HP5 Plus", iso: 400),
            FilmVariant(label: "FP4 Plus 125", fullName: "Ilford FP4 Plus", iso: 125),
            FilmVariant(label: "Pan F Plus 50", fullName: "Ilford Pan F Plus", iso: 50),
            FilmVariant(label: "XP2 Super 400", fullName: "Ilford XP2 Super", iso: 400),
            FilmVariant(label: "SFX 200", fullName: "Ilford SFX 200", iso: 200)
        ]
    ),
    FilmFamily(
        brand: "Ilford",
        familyName: "Delta Professional",
        category: "B&W",
        variants: [
            FilmVariant(label: "Delta 100", fullName: "Ilford Delta 100", iso: 100),
            FilmVariant(label: "Delta 400", fullName: "Ilford Delta 400", iso: 400),
            FilmVariant(label: "Delta 3200", fullName: "Ilford Delta 3200", iso: 3200)
        ]
    ),

    // ── CINESTILL ──
    FilmFamily(
        brand: "CineStill",
        familyName: "CineStill Color & B&W",
        category: "Color",
        variants: [
            FilmVariant(label: "800T", fullName: "CineStill 800T", iso: 800),
            FilmVariant(label: "400D", fullName: "CineStill 400D", iso: 400),
            FilmVariant(label: "50D", fullName: "CineStill 50D", iso: 50),
            FilmVariant(label: "BwXX 250", fullName: "CineStill BwXX", iso: 250)
        ]
    ),

    // ── FOMAPAN / KENTMERE / ROLLEI / LOMO ──
    FilmFamily(
        brand: "Foma · Kentmere · Rollei · Lomo",
        familyName: "Fomapan Classic",
        category: "B&W",
        variants: [
            FilmVariant(label: "Foma 100", fullName: "Fomapan 100", iso: 100),
            FilmVariant(label: "Foma 200", fullName: "Fomapan 200", iso: 200),
            FilmVariant(label: "Foma 400", fullName: "Fomapan 400", iso: 400)
        ]
    ),
    FilmFamily(
        brand: "Foma · Kentmere · Rollei · Lomo",
        familyName: "Kentmere / Agfa / Rollei",
        category: "B&W",
        variants: [
            FilmVariant(label: "Kentmere 100", fullName: "Kentmere Pan 100", iso: 100),
            FilmVariant(label: "Kentmere 400", fullName: "Kentmere Pan 400", iso: 400),
            FilmVariant(label: "Agfa APX 100", fullName: "AgfaPhoto APX 100", iso: 100),
            FilmVariant(label: "Agfa APX 400", fullName: "AgfaPhoto APX 400", iso: 400),
            FilmVariant(label: "Rollei RPX 25", fullName: "Rollei RPX 25", iso: 25),
            FilmVariant(label: "Rollei Retro 80S", fullName: "Rollei Retro 80S", iso: 80),
            FilmVariant(label: "Rollei IR 400", fullName: "Rollei Infrared 400", iso: 400)
        ]
    ),
    FilmFamily(
        brand: "Foma · Kentmere · Rollei · Lomo",
        familyName: "Lomography / Harman Phoenix",
        category: "Color",
        variants: [
            FilmVariant(label: "Phoenix 200", fullName: "Harman Phoenix 200", iso: 200),
            FilmVariant(label: "Lomo 100", fullName: "Lomography 100", iso: 100),
            FilmVariant(label: "Lomo 400", fullName: "Lomography 400", iso: 400),
            FilmVariant(label: "Lomo 800", fullName: "Lomography 800", iso: 800)
        ]
    )
]

let BUILTIN_FILM_STOCKS: [FilmStockPreset] = BUILTIN_FILM_FAMILIES.flatMap { family in
    family.variants.map { variant in
        FilmStockPreset(
            name: variant.fullName,
            iso: variant.iso,
            category: family.category,
            isCustom: false
        )
    }
}

// MARK: - Film Roll State

struct FilmRollState: Codable, Equatable {
    var rollNumber: Int = 1
    var filmName: String = "Kodak Portra 400"
    var boxIso: Int = 400
    var category: String = "Color"
    var currentFrame: Int = 1
    var maxFrames: Int = 36
    var isExpired: Bool = false
    var expiredYear: Int = 2005
    var autoApplyExpiredComp: Bool = true

    var isUnloaded: Bool { filmName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isBonusFrames: Bool { !isUnloaded && currentFrame > maxFrames }
    var isRollComplete: Bool { !isUnloaded && currentFrame >= maxFrames }
    var isSlideFilm: Bool { !isUnloaded && category.caseInsensitiveCompare("Slide") == .orderedSame }

    var decadesExpired: Double {
        guard !isUnloaded && isExpired else { return 0.0 }
        let currentYear = Calendar.current.component(.year, from: Date())
        let years = max(0, currentYear - expiredYear)
        return Double(years) / 10.0
    }

    var recommendedExpiredCompEv: Double {
        guard !isUnloaded && isExpired && !isSlideFilm else { return 0.0 }
        let rawStops = decadesExpired
        return (rawStops * 3.0).rounded() / 3.0
    }

    var activeExpiredCompEv: Double {
        (!isUnloaded && isExpired && autoApplyExpiredComp && !isSlideFilm) ? recommendedExpiredCompEv : 0.0
    }
}

// MARK: - Captured Moment & Logged Frame

struct CapturedMoment: Equatable {
    let rollNumber: Int
    let frameNumber: Int
    let rollMaxFrames: Int
    let filmName: String
    let isExpiredFilm: Bool
    let expiredYear: Int
    let timestampIso: String
    let timestampUtc: String
    let timezoneId: String
    let shutterSpeed: String
    let aperture: String
    let iso: Int
    let sceneEv: Double
    let compensatedEv: Double
    let zone: Int
    let meterMode: String
    let isAutoExposure: Bool
    let manualEvComp: Double
    let expiredEvComp: Double
    let totalEvComp: Double
    let latitude: Double?
    let longitude: Double?
    let snapshotImage: UIImage?
    var cameraName: String = ""
    var lensName: String = ""
}

struct LoggedFrame: Codable, Identifiable, Equatable {
    let id: Int64
    let rollNumber: Int
    let frameNumber: Int
    var rollMaxFrames: Int = 36
    let filmName: String
    var isExpiredFilm: Bool = false
    var expiredYear: Int = 0
    let timestampIso: String
    let timestampUtc: String
    let timezoneId: String
    let shutterSpeed: String
    let aperture: String
    let iso: Int
    let sceneEv: Double
    let compensatedEv: Double
    let zone: Int
    let meterMode: String
    let isAutoExposure: Bool
    let manualEvComp: Double
    let expiredEvComp: Double
    let totalEvComp: Double
    let latitude: Double?
    let longitude: Double?
    let snapshotFileName: String?
    var note: String = ""
    var cameraName: String = ""
    var lensName: String = ""
}

// MARK: - Film Formatters

func formatEvComp(_ ev: Double) -> String {
    if abs(ev) < 0.05 { return "0 EV" }
    let sign = ev > 0 ? "+" : ""
    return String(format: "%@%.1f EV", sign, ev)
}

func formatFilmDisplay(name: String, iso: Int) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "LOAD FILM" }
    let isoStr = "\(iso)"
    let pattern = "\\b\(NSRegularExpression.escapedPattern(for: isoStr))[A-Za-z]*\\b"
    if trimmed.range(of: pattern, options: .regularExpression) != nil {
        return trimmed
    }
    return "\(trimmed) \(iso)"
}

func shortFilmBadge(name: String, iso: Int) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "LOAD FILM" }
    let stripped = trimmed
        .replacingOccurrences(of: #"\b(Kodak|Fujifilm|Fuji|Ilford|Fomapan|Kentmere|AgfaPhoto|Rollei|Lomography|Harman)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        .trimmingCharacters(in: .whitespaces)
    let base = stripped.isEmpty ? trimmed : stripped
    let isoStr = "\(iso)"
    let pattern = "\\b\(NSRegularExpression.escapedPattern(for: isoStr))[A-Za-z]*\\b"
    if base.range(of: pattern, options: .regularExpression) != nil {
        return base
    }
    return "\(base) \(iso)"
}

func abbreviateShutterForBadge(_ shutter: String) -> String {
    let s = shutter.trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("1/") {
        let denom = String(s.dropFirst(2))
        if denom == "1000" { return "1k" }
        if denom == "2000" { return "2k" }
        if denom == "4000" { return "4k" }
        if denom == "8000" { return "8k" }
        return denom
    }
    return s
}

func abbreviateApertureForBadge(_ aperture: String) -> String {
    let a = aperture.trimmingCharacters(in: .whitespaces)
    let stripped: String
    if a.lowercased().hasPrefix("f/") {
        stripped = String(a.dropFirst(2))
    } else if a.lowercased().hasPrefix("f") {
        stripped = String(a.dropFirst(1))
    } else {
        stripped = a
    }
    let clean = stripped.hasSuffix(".0") ? String(stripped.dropLast(2)) : stripped
    return "f\(clean)"
}

func formatIsoTimestampForDisplay(_ isoString: String) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = formatter.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString)
    guard let date else {
        return String(isoString.replacingOccurrences(of: "T", with: " ").prefix(16))
    }
    let out = DateFormatter()
    out.locale = Locale(identifier: "en_US_POSIX")
    out.dateFormat = "MMM d · HH:mm"
    return out.string(from: date)
}

func formatGpsCoordinates(lat: Double?, lon: Double?) -> String? {
    guard let lat, let lon else { return nil }
    let latDir = lat >= 0 ? "N" : "S"
    let lonDir = lon >= 0 ? "E" : "W"
    return String(format: "%.4f°%@ %.4f°%@", abs(lat), latDir, abs(lon), lonDir)
}
