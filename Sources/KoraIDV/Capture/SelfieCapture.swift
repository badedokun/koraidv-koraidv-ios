import UIKit
import AVFoundation

/// Selfie capture delegate
protocol SelfieCaptureDelegate: AnyObject {
    func selfieCapture(_ capture: SelfieCapture, didDetectFace result: FaceDetectionResult)
    func selfieCapture(_ capture: SelfieCapture, didCapture imageData: Data)
    func selfieCapture(_ capture: SelfieCapture, didUpdateValidation issues: [String])
    func selfieCapture(_ capture: SelfieCapture, didFail error: KoraError)
}

/// Selfie capture manager
final class SelfieCapture: NSObject {

    // MARK: - Properties

    weak var delegate: SelfieCaptureDelegate?

    /// Camera manager - exposed for preview layer access
    let cameraManager = CameraManager()
    private let faceDetector = FaceDetector()
    private let qualityValidator = QualityValidator()
    private let antiSpoofCheck = AntiSpoofCheck()

    private var isCapturing = false
    private var isAutoCaptureEnabled = true
    private var autoCaptureCounter = 0
    // Valid frames required before auto-capture fires. History: 10 was twitchy
    // (snapped before the user could settle, BanffPay v1.9.4); 24 with a
    // reset-to-0 on any bad frame was the opposite — a single flickery
    // lighting/yaw frame wiped all progress, so it rarely reached 24 and testers
    // waited 60s+ with the face in the oval (BanffPay v1.9.6, 2026-06). Now 16
    // frames (~0.5s at 30fps) combined with a *decrement* (not reset) on bad
    // frames below, so transient flicker no longer thrashes the counter.
    private let autoCaptureThreshold = 16 // Number of valid frames before auto-capture

    /// Minimum face size as percentage of frame
    var minimumFaceSizePercentage: CGFloat = 0.2

    /// Maximum face size as percentage of frame
    var maximumFaceSizePercentage: CGFloat = 0.6

    /// Proactive lighting coaching (BanffPay robustness, 2026-06-20).
    ///
    /// Measured on the CENTER region (where the selfie oval guides the face),
    /// NOT the whole frame — a bright window beside the user pulls the
    /// whole-frame average to a "fine" value while the face sits in shadow.
    /// `minFaceBrightness`/`maxFaceBrightness` gate the face's own exposure;
    /// `backlightBlownFraction` catches BACKLIGHT — a large blown-out region
    /// (window) that throws harsh shadows across the face and tanks face-match
    /// even when the average looks fine (the real cause of the faceMatch-58.7
    /// auto-reject on 2026-06-20).
    var minFaceBrightness: Double = 70
    var maxFaceBrightness: Double = 235
    // 0.08 sits in the wide empty gap between evenly-lit selfies (blown ≈ 0.00)
    // and backlit ones (blown ≈ 0.14–0.15, measured on-device 2026-06-20 where
    // faceMatch fell to 50–59 and auto-rejected). Catches backlight with margin
    // without tripping on minor bright spots.
    var backlightBlownFraction: Double = 0.08

    /// Force-capture escape. If a face stays present for this long but the
    /// lighting/position gate never clears, capture anyway so the user is never
    /// stranded (iOS selfie has no manual shutter). Parity with Android's selfie
    /// force-capture; the backend then returns a clear reason if the shot is
    /// genuinely too poor. The coaching runs the whole time first.
    /// v1.9.6 (BanffPay): 12s → 8s → 5s. With the vertically-recentred
    /// acceptance ellipse the fast auto-capture now fires for a normally-held
    /// face, so this is only a last-resort floor; 5s keeps even edge cases from
    /// feeling stuck.
    var selfieForceCaptureDeadline: TimeInterval = 5.0
    private var firstFaceSeenAt: Date?

