import AVFoundation
import UIKit
import Vision

/// Camera position
public enum CameraPosition {
    case front
    case back
}

/// Camera Manager delegate
protocol CameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: CameraManager, didCapturePhoto imageData: Data)
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer)
    func cameraManager(_ manager: CameraManager, didFail error: KoraError)
}

/// Camera Manager for capturing photos and video frames
final class CameraManager: NSObject {

    // MARK: - Properties

    weak var delegate: CameraManagerDelegate?

    /// AVCaptureSession backing all preview + capture.
    ///
    /// Visibility relaxed from `private` to internal (module-default) in v1.8.6
    /// so `CameraPreviewUIView` (defined below) can attach it directly to a
    /// `UIView` whose `layerClass` is `AVCaptureVideoPreviewLayer`. This is the
    /// canonical SwiftUI+AVFoundation preview pattern; the previous flow
    /// (`createPreviewLayer(for:)` + `view.layer.addSublayer`) wrote
    /// `layer.frame = view.bounds` at a moment when `bounds` was still `.zero`,
    /// leaving every preview at zero-size and invisible to the user. See
    /// `CameraPreviewUIView` documentation at the bottom of this file.
    let captureSession = AVCaptureSession()
    private var photoOutput: AVCapturePhotoOutput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var currentDevice: AVCaptureDevice?
    private var currentPosition: CameraPosition = .back

    /// When true, captured photos are additionally cropped to the
    /// detected document bounding box after orientation normalization.
    /// Set by `DocumentCaptureView` before triggering capture; selfie/
    /// liveness flows leave this `false` so the full portrait selfie
    /// isn't cropped down to a card region. v1.9.0-rc5 (centered
    /// fallback) / v1.9.0-rc6.1 (bbox-based when `documentBbox` is
    /// also set).
    var documentMode: Bool = false

    /// **v1.9.0-rc6.1** — bounding box of the detected document in
    /// 0–1 normalized coordinates, snapshotted by DocumentCaptureView
    /// at capture trigger time from `DocumentScanner.lastBoundsFractional()`.
    /// When non-nil AND `documentMode` is true, the captured photo is
    /// cropped to this region (plus padding) instead of falling back to
    /// the centered-geometric heuristic that rc5 used (which clipped
    /// the DL face region and broke face/name matching).
    ///
    /// Cleared by the caller after consuming, or left set across
    /// retakes if the next detection has produced a new bbox.
    var documentBbox: CGRect?

    /// When true (set for the BACK side), the captured photo is cropped to the
    /// card's detected RECTANGLE rather than the content bbox. The back's
    /// text+barcode only covers the upper-middle of the card, so a content
    /// crop is too small and a centered crop leaves tablecloth margins;
    /// detecting the card's actual edges gives a tight, full-card crop that
    /// fills the review like the text-dense front. Falls back to documentBbox
    /// / centered crop when no card rectangle is found. See `cropToDocument`.
    var useCardRectCrop = false

    private let sessionQueue = DispatchQueue(label: "com.koraidv.camera.session")
    private let videoOutputQueue = DispatchQueue(label: "com.koraidv.camera.video")

    private var isConfigured = false

