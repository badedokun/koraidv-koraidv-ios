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

    private let captureSession = AVCaptureSession()
    private var photoOutput: AVCapturePhotoOutput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var currentDevice: AVCaptureDevice?
    private var currentPosition: CameraPosition = .back

    private let sessionQueue = DispatchQueue(label: "com.koraidv.camera.session")
    private let videoOutputQueue = DispatchQueue(label: "com.koraidv.camera.video")

    private var isConfigured = false

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
            device.focusPointOfInterest = point
            device.focusMode = .autoFocus

            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }

            device.unlockForConfiguration()
        } catch {
            // Focus failed, not critical
        }
    }

    /// Set zoom level
    func setZoom(_ factor: CGFloat) {
        guard let device = currentDevice else { return }

        let clampedFactor = max(1.0, min(factor, device.activeFormat.videoMaxZoomFactor))

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clampedFactor
            device.unlockForConfiguration()
        } catch {
            // Zoom failed, not critical
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

        delegate?.cameraManager(self, didCapturePhoto: imageData)
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