    /// **Camera settle delay (BanffPay retest #5).** Minimum time between the
    /// camera starting and ANY auto/force capture firing. Without it the selfie
    /// snapped the instant the camera opened with a face already in frame — the
    /// "takes the pic as soon as the oval appears" report — giving the user no
    /// time to position. Mirrors the document path's `cameraSettleDelay`.
    private let selfieSettleDelay: TimeInterval = 1.2
    /// Set when the camera session starts (and re-armed on retake); used by the
    /// settle-delay gate in `handleFaceDetection`.
    private var cameraStartedAt: Date?

    /// Auto-capture enabled
    var autoCaptureEnabled: Bool {
        get { isAutoCaptureEnabled }
        set { isAutoCaptureEnabled = newValue }
    }

    // MARK: - Initialization

    override init() {
        super.init()
        cameraManager.delegate = self
    }

    // MARK: - Public Methods

    /// Request camera permission
    func requestPermission(completion: @escaping (Bool) -> Void) {
        cameraManager.requestPermission(completion: completion)
    }

    /// Start selfie capture
    func start(completion: @escaping (Result<Void, KoraError>) -> Void) {
        cameraManager.configure(position: .front) { [weak self] result in
            guard let self = self else {
                completion(.failure(.unknown("Selfie capture was released")))
                return
            }
            switch result {
            case .success:
                self.cameraManager.start()
                // retest #5: arm the settle delay so capture can't fire for the
                // first `selfieSettleDelay` seconds after the camera opens.
                self.cameraStartedAt = Date()
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Stop selfie capture
    func stop() {
        cameraManager.stop()
        autoCaptureCounter = 0
        firstFaceSeenAt = nil
    }

    /// Capture selfie manually
    func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        cameraManager.capturePhoto()
    }

    /// Get preview layer
    func createPreviewLayer(for view: UIView) -> AVCaptureVideoPreviewLayer {
        return cameraManager.createPreviewLayer(for: view)
    }

    /// Reset auto-capture counter
    func resetAutoCapture() {
        autoCaptureCounter = 0
    }

    /// Re-arm the capture engine for a retake. Releases the isCapturing
    /// gate that was held through validation/anti-spoof/delegate and
    /// resets the auto-capture counter so frame accumulation starts
    /// fresh. Call after the user taps Retake on the review screen.
    func resetForRetake() {
        isCapturing = false
        autoCaptureCounter = 0
        firstFaceSeenAt = nil
        // Re-arm the settle delay so a retake gets the same positioning
        // headroom as the initial capture instead of firing immediately.
        cameraStartedAt = Date()
    }

    // MARK: - Private Methods

    private func processFrame(_ sampleBuffer: CMSampleBuffer) {
        // Read lighting stats on the capture queue (cheap, before the async
        // face-detect hop) so the gate reflects this exact frame.
        let lighting = SelfieCapture.lightingStats(sampleBuffer)
        faceDetector.detectFaces(in: sampleBuffer) { [weak self] result in
            guard let self = self else { return }

            if let result = result {
                DispatchQueue.main.async {
                    self.delegate?.selfieCapture(self, didDetectFace: result)
                    self.handleFaceDetection(result, lighting: lighting)
                }
            } else {
                DispatchQueue.main.async {
                    self.delegate?.selfieCapture(self, didUpdateValidation: ["No face detected"])
                    self.autoCaptureCounter = 0
                    self.firstFaceSeenAt = nil
                }
            }
        }
    }

    private func handleFaceDetection(_ result: FaceDetectionResult, lighting: (center: Double, blown: Double)) {
        // Start the force-capture clock on the first continuous sighting of a face.
        if firstFaceSeenAt == nil { firstFaceSeenAt = Date() }

        // POSITION + SIZE (+yaw) are *blocking* — we never auto-capture a face
        // outside the oval. These are the only issues the auto-capture gate
        // keys off below.
        let validation = faceDetector.validateForSelfie(result: result)
        let issues = validation.issues

        // Lighting is *advisory* coaching only — NOT a capture blocker.
        // BanffPay v1.9.6 retest: testers in a room with a window behind them
        // hit the backlight check on every frame, so the fast auto-capture
        // never fired and every selfie fell through to the 8s force-capture
        // (the "snaps only after 8–9s" report). A user can't fix their room's
        // lighting, so we coach but still capture once they're positioned; the
        // backend scores the lighting and returns a clear reason if the shot is
        // genuinely too poor.
        var lightingCoaching: [String] = []
        if lighting.center < minFaceBrightness {
            lightingCoaching.append("More light on your face — turn toward the light")
        } else if lighting.center > maxFaceBrightness {
            lightingCoaching.append("Too bright — reduce glare or direct light")
        } else if lighting.blown > backlightBlownFraction {
            lightingCoaching.append("Strong light behind you — turn to face the light")
        }

        // Show position issues first (they lead), then lighting coaching.
        delegate?.selfieCapture(self, didUpdateValidation: issues + lightingCoaching)

        let heldLongEnough = firstFaceSeenAt.map {
            Date().timeIntervalSince($0) >= selfieForceCaptureDeadline
        } ?? false

        // retest #5: the camera must have been open for `selfieSettleDelay`
        // before any capture fires. The counter still accumulates while the
        // face is well-positioned, but the SHUTTER is held until settled, so
        // a face already in frame at camera-open captures at ~1.2s (time to
        // position) instead of instantly.
        let settled = cameraStartedAt.map {
            Date().timeIntervalSince($0) >= selfieSettleDelay
        } ?? false

        // **v1.9.6** — whether the face is inside the oval guide (position+size
        // only, no yaw). The force-capture fallback below requires this so we
        // never force-capture a selfie with the face OUTSIDE the oval — the
        // same outside-oval capture Olabode reported for the selfie step
        // (BanffPay v1.9.5, 2026-06). A persistent lighting issue still rescues
        // via force-capture once the face is positioned; a position failure
        // does not.
        let faceInOval = result.faces.first.map {
            faceDetector.isWithinSelfieOval(face: $0, imageSize: result.imageSize)
        } ?? false

        // **Hold the shutter unless lighting is adequate (BanffPay low-light
        // "machine gun", 2026-06-30).** Firing in poor light produced doomed
        // frames (dim / motion-blurred) that fail quality validation, which
        // resets isCapturing + the auto-counter and immediately re-fires —
        // a rapid capture loop in the dark. Gate BOTH the counter path AND the
        // force-capture on `lightingOK`, so in poor light we surface the
        // "more light on your face" coaching and wait instead of machine-gunning.
        // (Too dark to take a usable selfie is a legitimate stop — fail-closed.)
        let lightingOK = lightingCoaching.isEmpty
        if issues.isEmpty && lightingOK && isAutoCaptureEnabled {
            autoCaptureCounter += 1
            if autoCaptureCounter >= autoCaptureThreshold && settled && !isCapturing {
                capture()
            }
        } else if heldLongEnough && faceInOval && lightingOK && isAutoCaptureEnabled && !isCapturing {
            // Coached for the full deadline and the face IS in the oval, but a
            // non-positional issue never cleared — capture anyway so the user is
            // never stranded. Still gated on lightingOK: a persistent LIGHTING
            // problem must be fixed with light, not force-captured into a loop.
            capture()
        } else {
            // v1.9.6 (BanffPay): decrement instead of resetting to 0 so a
            // single flickery frame (transient lighting/yaw) doesn't wipe all
            // accumulated progress. A *sustained* bad streak still drains the
            // counter quickly (so a genuine move-away won't auto-capture), but a
            // mostly-good scene with occasional flicker now climbs steadily to
            // the threshold instead of thrashing back to zero.
            autoCaptureCounter = max(0, autoCaptureCounter - 2)
        }
    }

    /// Lighting stats for the proactive selfie gate, sub-sampled on a stride for
    /// negligible cost. Returns the mean luma of the CENTER region (the face, per
    /// the oval guide) and the fraction of near-white ("blown") pixels over the
    /// whole frame (a strong-backlight signal). Luma ≈ 0.114·B + 0.587·G +
    /// 0.299·R (32BGRA). Returns neutral values if the buffer can't be read so a
    /// read failure never blocks capture.
    private static func lightingStats(_ sampleBuffer: CMSampleBuffer) -> (center: Double, blown: Double) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return (128, 0) }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return (128, 0) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        // Center box ≈ where the oval guides the face.
        let cx0 = Int(Double(width) * 0.3), cx1 = Int(Double(width) * 0.7)
        let cy0 = Int(Double(height) * 0.3), cy1 = Int(Double(height) * 0.7)

        let step = 16
        var centerSum = 0.0, centerCount = 0
        var total = 0, blown = 0
        var y = 0
        while y < height {
            let row = y * rowBytes
            var x = 0
            while x < width {
                let p = row + x * 4 // BGRA
                let luma = 0.114 * Double(ptr[p]) + 0.587 * Double(ptr[p + 1]) + 0.299 * Double(ptr[p + 2])
                total += 1
                if luma > 235 { blown += 1 }
                if x >= cx0 && x < cx1 && y >= cy0 && y < cy1 {
                    centerSum += luma
                    centerCount += 1
                }
                x += step
            }
            y += step
        }
        let center = centerCount > 0 ? centerSum / Double(centerCount) : 128
        let blownFraction = total > 0 ? Double(blown) / Double(total) : 0
        return (center, blownFraction)
    }
}