    deinit {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    /// Preview layer for displaying camera feed
    var previewLayer: AVCaptureVideoPreviewLayer?

    /// Whether the camera is running
    var isRunning: Bool {
        captureSession.isRunning
    }

    // MARK: - Public Methods

    /// Request camera permission
    func requestPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        default:
            completion(false)
        }
    }

    /// Configure the camera
    func configure(position: CameraPosition, completion: @escaping (Result<Void, KoraError>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                try self.setupSession(position: position)
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch let error as KoraError {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.cameraNotAvailable))
                }
            }
        }
    }

    /// Start the camera session
    func start() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
        }
    }

    /// Stop the camera session
    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }

    /// Switch camera position
    func switchCamera(completion: @escaping (Result<Void, KoraError>) -> Void) {
        let newPosition: CameraPosition = currentPosition == .back ? .front : .back
        configure(position: newPosition, completion: completion)
    }

    /// Capture a photo
    func capturePhoto() {
        guard let photoOutput = photoOutput else {
            delegate?.cameraManager(self, didFail: .captureFailed("Photo output not available"))
            return
        }

        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off

        if let connection = photoOutput.connection(with: .video) {
            connection.videoOrientation = .portrait

            // Mirror for front camera
            if currentPosition == .front {
                connection.isVideoMirrored = true
            }
        }

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    /// Create preview layer
    func createPreviewLayer(for view: UIView) -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        previewLayer = layer
        return layer
    }

    /// Set focus point
    func focus(at point: CGPoint) {
        guard let device = currentDevice, device.isFocusPointOfInterestSupported else { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            device.focusPointOfInterest = point
            device.focusMode = .autoFocus

            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
        } catch {
            KoraIDV.log("Focus configuration failed: \(error)")
        }
    }

    /// Set zoom level
    func setZoom(_ factor: CGFloat) {
        guard let device = currentDevice else { return }

        let clampedFactor = max(1.0, min(factor, device.activeFormat.videoMaxZoomFactor))

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            device.videoZoomFactor = clampedFactor
        } catch {
            KoraIDV.log("Zoom configuration failed: \(error)")
        }
    }

    // MARK: - Private Methods

    private func setupSession(position: CameraPosition) throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        // Remove existing inputs/outputs
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }

        // Set session preset. Document capture uses `.photo` for full-resolution
        // 4:3 stills; the selfie/liveness camera stays on `.high` (16:9).
        //
        // **Back-DL barcode decode fix (BanffPay, 2026-06-20).** A 1.586:1 ID
        // card has far higher pixel density at 4:3 than 16:9, and a PDF417 on a
        // DL back needs ~3000px across the card to decode. The `.high` path
        // (1920×1080) produced a ~730px card crop that no decoder could read —
        // while the web SDK (full-res 3072×4080) and Android
        // (CAPTURE_MODE_MAXIMIZE_QUALITY + 4:3 ResolutionSelector,
        // CameraManager.kt:118) both decode cleanly. `.photo` makes iOS match.
        // Scoped to `documentMode` so the device-fragile liveness/selfie
        // pipeline (calibrated to `.high` 16:9) is unaffected.
        let preferredPreset: AVCaptureSession.Preset = documentMode ? .photo : .high
        if captureSession.canSetSessionPreset(preferredPreset) {
            captureSession.sessionPreset = preferredPreset
        } else if captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
        }

        // Add video input
        let devicePosition: AVCaptureDevice.Position = position == .front ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: devicePosition) else {
            throw KoraError.cameraNotAvailable
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else {
            throw KoraError.cameraNotAvailable
        }
        captureSession.addInput(input)
        currentDevice = device
        currentPosition = position

        // Add photo output
        let photo = AVCapturePhotoOutput()
        guard captureSession.canAddOutput(photo) else {
            throw KoraError.cameraNotAvailable
        }
        captureSession.addOutput(photo)
        photoOutput = photo

        // Add video output for frame analysis
        let video = AVCaptureVideoDataOutput()
        video.setSampleBufferDelegate(self, queue: videoOutputQueue)
        video.alwaysDiscardsLateVideoFrames = true
        video.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        guard captureSession.canAddOutput(video) else {
            throw KoraError.cameraNotAvailable
        }
        captureSession.addOutput(video)
        videoOutput = video

        // Configure video connection
        if let connection = video.connection(with: .video) {
            connection.videoOrientation = .portrait
            if position == .front && connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }

        isConfigured = true
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraManager: AVCapturePhotoCaptureDelegate {

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error = error {
            delegate?.cameraManager(self, didFail: .captureFailed(error.localizedDescription))
            return
        }

        guard let imageData = photo.fileDataRepresentation() else {
            delegate?.cameraManager(self, didFail: .captureFailed("Failed to get image data"))
            return
        }

        // **v1.9.0-rc4 — photo orientation normalization (Step 1).**
        // Stratum Remit's 2026-06-06 device test confirmed AVFoundation
        // delivers landscape-sensor-native JPEGs (1920x1080 with no EXIF
        // rotation tag) on iPhone 13 Pro even though we set
        // `connection.videoOrientation = .portrait` on `capturePhoto()`.
        // Result on the server: document_front.jpg, document_back.jpg
        // and selfie.jpg all 1920x1080 landscape with documents/faces
        // lying on their side — `document_completeness: 30/100`,
        // `face_match: 0`, `liveness: 0`, auto-reject. Meanwhile the
        // video output's portrait rotation works fine (liveness frames
        // were correctly 1080x1920) — so the bug is specific to the
        // still-photo path.
        //
        // Workaround: normalize the captured photo to upright portrait
        // *before* the aspect-crop step. Two cases to handle:
        // (a) AVFoundation set EXIF orientation but the buffer is still
        //     sensor-native — UIImage decodes it correctly but downstream
        //     ML services that don't read EXIF see it sideways
        // (b) AVFoundation set neither rotation nor EXIF (what we
        //     observed on iPhone 13 Pro) — image is landscape, nothing
        //     downstream knows to rotate
        // Single redraw at .up handles both.
        let portraitData = normalizeToPortrait(imageData) ?? imageData

        // Step 2 (existing v1.8.6-rc3): crop to 9:16 portrait aspect so
        // the captured photo matches what the user saw in the viewfinder.
        // Now that the input is reliably upright (Step 1), the existing
        // crop logic produces the expected vertical-strip result.
        // Step 3 — crop to the document (documents) or the viewfinder aspect
        // (selfie).
        let finalData: Data
        if documentMode {
            // **Full-res document crop (BanffPay back-DL fix, 2026-06-20).** Do
            // NOT 9:16-crop first: under `.photo` the still is full-resolution
            // 4:3, and a 9:16 crop would trim the card's left/right edges —
            // clipping the very PDF417 we need to decode. Crop straight to the
            // detected card on the full-res still (`cropToDocument` →
            // `detectCardRect` for the back, `documentBbox` for the front), which
            // preserves the ~3000px-across pixel density the barcode decode needs.
            // `cropToDocument` still centers/fills the card so the review screen
            // shows it large (the original reason Step 3 existed).
            finalData = cropToDocument(portraitData) ?? portraitData
        } else {
            // Selfie: crop to the 9:16 viewfinder aspect.
            finalData = cropToVideoAspect(portraitData) ?? portraitData
        }
        delegate?.cameraManager(self, didCapturePhoto: finalData)
    }

    /// Normalize a captured photo's JPEG data to upright portrait,
    /// flattening any EXIF orientation tag into the actual pixel layout.
    ///
    /// `AVCapturePhotoOutput` on iPhone 13 Pro (iOS 26.4) was observed
    /// to return 1920×1080 sensor-native landscape JPEGs with no EXIF
    /// orientation tag, even with `connection.videoOrientation = .portrait`
    /// set on the photo connection just before capture. This breaks every
    /// downstream consumer that assumes upright pixels — face detection,
    /// OCR, document-quality scoring, PDF417 decode.
    ///
    /// The fix is platform-defensive: re-render the UIImage at its
    /// display-coordinate `.up` orientation, then explicitly rotate if
    /// the bytes are still landscape afterward. Returns nil only if the
    /// JPEG can't be decoded; caller falls back to original data.
    ///
    /// - Parameter data: JPEG/HEIF data from `AVCapturePhoto.fileDataRepresentation()`.
    /// - Returns: JPEG data with pixels in upright portrait orientation,
    ///   or nil if decode failed.
    private func normalizeToPortrait(_ data: Data) -> Data? {
        guard let original = UIImage(data: data) else { return nil }

        // Step A: flatten EXIF orientation. If the source image has any
        // non-`.up` `imageOrientation`, draw it into a fresh context so
        // the output bytes match the displayed pixels (and any consumer
        // that ignores EXIF — most ML services do — sees the upright
        // result). No-op when `imageOrientation == .up`, but cheap to
        // run unconditionally for clarity.
        let flattened: UIImage
        if original.imageOrientation == .up {
            flattened = original
        } else {
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = original.scale
            let renderer = UIGraphicsImageRenderer(size: original.size, format: format)
            flattened = renderer.image { _ in
                original.draw(in: CGRect(origin: .zero, size: original.size))
            }
        }

        // Step B: if the flattened result is landscape (sensor-native
        // without EXIF rotation), rotate to portrait. Back-facing
        // camera in portrait device orientation: rotate 90° clockwise
        // (UIImage.Orientation.right). Front camera: rotate 90°
        // counter-clockwise (UIImage.Orientation.left) — the camera
        // input already has `isVideoMirrored = true` for front capture
        // (see capturePhoto), so the resulting pixels mirror correctly
        // after rotation.
        if flattened.size.width <= flattened.size.height {
            // Already portrait (or square) — done.
            return flattened.jpegData(compressionQuality: 0.92)
        }
        guard let cgImage = flattened.cgImage else {
            // Drawing-based rotation requires cgImage; fall back to
            // the flattened landscape JPEG so caller still gets *some*
            // data rather than nil.
            return flattened.jpegData(compressionQuality: 0.92)
        }
        let rotationOrientation: UIImage.Orientation = currentPosition == .front ? .left : .right
        let rotated = UIImage(cgImage: cgImage, scale: flattened.scale, orientation: rotationOrientation)

        // Re-flatten the rotated image so the JPEG bytes have the
        // rotation baked in (not just an EXIF tag). Downstream ML
        // services that read pixel buffers directly will see upright
        // portrait.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = rotated.scale
        let renderer = UIGraphicsImageRenderer(size: rotated.size, format: format)
        let upright = renderer.image { _ in
            rotated.draw(in: CGRect(origin: .zero, size: rotated.size))
        }
        return upright.jpegData(compressionQuality: 0.92)
    }

    /// Crops the captured photo to match the video preview's aspect ratio
    /// (9:16 portrait under sessionPreset.high). Uses `UIGraphicsImageRenderer`
    /// to handle orientation correctly — `UIImage.draw(at:)` respects the
    /// image's `imageOrientation`, so the rendered output is always in
    /// display orientation regardless of how the underlying CGImage was
    /// stored. Returns nil if the data can't be decoded; caller falls
    /// back to the original uncropped data in that case.
    private func cropToVideoAspect(_ data: Data) -> Data? {
        guard let originalImage = UIImage(data: data) else { return nil }

        // Display-oriented size (post-EXIF rotation).
        let imageSize = originalImage.size
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }

        // Target aspect = 9:16 portrait (matches AVCaptureSession.Preset.high
        // video frames after .portrait orientation rotation: 1920x1080
        // landscape → 1080x1920 portrait). Keep in sync with sessionPreset
        // if that is ever changed in setupSession.
        let targetAspect: CGFloat = 9.0 / 16.0  // width / height
        let imageAspect = imageSize.width / imageSize.height

        // Already-matching aspect — no-op (saves a re-encode round trip).
        if abs(imageAspect - targetAspect) < 0.001 {
            return data
        }

        // Compute center-cropped target rect.
        let cropSize: CGSize
        if imageAspect > targetAspect {
            // Image is wider than target — trim width.
            cropSize = CGSize(width: imageSize.height * targetAspect, height: imageSize.height)
        } else {
            // Image is taller than target — trim height.
            cropSize = CGSize(width: imageSize.width, height: imageSize.width / targetAspect)
        }
        let cropOrigin = CGPoint(
            x: (imageSize.width - cropSize.width) / 2,
            y: (imageSize.height - cropSize.height) / 2
        )

        // Render the cropped region. UIGraphicsImageRenderer respects the
        // source image's orientation, so `draw(at:)` blits in display
        // coordinates and the output is always upright.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = originalImage.scale
        let renderer = UIGraphicsImageRenderer(size: cropSize, format: format)
        let cropped = renderer.image { _ in
            originalImage.draw(at: CGPoint(x: -cropOrigin.x, y: -cropOrigin.y))
        }

        return cropped.jpegData(compressionQuality: 0.9)
    }

    /// Crop a captured photo to the detected document region.
    ///
    /// **v1.9.0-rc6.1** — bbox-based implementation. When `documentBbox`
    /// is set (normalized 0–1 coordinates from
    /// `DocumentScanner.lastBoundsFractional()`), scales to absolute
    /// pixel coords on the input photo, adds a 5% padding around each
    /// edge, and crops. This is the permanent fix for the chronic
    /// "DL too small in review screen" issue:
    ///
    /// - rc4 (no crop): DL was small in the 1080×1920 portrait frame
    /// - rc5 (centered ID-1 crop): clipped the DL because users place
    ///   documents where the viewfinder guides them (upper portion of
    ///   the screen), not at the geometric center of the photo
    /// - rc5.1 (revert): back to rc4's "small but whole"
    /// - rc6.1 (bbox-based): use the DETECTOR's known document location
    ///   — what should have been done in rc5
    ///
    /// Padding is asymmetric — 5% per side gives the photo room
    /// around the card so backend ML services that re-detect the
    /// document (face quality scoring, PDF417 decode) have margin
    /// to work with rather than a perfectly-tight crop that might
    /// touch the card edges and cause edge artifacts.
    ///
    /// Falls back to a centered ID-1 crop (the rc5 behavior) when
    /// `documentBbox` is nil — only happens if the SDK captured a
    /// frame before any detection succeeded, which shouldn't occur
    /// in normal flow but is defensive.
    ///
    /// Returns nil if the JPEG can't be decoded; caller falls back
    /// to the input data.
    private func cropToDocument(_ data: Data) -> Data? {
        guard let originalImage = UIImage(data: data) else { return nil }

        let imageSize = originalImage.size
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }

        var cropRect: CGRect
        if useCardRectCrop, let cardRect = detectCardRect(in: originalImage) {
            // **Card-rectangle path (back side, 2026-06-16).** `cardRect` is
            // normalized 0–1, top-left origin — the detected card outline.
            // Add a small 3% margin and scale to pixels for a tight, full-card
            // crop that fills the review like the front.
            let pad: CGFloat = 0.03
            let px = max(0, cardRect.minX - cardRect.width * pad)
            let py = max(0, cardRect.minY - cardRect.height * pad)
            let pw = min(1 - px, cardRect.width * (1 + 2 * pad))
            let ph = min(1 - py, cardRect.height * (1 + 2 * pad))
            cropRect = CGRect(
                x: px * imageSize.width,
                y: py * imageSize.height,
                width: pw * imageSize.width,
                height: ph * imageSize.height
            )
        } else if let bbox = documentBbox {
            // **rc6.1 bbox path.** Scale the 0–1 normalized bbox to
            // absolute pixel coordinates on the captured photo, then
            // add a 5% padding around each edge.
            let pad: CGFloat = 0.05
            let xPad = bbox.width * pad
            let yPad = bbox.height * pad
            let padded = CGRect(
                x: max(0, bbox.minX - xPad),
                y: max(0, bbox.minY - yPad),
                width: min(1 - max(0, bbox.minX - xPad), bbox.width + 2 * xPad),
                height: min(1 - max(0, bbox.minY - yPad), bbox.height + 2 * yPad)
            )
            cropRect = CGRect(
                x: padded.minX * imageSize.width,
                y: padded.minY * imageSize.height,
                width: padded.width * imageSize.width,
                height: padded.height * imageSize.height
            )
        } else {
            // Fallback: centered ID-1 aspect crop (rc5 behavior).
            // Only used when no detection bbox is available.
            let targetAspect: CGFloat = 1.586
            let isPortrait = imageSize.height >= imageSize.width
            let cropSize: CGSize
            if isPortrait {
                let targetW = imageSize.width * 0.95
                let targetH = min(targetW / targetAspect, imageSize.height)
                cropSize = CGSize(width: targetW, height: targetH)
            } else {
                let targetH = imageSize.height * 0.95
                let targetW = min(targetH * targetAspect, imageSize.width)
                cropSize = CGSize(width: targetW, height: targetH)
            }
            cropRect = CGRect(
                x: (imageSize.width - cropSize.width) / 2,
                y: (imageSize.height - cropSize.height) / 2,
                width: cropSize.width,
                height: cropSize.height
            )
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = originalImage.scale
        let renderer = UIGraphicsImageRenderer(size: cropRect.size, format: format)
        let cropped = renderer.image { _ in
            originalImage.draw(at: CGPoint(x: -cropRect.minX, y: -cropRect.minY))
        }

        return cropped.jpegData(compressionQuality: 0.92)
    }

    /// Detect the ID card's rectangle in the captured photo and return its
    /// bounding box in normalized 0–1 coordinates (top-left origin), or nil if
    /// no card-like rectangle is found. One-shot on the captured still (not
    /// per-frame), so live-detection cost is avoided. Used for the BACK crop
    /// where the text+barcode content bbox doesn't span the whole card.
    private func detectCardRect(in image: UIImage) -> CGRect? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNDetectRectanglesRequest()
        // ID-1 card is 1.586:1 → short/long ratio ≈ 0.63; allow a band around
        // it. minimumSize keeps us off small background rectangles.
        request.minimumAspectRatio = 0.5
        request.maximumAspectRatio = 0.85
        request.minimumSize = 0.3
        request.minimumConfidence = 0.6
        request.maximumObservations = 8
        request.quadratureTolerance = 25
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        // Largest detected rectangle = the card (it dominates the frame).
        guard let best = request.results?.max(by: {
            ($0.boundingBox.width * $0.boundingBox.height) <
            ($1.boundingBox.width * $1.boundingBox.height)
        }) else { return nil }
        let bb = best.boundingBox  // Vision: normalized, origin BOTTOM-LEFT.
        return CGRect(x: bb.minX, y: 1 - bb.minY - bb.height, width: bb.width, height: bb.height)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        delegate?.cameraManager(self, didOutput: sampleBuffer)
    }
}

