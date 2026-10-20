import AVFoundation
import Combine
import ImageIO
import QuartzCore

/// Runs the back camera and turns each frame into a scene EV (ISO 100).
/// On LiDAR phones it also reads distance at the metered point.
///
/// Per frame: EV of the exposure the frame was actually shot at
/// + log2(measured luminance / reference). A slow servo on the camera's exposure bias
/// (`steerExposure`) holds the metered reference near mid-grey, so the preview shows
/// the metered exposure and Apple's tone curve matters least.
final class CameraMeter: NSObject, ObservableObject,
    AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureDepthDataOutputDelegate {

    let session = AVCaptureSession()

    @Published private(set) var sceneEV: Double = 12
    /// Metres, nil when there is no valid LiDAR reading.
    @Published private(set) var distance: Double?
    @Published private(set) var hasLiDAR = false
    @Published private(set) var denied = false

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
    private var smoothed: Double?
    private var distSmoothed: Double?
    private var lastPublish: CFTimeInterval = 0
    private var lastDepthPublish: CFTimeInterval = 0

    /// Highlight mode: the bright end of the scene (98th percentile) is not allowed to
    /// land more than this many stops above middle grey.
    private let highlightStops = 1.5

    /// Exposure-bias servo state. Only touched from the frame queue. See `steerExposure`.
    private var currentBias: Float = 0
    private var lastBiasUpdate: CFTimeInterval = 0

    /// sRGB decoding curve. We request the sRGB colour space, so this is the right inverse.
    private static let lut: [Double] = (0..<256).map { i in
        let v = Double(i) / 255.0
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    func setConfig(mode: MeterMode, spot: CGPoint, radius: CGFloat) {
        lock.lock()
        self.mode = mode
        self.spot = spot
        self.spotRadius = radius
        self.smoothed = nil
        self.distSmoothed = nil
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

    // MARK: - Session setup

    private func configureAndRun() {
        if !configured {
            // LiDAR camera first, plain wide camera as the fallback.
            configured = buildSession(lidar: true) || buildSession(lidar: false)
            if configured, let dev = device { tune(dev) }
        }
        if configured {
            currentBias = 0
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

        // Don't let the session switch the camera to wide colour behind our back.
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

        if let conn = output.connection(with: .video), conn.isVideoRotationAngleSupported(90) {
            conn.videoRotationAngle = 90
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
        DispatchQueue.main.async { self.hasLiDAR = lidar }
        return true
    }

    /// Turn off the processing that would bend the readings: HDR tone mapping, low-light boost, wide gamut.
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

    /// Slow servo on the camera's exposure bias: nudge it until the metered reference
    /// (matrix average, the spot, or the protected highlight) sits at middle grey in the preview.
    ///
    /// Two reasons:
    /// 1. The preview becomes the picture the film would get. Tap a bright spot and the whole view
    ///    darkens by the same number of stops the shutter speed moves. Highlight mode darkens by exactly
    ///    the protection it applies. Picture and reading can't disagree.
    /// 2. The pixels that define the reading always sit near mid-grey, where Apple's tone curve
    ///    does the least damage. Errors in the curve cancel out.
    private func steerExposure(refY: Double) {
        let now = CACurrentMediaTime()
        guard now - lastBiasUpdate > 0.2 else { return }
        lastBiasUpdate = now

        let err = log2(refY / 0.18)           // stops above mid-grey
        guard abs(err) > 0.1 else { return }
        // Gain kept low on purpose: the camera takes a few frames to act on a bias change, and a
        // higher gain makes the preview breathe. The reading itself doesn't wait for this to settle.
        let next = min(max(currentBias - Float(err) * 0.15, -6), 6)
        guard abs(next - currentBias) > 0.02 else { return }
        currentBias = next
        setBias(next)
    }

    // MARK: - Depth (LiDAR)

    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        lock.lock()
        let m = mode
        let sp = spot
        let rad = spotRadius
        lock.unlock()

        // Same point the exposure is read from: the spot, otherwise the frame centre.
        let pt = (m == .spot) ? sp : CGPoint(x: 0.5, y: 0.5)
        let r = (m == .spot) ? Double(rad) : 0.03

        let converted = depthData.depthDataType == kCVPixelFormatType_DepthFloat32
            ? depthData
            : depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let map = converted.depthDataMap

        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return }
        let w = CVPixelBufferGetWidth(map)
        let h = CVPixelBufferGetHeight(map)
        let bpr = CVPixelBufferGetBytesPerRow(map)

        // The depth map is in sensor (landscape) orientation. Portrait (px, py) -> sensor (py, 1 - px).
        let sx = Double(pt.y)
        let sy = 1.0 - Double(pt.x)

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
            if let s = distSmoothed, abs(med - s) < 0.3 {
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
            self?.distance = out
        }
    }

    // MARK: - Frame processing (exposure)

    /// Exposure the frame was actually shot at. Reads the frame's own metadata, which stays in step with
    /// the pixels even while auto exposure is moving, and falls back to the device's current values.
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

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let dev = device, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

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

        let yRaw: Double

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

        case .matrix, .highlight:
            let gx = 36
            let gy = 48
            var ys: [Double] = []
            ys.reserveCapacity(gx * gy)
            var sum = 0.0
            var wsum = 0.0
            for j in 0..<gy {
                let fy = (Double(j) + 0.5) / Double(gy)
                for i in 0..<gx {
                    let fx = (Double(i) + 0.5) / Double(gx)
                    let y = lum(Int(fx * Double(w)), Int(fy * Double(h)))
                    let dx = fx - 0.5
                    let dy = fy - 0.5
                    let weight = 0.35 + 0.65 * exp(-(dx * dx + dy * dy) / 0.18)
                    ys.append(y)
                    sum += weight * y
                    wsum += weight
                }
            }
            let yMatrix = sum / wsum

            if m == .matrix {
                yRaw = yMatrix
            } else {
                // Highlight: protect the bright end. It may only ever ask for LESS exposure than matrix.
                // A bright area sitting more than `highlightStops` above grey pulls the reading brighter
                // (faster shutter); a flat scene falls back to matrix instead of over-exposing.
                ys.sort()
                let p98 = ys[Int(Double(ys.count - 1) * 0.98)]
                yRaw = max(yMatrix, p98 / pow(2.0, highlightStops))
            }
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
        let out = smoothed ?? ev
        lock.unlock()

        let now = CACurrentMediaTime()
        if now - lastPublish > 0.05 {
            lastPublish = now
            DispatchQueue.main.async { [weak self] in
                self?.sceneEV = out
            }
        }
    }
}