// MARK: - CameraManagerDelegate

extension SelfieCapture: CameraManagerDelegate {

    func cameraManager(_ manager: CameraManager, didCapturePhoto imageData: Data) {
        // Keep isCapturing=true through the entire async validation +
        // anti-spoof + compress + delegate.didCapture pipeline. Resetting
        // here would let the sample-buffer path (line ~190) re-enter
        // processFrame → handleFaceDetection → autoCaptureCounter →
        // capture() before the first capture's delegate callback has
        // even fired, causing the multi-shutter "rapid snap" defect
        // BanffPay reported 2026-05-28. Mirrors the gate pattern
        // DocumentCaptureView shipped in v1.6.3 for the same class of
        // bug on the document side. Reset happens via resetForRetake()
        // when the user taps Retake, or via stop() when the flow ends.

        // Validate quality
        guard let image = UIImage(data: imageData) else {
            isCapturing = false
            delegate?.selfieCapture(self, didFail: .captureFailed("Invalid image data"))
            return
        }

        // Get face detection for quality validation
        faceDetector.detectFaces(in: image) { [weak self] result in
            guard let self = self else { return }

            let faceInfo: (confidence: Float, boundingBox: CGRect)?
            if let face = result?.faces.first {
                faceInfo = (face.confidence, face.boundingBox)
            } else {
                faceInfo = nil
            }

            let validation = self.qualityValidator.validateSelfieImage(image, faceDetection: faceInfo)

            if validation.isValid {
                // Run anti-spoof check before accepting
                let spoofResult = self.antiSpoofCheck.analyze(image)
                if !spoofResult.isLikelyReal {
                    DispatchQueue.main.async {
                        self.isCapturing = false
                        self.delegate?.selfieCapture(self, didFail: .qualityValidationFailed(["Image appears to be a photo of a screen or printed image"]))
                        self.resetAutoCapture()
                    }
                    return
                }

                // Compress image. isCapturing remains true — only resetForRetake()
                // or stop() releases the gate so the sample-buffer path can't
                // start a second capture while the ViewModel is on the review
                // screen.
                if let compressedData = image.jpegData(compressionQuality: 0.85) {
                    DispatchQueue.main.async {
                        self.delegate?.selfieCapture(self, didCapture: compressedData)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.delegate?.selfieCapture(self, didCapture: imageData)
                    }
                }
            } else {
                let issues = validation.issues.map { $0.message }
                DispatchQueue.main.async {
                    self.isCapturing = false
                    self.delegate?.selfieCapture(self, didFail: .qualityValidationFailed(issues))
                    self.resetAutoCapture()
                }
            }
        }
    }

    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer) {
        guard !isCapturing else { return }
        processFrame(sampleBuffer)
    }

    func cameraManager(_ manager: CameraManager, didFail error: KoraError) {
        isCapturing = false
        delegate?.selfieCapture(self, didFail: error)
    }
}
