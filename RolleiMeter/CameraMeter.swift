import AVFoundation
import Combine
import CoreImage
import CoreVideo
import ImageIO
import QuartzCore
import UIKit

/// Runs the back camera and turns each frame into a scene EV (ISO 100).
/// On LiDAR phones it renders the pure red Depth-of-Field overlay for the metered range.
final class CameraMeter: NSObject, ObservableObject,
    AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureDepthDataOutputDelegate {

    let session = AVCaptureSession()

    @Published private(set) var sceneEV: Double = 12
    @Published private(set) var distance: Double?
    @Published private(set) var hasLiDAR = false
    @Published private(set) var denied = false
    @Published private(set) var spotDelta: Double?
    @Published private(set) var canFocusManually = true
    let peakingFeed = PeakingFeed()

    private let sessionQueue = DispatchQueue(label: "meter.session")
    private let frameQueue = DispatchQueue(label: "meter.frames")
    private let depthQueue = DispatchQueue(label: "meter.depth")
    private let output = AVCaptureVideoDataOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private var device: AVCaptureDevice?
    private var configured = false

    private let lock = NSLock()
    private var mode: MeterMode = .matrix
    private var spot = CGPoint(x: 0.5, y: 0.5)
    private var spotRadius: CGFloat = 0.05
    private var focus = CGPoint(x: 0.5, y: 0.5)
    private var previewFlipped = false
    private var lensNow: Float = 0.5
    private static let phoneFocalMM = 6.8
    private var phoneMinFocusMM = 200.0

    // LiDAR Pure Depth-of-Field Overlay & Snapshot Cloning
    private var dofNear: Double = 0.9
    private var dofFar: Double = 2.0
    private var dofActive: Bool = false
    private var latestDepthPixelBuffer: CVPixelBuffer?
    private var frozenDepthPixelBuffer: CVPixelBuffer?
    private let dofLock = NSLock()
    private let dofContext = CIContext(options: [.workingColorSpace: NSNull()])
    private var dofBusy = false
    private let peakQueue = DispatchQueue(label: "meter.peak", qos: .userInitiated)

    private static let dofKernel: CIColorKernel? = {
        let src = """
        kernel vec4 dofMask(__sample depthVal, float nearDist, float farDist) {
            float d = depthVal.r;
            if (d > 0.1 && d >= nearDist && d <= farDist) {
                return vec4(1.0, 0.12, 0.12, 0.45);
            }
            return vec4(0.0, 0.0, 0.0, 0.0);
        }
        """
        return CIColorKernel(source: src)
    }()

    private var smoothed: Double?
    private var deltaSmoothed: Double?
    private var steadyEV: Double?
    private var steadyDelta: Double?
    private var distSmoothed: Double?
    private var latestPreviewPixelBuffer: CVPixelBuffer?
    private let previewImageContext = CIContext()
    private var lastPublish: CFTimeInterval = 0
    private var lastDepthPublish: CFTimeInterval = 0

    private let highlightStops = 1.5
    private var currentBias: Float = 0
    private var lastBiasUpdate: CFTimeInterval = 0

    private static let lut: [Double] = (0..<256).map { i in
        let v = Double(i) / 255.0
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private struct MatrixGridPoint {
        let fx: Double
        let fy: Double
        let weight: Double
    }

    private static let matrixGrid: [MatrixGridPoint] = {
        let gx = 48
        let gy = 36
        var points: [MatrixGridPoint] = []
        points.reserveCapacity(gx * gy)
        for j in 0..<gy {
            let fy = (Double(j) + 0.5) / Double(gy)
            let dy = fy - 0.5
            for i in 0..<gx {
                let fx = (Double(i) + 0.5) / Double(gx)
                let dx = fx - 0.5
                let w = 0.35 + 0.65 * exp(-(dx * dx + dy * dy) / 0.18)
                points.append(MatrixGridPoint(fx: fx, fy: fy, weight: w))
            }
        }
        return points
    }()

    private static let matrixWeightTotal: Double = {
        matrixGrid.reduce(0) { $0 + $1.weight }
    }()

    private static func settled(_ value: Double, _ current: inout Double?) -> Double {
        let step = 1.0 / 3.0
        if let cur = current, abs(value - cur) <= step * 0.5 + 0.1 { return cur }
        let snapped = (value / step).rounded() * step
        current = snapped
        return snapped
    }

    func setConfig(mode: MeterMode, spot: CGPoint, radius: CGFloat, focus: CGPoint, flipped: Bool) {
        lock.lock()
        self.previewFlipped = flipped
        self.mode = mode
        self.spot = spot
        self.spotRadius = radius
        self.smoothed = nil
        self.deltaSmoothed = nil
        self.steadyEV = nil
        self.steadyDelta = nil
        if focus != self.focus { self.distSmoothed = nil }
        self.focus = focus
        lock.unlock()
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async { self.configureAndRun() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.sessionQueue.async { self.configureAndRun() }
                } else {
                    DispatchQueue.main.async { self.denied = true }
                }
            }
        default:
            DispatchQueue.main.async { self.denied = true }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    // MARK: - Focus & LiDAR DoF

    func setManualFocus(_ position: Float) {}
    func setManualFocusThrottled(_ position: Float) {}

    func resumeAutoFocus() {
        sessionQueue.async {
            guard let dev = self.device, dev.isFocusModeSupported(.continuousAutoFocus) else { return }
            do {
                try dev.lockForConfiguration()
                dev.focusMode = .continuousAutoFocus
                dev.unlockForConfiguration()
            } catch {}
        }
    }

    func currentLensPosition() -> Float {
        lock.lock()
        defer { lock.unlock() }
        return lensNow
    }

    func lensPosition(forDistance d: Double) -> Float {
        if d.isInfinite { return 1 }
        let f = CameraMeter.phoneFocalMM
        lock.lock()
        let nearMM = max(phoneMinFocusMM, 2 * f)
        lock.unlock()
        let x0 = f * f / (nearMM - f)
        let x = f * f / (max(d * 1000, nearMM) - f)
        return Float(min(max(1 - x / x0, 0), 1))
    }

    func focusDistance(forLensPosition p: Float) -> Double {
        let f = CameraMeter.phoneFocalMM
        lock.lock()
        let nearMM = max(phoneMinFocusMM, 2 * f)
        lock.unlock()
        let x = f * f / (nearMM - f) * (1 - Double(min(max(p, 0), 1)))
        if x < 0.0005 { return .infinity }
        let d = (f * f / x + f) / 1000.0
        return d >= 8.5 ? .infinity : d
    }

    func currentFocusDistance() -> Double {
        focusDistance(forLensPosition: currentLensPosition())
    }

    func setPeaking(_ on: Bool) {
        if !on {
            DispatchQueue.main.async { self.peakingFeed.image = nil }
        }
    }

    // MARK: - Deep Copy & Frozen Snapshot

    private func deepCopyPixelBuffer(_ src: CVPixelBuffer) -> CVPixelBuffer? {
        CVPixelBufferLockBaseAddress(src, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(src, .readOnly) }

        guard let srcBase = CVPixelBufferGetBaseAddress(src) else { return nil }
        let width = CVPixelBufferGetWidth(src)
        let height = CVPixelBufferGetHeight(src)
        let pixelFormat = CVPixelBufferGetPixelFormatType(src)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(src)

        var dst: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            pixelFormat,
            nil,
            &dst
        )

        guard status == kCVReturnSuccess, let dstBuffer = dst else { return nil }

        CVPixelBufferLockBaseAddress(dstBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(dstBuffer, []) }

        if let dstBase = CVPixelBufferGetBaseAddress(dstBuffer) {
            let dstBytesPerRow = CVPixelBufferGetBytesPerRow(dstBuffer)
            if bytesPerRow == dstBytesPerRow {
                memcpy(dstBase, srcBase, height * bytesPerRow)
            } else {
                let copyBytes = min(bytesPerRow, dstBytesPerRow)
                for row in 0..<height {
                    let srcRow = srcBase.advanced(by: row * bytesPerRow)
                    let dstRow = dstBase.advanced(by: row * dstBytesPerRow)
                    memcpy(dstRow, srcRow, copyBytes)
                }
            }
        }

        return dstBuffer
    }

    /// Takes a true byte-level screenshot of the LiDAR depth map so the camera pool cannot overwrite it.
    func freezeDepth() {
        dofLock.lock()
        if let live = latestDepthPixelBuffer {
            frozenDepthPixelBuffer = deepCopyPixelBuffer(live)
        }
        dofLock.unlock()
    }

    /// Resumes live depth scanning when HOLD is released.
    func unfreezeDepth() {
        dofLock.lock()
        frozenDepthPixelBuffer = nil
        dofLock.unlock()
    }

    /// Sets the physical depth slice (in metres) to shade red over the viewfinder.
    /// Operates on the frozen LiDAR screenshot when HOLD is active.
    func setDoFRange(near: Double, far: Double, active: Bool) {
        dofLock.lock()
        dofNear = near
        dofFar = far
        dofActive = active
        let pb = frozenDepthPixelBuffer ?? latestDepthPixelBuffer
        let flipped = previewFlipped
        dofLock.unlock()

        if !active {
            DispatchQueue.main.async { self.peakingFeed.image = nil }
            return
        }

        if let pb = pb {
            renderDoFOverlay(pb, near: near, far: far, flipped: flipped)
        }
    }

    private func renderDoFOverlay(_ pb: CVPixelBuffer, near: Double, far: Double, flipped: Bool) {
        dofLock.lock()
        guard !dofBusy else {
            dofLock.unlock()
            return
        }
        dofBusy = true
        dofLock.unlock()

        peakQueue.async { [weak self] in
            guard let self = self else { return }
            defer {
                self.dofLock.lock()
                self.dofBusy = false
                self.dofLock.unlock()
            }

            var image = CIImage(cvPixelBuffer: pb)
            if flipped { image = image.oriented(.down) }

            guard let kernel = CameraMeter.dofKernel,
                  let output = kernel.apply(extent: image.extent, arguments: [image, Float(near), Float(far)]),
                  let cg = self.dofContext.createCGImage(output, from: output.extent)
            else { return }

            let uiImage = UIImage(cgImage: cg)
            DispatchQueue.main.async {
                self.peakingFeed.image = uiImage
            }
        }
    }

    // MARK: - Session setup

    private func configureAndRun() {
        if !configured {
            configured = buildSession(lidar: true) || buildSession(lidar: false)
            if configured, let dev = device { tune(dev) }
        }
        if configured {
            currentBias = 0
            lastBiasUpdate = 0
            setBias(0)
            if !session.isRunning { session.startRunning() }
        }
    }

    private func pickLiDARFormat(_ dev: AVCaptureDevice) -> (video: AVCaptureDevice.Format, depth: AVCaptureDevice.Format)? {
        var best: (video: AVCaptureDevice.Format, depth: AVCaptureDevice.Format)?
        var bestDelta = Int32.max
        for f in dev.formats {
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            guard d.height > 0, d.width >= 1000,
                  abs(Double(d.width) / Double(d.height) - 4.0 / 3.0) < 0.01,
                  !f.supportedDepthDataFormats.isEmpty else { continue }
            let depthFormat = f.supportedDepthDataFormats.first {
                CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat32
            } ?? f.supportedDepthDataFormats[0]
            let delta = abs(d.width - 1920)
            if delta < bestDelta {
                bestDelta = delta
                best = (video: f, depth: depthFormat)
            }
        }
        return best
    }

    private func buildSession(lidar: Bool) -> Bool {
        let type: AVCaptureDevice.DeviceType = lidar ? .builtInLiDARDepthCamera : .builtInWideAngleCamera
        guard let dev = AVCaptureDevice.default(type, for: .video, position: .back) else { return false }

        session.automaticallyConfiguresCaptureDeviceForWideColor = false
        session.beginConfiguration()
        for i in session.inputs { session.removeInput(i) }
        for o in session.outputs { session.removeOutput(o) }

        func fail() -> Bool {
            session.commitConfiguration()
            return false
        }

        guard let input = try? AVCaptureDeviceInput(device: dev), session.canAddInput(input) else { return fail() }
        session.addInput(input)

        if lidar {
            guard let pick = pickLiDARFormat(dev) else { return fail() }
            do {
                try dev.lockForConfiguration()
                dev.activeFormat = pick.video
                dev.activeDepthDataFormat = pick.depth
                dev.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                dev.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                dev.unlockForConfiguration()
            } catch {
                return fail()
            }
        } else {
            session.sessionPreset = .photo
        }

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: frameQueue)
        guard session.canAddOutput(output) else { return fail() }
        session.addOutput(output)

        if let conn = output.connection(with: .video), conn.isVideoRotationAngleSupported(0) {
            conn.videoRotationAngle = 0
        }

        if lidar {
            depthOutput.isFilteringEnabled = true
            depthOutput.alwaysDiscardsLateDepthData = true
            depthOutput.setDelegate(self, callbackQueue: depthQueue)
            guard session.canAddOutput(depthOutput) else { return fail() }
            session.addOutput(depthOutput)
        }

        session.commitConfiguration()
        device = dev
        let minFocus = Double(dev.minimumFocusDistance)
        lock.lock()
        if minFocus > 0 { phoneMinFocusMM = minFocus }
        lock.unlock()
        DispatchQueue.main.async {
            self.hasLiDAR = lidar
            self.canFocusManually = true
        }
        return true
    }

    private func tune(_ dev: AVCaptureDevice) {
        do {
            try dev.lockForConfiguration()
            dev.automaticallyAdjustsVideoHDREnabled = false
            if dev.activeFormat.isVideoHDRSupported { dev.isVideoHDREnabled = false }
            if dev.isLowLightBoostSupported { dev.automaticallyEnablesLowLightBoostWhenAvailable = false }
            if dev.activeFormat.supportedColorSpaces.contains(.sRGB) { dev.activeColorSpace = .sRGB }
            if dev.isExposurePointOfInterestSupported { dev.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5) }
            if dev.isExposureModeSupported(.continuousAutoExposure) { dev.exposureMode = .continuousAutoExposure }
            dev.unlockForConfiguration()
        } catch {}
    }

    private func setBias(_ b: Float) {
        sessionQueue.async {
            guard let dev = self.device else { return }
            do {
                try dev.lockForConfiguration()
                let c = min(max(b, dev.minExposureTargetBias), dev.maxExposureTargetBias)
                dev.setExposureTargetBias(c, completionHandler: nil)
                dev.unlockForConfiguration()
            } catch {}
        }
    }

    private func steerExposure(refY: Double) {
        let now = CACurrentMediaTime()
        let isFirstCorrection = lastBiasUpdate == 0
        guard now - lastBiasUpdate > (isFirstCorrection ? 0 : 0.15) else { return }
        lastBiasUpdate = now

        let err = log2(refY / 0.18)
        guard abs(err) > 0.1 else { return }
        let gain: Float = isFirstCorrection ? 0.9 : 0.35
        let maxStep: Float = isFirstCorrection ? 4 : 1.25
        let step = min(max(Float(err) * gain, -maxStep), maxStep)
        let next = min(max(currentBias - step, -6), 6)
        guard abs(next - currentBias) > 0.02 else { return }
        currentBias = next
        setBias(next)
    }

    // MARK: - Depth (LiDAR)

    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        dofLock.lock()
        let isFrozen = (frozenDepthPixelBuffer != nil)
        dofLock.unlock()

        // In HOLD mode: completely halt live LiDAR stream
        if isFrozen { return }

        lock.lock()
        let pt = focus
        lock.unlock()

        let r = 0.03
        let converted = depthData.depthDataType == kCVPixelFormatType_DepthFloat32
            ? depthData
            : depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let map = converted.depthDataMap

        dofLock.lock()
        latestDepthPixelBuffer = map
        let renderNow = dofActive
        let curNear = dofNear
        let curFar = dofFar
        let isFlipped = previewFlipped
        dofLock.unlock()

        if renderNow {
            renderDoFOverlay(map, near: curNear, far: curFar, flipped: isFlipped)
        }

        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return }
        let w = CVPixelBufferGetWidth(map)
        let h = CVPixelBufferGetHeight(map)
        let bpr = CVPixelBufferGetBytesPerRow(map)

        let sx = Double(pt.x)
        let sy = Double(pt.y)

        var values: [Double] = []
        let steps = 7
        for j in 0..<steps {
            for i in 0..<steps {
                let u = (Double(i) + 0.5) / Double(steps) * 2 - 1
                let v = (Double(j) + 0.5) / Double(steps) * 2 - 1
                let x = min(max(Int((sx + u * r * 0.75) * Double(w)), 0), w - 1)
                let y = min(max(Int((sy + v * r) * Double(h)), 0), h - 1)
                let row = base.advanced(by: y * bpr).assumingMemoryBound(to: Float32.self)
                let d = Double(row[x])
                if d.isFinite, d > 0.1, d < 12 { values.append(d) }
            }
        }

        var out: Double?
        lock.lock()
        if values.count >= 5 {
            values.sort()
            let med = values[values.count / 2]
            if let s = distSmoothed, abs(med - s) < max(0.15, 0.08 * s) {
                distSmoothed = s + 0.4 * (med - s)
            } else {
                distSmoothed = med
            }
            out = distSmoothed
        } else {
            distSmoothed = nil
        }
        lock.unlock()

        let now = CACurrentMediaTime()
        guard now - lastDepthPublish > 0.1 else { return }
        lastDepthPublish = now
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let new = out, let old = self.distance, abs(new - old) < max(0.03, 0.02 * old) { return }
            self.distance = out
        }
    }

    // MARK: - Frame processing (exposure)

    private func frameExposure(_ sb: CMSampleBuffer, _ dev: AVCaptureDevice) -> (t: Double, iso: Double, n: Double) {
        var t = CMTimeGetSeconds(dev.exposureDuration)
        var iso = Double(dev.iso)
        var n = Double(dev.lensAperture)

        if let raw = CMGetAttachment(sb, key: kCGImagePropertyExifDictionary, attachmentModeOut: nil),
           let exif = raw as? NSDictionary {
            if let v = exif[kCGImagePropertyExifExposureTime as String] as? Double, v > 0 { t = v }
            if let arr = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Any],
               let v = (arr.first as? NSNumber)?.doubleValue, v > 0 { iso = v }
            if let v = exif[kCGImagePropertyExifFNumber as String] as? Double, v > 0 { n = v }
        }
        return (t, iso, n)
    }

    func sampleFrozenDepth(at pt: CGPoint) -> Double? {
        dofLock.lock()
        let pb = frozenDepthPixelBuffer ?? latestDepthPixelBuffer
        dofLock.unlock()
        guard let map = pb else { return nil }

        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let w = CVPixelBufferGetWidth(map)
        let h = CVPixelBufferGetHeight(map)
        let bpr = CVPixelBufferGetBytesPerRow(map)

        let sx = Double(pt.x)
        let sy = Double(pt.y)
        let r = 0.03
        var values: [Double] = []
        let steps = 7
        for j in 0..<steps {
            for i in 0..<steps {
                let u = (Double(i) + 0.5) / Double(steps) * 2 - 1
                let v = (Double(j) + 0.5) / Double(steps) * 2 - 1
                let x = min(max(Int((sx + u * r * 0.75) * Double(w)), 0), w - 1)
                let y = min(max(Int((sy + v * r) * Double(h)), 0), h - 1)
                let row = base.advanced(by: y * bpr).assumingMemoryBound(to: Float32.self)
                let d = Double(row[x])
                if d.isFinite, d > 0.1, d < 8.5 { values.append(d) }
            }
        }
        if values.count >= 3 {
            values.sort()
            return values[values.count / 2]
        }
        return nil
    }

    func previewSnapshot() -> UIImage? {
        lock.lock()
        let pixelBuffer = latestPreviewPixelBuffer
        let flipped = previewFlipped
        lock.unlock()
        guard let pixelBuffer = pixelBuffer else { return nil }

        let sensorImage = CIImage(cvPixelBuffer: pixelBuffer)
        let image = flipped ? sensorImage.oriented(.down) : sensorImage
        guard let cgImage = previewImageContext.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let dev = device, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        lock.lock()
        latestPreviewPixelBuffer = pb
        lensNow = dev.lensPosition
        lock.unlock()

        if !hasLiDAR {
            let focusM = focusDistance(forLensPosition: dev.lensPosition)
            let now = CACurrentMediaTime()
            if now - lastDepthPublish > 0.15 {
                lastDepthPublish = now
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if focusM.isFinite && focusM > 0.1 {
                        if let old = self.distance, abs(focusM - old) < max(0.05, 0.03 * old) { return }
                        self.distance = focusM
                    }
                }
            }
        }

        let e = frameExposure(sampleBuffer, dev)
        guard e.t > 0, e.iso > 0, e.n > 0 else { return }
        let evCam = log2(e.n * e.n / e.t) - log2(e.iso / 100.0)

        lock.lock()
        let m = mode
        let sp = spot
        let rad = spotRadius
        lock.unlock()

        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return }
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        let bpr = CVPixelBufferGetBytesPerRow(pb)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        let lut = CameraMeter.lut

        func lum(_ x: Int, _ y: Int) -> Double {
            let o = y * bpr + x * 4
            let b = lut[Int(ptr[o])]
            let g = lut[Int(ptr[o + 1])]
            let r = lut[Int(ptr[o + 2])]
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }

        func matrixSample(needPoints: Bool) -> (y: Double, ys: [Double]) {
            let grid = CameraMeter.matrixGrid
            var ys: [Double] = []
            if needPoints { ys.reserveCapacity(grid.count) }
            var sum = 0.0
            let dw = Double(w)
            let dh = Double(h)
            for pt in grid {
                let px = min(max(Int(pt.fx * dw), 0), w - 1)
                let py = min(max(Int(pt.fy * dh), 0), h - 1)
                let y = lum(px, py)
                if needPoints { ys.append(y) }
                sum += pt.weight * y
            }
            return (sum / CameraMeter.matrixWeightTotal, ys)
        }

        let yRaw: Double
        var deltaNow: Double?

        switch m {
        case .spot:
            let cx = Double(sp.x) * Double(w)
            let cy = Double(sp.y) * Double(h)
            let r = Double(rad) * Double(w)
            let steps = 13
            var sum = 0.0
            var count = 0.0
            for j in 0..<steps {
                for i in 0..<steps {
                    let u = (Double(i) + 0.5) / Double(steps) * 2 - 1
                    let v = (Double(j) + 0.5) / Double(steps) * 2 - 1
                    if u * u + v * v > 1 { continue }
                    let x = min(max(Int(cx + u * r), 0), w - 1)
                    let y = min(max(Int(cy + v * r), 0), h - 1)
                    sum += lum(x, y)
                    count += 1
                }
            }
            yRaw = count > 0 ? sum / count : 0.18
            deltaNow = log2(max(yRaw, 0.0005) / max(matrixSample(needPoints: false).y, 0.0005))

        case .matrix:
            yRaw = matrixSample(needPoints: false).y

        case .highlight:
            let sample = matrixSample(needPoints: true)
            var ys = sample.ys
            let yMatrix = sample.y
            ys.sort()
            let p98 = ys[Int(Double(ys.count - 1) * 0.98)]
            yRaw = max(yMatrix, p98 / pow(2.0, highlightStops))
        }

        let yRef = max(yRaw, 0.0005)
        let ev = evCam + log2(yRef / 0.18)
        steerExposure(refY: yRef)

        lock.lock()
        if let s = smoothed, abs(ev - s) < 1.0 {
            smoothed = s + 0.3 * (ev - s)
        } else {
            smoothed = ev
        }
        let out = CameraMeter.settled(smoothed ?? ev, &steadyEV)
        var deltaOut: Double?
        if let d = deltaNow {
            if let s = deltaSmoothed {
                deltaSmoothed = s + 0.3 * (d - s)
            } else {
                deltaSmoothed = d
            }
            deltaOut = CameraMeter.settled(deltaSmoothed ?? d, &steadyDelta)
        } else {
            deltaSmoothed = nil
            steadyDelta = nil
        }
        lock.unlock()
        let delta = deltaOut

        let now = CACurrentMediaTime()
        if now - lastPublish > 0.016 {
            lastPublish = now
            DispatchQueue.main.async { [weak self] in
                self?.sceneEV = out
                self?.spotDelta = delta
            }
        }
    }
}

final class PeakingFeed: ObservableObject {
    @Published var image: UIImage?
}
