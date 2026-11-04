import Foundation
import SwiftUI

// MARK: - Camera & Lens Specifications

struct CameraGearSpec: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let brand: String
    let model: String
    let isFixed: Bool
    let mount: String
    let minShutter: Double
    let maxShutter: Double
    var fixedLensName: String = ""
    var fixedMinAperture: Double = 0.0
    var fixedMaxAperture: Double = 0.0
    var fixedApertureStops: [Double] = []
    var isCustom: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, brand, model, mount
        case isFixed = "is_fixed"
        case minShutter = "min_shutter"
        case maxShutter = "max_shutter"
        case fixedLensName = "fixed_lens_name"
        case fixedMinAperture = "fixed_min_aperture"
        case fixedMaxAperture = "fixed_max_aperture"
        case fixedApertureStops = "fixed_aperture_stops"
        case isCustom = "is_custom"
    }

    init(
        id: String,
        brand: String,
        model: String,
        isFixed: Bool,
        mount: String,
        minShutter: Double,
        maxShutter: Double,
        fixedLensName: String = "",
        fixedMinAperture: Double = 0.0,
        fixedMaxAperture: Double = 0.0,
        fixedApertureStops: [Double] = [],
        isCustom: Bool = false
    ) {
        self.id = id
        self.brand = brand
        self.model = model
        self.isFixed = isFixed
        self.mount = mount
        self.minShutter = minShutter
        self.maxShutter = maxShutter
        self.fixedLensName = fixedLensName
        self.fixedMinAperture = fixedMinAperture
        self.fixedMaxAperture = fixedMaxAperture
        self.fixedApertureStops = fixedApertureStops
        self.isCustom = isCustom
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        brand = try c.decode(String.self, forKey: .brand)
        model = try c.decode(String.self, forKey: .model)
        isFixed = try c.decodeIfPresent(Bool.self, forKey: .isFixed) ?? false
        mount = try c.decodeIfPresent(String.self, forKey: .mount) ?? "Fixed"
        minShutter = try c.decodeIfPresent(Double.self, forKey: .minShutter) ?? 1.0
        maxShutter = try c.decodeIfPresent(Double.self, forKey: .maxShutter) ?? 0.001
        fixedLensName = try c.decodeIfPresent(String.self, forKey: .fixedLensName) ?? ""
        fixedMinAperture = try c.decodeIfPresent(Double.self, forKey: .fixedMinAperture) ?? 0.0
        fixedMaxAperture = try c.decodeIfPresent(Double.self, forKey: .fixedMaxAperture) ?? 0.0
        fixedApertureStops = try c.decodeIfPresent([Double].self, forKey: .fixedApertureStops) ?? []
        isCustom = try c.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
    }
}

struct LensGearSpec: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let brand: String
    let model: String
    let mount: String
    let minAperture: Double
    let maxAperture: Double
    var apertureStops: [Double] = []
    var isCustom: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, brand, model, mount
        case minAperture = "min_aperture"
        case maxAperture = "max_aperture"
        case apertureStops = "aperture_stops"
        case isCustom = "is_custom"
    }

    init(
        id: String,
        brand: String,
        model: String,
        mount: String,
        minAperture: Double,
        maxAperture: Double,
        apertureStops: [Double] = [],
        isCustom: Bool = false
    ) {
        self.id = id
        self.brand = brand
        self.model = model
        self.mount = mount
        self.minAperture = minAperture
        self.maxAperture = maxAperture
        self.apertureStops = apertureStops
        self.isCustom = isCustom
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        brand = try c.decode(String.self, forKey: .brand)
        model = try c.decode(String.self, forKey: .model)
        mount = try c.decodeIfPresent(String.self, forKey: .mount) ?? ""
        minAperture = try c.decodeIfPresent(Double.self, forKey: .minAperture) ?? 2.8
        maxAperture = try c.decodeIfPresent(Double.self, forKey: .maxAperture) ?? 16.0
        apertureStops = try c.decodeIfPresent([Double].self, forKey: .apertureStops) ?? []
        isCustom = try c.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
    }
}

struct ActiveGearProfile: Codable, Equatable {
    var cameraId: String = "rollei_35_s"
    var cameraName: String = "Rollei 35 S / 35 SE"
    var mount: String = "Fixed"
    var isFixedLens: Bool = true
    var minShutter: Double = 0.5
    var maxShutter: Double = 1.0 / 500.0
    var lensId: String = "rollei_35_s_fixed"
    var lensName: String = "Rollei-HFT Sonnar 40mm f/2.8"
    var minAperture: Double = 2.8
    var maxAperture: Double = 22.0
    var apertureStops: [Double] = [2.8, 4.0, 5.6, 8.0, 11.0, 16.0, 22.0]

