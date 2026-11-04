import Foundation
import CoreLocation
import UIKit
import Combine

// MARK: - Passive GPS Location Cache

final class LocationCache: NSObject, CLLocationManagerDelegate {
    static let shared = LocationCache()

    private let manager = CLLocationManager()
    private(set) var lastKnownCoordinate: CLLocationCoordinate2D?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if let loc = manager.location {
            lastKnownCoordinate = loc.coordinate
        }
    }

    func refreshIfAuthorized() {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            if let loc = manager.location {
                lastKnownCoordinate = loc.coordinate
            }
            manager.requestLocation()
        }
    }

    func requestPermissionAndRefresh() {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            if let loc = manager.location {
                lastKnownCoordinate = loc.coordinate
            }
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let latest = locations.last {
            lastKnownCoordinate = latest.coordinate
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Ignore transient GPS errors
    }
}

// MARK: - Persistent Film Log Store

final class FilmLogStore: ObservableObject {
    @Published var rollState: FilmRollState {
        didSet { saveRollState(rollState) }
    }
    @Published var customFilms: [FilmStockPreset] {
        didSet { saveCustomFilms(customFilms) }
    }
    @Published var loggedFrames: [LoggedFrame] {
        didSet { saveLoggedFrames(loggedFrames) }
    }
    @Published var activeGear: ActiveGearProfile {
        didSet { saveActiveGear(activeGear) }
    }
    @Published var customCameras: [CameraGearSpec] {
        didSet { saveCustomCameras(customCameras) }
    }
    @Published var customLenses: [LensGearSpec] {
        didSet { saveCustomLenses(customLenses) }
    }
    @Published var manualEvCompIndex: Int {
        didSet {
            let safeIdx = manualEvCompIndex.clamped(to: 0...(EV_COMP_STOPS.count - 1))
            UserDefaults.standard.set(EV_COMP_STOPS[safeIdx], forKey: Keys.manualEvComp)
        }
    }

    private enum Keys {
        static let rollState = "rollei.filmlog.rollState"
        static let customFilms = "rollei.filmlog.customFilms"
        static let loggedFrames = "rollei.filmlog.loggedFrames"
        static let activeGear = "rollei.filmlog.activeGear"
        static let customCameras = "rollei.filmlog.customCameras"
        static let customLenses = "rollei.filmlog.customLenses"
        static let manualEvComp = "rollei.filmlog.manualEvComp"
    }

    private let snapshotCache = NSCache<NSString, UIImage>()
    private let snapshotsDirURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = docs.appendingPathComponent("film_snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.snapshotsDirURL = dir

        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: Keys.rollState),
           let decoded = try? decoder.decode(FilmRollState.self, from: data) {
            self.rollState = decoded
        } else {
            self.rollState = FilmRollState()
        }

        if let data = UserDefaults.standard.data(forKey: Keys.customFilms),
           let decoded = try? decoder.decode([FilmStockPreset].self, from: data) {
            self.customFilms = decoded
        } else {
            self.customFilms = []
        }

        if let data = UserDefaults.standard.data(forKey: Keys.loggedFrames),
           let decoded = try? decoder.decode([LoggedFrame].self, from: data) {
            self.loggedFrames = decoded
        } else {
            self.loggedFrames = []
        }

        if let data = UserDefaults.standard.data(forKey: Keys.activeGear),
           let decoded = try? decoder.decode(ActiveGearProfile.self, from: data) {
            self.activeGear = decoded
        } else {
            self.activeGear = ActiveGearProfile()
        }

        if let data = UserDefaults.standard.data(forKey: Keys.customCameras),
           let decoded = try? decoder.decode([CameraGearSpec].self, from: data) {
            self.customCameras = decoded
        } else {
            self.customCameras = []
        }

        if let data = UserDefaults.standard.data(forKey: Keys.customLenses),
           let decoded = try? decoder.decode([LensGearSpec].self, from: data) {
            self.customLenses = decoded
        } else {
            self.customLenses = []
        }

