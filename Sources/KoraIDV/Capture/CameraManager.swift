import AVFoundation
import UIKit

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

    /// When true, captured photos are additionally cropped to a centered
    /// ID-1 aspect (1.586:1) horizontal card after orientation normalization.
    /// Set by `DocumentCaptureView` before triggering capture so the review
    /// screen sees the document filling the frame rather than a tiny card
    /// inside a 1080×1920 portrait expanse of background. Selfie/liveness
    /// flows leave this `false` so the full portrait selfie isn't cropped
    /// down to a horizontal slice. Mirrors Android's
    /// `DocumentScanner.cropToDocument` which serves the same purpose on
    /// `Bitmap` outputs from CameraX. v1.9.0-rc5.
    var documentMode: Bool = false

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

        // Set session preset
        if captureSession.canSetSessionPreset(.high) {
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
        let aspectCropped = cropToVideoAspect(portraitData) ?? portraitData

        // **v1.9.0-rc5 — Step 3 (document captures only).** When
        // `documentMode` is set (by DocumentCaptureView before triggering
        // capture), additionally crop to a centered ID-1 aspect
        // (1.586:1) horizontal card. Without this, Stratum Remit 2026-06-06
        // rc4 review screen still showed the DL as a small card in the
        // middle of a 1080×1920 portrait frame (~70% wood-grain background)
        // — even though orientation was correct, the captured photo just
        // included too much of what the camera saw. Server confirmed
        // `document_completeness: 60/100` and rejected for "Document
        // quality too low." Mirrors Android's `cropToDocument` choice
        // (`koraidv-android/.../DocumentScanner.kt:260`) of a centered
        // aspect crop over a tight-to-bbox crop — Android explicitly
        // rejected the latter because "analysis stream and capture stream
        // can arrive in different orientations." iOS doesn't have that
        // exact issue post-normalizeToPortrait, but the centered approach
        // is simpler, doesn't depend on plumbing DocumentScanner's bbox
        // through to here, and handles the common case (user centers the
        // doc in the viewfinder).
        let finalData: Data
        if documentMode {
            finalData = cropToDocument(aspectCropped) ?? aspectCropped
        } else {
            finalData = aspectCropped
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

    /// Crop a captured photo to a centered ID-1 aspect (1.586:1)
    /// horizontal card region, sized to ~95% of the shorter dimension.
    ///
    /// Mirrors Android's `DocumentScanner.cropToDocument` strategy:
    /// the viewfinder already funnels the user toward a centered,
    /// horizontally-oriented ID-1 document, so a centered aspect crop
    /// at the standard ID card ratio reliably frames the card without
    /// needing to plumb the live-detection bbox through to the photo
    /// capture path. Android chose this over a tight-to-bbox crop
    /// because their analysis stream and capture stream can arrive in
    /// different orientations on CameraX — iOS doesn't have that exact
    /// hazard after `normalizeToPortrait` runs, but the centered
    /// approach is simpler, more robust to detection noise, and
    /// matches Android's behavior for cross-platform parity.
    ///
    /// Returns nil if the JPEG can't be decoded; caller falls back to
    /// the input data.
    ///
    /// v1.9.0-rc5.
    private func cropToDocument(_ data: Data) -> Data? {
        guard let originalImage = UIImage(data: data) else { return nil }

        let imageSize = originalImage.size
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }

        // Standard ID-1 ratio (driver's licenses, national ID cards,
        // passport biopage, credit cards). 85.60mm × 53.98mm = 1.586.
        let targetAspect: CGFloat = 1.586

        // Size the crop to ~95% of the dominant dimension. For a
        // portrait-oriented input (the post-normalizeToPortrait case):
        // width is the shorter edge → targetWidth = width * 0.95,
        // targetHeight = targetWidth / aspect. For a landscape input
        // (unlikely after normalizeToPortrait, kept for robustness):
        // height is the shorter edge → targetHeight = height * 0.95,
        // targetWidth = targetHeight * aspect.
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

        let cropOrigin = CGPoint(
            x: (imageSize.width - cropSize.width) / 2,
            y: (imageSize.height - cropSize.height) / 2
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = originalImage.scale
        let renderer = UIGraphicsImageRenderer(size: cropSize, format: format)
        let cropped = renderer.image { _ in
            originalImage.draw(at: CGPoint(x: -cropOrigin.x, y: -cropOrigin.y))
        }

        return cropped.jpegData(compressionQuality: 0.92)
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