// MARK: - Camera Preview UIView

/// `UIView` subclass whose root layer IS an `AVCaptureVideoPreviewLayer`.
///
/// Use via the SwiftUI `UIViewRepresentable` pattern (see `CameraPreviewView`
/// in `DocumentCaptureView.swift` and `LivenessCameraPreviewView` in
/// `LivenessView.swift`).
///
/// Why this exists: prior to v1.8.6, every camera preview in the SDK was built
/// by creating a `UIView(frame: .zero)`, calling `cameraManager.createPreviewLayer(for: view)`,
/// and adding the returned `AVCaptureVideoPreviewLayer` as a sublayer. The
/// preview layer's `frame` was set to `view.bounds` at the moment of creation
/// — but at that moment `bounds` was still `.zero`, because SwiftUI hadn't
/// resolved the parent geometry yet. The only place that re-set the layer
/// frame was `UIViewRepresentable.updateUIView`, which fires on data-binding
/// changes, not on the initial bounds resolution. Net result: the preview
/// layer stayed at zero size forever and the user never saw a camera feed,
/// even though the capture session was healthy underneath and captured photos
/// landed correctly.
///
/// The fix is the canonical SwiftUI+AVFoundation pattern: make the root layer
/// of a `UIView` BE the `AVCaptureVideoPreviewLayer` by overriding
/// `layerClass`. UIKit's normal layout system then resizes it automatically
/// whenever the view's bounds change — no manual frame management needed and
/// no `updateUIView` work to maintain layout.
///
/// Surfaced by Stratum Remit team on 2026-06-01 (iPhone 12 + iPhone 15 Pro
/// Max both reproduced); fix lands in v1.8.6.
final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