        let savedEv = UserDefaults.standard.double(forKey: Keys.manualEvComp)
        let idx = EV_COMP_STOPS.firstIndex(where: { abs($0 - savedEv) < 0.08 })
            ?? EV_COMP_STOPS.firstIndex(of: 0.0)
            ?? 9
        self.manualEvCompIndex = idx
    }

    var manualEvComp: Double {
        if rollState.isSlideFilm { return 0.0 }
        let safeIdx = manualEvCompIndex.clamped(to: 0...(EV_COMP_STOPS.count - 1))
        return EV_COMP_STOPS[safeIdx]
    }

    var expiredEvComp: Double {
        rollState.isSlideFilm ? 0.0 : rollState.activeExpiredCompEv
    }

    var totalEvComp: Double {
        manualEvComp + expiredEvComp
    }

    // MARK: - Persistence Helpers

    private func saveRollState(_ state: FilmRollState) {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Keys.rollState)
        }
    }

    private func saveCustomFilms(_ stocks: [FilmStockPreset]) {
        if let data = try? JSONEncoder().encode(stocks) {
            UserDefaults.standard.set(data, forKey: Keys.customFilms)
        }
    }

    private func saveLoggedFrames(_ frames: [LoggedFrame]) {
        if let data = try? JSONEncoder().encode(frames) {
            UserDefaults.standard.set(data, forKey: Keys.loggedFrames)
        }
    }

    private func saveActiveGear(_ gear: ActiveGearProfile) {
        if let data = try? JSONEncoder().encode(gear) {
            UserDefaults.standard.set(data, forKey: Keys.activeGear)
        }
    }

    private func saveCustomCameras(_ cameras: [CameraGearSpec]) {
        if let data = try? JSONEncoder().encode(cameras) {
            UserDefaults.standard.set(data, forKey: Keys.customCameras)
        }
    }

    private func saveCustomLenses(_ lenses: [LensGearSpec]) {
        if let data = try? JSONEncoder().encode(lenses) {
            UserDefaults.standard.set(data, forKey: Keys.customLenses)
        }
    }

    // MARK: - Capture & Record Moments

    func captureMoment(
        shutterSpeed: String,
        aperture: String,
        iso: Int,
        sceneEv: Double,
        compensatedEv: Double,
        zone: Int,
        meterMode: String,
        isAutoExposure: Bool,
        previewImage: UIImage?
    ) -> CapturedMoment {
        LocationCache.shared.refreshIfAuthorized()
        let coord = LocationCache.shared.lastKnownCoordinate

        let now = Date()
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.timeZone = TimeZone.current
        isoFormatter.formatOptions = [.withInternetDateTime]
        let timestampIso = isoFormatter.string(from: now)

        let utcFormatter = ISO8601DateFormatter()
        utcFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        utcFormatter.formatOptions = [.withInternetDateTime]
        let timestampUtc = utcFormatter.string(from: now)

        let scaledSnap = previewImage.map { Self.scaleSnapshot($0, maxDimension: 520) }

        return CapturedMoment(
            rollNumber: rollState.rollNumber,
            frameNumber: rollState.currentFrame,
            rollMaxFrames: rollState.maxFrames,
            filmName: rollState.filmName.isEmpty ? "Unloaded Roll" : rollState.filmName,
            isExpiredFilm: rollState.isExpired,
            expiredYear: rollState.expiredYear,
            timestampIso: timestampIso,
            timestampUtc: timestampUtc,
            timezoneId: TimeZone.current.identifier,
            shutterSpeed: shutterSpeed,
            aperture: aperture,
            iso: iso,
            sceneEv: sceneEv,
            compensatedEv: compensatedEv,
            zone: zone,
            meterMode: meterMode,
            isAutoExposure: isAutoExposure,
            manualEvComp: manualEvComp,
            expiredEvComp: expiredEvComp,
            totalEvComp: totalEvComp,
            latitude: coord?.latitude,
            longitude: coord?.longitude,
            snapshotImage: scaledSnap,
            cameraName: activeGear.cameraName,
            lensName: activeGear.lensName
        )
    }

    @discardableResult
    func recordMoment(_ moment: CapturedMoment) -> LoggedFrame {
        let id = Int64(Date().timeIntervalSince1970 * 1000)
        var snapshotFileName: String? = nil

        if let img = moment.snapshotImage,
           let jpegData = img.jpegData(compressionQuality: 0.85) {
            let fileName = "roll\(moment.rollNumber)_frame\(moment.frameNumber)_\(id).jpg"
            let fileURL = snapshotsDirURL.appendingPathComponent(fileName)
            if (try? jpegData.write(to: fileURL, options: .atomic)) != nil {
                snapshotFileName = fileName
                snapshotCache.setObject(img, forKey: fileName as NSString)
            }
        }

        let newFrame = LoggedFrame(
            id: id,
            rollNumber: moment.rollNumber,
            frameNumber: moment.frameNumber,
            rollMaxFrames: moment.rollMaxFrames,
            filmName: moment.filmName,
            isExpiredFilm: moment.isExpiredFilm,
            expiredYear: moment.expiredYear,
            timestampIso: moment.timestampIso,
            timestampUtc: moment.timestampUtc,
            timezoneId: moment.timezoneId,
            shutterSpeed: moment.shutterSpeed,
            aperture: moment.aperture,
            iso: moment.iso,
            sceneEv: moment.sceneEv,
            compensatedEv: moment.compensatedEv,
            zone: moment.zone,
            meterMode: moment.meterMode,
            isAutoExposure: moment.isAutoExposure,
            manualEvComp: moment.manualEvComp,
            expiredEvComp: moment.expiredEvComp,
            totalEvComp: moment.totalEvComp,
            latitude: moment.latitude,
            longitude: moment.longitude,
            snapshotFileName: snapshotFileName,
            note: "",
            cameraName: moment.cameraName,
            lensName: moment.lensName
        )

        if let fileName = snapshotFileName {
            let fileURL = snapshotsDirURL.appendingPathComponent(fileName)
            DispatchQueue.global(qos: .utility).async {
                _ = ExifAndXmpWriter.writeExifMetadataToFile(url: fileURL, frame: newFrame)
            }
        }

        loggedFrames.insert(newFrame, at: 0)
        var nextRoll = rollState
        nextRoll.currentFrame = min(99, rollState.currentFrame + 1)
        rollState = nextRoll
        return newFrame
    }

    func updateFrameNote(frameId: Int64, note: String) {
        guard let idx = loggedFrames.firstIndex(where: { $0.id == frameId }) else { return }
        loggedFrames[idx].note = note
        let updated = loggedFrames[idx]
        if let fileName = updated.snapshotFileName {
            let fileURL = snapshotsDirURL.appendingPathComponent(fileName)
            DispatchQueue.global(qos: .utility).async {
                _ = ExifAndXmpWriter.writeExifMetadataToFile(url: fileURL, frame: updated)
            }
        }
    }

    func deleteFrame(frameId: Int64) {
        if let target = loggedFrames.first(where: { $0.id == frameId }),
           let fileName = target.snapshotFileName {
            snapshotCache.removeObject(forKey: fileName as NSString)
            let fileURL = snapshotsDirURL.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: fileURL)
        }
        loggedFrames.removeAll { $0.id == frameId }
    }

    func addCustomFilm(_ stock: FilmStockPreset) {
        let key = "\(stock.name.trimmingCharacters(in: .whitespaces).lowercased())_\(stock.iso)"
        var updated = customFilms.filter {
            "\($0.name.trimmingCharacters(in: .whitespaces).lowercased())_\($0.iso)" != key
        }
        updated.append(stock)
        customFilms = updated
    }

    func deleteCustomFilm(_ target: FilmStockPreset) {
        customFilms.removeAll { $0.name == target.name && $0.iso == target.iso }
    }

    func addCustomCamera(_ cam: CameraGearSpec) {
        let key = "\(cam.brand) \(cam.model)".trimmingCharacters(in: .whitespaces).lowercased()
        var updated = customCameras.filter {
            "\($0.brand) \($0.model)".trimmingCharacters(in: .whitespaces).lowercased() != key
        }
        updated.insert(cam, at: 0)
        customCameras = updated
    }

    func addCustomLens(_ lens: LensGearSpec) {
        let key = "\(lens.brand) \(lens.model)".trimmingCharacters(in: .whitespaces).lowercased()
        var updated = customLenses.filter {
            "\($0.brand) \($0.model)".trimmingCharacters(in: .whitespaces).lowercased() != key
        }
        updated.insert(lens, at: 0)
        customLenses = updated
    }

    /// Removes a user-added body and detaches it from the meter if it was in use.
    func removeCustomCamera(id: String) {
        customCameras.removeAll { $0.id == id }
        if activeGear.cameraId == id {
            activeGear = .unloaded
        }
    }

    /// Removes a user-added lens and clears it from the meter if it was mounted.
    func removeCustomLens(id: String) {
        customLenses.removeAll { $0.id == id }
        if activeGear.lensId == id {
            var gear = activeGear
            gear.lensId = ""
            gear.lensName = ""
            gear.minAperture = 1.0
            gear.maxAperture = 32.0
            activeGear = gear
        }
    }

    func loadSnapshotImage(_ fileName: String?) -> UIImage? {
        guard let fileName, !fileName.isEmpty else { return nil }
        if let cached = snapshotCache.object(forKey: fileName as NSString) {
            return cached
        }
        let url = snapshotsDirURL.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        snapshotCache.setObject(image, forKey: fileName as NSString)
        return image
    }

    static func scaleSnapshot(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension, maxSide > 0 else { return image }
        let ratio = maxDimension / maxSide
        let targetSize = CGSize(width: round(size.width * ratio), height: round(size.height * ratio))
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

// MARK: - Mechanical Haptics Helper

enum MechanicalHaptics {
    static func tick() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func click() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func confirm() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