    var hasCamera: Bool { !cameraName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasLens: Bool { !lensName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    enum CodingKeys: String, CodingKey {
        case cameraId, cameraName, mount, isFixedLens, minShutter, maxShutter
        case lensId, lensName, minAperture, maxAperture, apertureStops
    }

    init(
        cameraId: String = "rollei_35_s",
        cameraName: String = "Rollei 35 S / 35 SE",
        mount: String = "Fixed",
        isFixedLens: Bool = true,
        minShutter: Double = 0.5,
        maxShutter: Double = 1.0 / 500.0,
        lensId: String = "rollei_35_s_fixed",
        lensName: String = "Rollei-HFT Sonnar 40mm f/2.8",
        minAperture: Double = 2.8,
        maxAperture: Double = 22.0,
        apertureStops: [Double] = [2.8, 4.0, 5.6, 8.0, 11.0, 16.0, 22.0]
    ) {
        self.cameraId = cameraId
        self.cameraName = cameraName
        self.mount = mount
        self.isFixedLens = isFixedLens
        self.minShutter = minShutter
        self.maxShutter = maxShutter
        self.lensId = lensId
        self.lensName = lensName
        self.minAperture = minAperture
        self.maxAperture = maxAperture
        self.apertureStops = apertureStops
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cameraId = try c.decodeIfPresent(String.self, forKey: .cameraId) ?? "rollei_35_s"
        cameraName = try c.decodeIfPresent(String.self, forKey: .cameraName) ?? "Rollei 35 S / 35 SE"
        mount = try c.decodeIfPresent(String.self, forKey: .mount) ?? "Fixed"
        isFixedLens = try c.decodeIfPresent(Bool.self, forKey: .isFixedLens) ?? true
        minShutter = try c.decodeIfPresent(Double.self, forKey: .minShutter) ?? 0.5
        maxShutter = try c.decodeIfPresent(Double.self, forKey: .maxShutter) ?? (1.0 / 500.0)
        lensId = try c.decodeIfPresent(String.self, forKey: .lensId) ?? "rollei_35_s_fixed"
        lensName = try c.decodeIfPresent(String.self, forKey: .lensName) ?? "Rollei-HFT Sonnar 40mm f/2.8"
        minAperture = try c.decodeIfPresent(Double.self, forKey: .minAperture) ?? 2.8
        maxAperture = try c.decodeIfPresent(Double.self, forKey: .maxAperture) ?? 22.0
        apertureStops = try c.decodeIfPresent([Double].self, forKey: .apertureStops) ?? []
    }

    static let unloaded = ActiveGearProfile(
        cameraId: "",
        cameraName: "",
        mount: "",
        isFixedLens: false,
        minShutter: 30.0,
        maxShutter: 1.0 / 8000.0,
        lensId: "",
        lensName: "",
        minAperture: 0.95,
        maxAperture: 64.0,
        apertureStops: []
    )
}

// MARK: - Analog Stops & Gear Clamping

let ALL_ANALOG_SHUTTER_STOPS: [Double] = [
    30.0, 15.0, 8.0, 4.0, 2.0, 1.0,
    1.0 / 2.0, 1.0 / 4.0, 1.0 / 8.0, 1.0 / 15.0, 1.0 / 30.0,
    1.0 / 60.0, 1.0 / 125.0, 1.0 / 250.0, 1.0 / 500.0,
    1.0 / 1000.0, 1.0 / 2000.0, 1.0 / 4000.0, 1.0 / 8000.0
]

let ALL_ANALOG_APERTURE_STOPS: [Double] = [
    0.95, 1.0, 1.2, 1.4, 1.7, 1.8, 2.0, 2.4, 2.8, 3.2, 3.5,
    4.0, 4.5, 5.6, 6.7, 8.0, 9.5, 11.0, 13.0, 16.0, 22.0, 32.0, 45.0, 64.0
]

let FULL_APERTURE_STOPS: [Double] = [
    1.0, 1.4, 2.0, 2.8, 4.0, 5.6, 8.0, 11.0, 16.0, 22.0, 32.0, 45.0, 64.0
]

/// Returns the valid shutter speeds (sorted fast -> slow to match the RolleiMeter dial) for the active gear.
func clampShutterStopsForGear(_ gear: ActiveGearProfile) -> [(label: String, t: Double)] {
    guard gear.hasCamera else {
        return Rollei.speeds
    }
    let lo = min(gear.minShutter, gear.maxShutter) * 0.90
    let hi = max(gear.minShutter, gear.maxShutter) * 1.10
    let filtered = ALL_ANALOG_SHUTTER_STOPS.filter { $0 >= lo && $0 <= hi }
    guard !filtered.isEmpty else { return Rollei.speeds }
    let sortedFastFirst = filtered.sorted() // smallest seconds (fastest) first
    return sortedFastFirst.map { sec in
        let label: String
        if sec >= 1.0 {
            label = "\(Int(sec.rounded()))\""
        } else {
            label = "\(Int((1.0 / sec).rounded()))"
        }
        return (label: label, t: sec)
    }
}

/// Formats a sorted array of f-numbers into dial stop tuples.
private func formatApertureStopTuples(_ stops: [Double]) -> [(label: String, n: Double)] {
    var deduped: [Double] = []
    for f in stops.sorted() where f > 0 {
        if let last = deduped.last, abs(last - f) < 0.04 {
            continue
        }
        deduped.append(f)
    }
    guard !deduped.isEmpty else { return Rollei.stops }
    return deduped.map { f in
        let label: String
        if f.truncatingRemainder(dividingBy: 1.0) == 0.0 {
            label = String(format: "%.0f", f)
        } else if (f * 10).truncatingRemainder(dividingBy: 1.0) == 0.0 {
            label = String(format: "%.1f", f)
        } else {
            label = String(format: "%.2f", f)
        }
        return (label: label, n: f)
    }
}

/// Generates realistic physical aperture ring stops from a (minAperture, maxAperture) range
/// when explicit stops are not provided (e.g. user-added custom gear or generic adapter).
func defaultApertureStopsForRange(minAperture: Double, maxAperture: Double) -> [Double] {
    let minF = min(minAperture, maxAperture)
    let maxF = max(minAperture, maxAperture)
    guard minF > 0, maxF > 0 else { return FULL_APERTURE_STOPS }

    var stops = FULL_APERTURE_STOPS.filter { $0 >= minF - 0.05 && $0 <= maxF + 0.05 }

    // If the wide-open aperture is a fractional stop (e.g. f/0.95, f/1.7, f/1.8, f/1.9),
    // physical aperture rings omit a standard full stop that sits within ~0.28 EV of wide-open
    // (for example f/1.7 and f/1.8 step directly to f/2.8, and f/0.95 steps directly to f/1.4).
    if !stops.contains(where: { abs($0 - minF) < 0.08 }) {
        stops.removeAll { candidate in
            let evGap = abs(2.0 * log2(candidate / minF))
            return evGap < 0.28
        }
        stops.insert(minF, at: 0)
    }
    if !stops.contains(where: { abs($0 - maxF) < 0.08 }) {
        stops.append(maxF)
    }
    return stops.sorted()
}

/// Returns the valid aperture stops (sorted wide -> narrow) for the active gear.
func clampApertureStopsForGear(_ gear: ActiveGearProfile) -> [(label: String, n: Double)] {
    guard gear.hasLens else {
        return Rollei.stops
    }
    if let explicitStops = GearCatalogCache.resolveApertureStops(for: gear), !explicitStops.isEmpty {
        return formatApertureStopTuples(explicitStops)
    }
    let stops = defaultApertureStopsForRange(minAperture: gear.minAperture, maxAperture: gear.maxAperture)
    return formatApertureStopTuples(stops)
}

func formatShutterStopLabel(_ seconds: Double) -> String {
    if seconds >= 1.0 {
        return "\(Int(seconds.rounded()))s"
    }
    let denom = Int((1.0 / seconds).rounded())
    return "1/\(denom)"
}

func formatApertureStopLabel(_ f: Double) -> String {
    if f.truncatingRemainder(dividingBy: 1.0) == 0.0 {
        return String(format: "f/%.0f", f)
    } else if (f * 10).truncatingRemainder(dividingBy: 1.0) == 0.0 {
        return String(format: "f/%.1f", f)
    } else {
        return String(format: "f/%.2f", f)
    }
}

func formatApertureRange(_ minF: Double, _ maxF: Double) -> String {
    "\(formatApertureStopLabel(minF))–\(formatApertureStopLabel(maxF))"
}

func formatMountBadge(_ mount: String) -> String {
    let m = mount.trimmingCharacters(in: .whitespacesAndNewlines)
    switch m {
    case "Contax/Yashica (C/Y)": return "C/Y"
    case "M42 Screw Mount": return "M42"
    case "Leica LTM (M39)": return "M39 / LTM"
    case "Nikon S (Rangefinder)": return "Nikon S"
    case "Minolta SR/MD": return "MD / SR"
    case "Minolta/Sony A": return "A-Mount"
    case "Hasselblad XPan / Fuji TX": return "XPan"
    case "Mamiya TLR (C220/C330)": return "Mamiya TLR"
    case "Bronica ETR (645)": return "ETR 645"
    case "Bronica SQ (6x6)": return "SQ 6x6"
    case "Bronica GS-1 (6x7)": return "GS-1 6x7"
    case "Rollei SL66 / 6000": return "SL66"
    default: return m
    }
}

/// Tokenized & Subsequence Fuzzy Search Scorer (> 0 means match).
func fuzzyMatchScore(query: String, target: String) -> Int {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if q.isEmpty { return 1 }
    let t = target.lowercased()
    if t == q { return 1000 }
    if t.hasPrefix(q) { return 850 }
    if t.contains(q) { return 700 }

    let qClean = q.replacingOccurrences(of: "[-/._]", with: " ", options: .regularExpression)
    let tClean = t.replacingOccurrences(of: "[-/._]", with: " ", options: .regularExpression)
    let tokens = qClean.split(separator: " ").map(String.init).filter { !$0.isEmpty }
    guard !tokens.isEmpty else { return 1 }

    var totalScore = 0
    for token in tokens {
        if tClean.contains(token) {
            totalScore += 200
        } else {
            var tIdx = tClean.startIndex
            var matchedChars = 0
            for ch in token {
                if let found = tClean[tIdx...].firstIndex(of: ch) {
                    matchedChars += 1
                    tIdx = tClean.index(after: found)
                } else {
                    break
                }
            }
            if matchedChars == token.count {
                totalScore += 75
            } else {
                return 0
            }
        }
    }
    return totalScore
}

// MARK: - Lens Variants & Focal Categories

enum FocalLengthCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case ultraWide = "≤24"
    case w28 = "28"
    case w35 = "35"
    case std50 = "50"
    case port85 = "85"
    case tele105Plus = "105+"
    case zoom = "Zoom"

    var id: String { rawValue }
    var label: String { rawValue }
}

let ADAPTER_MOUNT_FILTERS: [String] = [
    "All", "M42", "Leica M", "L39", "Nikon F", "Canon FD", "Olympus OM", "Pentax K", "Contax (C/Y)"
]

struct LensVariantItem: Identifiable, Equatable {
    var id: String { "\(spec.id)_\(badge)" }
    let badge: String
    let subtitle: String
    let spec: LensGearSpec
}

struct ConsolidatedLensFamily: Identifiable, Equatable {
    let familyKey: String
    let displayTitle: String
    let brand: String
    let mount: String
    let variants: [LensVariantItem]
    var id: String { familyKey }
}

func resolveLensVariants(_ lens: LensGearSpec) -> [LensVariantItem] {
    let m = lens.model
    let mount = lens.mount

    if m.contains("New FD") {
        // The catalog writes the two generations in one string, e.g.
        // "FD 24mm f/2.8 S.S.C. / New FD 24mm f/2.8", so key off the New FD name.
        var base = m.components(separatedBy: "New FD").last ?? m
        if let dual = base.range(of: " / f/") {
            base = String(base[base.startIndex..<dual.lowerBound])
        }
        base = base.trimmingCharacters(in: .whitespacesAndNewlines)
        base = base.trimmingCharacters(in: CharacterSet(charactersIn: "/- "))

        // Early Canon FD Breech-Lock / FL 50mm f/1.8 stops down to f/16, whereas New FD 50mm f/1.8 reaches f/22.
        let breechMaxAperture = (lens.id == "canon_fd_50_18") ? 16.0 : lens.maxAperture
        let breechStops = (lens.id == "canon_fd_50_18")
            ? [1.8, 2.8, 4.0, 5.6, 8.0, 11.0, 16.0]
            : lens.apertureStops

        return [
            LensVariantItem(
                badge: "New FD (nFD)",
                subtitle: "Bayonet lock ring · S.C./S.S.C. multi-coated",
                spec: LensVariantSpec(lens, idSuffix: "nfd", model: "Canon New FD \(base)")
            ),
            LensVariantItem(
                badge: "FD Breech-Lock",
                subtitle: "Chrome/black breech ring · S.C. / S.S.C.",
                spec: LensVariantSpec(lens, idSuffix: "fd_breech", model: "Canon FD \(base) (Breech-Lock)", maxAperture: breechMaxAperture, apertureStops: breechStops)
            ),
            LensVariantItem(
                badge: "FL Mount",
                subtitle: "Stop-down metering vintage series",
                spec: LensVariantSpec(lens, idSuffix: "fl", model: "Canon FL \(base)", maxAperture: breechMaxAperture, apertureStops: breechStops)
            )
        ]
    }

    if m.contains("AI / AI-S") {
        let base = m.replacingOccurrences(of: "Nikkor ", with: "").replacingOccurrences(of: " (AI / AI-S)", with: "").trimmingCharacters(in: .whitespaces)
        return [
            LensVariantItem(
                badge: "AI-S",
                subtitle: "Linear aperture stop-down · NIC multi-coated",
                spec: LensVariantSpec(lens, idSuffix: "ais", model: "Nikkor \(base) AI-S")
            ),
            LensVariantItem(
                badge: "AI",
                subtitle: "Meter-coupled ridge · Classic throw",
                spec: LensVariantSpec(lens, idSuffix: "ai", model: "Nikkor \(base) AI")
            ),
            LensVariantItem(
                badge: "Pre-AI (Non-AI)",
                subtitle: "Scalloped metal ring · Nippon Kogaku",
                spec: LensVariantSpec(lens, idSuffix: "pre_ai", model: "Nikkor \(base) (Pre-AI)")
            )
        ]
    }

    if m.contains("AF / AF-D") {
        let base = m.replacingOccurrences(of: "AF / AF-D ", with: "").trimmingCharacters(in: .whitespaces)
        return [
            LensVariantItem(
                badge: "AF-D",
                subtitle: "Distance encoder · Physical aperture ring",
                spec: LensVariantSpec(lens, idSuffix: "afd", model: "AF \(base) D")
            ),
            LensVariantItem(
                badge: "AF (Non-D)",
                subtitle: "Original screw-drive autofocus",
                spec: LensVariantSpec(lens, idSuffix: "af", model: "AF \(base)")
            )
        ]
    }

    if m.contains("Super-Takumar / SMC Takumar") {
        let base = m.replacingOccurrences(of: "Super-Takumar / SMC Takumar ", with: "").trimmingCharacters(in: .whitespaces)
        return [
            LensVariantItem(
                badge: "SMC Takumar",
                subtitle: "7-layer Super-Multi-Coated · Rubberized focus",
                spec: LensVariantSpec(lens, idSuffix: "smc", model: "SMC Takumar \(base)")
            ),
            LensVariantItem(
                badge: "Super-Multi-Coated",
                subtitle: "All-metal scalloped barrel · S-M-C",
                spec: LensVariantSpec(lens, idSuffix: "smct", model: "Super-Multi-Coated Takumar \(base)")
            ),
            LensVariantItem(
                badge: "Super-Takumar",
                subtitle: "Classic amber single-coated optics",
                spec: LensVariantSpec(lens, idSuffix: "super", model: "Super-Takumar \(base)")
            )
        ]
    }

    if m.contains("Summicron-M") || m.contains("Summilux-M") || m.contains("Elmarit-M") || m.contains("Noctilux-M") {
        if m.contains("ASPH") {
            let nonAsph = m.replacingOccurrences(of: " ASPH", with: "")
            return [
                LensVariantItem(badge: "ASPH", subtitle: "Modern aspherical optical design", spec: lens),
                LensVariantItem(badge: "Pre-ASPH", subtitle: "Classic spherical rendering", spec: LensVariantSpec(lens, idSuffix: "pre_asph", model: "\(nonAsph) (Pre-ASPH)"))
            ]
        } else if !m.contains("V1") && !m.contains("Rigid") && !m.contains("Dual-Range") {
            return [
                LensVariantItem(badge: "Pre-ASPH (Classic)", subtitle: "Traditional spherical Mandler/Leitz optics", spec: lens),
                LensVariantItem(badge: "ASPH (Modern)", subtitle: "Aspherical fleet variant", spec: LensVariantSpec(lens, idSuffix: "asph", model: "\(m) ASPH"))
            ]
        }
    }

    if m.contains("SMC Pentax-M") || m.contains("SMC Pentax-A") || m.contains("SMC Pentax ") {
        let base = m
            .replacingOccurrences(of: "SMC Pentax-M ", with: "")
            .replacingOccurrences(of: "SMC Pentax-A ", with: "")
            .replacingOccurrences(of: "SMC Pentax ", with: "")
            .trimmingCharacters(in: .whitespaces)
        return [
            LensVariantItem(badge: "SMC Pentax-M", subtitle: "Compact mechanical K-mount", spec: LensVariantSpec(lens, idSuffix: "m", model: "SMC Pentax-M \(base)")),
            LensVariantItem(badge: "SMC Pentax-A", subtitle: "'A' auto-aperture contact pin", spec: LensVariantSpec(lens, idSuffix: "a", model: "SMC Pentax-A \(base)")),
            LensVariantItem(badge: "SMC Pentax (K)", subtitle: "Original full-size K-series", spec: LensVariantSpec(lens, idSuffix: "k", model: "SMC Pentax \(base)"))
        ]
    }

    if m.hasPrefix("Olympus Zuiko ") {
        let base = m.replacingOccurrences(of: "Olympus Zuiko ", with: "").trimmingCharacters(in: .whitespaces)
        return [
            LensVariantItem(badge: "Zuiko MC (Multi-Coated)", subtitle: "Later multi-coated black nose", spec: LensVariantSpec(lens, idSuffix: "mc", model: "Olympus Zuiko Auto-\(base) MC")),
            LensVariantItem(badge: "Silver Nose (S.C.)", subtitle: "Early chrome filter ring · Single-coated", spec: LensVariantSpec(lens, idSuffix: "sc", model: "Olympus Zuiko \(base) (Silver Nose)"))
        ]
    }

    if m.hasPrefix("Minolta MD ") || m.hasPrefix("Minolta MC ") {
        let base = m
            .replacingOccurrences(of: "Minolta MD W.Rokkor ", with: "")
            .replacingOccurrences(of: "Minolta MD Rokkor-X ", with: "")
            .replacingOccurrences(of: "Minolta MC Rokkor-PG ", with: "")
            .replacingOccurrences(of: "Minolta MC Rokkor-PF ", with: "")
            .replacingOccurrences(of: "Minolta MD Tele Rokkor ", with: "")
            .replacingOccurrences(of: "Minolta MD ", with: "")
            .replacingOccurrences(of: "Minolta MC ", with: "")
            .trimmingCharacters(in: .whitespaces)

        // Minolta MC Rokkor-PF 50mm f/1.7 stops down to f/16, whereas MD 50mm f/1.7 reaches f/22.
        let mcMaxAperture = (lens.id == "minolta_md_50_17") ? 16.0 : lens.maxAperture
        let mcStops = (lens.id == "minolta_md_50_17")
            ? [1.7, 2.8, 4.0, 5.6, 8.0, 11.0, 16.0]
            : lens.apertureStops

        return [
            LensVariantItem(badge: "New MD (Plain MD)", subtitle: "Compact lightweight barrel · Minimum aperture lock", spec: LensVariantSpec(lens, idSuffix: "nmd", model: "Minolta MD \(base)")),
            LensVariantItem(badge: "MD Rokkor-X", subtitle: "Second-gen MD · Achromatic coating", spec: LensVariantSpec(lens, idSuffix: "md_rokkor", model: "Minolta MD Rokkor-X \(base)")),
            LensVariantItem(badge: "MC Rokkor", subtitle: "All-metal metered-coupled vintage barrel", spec: LensVariantSpec(lens, idSuffix: "mc_rokkor", model: "Minolta MC Rokkor \(base)", maxAperture: mcMaxAperture, apertureStops: mcStops))
        ]
    }

    if mount == "Contax/Yashica (C/Y)" && m.hasPrefix("Carl Zeiss ") {
        return [
            LensVariantItem(badge: "MM (Multi-Mode)", subtitle: "Green minimum-aperture number · Program/Shutter priority", spec: LensVariantSpec(lens, idSuffix: "mm", model: "\(m) (MM)")),
            LensVariantItem(badge: "AE (Aperture-Priority)", subtitle: "White minimum-aperture number · Ninja-star bokeh", spec: LensVariantSpec(lens, idSuffix: "ae", model: "\(m) (AE)"))
        ]
    }

    if mount == "Hasselblad V" && m.contains("C / CF") {
        let base = m.replacingOccurrences(of: " C / CF", with: "").replacingOccurrences(of: " C / CF / CFE", with: "").trimmingCharacters(in: .whitespaces)
        return [
            LensVariantItem(badge: "CF (Prontor)", subtitle: "Ergonomic rubber grip · EV interlock optional", spec: LensVariantSpec(lens, idSuffix: "cf", model: "\(base) CF")),
            LensVariantItem(badge: "C (Synchro-Compur)", subtitle: "Classic chrome/black all-metal barrel", spec: LensVariantSpec(lens, idSuffix: "c", model: "\(base) C")),
            LensVariantItem(badge: "CB / CFi / CFE", subtitle: "Later internal stray-light baffling", spec: LensVariantSpec(lens, idSuffix: "cfi", model: "\(base) CFi/CFE"))
        ]
    }

    return [
        LensVariantItem(badge: "Standard", subtitle: lens.mount, spec: lens)
    ]
}

private func LensVariantSpec(
    _ base: LensGearSpec,
    idSuffix: String,
    model: String,
    minAperture: Double? = nil,
    maxAperture: Double? = nil,
    apertureStops: [Double]? = nil
) -> LensGearSpec {
    LensGearSpec(
        id: "\(base.id)_\(idSuffix)",
        brand: base.brand,
        model: model,
        mount: base.mount,
        minAperture: minAperture ?? base.minAperture,
        maxAperture: maxAperture ?? base.maxAperture,
        apertureStops: apertureStops ?? base.apertureStops,
        isCustom: base.isCustom
    )
}

func matchesFocalCategory(model: String, category: FocalLengthCategory) -> Bool {
    if category == .all { return true }
    let lower = model.lowercased()
    let isZoom = lower.range(of: #"\b\d{2,3}\s*-\s*\d{2,3}\s*mm"#, options: .regularExpression) != nil
    if category == .zoom { return isZoom }
    if isZoom { return false }

    guard let regex = try? NSRegularExpression(pattern: #"\b(\d+(?:\.\d+)?)\s*mm"#),
          let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
          let range = Range(match.range(at: 1), in: lower),
          let mm = Double(lower[range]) else {
        return false
    }

    switch category {
    case .all, .zoom: return true
    case .ultraWide: return mm <= 25.0
    case .w28: return mm >= 26.0 && mm <= 31.0
    case .w35: return mm >= 32.0 && mm <= 43.0
    case .std50: return mm >= 44.0 && mm <= 65.0
    case .port85: return mm >= 70.0 && mm <= 100.0
    case .tele105Plus: return mm > 100.0
    }
}

func extractFocalLengthMm(_ text: String) -> Double? {
    let lower = text.lowercased()
    guard let regex = try? NSRegularExpression(pattern: #"\b(\d+(?:\.\d+)?)\s*mm"#),
          let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
          let range = Range(match.range(at: 1), in: lower) else {
        return nil
    }
    return Double(lower[range])
}

func matchesAdaptedMount(lensMount: String, filter: String) -> Bool {
    switch filter {
    case "All": return true
    case "M42": return lensMount.localizedCaseInsensitiveContains("M42")
    case "Leica M": return lensMount.localizedCaseInsensitiveContains("Leica M")
    case "L39": return lensMount.localizedCaseInsensitiveContains("M39") || lensMount.localizedCaseInsensitiveContains("LTM")
    case "Nikon F": return lensMount.localizedCaseInsensitiveContains("Nikon F")
    case "Canon FD": return lensMount.localizedCaseInsensitiveContains("Canon FD")
    case "Olympus OM": return lensMount.localizedCaseInsensitiveContains("Olympus OM")
    case "Pentax K": return lensMount.localizedCaseInsensitiveContains("Pentax K")
    case "Contax (C/Y)": return lensMount.localizedCaseInsensitiveContains("Contax/Yashica")
    default: return true
    }
}

// MARK: - Gear Catalog Cache

struct PrewarmedLensEntry: Identifiable, Equatable {
    var id: String { lens.id }
    let lens: LensGearSpec
    let focalLengthMm: Double
    let variants: [LensVariantItem]
}

struct GearCatalogData: Codable {
    let mounts: [String]
    let cameras: [CameraGearSpec]
    let lenses: [LensGearSpec]
}

enum GearCatalogCache {
    private static var cachedCatalog: GearCatalogData?
    private static var cachedPrewarmedLenses: [PrewarmedLensEntry]?

    static func loadBundledCatalog() -> GearCatalogData {
        if let cached = cachedCatalog {
            return cached
        }
        guard let url = Bundle.main.url(forResource: "gear_catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(GearCatalogData.self, from: data) else {
            let fallback = GearCatalogData(
                mounts: ["Fixed", "Leica M", "Nikon F", "Canon FD", "Pentax K", "Olympus OM", "Minolta SR/MD", "Hasselblad V"],
                cameras: [
                    CameraGearSpec(
                        id: "rollei_35_s",
                        brand: "Rollei",
                        model: "Rollei 35 S / 35 SE",
                        isFixed: true,
                        mount: "Fixed",
                        minShutter: 0.5,
                        maxShutter: 0.002,
                        fixedLensName: "Rollei-HFT Sonnar 40mm f/2.8",
                        fixedMinAperture: 2.8,
                        fixedMaxAperture: 22.0,
                        fixedApertureStops: [2.8, 4.0, 5.6, 8.0, 11.0, 16.0, 22.0]
                    )
                ],
                lenses: []
            )
            cachedCatalog = fallback
            return fallback
        }
        cachedCatalog = decoded
        return decoded
    }

    /// Resolves the physical aperture stop markings for an active gear profile,
    /// including profiles decoded from older persisted UserDefaults state.
    static func resolveApertureStops(for gear: ActiveGearProfile) -> [Double]? {
        if !gear.apertureStops.isEmpty {
            return gear.apertureStops
        }

        let catalog = loadBundledCatalog()

        if gear.isFixedLens || gear.lensId.hasSuffix("_fixed") {
            if let cam = catalog.cameras.first(where: { $0.id == gear.cameraId || "\($0.id)_fixed" == gear.lensId }),
               !cam.fixedApertureStops.isEmpty {
                return cam.fixedApertureStops
            }
        }

        if !gear.lensId.isEmpty && !gear.lensId.hasSuffix("_adapter") {
            let entries = prewarmedBundledLenses()
            for entry in entries {
                if entry.lens.id == gear.lensId, !entry.lens.apertureStops.isEmpty {
                    return entry.lens.apertureStops
                }
                if let variant = entry.variants.first(where: { $0.spec.id == gear.lensId }),
                   !variant.spec.apertureStops.isEmpty {
                    return variant.spec.apertureStops
                }
            }
            for entry in entries {
                if gear.lensId.hasPrefix(entry.lens.id + "_"), !entry.lens.apertureStops.isEmpty {
                    return entry.lens.apertureStops
                }
            }
        }

        return nil
    }

    static func prewarmedBundledLenses() -> [PrewarmedLensEntry] {
        if let cached = cachedPrewarmedLenses {
            return cached
        }
        let catalog = loadBundledCatalog()
        let entries = catalog.lenses.map { lens in
            PrewarmedLensEntry(
                lens: lens,
                focalLengthMm: extractFocalLengthMm(lens.model) ?? 9999.0,
                variants: resolveLensVariants(lens)
            )
        }.sorted { a, b in
            if a.focalLengthMm != b.focalLengthMm { return a.focalLengthMm < b.focalLengthMm }
            if a.lens.minAperture != b.lens.minAperture { return a.lens.minAperture < b.lens.minAperture }
            return a.lens.model < b.lens.model
        }
        cachedPrewarmedLenses = entries
        return entries
    }

    static func allCameras(customCameras: [CameraGearSpec]) -> [CameraGearSpec] {
        let base = loadBundledCatalog().cameras
        var seen = Set<String>()
        var result: [CameraGearSpec] = []
        for cam in (customCameras + base) {
            let key = "\(cam.brand) \(cam.model)".trimmingCharacters(in: .whitespaces).lowercased()
            if seen.insert(key).inserted {
                result.append(cam)
            }
        }
        return result
    }

    static func allLensEntries(customLenses: [LensGearSpec]) -> [PrewarmedLensEntry] {
        let base = prewarmedBundledLenses()
        guard !customLenses.isEmpty else { return base }
        let customEntries = customLenses.map { lens in
            PrewarmedLensEntry(
                lens: lens,
                focalLengthMm: extractFocalLengthMm(lens.model) ?? 9999.0,
                variants: resolveLensVariants(lens)
            )
        }
        return (customEntries + base).sorted { a, b in
            if a.focalLengthMm != b.focalLengthMm { return a.focalLengthMm < b.focalLengthMm }
            if a.lens.minAperture != b.lens.minAperture { return a.lens.minAperture < b.lens.minAperture }
            return a.lens.model < b.lens.model
        }
    }
}
